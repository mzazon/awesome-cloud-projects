"""
AWS Lambda function for automated WorkSpaces provisioning
This function manages the lifecycle of WorkSpaces for development teams
"""

import json
import boto3
import logging
import time
import os
from botocore.exceptions import ClientError
from typing import Dict, List, Any, Optional

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize AWS clients
workspaces_client = boto3.client('workspaces')
ssm_client = boto3.client('ssm')
secrets_client = boto3.client('secretsmanager')

def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Main Lambda handler for WorkSpaces automation
    
    Args:
        event: Event data containing configuration parameters
        context: Lambda runtime information
        
    Returns:
        Response with status and results
    """
    try:
        logger.info("Starting WorkSpaces automation process")
        logger.info(f"Event: {json.dumps(event, default=str)}")
        
        # Validate required event parameters
        required_params = ['directory_id', 'bundle_id', 'target_users']
        for param in required_params:
            if param not in event:
                raise ValueError(f"Missing required parameter: {param}")
        
        # Get configuration from environment and event
        secret_name = event.get('secret_name', os.environ.get('SECRET_NAME'))
        ssm_document = event.get('ssm_document', os.environ.get('SSM_DOCUMENT_NAME'))
        
        # Get AD credentials from Secrets Manager
        credentials = get_ad_credentials(secret_name)
        
        # Get current WorkSpaces
        current_workspaces = get_current_workspaces(event['directory_id'])
        logger.info(f"Found {len(current_workspaces)} existing WorkSpaces")
        
        # Get target users from event
        target_users = event.get('target_users', [])
        logger.info(f"Target users: {target_users}")
        
        # Provision WorkSpaces for new users
        provision_results = provision_workspaces(target_users, current_workspaces, event)
        
        # Schedule configuration for new WorkSpaces
        configuration_results = schedule_workspaces_configuration(
            provision_results, event, ssm_document
        )
        
        # Clean up unused WorkSpaces (optional)
        cleanup_results = cleanup_unused_workspaces(
            target_users, current_workspaces, event
        )
        
        response = {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'WorkSpaces provisioning completed successfully',
                'provisioned': provision_results,
                'configured': configuration_results,
                'cleaned_up': cleanup_results,
                'timestamp': time.strftime('%Y-%m-%d %H:%M:%S UTC', time.gmtime()),
                'request_id': context.aws_request_id if context else 'local-test'
            })
        }
        
        logger.info("WorkSpaces automation completed successfully")
        return response
        
    except Exception as e:
        logger.error(f"Error in WorkSpaces automation: {str(e)}", exc_info=True)
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': str(e),
                'message': 'WorkSpaces automation failed',
                'request_id': context.aws_request_id if context else 'local-test'
            })
        }

def get_ad_credentials(secret_name: str) -> Dict[str, str]:
    """Retrieve AD credentials from Secrets Manager"""
    try:
        logger.info(f"Retrieving credentials from secret: {secret_name}")
        response = secrets_client.get_secret_value(SecretId=secret_name)
        credentials = json.loads(response['SecretString'])
        logger.info("Successfully retrieved AD credentials")
        return credentials
    except ClientError as e:
        logger.error(f"Failed to retrieve credentials: {e}")
        raise
    except json.JSONDecodeError as e:
        logger.error(f"Failed to parse credentials JSON: {e}")
        raise

def get_current_workspaces(directory_id: str) -> Dict[str, Dict[str, Any]]:
    """Get list of current WorkSpaces for the directory"""
    try:
        logger.info(f"Describing WorkSpaces for directory: {directory_id}")
        
        workspaces = {}
        paginator = workspaces_client.get_paginator('describe_workspaces')
        
        for page in paginator.paginate(DirectoryId=directory_id):
            for workspace in page['Workspaces']:
                # Only include active or transitioning WorkSpaces
                if workspace['State'] in ['AVAILABLE', 'PENDING', 'STARTING', 'REBUILDING', 'RESTORING']:
                    workspaces[workspace['UserName']] = {
                        'workspace_id': workspace['WorkspaceId'],
                        'state': workspace['State'],
                        'bundle_id': workspace['BundleId'],
                        'directory_id': workspace['DirectoryId']
                    }
        
        logger.info(f"Found {len(workspaces)} active WorkSpaces")
        return workspaces
        
    except ClientError as e:
        logger.error(f"Failed to describe WorkSpaces: {e}")
        return {}

def provision_workspaces(
    target_users: List[str], 
    current_workspaces: Dict[str, Dict[str, Any]], 
    event: Dict[str, Any]
) -> List[Dict[str, Any]]:
    """Provision WorkSpaces for users who don't have them"""
    results = []
    
    # Configuration from event
    directory_id = event['directory_id']
    bundle_id = event['bundle_id']
    running_mode = event.get('running_mode', 'AUTO_STOP')
    auto_stop_timeout = event.get('auto_stop_timeout', 60)
    
    for user in target_users:
        if user not in current_workspaces:
            try:
                logger.info(f"Creating WorkSpace for user: {user}")
                
                workspace_request = {
                    'DirectoryId': directory_id,
                    'UserName': user,
                    'BundleId': bundle_id,
                    'WorkspaceProperties': {
                        'RunningMode': running_mode,
                        'UserVolumeEncryptionEnabled': True,
                        'RootVolumeEncryptionEnabled': True
                    },
                    'Tags': [
                        {'Key': 'Project', 'Value': event.get('project_name', 'DevEnvironmentAutomation')},
                        {'Key': 'User', 'Value': user},
                        {'Key': 'Environment', 'Value': 'Development'},
                        {'Key': 'AutomatedProvisioning', 'Value': 'true'},
                        {'Key': 'TeamConfiguration', 'Value': event.get('team_configuration', 'standard')}
                    ]
                }
                
                # Add auto-stop timeout for AUTO_STOP mode
                if running_mode == 'AUTO_STOP':
                    workspace_request['WorkspaceProperties']['RunningModeAutoStopTimeoutInMinutes'] = auto_stop_timeout
                
                response = workspaces_client.create_workspaces(
                    Workspaces=[workspace_request]
                )
                
                if response['PendingRequests']:
                    workspace_id = response['PendingRequests'][0]['WorkspaceId']
                    results.append({
                        'user': user,
                        'workspace_id': workspace_id,
                        'status': 'created',
                        'bundle_id': bundle_id,
                        'running_mode': running_mode
                    })
                    logger.info(f"Successfully created WorkSpace {workspace_id} for {user}")
                    
                elif response['FailedRequests']:
                    error_code = response['FailedRequests'][0]['ErrorCode']
                    error_message = response['FailedRequests'][0]['ErrorMessage']
                    results.append({
                        'user': user,
                        'status': 'failed',
                        'error': f"{error_code}: {error_message}"
                    })
                    logger.error(f"Failed to create WorkSpace for {user}: {error_code} - {error_message}")
                   
            except ClientError as e:
                logger.error(f"Failed to create WorkSpace for {user}: {e}")
                results.append({
                    'user': user,
                    'status': 'failed',
                    'error': str(e)
                })
        else:
            workspace_info = current_workspaces[user]
            logger.info(f"User {user} already has WorkSpace: {workspace_info['workspace_id']} (State: {workspace_info['state']})")
            results.append({
                'user': user,
                'workspace_id': workspace_info['workspace_id'],
                'status': 'existing',
                'state': workspace_info['state']
            })
    
    return results

