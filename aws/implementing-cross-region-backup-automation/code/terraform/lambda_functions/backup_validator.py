"""
AWS Backup Validation Lambda Function

This Lambda function provides automated validation of backup operations and 
performs advanced monitoring tasks including verifying cross-region copy 
success and recovery point integrity.

Features:
- Validates backup job completion and health
- Monitors cross-region copy operations
- Sends intelligent notifications based on job status
- Performs custom business logic validation
- Integrates with CloudWatch for logging and metrics

Environment Variables:
- SNS_TOPIC_ARN: ARN of SNS topic for notifications
- LOG_LEVEL: Logging level (DEBUG, INFO, WARNING, ERROR, CRITICAL)
"""

import json
import boto3
import logging
import os
from datetime import datetime, timedelta
from typing import Dict, List, Any, Optional
import traceback

# Configure logging
log_level = os.environ.get('LOG_LEVEL', 'INFO').upper()
logger = logging.getLogger()
logger.setLevel(getattr(logging, log_level, logging.INFO))

# Initialize AWS clients
backup_client = boto3.client('backup')
sns_client = boto3.client('sns')
cloudwatch_client = boto3.client('cloudwatch')


def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Main Lambda handler for backup validation events.
    
    Args:
        event: EventBridge event containing backup job details
        context: Lambda context object
    
    Returns:
        Dict containing status code and response message
    """
    try:
        logger.info(f"Received event: {json.dumps(event, default=str)}")
        
        # Extract event details
        event_source = event.get('source', '')
        detail_type = event.get('detail-type', '')
        detail = event.get('detail', {})
        
        # Route to appropriate handler based on event type
        if event_source == 'aws.backup':
            if detail_type == 'Backup Job State Change':
                return handle_backup_job_event(detail, event)
            elif detail_type == 'Copy Job State Change':
                return handle_copy_job_event(detail, event)
            else:
                logger.warning(f"Unhandled event type: {detail_type}")
                return create_response(200, f"Unhandled event type: {detail_type}")
        else:
            logger.warning(f"Unhandled event source: {event_source}")
            return create_response(200, f"Unhandled event source: {event_source}")
            
    except Exception as e:
        error_message = f"Error processing backup validation event: {str(e)}"
        logger.error(error_message)
        logger.error(f"Traceback: {traceback.format_exc()}")
        
        # Send error notification
        send_error_notification(error_message, event)
        
        return create_response(500, error_message)


def handle_backup_job_event(detail: Dict[str, Any], full_event: Dict[str, Any]) -> Dict[str, Any]:
    """
    Handle backup job state change events.
    
    Args:
        detail: Event detail containing backup job information
        full_event: Complete EventBridge event
    
    Returns:
        Dict containing processing results
    """
    backup_job_id = detail.get('backupJobId', '')
    state = detail.get('state', '')
    resource_arn = detail.get('resourceArn', '')
    
    logger.info(f"Processing backup job {backup_job_id} with state: {state}")
    
    try:
        # Get detailed backup job information
        backup_job_details = get_backup_job_details(backup_job_id)
        
        if state in ['COMPLETED']:
            return handle_successful_backup(backup_job_details, detail)
        elif state in ['FAILED', 'ABORTED']:
            return handle_failed_backup(backup_job_details, detail)
        elif state in ['RUNNING']:
            return handle_running_backup(backup_job_details, detail)
        else:
            logger.info(f"Backup job {backup_job_id} in state {state} - no action required")
            return create_response(200, f"Backup job state {state} acknowledged")
            
    except Exception as e:
        error_message = f"Error handling backup job {backup_job_id}: {str(e)}"
        logger.error(error_message)
        send_notification(
            subject="Backup Validation Error",
            message=error_message,
            severity="ERROR"
        )
        return create_response(500, error_message)


def handle_copy_job_event(detail: Dict[str, Any], full_event: Dict[str, Any]) -> Dict[str, Any]:
    """
    Handle copy job state change events for cross-region backups.
    
    Args:
        detail: Event detail containing copy job information
        full_event: Complete EventBridge event
    
    Returns:
        Dict containing processing results
    """
    copy_job_id = detail.get('copyJobId', '')
    state = detail.get('state', '')
    source_backup_vault = detail.get('sourceBackupVaultName', '')
    destination_backup_vault = detail.get('destinationBackupVaultName', '')
    
    logger.info(f"Processing copy job {copy_job_id} with state: {state}")
    
    try:
        # Get detailed copy job information
        copy_job_details = get_copy_job_details(copy_job_id)
        
        if state in ['COMPLETED']:
            return handle_successful_copy(copy_job_details, detail)
        elif state in ['FAILED', 'ABORTED']:
            return handle_failed_copy(copy_job_details, detail)
        else:
            logger.info(f"Copy job {copy_job_id} in state {state} - monitoring")
            return create_response(200, f"Copy job state {state} acknowledged")
            
    except Exception as e:
        error_message = f"Error handling copy job {copy_job_id}: {str(e)}"
        logger.error(error_message)
        return create_response(500, error_message)


def handle_successful_backup(backup_job: Dict[str, Any], detail: Dict[str, Any]) -> Dict[str, Any]:
    """
    Process successful backup job completion.
    
    Args:
        backup_job: Detailed backup job information
        detail: Event detail
    
    Returns:
        Dict containing processing results
    """
    backup_job_id = backup_job.get('BackupJobId', '')
    resource_arn = backup_job.get('ResourceArn', '')
    recovery_point_arn = backup_job.get('RecoveryPointArn', '')
    backup_size_bytes = backup_job.get('BackupSizeInBytes', 0)
    
    logger.info(f"Backup job {backup_job_id} completed successfully")
    
    # Validate backup integrity
    validation_results = validate_backup_integrity(backup_job)
    
    # Check for cross-region copy jobs
    copy_job_status = check_cross_region_copies(recovery_point_arn)
    
    # Send CloudWatch metrics
    send_backup_metrics(backup_job, 'SUCCESS')
    
    # Send success notification if configured
    if should_send_success_notification():
        send_notification(
            subject="Backup Job Completed Successfully",
            message=format_success_message(backup_job, validation_results, copy_job_status),
            severity="INFO"
        )
    
    logger.info(f"Backup validation completed for job {backup_job_id}")
    return create_response(200, "Backup validation successful")


def handle_failed_backup(backup_job: Dict[str, Any], detail: Dict[str, Any]) -> Dict[str, Any]:
    """
    Process failed backup job.
    
    Args:
        backup_job: Detailed backup job information
        detail: Event detail
    
    Returns:
        Dict containing processing results
    """
    backup_job_id = backup_job.get('BackupJobId', '')
    resource_arn = backup_job.get('ResourceArn', '')
    status_message = backup_job.get('StatusMessage', 'Unknown error')
    state = backup_job.get('State', 'FAILED')
    
    logger.error(f"Backup job {backup_job_id} failed: {status_message}")
    
    # Send CloudWatch metrics
    send_backup_metrics(backup_job, 'FAILED')
    
    # Analyze failure reason
    failure_analysis = analyze_backup_failure(backup_job)
    
    # Send failure notification
    send_notification(
        subject=f"AWS Backup Job Failed - {backup_job_id}",
        message=format_failure_message(backup_job, failure_analysis),
        severity="ERROR"
    )
    
    # Log for operational monitoring
    logger.error(f"Backup failure analysis: {json.dumps(failure_analysis, default=str)}")
    
    return create_response(200, "Backup failure processed")


def handle_running_backup(backup_job: Dict[str, Any], detail: Dict[str, Any]) -> Dict[str, Any]:
    """
    Monitor running backup job for potential issues.
    
    Args:
        backup_job: Detailed backup job information
        detail: Event detail
    
    Returns:
        Dict containing processing results
    """
    backup_job_id = backup_job.get('BackupJobId', '')
    creation_date = backup_job.get('CreationDate')
    
    # Check if backup is running longer than expected
    if creation_date:
        runtime = datetime.now(creation_date.tzinfo) - creation_date
        max_runtime = timedelta(hours=24)  # Configurable threshold
        
        if runtime > max_runtime:
            logger.warning(f"Backup job {backup_job_id} running longer than expected: {runtime}")
            send_notification(
                subject=f"Long Running Backup Job - {backup_job_id}",
                message=f"Backup job {backup_job_id} has been running for {runtime}. Please investigate.",
                severity="WARNING"
            )
    
    return create_response(200, "Running backup monitored")


def handle_successful_copy(copy_job: Dict[str, Any], detail: Dict[str, Any]) -> Dict[str, Any]:
    """
    Process successful cross-region copy job.
    
    Args:
        copy_job: Detailed copy job information
        detail: Event detail
    
    Returns:
        Dict containing processing results
    """
    copy_job_id = copy_job.get('CopyJobId', '')
    destination_region = copy_job.get('DestinationRegion', '')
    
    logger.info(f"Copy job {copy_job_id} to {destination_region} completed successfully")
    
    # Send CloudWatch metrics
    send_copy_metrics(copy_job, 'SUCCESS')
    
    return create_response(200, "Copy job validation successful")


def handle_failed_copy(copy_job: Dict[str, Any], detail: Dict[str, Any]) -> Dict[str, Any]:
    """
    Process failed cross-region copy job.
    
    Args:
        copy_job: Detailed copy job information
        detail: Event detail
    
    Returns:
        Dict containing processing results
    """
    copy_job_id = copy_job.get('CopyJobId', '')
    status_message = copy_job.get('StatusMessage', 'Unknown error')
    destination_region = copy_job.get('DestinationRegion', '')
    
    logger.error(f"Copy job {copy_job_id} to {destination_region} failed: {status_message}")
    
    # Send CloudWatch metrics
    send_copy_metrics(copy_job, 'FAILED')
    
    # Send failure notification
    send_notification(
        subject=f"Cross-Region Copy Job Failed - {copy_job_id}",
        message=format_copy_failure_message(copy_job),
        severity="ERROR"
    )
    
    return create_response(200, "Copy job failure processed")


def get_backup_job_details(backup_job_id: str) -> Dict[str, Any]:
    """Get detailed information about a backup job."""
    try:
        response = backup_client.describe_backup_job(BackupJobId=backup_job_id)
        return response.get('BackupJob', {})
    except Exception as e:
        logger.error(f"Error getting backup job details for {backup_job_id}: {str(e)}")
        raise


def get_copy_job_details(copy_job_id: str) -> Dict[str, Any]:
    """Get detailed information about a copy job."""
    try:
        response = backup_client.describe_copy_job(CopyJobId=copy_job_id)
        return response.get('CopyJob', {})
    except Exception as e:
        logger.error(f"Error getting copy job details for {copy_job_id}: {str(e)}")
        raise


def validate_backup_integrity(backup_job: Dict[str, Any]) -> Dict[str, Any]:
    """
    Validate backup integrity and completeness.
    
    Args:
        backup_job: Backup job details
    
    Returns:
        Dict containing validation results
    """
    validation_results = {
        'recovery_point_validated': False,
        'size_check_passed': False,
        'encryption_validated': False,
        'tags_validated': False
    }
    
    try:
        recovery_point_arn = backup_job.get('RecoveryPointArn')
        if recovery_point_arn:
            # Validate recovery point exists and is accessible
            backup_vault_name = recovery_point_arn.split(':')[5].split('/')[1]
            recovery_point_arn_parts = recovery_point_arn.split('/')
            recovery_point_id = recovery_point_arn_parts[-1]
            
            recovery_point = backup_client.describe_recovery_point(
                BackupVaultName=backup_vault_name,
                RecoveryPointArn=recovery_point_arn
            )
            
            validation_results['recovery_point_validated'] = True
            validation_results['size_check_passed'] = recovery_point.get('BackupSizeInBytes', 0) > 0
            validation_results['encryption_validated'] = bool(recovery_point.get('EncryptionKeyArn'))
            
    except Exception as e:
        logger.warning(f"Backup validation error: {str(e)}")
    
    return validation_results


def check_cross_region_copies(recovery_point_arn: str) -> Dict[str, Any]:
    """
    Check status of cross-region copy jobs for a recovery point.
    
    Args:
        recovery_point_arn: ARN of the recovery point
    
    Returns:
        Dict containing copy job status information
    """
    copy_status = {
        'copy_jobs_found': 0,
        'successful_copies': 0,
        'failed_copies': 0,
        'in_progress_copies': 0
    }
    
    try:
        # List copy jobs for this recovery point
        response = backup_client.list_copy_jobs(
            ByResourceArn=recovery_point_arn,
            MaxResults=100
        )
        
        copy_jobs = response.get('CopyJobs', [])
        copy_status['copy_jobs_found'] = len(copy_jobs)
        
        for copy_job in copy_jobs:
            state = copy_job.get('State', '')
            if state == 'COMPLETED':
                copy_status['successful_copies'] += 1
            elif state in ['FAILED', 'ABORTED']:
                copy_status['failed_copies'] += 1
            elif state in ['CREATED', 'RUNNING']:
                copy_status['in_progress_copies'] += 1
                
    except Exception as e:
        logger.warning(f"Error checking copy jobs: {str(e)}")
    
    return copy_status


def analyze_backup_failure(backup_job: Dict[str, Any]) -> Dict[str, Any]:
    """
    Analyze backup failure to provide actionable insights.
    
    Args:
        backup_job: Failed backup job details
    
    Returns:
        Dict containing failure analysis
    """
    analysis = {
        'failure_category': 'UNKNOWN',
        'likely_cause': 'Unknown error',
        'recommended_action': 'Contact AWS Support',
        'retry_recommended': False
    }
    
    status_message = backup_job.get('StatusMessage', '').lower()
    resource_arn = backup_job.get('ResourceArn', '')
    
    # Categorize common failure types
    if 'permission' in status_message or 'access denied' in status_message:
        analysis.update({
            'failure_category': 'PERMISSIONS',
            'likely_cause': 'Insufficient IAM permissions',
            'recommended_action': 'Check IAM role permissions for AWS Backup service',
            'retry_recommended': False
        })
    elif 'timeout' in status_message:
        analysis.update({
            'failure_category': 'TIMEOUT',
            'likely_cause': 'Backup job exceeded time limits',
            'recommended_action': 'Increase completion window or check resource availability',
            'retry_recommended': True
        })
    elif 'network' in status_message or 'connectivity' in status_message:
        analysis.update({
            'failure_category': 'NETWORK',
            'likely_cause': 'Network connectivity issues',
            'recommended_action': 'Check VPC configuration and security groups',
            'retry_recommended': True
        })
    elif 'resource not found' in status_message:
        analysis.update({
            'failure_category': 'RESOURCE',
            'likely_cause': 'Source resource no longer exists',
            'recommended_action': 'Verify resource exists and update backup selection',
            'retry_recommended': False
        })
    
    return analysis


def send_backup_metrics(backup_job: Dict[str, Any], status: str) -> None:
    """Send backup job metrics to CloudWatch."""
    try:
        resource_type = extract_resource_type(backup_job.get('ResourceArn', ''))
        backup_size_mb = (backup_job.get('BackupSizeInBytes', 0)) / (1024 * 1024)
        
        # Send custom metrics
        cloudwatch_client.put_metric_data(
            Namespace='AWS/Backup/Custom',
            MetricData=[
                {
                    'MetricName': 'BackupJobCount',
                    'Value': 1,
                    'Unit': 'Count',
                    'Dimensions': [
                        {'Name': 'Status', 'Value': status},
                        {'Name': 'ResourceType', 'Value': resource_type}
                    ]
                },
                {
                    'MetricName': 'BackupSizeMB',
                    'Value': backup_size_mb,
                    'Unit': 'None',
                    'Dimensions': [
                        {'Name': 'ResourceType', 'Value': resource_type}
                    ]
                }
            ]
        )
    except Exception as e:
        logger.warning(f"Error sending backup metrics: {str(e)}")


def send_copy_metrics(copy_job: Dict[str, Any], status: str) -> None:
    """Send copy job metrics to CloudWatch."""
    try:
        destination_region = copy_job.get('DestinationRegion', 'unknown')
        
        cloudwatch_client.put_metric_data(
            Namespace='AWS/Backup/Custom',
            MetricData=[
                {
                    'MetricName': 'CopyJobCount',
                    'Value': 1,
                    'Unit': 'Count',
                    'Dimensions': [
                        {'Name': 'Status', 'Value': status},
                        {'Name': 'DestinationRegion', 'Value': destination_region}
                    ]
                }
            ]
        )
    except Exception as e:
        logger.warning(f"Error sending copy metrics: {str(e)}")


def should_send_success_notification() -> bool:
    """Determine if success notifications should be sent."""
    # Configure based on environment or time of day
    return os.environ.get('SEND_SUCCESS_NOTIFICATIONS', 'false').lower() == 'true'


def extract_resource_type(resource_arn: str) -> str:
    """Extract resource type from ARN."""
    try:
        parts = resource_arn.split(':')
        if len(parts) >= 3:
            service = parts[2]
            resource_part = parts[5] if len(parts) > 5 else parts[4]
            
            if service == 'ec2' and 'instance' in resource_part:
                return 'EC2'
            elif service == 'rds':
                return 'RDS'
            elif service == 'dynamodb':
                return 'DynamoDB'
            elif service == 'elasticfilesystem':
                return 'EFS'
            elif service == 'fsx':
                return 'FSx'
            else:
                return service.upper()
    except:
        pass
    
    return 'UNKNOWN'


def format_success_message(backup_job: Dict[str, Any], validation: Dict[str, Any], copy_status: Dict[str, Any]) -> str:
    """Format success notification message."""
    backup_job_id = backup_job.get('BackupJobId', '')
    resource_arn = backup_job.get('ResourceArn', '')
    backup_size_mb = round((backup_job.get('BackupSizeInBytes', 0)) / (1024 * 1024), 2)
    
    message = f"""
