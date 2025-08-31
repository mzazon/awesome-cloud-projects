"""
Unsubscribe Function for Email List Management System
Handles subscriber unsubscription requests with validation and status updates
"""

import json
import boto3
import datetime
import os
import logging
from botocore.exceptions import ClientError

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize AWS services
dynamodb = boto3.resource('dynamodb')
table = dynamodb.Table('${table_name}')

def lambda_handler(event, context):
    """
    Handle subscriber unsubscription requests
    
    Expected input:
    {
        "email": "user@example.com",
        "reason": "Optional unsubscribe reason"
    }
    
    Returns:
    {
        "statusCode": 200|400|404|500,
        "body": JSON string with result
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
        
        # Handle GET request with query parameters (for email links)
        if 'queryStringParameters' in event and event['queryStringParameters']:
            query_params = event['queryStringParameters'] or {}
            email = query_params.get('email', '').lower().strip()
            reason = query_params.get('reason', 'User requested via link')
        else:
            # Extract email and reason from body
            email = body.get('email', '').lower().strip()
            reason = body.get('reason', 'User requested')
        
        # Validate email format
        if not email or '@' not in email or '.' not in email.split('@')[1]:
            logger.error(f"Invalid email format: {email}")
            return {
                'statusCode': 400,
                'headers': {
                    'Content-Type': 'application/json',
                    'Access-Control-Allow-Origin': '*'
                },
                'body': json.dumps({
                    'error': 'Valid email address is required',
                    'message': 'Please provide a valid email address'
                })
            }
        
        # Check if subscriber exists
        try:
            response = table.get_item(Key={'email': email})
            
            if 'Item' not in response:
                logger.warning(f"Unsubscribe attempt for non-existent email: {email}")
                return {
                    'statusCode': 404,
                    'headers': {
                        'Content-Type': 'application/json',
                        'Access-Control-Allow-Origin': '*'
                    },
                    'body': json.dumps({
                        'error': 'Email not found',
                        'message': f'The email {email} is not in our subscriber list',
                        'email': email
                    })
                }
            
            subscriber = response['Item']
            current_status = subscriber.get('status', 'unknown')
            
            # Check if already unsubscribed
            if current_status == 'inactive':
                logger.info(f"Email already unsubscribed: {email}")
                return {
                    'statusCode': 200,
                    'headers': {
                        'Content-Type': 'application/json',
                        'Access-Control-Allow-Origin': '*'
                    },
                    'body': json.dumps({
                        'message': f'Email {email} is already unsubscribed',
                        'email': email,
                        'status': 'inactive',
                        'previously_unsubscribed': True
                    })
                }
            
        except ClientError as e:
            logger.error(f"Error retrieving subscriber: {str(e)}")
            return {
                'statusCode': 500,
                'headers': {
                    'Content-Type': 'application/json',
                    'Access-Control-Allow-Origin': '*'
                },
                'body': json.dumps({
                    'error': 'Database error',
                    'message': 'Unable to process unsubscribe request'
                })
            }
        
        # Update subscriber status to inactive
        unsubscribe_date = datetime.datetime.now().isoformat()
        
        try:
            # Update the subscriber record
            update_response = table.update_item(
                Key={'email': email},
                UpdateExpression='SET #status = :status, unsubscribed_date = :unsubscribe_date, unsubscribe_reason = :reason, updated_at = :updated_at',
                ExpressionAttributeNames={
                    '#status': 'status'
                },
                ExpressionAttributeValues={
                    ':status': 'inactive',
                    ':unsubscribe_date': unsubscribe_date,
                    ':reason': reason[:500] if reason else 'No reason provided',  # Limit reason length
                    ':updated_at': unsubscribe_date
                },
                ConditionExpression='attribute_exists(email)',  # Ensure record exists
                ReturnValues='ALL_NEW'
            )
            
            updated_subscriber = update_response['Attributes']
            
            logger.info(f"Successfully unsubscribed: {email}")
            
            # Prepare response with updated subscriber info
            response_data = {
                'message': f'Successfully unsubscribed {email}',
                'email': email,
                'status': 'inactive',
                'unsubscribed_date': unsubscribe_date,
                'reason': reason,
                'previous_status': current_status
            }
            
            # Handle GET request (likely from email link) with HTML response
            if event.get('httpMethod') == 'GET' or 'queryStringParameters' in event:
                html_response = f"""
                <!DOCTYPE html>
                <html>
                <head>
                    <title>Unsubscribed Successfully</title>
                    <style>
                        body {{ font-family: Arial, sans-serif; max-width: 600px; margin: 50px auto; padding: 20px; }}
                        .success {{ color: #28a745; background: #d4edda; padding: 15px; border-radius: 5px; }}
                        .info {{ color: #0c5460; background: #bee5eb; padding: 10px; border-radius: 5px; margin-top: 20px; }}
                    </style>
                </head>
                <body>
                    <div class="success">
                        <h2>✅ Successfully Unsubscribed</h2>
                        <p>The email address <strong>{email}</strong> has been removed from our mailing list.</p>
                    </div>
                    <div class="info">
                        <p><strong>Unsubscribed on:</strong> {unsubscribe_date}</p>
                        <p><strong>Reason:</strong> {reason}</p>
                    </div>
                    <p>You will no longer receive newsletters from us. If this was a mistake, please contact our support team.</p>
                </body>
                </html>
                """
                
                return {
                    'statusCode': 200,
                    'headers': {
                        'Content-Type': 'text/html',
                        'Access-Control-Allow-Origin': '*'
                    },
                    'body': html_response
                }
            
            # JSON response for API calls
            return {
                'statusCode': 200,
                'headers': {
                    'Content-Type': 'application/json',
                    'Access-Control-Allow-Origin': '*'
                },
                'body': json.dumps(response_data)
            }
            
        except ClientError as e:
            error_code = e.response['Error']['Code']
            
            if error_code == 'ConditionalCheckFailedException':
                logger.error(f"Subscriber record no longer exists: {email}")
                return {
                    'statusCode': 404,
                    'headers': {
                        'Content-Type': 'application/json',
                        'Access-Control-Allow-Origin': '*'
                    },
                    'body': json.dumps({
                        'error': 'Subscriber not found',
                        'message': 'The subscriber record no longer exists'
                    })
                }
            else:
                logger.error(f"DynamoDB update error: {str(e)}")
                return {
                    'statusCode': 500,
                    'headers': {
                        'Content-Type': 'application/json',
                        'Access-Control-Allow-Origin': '*'
                    },
                    'body': json.dumps({
                        'error': 'Database error',
                        'message': 'Unable to process unsubscribe request'
                    })
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
                'message': 'An unexpected error occurred'
            })
        }