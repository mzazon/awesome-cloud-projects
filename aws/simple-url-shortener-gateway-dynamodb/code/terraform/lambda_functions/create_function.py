# Lambda function for creating short URLs
# This function handles POST requests to create new short URLs
# Template variables: short_code_length = ${short_code_length}

import json
import boto3
import string
import random
import os
import logging
from urllib.parse import urlparse
from botocore.exceptions import ClientError

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize AWS services
dynamodb = boto3.resource('dynamodb')
table = dynamodb.Table(os.environ['TABLE_NAME'])

def lambda_handler(event, context):
    """
    Main Lambda handler for creating short URLs
    
    Args:
        event: API Gateway event containing request details
        context: Lambda runtime context
        
    Returns:
        API Gateway response with short URL details or error
    """
    try:
        logger.info(f"Received event: {json.dumps(event, default=str)}")
        
        # Parse and validate request body
        if not event.get('body'):
            return create_error_response(400, 'Request body is required')
        
        try:
            body = json.loads(event['body'])
        except json.JSONDecodeError:
            return create_error_response(400, 'Invalid JSON in request body')
        
        original_url = body.get('url')
        
        # Validate URL presence
        if not original_url:
            return create_error_response(400, 'URL is required')
        
        # Validate URL format
        if not is_valid_url(original_url):
            return create_error_response(400, 'Invalid URL format')
        
        # Generate and store short code
        short_code = generate_unique_short_code()
        
        # Store URL mapping in DynamoDB
        try:
            store_url_mapping(short_code, original_url)
        except Exception as e:
            logger.error(f"Failed to store URL mapping: {str(e)}")
            return create_error_response(500, 'Failed to create short URL')
        
        # Construct response
        api_gateway_url = get_api_gateway_url(event)
        short_url = f"{api_gateway_url}/{short_code}"
        
        logger.info(f"Successfully created short URL: {short_code} -> {original_url}")
        
        return {
            'statusCode': 201,
            'headers': get_cors_headers(),
            'body': json.dumps({
                'shortCode': short_code,
                'shortUrl': short_url,
                'originalUrl': original_url,
                'message': 'Short URL created successfully'
            })
        }
        
    except Exception as e:
        logger.error(f"Unexpected error creating short URL: {str(e)}")
        return create_error_response(500, 'Internal server error')

def is_valid_url(url):
    """
    Validate URL format and scheme
    
    Args:
        url: URL string to validate
        
    Returns:
        bool: True if URL is valid, False otherwise
    """
    try:
        parsed_url = urlparse(url)
        # Check for valid scheme and netloc
        if not all([parsed_url.scheme, parsed_url.netloc]):
            return False
        # Ensure scheme is http or https
        if parsed_url.scheme not in ['http', 'https']:
            return False
        return True
    except Exception:
        return False

def generate_unique_short_code():
    """
    Generate a unique short code with collision handling
    
    Returns:
        str: Unique short code
        
    Raises:
        Exception: If unable to generate unique code after max retries
    """
    max_retries = 10
    short_code_length = int(os.environ.get('SHORT_CODE_LENGTH', '${short_code_length}'))
    
    for attempt in range(max_retries):
        # Generate random alphanumeric code
        short_code = ''.join(random.choices(
            string.ascii_letters + string.digits, 
            k=short_code_length
        ))
        
        # Check if code already exists
        try:
            response = table.get_item(Key={'shortCode': short_code})
            if 'Item' not in response:
                return short_code  # Code is unique
        except ClientError as e:
            logger.error(f"Error checking for existing short code: {str(e)}")
            # Continue trying with a new code
            continue
    
    raise Exception("Unable to generate unique short code after multiple attempts")

def store_url_mapping(short_code, original_url):
    """
    Store URL mapping in DynamoDB with conditional write
    
    Args:
        short_code: Generated short code
        original_url: Original URL to map
        
    Raises:
        Exception: If storage fails
    """
    try:
        # Use conditional write to prevent overwriting existing codes
        table.put_item(
            Item={
                'shortCode': short_code,
                'originalUrl': original_url,
                'createdAt': context.aws_request_id if 'context' in globals() else 'unknown',
                'ttl': None  # No expiration by default, can be extended later
            },
            ConditionExpression='attribute_not_exists(shortCode)'
        )
    except ClientError as e:
        if e.response['Error']['Code'] == 'ConditionalCheckFailedException':
            raise Exception("Short code collision detected")
        else:
            raise Exception(f"DynamoDB error: {str(e)}")

def get_api_gateway_url(event):
    """
    Construct API Gateway URL from event context
    
    Args:
        event: API Gateway event
        
    Returns:
        str: Base API Gateway URL
    """
    try:
        # Extract domain and stage from event
        domain = event['requestContext']['domainName']
        stage = event['requestContext']['stage']
        protocol = event['headers'].get('X-Forwarded-Proto', 'https')
        
        return f"{protocol}://{domain}/{stage}"
    except Exception:
        # Fallback to environment variable or default
        return os.environ.get('API_BASE_URL', 'https://your-api-gateway-url/prod')

def get_cors_headers():
    """
    Get CORS headers for API responses
    
    Returns:
        dict: CORS headers
    """
    return {
        'Content-Type': 'application/json',
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Headers': 'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token',
        'Access-Control-Allow-Methods': 'POST,OPTIONS'
    }

def create_error_response(status_code, message):
    """
    Create standardized error response
    
    Args:
        status_code: HTTP status code
        message: Error message
        
    Returns:
        dict: API Gateway response
    """
    return {
        'statusCode': status_code,
        'headers': get_cors_headers(),
        'body': json.dumps({
            'error': message,
            'statusCode': status_code
        })
    }