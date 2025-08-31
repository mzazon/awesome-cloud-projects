"""
Intelligent Web Scraping Lambda Function
This function orchestrates web scraping using AWS Bedrock AgentCore Browser
and Code Interpreter services with comprehensive error handling and monitoring.
"""

import json
import boto3
import time
import logging
import uuid
import os
from datetime import datetime
from botocore.exceptions import ClientError, BotoCoreError
from typing import Dict, List, Any, Optional

# Configure logging
logger = logging.getLogger()
log_level = os.environ.get('LOG_LEVEL', 'INFO')
logger.setLevel(getattr(logging, log_level))

# Initialize AWS clients
s3_client = boto3.client('s3')
agentcore_client = boto3.client('bedrock-agentcore')
cloudwatch_client = boto3.client('cloudwatch')


class ScrapingError(Exception):
    """Custom exception for scraping-related errors"""
    pass


class DataProcessingError(Exception):
    """Custom exception for data processing errors"""
    pass


def lambda_handler(event: Dict[str, Any], context) -> Dict[str, Any]:
    """
    Main Lambda handler for intelligent web scraping workflow
    
    Args:
        event: Lambda event containing scraping configuration
        context: Lambda context object
        
    Returns:
        Dict containing execution results and metadata
    """
    try:
        # Extract configuration from event
        bucket_input = event.get('bucket_input', os.environ.get('S3_BUCKET_INPUT'))
        bucket_output = event.get('bucket_output', os.environ.get('S3_BUCKET_OUTPUT'))
        test_mode = event.get('test_mode', False)
        scheduled_execution = event.get('scheduled_execution', False)
        
        if not bucket_input or not bucket_output:
            raise ValueError("Missing required S3 bucket configuration")
        
        logger.info(f"Starting scraping workflow - Input: {bucket_input}, Output: {bucket_output}")
        
        # Load scraping configuration from S3
        config = load_scraping_config(bucket_input)
        processing_config = load_processing_config(bucket_input)
        
        # Process each scraping scenario
        all_scraped_data = []
        session_metrics = {
            'browser_sessions_created': 0,
            'browser_sessions_succeeded': 0,
            'code_interpreter_sessions': 0,
            'total_data_points': 0,
            'processing_errors': 0
        }
        
        for scenario in config.get('scraping_scenarios', []):
            try:
                logger.info(f"Processing scenario: {scenario['name']}")
                
                # Execute browser scraping session
                scenario_data = execute_browser_session(scenario, session_metrics)
                
                if scenario_data:
                    all_scraped_data.append(scenario_data)
                    session_metrics['total_data_points'] += len(
                        scenario_data.get('extracted_data', {}).get('product_titles', [])
                    )
                
            except ScrapingError as e:
                logger.error(f"Scraping error in scenario {scenario['name']}: {str(e)}")
                session_metrics['processing_errors'] += 1
                continue
            except Exception as e:
                logger.error(f"Unexpected error in scenario {scenario['name']}: {str(e)}")
                session_metrics['processing_errors'] += 1
                continue
        
        # Process scraped data with Code Interpreter
        processing_results = None
        if all_scraped_data:
            try:
                processing_results = execute_code_interpreter_session(
                    all_scraped_data, processing_config, session_metrics
                )
            except DataProcessingError as e:
                logger.error(f"Data processing error: {str(e)}")
                session_metrics['processing_errors'] += 1
        
        # Prepare final results
        result_data = prepare_results(
            all_scraped_data, processing_results, session_metrics, context
        )
        
        # Save results to S3
        result_location = save_results_to_s3(result_data, bucket_output)
        
        # Send CloudWatch metrics
        send_cloudwatch_metrics(session_metrics, context.function_name)
        
        # Prepare response
        response = {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Scraping completed successfully',
                'scenarios_processed': len(config.get('scraping_scenarios', [])),
                'scenarios_succeeded': len(all_scraped_data),
                'total_data_points': session_metrics['total_data_points'],
                'result_location': result_location,
                'execution_time_ms': (datetime.utcnow().timestamp() * 1000) - (context.get_remaining_time_in_millis() if hasattr(context, 'get_remaining_time_in_millis') else 0),
                'metrics': session_metrics
            })
        }
        
        logger.info(f"Workflow completed successfully: {result_location}")
        return response
        
    except Exception as e:
        logger.error(f"Critical error in scraping workflow: {str(e)}")
        
        # Send error metrics
        send_error_metrics(str(e), context.function_name)
        
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': str(e),
                'error_type': type(e).__name__,
                'request_id': context.aws_request_id,
                'timestamp': datetime.utcnow().isoformat()
            })
        }


