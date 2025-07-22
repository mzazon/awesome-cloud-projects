"""
AWS Backup Validation Lambda Function
This Lambda function validates backup job completion and sends notifications
for failed or successful backup operations across multiple regions.
"""

import json
import boto3
import os
import logging
from datetime import datetime, timedelta
from typing import Dict, Any, Optional

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize AWS clients
backup_client = boto3.client('backup')
sns_client = boto3.client('sns')

# Environment variables
SNS_TOPIC_ARN = os.environ.get('SNS_TOPIC_ARN', '${sns_topic_arn}')

def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Main Lambda handler for processing backup job state changes.
    
    Args:
        event: EventBridge event containing backup job details
        context: Lambda context object
    
    Returns:
        Dict containing status code and response message
    """
    try:
        logger.info(f"Processing backup event: {json.dumps(event, default=str)}")
        
        # Extract backup job details from EventBridge event
        detail = event.get('detail', {})
        backup_job_id = detail.get('backupJobId')
        
        if not backup_job_id:
            logger.error("No backup job ID found in event")
            return {
                'statusCode': 400,
                'body': json.dumps('No backup job ID found in event')
            }
        
        # Process the backup job
        result = process_backup_job(backup_job_id, detail)
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Backup validation completed successfully',
                'result': result
            })
        }
        
    except Exception as e:
        logger.error(f"Error processing backup event: {str(e)}")
        
        # Send error notification if SNS is configured
        if SNS_TOPIC_ARN:
            try:
                send_error_notification(str(e))
            except Exception as sns_error:
                logger.error(f"Failed to send error notification: {str(sns_error)}")
        
        return {
            'statusCode': 500,
            'body': json.dumps(f'Error processing backup event: {str(e)}')
        }

def process_backup_job(backup_job_id: str, detail: Dict[str, Any]) -> Dict[str, Any]:
    """
    Process a backup job and perform validation.
    
    Args:
        backup_job_id: The backup job ID to process
        detail: Event detail containing backup job information
    
    Returns:
        Dict containing processing results
    """
    try:
        # Get detailed backup job information
        response = backup_client.describe_backup_job(BackupJobId=backup_job_id)
        backup_job = response['BackupJob']
        
        job_state = backup_job.get('State', 'UNKNOWN')
        resource_arn = backup_job.get('ResourceArn', 'Unknown')
        backup_vault_name = backup_job.get('BackupVaultName', 'Unknown')
        creation_date = backup_job.get('CreationDate')
        completion_date = backup_job.get('CompletionDate')
        
        logger.info(f"Processing backup job {backup_job_id} with state {job_state}")
        
        result = {
            'backup_job_id': backup_job_id,
            'state': job_state,
            'resource_arn': resource_arn,
            'backup_vault': backup_vault_name,
            'creation_date': creation_date.isoformat() if creation_date else None,
            'completion_date': completion_date.isoformat() if completion_date else None
        }
        
        # Process based on job state
        if job_state == 'COMPLETED':
            result.update(handle_successful_backup(backup_job))
        elif job_state in ['FAILED', 'ABORTED', 'EXPIRED']:
            result.update(handle_failed_backup(backup_job))
        else:
            logger.info(f"Backup job {backup_job_id} is in state {job_state}, no action needed")
        
        return result
        
    except Exception as e:
        logger.error(f"Error processing backup job {backup_job_id}: {str(e)}")
        raise

def handle_successful_backup(backup_job: Dict[str, Any]) -> Dict[str, Any]:
    """
    Handle successful backup completion.
    
    Args:
        backup_job: Backup job details from AWS Backup
    
    Returns:
        Dict containing success handling results
    """
    backup_job_id = backup_job.get('BackupJobId')
    recovery_point_arn = backup_job.get('RecoveryPointArn')
    backup_size_bytes = backup_job.get('BackupSizeInBytes', 0)
    
    logger.info(f"Backup job {backup_job_id} completed successfully")
    logger.info(f"Recovery point: {recovery_point_arn}")
    logger.info(f"Backup size: {backup_size_bytes} bytes")
    
    # Validate recovery point exists
    validation_result = validate_recovery_point(recovery_point_arn)
    
    # Send success notification if configured
    if SNS_TOPIC_ARN:
        send_success_notification(backup_job, validation_result)
    
    return {
        'status': 'success',
        'recovery_point_arn': recovery_point_arn,
        'backup_size_bytes': backup_size_bytes,
        'validation_result': validation_result
    }

def handle_failed_backup(backup_job: Dict[str, Any]) -> Dict[str, Any]:
    """
    Handle failed backup operations.
    
    Args:
        backup_job: Backup job details from AWS Backup
    
    Returns:
        Dict containing failure handling results
    """
    backup_job_id = backup_job.get('BackupJobId')
    state = backup_job.get('State')
    status_message = backup_job.get('StatusMessage', 'No status message available')
    
    logger.error(f"Backup job {backup_job_id} failed with state {state}")
    logger.error(f"Status message: {status_message}")
    
    # Send failure notification if configured
    if SNS_TOPIC_ARN:
        send_failure_notification(backup_job)
    
    return {
        'status': 'failed',
        'failure_state': state,
        'status_message': status_message
    }

def validate_recovery_point(recovery_point_arn: Optional[str]) -> Dict[str, Any]:
    """
    Validate that a recovery point exists and is accessible.
    
    Args:
        recovery_point_arn: ARN of the recovery point to validate
    
    Returns:
        Dict containing validation results
    """
    if not recovery_point_arn:
        return {'valid': False, 'error': 'No recovery point ARN provided'}
    
    try:
        # Extract backup vault name from recovery point ARN
        # ARN format: arn:aws:backup:region:account:recovery-point:backup-vault-name/recovery-point-id
        arn_parts = recovery_point_arn.split(':')
        if len(arn_parts) >= 6:
            vault_and_point = arn_parts[6].split('/')
            if len(vault_and_point) >= 2:
                backup_vault_name = vault_and_point[0]
                recovery_point_id = vault_and_point[1]
                
                # Describe the recovery point
                response = backup_client.describe_recovery_point(
                    BackupVaultName=backup_vault_name,
                    RecoveryPointArn=recovery_point_arn
                )
                
                recovery_point = response['RecoveryPointArn']
                status = response['Status']
                
                logger.info(f"Recovery point validation successful: {recovery_point}")
                
                return {
                    'valid': True,
                    'status': status,
                    'backup_vault_name': backup_vault_name,
                    'recovery_point_id': recovery_point_id
                }
        
        return {'valid': False, 'error': 'Invalid recovery point ARN format'}
        
    except Exception as e:
        logger.error(f"Error validating recovery point {recovery_point_arn}: {str(e)}")
        return {'valid': False, 'error': str(e)}

def send_success_notification(backup_job: Dict[str, Any], validation_result: Dict[str, Any]) -> None:
    """
    Send success notification via SNS.
    
    Args:
        backup_job: Backup job details
        validation_result: Recovery point validation results
    """
    backup_job_id = backup_job.get('BackupJobId')
    resource_arn = backup_job.get('ResourceArn')
    backup_vault_name = backup_job.get('BackupVaultName')
    backup_size_bytes = backup_job.get('BackupSizeInBytes', 0)
    completion_date = backup_job.get('CompletionDate')
    
    # Format backup size for readability
    backup_size_mb = backup_size_bytes / (1024 * 1024) if backup_size_bytes else 0
    
    subject = f"AWS Backup Job Completed Successfully - {backup_job_id}"
    
    message = f"""
