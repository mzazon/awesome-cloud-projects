"""
Cost Data Collector Lambda Function

This function collects comprehensive cost and usage data from AWS Cost Explorer API
and stores it in S3 for further processing and analysis.

Environment Variables:
- RAW_DATA_BUCKET: S3 bucket for storing raw cost data
- LOOKBACK_DAYS: Number of days to look back for cost data (default: 90)
- GRANULARITY: Data granularity - DAILY or MONTHLY (default: DAILY)
- LOG_LEVEL: Logging level (default: INFO)
"""

import json
import boto3
import logging
import os
from datetime import datetime, timedelta, date
import uuid
from typing import Dict, Any, Optional

# Configure logging
log_level = os.environ.get('LOG_LEVEL', 'INFO')
logging.basicConfig(level=getattr(logging, log_level))
logger = logging.getLogger(__name__)

# Initialize AWS clients
ce_client = boto3.client('ce')
s3_client = boto3.client('s3')
organizations_client = boto3.client('organizations')

# Configuration from environment variables
RAW_DATA_BUCKET = os.environ.get('RAW_DATA_BUCKET', '${raw_data_bucket}')
LOOKBACK_DAYS = int(os.environ.get('LOOKBACK_DAYS', '${lookback_days}'))
GRANULARITY = os.environ.get('GRANULARITY', '${granularity}')