def load_scraping_config(bucket_name: str) -> Dict[str, Any]:
    """Load scraping configuration from S3"""
    try:
        response = s3_client.get_object(Bucket=bucket_name, Key='scraper-config.json')
        config = json.loads(response['Body'].read())
        logger.info(f"Loaded scraping config with {len(config.get('scraping_scenarios', []))} scenarios")
        return config
    except ClientError as e:
        logger.error(f"Failed to load scraping config: {str(e)}")
        raise ScrapingError(f"Configuration loading failed: {str(e)}")


def load_processing_config(bucket_name: str) -> Dict[str, Any]:
    """Load data processing configuration from S3"""
    try:
        response = s3_client.get_object(Bucket=bucket_name, Key='data-processing-config.json')
        config = json.loads(response['Body'].read())
        logger.info("Loaded data processing configuration")
        return config
    except ClientError as e:
        logger.warning(f"Failed to load processing config, using defaults: {str(e)}")
        return {
            'processing_rules': {
                'price_cleaning': {'convert_to_numeric': True},
                'data_validation': {'min_data_points': 1}
            }
        }


def execute_browser_session(scenario: Dict[str, Any], metrics: Dict[str, int]) -> Optional[Dict[str, Any]]:
    """Execute a browser scraping session for a given scenario"""
    browser_session_id = None
    
    try:
        # Start browser session
        session_config = scenario.get('session_config', {})
        session_response = agentcore_client.start_browser_session(
            browserIdentifier='default-browser',
            name=f"{scenario['name']}-{int(time.time())}",
            sessionTimeoutSeconds=session_config.get('timeout_seconds', 300)
        )
        
        browser_session_id = session_response['sessionId']
        metrics['browser_sessions_created'] += 1
        logger.info(f"Started browser session: {browser_session_id}")
        
        # Simulate web navigation and data extraction
        # Note: In actual implementation, you would use browser automation SDK
        extracted_data = simulate_web_scraping(scenario)
        
        scenario_data = {
            'scenario_name': scenario['name'],
            'target_url': scenario['target_url'],
            'timestamp': datetime.utcnow().isoformat(),
            'session_id': browser_session_id,
            'extracted_data': extracted_data,
            'extraction_rules': scenario.get('extraction_rules', {}),
            'success': True
        }
        
        metrics['browser_sessions_succeeded'] += 1
        logger.info(f"Successfully extracted {len(extracted_data.get('product_titles', []))} items")
        
        return scenario_data
        
    except Exception as e:
        logger.error(f"Browser session error: {str(e)}")
        raise ScrapingError(f"Browser automation failed: {str(e)}")
        
    finally:
        # Cleanup browser session
        if browser_session_id:
            try:
                agentcore_client.stop_browser_session(sessionId=browser_session_id)
                logger.info(f"Stopped browser session: {browser_session_id}")
            except Exception as e:
                logger.warning(f"Failed to stop browser session {browser_session_id}: {e}")


def simulate_web_scraping(scenario: Dict[str, Any]) -> Dict[str, List[str]]:
    """
    Simulate web scraping for demonstration purposes
    In production, this would interface with AgentCore Browser APIs
    """
    target_url = scenario.get('target_url', '')
    
    # Generate realistic sample data based on the target URL
    if 'books.toscrape.com' in target_url:
        return {
            'product_titles': [
                'A Light in the Attic',
                'Tipping the Velvet',
                'Soumission',
                'Sharp Objects',
                'Sapiens: A Brief History of Humankind'
            ],
            'prices': ['£51.77', '£53.74', '£50.10', '£47.82', '£54.23'],
            'availability': ['In stock', 'In stock', 'In stock', 'Out of stock', 'In stock'],
            'ratings': ['Three', 'One', 'One', 'Four', 'Five']
        }
    else:
        # Generic sample data for other sites
        return {
            'product_titles': ['Sample Product 1', 'Sample Product 2', 'Sample Product 3'],
            'prices': ['$29.99', '$39.99', '$19.99'],
            'availability': ['Available', 'Limited', 'Available'],
            'descriptions': ['High quality product', 'Premium features', 'Best value option']
        }