Backup Job Completed Successfully

Job ID: {backup_job_id}
Resource: {resource_arn}
Backup Size: {backup_size_mb} MB

Validation Results:
- Recovery Point: {'✓' if validation.get('recovery_point_validated') else '✗'}
- Size Check: {'✓' if validation.get('size_check_passed') else '✗'}
- Encryption: {'✓' if validation.get('encryption_validated') else '✗'}

Cross-Region Copies:
- Total Copy Jobs: {copy_status.get('copy_jobs_found', 0)}
- Successful: {copy_status.get('successful_copies', 0)}
- Failed: {copy_status.get('failed_copies', 0)}
- In Progress: {copy_status.get('in_progress_copies', 0)}
"""
    return message.strip()


def format_failure_message(backup_job: Dict[str, Any], analysis: Dict[str, Any]) -> str:
    """Format failure notification message."""
    backup_job_id = backup_job.get('BackupJobId', '')
    resource_arn = backup_job.get('ResourceArn', '')
    status_message = backup_job.get('StatusMessage', 'Unknown error')
    
    message = f"""
Backup Job Failed

Job ID: {backup_job_id}
Resource: {resource_arn}
Error: {status_message}

Failure Analysis:
- Category: {analysis.get('failure_category', 'UNKNOWN')}
- Likely Cause: {analysis.get('likely_cause', 'Unknown')}
- Recommended Action: {analysis.get('recommended_action', 'Contact support')}
- Retry Recommended: {'Yes' if analysis.get('retry_recommended') else 'No'}