AWS Backup Job Completed Successfully

Job Details:
- Backup Job ID: {backup_job_id}
- Resource ARN: {resource_arn}
- Backup Vault: {backup_vault_name}
- Backup Size: {backup_size_mb:.2f} MB
- Completion Date: {completion_date.strftime('%Y-%m-%d %H:%M:%S UTC') if completion_date else 'N/A'}

Validation Results:
- Recovery Point Valid: {validation_result.get('valid', False)}
- Recovery Point Status: {validation_result.get('status', 'Unknown')}

This backup is now available for restoration if needed.
"""
    
    try:
        sns_client.publish(
            TopicArn=SNS_TOPIC_ARN,
            Subject=subject,
            Message=message.strip()
        )
        logger.info(f"Success notification sent for backup job {backup_job_id}")
    except Exception as e:
        logger.error(f"Failed to send success notification: {str(e)}")

def send_failure_notification(backup_job: Dict[str, Any]) -> None:
    """
    Send failure notification via SNS.
    
    Args:
        backup_job: Backup job details
    """
    backup_job_id = backup_job.get('BackupJobId')
    resource_arn = backup_job.get('ResourceArn')
    state = backup_job.get('State')
    status_message = backup_job.get('StatusMessage', 'No status message available')
    creation_date = backup_job.get('CreationDate')
    
    subject = f"AWS Backup Job Failed - {backup_job_id}"
    
    message = f"""
AWS Backup Job Failed

Job Details:
- Backup Job ID: {backup_job_id}
- Resource ARN: {resource_arn}
- State: {state}
- Status Message: {status_message}
- Creation Date: {creation_date.strftime('%Y-%m-%d %H:%M:%S UTC') if creation_date else 'N/A'}

Action Required:
Please investigate this backup failure and take appropriate action to ensure
data protection for the affected resource.

You can view more details in the AWS Backup console:
https://console.aws.amazon.com/backup/home
"""
    
    try:
        sns_client.publish(
            TopicArn=SNS_TOPIC_ARN,
            Subject=subject,
            Message=message.strip()
        )
        logger.info(f"Failure notification sent for backup job {backup_job_id}")
    except Exception as e:
        logger.error(f"Failed to send failure notification: {str(e)}")

def send_error_notification(error_message: str) -> None:
    """
    Send error notification for Lambda function errors.
    
    Args:
        error_message: Error message to include in notification
    """
    subject = "AWS Backup Validator Lambda Function Error"
    
    message = f"""
AWS Backup Validator Lambda Function Error

An error occurred while processing a backup event:

Error: {error_message}

Please check the Lambda function logs for more details and take appropriate action.
"""
    
    try:
        sns_client.publish(
            TopicArn=SNS_TOPIC_ARN,
            Subject=subject,
            Message=message.strip()
        )
        logger.info("Error notification sent")
    except Exception as e:
        logger.error(f"Failed to send error notification: {str(e)}")