# Lambda function for URL redirection
# This function handles GET requests with short codes and redirects to original URLs
# Template variables: short_code_length = ${short_code_length}

import json
import boto3
import os
import logging
import re
from botocore.exceptions import ClientError

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize AWS services
dynamodb = boto3.resource('dynamodb')
table = dynamodb.Table(os.environ['TABLE_NAME'])

def lambda_handler(event, context):
    """
    Main Lambda handler for URL redirection
    
    Args:
        event: API Gateway event containing request details
        context: Lambda runtime context
        
    Returns:
        API Gateway response with redirect or error page
    """
    try:
        logger.info(f"Received event: {json.dumps(event, default=str)}")
        
        # Extract short code from path parameters
        short_code = extract_short_code(event)
        if not short_code:
            return create_error_response(
                400, 
                "Bad Request", 
                "Short code parameter is required"
            )
        
        # Validate short code format
        if not is_valid_short_code(short_code):
            return create_error_response(
                400, 
                "Bad Request", 
                "Invalid short code format"
            )
        
        # Lookup original URL in DynamoDB
        original_url = lookup_original_url(short_code)
        if not original_url:
            return create_error_response(
                404, 
                "Short URL Not Found", 
                "The requested short URL does not exist or has expired"
            )
        
        # Log successful redirect for analytics
        logger.info(f"Redirecting {short_code} to {original_url}")
        
        # Return redirect response
        return {
            'statusCode': 302,
            'headers': {
                'Location': original_url,
                'Cache-Control': 'no-cache, no-store, must-revalidate',
                'Pragma': 'no-cache',
                'Expires': '0'
            }
        }
        
    except Exception as e:
        logger.error(f"Unexpected error in redirect function: {str(e)}")
        return create_error_response(
            500, 
            "Internal Server Error", 
            "An unexpected error occurred while processing your request"
        )

def extract_short_code(event):
    """
    Extract short code from API Gateway path parameters
    
    Args:
        event: API Gateway event
        
    Returns:
        str: Short code or None if not found
    """
    try:
        path_parameters = event.get('pathParameters')
        if not path_parameters:
            return None
        
        return path_parameters.get('shortCode')
    except Exception as e:
        logger.error(f"Error extracting short code: {str(e)}")
        return None

def is_valid_short_code(short_code):
    """
    Validate short code format
    
    Args:
        short_code: Short code to validate
        
    Returns:
        bool: True if valid, False otherwise
    """
    if not short_code:
        return False
    
    expected_length = int(os.environ.get('SHORT_CODE_LENGTH', '${short_code_length}'))
    
    # Check length and alphanumeric characters only
    if len(short_code) != expected_length:
        return False
    
    # Allow only alphanumeric characters
    if not re.match(r'^[a-zA-Z0-9]+$', short_code):
        return False
    
    return True

def lookup_original_url(short_code):
    """
    Look up original URL from DynamoDB
    
    Args:
        short_code: Short code to look up
        
    Returns:
        str: Original URL or None if not found
    """
    try:
        response = table.get_item(
            Key={'shortCode': short_code},
            ProjectionExpression='originalUrl'  # Only retrieve what we need
        )
        
        if 'Item' in response:
            return response['Item'].get('originalUrl')
        else:
            logger.warning(f"Short code not found in database: {short_code}")
            return None
            
    except ClientError as e:
        error_code = e.response['Error']['Code']
        logger.error(f"DynamoDB error ({error_code}): {str(e)}")
        
        # Don't expose internal errors to users
        if error_code in ['ResourceNotFoundException', 'ValidationException']:
            return None
        else:
            # Re-raise for other errors to trigger 500 response
            raise e
    except Exception as e:
        logger.error(f"Unexpected error during URL lookup: {str(e)}")
        raise e

def create_error_response(status_code, title, message):
    """
    Create HTML error response
    
    Args:
        status_code: HTTP status code
        title: Error title
        message: Error message
        
    Returns:
        dict: API Gateway response with HTML error page
    """
    html_content = f"""
    <!DOCTYPE html>
    <html lang="en">
    <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>{status_code} - {title}</title>
        <style>
            body {{
                font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
                line-height: 1.6;
                color: #333;
                max-width: 600px;
                margin: 0 auto;
                padding: 20px;
                background-color: #f5f5f5;
            }}
            .error-container {{
                background: white;
                padding: 40px;
                border-radius: 8px;
                box-shadow: 0 2px 10px rgba(0,0,0,0.1);
                text-align: center;
            }}
            .error-code {{
                font-size: 4em;
                font-weight: bold;
                color: #e74c3c;
                margin: 0;
            }}
            .error-title {{
                font-size: 1.5em;
                margin: 10px 0;
                color: #2c3e50;
            }}
            .error-message {{
                font-size: 1em;
                color: #7f8c8d;
                margin: 20px 0;
            }}
            .back-link {{
                display: inline-block;
                margin-top: 20px;
                padding: 10px 20px;
                background-color: #3498db;
                color: white;
                text-decoration: none;
                border-radius: 4px;
                transition: background-color 0.3s;
            }}
            .back-link:hover {{
                background-color: #2980b9;
            }}
        </style>
    </head>
    <body>
        <div class="error-container">
            <div class="error-code">{status_code}</div>
            <div class="error-title">{title}</div>
            <div class="error-message">{message}</div>
            <a href="javascript:history.back()" class="back-link">Go Back</a>
        </div>
    </body>
    </html>
    """
    
    return {
        'statusCode': status_code,
        'headers': {
            'Content-Type': 'text/html; charset=utf-8',
            'Cache-Control': 'no-cache, no-store, must-revalidate',
            'Pragma': 'no-cache',
            'Expires': '0'
        },
        'body': html_content
    }