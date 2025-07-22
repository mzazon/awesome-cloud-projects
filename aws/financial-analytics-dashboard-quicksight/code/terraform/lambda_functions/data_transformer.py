"""
Data Transformer Lambda Function

This function transforms raw cost data from Cost Explorer into analytics-ready formats
including JSON for QuickSight and Parquet for Athena queries.

Environment Variables:
- RAW_DATA_BUCKET: S3 bucket containing raw cost data
- PROCESSED_DATA_BUCKET: S3 bucket for storing processed data
- GLUE_DATABASE_NAME: Glue database name for data catalog
- LOG_LEVEL: Logging level (default: INFO)
"""

import json
import boto3
import logging
import os
import pandas as pd
import pyarrow.parquet as pq
import pyarrow as pa
from datetime import datetime
import uuid
import io
from typing import Dict, Any, List, Optional

# Configure logging
log_level = os.environ.get('LOG_LEVEL', 'INFO')
logging.basicConfig(level=getattr(logging, log_level))
logger = logging.getLogger(__name__)

# Initialize AWS clients
s3_client = boto3.client('s3')
glue_client = boto3.client('glue')

# Configuration from environment variables
RAW_DATA_BUCKET = os.environ.get('RAW_DATA_BUCKET', '${raw_data_bucket}')
PROCESSED_DATA_BUCKET = os.environ.get('PROCESSED_DATA_BUCKET', '${processed_data_bucket}')
GLUE_DATABASE_NAME = os.environ.get('GLUE_DATABASE_NAME', '${glue_database_name}')


