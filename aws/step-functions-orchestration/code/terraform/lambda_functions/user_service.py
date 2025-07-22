import json
import boto3
import random
import logging
import os

# Configure logging
logger = logging.getLogger()
logger.setLevel(os.environ.get('LOG_LEVEL', 'INFO'))

def lambda_handler(event, context):
    """
    User Service Lambda Function
    
    Handles user validation and profile retrieval for the microservices workflow.
    Validates user credentials and fetches user profile data needed for order processing.
    
    Args:
        event: Lambda event containing userId and request context
        context: Lambda context object
        
    Returns:
        dict: User data including userId, email, status, and creditScore
        
    Raises:
        Exception: When user ID is missing or invalid
    """
    
    logger.info(f"User Service invoked with event: {json.dumps(event)}")
    
    try:
        # Extract user ID from event
        user_id = event.get('userId')
        
        # Validate required input
        if not user_id:
            error_msg = "User ID is required"
            logger.error(error_msg)
            raise Exception(error_msg)
        
        logger.info(f"Processing user validation for user ID: {user_id}")
        
        # Mock user validation - In production, this would query a user database
        # Generate consistent mock data based on user ID for testing
        random.seed(hash(user_id) % (10**8))
        
        user_data = {
            'userId': user_id,
            'email': f'user{user_id}@example.com',
            'status': 'active',
            'creditScore': random.randint(600, 850),
            'accountType': random.choice(['premium', 'standard', 'basic']),
            'joinDate': '2023-01-15',
            'verified': True
        }
        
        logger.info(f"User validation successful for user ID: {user_id}")
        logger.debug(f"User data retrieved: {json.dumps(user_data)}")
        
        # Return successful response
        response = {
            'statusCode': 200,
            'body': json.dumps(user_data),
            'headers': {
                'Content-Type': 'application/json'
            }
        }
        
        logger.info("User Service completed successfully")
        return response
        
    except Exception as e:
        error_msg = f"User Service error: {str(e)}"
        logger.error(error_msg)
        
        # Return error response
        return {
            'statusCode': 400,
            'body': json.dumps({
                'error': error_msg,
                'userId': event.get('userId')
            }),
            'headers': {
                'Content-Type': 'application/json'
            }
        }