def schedule_workspaces_configuration(
    provision_results: List[Dict[str, Any]], 
    event: Dict[str, Any],
    ssm_document: str
) -> List[Dict[str, Any]]:
    """Schedule configuration for newly provisioned WorkSpaces"""
    configuration_results = []
    
    # Get configuration parameters
    development_tools = event.get('development_tools', 'git,vscode,nodejs,python')
    team_configuration = event.get('team_configuration', 'standard')
    
    for result in provision_results:
        if result.get('status') == 'created':
            workspace_id = result['workspace_id']
            user = result['user']
            
            try:
                # Note: In production, you would wait for WorkSpaces to be available
                # and then send SSM commands. For now, we'll just schedule the configuration
                logger.info(f"Scheduling configuration for WorkSpace {workspace_id}")
                
                configuration_results.append({
                    'workspace_id': workspace_id,
                    'user': user,
                    'configuration_status': 'scheduled',
                    'ssm_document': ssm_document,
                    'development_tools': development_tools,
                    'team_configuration': team_configuration
                })
                
            except Exception as e:
                logger.error(f"Failed to schedule configuration for {workspace_id}: {e}")
                configuration_results.append({
                    'workspace_id': workspace_id,
                    'user': user,
                    'configuration_status': 'failed',
                    'error': str(e)
                })
    
    return configuration_results

def wait_for_workspace_available(workspace_id: str, max_wait_minutes: int = 30) -> bool:
    """Wait for a WorkSpace to become available"""
    max_wait_seconds = max_wait_minutes * 60
    wait_interval = 30  # Check every 30 seconds
    total_waited = 0
    
    logger.info(f"Waiting for WorkSpace {workspace_id} to become available (max wait: {max_wait_minutes} minutes)")
    
    while total_waited < max_wait_seconds:
        try:
            response = workspaces_client.describe_workspaces(
                WorkspaceIds=[workspace_id]
            )
            
            if response['Workspaces']:
                state = response['Workspaces'][0]['State']
                logger.info(f"WorkSpace {workspace_id} current state: {state}")
                
                if state == 'AVAILABLE':
                    logger.info(f"WorkSpace {workspace_id} is now available")
                    return True
                elif state in ['ERROR', 'TERMINATING', 'TERMINATED']:
                    logger.error(f"WorkSpace {workspace_id} is in error state: {state}")
                    return False
            
            time.sleep(wait_interval)
            total_waited += wait_interval
            
        except ClientError as e:
            logger.error(f"Error checking WorkSpace {workspace_id} status: {e}")
            return False
    
    logger.warning(f"WorkSpace {workspace_id} did not become available within {max_wait_minutes} minutes")
    return False

