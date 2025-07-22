import json
import base64
from urllib.parse import parse_qs

def lambda_handler(event, context):
    """
    Request-based authorizer that validates based on request context
    """
    print(f"Request Authorizer Event: {json.dumps(event)}")
    
    # Extract request details
    headers = event.get('headers', {})
    query_params = event.get('queryStringParameters', {}) or {}
    method_arn = event.get('methodArn', '')
    source_ip = event.get('requestContext', {}).get('identity', {}).get('sourceIp', '')
    
    # Check for API key in query parameters
    api_key = query_params.get('api_key', '')
    
    # Check for custom authentication header
    custom_auth = headers.get('X-Custom-Auth', '')
    
    # Configuration from Terraform variables
    valid_api_keys = ${valid_api_keys}
    custom_auth_values = ${custom_auth_values}
    
    # Validate based on multiple criteria
    principal_id = 'unknown'
    effect = 'Deny'
    context = {}
    
    # API Key validation
    if api_key in valid_api_keys:
        principal_id = 'api-key-user'
        effect = 'Allow'
        context = {
            'authType': 'api-key',
            'sourceIp': source_ip,
            'permissions': 'read,write'
        }
    # Custom header validation
    elif custom_auth in custom_auth_values:
        principal_id = 'custom-user'
        effect = 'Allow'
        context = {
            'authType': 'custom-header',
            'sourceIp': source_ip,
            'permissions': 'read'
        }
    # IP-based validation (example for internal networks)
    elif source_ip.startswith('10.') or source_ip.startswith('172.') or source_ip.startswith('192.168.'):
        principal_id = 'internal-user'
        effect = 'Allow'
        context = {
            'authType': 'ip-whitelist',
            'sourceIp': source_ip,
            'permissions': 'read,write,delete'
        }
    
    # Generate policy
    policy = generate_policy(principal_id, effect, method_arn, context)
    
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
    
    if context:
        policy['context'] = context
        
    return policy