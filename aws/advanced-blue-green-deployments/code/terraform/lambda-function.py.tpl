#!/usr/bin/env python3
"""
Lambda function for blue-green deployment demo
This function provides API endpoints with version-specific behavior
for demonstrating blue-green deployment patterns.
"""

import json
import os
import time
import random
from datetime import datetime


def lambda_handler(event, context):
    """
    Lambda function handler for blue-green deployment demo
    
    Args:
        event: API Gateway event or direct invocation event
        context: Lambda context object
    
    Returns:
        HTTP response with status code and JSON body
    """
    
    version = os.environ.get('VERSION', '1.0.0')
    environment = os.environ.get('ENVIRONMENT', 'blue')
    
    # Extract HTTP method and path from event
    http_method = event.get('httpMethod', 'GET')
    path = event.get('path', '/')
    
    # Route requests based on path
    if path == '/health':
        return health_check(version, environment, context)
    elif path == '/api/lambda-data':
        return get_lambda_data(version, environment, context)
    elif path == '/':
        return home_response(version, environment, context)
    elif path == '/version':
        return version_info(version, environment, context)
    else:
        return {
            'statusCode': 404,
            'headers': {'Content-Type': 'application/json'},
            'body': json.dumps({
                'error': 'Not found',
                'path': path,
                'available_endpoints': ['/health', '/api/lambda-data', '/', '/version']
            })
        }


def health_check(version, environment, context):
    """
    Health check endpoint for deployment validation
    
    Returns:
        Health status with version and environment information
    """
    return {
        'statusCode': 200,
        'headers': {'Content-Type': 'application/json'},
        'body': json.dumps({
            'status': 'healthy',
            'version': version,
            'environment': environment,
            'timestamp': datetime.utcnow().isoformat(),
            'request_id': context.aws_request_id,
            'function_name': context.function_name,
            'memory_limit': context.memory_limit_in_mb,
            'remaining_time': context.get_remaining_time_in_millis()
        })
    }


def get_lambda_data(version, environment, context):
    """
    API endpoint returning sample data with version-specific features
    
    Returns:
        JSON response with data and metadata
    """
    
    # Base data structure
    data = {
        'version': version,
        'environment': environment,
        'lambda_data': [
            {'id': 1, 'type': 'lambda', 'value': round(random.random(), 4)},
            {'id': 2, 'type': 'lambda', 'value': round(random.random(), 4)},
            {'id': 3, 'type': 'lambda', 'value': round(random.random(), 4)}
        ],
        'timestamp': datetime.utcnow().isoformat(),
        'execution_time_ms': random.randint(50, 200),
        'request_id': context.aws_request_id,
        'function_version': context.function_version
    }
    
    # Version-specific features and behavior
    if version.startswith('2.'):
        # Enhanced features in version 2.x
        data['new_feature'] = 'Enhanced Lambda processing v2.x'
        data['lambda_data'].append({
            'id': 4, 
            'type': 'lambda-enhanced', 
            'value': round(random.random(), 4),
            'enhanced_processing': True
        })
        
        # Add performance metrics for v2
        data['performance_metrics'] = {
            'memory_used_mb': random.randint(128, 256),
            'cpu_utilization': round(random.uniform(0.1, 0.5), 2),
            'network_io_kb': random.randint(10, 100)
        }
        
        # Simulate occasional errors in v2.0.0 for rollback testing
        if version == '2.0.0' and random.random() < 0.05:  # 5% error rate
            return {
                'statusCode': 500,
                'headers': {'Content-Type': 'application/json'},
                'body': json.dumps({
                    'error': 'Simulated error in Lambda v2.0.0 for rollback testing',
                    'version': version,
                    'timestamp': datetime.utcnow().isoformat(),
                    'request_id': context.aws_request_id
                })
            }
    
    elif version.startswith('3.'):
        # Future version features
        data['experimental_feature'] = 'Advanced ML-powered processing v3.x'
        data['lambda_data'].extend([
            {
                'id': 5,
                'type': 'ml-enhanced',
                'value': round(random.random(), 4),
                'confidence_score': round(random.uniform(0.8, 0.99), 3)
            }
        ])
    
    return {
        'statusCode': 200,
        'headers': {
            'Content-Type': 'application/json',
            'X-Lambda-Version': version,
            'X-Environment': environment
        },
        'body': json.dumps(data)
    }


def home_response(version, environment, context):
    """
    Home endpoint response with basic service information
    
    Returns:
        Welcome message with service metadata
    """
    return {
        'statusCode': 200,
        'headers': {'Content-Type': 'application/json'},
        'body': json.dumps({
            'message': 'Lambda Blue-Green Deployment Demo',
            'service': 'advanced-blue-green-lambda-api',
            'version': version,
            'environment': environment,
            'timestamp': datetime.utcnow().isoformat(),
            'function_name': context.function_name,
            'region': os.environ.get('AWS_REGION', 'unknown'),
            'available_endpoints': {
                '/health': 'Health check endpoint',
                '/api/lambda-data': 'Sample API data with version-specific features',
                '/version': 'Detailed version information',
                '/': 'This welcome message'
            }
        })
    }


def version_info(version, environment, context):
    """
    Detailed version information endpoint
    
    Returns:
        Comprehensive version and environment details
    """
    
    # Extract version components
    version_parts = version.split('.')
    major = version_parts[0] if len(version_parts) > 0 else '0'
    minor = version_parts[1] if len(version_parts) > 1 else '0'
    patch = version_parts[2] if len(version_parts) > 2 else '0'
    
    # Feature flags based on version
    features = {
        'basic_api': True,
        'health_checks': True,
        'error_simulation': version == '2.0.0',
        'enhanced_processing': version.startswith('2.'),
        'ml_features': version.startswith('3.'),
        'performance_metrics': version.startswith('2.'),
    }
    
    return {
        'statusCode': 200,
        'headers': {'Content-Type': 'application/json'},
        'body': json.dumps({
            'version': {
                'full': version,
                'major': major,
                'minor': minor,
                'patch': patch
            },
            'environment': environment,
            'deployment_info': {
                'function_name': context.function_name,
                'function_version': context.function_version,
                'memory_limit_mb': context.memory_limit_in_mb,
                'timeout_seconds': int(os.environ.get('AWS_LAMBDA_FUNCTION_TIMEOUT', '30')),
                'runtime': os.environ.get('AWS_EXECUTION_ENV', 'unknown')
            },
            'features': features,
            'metadata': {
                'project': '${project_name}',
                'managed_by': 'terraform',
                'deployment_method': 'blue-green',
                'timestamp': datetime.utcnow().isoformat(),
                'request_id': context.aws_request_id
            }
        })
    }


# Error handling for Lambda runtime
def handle_error(error, context):
    """
    Generic error handler for Lambda function
    
    Args:
        error: Exception object
        context: Lambda context
    
    Returns:
        Error response with details
    """
    return {
        'statusCode': 500,
        'headers': {'Content-Type': 'application/json'},
        'body': json.dumps({
            'error': 'Internal server error',
            'message': str(error),
            'request_id': context.aws_request_id,
            'timestamp': datetime.utcnow().isoformat()
        })
    }