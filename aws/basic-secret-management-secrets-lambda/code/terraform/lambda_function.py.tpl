# lambda_function.py.tpl
# AWS Lambda function template for retrieving secrets from AWS Secrets Manager
# This function demonstrates the use of the AWS Parameters and Secrets Lambda Extension
# for optimized secret retrieval with caching

import json
import urllib.request
import urllib.error
import os
import logging

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# AWS Parameters and Secrets Lambda Extension configuration
SECRETS_EXTENSION_HTTP_PORT = "2773"
SECRETS_EXTENSION_SERVER_PORT = os.environ.get(
    'PARAMETERS_SECRETS_EXTENSION_HTTP_PORT', 
    SECRETS_EXTENSION_HTTP_PORT
)

def get_secret(secret_name):
    """
    Retrieve secret using AWS Parameters and Secrets Lambda Extension
    
    This function uses the extension's HTTP interface for optimized performance:
    - Local caching reduces API calls to Secrets Manager
    - HTTP interface is faster than SDK calls
    - Automatic retry and error handling
    
    Args:
        secret_name (str): Name or ARN of the secret to retrieve
        
    Returns:
        dict: Secret data from Secrets Manager
        
    Raises:
        Exception: If secret retrieval fails
    """
    secrets_extension_endpoint = (
        f"http://localhost:{SECRETS_EXTENSION_SERVER_PORT}"
        f"/secretsmanager/get?secretId={secret_name}"
    )
    
    # Add authentication header for the extension
    headers = {
        'X-Aws-Parameters-Secrets-Token': os.environ.get('AWS_SESSION_TOKEN', '')
    }
    
    try:
        logger.info(f"Retrieving secret: {secret_name}")
        req = urllib.request.Request(
            secrets_extension_endpoint, 
            headers=headers
        )
        
        with urllib.request.urlopen(req, timeout=10) as response:
            secret_data = response.read().decode('utf-8')
            logger.info("Successfully retrieved secret from extension")
            return json.loads(secret_data)
            
    except urllib.error.HTTPError as e:
        error_msg = f"HTTP error {e.code} retrieving secret: {e.reason}"
        logger.error(error_msg)
        raise Exception(error_msg)
        
    except urllib.error.URLError as e:
        error_msg = f"URL error retrieving secret: {e.reason}"
        logger.error(error_msg)
        raise Exception(error_msg)
        
    except json.JSONDecodeError as e:
        error_msg = f"Error parsing secret JSON: {e}"
        logger.error(error_msg)
        raise Exception(error_msg)
        
    except Exception as e:
        error_msg = f"Unexpected error in get_secret: {e}"
        logger.error(error_msg)
        raise Exception(error_msg)

def lambda_handler(event, context):
    """
    Main Lambda function handler
    
    This function demonstrates:
    - Retrieving secrets using the AWS Parameters and Secrets Extension
    - Parsing JSON secret values
    - Secure handling of sensitive data (password not returned in response)
    - Proper error handling and logging
    - Performance optimization through extension caching
    
    Args:
        event (dict): Lambda event data
        context (object): Lambda context object
        
    Returns:
        dict: HTTP response with secret information (excluding sensitive values)
    """
    try:
        # Get secret name from environment variable (injected by Terraform)
        secret_name = "${secret_name}"
        
        if not secret_name:
            error_msg = "Secret name not configured"
            logger.error(error_msg)
            return {
                'statusCode': 500,
                'headers': {
                    'Content-Type': 'application/json'
                },
                'body': json.dumps({
                    'error': 'Configuration error',
                    'message': error_msg
                })
            }
        
        # Retrieve secret using the extension
        logger.info(f"Processing request to retrieve secret: {secret_name}")
        secret_response = get_secret(secret_name)
        
        # Parse the secret JSON
        secret_value = json.loads(secret_response['SecretString'])
        
        # Extract non-sensitive information for response
        db_host = secret_value.get('database_host', 'Not found')
        db_port = secret_value.get('database_port', 'Not found')
        db_name = secret_value.get('database_name', 'Not found')
        username = secret_value.get('username', 'Not found')
        
        logger.info(f"Successfully processed secret for database: {db_name}")
        
        # Return success response (excluding password for security)
        return {
            'statusCode': 200,
            'headers': {
                'Content-Type': 'application/json'
            },
            'body': json.dumps({
                'message': 'Secret retrieved successfully',
                'secret_name': secret_name,
                'database_info': {
                    'host': db_host,
                    'port': db_port,
                    'database': db_name,
                    'username': username
                },
                'extension_info': {
                    'cache_enabled': os.environ.get('PARAMETERS_SECRETS_EXTENSION_CACHE_ENABLED', 'true'),
                    'cache_size': os.environ.get('PARAMETERS_SECRETS_EXTENSION_CACHE_SIZE', '1000'),
                    'http_port': SECRETS_EXTENSION_SERVER_PORT
                },
                'note': 'Password retrieved but not displayed for security',
                'timestamp': context.aws_request_id,
                'function_version': context.function_version
            })
        }
        
    except Exception as e:
        error_msg = f"Error in lambda_handler: {str(e)}"
        logger.error(error_msg)
        
        return {
            'statusCode': 500,
            'headers': {
                'Content-Type': 'application/json'
            },
            'body': json.dumps({
                'error': 'Internal server error',
                'message': 'Failed to retrieve secret',
                'details': str(e),
                'request_id': context.aws_request_id
            })
        }

# Health check function for monitoring
def health_check():
    """
    Simple health check to verify extension availability
    
    Returns:
        bool: True if extension is responding, False otherwise
    """
    try:
        # Simple health check endpoint
        health_endpoint = f"http://localhost:{SECRETS_EXTENSION_SERVER_PORT}/health"
        req = urllib.request.Request(health_endpoint)
        
        with urllib.request.urlopen(req, timeout=5) as response:
            return response.getcode() == 200
            
    except Exception:
        return False