def execute_code_interpreter_session(
    scraped_data: List[Dict[str, Any]], 
    processing_config: Dict[str, Any],
    metrics: Dict[str, int]
) -> Dict[str, Any]:
    """Execute data processing using Code Interpreter session"""
    code_session_id = None
    
    try:
        # Start Code Interpreter session
        code_session_response = agentcore_client.start_code_interpreter_session(
            codeInterpreterIdentifier='default-code-interpreter',
            name=f"data-processor-{int(time.time())}",
            sessionTimeoutSeconds=300
        )
        
        code_session_id = code_session_response['sessionId']
        metrics['code_interpreter_sessions'] += 1
        logger.info(f"Started code interpreter session: {code_session_id}")
        
        # Process data with analysis
        processing_results = process_scraped_data(scraped_data, processing_config)
        
        logger.info("Data processing completed successfully")
        return processing_results
        
    except Exception as e:
        logger.error(f"Code interpreter session error: {str(e)}")
        raise DataProcessingError(f"Data processing failed: {str(e)}")
        
    finally:
        # Cleanup code interpreter session
        if code_session_id:
            try:
                agentcore_client.stop_code_interpreter_session(sessionId=code_session_id)
                logger.info(f"Stopped code interpreter session: {code_session_id}")
            except Exception as e:
                logger.warning(f"Failed to stop code session {code_session_id}: {e}")


def process_scraped_data(
    scraped_data: List[Dict[str, Any]], 
    config: Dict[str, Any]
) -> Dict[str, Any]:
    """Process and analyze scraped data"""
    
    processing_rules = config.get('processing_rules', {})
    price_cleaning = processing_rules.get('price_cleaning', {})
    
    # Aggregate all data
    total_items = sum(len(data['extracted_data'].get('product_titles', [])) for data in scraped_data)
    
    # Process prices
    all_prices = []
    for data in scraped_data:
        prices = data['extracted_data'].get('prices', [])
        for price_str in prices:
            if price_cleaning.get('convert_to_numeric', True):
                # Extract numeric value from price string
                numeric_price = ''.join(filter(lambda x: x.isdigit() or x == '.', price_str))
                if numeric_price and '.' in numeric_price:
                    all_prices.append(float(numeric_price))
    
    # Process availability data
    all_availability = []
    for data in scraped_data:
        availability = data['extracted_data'].get('availability', [])
        all_availability.extend(availability)
    
    # Calculate availability statistics
    available_count = sum(1 for status in all_availability 
                         if any(word in status.lower() for word in ['stock', 'available', 'in stock']))
    
    # Generate comprehensive analysis
    analysis = {
        'total_products_scraped': total_items,
        'scenarios_processed': len(scraped_data),
        'price_analysis': {
            'total_prices_found': len(all_prices),
            'average_price': round(sum(all_prices) / len(all_prices), 2) if all_prices else 0,
            'min_price': round(min(all_prices), 2) if all_prices else 0,
            'max_price': round(max(all_prices), 2) if all_prices else 0,
            'price_range': round(max(all_prices) - min(all_prices), 2) if all_prices else 0
        },
        'availability_analysis': {
            'total_items_checked': len(all_availability),
            'available_count': available_count,
            'unavailable_count': len(all_availability) - available_count,
            'availability_rate_percent': round((available_count / len(all_availability) * 100), 2) if all_availability else 0
        },
        'data_quality_metrics': {
            'completeness_score': round((total_items / max(1, len(scraped_data))) * 100, 2),
            'price_data_coverage': round((len(all_prices) / max(1, total_items)) * 100, 2),
            'availability_data_coverage': round((len(all_availability) / max(1, total_items)) * 100, 2)
        },
        'processing_metadata': {
            'processing_timestamp': datetime.utcnow().isoformat(),
            'processing_rules_applied': list(processing_rules.keys()),
            'data_sources': [data['target_url'] for data in scraped_data]
        }
    }
    
    return analysis


