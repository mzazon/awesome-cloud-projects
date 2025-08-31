"""
List Subscribers Function for Email List Management System
Provides administrative access to view all subscribers with pagination and filtering
"""

import json
import boto3
import os
import logging
from decimal import Decimal
from botocore.exceptions import ClientError

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize AWS services
dynamodb = boto3.resource('dynamodb')
table = dynamodb.Table('${table_name}')

def decimal_default(obj):
    """JSON serializer for objects not serializable by default json code"""
    if isinstance(obj, Decimal):
        return float(obj)
    raise TypeError

def lambda_handler(event, context):
    """
    List all subscribers with optional filtering and pagination
    
    Expected input (optional):
    {
        "status": "active|inactive|all" (optional, defaults to "all"),
        "limit": 100 (optional, max 1000),
        "last_evaluated_key": {...} (optional, for pagination)
    }
    
    Returns:
    {
        "statusCode": 200|400|500,
        "body": JSON string with subscribers list and metadata
    }
    """
    
    try:
        # Parse request body (GET requests might have empty body)
        if 'body' in event and event['body']:
            if isinstance(event['body'], str):
                body = json.loads(event['body'])
            else:
                body = event['body']
        else:
            # Check for query parameters (for API Gateway GET requests)
            body = event.get('queryStringParameters') or {}
        
        # Extract parameters with defaults
        status_filter = body.get('status', 'all').lower()
        limit = min(int(body.get('limit', 100)), 1000)  # Cap at 1000 items
        last_evaluated_key = body.get('last_evaluated_key')
        
        # Validate status filter
        valid_statuses = ['active', 'inactive', 'all']
        if status_filter not in valid_statuses:
            return {
                'statusCode': 400,
                'headers': {
                    'Content-Type': 'application/json',
                    'Access-Control-Allow-Origin': '*'
                },
                'body': json.dumps({
                    'error': 'Invalid status filter',
                    'message': f'Status must be one of: {", ".join(valid_statuses)}',
                    'valid_values': valid_statuses
                })
            }
        
        # Prepare scan parameters
        scan_kwargs = {
            'Limit': limit
        }
        
        # Add pagination support
        if last_evaluated_key:
            scan_kwargs['ExclusiveStartKey'] = last_evaluated_key
        
        # Add status filter if not 'all'
        if status_filter != 'all':
            scan_kwargs['FilterExpression'] = '#status = :status'
            scan_kwargs['ExpressionAttributeNames'] = {'#status': 'status'}
            scan_kwargs['ExpressionAttributeValues'] = {':status': status_filter}
        
        # Perform DynamoDB scan
        response = table.scan(**scan_kwargs)
        
        subscribers = response.get('Items', [])
        last_evaluated_key = response.get('LastEvaluatedKey')
        
        # Process subscribers data
        processed_subscribers = []
        for subscriber in subscribers:
            processed_subscriber = {}
            for key, value in subscriber.items():
                # Convert Decimal types for JSON serialization
                if isinstance(value, Decimal):
                    processed_subscriber[key] = float(value)
                else:
                    processed_subscriber[key] = value
            processed_subscribers.append(processed_subscriber)
        
        # Calculate statistics
        total_count = len(processed_subscribers)
        active_count = len([s for s in processed_subscribers if s.get('status') == 'active'])
        inactive_count = len([s for s in processed_subscribers if s.get('status') == 'inactive'])
        
        # Prepare response
        response_data = {
            'subscribers': processed_subscribers,
            'metadata': {
                'total_count': total_count,
                'active_count': active_count,
                'inactive_count': inactive_count,
                'status_filter': status_filter,
                'limit': limit,
                'has_more': last_evaluated_key is not None
            }
        }
        
        # Include pagination token if more results available
        if last_evaluated_key:
            response_data['pagination'] = {
                'last_evaluated_key': last_evaluated_key,
                'next_request_body': {
                    'status': status_filter,
                    'limit': limit,
                    'last_evaluated_key': last_evaluated_key
                }
            }
        
        logger.info(f"Retrieved {total_count} subscribers (filter: {status_filter})")
        
        return {
            'statusCode': 200,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps(response_data, default=decimal_default)
        }
        
    except ValueError as e:
        logger.error(f"Invalid parameter: {str(e)}")
        return {
            'statusCode': 400,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({
                'error': 'Invalid parameter',
                'message': 'Limit must be a valid number'
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
        
    except ClientError as e:
        error_code = e.response['Error']['Code']
        error_message = e.response['Error']['Message']
        
        logger.error(f"DynamoDB error: {error_code} - {error_message}")
        return {
            'statusCode': 500,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({
                'error': 'Database error',
                'message': 'Unable to retrieve subscribers list'
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
                'message': 'An unexpected error occurred while retrieving subscribers'
            })
        }