import json
import boto3
import os
from datetime import datetime
import logging

# Configure logging
logger = logging.getLogger()
logger.setLevel(os.environ.get('LOG_LEVEL', 'INFO'))

def lambda_handler(event, context):
    """
    Process anomaly detection events and send notifications.
    
    This function receives anomaly events, enriches them with metadata,
    publishes metrics to CloudWatch, and sends notifications via SNS.
    """
    # Initialize AWS clients
    cloudwatch = boto3.client('cloudwatch')
    sns = boto3.client('sns')
    
    try:
        # Process each record in the event
        for record in event.get('Records', []):
            # Parse the anomaly data
            message_body = record.get('body', '{}')
            
            try:
                anomaly_data = json.loads(message_body)
            except json.JSONDecodeError:
                # Handle plain text messages
                anomaly_data = {'message': message_body}
            
            # Extract anomaly details
            user_id = anomaly_data.get('userId', 'unknown')
            amount = anomaly_data.get('amount', 0)
            threshold = anomaly_data.get('threshold', 0)
            timestamp = anomaly_data.get('timestamp', int(datetime.utcnow().timestamp() * 1000))
            
            # Determine anomaly severity
            severity = determine_severity(amount, threshold)
            
            # Create enriched notification message
            notification_message = create_notification_message(
                user_id, amount, threshold, severity, timestamp
            )
            
            # Send custom metric to CloudWatch
            try:
                cloudwatch.put_metric_data(
                    Namespace=os.environ.get('CLOUDWATCH_NAMESPACE', 'AnomalyDetection'),
                    MetricData=[
                        {
                            'MetricName': 'AnomalyCount',
                            'Value': 1,
                            'Unit': 'Count',
                            'Timestamp': datetime.utcnow(),
                            'Dimensions': [
                                {
                                    'Name': 'Severity',
                                    'Value': severity
                                },
                                {
                                    'Name': 'UserId',
                                    'Value': user_id
                                }
                            ]
                        },
                        {
                            'MetricName': 'AnomalyAmount',
                            'Value': float(amount),
                            'Unit': 'None',
                            'Timestamp': datetime.utcnow(),
                            'Dimensions': [
                                {
                                    'Name': 'Severity',
                                    'Value': severity
                                }
                            ]
                        }
                    ]
                )
                logger.info(f"CloudWatch metrics published for user {user_id}")
            except Exception as e:
                logger.error(f"Failed to publish CloudWatch metrics: {str(e)}")
            
            # Send notification via SNS
            try:
                sns.publish(
                    TopicArn="${sns_topic_arn}",
                    Message=notification_message,
                    Subject=f'[{severity.upper()}] Transaction Anomaly Alert - User {user_id}',
                    MessageAttributes={
                        'severity': {
                            'DataType': 'String',
                            'StringValue': severity
                        },
                        'userId': {
                            'DataType': 'String',
                            'StringValue': user_id
                        },
                        'amount': {
                            'DataType': 'Number',
                            'StringValue': str(amount)
                        }
                    }
                )
                logger.info(f"SNS notification sent for anomaly: {user_id}")
            except Exception as e:
                logger.error(f"Failed to send SNS notification: {str(e)}")
                raise
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Anomalies processed successfully',
                'processedRecords': len(event.get('Records', []))
            })
        }
        
    except Exception as e:
        logger.error(f"Error processing anomaly event: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': 'Failed to process anomaly event',
                'details': str(e)
            })
        }

def determine_severity(amount, threshold):
    """Determine the severity level of the anomaly."""
    if amount > threshold * 5:
        return 'critical'
    elif amount > threshold * 3:
        return 'high'
    elif amount > threshold * 2:
        return 'medium'
    else:
        return 'low'

def create_notification_message(user_id, amount, threshold, severity, timestamp):
    """Create a formatted notification message."""
    formatted_time = datetime.fromtimestamp(timestamp / 1000).strftime('%Y-%m-%d %H:%M:%S UTC')
    
    message = f"""
🚨 ANOMALY DETECTED - {severity.upper()} SEVERITY

📊 Transaction Details:
   • User ID: {user_id}
   • Amount: ${amount:,.2f}
   • Threshold: ${threshold:,.2f}
   • Deviation: {((amount / threshold - 1) * 100):.1f}% above normal
   • Timestamp: {formatted_time}

⚠️  Recommended Actions:
   • Review transaction history for user {user_id}
   • Verify merchant and transaction details
   • Consider temporary account restrictions if severity is HIGH or CRITICAL
   • Monitor for additional anomalous activity

🔗 Investigation Links:
   • CloudWatch Dashboard: [View Metrics]
   • Transaction Logs: [View Details]
   • User Profile: [Review Account]

This alert was generated by the real-time anomaly detection system.
For questions or to modify alert settings, contact your security team.
"""
    return message.strip()