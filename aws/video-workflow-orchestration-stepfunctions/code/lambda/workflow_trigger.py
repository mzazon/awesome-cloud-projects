"""
Workflow Trigger Lambda Function
Triggers video processing workflows via API Gateway or S3 events.
"""

import json
import boto3
import uuid
import os
from datetime import datetime
from typing import Dict, Any, Optional

# Initialize AWS clients
stepfunctions_client = boto3.client('stepfunctions')

def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Lambda function handler for triggering video processing workflows.
    
    Supports triggering via:
    1. API Gateway HTTP requests
    2. S3 event notifications
    
    Args:
        event: Event data from API Gateway or S3
        context: Lambda runtime context
        
    Returns:
        Dict containing trigger result and execution information
    """
    try:
        print(f"Received event: {json.dumps(event, default=str)}")
        
        # Determine event source and extract trigger information
        trigger_info = parse_trigger_event(event)
        
        if not trigger_info:
            return create_error_response(400, "Unable to parse trigger event")
        
        print(f"Parsed trigger info: {trigger_info}")
        
        # Validate required parameters
        bucket = trigger_info.get('bucket')
        key = trigger_info.get('key')
        
        if not bucket or not key:
            return create_error_response(400, "Missing required parameters: bucket and/or key")
        
        # Validate file is a video
        if not is_video_file(key):
            return create_error_response(400, f"File {key} is not a supported video format")
        
        # Generate unique job ID
        job_id = str(uuid.uuid4())
        
        # Prepare workflow input
        workflow_input = {
            'jobId': job_id,
            'bucket': bucket,
            'key': key,
            'requestedAt': datetime.utcnow().isoformat(),
            'triggerSource': trigger_info.get('source', 'unknown'),
            'triggerMetadata': trigger_info.get('metadata', {})
        }
        
        # Start Step Functions execution
        execution_result = start_workflow_execution(job_id, workflow_input)
        
        if execution_result['success']:
            response_data = {
                'jobId': job_id,
                'executionArn': execution_result['executionArn'],
                'workflowInput': workflow_input,
                'message': 'Video processing workflow started successfully',
                'startedAt': datetime.utcnow().isoformat()
            }
            
            print(f"Successfully started workflow for job {job_id}")
            return create_success_response(response_data)
        else:
            error_msg = f"Failed to start workflow: {execution_result.get('error', 'Unknown error')}"
            print(error_msg)
            return create_error_response(500, error_msg)
        
    except Exception as e:
        error_message = f"Error triggering workflow: {str(e)}"
        print(error_message)
        return create_error_response(500, error_message)

def parse_trigger_event(event: Dict[str, Any]) -> Optional[Dict[str, Any]]:
    """
    Parse trigger event from different sources (API Gateway, S3, etc.).
    
    Args:
        event: Raw event data
        
    Returns:
        Dict containing parsed trigger information or None if invalid
    """
    try:
        # Check if this is an API Gateway event
        if 'httpMethod' in event or 'requestContext' in event:
            return parse_api_gateway_event(event)
        
        # Check if this is an S3 event
        elif 'Records' in event:
            return parse_s3_event(event)
        
        # Check if this is a direct invocation with bucket/key
        elif 'bucket' in event and 'key' in event:
            return parse_direct_invocation(event)
        
        else:
            print(f"Unknown event format: {list(event.keys())}")
            return None
            
    except Exception as e:
        print(f"Error parsing trigger event: {str(e)}")
        return None

def parse_api_gateway_event(event: Dict[str, Any]) -> Optional[Dict[str, Any]]:
    """Parse API Gateway trigger event."""
    try:
        # Extract body from API Gateway event
        body = event.get('body', '{}')
        if isinstance(body, str):
            body_data = json.loads(body) if body else {}
        else:
            body_data = body
        
        bucket = body_data.get('bucket')
        key = body_data.get('key')
        
        if not bucket or not key:
            # Check query parameters as fallback
            query_params = event.get('queryStringParameters') or {}
            bucket = bucket or query_params.get('bucket')
            key = key or query_params.get('key')
        
        if bucket and key:
            return {
                'source': 'api_gateway',
                'bucket': bucket,
                'key': key,
                'metadata': {
                    'requestId': event.get('requestContext', {}).get('requestId'),
                    'sourceIp': event.get('requestContext', {}).get('identity', {}).get('sourceIp'),
                    'userAgent': event.get('requestContext', {}).get('identity', {}).get('userAgent'),
                    'httpMethod': event.get('httpMethod'),
                    'path': event.get('path'),
                    'headers': event.get('headers', {}),
                    'triggeredAt': datetime.utcnow().isoformat()
                }
            }
        
        return None
        
    except Exception as e:
        print(f"Error parsing API Gateway event: {str(e)}")
        return None

def parse_s3_event(event: Dict[str, Any]) -> Optional[Dict[str, Any]]:
    """Parse S3 event notification."""
    try:
        records = event.get('Records', [])
        if not records:
            return None
        
        # Process the first S3 record (typically only one for object created events)
        s3_record = records[0]
        
        # Validate this is an S3 event
        if s3_record.get('eventSource') != 'aws:s3':
            print(f"Not an S3 event: {s3_record.get('eventSource')}")
            return None
        
        s3_info = s3_record.get('s3', {})
        bucket_info = s3_info.get('bucket', {})
        object_info = s3_info.get('object', {})
        
        bucket = bucket_info.get('name')
        key = object_info.get('key')
        
        # URL decode the key (S3 events URL encode object keys)
        if key:
            import urllib.parse
            key = urllib.parse.unquote_plus(key)
        
        if bucket and key:
            return {
                'source': 's3_event',
                'bucket': bucket,
                'key': key,
                'metadata': {
                    'eventName': s3_record.get('eventName'),
                    'eventTime': s3_record.get('eventTime'),
                    'eventSource': s3_record.get('eventSource'),
                    'awsRegion': s3_record.get('awsRegion'),
                    'objectSize': object_info.get('size'),
                    'objectETag': object_info.get('eTag'),
                    'objectVersionId': object_info.get('versionId'),
                    'sequencer': object_info.get('sequencer'),
                    'triggeredAt': datetime.utcnow().isoformat()
                }
            }
        
        return None
        
    except Exception as e:
        print(f"Error parsing S3 event: {str(e)}")
        return None

def parse_direct_invocation(event: Dict[str, Any]) -> Optional[Dict[str, Any]]:
    """Parse direct Lambda invocation with bucket/key parameters."""
    try:
        bucket = event.get('bucket')
        key = event.get('key')
        
        if bucket and key:
            return {
                'source': 'direct_invocation',
                'bucket': bucket,
                'key': key,
                'metadata': {
                    'invokedDirectly': True,
                    'additionalParams': {k: v for k, v in event.items() if k not in ['bucket', 'key']},
                    'triggeredAt': datetime.utcnow().isoformat()
                }
            }
        
        return None
        
    except Exception as e:
        print(f"Error parsing direct invocation: {str(e)}")
        return None

def is_video_file(key: str) -> bool:
    """
    Check if the file is a supported video format.
    
    Args:
        key: S3 object key (file path)
        
    Returns:
        True if file appears to be a supported video format
    """
    if not key or '.' not in key:
        return False
    
    # Extract file extension
    file_extension = key.lower().split('.')[-1]
    
    # Supported video formats
    supported_formats = {
        'mp4', 'mov', 'avi', 'mkv', 'wmv', 'flv', 'webm', 'm4v',
        'mpg', 'mpeg', '3gp', 'm2v', 'ts', 'mts', 'mxf'
    }
    
    is_supported = file_extension in supported_formats
    print(f"File {key} - extension: {file_extension}, supported: {is_supported}")
    
    return is_supported

def start_workflow_execution(job_id: str, workflow_input: Dict[str, Any]) -> Dict[str, Any]:
    """
    Start Step Functions workflow execution.
    
    Args:
        job_id: Unique job identifier
        workflow_input: Input data for the workflow
        
    Returns:
        Dict containing execution result
    """
    try:
        state_machine_arn = os.environ['STATE_MACHINE_ARN']
        execution_name = f"video-workflow-{job_id}"
        
        print(f"Starting Step Functions execution: {execution_name}")
        
        response = stepfunctions_client.start_execution(
            stateMachineArn=state_machine_arn,
            name=execution_name,
            input=json.dumps(workflow_input, default=str)
        )
        
        execution_arn = response['executionArn']
        print(f"Started execution: {execution_arn}")
        
        return {
            'success': True,
            'executionArn': execution_arn,
            'executionName': execution_name,
            'startDate': response.get('startDate')
        }
        
    except stepfunctions_client.exceptions.ExecutionLimitExceeded:
        error_msg = "Maximum number of concurrent executions reached"
        print(error_msg)
        return {'success': False, 'error': error_msg}
        
    except stepfunctions_client.exceptions.ExecutionAlreadyExists:
        error_msg = f"Execution with name {execution_name} already exists"
        print(error_msg)
        return {'success': False, 'error': error_msg}
        
    except stepfunctions_client.exceptions.InvalidArn:
        error_msg = f"Invalid state machine ARN: {state_machine_arn}"
        print(error_msg)
        return {'success': False, 'error': error_msg}
        
    except stepfunctions_client.exceptions.InvalidExecutionInput:
        error_msg = "Invalid execution input format"
        print(error_msg)
        return {'success': False, 'error': error_msg}
        
    except Exception as e:
        error_msg = f"Unexpected error starting execution: {str(e)}"
        print(error_msg)
        return {'success': False, 'error': error_msg}

def create_success_response(data: Dict[str, Any]) -> Dict[str, Any]:
    """Create standardized success response."""
    return {
        'statusCode': 200,
        'headers': {
            'Content-Type': 'application/json',
            'Access-Control-Allow-Origin': '*',
            'Access-Control-Allow-Headers': 'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token',
            'Access-Control-Allow-Methods': 'OPTIONS,POST'
        },
        'body': json.dumps({
            'success': True,
            'data': data,
            'timestamp': datetime.utcnow().isoformat()
        }, default=str)
    }

def create_error_response(status_code: int, error_message: str) -> Dict[str, Any]:
    """Create standardized error response."""
    return {
        'statusCode': status_code,
        'headers': {
            'Content-Type': 'application/json',
            'Access-Control-Allow-Origin': '*',
            'Access-Control-Allow-Headers': 'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token',
            'Access-Control-Allow-Methods': 'OPTIONS,POST'
        },
        'body': json.dumps({
            'success': False,
            'error': error_message,
            'timestamp': datetime.utcnow().isoformat()
        }, default=str)
    }

def validate_workflow_prerequisites() -> Dict[str, Any]:
    """
    Validate that required environment variables and AWS services are accessible.
    This function can be called during Lambda initialization for health checks.
    
    Returns:
        Dict containing validation results
    """
    try:
        validation_results = {
            'environment_variables': {},
            'aws_services': {},
            'overall_status': 'healthy'
        }
        
        # Check required environment variables
        required_env_vars = ['STATE_MACHINE_ARN']
        for var in required_env_vars:
            value = os.environ.get(var)
            validation_results['environment_variables'][var] = {
                'present': value is not None,
                'value_length': len(value) if value else 0
            }
        
        # Test Step Functions access
        try:
            state_machine_arn = os.environ.get('STATE_MACHINE_ARN')
            if state_machine_arn:
                stepfunctions_client.describe_state_machine(stateMachineArn=state_machine_arn)
                validation_results['aws_services']['step_functions'] = 'accessible'
            else:
                validation_results['aws_services']['step_functions'] = 'no_arn_configured'
        except Exception as e:
            validation_results['aws_services']['step_functions'] = f'error: {str(e)}'
            validation_results['overall_status'] = 'degraded'
        
        return validation_results
        
    except Exception as e:
        return {
            'overall_status': 'error',
            'validation_error': str(e),
            'timestamp': datetime.utcnow().isoformat()
        }

# Perform validation during module initialization (optional)
# This can help identify configuration issues early
try:
    if os.environ.get('VALIDATE_ON_INIT', 'false').lower() == 'true':
        _validation_result = validate_workflow_prerequisites()
        if _validation_result['overall_status'] != 'healthy':
            print(f"Workflow trigger validation warning: {_validation_result}")
except Exception as e:
    print(f"Error during initialization validation: {str(e)}")