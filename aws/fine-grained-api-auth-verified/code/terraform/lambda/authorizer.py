import json
import boto3
import jwt
from jwt import PyJWKSClient
import os
import urllib.request

# Initialize AWS clients
verifiedpermissions = boto3.client('verifiedpermissions')

# Environment variables
policy_store_id = os.environ.get('POLICY_STORE_ID', '${policy_store_id}')
user_pool_id = os.environ.get('USER_POOL_ID', '${user_pool_id}')
region = os.environ.get('AWS_REGION', '${aws_region}')
user_pool_client_id = os.environ.get('USER_POOL_CLIENT_ID', '')

def lambda_handler(event, context):
    """
    Lambda authorizer function that integrates with Amazon Verified Permissions
    to provide fine-grained authorization for API Gateway requests.
    """
    try:
        # Extract token from Authorization header
        auth_header = event.get('authorizationToken', '')
        if not auth_header.startswith('Bearer '):
            raise ValueError("Invalid authorization header format")
        
        token = auth_header.replace('Bearer ', '')
        
        # Validate and decode JWT token
        decoded_token = validate_jwt_token(token)
        
        # Extract resource and action from method ARN
        method_arn = event['methodArn']
        resource_info = parse_method_arn(method_arn)
        
        # Map HTTP method to Cedar action
        action = map_http_method_to_action(resource_info['http_method'])
        
        # Extract document ID from resource path
        document_id = extract_document_id(resource_info['resource_path'])
        
        # Make authorization request to Amazon Verified Permissions
        auth_response = make_authorization_request(
            token, action, document_id
        )
        
        # Generate IAM policy based on authorization decision
        policy_document = generate_policy_document(
            auth_response['decision'], event['methodArn']
        )
        
        # Return authorizer response with context
        return {
            'principalId': decoded_token['sub'],
            'policyDocument': policy_document,
            'context': {
                'userId': decoded_token['sub'],
                'department': decoded_token.get('custom:department', ''),
                'role': decoded_token.get('custom:role', ''),
                'authDecision': auth_response['decision'],
                'documentId': document_id
            }
        }
        
    except Exception as e:
        print(f"Authorization error: {str(e)}")
        # Return deny policy for any authorization failures
        return {
            'principalId': 'unknown',
            'policyDocument': {
                'Version': '2012-10-17',
                'Statement': [{
                    'Action': 'execute-api:Invoke',
                    'Effect': 'Deny',
                    'Resource': event['methodArn']
                }]
            },
            'context': {
                'authDecision': 'DENY',
                'error': str(e)
            }
        }

def validate_jwt_token(token):
    """
    Validate JWT token against Cognito User Pool JWKS
    """
    try:
        # Construct JWKS URL for Cognito User Pool
        jwks_url = f'https://cognito-idp.{region}.amazonaws.com/{user_pool_id}/.well-known/jwks.json'
        
        # Get signing key from JWKS
        jwks_client = PyJWKSClient(jwks_url)
        signing_key = jwks_client.get_signing_key_from_jwt(token)
        
        # Decode and validate token
        decoded_token = jwt.decode(
            token,
            signing_key.key,
            algorithms=['RS256'],
            audience=user_pool_client_id if user_pool_client_id else None
        )
        
        return decoded_token
        
    except Exception as e:
        raise ValueError(f"Token validation failed: {str(e)}")

def parse_method_arn(method_arn):
    """
    Parse API Gateway method ARN to extract resource information
    """
    # ARN format: arn:aws:execute-api:region:account:api-id/stage/method/resource-path
    try:
        arn_parts = method_arn.split(':')
        if len(arn_parts) < 6:
            raise ValueError("Invalid method ARN format")
        
        api_parts = arn_parts[5].split('/')
        if len(api_parts) < 3:
            raise ValueError("Invalid API Gateway ARN format")
        
        return {
            'api_id': api_parts[0],
            'stage': api_parts[1] if len(api_parts) > 1 else '',
            'http_method': api_parts[2] if len(api_parts) > 2 else '',
            'resource_path': '/'.join(api_parts[3:]) if len(api_parts) > 3 else ''
        }
        
    except Exception as e:
        raise ValueError(f"Failed to parse method ARN: {str(e)}")

def map_http_method_to_action(http_method):
    """
    Map HTTP methods to Cedar action identifiers
    """
    action_map = {
        'GET': 'ViewDocument',
        'PUT': 'EditDocument',
        'POST': 'EditDocument',
        'DELETE': 'DeleteDocument'
    }
    
    return action_map.get(http_method.upper(), 'ViewDocument')

def extract_document_id(resource_path):
    """
    Extract document ID from resource path
    """
    if not resource_path:
        return 'unknown'
    
    # For paths like 'documents/123' or 'documents/123/edit'
    path_parts = resource_path.split('/')
    if len(path_parts) >= 2 and path_parts[0] == 'documents':
        return path_parts[1]
    
    # For single document operations, use the last part
    return path_parts[-1] if path_parts else 'unknown'

def make_authorization_request(token, action, document_id):
    """
    Make authorization request to Amazon Verified Permissions
    """
    try:
        response = verifiedpermissions.is_authorized_with_token(
            policyStoreId=policy_store_id,
            identityToken=token,
            action={
                'actionType': 'Action',
                'actionId': action
            },
            resource={
                'entityType': 'Document',
                'entityId': document_id
            }
        )
        
        return response
        
    except Exception as e:
        print(f"Verified Permissions authorization failed: {str(e)}")
        # Default to deny if authorization service fails
        return {'decision': 'DENY'}

def generate_policy_document(decision, method_arn):
    """
    Generate IAM policy document based on authorization decision
    """
    effect = 'Allow' if decision == 'ALLOW' else 'Deny'
    
    return {
        'Version': '2012-10-17',
        'Statement': [{
            'Action': 'execute-api:Invoke',
            'Effect': effect,
            'Resource': method_arn
        }]
    }