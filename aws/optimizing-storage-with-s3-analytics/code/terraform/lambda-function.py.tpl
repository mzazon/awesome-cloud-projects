"""
Lambda function for automated S3 storage analytics reporting.

This function executes Athena queries against S3 inventory data to generate
storage optimization insights and recommendations.
"""

import json
import boto3
import os
import logging
from datetime import datetime, timedelta
from typing import Dict, Any, Optional

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize AWS clients
athena = boto3.client('athena')
s3 = boto3.client('s3')
cloudwatch = boto3.client('cloudwatch')

# Configuration from environment variables
ATHENA_DATABASE = os.environ['ATHENA_DATABASE']
ATHENA_TABLE = os.environ['ATHENA_TABLE']
DEST_BUCKET = os.environ['DEST_BUCKET']
SOURCE_BUCKET = os.environ['SOURCE_BUCKET']


def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Main Lambda handler for storage analytics reporting.
    
    Args:
        event: Lambda event data
        context: Lambda context object
        
    Returns:
        Response dictionary with status and results
    """
    try:
        logger.info("Starting storage analytics reporting")
        
        # Execute storage analysis queries
        query_results = execute_analytics_queries()
        
        # Publish CloudWatch metrics
        publish_custom_metrics(query_results)
        
        # Generate summary report
        summary = generate_report_summary(query_results)
        
        logger.info("Storage analytics reporting completed successfully")
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Storage analytics executed successfully',
                'timestamp': datetime.utcnow().isoformat(),
                'summary': summary,
                'queryResults': query_results
            })
        }
        
    except Exception as e:
        logger.error(f"Error in storage analytics: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': str(e),
                'timestamp': datetime.utcnow().isoformat()
            })
        }


def execute_analytics_queries() -> Dict[str, Any]:
    """
    Execute various analytics queries against the inventory data.
    
    Returns:
        Dictionary containing query results
    """
    queries = {
        'storage_class_distribution': f"""
        SELECT 
            storage_class,
            COUNT(*) as object_count,
            SUM(size) as total_size_bytes,
            ROUND(SUM(size) / 1024.0 / 1024.0 / 1024.0, 2) as total_size_gb,
            ROUND(AVG(size) / 1024.0 / 1024.0, 2) as avg_size_mb
        FROM {ATHENA_DATABASE}.{ATHENA_TABLE}
        WHERE size > 0
        GROUP BY storage_class
        ORDER BY total_size_bytes DESC;
        """,
        
        'old_objects_analysis': f"""
        SELECT 
            storage_class,
            COUNT(*) as object_count,
            SUM(size) as total_size_bytes,
            ROUND(SUM(size) / 1024.0 / 1024.0 / 1024.0, 2) as total_size_gb
        FROM {ATHENA_DATABASE}.{ATHENA_TABLE}
        WHERE DATE_DIFF('day', DATE_PARSE(last_modified_date, '%Y-%m-%dT%H:%i:%s.%fZ'), CURRENT_DATE) > 30
        AND size > 0
        GROUP BY storage_class
        ORDER BY total_size_bytes DESC;
        """,
        
        'prefix_analysis': f"""
        SELECT 
            CASE 
                WHEN key LIKE 'data/%' THEN 'data'
                WHEN key LIKE 'logs/%' THEN 'logs'
                WHEN key LIKE 'archive/%' THEN 'archive'
                WHEN key LIKE 'temp/%' THEN 'temp'
                ELSE 'other'
            END as prefix_category,
            COUNT(*) as object_count,
            SUM(size) as total_size_bytes,
            ROUND(SUM(size) / 1024.0 / 1024.0 / 1024.0, 2) as total_size_gb,
            ROUND(AVG(size) / 1024.0 / 1024.0, 2) as avg_size_mb
        FROM {ATHENA_DATABASE}.{ATHENA_TABLE}
        WHERE size > 0
        GROUP BY 1
        ORDER BY total_size_bytes DESC;
        """,
        
        'optimization_opportunities': f"""
        SELECT 
            'Standard to Standard-IA' as optimization_type,
            COUNT(*) as candidate_objects,
            SUM(size) as total_size_bytes,
            ROUND(SUM(size) / 1024.0 / 1024.0 / 1024.0, 2) as total_size_gb,
            ROUND(SUM(size) * 0.0125 / 1024.0 / 1024.0 / 1024.0, 2) as estimated_monthly_savings_usd
        FROM {ATHENA_DATABASE}.{ATHENA_TABLE}
        WHERE storage_class = 'STANDARD'
        AND DATE_DIFF('day', DATE_PARSE(last_modified_date, '%Y-%m-%dT%H:%i:%s.%fZ'), CURRENT_DATE) > 30
        AND size > 128000
        AND size > 0
        
        UNION ALL
        
        SELECT 
            'Standard-IA to Glacier' as optimization_type,
            COUNT(*) as candidate_objects,
            SUM(size) as total_size_bytes,
            ROUND(SUM(size) / 1024.0 / 1024.0 / 1024.0, 2) as total_size_gb,
            ROUND(SUM(size) * 0.008 / 1024.0 / 1024.0 / 1024.0, 2) as estimated_monthly_savings_usd
        FROM {ATHENA_DATABASE}.{ATHENA_TABLE}
        WHERE storage_class = 'STANDARD_IA'
        AND DATE_DIFF('day', DATE_PARSE(last_modified_date, '%Y-%m-%dT%H:%i:%s.%fZ'), CURRENT_DATE) > 90
        AND size > 0;
        """
    }
    
    results = {}
    
    for query_name, query_sql in queries.items():
        try:
            logger.info(f"Executing query: {query_name}")
            
            # Start query execution
            response = athena.start_query_execution(
                QueryString=query_sql,
                QueryExecutionContext={'Database': ATHENA_DATABASE},
                ResultConfiguration={
                    'OutputLocation': f's3://{DEST_BUCKET}/athena-results/',
                    'EncryptionConfiguration': {
                        'EncryptionOption': 'SSE_S3'
                    }
                }
            )
            
            query_execution_id = response['QueryExecutionId']
            
            # Wait for query completion
            query_result = wait_for_query_completion(query_execution_id)
            
            if query_result:
                results[query_name] = {
                    'execution_id': query_execution_id,
                    'status': 'SUCCESS',
                    'result_location': f's3://{DEST_BUCKET}/athena-results/{query_execution_id}.csv'
                }
            else:
                results[query_name] = {
                    'execution_id': query_execution_id,
                    'status': 'FAILED'
                }
                
        except Exception as e:
            logger.error(f"Error executing query {query_name}: {str(e)}")
            results[query_name] = {
                'status': 'ERROR',
                'error': str(e)
            }
    
    return results


def wait_for_query_completion(query_execution_id: str, max_wait_time: int = 300) -> bool:
    """
    Wait for Athena query to complete.
    
    Args:
        query_execution_id: Athena query execution ID
        max_wait_time: Maximum time to wait in seconds
        
    Returns:
        True if query succeeded, False otherwise
    """
    import time
    
    start_time = time.time()
    
    while time.time() - start_time < max_wait_time:
        try:
            response = athena.get_query_execution(QueryExecutionId=query_execution_id)
            status = response['QueryExecution']['Status']['State']
            
            if status == 'SUCCEEDED':
                return True
            elif status in ['FAILED', 'CANCELLED']:
                logger.error(f"Query {query_execution_id} failed with status: {status}")
                if 'StateChangeReason' in response['QueryExecution']['Status']:
                    logger.error(f"Reason: {response['QueryExecution']['Status']['StateChangeReason']}")
                return False
            
            # Wait before checking again
            time.sleep(5)
            
        except Exception as e:
            logger.error(f"Error checking query status: {str(e)}")
            return False
    
    logger.error(f"Query {query_execution_id} timed out after {max_wait_time} seconds")
    return False


def publish_custom_metrics(query_results: Dict[str, Any]) -> None:
    """
    Publish custom CloudWatch metrics based on query results.
    
    Args:
        query_results: Results from analytics queries
    """
    try:
        # Count successful queries
        successful_queries = sum(1 for result in query_results.values() 
                               if result.get('status') == 'SUCCESS')
        
        # Publish metrics
        cloudwatch.put_metric_data(
            Namespace='S3/StorageAnalytics',
            MetricData=[
                {
                    'MetricName': 'SuccessfulQueries',
                    'Value': successful_queries,
                    'Unit': 'Count',
                    'Dimensions': [
                        {
                            'Name': 'SourceBucket',
                            'Value': SOURCE_BUCKET
                        }
                    ]
                },
                {
                    'MetricName': 'AnalyticsExecutions',
                    'Value': 1,
                    'Unit': 'Count',
                    'Dimensions': [
                        {
                            'Name': 'SourceBucket',
                            'Value': SOURCE_BUCKET
                        }
                    ]
                }
            ]
        )
        
        logger.info("Custom metrics published successfully")
        
    except Exception as e:
        logger.error(f"Error publishing metrics: {str(e)}")


def generate_report_summary(query_results: Dict[str, Any]) -> Dict[str, Any]:
    """
    Generate a summary of the analytics report.
    
    Args:
        query_results: Results from analytics queries
        
    Returns:
        Summary dictionary
    """
    successful_queries = [name for name, result in query_results.items() 
                         if result.get('status') == 'SUCCESS']
    
    failed_queries = [name for name, result in query_results.items() 
                     if result.get('status') != 'SUCCESS']
    
    return {
        'execution_timestamp': datetime.utcnow().isoformat(),
        'source_bucket': SOURCE_BUCKET,
        'destination_bucket': DEST_BUCKET,
        'total_queries': len(query_results),
        'successful_queries': len(successful_queries),
        'failed_queries': len(failed_queries),
        'successful_query_names': successful_queries,
        'failed_query_names': failed_queries,
        'athena_database': ATHENA_DATABASE,
        'athena_table': ATHENA_TABLE
    }