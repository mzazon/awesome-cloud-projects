import json
import logging
import os
from datetime import datetime

# Configure logging
logger = logging.getLogger()
logger.setLevel(os.getenv('LOG_LEVEL', 'INFO'))

def lambda_handler(event, context):
    """
    Process messages from the Dead Letter Queue
    
    This function handles messages that failed processing multiple times.
    It logs failed messages for investigation and can implement custom
    alerting or retry logic.
    """
    
    processed_messages = []
    
    logger.info(f"Processing {len(event['Records'])} failed message(s) from DLQ")
    
    for record in event['Records']:
        try:
            # Parse message body
            message_body = json.loads(record['body'])
            
            # Extract message details
            subject = message_body.get('subject', 'Unknown')
            message = message_body.get('message', '')
            notification_type = message_body.get('notification_type', 'unknown')
            recipient = message_body.get('recipient', 'unknown')
            webhook_url = message_body.get('webhook_url', '')
            priority = message_body.get('priority', 'normal')
            original_timestamp = message_body.get('timestamp', 'unknown')
            
            # Log failure details
            logger.error(f"🚨 FAILED MESSAGE ALERT:")
            logger.error(f"   Message ID: {record['messageId']}")
            logger.error(f"   Notification Type: {notification_type}")
            logger.error(f"   Subject: {subject}")
            logger.error(f"   Priority: {priority}")
            logger.error(f"   Original Timestamp: {original_timestamp}")
            logger.error(f"   Processing Timestamp: {datetime.utcnow().isoformat()}")
            
            if notification_type == 'email':
                logger.error(f"   Email Recipient: {recipient}")
            elif notification_type == 'webhook':
                logger.error(f"   Webhook URL: {webhook_url}")
            
            logger.error(f"   Message Content: {message}")
            
            # Create alert payload
            alert_payload = {
                'alert_type': 'notification_failure',
                'message_id': record['messageId'],
                'notification_type': notification_type,
                'subject': subject,
                'priority': priority,
                'original_timestamp': original_timestamp,
                'failure_timestamp': datetime.utcnow().isoformat(),
                'recipient': recipient,
                'webhook_url': webhook_url,
                'message_content': message,
                'environment': os.getenv('ENVIRONMENT', 'dev'),
                'project': os.getenv('PROJECT_NAME', 'notification-system')
            }
            
            # Send alert (implement your preferred alerting mechanism)
            alert_sent = send_failure_alert(alert_payload)
            
            # Archive failed message for investigation
            archived = archive_failed_message(alert_payload)
            
            processed_messages.append({
                'messageId': record['messageId'],
                'status': 'processed',
                'notification_type': notification_type,
                'priority': priority,
                'alert_sent': alert_sent,
                'archived': archived,
                'timestamp': datetime.utcnow().isoformat()
            })
            
            logger.info(f"✅ Failed message processed and logged: {record['messageId']}")
            
        except Exception as e:
            logger.error(f"Error processing DLQ message {record['messageId']}: {str(e)}")
            # For DLQ processing, we don't want to re-raise exceptions
            # as this would cause the message to be retried indefinitely
            processed_messages.append({
                'messageId': record['messageId'],
                'status': 'error',
                'error': str(e),
                'timestamp': datetime.utcnow().isoformat()
            })
    
    return {
        'statusCode': 200,
        'body': json.dumps({
            'processed': len(processed_messages),
            'messages': processed_messages,
            'timestamp': datetime.utcnow().isoformat()
        })
    }

def send_failure_alert(alert_payload):
    """
    Send alert about failed notification
    
    Args:
        alert_payload (dict): Alert information
    
    Returns:
        bool: True if alert sent successfully
    """
    
    try:
        # Option 1: Send to CloudWatch as a custom metric
        import boto3
        cloudwatch = boto3.client('cloudwatch')
        
        cloudwatch.put_metric_data(
            Namespace='NotificationSystem/Failures',
            MetricData=[
                {
                    'MetricName': 'FailedNotifications',
                    'Value': 1,
                    'Unit': 'Count',
                    'Dimensions': [
                        {
                            'Name': 'NotificationType',
                            'Value': alert_payload['notification_type']
                        },
                        {
                            'Name': 'Priority',
                            'Value': alert_payload['priority']
                        },
                        {
                            'Name': 'Environment',
                            'Value': alert_payload['environment']
                        }
                    ]
                }
            ]
        )
        
        logger.info("📊 Failure metric sent to CloudWatch")
        
        # Option 2: Send alert to another SNS topic for ops team
        # sns = boto3.client('sns')
        # alert_topic_arn = os.getenv('ALERT_SNS_TOPIC_ARN')
        # if alert_topic_arn:
        #     sns.publish(
        #         TopicArn=alert_topic_arn,
        #         Subject=f"🚨 Notification System Alert - {alert_payload['priority'].upper()} Priority",
        #         Message=json.dumps(alert_payload, indent=2)
        #     )
        #     logger.info(f"🚨 Alert sent to SNS topic: {alert_topic_arn}")
        
        # Option 3: Send to external service (PagerDuty, Slack, etc.)
        # implement_external_alerting(alert_payload)
        
        return True
        
    except Exception as e:
        logger.error(f"Failed to send alert: {str(e)}")
        return False

