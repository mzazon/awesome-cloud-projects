"""
AWS Backup Orchestrator Lambda Function
Handles backup operations, validation, metrics, and notifications for S3 and Glacier backup strategy.
"""

import json
import boto3
import os
from datetime import datetime, timezone
import logging
from typing import Dict, Any, Tuple

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize AWS clients
s3_client = boto3.client('s3')
sns_client = boto3.client('sns')
cloudwatch_client = boto3.client('cloudwatch')


def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Main Lambda handler for backup orchestration.
    
    Args:
        event: Lambda event containing backup parameters
        context: Lambda context object
        
    Returns:
        Response dictionary with status and details
    """
    # Get environment variables
    backup_bucket = os.environ.get('BACKUP_BUCKET')
    sns_topic_arn = os.environ.get('SNS_TOPIC_ARN')
    
    if not backup_bucket or not sns_topic_arn:
        error_msg = "Missing required environment variables"
        logger.error(error_msg)
        return {
            'statusCode': 500,
            'body': json.dumps({'error': error_msg})
        }
    
    try:
        # Extract backup parameters from event
        backup_type = event.get('backup_type', 'incremental')
        source_prefix = event.get('source_prefix', 'data/')
        
        logger.info(f"Starting {backup_type} backup for prefix: {source_prefix}")
        
        # Perform backup operation
        timestamp = datetime.now(timezone.utc).strftime('%Y%m%d_%H%M%S')
        backup_key = f"backups/{backup_type}/{timestamp}/"
        
        # Execute backup workflow
        backup_result = execute_backup_workflow(
            backup_bucket, 
            backup_key, 
            backup_type, 
            source_prefix
        )
        
        # Validate backup integrity
        validation_result = validate_backup(backup_bucket, backup_key)
        
        # Send CloudWatch metrics
        send_cloudwatch_metrics(backup_result, validation_result)
        
        # Prepare response message
        status = 'SUCCESS' if validation_result else 'FAILED'
        message = {
            'backup_type': backup_type,
            'timestamp': timestamp,
            'status': status,
            'bucket': backup_bucket,
            'backup_location': backup_key,
            'files_processed': backup_result.get('files_processed', 0),
            'total_size_bytes': backup_result.get('total_size_bytes', 0),
            'duration_seconds': backup_result.get('duration_seconds', 0)
        }
        
        # Send notification
        send_notification(sns_topic_arn, message, status)
        
        logger.info(f"Backup completed successfully: {message}")
        
        return {
            'statusCode': 200,
            'body': json.dumps(message)
        }
        
    except Exception as e:
        logger.error(f"Backup failed: {str(e)}", exc_info=True)
        
        # Send failure notification
        error_message = {
            'backup_type': event.get('backup_type', 'unknown'),
            'timestamp': datetime.now(timezone.utc).isoformat(),
            'status': 'FAILED',
            'error': str(e),
            'bucket': backup_bucket
        }
        
        send_notification(sns_topic_arn, error_message, 'FAILED')
        
        # Send failure metrics
        send_cloudwatch_metrics({'success': False}, False)
        
        return {
            'statusCode': 500,
            'body': json.dumps(error_message)
        }


def execute_backup_workflow(
    bucket_name: str, 
    backup_key: str, 
    backup_type: str, 
    source_prefix: str
) -> Dict[str, Any]:
    """
    Execute the backup workflow by copying and organizing files.
    
    Args:
        bucket_name: Target S3 bucket name
        backup_key: Backup location prefix
        backup_type: Type of backup (incremental/full)
        source_prefix: Source data prefix
        
    Returns:
        Dictionary with backup operation results
    """
    start_time = datetime.now(timezone.utc)
    files_processed = 0
    total_size_bytes = 0
    
    try:
        # List objects in the source prefix
        paginator = s3_client.get_paginator('list_objects_v2')
        page_iterator = paginator.paginate(
            Bucket=bucket_name,
            Prefix=source_prefix
        )
        
        # Process objects based on backup type
        for page in page_iterator:
            if 'Contents' in page:
                for obj in page['Contents']:
                    source_key = obj['Key']
                    object_size = obj['Size']
                    
                    # Skip directories (keys ending with '/')
                    if source_key.endswith('/'):
                        continue
                    
                    # Determine if object should be included in backup
                    if should_include_object(obj, backup_type):
                        # Create backup copy with metadata
                        backup_object_key = f"{backup_key}{source_key}"
                        
                        # Copy object to backup location
                        copy_source = {'Bucket': bucket_name, 'Key': source_key}
                        s3_client.copy_object(
                            CopySource=copy_source,
                            Bucket=bucket_name,
                            Key=backup_object_key,
                            MetadataDirective='COPY',
                            TaggingDirective='COPY'
                        )
                        
                        files_processed += 1
                        total_size_bytes += object_size
                        
                        logger.debug(f"Backed up: {source_key} -> {backup_object_key}")
        
        # Create backup manifest
        create_backup_manifest(
            bucket_name, 
            backup_key, 
            backup_type, 
            files_processed, 
            total_size_bytes
        )
        
        end_time = datetime.now(timezone.utc)
        duration_seconds = (end_time - start_time).total_seconds()
        
        return {
            'success': True,
            'files_processed': files_processed,
            'total_size_bytes': total_size_bytes,
            'duration_seconds': duration_seconds,
            'backup_location': backup_key
        }
        
    except Exception as e:
        logger.error(f"Backup workflow failed: {str(e)}")
        raise


def should_include_object(obj: Dict[str, Any], backup_type: str) -> bool:
    """
    Determine if an object should be included in the backup based on type and criteria.
    
    Args:
        obj: S3 object metadata
        backup_type: Type of backup (incremental/full)
        
    Returns:
        True if object should be included, False otherwise
    """
    if backup_type == 'full':
        return True
    
    # For incremental backups, include objects modified in the last 24 hours
    if backup_type == 'incremental':
        last_modified = obj['LastModified']
        now = datetime.now(timezone.utc)
        time_diff = now - last_modified.replace(tzinfo=timezone.utc)
        return time_diff.total_seconds() <= 86400  # 24 hours
    
    return True


def create_backup_manifest(
    bucket_name: str, 
    backup_key: str, 
    backup_type: str, 
    files_count: int, 
    total_size: int
) -> None:
    """
    Create a backup manifest file with metadata about the backup operation.
    
    Args:
        bucket_name: Target S3 bucket name
        backup_key: Backup location prefix
        backup_type: Type of backup performed
        files_count: Number of files backed up
        total_size: Total size of backed up data in bytes
    """
    manifest = {
        'backup_type': backup_type,
        'timestamp': datetime.now(timezone.utc).isoformat(),
        'files_count': files_count,
        'total_size_bytes': total_size,
        'bucket': bucket_name,
        'backup_location': backup_key,
        'version': '1.0'
    }
    
    manifest_key = f"{backup_key}backup_manifest.json"
    
    s3_client.put_object(
        Bucket=bucket_name,
        Key=manifest_key,
        Body=json.dumps(manifest, indent=2),
        ContentType='application/json',
        Metadata={
            'backup-type': backup_type,
            'files-count': str(files_count),
            'total-size': str(total_size)
        }
    )
    
    logger.info(f"Backup manifest created: {manifest_key}")


def validate_backup(bucket_name: str, backup_key: str) -> bool:
    """
    Validate backup integrity and completeness.
    
    Args:
        bucket_name: S3 bucket name
        backup_key: Backup location prefix
        
    Returns:
        True if backup validation passes, False otherwise
    """
    try:
        # Check if backup manifest exists
        manifest_key = f"{backup_key}backup_manifest.json"
        
        try:
            response = s3_client.head_object(Bucket=bucket_name, Key=manifest_key)
            logger.info("Backup manifest found and accessible")
        except s3_client.exceptions.NoSuchKey:
            logger.warning("Backup manifest not found")
            return False
        
        # Check if backup location has objects
        response = s3_client.list_objects_v2(
            Bucket=bucket_name,
            Prefix=backup_key,
            MaxKeys=1
        )
        
        if 'Contents' not in response or len(response['Contents']) == 0:
            logger.warning("No backup files found in backup location")
            return False
        
        # Additional validation checks could include:
        # 1. Verify file checksums
        # 2. Test restoration of sample files
        # 3. Validate backup completeness against source
        # 4. Check storage class transitions
        
        logger.info("Backup validation completed successfully")
        return True
        
    except Exception as e:
        logger.error(f"Backup validation failed: {str(e)}")
        return False


def send_cloudwatch_metrics(backup_result: Dict[str, Any], validation_result: bool) -> None:
    """
    Send custom metrics to CloudWatch for monitoring backup operations.
    
    Args:
        backup_result: Dictionary containing backup operation results
        validation_result: Boolean indicating if backup validation passed
    """
    try:
        metrics = []
        
        # Backup success metric
        metrics.append({
            'MetricName': 'BackupSuccess',
            'Value': 1 if backup_result.get('success', False) and validation_result else 0,
            'Unit': 'Count',
            'Timestamp': datetime.now(timezone.utc)
        })
        
        # Backup duration metric
        if 'duration_seconds' in backup_result:
            metrics.append({
                'MetricName': 'BackupDuration',
                'Value': backup_result['duration_seconds'],
                'Unit': 'Seconds',
                'Timestamp': datetime.now(timezone.utc)
            })
        
        # Files processed metric
        if 'files_processed' in backup_result:
            metrics.append({
                'MetricName': 'FilesProcessed',
                'Value': backup_result['files_processed'],
                'Unit': 'Count',
                'Timestamp': datetime.now(timezone.utc)
            })
        
        # Data size metric
        if 'total_size_bytes' in backup_result:
            metrics.append({
                'MetricName': 'DataSizeBytes',
                'Value': backup_result['total_size_bytes'],
                'Unit': 'Bytes',
                'Timestamp': datetime.now(timezone.utc)
            })
        
        # Send metrics to CloudWatch
        cloudwatch_client.put_metric_data(
            Namespace='BackupStrategy',
            MetricData=metrics
        )
        
        logger.info(f"Sent {len(metrics)} metrics to CloudWatch")
        
    except Exception as e:
        logger.error(f"Failed to send CloudWatch metrics: {str(e)}")


def send_notification(sns_topic_arn: str, message: Dict[str, Any], status: str) -> None:
    """
    Send backup status notification via SNS.
    
    Args:
        sns_topic_arn: SNS topic ARN for notifications
        message: Message content dictionary
        status: Backup status (SUCCESS/FAILED)
    """
    try:
        subject = f"Backup {status}: {message.get('backup_type', 'Unknown')}"
        
        # Format message for better readability
        formatted_message = format_notification_message(message, status)
        
        sns_client.publish(
            TopicArn=sns_topic_arn,
            Message=formatted_message,
            Subject=subject
        )
        
        logger.info(f"Notification sent: {subject}")
        
    except Exception as e:
        logger.error(f"Failed to send notification: {str(e)}")


def format_notification_message(message: Dict[str, Any], status: str) -> str:
    """
    Format the notification message for better readability.
    
    Args:
        message: Message content dictionary
        status: Backup status
        
    Returns:
        Formatted message string
    """
    if status == 'SUCCESS':
        return f"""
