import json
import boto3
import time
import os
from datetime import datetime, timedelta
from decimal import Decimal
import hashlib
import random

dynamodb = boto3.resource('dynamodb')
cloudwatch = boto3.client('cloudwatch')
sqs = boto3.client('sqs')

def lambda_handler(event, context):
    """
    Process messages from SQS FIFO queue with ordering guarantees
    """
    processed_count = 0
    failed_count = 0
    
    for record in event['Records']:
        try:
            # Extract message details
            message_body = json.loads(record['body'])
            message_group_id = record['attributes']['MessageGroupId']
            message_dedup_id = record['attributes']['MessageDeduplicationId']
            receipt_handle = record['receiptHandle']
            
            print(f"Processing message: {message_dedup_id} in group: {message_group_id}")
            
            # Simulate business logic processing
            result = process_order_message(message_body, message_group_id, message_dedup_id)
            
            if result['success']:
                processed_count += 1
                
                # Publish custom metrics
                publish_processing_metrics(message_group_id, 'SUCCESS', result['processing_time'])
                
            else:
                failed_count += 1
                # Don't delete message - let it go to DLQ after max retries
                publish_processing_metrics(message_group_id, 'FAILURE', result['processing_time'])
                
                # For demonstration: simulate different failure scenarios
                if should_simulate_failure():
                    raise Exception(f"Simulated processing failure for message {message_dedup_id}")
            
        except Exception as e:
            failed_count += 1
            print(f"Error processing message: {str(e)}")
            
            # Publish error metrics
            publish_processing_metrics(
                record['attributes'].get('MessageGroupId', 'unknown'), 
                'ERROR', 
                0
            )
            
            # Re-raise to trigger DLQ behavior
            raise
    
    # Publish batch metrics
    cloudwatch.put_metric_data(
        Namespace='FIFO/MessageProcessing',
        MetricData=[
            {
                'MetricName': 'ProcessedMessages',
                'Value': processed_count,
                'Unit': 'Count',
                'Dimensions': [
                    {'Name': 'Environment', 'Value': 'Demo'}
                ]
            },
            {
                'MetricName': 'FailedMessages', 
                'Value': failed_count,
                'Unit': 'Count',
                'Dimensions': [
                    {'Name': 'Environment', 'Value': 'Demo'}
                ]
            }
        ]
    )
    
    return {
        'statusCode': 200,
        'processedCount': processed_count,
        'failedCount': failed_count
    }

def process_order_message(message_body, message_group_id, message_dedup_id):
    """
    Process individual order message with idempotency
    """
    start_time = time.time()
    
    try:
        # Extract order information
        order_id = message_body.get('orderId')
        order_type = message_body.get('orderType')
        amount = message_body.get('amount')
        timestamp = message_body.get('timestamp')
        
        if not all([order_id, order_type, amount]):
            raise ValueError("Missing required order fields")
        
        table = dynamodb.Table('${order_table_name}')
        
        # Check for duplicate processing (idempotency)
        try:
            existing_item = table.get_item(
                Key={'OrderId': order_id}
            )
            
            if 'Item' in existing_item:
                if existing_item['Item'].get('MessageDeduplicationId') == message_dedup_id:
                    print(f"Message {message_dedup_id} already processed for order {order_id}")
                    return {
                        'success': True, 
                        'processing_time': time.time() - start_time,
                        'duplicate': True
                    }
        except Exception as e:
            print(f"Error checking for duplicates: {str(e)}")
        
        # Validate order amount (business rule)
        if Decimal(str(amount)) < 0:
            raise ValueError(f"Invalid order amount: {amount}")
        
        # Simulate complex business logic
        time.sleep(random.uniform(0.1, 0.5))  # Simulate processing time
        
        # Store order state with message tracking
        table.put_item(
            Item={
                'OrderId': order_id,
                'OrderType': order_type,
                'Amount': Decimal(str(amount)),
                'MessageGroupId': message_group_id,
                'MessageDeduplicationId': message_dedup_id,
                'Status': 'PROCESSED',
                'ProcessedAt': datetime.utcnow().isoformat(),
                'ProcessingTimeMs': int((time.time() - start_time) * 1000),
                'OriginalTimestamp': timestamp
            }
        )
        
        return {
            'success': True, 
            'processing_time': time.time() - start_time,
            'duplicate': False
        }
        
    except Exception as e:
        print(f"Error processing order {message_body.get('orderId', 'unknown')}: {str(e)}")
        return {
            'success': False, 
            'processing_time': time.time() - start_time,
            'error': str(e)
        }

def publish_processing_metrics(message_group_id, status, processing_time):
    """
    Publish detailed processing metrics to CloudWatch
    """
    try:
        cloudwatch.put_metric_data(
            Namespace='FIFO/MessageProcessing',
            MetricData=[
                {
                    'MetricName': 'ProcessingTime',
                    'Value': processing_time * 1000,  # Convert to milliseconds
                    'Unit': 'Milliseconds',
                    'Dimensions': [
                        {'Name': 'MessageGroup', 'Value': message_group_id},
                        {'Name': 'Status', 'Value': status}
                    ]
                },
                {
                    'MetricName': 'MessageStatus',
                    'Value': 1,
                    'Unit': 'Count',
                    'Dimensions': [
                        {'Name': 'MessageGroup', 'Value': message_group_id},
                        {'Name': 'Status', 'Value': status}
                    ]
                }
            ]
        )
    except Exception as e:
        print(f"Error publishing metrics: {str(e)}")

def should_simulate_failure():
    """
    Simulate occasional processing failures for testing
    """
    # 10% chance of failure for demonstration
    return random.random() < 0.1