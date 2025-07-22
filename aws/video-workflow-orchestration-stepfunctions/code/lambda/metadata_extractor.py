"""
Video Metadata Extraction Lambda Function
Extracts metadata from video files for the video processing workflow.
"""

import json
import boto3
import os
import tempfile
from datetime import datetime
from typing import Dict, Any

# Initialize AWS clients
s3_client = boto3.client('s3')
dynamodb = boto3.resource('dynamodb')

def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Lambda function handler for extracting video metadata.
    
    Args:
        event: Event data containing bucket, key, and jobId
        context: Lambda runtime context
        
    Returns:
        Dict containing status, metadata, and job information
    """
    try:
        # Extract input parameters
        bucket = event.get('bucket')
        key = event.get('key')
        job_id = event.get('jobId')
        
        if not all([bucket, key, job_id]):
            raise ValueError("Missing required parameters: bucket, key, or jobId")
        
        print(f"Processing metadata extraction for job {job_id}: {bucket}/{key}")
        
        # Get file information from S3
        try:
            s3_response = s3_client.head_object(Bucket=bucket, Key=key)
            file_size = s3_response['ContentLength']
            last_modified = s3_response['LastModified'].isoformat()
            content_type = s3_response.get('ContentType', 'unknown')
            
            print(f"File size: {file_size} bytes, Content type: {content_type}")
            
        except Exception as e:
            print(f"Error getting S3 object info: {str(e)}")
            raise
        
        # Extract basic metadata (simplified for this example)
        # In a production environment, you would use FFmpeg or similar tools
        metadata = extract_video_metadata(bucket, key, file_size, content_type)
        
        # Store metadata in DynamoDB
        table = dynamodb.Table(os.environ['JOBS_TABLE'])
        update_job_metadata(table, job_id, metadata)
        
        print(f"Successfully extracted metadata for job {job_id}")
        
        return {
            'statusCode': 200,
            'jobId': job_id,
            'metadata': metadata,
            'message': 'Metadata extraction completed successfully'
        }
        
    except Exception as e:
        error_message = f"Error extracting metadata: {str(e)}"
        print(error_message)
        
        # Update job with error status
        try:
            table = dynamodb.Table(os.environ['JOBS_TABLE'])
            update_job_error(table, event.get('jobId', 'unknown'), error_message)
        except Exception as db_error:
            print(f"Failed to update job error status: {str(db_error)}")
        
        return {
            'statusCode': 500,
            'jobId': event.get('jobId', 'unknown'),
            'error': error_message,
            'message': 'Metadata extraction failed'
        }

def extract_video_metadata(bucket: str, key: str, file_size: int, content_type: str) -> Dict[str, Any]:
    """
    Extract video metadata from the file.
    
    Note: This is a simplified implementation. In production, you would:
    1. Download the file to a temporary location
    2. Use FFmpeg or similar tools to extract detailed metadata
    3. Return comprehensive video properties
    
    Args:
        bucket: S3 bucket name
        key: S3 object key
        file_size: File size in bytes
        content_type: MIME content type
        
    Returns:
        Dict containing video metadata
    """
    
    # Determine video format from file extension
    file_extension = key.lower().split('.')[-1] if '.' in key else 'unknown'
    
    # Estimate video properties based on file size and type
    # This is a placeholder implementation - real metadata extraction would use FFmpeg
    estimated_duration = estimate_duration_from_size(file_size, file_extension)
    
    metadata = {
        'file_name': key.split('/')[-1],
        'file_extension': file_extension,
        'file_size_bytes': file_size,
        'file_size_mb': round(file_size / (1024 * 1024), 2),
        'content_type': content_type,
        'estimated_duration_seconds': estimated_duration,
        'estimated_duration_minutes': round(estimated_duration / 60, 2),
        
        # Placeholder video properties (would be extracted using FFmpeg in production)
        'resolution': {
            'width': 1920 if file_size > 100 * 1024 * 1024 else 1280,  # Estimate based on file size
            'height': 1080 if file_size > 100 * 1024 * 1024 else 720
        },
        'estimated_bitrate': estimate_bitrate(file_size, estimated_duration),
        'codec_info': {
            'video_codec': 'h264',  # Most common
            'audio_codec': 'aac'    # Most common
        },
        'frame_rate': 29.97,  # Common frame rate
        
        # Processing metadata
        'extraction_timestamp': datetime.utcnow().isoformat(),
        'extraction_method': 'simplified_estimation',
        'requires_detailed_analysis': True,  # Flag for future detailed analysis
        
        # Quality indicators
        'quality_indicators': {
            'file_size_appropriate': file_size > 1024 * 1024,  # At least 1MB
            'supported_format': file_extension in ['mp4', 'mov', 'avi', 'mkv'],
            'estimated_quality': 'high' if file_size > 100 * 1024 * 1024 else 'medium'
        }
    }
    
    print(f"Extracted metadata: {json.dumps(metadata, indent=2)}")
    return metadata

def estimate_duration_from_size(file_size: int, file_extension: str) -> float:
    """
    Estimate video duration based on file size and format.
    
    Args:
        file_size: File size in bytes
        file_extension: Video file extension
        
    Returns:
        Estimated duration in seconds
    """
    # Rough estimates based on typical bitrates for different formats
    bitrate_estimates = {
        'mp4': 2000000,   # 2 Mbps
        'mov': 3000000,   # 3 Mbps
        'avi': 1500000,   # 1.5 Mbps
        'mkv': 2500000,   # 2.5 Mbps
    }
    
    estimated_bitrate = bitrate_estimates.get(file_extension, 2000000)
    
    # Duration = file_size_bits / bitrate
    duration_seconds = (file_size * 8) / estimated_bitrate
    
    # Reasonable bounds (1 second to 4 hours)
    return max(1.0, min(duration_seconds, 14400.0))

def estimate_bitrate(file_size: int, duration: float) -> int:
    """
    Estimate bitrate from file size and duration.
    
    Args:
        file_size: File size in bytes
        duration: Duration in seconds
        
    Returns:
        Estimated bitrate in bits per second
    """
    if duration <= 0:
        return 0
    
    return int((file_size * 8) / duration)

def update_job_metadata(table: Any, job_id: str, metadata: Dict[str, Any]) -> None:
    """
    Update DynamoDB job record with extracted metadata.
    
    Args:
        table: DynamoDB table resource
        job_id: Job identifier
        metadata: Extracted metadata
    """
    try:
        table.update_item(
            Key={'JobId': job_id},
            UpdateExpression='SET VideoMetadata = :metadata, MetadataExtractedAt = :timestamp, JobStatus = :status',
            ExpressionAttributeValues={
                ':metadata': metadata,
                ':timestamp': datetime.utcnow().isoformat(),
                ':status': 'METADATA_EXTRACTED'
            }
        )
        print(f"Updated job {job_id} with metadata in DynamoDB")
        
    except Exception as e:
        print(f"Error updating DynamoDB: {str(e)}")
        raise

def update_job_error(table: Any, job_id: str, error_message: str) -> None:
    """
    Update DynamoDB job record with error information.
    
    Args:
        table: DynamoDB table resource
        job_id: Job identifier
        error_message: Error description
    """
    try:
        table.update_item(
            Key={'JobId': job_id},
            UpdateExpression='SET JobStatus = :status, ErrorMessage = :error, ErrorTimestamp = :timestamp',
            ExpressionAttributeValues={
                ':status': 'METADATA_EXTRACTION_FAILED',
                ':error': error_message,
                ':timestamp': datetime.utcnow().isoformat()
            }
        )
        print(f"Updated job {job_id} with error status in DynamoDB")
        
    except Exception as e:
        print(f"Error updating DynamoDB with error status: {str(e)}")