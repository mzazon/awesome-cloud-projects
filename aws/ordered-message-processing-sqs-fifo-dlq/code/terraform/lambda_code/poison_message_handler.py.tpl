import json
import boto3
import time
import os
from datetime import datetime
import uuid

s3 = boto3.client('s3')
sns = boto3.client('sns')
sqs = boto3.client('sqs')
cloudwatch = boto3.client('cloudwatch')

def lambda_handler(event, context):
    """
    Handle poison messages from dead letter queue
    """
    processed_count = 0
    
    for record in event['Records']:
        try:
            # Extract message details
            message_body = json.loads(record['body'])
            message_group_id = record['attributes'].get('MessageGroupId', 'unknown')
            message_dedup_id = record['attributes'].get('MessageDeduplicationId', str(uuid.uuid4()))
            
            print(f"Processing poison message: {message_dedup_id} in group: {message_group_id}")
            
            # Analyze the poison message
            analysis_result = analyze_poison_message(message_body, record)
            
            # Archive the poison message to S3
            archive_key = archive_poison_message(message_body, record, analysis_result)
            
            # Send alert for critical poison messages
            if analysis_result['severity'] == 'CRITICAL':
                send_poison_message_alert(message_body, analysis_result, archive_key)
            
            # Attempt automated recovery if possible
            if analysis_result['recoverable']:
                recovery_result = attempt_message_recovery(message_body, message_group_id)
                if recovery_result['success']:
                    print(f"Successfully recovered message {message_dedup_id}")
            
            processed_count += 1
            
            # Publish metrics
            publish_poison_metrics(message_group_id, analysis_result)
            
        except Exception as e:
            print(f"Error handling poison message: {str(e)}")
            # Continue processing other messages
    
    return {
        'statusCode': 200,
        'processedCount': processed_count
    }

def analyze_poison_message(message_body, record):
    """
    Analyze poison message to determine cause and recovery options
    """
    analysis = {
        'severity': 'MEDIUM',
        'recoverable': False,
        'failure_reason': 'unknown',
        'analysis_timestamp': datetime.utcnow().isoformat()
    }
    
    try:
        # Check for common failure patterns
        
        # Missing required fields
        required_fields = ['orderId', 'orderType', 'amount']
        missing_fields = [field for field in required_fields if field not in message_body]
        
        if missing_fields:
            analysis['failure_reason'] = f"missing_fields: {', '.join(missing_fields)}"
            analysis['severity'] = 'HIGH'
            analysis['recoverable'] = False
        
        # Invalid data types or values
        elif 'amount' in message_body:
            try:
                amount = float(message_body['amount'])
                if amount < 0:
                    analysis['failure_reason'] = 'negative_amount'
                    analysis['severity'] = 'MEDIUM'
                    analysis['recoverable'] = True  # Could be corrected
            except (ValueError, TypeError):
                analysis['failure_reason'] = 'invalid_amount_format'
                analysis['severity'] = 'HIGH'
                analysis['recoverable'] = False
        
        # Check message attributes for processing history
        approximate_receive_count = int(record.get('attributes', {}).get('ApproximateReceiveCount', 0))
        if approximate_receive_count > 5:
            analysis['severity'] = 'CRITICAL'
            analysis['failure_reason'] = f'excessive_retries: {approximate_receive_count}'
        
        # Check for malformed JSON or encoding issues
        if not isinstance(message_body, dict):
            analysis['failure_reason'] = 'malformed_json'
            analysis['severity'] = 'HIGH'
            analysis['recoverable'] = False
        
    except Exception as e:
        analysis['failure_reason'] = f'analysis_error: {str(e)}'
        analysis['severity'] = 'CRITICAL'
    
    return analysis