def archive_failed_message(alert_payload):
    """
    Archive failed message for investigation
    
    Args:
        alert_payload (dict): Failed message information
    
    Returns:
        bool: True if archived successfully
    """
    
    try:
        # Option 1: Store in S3 for later analysis
        import boto3
        s3 = boto3.client('s3')
        
        bucket_name = os.getenv('FAILED_MESSAGES_BUCKET')
        if bucket_name:
            key = f"failed-notifications/{alert_payload['environment']}/{datetime.utcnow().strftime('%Y/%m/%d')}/{alert_payload['message_id']}.json"
            
            s3.put_object(
                Bucket=bucket_name,
                Key=key,
                Body=json.dumps(alert_payload, indent=2),
                ContentType='application/json'
            )
            
            logger.info(f"📁 Failed message archived to S3: s3://{bucket_name}/{key}")
            return True
        
        # Option 2: Store in DynamoDB for easier querying
        # dynamodb = boto3.resource('dynamodb')
        # table_name = os.getenv('FAILED_MESSAGES_TABLE')
        # if table_name:
        #     table = dynamodb.Table(table_name)
        #     table.put_item(Item=alert_payload)
        #     logger.info(f"📁 Failed message archived to DynamoDB: {table_name}")
        #     return True
        
        # Fallback: Just log the failure
        logger.warning("No archive storage configured, message logged only")
        return False
        
    except Exception as e:
        logger.error(f"Failed to archive message: {str(e)}")
        return False

def analyze_failure_patterns(alert_payload):
    """
    Analyze failure patterns to identify systemic issues
    
    Args:
        alert_payload (dict): Failed message information
    
    Returns:
        dict: Analysis results
    """
    
    analysis = {
        'failure_category': categorize_failure(alert_payload),
        'recommended_action': get_recommended_action(alert_payload),
        'escalation_needed': should_escalate(alert_payload)
    }
    
    logger.info(f"📈 Failure analysis: {analysis}")
    return analysis

def categorize_failure(alert_payload):
    """
    Categorize the type of failure
    
    Args:
        alert_payload (dict): Failed message information
    
    Returns:
        str: Failure category
    """
    
    notification_type = alert_payload['notification_type']
    
    if notification_type == 'email':
        return 'email_delivery_failure'
    elif notification_type == 'webhook':
        return 'webhook_delivery_failure'
    elif notification_type == 'sms':
        return 'sms_delivery_failure'
    else:
        return 'unknown_failure'

def get_recommended_action(alert_payload):
    """
    Get recommended action based on failure type
    
    Args:
        alert_payload (dict): Failed message information
    
    Returns:
        str: Recommended action
    """
    
    failure_category = categorize_failure(alert_payload)
    priority = alert_payload['priority']
    
    if failure_category == 'email_delivery_failure':
        return 'Check email service configuration and recipient validity'
    elif failure_category == 'webhook_delivery_failure':
        return 'Verify webhook endpoint availability and authentication'
    elif failure_category == 'sms_delivery_failure':
        return 'Check SMS service configuration and phone number validity'
    else:
        return 'Investigate message format and processing logic'

def should_escalate(alert_payload):
    """
    Determine if failure should be escalated
    
    Args:
        alert_payload (dict): Failed message information
    
    Returns:
        bool: True if escalation is needed
    """
    
    priority = alert_payload['priority']
    notification_type = alert_payload['notification_type']
    
    # Escalate high priority failures immediately
    if priority == 'high':
        return True
    
    # Add logic for escalation based on failure patterns
    # This could include checking failure rates, specific recipients, etc.
    
    return False