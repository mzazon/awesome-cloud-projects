"""
Newsletter Function for Email List Management System
Sends newsletters to all active subscribers with personalization and error handling
"""

import json
import boto3
import os
import logging
from botocore.exceptions import ClientError
from decimal import Decimal

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize AWS services
dynamodb = boto3.resource('dynamodb')
ses = boto3.client('ses')
table = dynamodb.Table('${table_name}')

# Configuration
SENDER_EMAIL = '${sender_email}'
MAX_SEND_RATE = 14  # SES default send rate (emails per second)

def lambda_handler(event, context):
    """
    Send newsletter to all active subscribers
    
    Expected input:
    {
        "subject": "Newsletter Subject",
        "message": "Newsletter content (supports HTML)",
        "is_html": true/false (optional, defaults to false)
    }
    
    Returns:
    {
        "statusCode": 200|400|500,
        "body": JSON string with sending statistics
    }
    """
    
    try:
        # Parse request body
        if 'body' in event:
            if isinstance(event['body'], str):
                body = json.loads(event['body'])
            else:
                body = event['body']
        else:
            body = event
        
        # Extract newsletter content
        subject = body.get('subject', 'Newsletter Update')
        message = body.get('message', 'Thank you for subscribing!')
        is_html = body.get('is_html', False)
        
        # Validate inputs
        if not subject.strip():
            return {
                'statusCode': 400,
                'headers': {
                    'Content-Type': 'application/json',
                    'Access-Control-Allow-Origin': '*'
                },
                'body': json.dumps({
                    'error': 'Subject is required',
                    'message': 'Newsletter subject cannot be empty'
                })
            }
        
        if not message.strip():
            return {
                'statusCode': 400,
                'headers': {
                    'Content-Type': 'application/json',
                    'Access-Control-Allow-Origin': '*'
                },
                'body': json.dumps({
                    'error': 'Message is required',
                    'message': 'Newsletter message cannot be empty'
                })
            }
        
        # Retrieve all active subscribers with pagination support
        subscribers = []
        last_evaluated_key = None
        
        while True:
            scan_kwargs = {
                'FilterExpression': '#status = :status',
                'ExpressionAttributeNames': {'#status': 'status'},
                'ExpressionAttributeValues': {':status': 'active'}
            }
            
            if last_evaluated_key:
                scan_kwargs['ExclusiveStartKey'] = last_evaluated_key
            
            response = table.scan(**scan_kwargs)
            subscribers.extend(response['Items'])
            
            last_evaluated_key = response.get('LastEvaluatedKey')
            if not last_evaluated_key:
                break
        
        logger.info(f"Found {len(subscribers)} active subscribers")
        
        if not subscribers:
            return {
                'statusCode': 200,
                'headers': {
                    'Content-Type': 'application/json',
                    'Access-Control-Allow-Origin': '*'
                },
                'body': json.dumps({
                    'message': 'No active subscribers found',
                    'sent_count': 0,
                    'failed_count': 0,
                    'total_subscribers': 0
                })
            }
        
        # Send emails to subscribers
        sent_count = 0
        failed_count = 0
        failed_emails = []
        
        for subscriber in subscribers:
            try:
                # Convert Decimal types to regular types for processing
                subscriber_email = str(subscriber['email'])
                subscriber_name = str(subscriber.get('name', 'Subscriber'))
                
                # Personalize message
                personalized_message = message.replace('{name}', subscriber_name)
                
                # Prepare email content
                email_body = {
                    'Text': {
                        'Data': f"Hello {subscriber_name},\n\n{personalized_message}\n\nBest regards,\nYour Newsletter Team",
                        'Charset': 'UTF-8'
                    }
                }
                
                # Add HTML version if requested
                if is_html:
                    html_content = f"""
                    <html>
                    <body>
                        <h2>Hello {subscriber_name},</h2>
                        <div>{personalized_message}</div>
                        <p>Best regards,<br>Your Newsletter Team</p>
                        <hr>
                        <small>
                            <a href="mailto:unsubscribe@example.com?subject=Unsubscribe&body=Please unsubscribe {subscriber_email}">
                                Unsubscribe
                            </a>
                        </small>
                    </body>
                    </html>
                    """
                    email_body['Html'] = {
                        'Data': html_content,
                        'Charset': 'UTF-8'
                    }
                
                # Send email via SES
                ses_response = ses.send_email(
                    Source=SENDER_EMAIL,
                    Destination={
                        'ToAddresses': [subscriber_email]
                    },
                    Message={
                        'Subject': {
                            'Data': subject,
                            'Charset': 'UTF-8'
                        },
                        'Body': email_body
                    },
                    # Add configuration set if available
                    # ConfigurationSetName='your-configuration-set'
                )
                
                sent_count += 1
                logger.info(f"Email sent successfully to {subscriber_email}, MessageId: {ses_response['MessageId']}")
                
            except ClientError as e:
                error_code = e.response['Error']['Code']
                error_message = e.response['Error']['Message']
                
                failed_count += 1
                failed_emails.append({
                    'email': subscriber_email,
                    'error': error_code,
                    'message': error_message
                })
                
                logger.error(f"Failed to send email to {subscriber_email}: {error_code} - {error_message}")
                
            except Exception as e:
                failed_count += 1
                failed_emails.append({
                    'email': subscriber_email,
                    'error': 'UnknownError',
                    'message': str(e)
                })
                
                logger.error(f"Unexpected error sending to {subscriber_email}: {str(e)}")
        
        # Prepare response
        response_body = {
            'message': f'Newsletter sent to {sent_count} subscribers',
            'sent_count': sent_count,
            'failed_count': failed_count,
            'total_subscribers': len(subscribers),
            'subject': subject,
            'delivery_rate': round((sent_count / len(subscribers)) * 100, 2) if subscribers else 0
        }
        
        # Include failed emails in response if any
        if failed_emails:
            response_body['failed_emails'] = failed_emails[:10]  # Limit to first 10 failures
            if len(failed_emails) > 10:
                response_body['additional_failures'] = len(failed_emails) - 10
        
        logger.info(f"Newsletter sending completed: {sent_count} sent, {failed_count} failed")
        
        return {
            'statusCode': 200,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps(response_body)
        }
        
    except json.JSONDecodeError as e:
        logger.error(f"JSON parsing error: {str(e)}")
        return {
            'statusCode': 400,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({
                'error': 'Invalid JSON',
                'message': 'Request body must be valid JSON'
            })
        }
        
    except Exception as e:
        logger.error(f"Unexpected error: {str(e)}")
        return {
            'statusCode': 500,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({
                'error': 'Internal server error',
                'message': 'An unexpected error occurred while sending newsletter'
            })
        }