def archive_poison_message(message_body, record, analysis):
    """
    Archive poison message to S3 for investigation
    """
    try:
        timestamp = datetime.utcnow()
        archive_key = f"poison-messages/{timestamp.strftime('%Y/%m/%d')}/{timestamp.strftime('%H%M%S')}-{uuid.uuid4()}.json"
        
        archive_data = {
            'originalMessage': message_body,
            'sqsRecord': {
                'messageId': record.get('messageId'),
                'receiptHandle': record.get('receiptHandle'),
                'messageAttributes': record.get('messageAttributes', {}),
                'attributes': record.get('attributes', {})
            },
            'analysis': analysis,
            'archivedAt': timestamp.isoformat()
        }
        
        s3.put_object(
            Bucket='${archive_bucket_name}',
            Key=archive_key,
            Body=json.dumps(archive_data, indent=2),
            ContentType='application/json',
            Metadata={
                'severity': analysis['severity'],
                'failure-reason': analysis['failure_reason'][:256],  # Truncate if too long
                'message-group-id': record['attributes'].get('MessageGroupId', 'unknown')
            }
        )
        
        print(f"Archived poison message to: s3://${archive_bucket_name}/{archive_key}")
        return archive_key
        
    except Exception as e:
        print(f"Error archiving poison message: {str(e)}")
        return None

def send_poison_message_alert(message_body, analysis, archive_key):
    """
    Send SNS alert for critical poison messages
    """
    try:
        alert_message = {
            'severity': analysis['severity'],
            'failure_reason': analysis['failure_reason'],
            'order_id': message_body.get('orderId', 'unknown'),
            'archive_location': f"s3://${archive_bucket_name}/{archive_key}" if archive_key else 'failed_to_archive',
            'timestamp': datetime.utcnow().isoformat(),
            'requires_investigation': True
        }
        
        sns.publish(
            TopicArn='${sns_topic_arn}',
            Subject=f"CRITICAL: Poison Message Detected - {analysis['failure_reason']}",
            Message=json.dumps(alert_message, indent=2)
        )
        
        print(f"Sent poison message alert for order {message_body.get('orderId', 'unknown')}")
        
    except Exception as e:
        print(f"Error sending poison message alert: {str(e)}")

def attempt_message_recovery(message_body, message_group_id):
    """
    Attempt automated recovery for recoverable poison messages
    """
    try:
        # Example recovery: fix negative amounts by taking absolute value
        if 'amount' in message_body and float(message_body['amount']) < 0:
            
            # Create corrected message
            corrected_message = message_body.copy()
            corrected_message['amount'] = abs(float(message_body['amount']))
            corrected_message['recovery_applied'] = 'negative_amount_correction'
            corrected_message['original_amount'] = message_body['amount']
            
            # Send corrected message back to main queue
            response = sqs.send_message(
                QueueUrl='${main_queue_url}',
                MessageBody=json.dumps(corrected_message),
                MessageGroupId=message_group_id,
                MessageDeduplicationId=f"recovered-{uuid.uuid4()}"
            )
            
            return {
                'success': True,
                'recovery_type': 'negative_amount_correction',
                'new_message_id': response['MessageId']
            }
        
        return {'success': False, 'reason': 'no_recovery_strategy'}
        
    except Exception as e:
        print(f"Error attempting message recovery: {str(e)}")
        return {'success': False, 'reason': str(e)}

def publish_poison_metrics(message_group_id, analysis):
    """
    Publish poison message metrics to CloudWatch
    """
    try:
        cloudwatch.put_metric_data(
            Namespace='FIFO/PoisonMessages',
            MetricData=[
                {
                    'MetricName': 'PoisonMessageCount',
                    'Value': 1,
                    'Unit': 'Count',
                    'Dimensions': [
                        {'Name': 'MessageGroup', 'Value': message_group_id},
                        {'Name': 'Severity', 'Value': analysis['severity']},
                        {'Name': 'FailureReason', 'Value': analysis['failure_reason'][:255]}
                    ]
                },
                {
                    'MetricName': 'RecoverableMessages',
                    'Value': 1 if analysis['recoverable'] else 0,
                    'Unit': 'Count',
                    'Dimensions': [
                        {'Name': 'MessageGroup', 'Value': message_group_id}
                    ]
                }
            ]
        )
    except Exception as e:
        print(f"Error publishing poison metrics: {str(e)}")