def prepare_results(
    scraped_data: List[Dict[str, Any]], 
    processing_results: Optional[Dict[str, Any]],
    metrics: Dict[str, int],
    context
) -> Dict[str, Any]:
    """Prepare final results for storage"""
    
    result_data = {
        'execution_metadata': {
            'timestamp': datetime.utcnow().isoformat(),
            'function_name': context.function_name,
            'request_id': context.aws_request_id,
            'function_version': context.function_version,
            'memory_limit_mb': context.memory_limit_in_mb,
            'remaining_time_ms': context.get_remaining_time_in_millis()
        },
        'session_metrics': metrics,
        'raw_data': scraped_data,
        'analysis': processing_results or {},
        'data_summary': {
            'scenarios_attempted': metrics.get('browser_sessions_created', 0),
            'scenarios_succeeded': metrics.get('browser_sessions_succeeded', 0),
            'total_data_points_extracted': metrics.get('total_data_points', 0),
            'processing_errors': metrics.get('processing_errors', 0),
            'success_rate_percent': round(
                (metrics.get('browser_sessions_succeeded', 0) / 
                 max(1, metrics.get('browser_sessions_created', 1))) * 100, 2
            )
        }
    }
    
    return result_data


def save_results_to_s3(result_data: Dict[str, Any], bucket_name: str) -> str:
    """Save processing results to S3"""
    try:
        result_key = f'scraping-results-{int(time.time())}.json'
        
        s3_client.put_object(
            Bucket=bucket_name,
            Key=result_key,
            Body=json.dumps(result_data, indent=2, default=str),
            ContentType='application/json',
            Metadata={
                'scraping-timestamp': datetime.utcnow().isoformat(),
                'data-points': str(result_data.get('session_metrics', {}).get('total_data_points', 0)),
                'success-rate': str(result_data.get('data_summary', {}).get('success_rate_percent', 0))
            }
        )
        
        result_location = f's3://{bucket_name}/{result_key}'
        logger.info(f"Results saved to: {result_location}")
        return result_location
        
    except ClientError as e:
        logger.error(f"Failed to save results to S3: {str(e)}")
        raise ScrapingError(f"Result storage failed: {str(e)}")


def send_cloudwatch_metrics(metrics: Dict[str, int], function_name: str):
    """Send custom metrics to CloudWatch"""
    try:
        namespace = f'IntelligentScraper/{function_name}'
        
        metric_data = [
            {
                'MetricName': 'ScrapingJobs',
                'Value': metrics.get('browser_sessions_succeeded', 0),
                'Unit': 'Count',
                'Timestamp': datetime.utcnow()
            },
            {
                'MetricName': 'DataPointsExtracted',
                'Value': metrics.get('total_data_points', 0),
                'Unit': 'Count',
                'Timestamp': datetime.utcnow()
            },
            {
                'MetricName': 'ProcessingErrors',
                'Value': metrics.get('processing_errors', 0),
                'Unit': 'Count',
                'Timestamp': datetime.utcnow()
            },
            {
                'MetricName': 'SuccessRate',
                'Value': round(
                    (metrics.get('browser_sessions_succeeded', 0) / 
                     max(1, metrics.get('browser_sessions_created', 1))) * 100, 2
                ),
                'Unit': 'Percent',
                'Timestamp': datetime.utcnow()
            }
        ]
        
        cloudwatch_client.put_metric_data(
            Namespace=namespace,
            MetricData=metric_data
        )
        
        logger.info(f"Sent {len(metric_data)} metrics to CloudWatch")
        
    except Exception as e:
        logger.warning(f"Failed to send CloudWatch metrics: {str(e)}")


def send_error_metrics(error_message: str, function_name: str):
    """Send error metrics to CloudWatch"""
    try:
        namespace = f'IntelligentScraper/{function_name}'
        
        cloudwatch_client.put_metric_data(
            Namespace=namespace,
            MetricData=[
                {
                    'MetricName': 'CriticalErrors',
                    'Value': 1,
                    'Unit': 'Count',
                    'Timestamp': datetime.utcnow(),
                    'Dimensions': [
                        {
                            'Name': 'ErrorType',
                            'Value': type(Exception).__name__
                        }
                    ]
                }
            ]
        )
        
    except Exception as e:
        logger.warning(f"Failed to send error metrics: {str(e)}")