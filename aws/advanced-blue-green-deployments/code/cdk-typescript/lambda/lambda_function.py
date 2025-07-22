import json
import os
import time
import random
from datetime import datetime

def lambda_handler(event, context):
    """
    Lambda function for blue-green deployment demo
    """
    
    version = os.environ.get('VERSION', '1.0.0')
    environment = os.environ.get('ENVIRONMENT', 'blue')
    
    # Extract HTTP method and path
    http_method = event.get('httpMethod', 'GET')
    path = event.get('path', '/')
    
    # Route requests
    if path == '/health':
        return health_check(version, environment)
    elif path == '/api/lambda-data':
        return get_lambda_data(version, environment)
    elif path == '/':
        return home_response(version, environment)
    else:
        return {
            'statusCode': 404,
            'headers': {'Content-Type': 'application/json'},
            'body': json.dumps({'error': 'Not found'})
        }

def health_check(version, environment):
    """Health check endpoint"""
    return {
        'statusCode': 200,
        'headers': {'Content-Type': 'application/json'},
        'body': json.dumps({
            'status': 'healthy',
            'version': version,
            'environment': environment,
            'timestamp': datetime.utcnow().isoformat(),
            'requestId': os.environ.get('AWS_REQUEST_ID', 'unknown')
        })
    }

def get_lambda_data(version, environment):
    """API endpoint returning data"""
    
    data = {
        'version': version,
        'environment': environment,
        'lambda_data': [
            {'id': 1, 'type': 'lambda', 'value': random.random()},
            {'id': 2, 'type': 'lambda', 'value': random.random()},
            {'id': 3, 'type': 'lambda', 'value': random.random()}
        ],
        'timestamp': datetime.utcnow().isoformat(),
        'execution_time_ms': random.randint(50, 200)
    }
    
    # Version-specific features
    if version == '2.0.0':
        data['new_feature'] = 'Enhanced Lambda processing'
        data['lambda_data'].append({
            'id': 4, 'type': 'lambda-enhanced', 'value': random.random()
        })
        
        # Simulate occasional errors in v2.0.0 for rollback testing
        if random.random() < 0.1:  # 10% error rate
            return {
                'statusCode': 500,
                'headers': {'Content-Type': 'application/json'},
                'body': json.dumps({
                    'error': 'Simulated error in Lambda v2.0.0',
                    'version': version
                })
            }
    
    return {
        'statusCode': 200,
        'headers': {'Content-Type': 'application/json'},
        'body': json.dumps(data)
    }

def home_response(version, environment):
    """Home endpoint response"""
    return {
        'statusCode': 200,
        'headers': {'Content-Type': 'application/json'},
        'body': json.dumps({
            'message': 'Lambda Blue-Green Deployment Demo',
            'version': version,
            'environment': environment,
            'timestamp': datetime.utcnow().isoformat()
        })
    }