import json
import boto3
import logging
import os
from datetime import datetime

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize AWS clients
ses_client = boto3.client('ses')

def lambda_handler(event, context):
    """
    Process events from EventBridge and send email notifications through SES.
    
    Supports multiple event types:
    - Email Notification Request
    - Priority Alert
    - Scheduled Reports
    """
    try:
        logger.info(f"Processing event: {json.dumps(event)}")
        
        # Handle different event sources
        if 'source' in event:
            # EventBridge event
            event_detail = event.get('detail', {})
            event_source = event.get('source', 'unknown')
            event_type = event.get('detail-type', 'Unknown Event')
        else:
            # Direct Lambda invocation or other sources
            event_detail = event
            event_source = 'direct.invocation'
            event_type = 'Direct Invocation'
        
        # Extract email configuration from event
        email_config = event_detail.get('emailConfig', {})
        recipient = email_config.get('recipient', '${default_recipient}')
        subject = email_config.get('subject', f'Notification: {event_type}')
        message = event_detail.get('message', 'No message provided')
        title = event_detail.get('title', event_type)
        
        # Get configuration from environment variables
        sender_email = os.environ.get('SENDER_EMAIL', '${sender_email}')
        template_name = os.environ.get('TEMPLATE_NAME', '${template_name}')
        
        # Prepare template data
        template_data = {
            'subject': subject,
            'title': title,
            'message': message,
            'timestamp': datetime.now().isoformat(),
            'source': event_source
        }
        
        # Send templated email
        response = ses_client.send_templated_email(
            Source=sender_email,
            Destination={'ToAddresses': [recipient]},
            Template=template_name,
            TemplateData=json.dumps(template_data)
        )
        
        logger.info(f"Email sent successfully: {response['MessageId']}")
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Email sent successfully',
                'messageId': response['MessageId'],
                'recipient': recipient,
                'subject': subject,
                'eventType': event_type
            })
        }
        
    except Exception as e:
        logger.error(f"Error processing email: {str(e)}")
        logger.error(f"Event details: {json.dumps(event)}")
        
        # Re-raise to trigger EventBridge retry mechanism
        raise e