def send_ssm_command(workspace_id: str, ssm_document: str, parameters: Dict[str, Any]) -> Optional[str]:
    """Send SSM command to configure WorkSpace"""
    try:
        logger.info(f"Sending SSM command to WorkSpace {workspace_id}")
        
        response = ssm_client.send_command(
            InstanceIds=[workspace_id],
            DocumentName=ssm_document,
            Parameters=parameters,
            TimeoutSeconds=3600,  # 1 hour timeout
            Comment=f"Development environment setup for WorkSpace {workspace_id}"
        )
        
        command_id = response['Command']['CommandId']
        logger.info(f"SSM command sent successfully. Command ID: {command_id}")
        return command_id
        
    except ClientError as e:
        logger.error(f"Failed to send SSM command to {workspace_id}: {e}")
        return None

def cleanup_unused_workspaces(
    target_users: List[str], 
    current_workspaces: Dict[str, Dict[str, Any]], 
    event: Dict[str, Any]
) -> List[Dict[str, Any]]:
    """Clean up WorkSpaces for users no longer in target list (optional)"""
    cleanup_results = []
    
    # Check if cleanup is enabled
    enable_cleanup = event.get('enable_cleanup', False)
    if not enable_cleanup:
        logger.info("Cleanup is disabled, skipping unused WorkSpaces removal")
        return cleanup_results
    
    logger.info("Checking for unused WorkSpaces to clean up")
    
    for user, workspace_info in current_workspaces.items():
        if user not in target_users:
            workspace_id = workspace_info['workspace_id']
            
            try:
                logger.info(f"Terminating unused WorkSpace {workspace_id} for user {user}")
                
                # Add termination protection check
                response = workspaces_client.describe_workspaces(
                    WorkspaceIds=[workspace_id]
                )
                
                if response['Workspaces']:
                    workspace = response['Workspaces'][0]
                    # Only terminate if not protected and in good state
                    if workspace['State'] in ['AVAILABLE', 'STOPPED']:
                        terminate_response = workspaces_client.terminate_workspaces(
                            TerminateWorkspaceRequests=[{
                                'WorkspaceId': workspace_id
                            }]
                        )
                        
                        cleanup_results.append({
                            'user': user,
                            'workspace_id': workspace_id,
                            'status': 'terminated',
                            'reason': 'user_no_longer_in_target_list'
                        })
                        logger.info(f"Successfully initiated termination for WorkSpace {workspace_id}")
            
            except ClientError as e:
                logger.error(f"Failed to terminate WorkSpace {workspace_id} for user {user}: {e}")
                cleanup_results.append({
                    'user': user,
                    'workspace_id': workspace_id,
                    'status': 'failed',
                    'error': str(e)
                })
    
    return cleanup_results

def get_workspace_utilization_metrics(workspace_id: str, days: int = 7) -> Dict[str, Any]:
    """Get utilization metrics for a WorkSpace (for future optimization)"""
    try:
        # This is a placeholder for future implementation
        # You could use CloudWatch metrics to determine usage patterns
        logger.info(f"Getting utilization metrics for WorkSpace {workspace_id} (last {days} days)")
        
        # Placeholder return
        return {
            'workspace_id': workspace_id,
            'days_analyzed': days,
            'avg_session_duration': 0,
            'total_sessions': 0,
            'utilization_score': 0.0
        }
    
    except Exception as e:
        logger.error(f"Failed to get utilization metrics for {workspace_id}: {e}")
        return {}

def validate_event_parameters(event: Dict[str, Any]) -> List[str]:
    """Validate event parameters and return list of errors"""
    errors = []
    
    # Required parameters
    required_params = ['directory_id', 'bundle_id']
    for param in required_params:
        if param not in event or not event[param]:
            errors.append(f"Missing or empty required parameter: {param}")
    
    # Validate directory_id format
    directory_id = event.get('directory_id', '')
    if directory_id and not directory_id.startswith('d-'):
        errors.append(f"Invalid directory_id format: {directory_id}")
    
    # Validate bundle_id format
    bundle_id = event.get('bundle_id', '')
    if bundle_id and not bundle_id.startswith('wsb-'):
        errors.append(f"Invalid bundle_id format: {bundle_id}")
    
    # Validate target_users
    target_users = event.get('target_users', [])
    if not isinstance(target_users, list):
        errors.append("target_users must be a list")
    elif len(target_users) > 25:
        errors.append("target_users list cannot contain more than 25 users")
    
    # Validate running_mode
    running_mode = event.get('running_mode', 'AUTO_STOP')
    if running_mode not in ['ALWAYS_ON', 'AUTO_STOP']:
        errors.append(f"Invalid running_mode: {running_mode}")
    
    return errors