def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Main Lambda handler function for collecting cost data.
    
    Args:
        event: Lambda event object
        context: Lambda context object
        
    Returns:
        Dictionary with status code and response body
    """
    try:
        logger.info(f"Starting cost data collection - Source: {event.get('source', 'unknown')}")
        
        # Calculate date ranges for data collection
        end_date = date.today()
        start_date = end_date - timedelta(days=LOOKBACK_DAYS)
        
        logger.info(f"Collecting cost data from {start_date} to {end_date}")
        
        # Collect comprehensive cost and usage data
        cost_data = collect_cost_data(start_date, end_date)
        
        # Store collected data in S3
        s3_location = store_data_in_s3(cost_data)
        
        # Prepare response summary
        summary = {
            'data_period': {
                'start_date': start_date.strftime('%Y-%m-%d'),
                'end_date': end_date.strftime('%Y-%m-%d')
            },
            'total_daily_records': len(cost_data.get('daily_costs', {}).get('ResultsByTime', [])),
            'total_monthly_records': len(cost_data.get('monthly_department_costs', {}).get('ResultsByTime', [])),
            'ri_utilization_periods': len(cost_data.get('ri_utilization', {}).get('UtilizationsByTime', [])),
            'savings_plans_periods': len(cost_data.get('savings_plans_utilization', {}).get('UtilizationsByTime', [])),
            'rightsizing_recommendations': len(cost_data.get('rightsizing_recommendations', {}).get('RightsizingRecommendations', [])),
            's3_location': s3_location,
            'collection_timestamp': cost_data['collection_timestamp']
        }
        
        logger.info(f"Cost data collection completed successfully: {s3_location}")
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Cost data collection completed successfully',
                'summary': summary
            })
        }
        
    except Exception as e:
        logger.error(f"Error collecting cost data: {str(e)}", exc_info=True)
        return {
            'statusCode': 500,
            'body': json.dumps({
                'message': 'Error collecting cost data',
                'error': str(e)
            })
        }


def collect_cost_data(start_date: date, end_date: date) -> Dict[str, Any]:
    """
    Collect comprehensive cost data from various Cost Explorer APIs.
    
    Args:
        start_date: Start date for data collection
        end_date: End date for data collection
        
    Returns:
        Dictionary containing all collected cost data
    """
    cost_data = {
        'collection_timestamp': datetime.utcnow().isoformat(),
        'data_period': {
            'start_date': start_date.strftime('%Y-%m-%d'),
            'end_date': end_date.strftime('%Y-%m-%d')
        }
    }
    
    try:
        # 1. Daily cost by service and account
        logger.info("Collecting daily cost and usage data")
        cost_data['daily_costs'] = get_daily_costs(start_date, end_date)
        
        # 2. Monthly cost by department (tag-based)
        logger.info("Collecting monthly department cost data")
        cost_data['monthly_department_costs'] = get_department_costs(start_date, end_date)
        
        # 3. Reserved Instance utilization
        logger.info("Collecting Reserved Instance utilization data")
        cost_data['ri_utilization'] = get_ri_utilization(start_date, end_date)
        
        # 4. Savings Plans utilization
        logger.info("Collecting Savings Plans utilization data")
        cost_data['savings_plans_utilization'] = get_savings_plans_utilization(start_date, end_date)
        
        # 5. Rightsizing recommendations
        logger.info("Collecting rightsizing recommendations")
        cost_data['rightsizing_recommendations'] = get_rightsizing_recommendations()
        
        # 6. Cost categories and dimensions
        logger.info("Collecting cost dimensions")
        cost_data['cost_dimensions'] = get_cost_dimensions(start_date, end_date)
        
        # 7. Organization information (if available)
        logger.info("Collecting organization information")
        cost_data['organization_info'] = get_organization_info()
        
    except Exception as e:
        logger.error(f"Error in collect_cost_data: {str(e)}")
        raise
    
    return cost_data


def get_daily_costs(start_date: date, end_date: date) -> Dict[str, Any]:
    """Get daily cost and usage data grouped by service and account."""
    try:
        response = ce_client.get_cost_and_usage(
            TimePeriod={
                'Start': start_date.strftime('%Y-%m-%d'),
                'End': end_date.strftime('%Y-%m-%d')
            },
            Granularity=GRANULARITY,
            Metrics=['BlendedCost', 'UnblendedCost', 'UsageQuantity'],
            GroupBy=[
                {'Type': 'DIMENSION', 'Key': 'SERVICE'},
                {'Type': 'DIMENSION', 'Key': 'LINKED_ACCOUNT'}
            ]
        )
        logger.info(f"Retrieved {len(response.get('ResultsByTime', []))} daily cost records")
        return response
    except Exception as e:
        logger.error(f"Error getting daily costs: {str(e)}")
        return {}


def get_department_costs(start_date: date, end_date: date) -> Dict[str, Any]:
    """Get monthly cost data grouped by department tags."""
    try:
        # Calculate first day of start month
        first_day_of_month = start_date.replace(day=1)
        
        response = ce_client.get_cost_and_usage(
            TimePeriod={
                'Start': first_day_of_month.strftime('%Y-%m-%d'),
                'End': end_date.strftime('%Y-%m-%d')
            },
            Granularity='MONTHLY',
            Metrics=['BlendedCost'],
            GroupBy=[
                {'Type': 'TAG', 'Key': 'Department'},
                {'Type': 'TAG', 'Key': 'Project'},
                {'Type': 'TAG', 'Key': 'Environment'}
            ]
        )
        logger.info(f"Retrieved {len(response.get('ResultsByTime', []))} monthly department cost records")
        return response
    except Exception as e:
        logger.error(f"Error getting department costs: {str(e)}")
        return {}


def get_ri_utilization(start_date: date, end_date: date) -> Dict[str, Any]:
    """Get Reserved Instance utilization data."""
    try:
        response = ce_client.get_reservation_utilization(
            TimePeriod={
                'Start': start_date.strftime('%Y-%m-%d'),
                'End': end_date.strftime('%Y-%m-%d')
            },
            Granularity='MONTHLY'
        )
        logger.info(f"Retrieved {len(response.get('UtilizationsByTime', []))} RI utilization records")
        return response
    except Exception as e:
        logger.error(f"Error getting RI utilization: {str(e)}")
        return {}


def get_savings_plans_utilization(start_date: date, end_date: date) -> Dict[str, Any]:
    """Get Savings Plans utilization data."""
    try:
        response = ce_client.get_savings_plans_utilization(
            TimePeriod={
                'Start': start_date.strftime('%Y-%m-%d'),
                'End': end_date.strftime('%Y-%m-%d')
            },
            Granularity='MONTHLY'
        )
        logger.info(f"Retrieved {len(response.get('UtilizationsByTime', []))} Savings Plans utilization records")
        return response
    except Exception as e:
        logger.error(f"Error getting Savings Plans utilization: {str(e)}")
        return {}


def get_rightsizing_recommendations() -> Dict[str, Any]:
    """Get rightsizing recommendations for EC2 instances."""
    try:
        response = ce_client.get_rightsizing_recommendation(
            Service='AmazonEC2'
        )
        logger.info(f"Retrieved {len(response.get('RightsizingRecommendations', []))} rightsizing recommendations")
        return response
    except Exception as e:
        logger.error(f"Error getting rightsizing recommendations: {str(e)}")
        return {}


def get_cost_dimensions(start_date: date, end_date: date) -> Dict[str, Any]:
    """Get available cost dimensions for analysis."""
    try:
        dimensions = {}
        
        # Get services
        services_response = ce_client.get_dimension_values(
            TimePeriod={
                'Start': start_date.strftime('%Y-%m-%d'),
                'End': end_date.strftime('%Y-%m-%d')
            },
            Dimension='SERVICE'
        )
        dimensions['services'] = services_response
        
        # Get linked accounts
        accounts_response = ce_client.get_dimension_values(
            TimePeriod={
                'Start': start_date.strftime('%Y-%m-%d'),
                'End': end_date.strftime('%Y-%m-%d')
            },
            Dimension='LINKED_ACCOUNT'
        )
        dimensions['accounts'] = accounts_response
        
        logger.info(f"Retrieved {len(dimensions)} cost dimension categories")
        return dimensions
    except Exception as e:
        logger.error(f"Error getting cost dimensions: {str(e)}")
        return {}


def get_organization_info() -> Dict[str, Any]:
    """Get AWS Organizations information if available."""
    try:
        # Get organization details
        org_response = organizations_client.describe_organization()
        
        # Get list of accounts
        accounts_response = organizations_client.list_accounts()
        
        organization_info = {
            'organization': org_response.get('Organization', {}),
            'accounts': accounts_response.get('Accounts', [])
        }
        
        logger.info(f"Retrieved organization info with {len(organization_info['accounts'])} accounts")
        return organization_info
    except Exception as e:
        logger.warning(f"Could not retrieve organization info (normal if not using Organizations): {str(e)}")
        return {}


def store_data_in_s3(cost_data: Dict[str, Any]) -> str:
    """
    Store collected cost data in S3.
    
    Args:
        cost_data: Dictionary containing all collected cost data
        
    Returns:
        S3 location of stored data
    """
    try:
        # Generate unique identifier for this collection
        collection_id = str(uuid.uuid4())
        timestamp = datetime.utcnow()
        
        # Create S3 key with hierarchical structure
        s3_key = f"raw-cost-data/{timestamp.strftime('%Y/%m/%d')}/cost-collection-{collection_id}.json"
        
        # Prepare metadata
        metadata = {
            'collection-date': timestamp.strftime('%Y-%m-%d'),
            'collection-time': timestamp.strftime('%H:%M:%S'),
            'data-type': 'cost-explorer-raw',
            'collection-id': collection_id,
            'lookback-days': str(LOOKBACK_DAYS),
            'granularity': GRANULARITY
        }
        
        # Store in S3
        s3_client.put_object(
            Bucket=RAW_DATA_BUCKET,
            Key=s3_key,
            Body=json.dumps(cost_data, default=str, indent=2),
            ContentType='application/json',
            Metadata=metadata,
            ServerSideEncryption='aws:kms' if os.environ.get('KMS_KEY_ID') else 'AES256'
        )
        
        s3_location = f"s3://{RAW_DATA_BUCKET}/{s3_key}"
        logger.info(f"Cost data stored successfully: {s3_location}")
        
        return s3_location
        
    except Exception as e:
        logger.error(f"Error storing data in S3: {str(e)}")
        raise


def validate_environment() -> bool:
    """Validate required environment variables and AWS permissions."""
    try:
        # Check required environment variables
        if not RAW_DATA_BUCKET:
            raise ValueError("RAW_DATA_BUCKET environment variable is required")
        
        # Test S3 bucket access
        s3_client.head_bucket(Bucket=RAW_DATA_BUCKET)
        
        # Test Cost Explorer access
        test_end_date = date.today()
        test_start_date = test_end_date - timedelta(days=1)
        
        ce_client.get_cost_and_usage(
            TimePeriod={
                'Start': test_start_date.strftime('%Y-%m-%d'),
                'End': test_end_date.strftime('%Y-%m-%d')
            },
            Granularity='DAILY',
            Metrics=['BlendedCost']
        )
        
        logger.info("Environment validation successful")
        return True
        
    except Exception as e:
        logger.error(f"Environment validation failed: {str(e)}")
        return False


# Validate environment on module import
if __name__ != "__main__":
    validate_environment()