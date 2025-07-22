import json
import logging
import os
from datetime import datetime

# Configure logging
logger = logging.getLogger()
logger.setLevel(os.getenv('LOG_LEVEL', 'INFO'))

def lambda_handler(event, context):
    """
    Process email notification messages from SQS
    
    This function demonstrates email notification processing.
    In production, integrate with Amazon SES, SendGrid, or other email service.
    """
    
    processed_messages = []
    
    logger.info(f"Processing {len(event['Records'])} message(s)")
    
    for record in event['Records']:
        try:
            # Parse message body
            message_body = json.loads(record['body'])
            
            # Extract notification details
            subject = message_body.get('subject', 'Notification')
            message = message_body.get('message', '')
            recipient = message_body.get('recipient', '${test_email}')
            priority = message_body.get('priority', 'normal')
            timestamp = message_body.get('timestamp', datetime.utcnow().isoformat())
            
            # Log email processing (replace with actual email service integration)
            logger.info(f"Processing email notification:")
            logger.info(f"  Recipient: {recipient}")
            logger.info(f"  Subject: {subject}")
            logger.info(f"  Priority: {priority}")
            logger.info(f"  Timestamp: {timestamp}")
            logger.info(f"  Message: {message}")
            
            # TODO: Integrate with email service
            # Example integrations:
            # - Amazon SES: Use boto3 SES client to send email
            # - SendGrid: Use SendGrid Python SDK
            # - Mailgun: Use Mailgun API
            # - SMTP: Use smtplib for custom SMTP servers
            
            # Simulate successful email sending
            success = send_email_notification(recipient, subject, message, priority)
            
            if success:
                processed_messages.append({
                    'messageId': record['messageId'],
                    'status': 'success',
                    'recipient': recipient,
                    'subject': subject,
                    'timestamp': timestamp
                })
                logger.info(f"✅ Email sent successfully to {recipient}")
            else:
                logger.error(f"❌ Failed to send email to {recipient}")
                # Message will be retried or sent to DLQ based on SQS configuration
                raise Exception(f"Failed to send email to {recipient}")
                
        except Exception as e:
            logger.error(f"Error processing message {record['messageId']}: {str(e)}")
            # Re-raise to trigger SQS retry mechanism
            raise e
    
    return {
        'statusCode': 200,
        'body': json.dumps({
            'processed': len(processed_messages),
            'messages': processed_messages,
            'timestamp': datetime.utcnow().isoformat()
        })
    }

def send_email_notification(recipient, subject, message, priority):
    """
    Send email notification using your preferred email service
    
    Args:
        recipient (str): Email address to send to
        subject (str): Email subject
        message (str): Email message content
        priority (str): Priority level (high, normal, low)
    
    Returns:
        bool: True if successful, False otherwise
    """
    
    # Example implementation using Amazon SES
    # Uncomment and modify for production use
    
    # import boto3
    # from botocore.exceptions import ClientError
    # 
    # ses_client = boto3.client('ses')
    # 
    # try:
    #     response = ses_client.send_email(
    #         Source=os.getenv('FROM_EMAIL', 'noreply@example.com'),
    #         Destination={
    #             'ToAddresses': [recipient]
    #         },
    #         Message={
    #             'Subject': {
    #                 'Data': f"[{priority.upper()}] {subject}",
    #                 'Charset': 'UTF-8'
    #             },
    #             'Body': {
    #                 'Text': {
    #                     'Data': message,
    #                     'Charset': 'UTF-8'
    #                 }
    #             }
    #         }
    #     )
    #     logger.info(f"SES MessageId: {response['MessageId']}")
    #     return True
    # except ClientError as e:
    #     logger.error(f"SES Error: {e.response['Error']['Message']}")
    #     return False
    
    # For demo purposes, simulate successful email sending
    logger.info(f"📧 Simulated email sent to {recipient}")
    logger.info(f"   Subject: [{priority.upper()}] {subject}")
    logger.info(f"   Message: {message}")
    
    return True

def format_email_content(subject, message, priority, timestamp):
    """
    Format email content with metadata
    
    Args:
        subject (str): Email subject
        message (str): Email message
        priority (str): Priority level
        timestamp (str): Timestamp of the notification
    
    Returns:
        tuple: (formatted_subject, formatted_message)
    """
    
    priority_prefix = {
        'high': '🔴 [HIGH]',
        'normal': '🟡 [NORMAL]',
        'low': '🟢 [LOW]'
    }.get(priority.lower(), '[NORMAL]')
    
    formatted_subject = f"{priority_prefix} {subject}"
    
    formatted_message = f"""
{message}

---
Notification Details:
- Priority: {priority.upper()}
- Timestamp: {timestamp}
- Project: {os.getenv('PROJECT_NAME', 'Notification System')}
- Environment: {os.getenv('ENVIRONMENT', 'dev')}
"""
    
    return formatted_subject, formatted_message