def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Main Lambda handler function for transforming cost data.
    
    Args:
        event: Lambda event object
        context: Lambda context object
        
    Returns:
        Dictionary with status code and response body
    """
    try:
        logger.info(f"Starting data transformation - Source: {event.get('source', 'unknown')}")
        
        # Get the latest raw data file from S3
        latest_raw_data = get_latest_raw_data()
        
        if not latest_raw_data:
            logger.info("No raw data files found to process")
            return {
                'statusCode': 200,
                'body': json.dumps({'message': 'No data to process'})
            }
        
        # Transform data for analytics
        transformed_data = transform_cost_data(latest_raw_data)
        
        # Store transformed data in multiple formats
        storage_results = store_transformed_data(transformed_data)
        
        # Update Glue Data Catalog
        update_glue_catalog(transformed_data)
        
        logger.info("Data transformation completed successfully")
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Data transformation completed successfully',
                'processed_datasets': list(transformed_data.keys()),
                'storage_results': storage_results,
                'output_bucket': PROCESSED_DATA_BUCKET
            })
        }
        
    except Exception as e:
        logger.error(f"Error in data transformation: {str(e)}", exc_info=True)
        return {
            'statusCode': 500,
            'body': json.dumps({
                'message': 'Error in data transformation',
                'error': str(e)
            })
        }


def get_latest_raw_data() -> Optional[Dict[str, Any]]:
    """
    Get the latest raw cost data file from S3.
    
    Returns:
        Dictionary containing raw cost data or None if no data found
    """
    try:
        # List objects in raw data bucket
        response = s3_client.list_objects_v2(
            Bucket=RAW_DATA_BUCKET,
            Prefix='raw-cost-data/',
            MaxKeys=1000
        )
        
        if 'Contents' not in response:
            logger.warning("No raw data files found in S3")
            return None
        
        # Sort by last modified and get the latest
        latest_file = sorted(response['Contents'], key=lambda x: x['LastModified'], reverse=True)[0]
        latest_key = latest_file['Key']
        
        logger.info(f"Processing latest file: {latest_key}")
        
        # Read raw data from S3
        obj = s3_client.get_object(Bucket=RAW_DATA_BUCKET, Key=latest_key)
        raw_data = json.loads(obj['Body'].read())
        
        logger.info(f"Successfully loaded raw data from {latest_key}")
        return raw_data
        
    except Exception as e:
        logger.error(f"Error getting latest raw data: {str(e)}")
        raise


def transform_cost_data(raw_data: Dict[str, Any]) -> Dict[str, List[Dict[str, Any]]]:
    """
    Transform raw cost explorer data into analytics-friendly format.
    
    Args:
        raw_data: Raw cost data from Cost Explorer
        
    Returns:
        Dictionary of transformed datasets
    """
    logger.info("Starting data transformation")
    transformed = {}
    
    try:
        # 1. Transform daily costs
        if 'daily_costs' in raw_data and raw_data['daily_costs']:
            logger.info("Transforming daily costs data")
            transformed['daily_costs'] = transform_daily_costs(raw_data['daily_costs'])
        
        # 2. Transform department costs
        if 'monthly_department_costs' in raw_data and raw_data['monthly_department_costs']:
            logger.info("Transforming department costs data")
            transformed['department_costs'] = transform_department_costs(raw_data['monthly_department_costs'])
        
        # 3. Transform RI utilization
        if 'ri_utilization' in raw_data and raw_data['ri_utilization']:
            logger.info("Transforming RI utilization data")
            transformed['ri_utilization'] = transform_ri_utilization(raw_data['ri_utilization'])
        
        # 4. Transform Savings Plans utilization
        if 'savings_plans_utilization' in raw_data and raw_data['savings_plans_utilization']:
            logger.info("Transforming Savings Plans utilization data")
            transformed['savings_plans_utilization'] = transform_savings_plans_utilization(raw_data['savings_plans_utilization'])
        
        # 5. Transform rightsizing recommendations
        if 'rightsizing_recommendations' in raw_data and raw_data['rightsizing_recommendations']:
            logger.info("Transforming rightsizing recommendations")
            transformed['rightsizing_recommendations'] = transform_rightsizing_recommendations(raw_data['rightsizing_recommendations'])
        
        # 6. Transform cost dimensions
        if 'cost_dimensions' in raw_data and raw_data['cost_dimensions']:
            logger.info("Transforming cost dimensions")
            transformed['cost_dimensions'] = transform_cost_dimensions(raw_data['cost_dimensions'])
        
        # 7. Transform organization information
        if 'organization_info' in raw_data and raw_data['organization_info']:
            logger.info("Transforming organization information")
            transformed['organization_info'] = transform_organization_info(raw_data['organization_info'])
        
        logger.info(f"Data transformation completed for {len(transformed)} datasets")
        return transformed
        
    except Exception as e:
        logger.error(f"Error in transform_cost_data: {str(e)}")
        raise


def transform_daily_costs(daily_costs_data: Dict[str, Any]) -> List[Dict[str, Any]]:
    """Transform daily costs data."""
    daily_costs = []
    
    for time_period in daily_costs_data.get('ResultsByTime', []):
        date = time_period['TimePeriod']['Start']
        
        for group in time_period.get('Groups', []):
            service = group['Keys'][0] if len(group['Keys']) > 0 else 'Unknown'
            account = group['Keys'][1] if len(group['Keys']) > 1 else 'Unknown'
            
            daily_costs.append({
                'date': date,
                'service': service,
                'account_id': account,
                'blended_cost': float(group['Metrics']['BlendedCost']['Amount']),
                'unblended_cost': float(group['Metrics']['UnblendedCost']['Amount']),
                'usage_quantity': float(group['Metrics']['UsageQuantity']['Amount']),
                'currency': group['Metrics']['BlendedCost']['Unit'],
                'year': date[:4],
                'month': date[5:7],
                'day': date[8:10]
            })
    
    logger.info(f"Transformed {len(daily_costs)} daily cost records")
    return daily_costs


def transform_department_costs(dept_costs_data: Dict[str, Any]) -> List[Dict[str, Any]]:
    """Transform department costs data."""
    dept_costs = []
    
    for time_period in dept_costs_data.get('ResultsByTime', []):
        start_date = time_period['TimePeriod']['Start']
        
        for group in time_period.get('Groups', []):
            keys = group.get('Keys', [])
            department = keys[0] if len(keys) > 0 and keys[0] else 'Untagged'
            project = keys[1] if len(keys) > 1 and keys[1] else 'Untagged'
            environment = keys[2] if len(keys) > 2 and keys[2] else 'Untagged'
            
            dept_costs.append({
                'month': start_date,
                'department': department,
                'project': project,
                'environment': environment,
                'cost': float(group['Metrics']['BlendedCost']['Amount']),
                'currency': group['Metrics']['BlendedCost']['Unit'],
                'year': start_date[:4],
                'month_num': start_date[5:7]
            })
    
    logger.info(f"Transformed {len(dept_costs)} department cost records")
    return dept_costs


def transform_ri_utilization(ri_util_data: Dict[str, Any]) -> List[Dict[str, Any]]:
    """Transform Reserved Instance utilization data."""
    ri_util = []
    
    for util_period in ri_util_data.get('UtilizationsByTime', []):
        ri_util.append({
            'month': util_period['TimePeriod']['Start'],
            'utilization_percentage': float(util_period['Total']['UtilizationPercentage']),
            'purchased_hours': float(util_period['Total']['PurchasedHours']),
            'used_hours': float(util_period['Total']['UsedHours']),
            'unused_hours': float(util_period['Total']['UnusedHours']),
            'total_actual_hours': float(util_period['Total']['TotalActualHours']),
            'year': util_period['TimePeriod']['Start'][:4],
            'month_num': util_period['TimePeriod']['Start'][5:7]
        })
    
    logger.info(f"Transformed {len(ri_util)} RI utilization records")
    return ri_util


def transform_savings_plans_utilization(sp_util_data: Dict[str, Any]) -> List[Dict[str, Any]]:
    """Transform Savings Plans utilization data."""
    sp_util = []
    
    for util_period in sp_util_data.get('UtilizationsByTime', []):
        sp_util.append({
            'month': util_period['TimePeriod']['Start'],
            'utilization_percentage': float(util_period['Total']['Utilization']['UtilizationPercentage']),
            'used_commitment': float(util_period['Total']['Utilization']['UsedCommitment']),
            'unused_commitment': float(util_period['Total']['Utilization']['UnusedCommitment']),
            'total_commitment': float(util_period['Total']['Utilization']['TotalCommitment']),
            'savings': float(util_period['Total']['Savings']['NetSavings']),
            'on_demand_cost_equivalent': float(util_period['Total']['Savings']['OnDemandCostEquivalent']),
            'year': util_period['TimePeriod']['Start'][:4],
            'month_num': util_period['TimePeriod']['Start'][5:7]
        })
    
    logger.info(f"Transformed {len(sp_util)} Savings Plans utilization records")
    return sp_util


def transform_rightsizing_recommendations(rightsizing_data: Dict[str, Any]) -> List[Dict[str, Any]]:
    """Transform rightsizing recommendations data."""
    rightsizing = []
    
    for rec in rightsizing_data.get('RightsizingRecommendations', []):
        rightsizing.append({
            'account_id': rec.get('AccountId', ''),
            'current_instance': rec.get('CurrentInstance', {}).get('InstanceName', ''),
            'current_instance_type': rec.get('CurrentInstance', {}).get('InstanceType', ''),
            'recommended_instance_type': rec.get('RightsizingType', ''),
            'estimated_monthly_savings': float(rec.get('EstimatedMonthlySavings', 0)),
            'currency': rec.get('CurrencyCode', 'USD'),
            'finding': rec.get('Finding', ''),
            'recommendation_date': datetime.utcnow().strftime('%Y-%m-%d')
        })
    
    logger.info(f"Transformed {len(rightsizing)} rightsizing recommendations")
    return rightsizing


def transform_cost_dimensions(dimensions_data: Dict[str, Any]) -> List[Dict[str, Any]]:
    """Transform cost dimensions data."""
    dimensions = []
    
    # Transform services
    for service in dimensions_data.get('services', {}).get('DimensionValues', []):
        dimensions.append({
            'dimension_type': 'SERVICE',
            'dimension_value': service.get('Value', ''),
            'attributes': service.get('Attributes', {}),
            'match_options': service.get('MatchOptions', [])
        })
    
    # Transform accounts
    for account in dimensions_data.get('accounts', {}).get('DimensionValues', []):
        dimensions.append({
            'dimension_type': 'LINKED_ACCOUNT',
            'dimension_value': account.get('Value', ''),
            'attributes': account.get('Attributes', {}),
            'match_options': account.get('MatchOptions', [])
        })
    
    logger.info(f"Transformed {len(dimensions)} cost dimension records")
    return dimensions


def transform_organization_info(org_data: Dict[str, Any]) -> List[Dict[str, Any]]:
    """Transform organization information."""
    org_info = []
    
    # Organization details
    organization = org_data.get('organization', {})
    if organization:
        org_info.append({
            'record_type': 'organization',
            'organization_id': organization.get('Id', ''),
            'organization_arn': organization.get('Arn', ''),
            'feature_set': organization.get('FeatureSet', ''),
            'master_account_id': organization.get('MasterAccountId', ''),
            'master_account_email': organization.get('MasterAccountEmail', '')
        })
    
    # Account details
    for account in org_data.get('accounts', []):
        org_info.append({
            'record_type': 'account',
            'account_id': account.get('Id', ''),
            'account_name': account.get('Name', ''),
            'account_email': account.get('Email', ''),
            'account_status': account.get('Status', ''),
            'joined_method': account.get('JoinedMethod', ''),
            'joined_timestamp': account.get('JoinedTimestamp', '').isoformat() if account.get('JoinedTimestamp') else ''
        })
    
    logger.info(f"Transformed {len(org_info)} organization records")
    return org_info


def store_transformed_data(transformed_data: Dict[str, List[Dict[str, Any]]]) -> Dict[str, Any]:
    """
    Store transformed data in multiple formats (JSON and Parquet).
    
    Args:
        transformed_data: Dictionary of transformed datasets
        
    Returns:
        Dictionary with storage results
    """
    logger.info("Starting data storage process")
    storage_results = {}
    timestamp = datetime.utcnow().strftime('%Y%m%d_%H%M%S')
    
    try:
        for data_type, data in transformed_data.items():
            if not data:  # Skip empty datasets
                logger.warning(f"Skipping empty dataset: {data_type}")
                continue
            
            # Store as JSON for QuickSight
            json_key = store_as_json(data_type, data, timestamp)
            
            # Store as Parquet for Athena
            parquet_key = store_as_parquet(data_type, data, timestamp)
            
            storage_results[data_type] = {
                'json_location': f"s3://{PROCESSED_DATA_BUCKET}/{json_key}",
                'parquet_location': f"s3://{PROCESSED_DATA_BUCKET}/{parquet_key}",
                'record_count': len(data)
            }
        
        logger.info(f"Data storage completed for {len(storage_results)} datasets")
        return storage_results
        
    except Exception as e:
        logger.error(f"Error storing transformed data: {str(e)}")
        raise


def store_as_json(data_type: str, data: List[Dict[str, Any]], timestamp: str) -> str:
    """Store data as JSON format."""
    json_key = f"processed-data/{data_type}/{datetime.utcnow().strftime('%Y/%m/%d')}/{data_type}_{timestamp}.json"
    
    s3_client.put_object(
        Bucket=PROCESSED_DATA_BUCKET,
        Key=json_key,
        Body=json.dumps(data, default=str, indent=2),
        ContentType='application/json',
        Metadata={
            'data-type': data_type,
            'format': 'json',
            'record-count': str(len(data)),
            'transformation-timestamp': timestamp
        }
    )
    
    logger.info(f"Stored JSON data: {json_key} ({len(data)} records)")
    return json_key


def store_as_parquet(data_type: str, data: List[Dict[str, Any]], timestamp: str) -> str:
    """Store data as Parquet format for efficient querying."""
    if not data:
        return ""
    
    try:
        # Convert to pandas DataFrame
        df = pd.DataFrame(data)
        
        # Convert to Parquet in memory
        parquet_buffer = io.BytesIO()
        df.to_parquet(parquet_buffer, index=False, engine='pyarrow')
        parquet_buffer.seek(0)
        
        # Generate S3 key with partitioning
        parquet_key = f"processed-data-parquet/{data_type}/{datetime.utcnow().strftime('%Y/%m/%d')}/{data_type}_{timestamp}.parquet"
        
        s3_client.put_object(
            Bucket=PROCESSED_DATA_BUCKET,
            Key=parquet_key,
            Body=parquet_buffer.getvalue(),
            ContentType='application/octet-stream',
            Metadata={
                'data-type': data_type,
                'format': 'parquet',
                'record-count': str(len(data)),
                'transformation-timestamp': timestamp
            }
        )
        
        logger.info(f"Stored Parquet data: {parquet_key} ({len(data)} records)")
        return parquet_key
        
    except Exception as e:
        logger.error(f"Error storing Parquet data for {data_type}: {str(e)}")
        raise


def update_glue_catalog(transformed_data: Dict[str, List[Dict[str, Any]]]) -> None:
    """
    Update Glue Data Catalog with new data partitions.
    
    Args:
        transformed_data: Dictionary of transformed datasets
    """
    logger.info("Updating Glue Data Catalog")
    
    try:
        # Ensure database exists
        create_glue_database()
        
        # Update tables for each dataset
        for data_type, data in transformed_data.items():
            if data:  # Only process non-empty datasets
                update_glue_table(data_type, data)
        
        logger.info("Glue Data Catalog update completed")
        
    except Exception as e:
        logger.error(f"Error updating Glue catalog: {str(e)}")
        # Don't raise - catalog update failure shouldn't fail the entire process
        

def create_glue_database() -> None:
    """Create Glue database if it doesn't exist."""
    try:
        glue_client.create_database(
            DatabaseInput={
                'Name': GLUE_DATABASE_NAME,
                'Description': 'Financial analytics database for AWS cost data processing and analysis'
            }
        )
        logger.info(f"Created Glue database: {GLUE_DATABASE_NAME}")
    except glue_client.exceptions.AlreadyExistsException:
        logger.info(f"Glue database already exists: {GLUE_DATABASE_NAME}")
    except Exception as e:
        logger.error(f"Error creating Glue database: {str(e)}")
        raise


