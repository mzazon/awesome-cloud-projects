"""
Subscribe Function for Email List Management System
Handles new subscriber registrations with validation and duplicate prevention
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
    Handle subscriber registration requests
    
    Expected input:
    {
        "email": "user@example.com",
        "name": "User Name" (optional)
    }
    
    Returns:
    {
        "statusCode": 200|400|409|500,
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
        
        # Extract and validate email
        email = body.get('email', '').lower().strip()
        name = body.get('name', 'Subscriber').strip()
        
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
        
        # Validate name
        if not name or len(name.strip()) == 0:
            name = 'Subscriber'
        
        # Limit name length
        if len(name) > 100:
            name = name[:100]
        
        # Generate subscription timestamp
        subscription_date = datetime.datetime.now().isoformat()
        
        # Prepare subscriber record
        subscriber_item = {
            'email': email,
            'name': name,
            'subscribed_date': subscription_date,
            'status': 'active',
            'subscription_source': 'api',
            'created_at': subscription_date,
            'updated_at': subscription_date
        }
        
        # Add subscriber to DynamoDB with condition to prevent duplicates
        response = table.put_item(
            Item=subscriber_item,
            ConditionExpression='attribute_not_exists(email)'
        )
        
        logger.info(f"Successfully subscribed: {email}")
        
        return {
            'statusCode': 200,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({
                'message': f'Successfully subscribed {email}',
                'email': email,
                'name': name,
                'subscribed_date': subscription_date,
                'status': 'active'
            })
        }
        
    except ClientError as e:
        error_code = e.response['Error']['Code']
        
        if error_code == 'ConditionalCheckFailedException':
            logger.warning(f"Duplicate subscription attempt: {email}")
            return {
                'statusCode': 409,
                'headers': {
                    'Content-Type': 'application/json',
                    'Access-Control-Allow-Origin': '*'
                },
                'body': json.dumps({
                    'error': 'Email already subscribed',
                    'message': f'The email {email} is already subscribed to the list',
                    'email': email
                })
            }
        else:
            logger.error(f"DynamoDB error: {str(e)}")
            return {
                'statusCode': 500,
                'headers': {
                    'Content-Type': 'application/json',
                    'Access-Control-Allow-Origin': '*'
                },
                'body': json.dumps({
                    'error': 'Database error',
                    'message': 'Unable to process subscription request'
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