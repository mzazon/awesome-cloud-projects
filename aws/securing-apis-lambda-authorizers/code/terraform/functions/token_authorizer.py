import json
import re

def lambda_handler(event, context):
    """
    Token-based authorizer that validates Bearer tokens
    """
    print(f"Token Authorizer Event: {json.dumps(event)}")
    
    # Extract token from event
    token = event.get('authorizationToken', '')
    method_arn = event.get('methodArn', '')
    
    # Validate token format (Bearer <token>)
    if not token.startswith('Bearer '):
        raise Exception('Unauthorized')
    
    # Extract actual token
    actual_token = token.replace('Bearer ', '')
    
    # Validate token (simplified validation)
    # In production, validate JWT signature, expiration, etc.
    valid_tokens = ${valid_tokens}
    
    # Check if token is valid
    if actual_token not in valid_tokens:
        raise Exception('Unauthorized')
    
    token_info = valid_tokens[actual_token]
    
    # Generate policy
    policy = generate_policy(
        token_info['principal_id'],
        'Allow',
        method_arn,
        {
            'role': token_info['role'],
            'permissions': token_info['permissions']
        }
    )
    
    print(f"Generated Policy: {json.dumps(policy)}")
    return policy

def generate_policy(principal_id, effect, resource, context=None):
    """Generate IAM policy for API Gateway"""
    policy = {
        'principalId': principal_id,
        'policyDocument': {
            'Version': '2012-10-17',
            'Statement': [
                {
                    'Action': 'execute-api:Invoke',
                    'Effect': effect,
                    'Resource': resource
                }
            ]
        }
    }
    
    # Add context for passing additional information
    if context:
        policy['context'] = context
        
    return policy