Backup Operation Completed Successfully

Details:
- Backup Type: {message.get('backup_type', 'Unknown')}
- Timestamp: {message.get('timestamp', 'Unknown')}
- S3 Bucket: {message.get('bucket', 'Unknown')}
- Backup Location: {message.get('backup_location', 'Unknown')}
- Files Processed: {message.get('files_processed', 0)}
- Total Size: {format_bytes(message.get('total_size_bytes', 0))}
- Duration: {message.get('duration_seconds', 0):.2f} seconds

The backup has been successfully stored and is available for recovery.
"""
    else:
        return f"""
Backup Operation Failed

Details:
- Backup Type: {message.get('backup_type', 'Unknown')}
- Timestamp: {message.get('timestamp', 'Unknown')}
- S3 Bucket: {message.get('bucket', 'Unknown')}
- Error: {message.get('error', 'Unknown error occurred')}

Please investigate the issue and ensure backup operations are restored.
"""


def format_bytes(bytes_value: int) -> str:
    """
    Format bytes into human-readable format.
    
    Args:
        bytes_value: Number of bytes
        
    Returns:
        Formatted string with appropriate unit
    """
    for unit in ['B', 'KB', 'MB', 'GB', 'TB']:
        if bytes_value < 1024.0:
            return f"{bytes_value:.2f} {unit}"
        bytes_value /= 1024.0
    return f"{bytes_value:.2f} PB"