def update_glue_table(data_type: str, data: List[Dict[str, Any]]) -> None:
    """Update or create Glue table for a specific data type."""
    try:
        # Define table schema based on data type
        table_schemas = get_table_schemas()
        
        if data_type not in table_schemas:
            logger.warning(f"No schema defined for data type: {data_type}")
            return
        
        table_input = {
            'Name': data_type,
            'StorageDescriptor': {
                'Columns': table_schemas[data_type],
                'Location': f"s3://{PROCESSED_DATA_BUCKET}/processed-data-parquet/{data_type}/",
                'InputFormat': 'org.apache.hadoop.mapred.TextInputFormat',
                'OutputFormat': 'org.apache.hadoop.hive.ql.io.HiveIgnoreKeyTextOutputFormat',
                'SerdeInfo': {
                    'SerializationLibrary': 'org.apache.hadoop.hive.serde2.lazy.LazySimpleSerDe'
                }
            },
            'PartitionKeys': [
                {'Name': 'year', 'Type': 'string'},
                {'Name': 'month', 'Type': 'string'}
            ] if data_type in ['daily_costs', 'department_costs'] else []
        }
        
        try:
            glue_client.create_table(
                DatabaseName=GLUE_DATABASE_NAME,
                TableInput=table_input
            )
            logger.info(f"Created Glue table: {data_type}")
        except glue_client.exceptions.AlreadyExistsException:
            glue_client.update_table(
                DatabaseName=GLUE_DATABASE_NAME,
                TableInput=table_input
            )
            logger.info(f"Updated Glue table: {data_type}")
        
    except Exception as e:
        logger.error(f"Error updating Glue table for {data_type}: {str(e)}")


