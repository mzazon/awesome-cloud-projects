# AWS Data Exchange Notification Handler Lambda Function
# This function processes Data Exchange events and sends notifications

import json
import boto3
import os
import logging
from datetime import datetime

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize AWS clients
sns = boto3.client('sns')

def lambda_handler(event, context):
    """
    Lambda handler for processing AWS Data Exchange events and sending notifications.
    
    Args:
        event: EventBridge event containing Data Exchange event details
        context: Lambda execution context
        
    Returns:
        dict: Response with status code and message
    """
    
    try:
        logger.info(f"Received Data Exchange event: {json.dumps(event, default=str)}")
        
        # Extract event details
        detail = event.get('detail', {})
        event_name = detail.get('eventName', 'Unknown')
        dataset_id = detail.get('dataSetId', 'Unknown')
        revision_id = detail.get('revisionId', 'Unknown')
        asset_id = detail.get('assetId', 'Unknown')
        event_source = event.get('source', 'aws.dataexchange')
        event_time = event.get('time', datetime.utcnow().isoformat())
        
        # Get SNS topic ARN from environment variable
        sns_topic_arn = os.environ.get('SNS_TOPIC_ARN', '${sns_topic_arn}')
        
        # Create notification message
        message = create_notification_message(
            event_name=event_name,
            dataset_id=dataset_id,
            revision_id=revision_id,
            asset_id=asset_id,
            event_source=event_source,
            event_time=event_time,
            event_detail=detail
        )
        
        # Send notification if SNS topic is configured
        if sns_topic_arn and sns_topic_arn != '':
            send_sns_notification(sns_topic_arn, message, event_name)
        else:
            logger.info("No SNS topic configured, logging notification only")
            logger.info(f"Notification message: {message}")
        
        # Log event for CloudWatch monitoring
        log_event_metrics(event_name, dataset_id, detail)
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Notification processed successfully',
                'event_name': event_name,
                'dataset_id': dataset_id,
                'timestamp': event_time
            })
        }
        
    except Exception as e:
        logger.error(f"Error processing Data Exchange event: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': str(e),
                'message': 'Failed to process notification'
            })
        }

def create_notification_message(event_name, dataset_id, revision_id, asset_id, 
                              event_source, event_time, event_detail):
    """
    Create a formatted notification message for the Data Exchange event.
    
    Args:
        event_name: Name of the Data Exchange event
        dataset_id: ID of the affected dataset
        revision_id: ID of the affected revision
        asset_id: ID of the affected asset
        event_source: Source of the event
        event_time: Timestamp of the event
        event_detail: Additional event details
        
    Returns:
        str: Formatted notification message
    """
    
    # Determine event severity and type
    event_type = determine_event_type(event_name)
    severity = determine_event_severity(event_name, event_detail)
    
    # Create base message
    message_lines = [
        f"🔔 AWS Data Exchange Event Notification",
        f"",
        f"Event: {event_name}",
        f"Type: {event_type}",
        f"Severity: {severity}",
        f"Timestamp: {event_time}",
        f"Source: {event_source}",
        f"",
        f"Resource Details:",
        f"• Dataset ID: {dataset_id}",
        f"• Revision ID: {revision_id}",
        f"• Asset ID: {asset_id}",
        f"",
    ]
    
    # Add event-specific details
    if event_name == "AssetImportStateChange":
        state = event_detail.get('state', 'Unknown')
        message_lines.extend([
            f"Import Details:",
            f"• State: {state}",
            f"• Asset Type: {event_detail.get('assetType', 'Unknown')}",
        ])
        
        if state == "FAILED":
            error_details = event_detail.get('errorDetails', {})
            message_lines.extend([
                f"• Error Code: {error_details.get('code', 'Unknown')}",
                f"• Error Message: {error_details.get('message', 'Unknown')}",
            ])
    
    elif event_name == "RevisionStateChange":
        state = event_detail.get('state', 'Unknown')
        message_lines.extend([
            f"Revision Details:",
            f"• State: {state}",
            f"• Comment: {event_detail.get('comment', 'No comment')}",
        ])
    
    # Add troubleshooting information
    message_lines.extend([
        f"",
        f"Troubleshooting:",
        f"• Check AWS Data Exchange console for detailed information",
        f"• Review CloudWatch logs for Lambda function execution",
        f"• Verify IAM permissions for Data Exchange operations",
        f"",
        f"Full Event Details:",
        f"{json.dumps(event_detail, indent=2)}"
    ])
    
    return "\n".join(message_lines)

def determine_event_type(event_name):
    """
    Determine the type of Data Exchange event.
    
    Args:
        event_name: Name of the event
        
    Returns:
        str: Event type classification
    """
    
    if "Import" in event_name:
        return "Asset Import"
    elif "Export" in event_name:
        return "Asset Export"
    elif "Revision" in event_name:
        return "Revision Management"
    elif "Grant" in event_name:
        return "Data Grant"
    else:
        return "General"

def determine_event_severity(event_name, event_detail):
    """
    Determine the severity level of the event.
    
    Args:
        event_name: Name of the event
        event_detail: Event detail information
        
    Returns:
        str: Severity level (INFO, WARNING, ERROR)
    """
    
    state = event_detail.get('state', '').upper()
    
    if state in ['FAILED', 'ERROR']:
        return "ERROR"
    elif state in ['PENDING', 'IN_PROGRESS']:
        return "INFO"
    elif state in ['COMPLETED', 'SUCCEEDED']:
        return "INFO"
    else:
        return "WARNING"

def send_sns_notification(topic_arn, message, event_name):
    """
    Send notification to SNS topic.
    
    Args:
        topic_arn: ARN of the SNS topic
        message: Notification message
        event_name: Name of the Data Exchange event
    """
    
    try:
        subject = f"Data Exchange Event: {event_name}"
        
        response = sns.publish(
            TopicArn=topic_arn,
            Message=message,
            Subject=subject
        )
        
        logger.info(f"SNS notification sent successfully. MessageId: {response['MessageId']}")
        
    except Exception as e:
        logger.error(f"Failed to send SNS notification: {str(e)}")
        raise

def log_event_metrics(event_name, dataset_id, event_detail):
    """
    Log custom metrics for CloudWatch monitoring.
    
    Args:
        event_name: Name of the Data Exchange event
        dataset_id: ID of the affected dataset
        event_detail: Event detail information
    """
    
    try:
        # Create CloudWatch client
        cloudwatch = boto3.client('cloudwatch')
        
        # Determine metric values
        state = event_detail.get('state', 'Unknown')
        
        # Log general event metric
        cloudwatch.put_metric_data(
            Namespace='DataExchange/Events',
            MetricData=[
                {
                    'MetricName': 'EventCount',
                    'Dimensions': [
                        {
                            'Name': 'EventName',
                            'Value': event_name
                        },
                        {
                            'Name': 'DataSetId',
                            'Value': dataset_id
                        }
                    ],
                    'Value': 1,
                    'Unit': 'Count'
                }
            ]
        )
        
        # Log state-specific metrics
        if state in ['FAILED', 'ERROR']:
            cloudwatch.put_metric_data(
                Namespace='DataExchange/Events',
                MetricData=[
                    {
                        'MetricName': 'FailedEvents',
                        'Dimensions': [
                            {
                                'Name': 'EventName',
                                'Value': event_name
                            }
                        ],
                        'Value': 1,
                        'Unit': 'Count'
                    }
                ]
            )
        
        logger.info(f"Custom metrics logged for event: {event_name}")
        
    except Exception as e:
        logger.warning(f"Failed to log custom metrics: {str(e)}")
        # Don't raise exception as this is not critical for notification functionality