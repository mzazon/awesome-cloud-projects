import json
import base64
import boto3
import time
import os
import uuid
from datetime import datetime

# Initialize AWS clients
dynamodb = boto3.resource('dynamodb')
table = dynamodb.Table('${dynamodb_table_name}')

cloudwatch = boto3.client('cloudwatch')
sqs = boto3.client('sqs')

def process_event(event_data):
    """
    Process a single event and return enriched results.
    
    Args:
        event_data (dict): Raw event data from Kinesis
        
    Returns:
        dict: Processed and enriched event data
    """
    # Extract required fields with defaults
    user_id = event_data.get('userId', 'unknown')
    event_type = event_data.get('eventType', 'unknown')
    product_id = event_data.get('productId', 'unknown')
    timestamp = int(event_data.get('timestamp', int(time.time() * 1000)))
    session_id = event_data.get('sessionId', str(uuid.uuid4()))
    
    # Business logic: calculate event score based on type
    event_scores = {
        'view': 1,
        'add_to_cart': 5,
        'purchase': 10,
        'wishlist': 3,
        'share': 2,
        'review': 8
    }
    
    event_score = event_scores.get(event_type, 1)
    
    # Generate business insights
    action_map = {
        'view': 'viewed',
        'add_to_cart': 'added to cart',
        'purchase': 'purchased',
        'wishlist': 'added to wishlist',
        'share': 'shared',
        'review': 'reviewed'
    }
    
    action = action_map.get(event_type, 'interacted with')
    insight = f"User {user_id} {action} product {product_id}"
    
    # Calculate user engagement score (simple example)
    engagement_level = 'low'
    if event_score >= 8:
        engagement_level = 'high'
    elif event_score >= 5:
        engagement_level = 'medium'
    
    # Data enrichment: add processing metadata and business context
    processed_data = {
        'userId': user_id,
        'eventTimestamp': timestamp,
        'eventType': event_type,
        'productId': product_id,
        'sessionId': session_id,
        'eventScore': event_score,
        'engagementLevel': engagement_level,
        'insight': insight,
        'processedAt': int(time.time() * 1000),
        'processingLatency': int(time.time() * 1000) - timestamp,
        'recordId': str(uuid.uuid4()),
        'version': '1.0',
        # Include original event data for audit purposes
        'originalEvent': event_data
    }
    
    return processed_data

def lambda_handler(event, context):
    """
    Main Lambda handler function for processing Kinesis stream records.
    
    Args:
        event (dict): Lambda event containing Kinesis records
        context (object): Lambda context object
        
    Returns:
        dict: Processing summary with counts and status
    """
    processed_count = 0
    failed_count = 0
    start_time = time.time()
    
    print(f"Processing batch of {len(event.get('Records', []))} records")
    
    # Process each record in the batch
    for record in event.get('Records', []):
        try:
            # Decode and parse the Kinesis record data
            # Kinesis data is base64 encoded
            payload = base64.b64decode(record['kinesis']['data']).decode('utf-8')
            event_data = json.loads(payload)
            
            # Validate required fields
            if not event_data.get('userId') or not event_data.get('eventType'):
                raise ValueError("Missing required fields: userId or eventType")
            
            # Process the event and enrich the data
            processed_data = process_event(event_data)
            
            # Store result in DynamoDB with error handling
            try:
                table.put_item(
                    Item=processed_data,
                    ConditionExpression='attribute_not_exists(recordId)'  # Prevent duplicates
                )
                processed_count += 1
                
                # Log successful processing (sample 10% for cost optimization)
                if processed_count % 10 == 0:
                    print(f"Successfully processed event for user {processed_data['userId']}")
                
            except dynamodb.meta.client.exceptions.ConditionalCheckFailedException:
                print(f"Duplicate record detected and skipped: {processed_data['recordId']}")
                processed_count += 1
                
        except Exception as e:
            failed_count += 1
            error_message = str(e)
            print(f"Error processing record: {error_message}")
            
            # Send failed record to Dead Letter Queue for later analysis
            try:
                dlq_message = {
                    'error': error_message,
                    'record_data': record['kinesis']['data'],
                    'partition_key': record['kinesis']['partitionKey'],
                    'sequence_number': record['kinesis']['sequenceNumber'],
                    'timestamp': datetime.utcnow().isoformat(),
                    'function_name': context.function_name,
                    'function_version': context.function_version,
                    'request_id': context.aws_request_id
                }
                
                sqs.send_message(
                    QueueUrl='${dlq_queue_url}',
                    MessageBody=json.dumps(dlq_message),
                    MessageAttributes={
                        'ErrorType': {
                            'StringValue': type(e).__name__,
                            'DataType': 'String'
                        },
                        'ProcessingTimestamp': {
                            'StringValue': datetime.utcnow().isoformat(),
                            'DataType': 'String'
                        }
                    }
                )
                print(f"Sent failed record to DLQ")
                
            except Exception as dlq_error:
                print(f"Error sending to DLQ: {str(dlq_error)}")
    
    # Calculate processing metrics
    processing_duration = time.time() - start_time
    total_records = processed_count + failed_count
    success_rate = (processed_count / total_records * 100) if total_records > 0 else 0
    
    # Send custom metrics to CloudWatch for monitoring and alerting
    try:
        metric_data = [
            {
                'MetricName': 'ProcessedEvents',
                'Value': processed_count,
                'Unit': 'Count',
                'Dimensions': [
                    {
                        'Name': 'FunctionName',
                        'Value': context.function_name
                    }
                ]
            },
            {
                'MetricName': 'FailedEvents',
                'Value': failed_count,
                'Unit': 'Count',
                'Dimensions': [
                    {
                        'Name': 'FunctionName',
                        'Value': context.function_name
                    }
                ]
            },
            {
                'MetricName': 'ProcessingDuration',
                'Value': processing_duration * 1000,  # Convert to milliseconds
                'Unit': 'Milliseconds',
                'Dimensions': [
                    {
                        'Name': 'FunctionName',
                        'Value': context.function_name
                    }
                ]
            },
            {
                'MetricName': 'SuccessRate',
                'Value': success_rate,
                'Unit': 'Percent',
                'Dimensions': [
                    {
                        'Name': 'FunctionName',
                        'Value': context.function_name
                    }
                ]
            },
            {
                'MetricName': 'BatchSize',
                'Value': total_records,
                'Unit': 'Count',
                'Dimensions': [
                    {
                        'Name': 'FunctionName',
                        'Value': context.function_name
                    }
                ]
            }
        ]
        
        cloudwatch.put_metric_data(
            Namespace='RetailEventProcessing',
            MetricData=metric_data
        )
        
    except Exception as metric_error:
        print(f"Error publishing metrics: {str(metric_error)}")
    
    # Log processing summary
    print(f"Processing complete - Success: {processed_count}, Failed: {failed_count}, "
          f"Duration: {processing_duration:.2f}s, Success Rate: {success_rate:.1f}%")
    
    # Return processing summary
    return {
        'statusCode': 200,
        'processed': processed_count,
        'failed': failed_count,
        'total': total_records,
        'success_rate': success_rate,
        'processing_duration_ms': processing_duration * 1000,
        'function_name': context.function_name,
        'request_id': context.aws_request_id
    }