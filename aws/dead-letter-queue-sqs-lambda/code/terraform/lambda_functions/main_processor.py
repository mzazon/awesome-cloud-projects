"""
Main order processing Lambda function for DLQ processing system.

This function processes order messages from the main SQS queue and simulates
business logic with configurable failure rates for demonstration purposes.
In production, this would contain actual order processing logic.
"""

import json
import logging
import random
import boto3
from datetime import datetime
from typing import Dict, Any, List

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize AWS clients
cloudwatch = boto3.client('cloudwatch')

def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Main order processing function that simulates processing with intentional failures.
    
    Args:
        event: SQS event containing message records
        context: Lambda context object
        
    Returns:
        Dict containing processing results
    """
    
    processed_count = 0
    failed_count = 0
    failure_rate = float("${failure_rate}")
    
    logger.info(f"Processing {len(event.get('Records', []))} messages")
    
    for record in event.get('Records', []):
        try:
            # Parse the message
            message_body = json.loads(record['body'])
            order_id = message_body.get('orderId', 'UNKNOWN')
            order_value = message_body.get('orderValue', 0)
            customer_id = message_body.get('customerId', 'UNKNOWN')
            
            logger.info(f"Processing order: {order_id}, value: ${order_value}, customer: {customer_id}")
            
            # Simulate processing logic with intentional failures for demo
            # Check for forced failure (for testing)
            if message_body.get('forceFailure', False):
                raise Exception(f"Forced failure for testing - order {order_id}")
            
            # Simulate random failures based on configured rate
            if random.random() < failure_rate:
                raise Exception(f"Simulated processing failure for order {order_id}")
            
            # Simulate successful processing
            success_result = process_order(message_body)
            
            logger.info(f"Successfully processed order: {order_id}")
            processed_count += 1
            
            # Send success metrics to CloudWatch
            send_processing_metrics('Success', order_value)
            
        except Exception as e:
            logger.error(f"Error processing message: {str(e)}")
            failed_count += 1
            
            # Send failure metrics to CloudWatch
            order_value = json.loads(record['body']).get('orderValue', 0)
            send_processing_metrics('Failure', order_value)
            
            # Re-raise the exception to trigger SQS retry mechanism
            raise e
    
    # Log processing summary
    logger.info(f"Processing summary - Successful: {processed_count}, Failed: {failed_count}")
    
    return {
        'statusCode': 200,
        'body': json.dumps({
            'message': 'Processing completed',
            'processed': processed_count,
            'failed': failed_count,
            'timestamp': datetime.utcnow().isoformat()
        })
    }

def process_order(order_data: Dict[str, Any]) -> Dict[str, Any]:
    """
    Simulate order processing business logic.
    
    In a real implementation, this would:
    - Validate order data
    - Check inventory availability
    - Process payment
    - Update order status
    - Send confirmation notifications
    
    Args:
        order_data: Order information dictionary
        
    Returns:
        Processing result dictionary
    """
    
    order_id = order_data.get('orderId')
    order_value = order_data.get('orderValue', 0)
    items = order_data.get('items', [])
    
    # Simulate processing time
    import time
    time.sleep(0.1)  # Simulate 100ms processing time
    
    # Simulate business logic validations
    if order_value <= 0:
        raise ValueError(f"Invalid order value: {order_value}")
    
    if not items:
        raise ValueError(f"Order {order_id} has no items")
    
    # Simulate inventory check
    for item in items:
        product_id = item.get('productId')
        quantity = item.get('quantity', 0)
        
        if quantity <= 0:
            raise ValueError(f"Invalid quantity for product {product_id}: {quantity}")
    
    # Return success result
    return {
        'orderId': order_id,
        'status': 'processed',
        'processedAt': datetime.utcnow().isoformat(),
        'totalValue': order_value,
        'itemCount': len(items)
    }

def send_processing_metrics(status: str, order_value: float) -> None:
    """
    Send custom metrics to CloudWatch for monitoring.
    
    Args:
        status: Processing status ('Success' or 'Failure')
        order_value: Value of the processed order
    """
    
    try:
        # Categorize order by value
        if order_value >= 1000:
            category = 'HighValue'
        elif order_value >= 100:
            category = 'MediumValue'
        else:
            category = 'LowValue'
        
        # Send metrics to CloudWatch
        cloudwatch.put_metric_data(
            Namespace='OrderProcessing/Main',
            MetricData=[
                {
                    'MetricName': 'ProcessedOrders',
                    'Value': 1,
                    'Unit': 'Count',
                    'Dimensions': [
                        {
                            'Name': 'Status',
                            'Value': status
                        },
                        {
                            'Name': 'OrderCategory',
                            'Value': category
                        }
                    ]
                },
                {
                    'MetricName': 'OrderValue',
                    'Value': order_value,
                    'Unit': 'None',
                    'Dimensions': [
                        {
                            'Name': 'Status',
                            'Value': status
                        }
                    ]
                }
            ]
        )
        
    except Exception as e:
        logger.warning(f"Failed to send metrics to CloudWatch: {str(e)}")
        # Don't fail the main processing for metrics issues