def get_table_schemas() -> Dict[str, List[Dict[str, str]]]:
    """Define Glue table schemas for different data types."""
    return {
        'daily_costs': [
            {'Name': 'date', 'Type': 'string'},
            {'Name': 'service', 'Type': 'string'},
            {'Name': 'account_id', 'Type': 'string'},
            {'Name': 'blended_cost', 'Type': 'double'},
            {'Name': 'unblended_cost', 'Type': 'double'},
            {'Name': 'usage_quantity', 'Type': 'double'},
            {'Name': 'currency', 'Type': 'string'},
            {'Name': 'day', 'Type': 'string'}
        ],
        'department_costs': [
            {'Name': 'month', 'Type': 'string'},
            {'Name': 'department', 'Type': 'string'},
            {'Name': 'project', 'Type': 'string'},
            {'Name': 'environment', 'Type': 'string'},
            {'Name': 'cost', 'Type': 'double'},
            {'Name': 'currency', 'Type': 'string'},
            {'Name': 'month_num', 'Type': 'string'}
        ],
        'ri_utilization': [
            {'Name': 'month', 'Type': 'string'},
            {'Name': 'utilization_percentage', 'Type': 'double'},
            {'Name': 'purchased_hours', 'Type': 'double'},
            {'Name': 'used_hours', 'Type': 'double'},
            {'Name': 'unused_hours', 'Type': 'double'},
            {'Name': 'total_actual_hours', 'Type': 'double'},
            {'Name': 'month_num', 'Type': 'string'}
        ],
        'rightsizing_recommendations': [
            {'Name': 'account_id', 'Type': 'string'},
            {'Name': 'current_instance', 'Type': 'string'},
            {'Name': 'current_instance_type', 'Type': 'string'},
            {'Name': 'recommended_instance_type', 'Type': 'string'},
            {'Name': 'estimated_monthly_savings', 'Type': 'double'},
            {'Name': 'currency', 'Type': 'string'},
            {'Name': 'finding', 'Type': 'string'},
            {'Name': 'recommendation_date', 'Type': 'string'}
        ]
    }


def validate_environment() -> bool:
    """Validate required environment variables and AWS permissions."""
    try:
        # Check required environment variables
        required_vars = [RAW_DATA_BUCKET, PROCESSED_DATA_BUCKET, GLUE_DATABASE_NAME]
        for var in required_vars:
            if not var:
                raise ValueError(f"Required environment variable is missing")
        
        # Test S3 bucket access
        s3_client.head_bucket(Bucket=RAW_DATA_BUCKET)
        s3_client.head_bucket(Bucket=PROCESSED_DATA_BUCKET)
        
        logger.info("Environment validation successful")
        return True
        
    except Exception as e:
        logger.error(f"Environment validation failed: {str(e)}")
        return False


# Validate environment on module import
if __name__ != "__main__":
    validate_environment()