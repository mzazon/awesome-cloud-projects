import json

def lambda_handler(event, context):
    """Protected API that requires authorization"""
    
    # Extract authorization context
    auth_context = event.get('requestContext', {}).get('authorizer', {})
    principal_id = auth_context.get('principalId', 'unknown')
    
    # Get additional context passed from authorizer
    role = auth_context.get('role', 'unknown')
    permissions = auth_context.get('permissions', 'none')
    auth_type = auth_context.get('authType', 'token')
    source_ip = auth_context.get('sourceIp', 'unknown')
    
    response_data = {
        'message': 'Access granted to protected resource',
        'user': {
            'principalId': principal_id,
            'role': role,
            'permissions': permissions.split(',') if permissions != 'none' else [],
            'authType': auth_type,
            'sourceIp': source_ip
        },
        'timestamp': context.aws_request_id,
        'protected_data': {
            'secret_value': 'This is confidential information',
            'access_level': role,
            'data_classification': 'restricted'
        },
        'api_info': {
            'function_name': context.function_name,
            'memory_limit': context.memory_limit_in_mb,
            'remaining_time': context.get_remaining_time_in_millis()
        }
    }
    
    return {
        'statusCode': 200,
        'headers': {
            'Content-Type': 'application/json',
            'Access-Control-Allow-Origin': '*',
            'X-API-Version': '1.0',
            'X-Auth-Type': auth_type
        },
        'body': json.dumps(response_data, indent=2)
    }