Please investigate and take appropriate action.
"""
    return message.strip()


def format_copy_failure_message(copy_job: Dict[str, Any]) -> str:
    """Format copy job failure notification message."""
    copy_job_id = copy_job.get('CopyJobId', '')
    source_arn = copy_job.get('SourceRecoveryPointArn', '')
    destination_region = copy_job.get('DestinationRegion', '')
    status_message = copy_job.get('StatusMessage', 'Unknown error')
    
    message = f"""
Cross-Region Copy Job Failed

Copy Job ID: {copy_job_id}
Source Recovery Point: {source_arn}
Destination Region: {destination_region}
Error: {status_message}

Cross-region backup redundancy may be compromised. Please investigate immediately.
"""
    return message.strip()


def send_notification(subject: str, message: str, severity: str = "INFO") -> None:
    """Send notification via SNS."""
    try:
        sns_topic_arn = os.environ.get('SNS_TOPIC_ARN')
        if not sns_topic_arn:
            logger.warning("SNS_TOPIC_ARN not configured, skipping notification")
            return
        
        # Add severity and timestamp to message
        enhanced_message = f"""
Severity: {severity}
Timestamp: {datetime.utcnow().isoformat()}Z

{message}

---
AWS Multi-Region Backup Monitoring
Generated by Lambda function: {os.environ.get('AWS_LAMBDA_FUNCTION_NAME', 'Unknown')}
"""
        
        sns_client.publish(
            TopicArn=sns_topic_arn,
            Subject=subject,
            Message=enhanced_message.strip()
        )
        
        logger.info(f"Notification sent: {subject}")
        
    except Exception as e:
        logger.error(f"Error sending notification: {str(e)}")


def send_error_notification(error_message: str, event: Dict[str, Any]) -> None:
    """Send error notification for Lambda function issues."""
    try:
        subject = "Backup Validation Lambda Error"
        message = f"""
Lambda Function Error

Error: {error_message}
Event: {json.dumps(event, default=str, indent=2)}

The backup validation function encountered an error and may need attention.
"""
        send_notification(subject, message, "CRITICAL")
    except Exception as e:
        logger.error(f"Failed to send error notification: {str(e)}")


def create_response(status_code: int, message: str) -> Dict[str, Any]:
    """Create standardized Lambda response."""
    return {
        'statusCode': status_code,
        'body': json.dumps({
            'message': message,
            'timestamp': datetime.utcnow().isoformat() + 'Z'
        })
    }