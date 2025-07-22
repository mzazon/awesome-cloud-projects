"""
Lambda function for CloudWatch Evidently feature flag evaluation demonstration.

This function demonstrates how to integrate with Amazon CloudWatch Evidently
to evaluate feature flags in a serverless environment. It provides safe
defaults and proper error handling for production use.

Environment Variables:
    PROJECT_NAME: Name of the Evidently project
    FEATURE_NAME: Name of the feature flag to evaluate
    AWS_REGION: AWS region for the Evidently service
"""

import json
import boto3
import os
import logging
from typing import Dict, Any

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize AWS clients outside the handler for connection reuse
evidently = boto3.client('evidently')

def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Lambda handler for evaluating feature flags using CloudWatch Evidently.
    
    Args:
        event: Lambda event containing user information
        context: Lambda runtime context
        
    Returns:
        Dict containing feature evaluation results and user information
    """
    
    # Extract configuration from environment variables
    project_name = os.environ.get('PROJECT_NAME')
    feature_name = os.environ.get('FEATURE_NAME', 'new-checkout-flow')
    
    # Extract user information from event with safe defaults
    user_id = event.get('userId', f'anonymous-user-{context.aws_request_id[:8]}')
    user_attributes = event.get('userAttributes', {})
    
    # Add request metadata for better tracking
    request_context = {
        'requestId': context.aws_request_id,
        'timestamp': context.get_remaining_time_in_millis(),
        'functionName': context.function_name
    }
    
    logger.info(f"Evaluating feature '{feature_name}' for user '{user_id}' in project '{project_name}'")
    
    try:
        # Evaluate feature flag for the specified user
        response = evidently.evaluate_feature(
            project=project_name,
            feature=feature_name,
            entityId=user_id,
            entityAttributes=user_attributes
        )
        
        # Extract evaluation results
        variation = response.get('variation', 'unknown')
        feature_enabled = variation == 'enabled'
        evaluation_reason = response.get('reason', 'default')
        
        # Log successful evaluation for monitoring and debugging
        logger.info(
            f"Feature evaluation successful - User: {user_id}, "
            f"Variation: {variation}, Enabled: {feature_enabled}, "
            f"Reason: {evaluation_reason}"
        )
        
        # Return successful response with detailed information
        return {
            'statusCode': 200,
            'headers': {
                'Content-Type': 'application/json',
                'X-Request-ID': context.aws_request_id
            },
            'body': json.dumps({
                'success': True,
                'userId': user_id,
                'featureEnabled': feature_enabled,
                'variation': variation,
                'reason': evaluation_reason,
                'featureName': feature_name,
                'projectName': project_name,
                'requestContext': request_context,
                'evaluationDetails': {
                    'evaluationTime': response.get('details', {}).get('evaluationTime'),
                    'entityId': response.get('details', {}).get('entityId')
                }
            }, indent=2)
        }
        
    except evidently.exceptions.ResourceNotFoundException as e:
        # Handle case where project or feature doesn't exist
        error_message = f"Evidently resource not found: {str(e)}"
        logger.error(f"Resource not found - {error_message}")
        
        return {
            'statusCode': 404,
            'headers': {
                'Content-Type': 'application/json',
                'X-Request-ID': context.aws_request_id
            },
            'body': json.dumps({
                'success': False,
                'error': 'Resource not found',
                'message': error_message,
                'userId': user_id,
                'featureEnabled': False,  # Safe default
                'variation': 'disabled',   # Safe default
                'reason': 'error-fallback'
            }, indent=2)
        }
        
    except evidently.exceptions.AccessDeniedException as e:
        # Handle insufficient permissions
        error_message = f"Access denied to Evidently: {str(e)}"
        logger.error(f"Access denied - {error_message}")
        
        return {
            'statusCode': 403,
            'headers': {
                'Content-Type': 'application/json',
                'X-Request-ID': context.aws_request_id
            },
            'body': json.dumps({
                'success': False,
                'error': 'Access denied',
                'message': error_message,
                'userId': user_id,
                'featureEnabled': False,  # Safe default
                'variation': 'disabled',   # Safe default
                'reason': 'error-fallback'
            }, indent=2)
        }
        
    except Exception as e:
        # Handle any other unexpected errors with safe defaults
        error_message = f"Unexpected error during feature evaluation: {str(e)}"
        logger.error(f"Feature evaluation failed - {error_message}")
        
        return {
            'statusCode': 500,
            'headers': {
                'Content-Type': 'application/json',
                'X-Request-ID': context.aws_request_id
            },
            'body': json.dumps({
                'success': False,
                'error': 'Internal server error',
                'message': 'Feature evaluation failed',
                'userId': user_id,
                'featureEnabled': False,  # Safe default - always disable on error
                'variation': 'disabled',   # Safe default
                'reason': 'error-fallback',
                'requestContext': request_context
            }, indent=2)
        }


def health_check() -> Dict[str, Any]:
    """
    Simple health check function for monitoring and debugging.
    
    Returns:
        Dict containing service health information
    """
    try:
        # Verify environment variables are set
        project_name = os.environ.get('PROJECT_NAME')
        feature_name = os.environ.get('FEATURE_NAME')
        
        if not project_name:
            return {'status': 'unhealthy', 'reason': 'PROJECT_NAME not set'}
        
        if not feature_name:
            return {'status': 'unhealthy', 'reason': 'FEATURE_NAME not set'}
        
        # Test Evidently connectivity (optional)
        try:
            evidently.get_project(project=project_name)
            return {
                'status': 'healthy',
                'projectName': project_name,
                'featureName': feature_name,
                'evidently': 'connected'
            }
        except Exception as e:
            return {
                'status': 'degraded',
                'reason': f'Evidently connection failed: {str(e)}',
                'projectName': project_name,
                'featureName': feature_name
            }
            
    except Exception as e:
        return {'status': 'unhealthy', 'reason': f'Health check failed: {str(e)}'}