"""
Checkpoint Manager Lambda Function

This function manages checkpoints for fault-tolerant HPC workflows, providing
state persistence and recovery capabilities across infrastructure failures.

Features:
- Save workflow checkpoints to S3 with metadata in DynamoDB
- Restore checkpoints for workflow resumption
- List and query checkpoint history
- Automatic cleanup of old checkpoints
- Compression and encryption support
- Hierarchical checkpoint organization
"""

import json
import boto3
import logging
import uuid
import gzip
import base64
from datetime import datetime, timedelta
from typing import Dict, List, Any, Optional

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize AWS clients
s3 = boto3.client('s3')
dynamodb = boto3.resource('dynamodb')
cloudwatch = boto3.client('cloudwatch')

# Configuration constants
PROJECT_NAME = "${project_name}"
REGION = "${region}"
CHECKPOINT_PREFIX = "checkpoints"
COMPRESSION_THRESHOLD = 1024  # Compress checkpoints larger than 1KB
MAX_CHECKPOINT_AGE_DAYS = 30


def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Main Lambda handler for checkpoint management operations.
    
    Args:
        event: Lambda event containing action and parameters
        context: Lambda context object
        
    Returns:
        Dict containing operation results and status
    """
    try:
        logger.info(f"Received event: {json.dumps(event, default=str)}")
        
        action = event.get('action', 'save')
        
        if action == 'save':
            return save_checkpoint(event)
        elif action == 'restore':
            return restore_checkpoint(event)
        elif action == 'list':
            return list_checkpoints(event)
        elif action == 'cleanup':
            return cleanup_old_checkpoints(event)
        elif action == 'delete':
            return delete_checkpoint(event)
        elif action == 'get_stats':
            return get_checkpoint_stats(event)
        else:
            raise ValueError(f"Unknown action: {action}")
            
    except Exception as e:
        logger.error(f"Error in checkpoint manager: {str(e)}")
        return {
            'statusCode': 500,
            'error': str(e),
            'action': event.get('action', 'unknown')
        }


def save_checkpoint(event: Dict[str, Any]) -> Dict[str, Any]:
    """
    Save workflow checkpoint to S3 and metadata to DynamoDB.
    
    Args:
        event: Event containing checkpoint data and metadata
        
    Returns:
        Dict containing checkpoint ID and storage information
    """
    try:
        # Extract required parameters
        workflow_id = event.get('workflow_id')
        task_id = event.get('task_id')
        checkpoint_data = event.get('checkpoint_data')
        bucket_name = event.get('bucket_name')
        table_name = event.get('table_name')
        
        # Validate required parameters
        if not workflow_id:
            raise ValueError("workflow_id is required")
        if not task_id:
            raise ValueError("task_id is required")
        if not checkpoint_data:
            raise ValueError("checkpoint_data is required")
        if not bucket_name:
            raise ValueError("bucket_name is required")
        if not table_name:
            raise ValueError("table_name is required")
        
        # Generate checkpoint ID and timestamp
        checkpoint_id = str(uuid.uuid4())
        timestamp = datetime.utcnow().isoformat()
        
        # Prepare checkpoint data
        checkpoint_json = json.dumps(checkpoint_data, default=str)
        
        # Compress if data is large
        compressed = False
        if len(checkpoint_json) > COMPRESSION_THRESHOLD:
            checkpoint_bytes = gzip.compress(checkpoint_json.encode('utf-8'))
            checkpoint_content = base64.b64encode(checkpoint_bytes).decode('utf-8')
            compressed = True
            content_encoding = 'gzip'
        else:
            checkpoint_content = checkpoint_json
            content_encoding = None
        
        # Create S3 key with hierarchical structure
        s3_key = f"{CHECKPOINT_PREFIX}/{workflow_id}/{task_id}/{checkpoint_id}.json"
        
        # Prepare S3 object metadata
        s3_metadata = {
            'workflow_id': workflow_id,
            'task_id': task_id,
            'checkpoint_id': checkpoint_id,
            'timestamp': timestamp,
            'compressed': str(compressed),
            'original_size': str(len(checkpoint_json))
        }
        
        # Save checkpoint data to S3
        s3_put_args = {
            'Bucket': bucket_name,
            'Key': s3_key,
            'Body': checkpoint_content,
            'ContentType': 'application/json',
            'Metadata': s3_metadata
        }
        
        if content_encoding:
            s3_put_args['ContentEncoding'] = content_encoding
        
        s3.put_object(**s3_put_args)
        
        # Calculate data size
        data_size = len(checkpoint_content)
        
        # Update DynamoDB with checkpoint metadata
        table = dynamodb.Table(table_name)
        
        # Calculate expiration time (30 days from now)
        expiration_time = datetime.utcnow() + timedelta(days=MAX_CHECKPOINT_AGE_DAYS)
        
        item = {
            'WorkflowId': workflow_id,
            'TaskId': task_id,
            'CheckpointId': checkpoint_id,
            'S3Key': s3_key,
            'S3Bucket': bucket_name,
            'Timestamp': timestamp,
            'Status': 'saved',
            'DataSize': data_size,
            'Compressed': compressed,
            'OriginalSize': len(checkpoint_json),
            'ExpirationTime': int(expiration_time.timestamp()),
            'CreatedAt': timestamp,
            'UpdatedAt': timestamp
        }
        
        # Add optional metadata
        if 'metadata' in event:
            item['Metadata'] = event['metadata']
        
        table.put_item(Item=item)
        
        # Send CloudWatch metrics
        send_cloudwatch_metric('CheckpointSaved', 1, workflow_id, task_id)
        send_cloudwatch_metric('CheckpointSize', data_size, workflow_id, task_id)
        
        logger.info(f"Checkpoint saved: {checkpoint_id} for workflow {workflow_id}, task {task_id}")
        
        return {
            'statusCode': 200,
            'checkpoint_id': checkpoint_id,
            's3_key': s3_key,
            's3_bucket': bucket_name,
            'timestamp': timestamp,
            'data_size': data_size,
            'compressed': compressed,
            'original_size': len(checkpoint_json)
        }
        
    except Exception as e:
        logger.error(f"Error saving checkpoint: {str(e)}")
        raise


def restore_checkpoint(event: Dict[str, Any]) -> Dict[str, Any]:
    """
    Restore latest checkpoint for a workflow task.
    
    Args:
        event: Event containing workflow and task identifiers
        
    Returns:
        Dict containing restored checkpoint data
    """
    try:
        workflow_id = event.get('workflow_id')
        task_id = event.get('task_id')
        bucket_name = event.get('bucket_name')
        table_name = event.get('table_name')
        checkpoint_id = event.get('checkpoint_id')  # Optional: restore specific checkpoint
        
        # Validate required parameters
        if not workflow_id:
            raise ValueError("workflow_id is required")
        if not task_id:
            raise ValueError("task_id is required")
        if not bucket_name:
            raise ValueError("bucket_name is required")
        if not table_name:
            raise ValueError("table_name is required")
        
        table = dynamodb.Table(table_name)
        
        # Query for checkpoints
        if checkpoint_id:
            # Restore specific checkpoint
            response = table.get_item(
                Key={
                    'WorkflowId': workflow_id,
                    'TaskId': task_id
                },
                FilterExpression='CheckpointId = :cid',
                ExpressionAttributeValues={':cid': checkpoint_id}
            )
            
            if 'Item' not in response:
                return {
                    'statusCode': 404,
                    'message': f'Checkpoint {checkpoint_id} not found'
                }
                
            checkpoint_metadata = response['Item']
        else:
            # Restore latest checkpoint
            response = table.query(
                KeyConditionExpression='WorkflowId = :wid AND TaskId = :tid',
                ExpressionAttributeValues={
                    ':wid': workflow_id,
                    ':tid': task_id
                },
                ScanIndexForward=False,  # Latest first
                Limit=1
            )
            
            if not response['Items']:
                return {
                    'statusCode': 404,
                    'message': 'No checkpoint found'
                }
                
            checkpoint_metadata = response['Items'][0]
        
        # Retrieve checkpoint data from S3
        s3_key = checkpoint_metadata['S3Key']
        s3_bucket = checkpoint_metadata.get('S3Bucket', bucket_name)
        
        s3_response = s3.get_object(
            Bucket=s3_bucket,
            Key=s3_key
        )
        
        # Read and decompress if needed
        checkpoint_content = s3_response['Body'].read()
        
        if checkpoint_metadata.get('Compressed', False):
            # Decode base64 and decompress
            checkpoint_bytes = base64.b64decode(checkpoint_content)
            checkpoint_json = gzip.decompress(checkpoint_bytes).decode('utf-8')
        else:
            checkpoint_json = checkpoint_content.decode('utf-8')
        
        # Parse checkpoint data
        checkpoint_data = json.loads(checkpoint_json)
        
        # Send CloudWatch metrics
        send_cloudwatch_metric('CheckpointRestored', 1, workflow_id, task_id)
        
        logger.info(f"Checkpoint restored: {checkpoint_metadata['CheckpointId']} for workflow {workflow_id}, task {task_id}")
        
        return {
            'statusCode': 200,
            'checkpoint_id': checkpoint_metadata['CheckpointId'],
            'checkpoint_data': checkpoint_data,
            'timestamp': checkpoint_metadata['Timestamp'],
            'data_size': checkpoint_metadata.get('DataSize', 0),
            'original_size': checkpoint_metadata.get('OriginalSize', 0),
            'compressed': checkpoint_metadata.get('Compressed', False)
        }
        
    except Exception as e:
        logger.error(f"Error restoring checkpoint: {str(e)}")
        raise


def list_checkpoints(event: Dict[str, Any]) -> Dict[str, Any]:
    """
    List all checkpoints for a workflow or task.
    
    Args:
        event: Event containing workflow identifier and optional filters
        
    Returns:
        Dict containing list of checkpoints
    """
    try:
        workflow_id = event.get('workflow_id')
        task_id = event.get('task_id')
        table_name = event.get('table_name')
        limit = event.get('limit', 50)
        
        if not workflow_id:
            raise ValueError("workflow_id is required")
        if not table_name:
            raise ValueError("table_name is required")
        
        table = dynamodb.Table(table_name)
        
        # Query based on parameters
        if task_id:
            # List checkpoints for specific task
            response = table.query(
                KeyConditionExpression='WorkflowId = :wid AND TaskId = :tid',
                ExpressionAttributeValues={
                    ':wid': workflow_id,
                    ':tid': task_id
                },
                ScanIndexForward=False,  # Latest first
                Limit=limit
            )
        else:
            # List all checkpoints for workflow
            response = table.query(
                KeyConditionExpression='WorkflowId = :wid',
                ExpressionAttributeValues={
                    ':wid': workflow_id
                },
                ScanIndexForward=False,  # Latest first
                Limit=limit
            )
        
        # Process checkpoints
        checkpoints = []
        for item in response['Items']:
            checkpoint_info = {
                'checkpoint_id': item['CheckpointId'],
                'task_id': item['TaskId'],
                'timestamp': item['Timestamp'],
                'status': item.get('Status', 'unknown'),
                'data_size': item.get('DataSize', 0),
                'compressed': item.get('Compressed', False),
                's3_key': item.get('S3Key', '')
            }
            
            # Add metadata if available
            if 'Metadata' in item:
                checkpoint_info['metadata'] = item['Metadata']
            
            checkpoints.append(checkpoint_info)
        
        return {
            'statusCode': 200,
            'workflow_id': workflow_id,
            'task_id': task_id,
            'checkpoints': checkpoints,
            'count': len(checkpoints),
            'has_more': 'LastEvaluatedKey' in response
        }
        
    except Exception as e:
        logger.error(f"Error listing checkpoints: {str(e)}")
        raise


def cleanup_old_checkpoints(event: Dict[str, Any]) -> Dict[str, Any]:
    """
    Clean up checkpoints older than specified days.
    
    Args:
        event: Event containing cleanup parameters
        
    Returns:
        Dict containing cleanup results
    """
    try:
        days_to_keep = event.get('days_to_keep', MAX_CHECKPOINT_AGE_DAYS)
        bucket_name = event.get('bucket_name')
        table_name = event.get('table_name')
        workflow_id = event.get('workflow_id')  # Optional: cleanup specific workflow
        
        if not bucket_name:
            raise ValueError("bucket_name is required")
        if not table_name:
            raise ValueError("table_name is required")
        
        # Calculate cutoff time
        cutoff_time = datetime.utcnow() - timedelta(days=days_to_keep)
        cutoff_timestamp = cutoff_time.isoformat()
        
        table = dynamodb.Table(table_name)
        
        # Query for old checkpoints
        scan_kwargs = {
            'FilterExpression': 'Timestamp < :cutoff',
            'ExpressionAttributeValues': {':cutoff': cutoff_timestamp}
        }
        
        if workflow_id:
            scan_kwargs['KeyConditionExpression'] = 'WorkflowId = :wid'
            scan_kwargs['ExpressionAttributeValues'][':wid'] = workflow_id
        
        deleted_count = 0
        total_size_deleted = 0
        
        # Scan for old checkpoints
        response = table.scan(**scan_kwargs)
        
        for item in response['Items']:
            try:
                # Delete from S3
                s3_key = item.get('S3Key')
                s3_bucket = item.get('S3Bucket', bucket_name)
                
                if s3_key:
                    s3.delete_object(Bucket=s3_bucket, Key=s3_key)
                    total_size_deleted += item.get('DataSize', 0)
                
                # Delete from DynamoDB
                table.delete_item(
                    Key={
                        'WorkflowId': item['WorkflowId'],
                        'TaskId': item['TaskId']
                    }
                )
                
                deleted_count += 1
                
            except Exception as e:
                logger.error(f"Error deleting checkpoint {item.get('CheckpointId', 'unknown')}: {str(e)}")
                # Continue with other checkpoints
        
        # Send CloudWatch metrics
        send_cloudwatch_metric('CheckpointsDeleted', deleted_count, workflow_id or 'all')
        send_cloudwatch_metric('StorageFreed', total_size_deleted, workflow_id or 'all')
        
        logger.info(f"Cleanup completed: deleted {deleted_count} checkpoints, freed {total_size_deleted} bytes")
        
        return {
            'statusCode': 200,
            'message': f'Cleanup completed for checkpoints older than {days_to_keep} days',
            'deleted_count': deleted_count,
            'total_size_deleted': total_size_deleted,
            'cutoff_date': cutoff_timestamp
        }
        
    except Exception as e:
        logger.error(f"Error cleaning up checkpoints: {str(e)}")
        raise


def delete_checkpoint(event: Dict[str, Any]) -> Dict[str, Any]:
    """
    Delete a specific checkpoint.
    
    Args:
        event: Event containing checkpoint identifiers
        
    Returns:
        Dict containing deletion results
    """
    try:
        workflow_id = event.get('workflow_id')
        task_id = event.get('task_id')
        checkpoint_id = event.get('checkpoint_id')
        bucket_name = event.get('bucket_name')
        table_name = event.get('table_name')
        
        if not all([workflow_id, task_id, checkpoint_id, bucket_name, table_name]):
            raise ValueError("workflow_id, task_id, checkpoint_id, bucket_name, and table_name are required")
        
        table = dynamodb.Table(table_name)
        
        # Get checkpoint metadata
        response = table.get_item(
            Key={
                'WorkflowId': workflow_id,
                'TaskId': task_id
            }
        )
        
        if 'Item' not in response:
            return {
                'statusCode': 404,
                'message': 'Checkpoint not found'
            }
        
        checkpoint_metadata = response['Item']
        
        # Delete from S3
        s3_key = checkpoint_metadata.get('S3Key')
        if s3_key:
            s3.delete_object(Bucket=bucket_name, Key=s3_key)
        
        # Delete from DynamoDB
        table.delete_item(
            Key={
                'WorkflowId': workflow_id,
                'TaskId': task_id
            }
        )
        
        # Send CloudWatch metrics
        send_cloudwatch_metric('CheckpointDeleted', 1, workflow_id, task_id)
        
        return {
            'statusCode': 200,
            'message': f'Checkpoint {checkpoint_id} deleted successfully',
            'checkpoint_id': checkpoint_id
        }
        
    except Exception as e:
        logger.error(f"Error deleting checkpoint: {str(e)}")
        raise


def get_checkpoint_stats(event: Dict[str, Any]) -> Dict[str, Any]:
    """
    Get statistics about checkpoints.
    
    Args:
        event: Event containing query parameters
        
    Returns:
        Dict containing checkpoint statistics
    """
    try:
        workflow_id = event.get('workflow_id')
        table_name = event.get('table_name')
        
        if not table_name:
            raise ValueError("table_name is required")
        
        table = dynamodb.Table(table_name)
        
        # Query for checkpoints
        if workflow_id:
            response = table.query(
                KeyConditionExpression='WorkflowId = :wid',
                ExpressionAttributeValues={':wid': workflow_id}
            )
        else:
            response = table.scan()
        
        # Calculate statistics
        total_checkpoints = len(response['Items'])
        total_size = sum(item.get('DataSize', 0) for item in response['Items'])
        compressed_count = sum(1 for item in response['Items'] if item.get('Compressed', False))
        
        # Group by task
        task_stats = {}
        for item in response['Items']:
            task_id = item['TaskId']
            if task_id not in task_stats:
                task_stats[task_id] = {
                    'count': 0,
                    'total_size': 0,
                    'latest_timestamp': None
                }
            
            task_stats[task_id]['count'] += 1
            task_stats[task_id]['total_size'] += item.get('DataSize', 0)
            
            timestamp = item.get('Timestamp')
            if not task_stats[task_id]['latest_timestamp'] or timestamp > task_stats[task_id]['latest_timestamp']:
                task_stats[task_id]['latest_timestamp'] = timestamp
        
        return {
            'statusCode': 200,
            'workflow_id': workflow_id,
            'total_checkpoints': total_checkpoints,
            'total_size': total_size,
            'compressed_count': compressed_count,
            'compression_ratio': compressed_count / max(total_checkpoints, 1),
            'task_stats': task_stats
        }
        
    except Exception as e:
        logger.error(f"Error getting checkpoint stats: {str(e)}")
        raise


def send_cloudwatch_metric(metric_name: str, value: float, workflow_id: str, task_id: str = None) -> None:
    """
    Send custom metric to CloudWatch.
    
    Args:
        metric_name: Name of the metric
        value: Metric value
        workflow_id: Workflow ID for dimensions
        task_id: Optional task ID for dimensions
    """
    try:
        dimensions = [
            {'Name': 'WorkflowId', 'Value': workflow_id},
            {'Name': 'Region', 'Value': REGION}
        ]
        
        if task_id:
            dimensions.append({'Name': 'TaskId', 'Value': task_id})
        
        cloudwatch.put_metric_data(
            Namespace=f'{PROJECT_NAME}/Checkpoints',
            MetricData=[
                {
                    'MetricName': metric_name,
                    'Value': value,
                    'Unit': 'Count' if 'Size' not in metric_name else 'Bytes',
                    'Dimensions': dimensions,
                    'Timestamp': datetime.utcnow()
                }
            ]
        )
        
    except Exception as e:
        logger.error(f"Error sending CloudWatch metric: {str(e)}")
        # Don't raise exception for metrics - they're not critical