"""
Dead Letter Queue monitoring and recovery Lambda function.

This function monitors messages in the DLQ, analyzes error patterns,
implements intelligent retry logic, and provides comprehensive error tracking.
"""

import json
import logging
import boto3
import os
from datetime import datetime
from typing import Dict, Any, Optional

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize AWS clients
sqs = boto3.client('sqs')
cloudwatch = boto3.client('cloudwatch')

# Environment variables
MAIN_QUEUE_URL = "${main_queue_url}"
MAX_RETRY_ATTEMPTS = int("${max_retry_attempts}")
HIGH_VALUE_THRESHOLD = float("${high_value_threshold}")

def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Monitor and analyze messages in the dead letter queue.
    
    Args:
        event: SQS event containing DLQ message records
        context: Lambda context object
        
    Returns:
        Dict containing monitoring results
    """
    
    analyzed_count = 0
    retried_count = 0
    permanent_failure_count = 0
    
    logger.info(f"Analyzing {len(event.get('Records', []))} messages from DLQ")
    
    for record in event.get('Records', []):
        try:
            # Parse the failed message
            message_body = json.loads(record['body'])
            receipt_handle = record['receiptHandle']
            
            # Extract error information
            order_id = message_body.get('orderId', 'UNKNOWN')
            order_value = message_body.get('orderValue', 0)
            customer_id = message_body.get('customerId', 'UNKNOWN')
            error_count = int(record.get('attributes', {}).get('ApproximateReceiveCount', '1'))
            
            logger.info(f"Analyzing failed message for order: {order_id}")
            logger.info(f"Order value: ${order_value}, Error count: {error_count}")
            
            # Perform comprehensive error analysis
            error_analysis = analyze_error(message_body, record)
            
            # Log detailed error information
            logger.info(f"Error category: {error_analysis['category']}")
            logger.info(f"Error severity: {error_analysis['severity']}")
            logger.info(f"Retry recommendation: {error_analysis['retry_recommended']}")
            
            # Send error metrics to CloudWatch
            send_error_metrics(error_analysis, order_value)
            
            # Determine if message should be retried
            retry_decision = make_retry_decision(message_body, error_count, error_analysis)
            
            if retry_decision['should_retry']:
                logger.info(f"Sending order {order_id} for retry (attempt {retry_decision['retry_count']})")
                send_to_retry_queue(message_body, retry_decision)
                retried_count += 1
            else:
                logger.warning(f"Order {order_id} marked as permanent failure: {retry_decision['reason']}")
                handle_permanent_failure(message_body, error_analysis)
                permanent_failure_count += 1
            
            analyzed_count += 1
            
        except Exception as e:
            logger.error(f"Error processing DLQ message: {str(e)}")
            # Continue processing other messages even if one fails
            continue
    
    # Log processing summary
    logger.info(f"DLQ analysis summary - Analyzed: {analyzed_count}, Retried: {retried_count}, Permanent failures: {permanent_failure_count}")
    
    return {
        'statusCode': 200,
        'body': json.dumps({
            'message': 'DLQ monitoring completed',
            'analyzed': analyzed_count,
            'retried': retried_count,
            'permanent_failures': permanent_failure_count,
            'timestamp': datetime.utcnow().isoformat()
        })
    }

def analyze_error(message_body: Dict[str, Any], record: Dict[str, Any]) -> Dict[str, Any]:
    """
    Perform comprehensive error analysis to categorize and understand failures.
    
    Args:
        message_body: Original message content
        record: SQS record containing error information
        
    Returns:
        Dict containing error analysis results
    """
    
    order_value = message_body.get('orderValue', 0)
    order_id = message_body.get('orderId', 'UNKNOWN')
    force_failure = message_body.get('forceFailure', False)
    
    # Determine error category based on message characteristics
    if force_failure:
        category = 'TestFailure'
        severity = 'Low'
        retry_recommended = False
    elif order_value >= HIGH_VALUE_THRESHOLD:
        category = 'HighValueOrder'
        severity = 'Critical'
        retry_recommended = True
    elif order_value >= 100:
        category = 'MediumValueOrder'
        severity = 'High'
        retry_recommended = True
    else:
        category = 'LowValueOrder'
        severity = 'Medium'
        retry_recommended = True
    
    # Analyze message attributes for additional context
    message_attributes = record.get('messageAttributes', {})
    retry_attempt = message_attributes.get('RetryAttempt', {}).get('stringValue') == 'true'
    
    # Determine probable failure cause (in real scenarios, this would be more sophisticated)
    if force_failure:
        probable_cause = 'Intentional test failure'
    elif retry_attempt:
        probable_cause = 'Persistent processing failure after retry'
    else:
        probable_cause = 'Initial processing failure (possibly transient)'
    
    return {
        'category': category,
        'severity': severity,
        'retry_recommended': retry_recommended,
        'probable_cause': probable_cause,
        'order_value': order_value,
        'is_retry_attempt': retry_attempt,
        'analysis_timestamp': datetime.utcnow().isoformat()
    }

def make_retry_decision(message_body: Dict[str, Any], error_count: int, error_analysis: Dict[str, Any]) -> Dict[str, Any]:
    """
    Intelligent retry decision making based on multiple factors.
    
    Args:
        message_body: Original message content
        error_count: Number of times message has been processed
        error_analysis: Results from error analysis
        
    Returns:
        Dict containing retry decision and metadata
    """
    
    order_id = message_body.get('orderId', 'UNKNOWN')
    order_value = message_body.get('orderValue', 0)
    force_failure = message_body.get('forceFailure', False)
    
    # Don't retry forced failures (test messages)
    if force_failure:
        return {
            'should_retry': False,
            'reason': 'Forced failure for testing - no retry',
            'retry_count': 0
        }
    
    # Determine max retries based on order characteristics
    if order_value >= HIGH_VALUE_THRESHOLD:
        max_retries = MAX_RETRY_ATTEMPTS
    elif order_value >= 100:
        max_retries = max(2, MAX_RETRY_ATTEMPTS - 2)
    else:
        max_retries = max(1, MAX_RETRY_ATTEMPTS - 3)
    
    # Check if we've exceeded retry limits
    if error_count >= max_retries:
        return {
            'should_retry': False,
            'reason': f'Exceeded maximum retry attempts ({max_retries})',
            'retry_count': 0
        }
    
    # Calculate retry delay based on attempt count (exponential backoff)
    retry_delay = min(900, 60 * (2 ** error_count))  # Max 15 minutes
    
    return {
        'should_retry': True,
        'reason': f'Retry attempt {error_count + 1} of {max_retries}',
        'retry_count': error_count + 1,
        'retry_delay': retry_delay,
        'max_retries': max_retries
    }

def send_to_retry_queue(message_body: Dict[str, Any], retry_decision: Dict[str, Any]) -> None:
    """
    Send message back to main queue for retry with enhanced metadata.
    
    Args:
        message_body: Original message content
        retry_decision: Retry decision metadata
    """
    
    try:
        # Enhance message with retry metadata
        enhanced_message = message_body.copy()
        enhanced_message['dlq_analysis'] = {
            'retry_count': retry_decision['retry_count'],
            'retry_timestamp': datetime.utcnow().isoformat(),
            'retry_delay': retry_decision['retry_delay']
        }
        
        # Send message with retry attributes
        response = sqs.send_message(
            QueueUrl=MAIN_QUEUE_URL,
            MessageBody=json.dumps(enhanced_message),
            MessageAttributes={
                'RetryAttempt': {
                    'StringValue': 'true',
                    'DataType': 'String'
                },
                'RetryCount': {
                    'StringValue': str(retry_decision['retry_count']),
                    'DataType': 'Number'
                },
                'OriginalFailureTime': {
                    'StringValue': datetime.utcnow().isoformat(),
                    'DataType': 'String'
                }
            },
            DelaySeconds=min(retry_decision.get('retry_delay', 0), 900)  # Max 15 minutes
        )
        
        logger.info(f"Message sent to retry queue with message ID: {response['MessageId']}")
        
    except Exception as e:
        logger.error(f"Failed to send message to retry queue: {str(e)}")
        raise e

def handle_permanent_failure(message_body: Dict[str, Any], error_analysis: Dict[str, Any]) -> None:
    """
    Handle messages that have permanently failed and cannot be retried.
    
    In production, this might:
    - Send to a manual review queue
    - Create support tickets
    - Send notifications to business stakeholders
    - Store in a failure database for analysis
    
    Args:
        message_body: Original message content
        error_analysis: Error analysis results
    """
    
    order_id = message_body.get('orderId', 'UNKNOWN')
    order_value = message_body.get('orderValue', 0)
    customer_id = message_body.get('customerId', 'UNKNOWN')
    
    # Log permanent failure for audit trail
    failure_record = {
        'order_id': order_id,
        'customer_id': customer_id,
        'order_value': order_value,
        'failure_time': datetime.utcnow().isoformat(),
        'error_analysis': error_analysis,
        'original_message': message_body
    }
    
    logger.error(f"PERMANENT FAILURE: {json.dumps(failure_record, indent=2)}")
    
    # In production, you would:
    # 1. Send to a manual review queue
    # 2. Create alerts for high-value order failures
    # 3. Update customer service systems
    # 4. Store in failure database for analysis

def send_error_metrics(error_analysis: Dict[str, Any], order_value: float) -> None:
    """
    Send detailed error metrics to CloudWatch for monitoring and alerting.
    
    Args:
        error_analysis: Error analysis results
        order_value: Value of the failed order
    """
    
    try:
        # Send comprehensive error metrics
        cloudwatch.put_metric_data(
            Namespace='DLQ/Processing',
            MetricData=[
                {
                    'MetricName': 'FailedMessages',
                    'Value': 1,
                    'Unit': 'Count',
                    'Dimensions': [
                        {
                            'Name': 'ErrorCategory',
                            'Value': error_analysis['category']
                        },
                        {
                            'Name': 'Severity',
                            'Value': error_analysis['severity']
                        }
                    ]
                },
                {
                    'MetricName': 'FailedOrderValue',
                    'Value': order_value,
                    'Unit': 'None',
                    'Dimensions': [
                        {
                            'Name': 'ErrorCategory',
                            'Value': error_analysis['category']
                        }
                    ]
                },
                {
                    'MetricName': 'RetryRecommendations',
                    'Value': 1 if error_analysis['retry_recommended'] else 0,
                    'Unit': 'Count',
                    'Dimensions': [
                        {
                            'Name': 'RecommendRetry',
                            'Value': 'Yes' if error_analysis['retry_recommended'] else 'No'
                        }
                    ]
                }
            ]
        )
        
    except Exception as e:
        logger.warning(f"Failed to send error metrics to CloudWatch: {str(e)}")
        # Don't fail the main processing for metrics issues