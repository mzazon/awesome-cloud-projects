"""
AWS Lambda Function for File Validation
=======================================

This function automatically validates files uploaded to an S3 bucket based on:
- File extension (whitelist approach)
- File size limits
- Basic security checks

Files that pass validation are moved to a "valid" bucket.
Files that fail validation are moved to a "quarantine" bucket.

Environment Variables:
- VALID_BUCKET_NAME: S3 bucket for valid files
- QUARANTINE_BUCKET_NAME: S3 bucket for quarantined files
- MAX_FILE_SIZE_MB: Maximum file size in MB
- ALLOWED_EXTENSIONS: JSON array of allowed file extensions
- LOG_LEVEL: Logging level (DEBUG, INFO, WARNING, ERROR, CRITICAL)
"""

import json
import boto3
import urllib.parse
import os
import logging
from datetime import datetime
from typing import Dict, List, Any, Tuple

# Configure logging
logger = logging.getLogger()
log_level = os.environ.get('LOG_LEVEL', 'INFO')
logger.setLevel(getattr(logging, log_level))

# Initialize AWS clients
s3_client = boto3.client('s3')

# Configuration from environment variables
MAX_FILE_SIZE_MB = int(os.environ.get('MAX_FILE_SIZE_MB', '${max_file_size_mb}'))
MAX_FILE_SIZE_BYTES = MAX_FILE_SIZE_MB * 1024 * 1024

# Parse allowed extensions from environment or use template default
try:
    ALLOWED_EXTENSIONS = json.loads(os.environ.get('ALLOWED_EXTENSIONS', '${allowed_extensions}'))
except json.JSONDecodeError:
    ALLOWED_EXTENSIONS = ${allowed_extensions}

VALID_BUCKET_NAME = os.environ.get('VALID_BUCKET_NAME')
QUARANTINE_BUCKET_NAME = os.environ.get('QUARANTINE_BUCKET_NAME')

# Validation constants
SUSPICIOUS_PATTERNS = [
    '.exe', '.bat', '.cmd', '.com', '.scr', '.pif', '.vbs', '.js', '.jar'
]


def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Main Lambda handler function for processing S3 events.
    
    Args:
        event: S3 event notification containing object details
        context: Lambda runtime context
        
    Returns:
        Response dictionary with status and processing results
    """
    logger.info(f"Processing event: {json.dumps(event, default=str)}")
    
    if not VALID_BUCKET_NAME or not QUARANTINE_BUCKET_NAME:
        logger.error("Required environment variables VALID_BUCKET_NAME or QUARANTINE_BUCKET_NAME not set")
        raise ValueError("Missing required environment variables")
    
    processing_results = []
    
    try:
        # Process each S3 record in the event
        for record in event['Records']:
            if 's3' not in record:
                logger.warning(f"Skipping non-S3 record: {record}")
                continue
                
            result = process_s3_record(record)
            processing_results.append(result)
            
    except Exception as e:
        logger.error(f"Error processing event: {str(e)}")
        raise
    
    # Summary logging
    valid_count = sum(1 for r in processing_results if r.get('valid', False))
    invalid_count = len(processing_results) - valid_count
    
    logger.info(f"Processing complete: {valid_count} valid files, {invalid_count} invalid files")
    
    return {
        'statusCode': 200,
        'body': json.dumps({
            'message': 'File validation completed successfully',
            'processed_files': len(processing_results),
            'valid_files': valid_count,
            'invalid_files': invalid_count,
            'results': processing_results
        }, default=str)
    }


def process_s3_record(record: Dict[str, Any]) -> Dict[str, Any]:
    """
    Process a single S3 record from the event.
    
    Args:
        record: Individual S3 record from the event
        
    Returns:
        Dictionary with processing results
    """
    try:
        # Extract S3 object information
        bucket_name = record['s3']['bucket']['name']
        object_key = urllib.parse.unquote_plus(record['s3']['object']['key'])
        object_size = record['s3']['object']['size']
        
        logger.info(f"Processing file: s3://{bucket_name}/{object_key} (Size: {object_size} bytes)")
        
        # Validate the file
        validation_result = validate_file(object_key, object_size)
        
        # Determine destination bucket
        if validation_result['valid']:
            destination_bucket = VALID_BUCKET_NAME
            logger.info(f"✅ File {object_key} passed validation")
        else:
            destination_bucket = QUARANTINE_BUCKET_NAME
            logger.warning(f"❌ File {object_key} failed validation: {validation_result['reason']}")
        
        # Move file to appropriate destination
        move_result = move_file_to_destination(
            source_bucket=bucket_name,
            source_key=object_key,
            destination_bucket=destination_bucket,
            validation_result=validation_result
        )
        
        return {
            'file': object_key,
            'size_bytes': object_size,
            'valid': validation_result['valid'],
            'reason': validation_result['reason'],
            'destination_bucket': destination_bucket,
            'destination_key': move_result['destination_key'],
            'moved_successfully': move_result['success']
        }
        
    except Exception as e:
        logger.error(f"Error processing S3 record: {str(e)}")
        return {
            'file': record.get('s3', {}).get('object', {}).get('key', 'unknown'),
            'valid': False,
            'reason': f"Processing error: {str(e)}",
            'moved_successfully': False
        }


def validate_file(filename: str, file_size: int) -> Dict[str, Any]:
    """
    Validate a file based on size, extension, and security checks.
    
    Args:
        filename: Name of the file to validate
        file_size: Size of the file in bytes
        
    Returns:
        Dictionary with validation results
    """
    # Check if filename is provided
    if not filename:
        return {'valid': False, 'reason': 'Empty filename'}
    
    # Check file size
    if file_size > MAX_FILE_SIZE_BYTES:
        size_mb = file_size / (1024 * 1024)
        return {
            'valid': False, 
            'reason': f'File size {size_mb:.2f}MB exceeds maximum {MAX_FILE_SIZE_MB}MB'
        }
    
    # Check for minimum file size (prevent empty files)
    if file_size == 0:
        return {'valid': False, 'reason': 'File is empty (0 bytes)'}
    
    # Extract and validate file extension
    if '.' not in filename:
        return {'valid': False, 'reason': 'File has no extension'}
    
    # Get file extension (case insensitive)
    file_extension = '.' + filename.lower().split('.')[-1]
    
    # Check against allowed extensions
    if file_extension not in [ext.lower() for ext in ALLOWED_EXTENSIONS]:
        return {
            'valid': False, 
            'reason': f'File extension {file_extension} not in allowed list: {ALLOWED_EXTENSIONS}'
        }
    
    # Security check: look for suspicious patterns
    filename_lower = filename.lower()
    for suspicious_pattern in SUSPICIOUS_PATTERNS:
        if suspicious_pattern in filename_lower:
            return {
                'valid': False, 
                'reason': f'File contains suspicious pattern: {suspicious_pattern}'
            }
    
    # Check for potential path traversal attacks
    if '../' in filename or '..\\' in filename:
        return {'valid': False, 'reason': 'File path contains directory traversal attempt'}
    
    # Check filename length (prevent overly long names)
    if len(filename) > 255:
        return {'valid': False, 'reason': 'Filename exceeds maximum length (255 characters)'}
    
    # All validations passed
    return {
        'valid': True, 
        'reason': f'File passed all validation checks (size: {file_size} bytes, extension: {file_extension})'
    }


def move_file_to_destination(source_bucket: str, source_key: str, 
                           destination_bucket: str, validation_result: Dict[str, Any]) -> Dict[str, Any]:
    """
    Move file from source bucket to destination bucket with organized structure.
    
    Args:
        source_bucket: Source S3 bucket name
        source_key: Source object key
        destination_bucket: Destination S3 bucket name
        validation_result: Results from file validation
        
    Returns:
        Dictionary with move operation results
    """
    try:
        # Create organized destination path with date and validation status
        current_date = datetime.now()
        date_prefix = current_date.strftime('%Y/%m/%d')
        
        # Add validation status to the path
        status = "valid" if validation_result['valid'] else "quarantine"
        
        # Preserve original filename but organize by date and status
        destination_key = f"{status}/{date_prefix}/{source_key}"
        
        # Copy source object to destination
        copy_source = {'Bucket': source_bucket, 'Key': source_key}
        
        # Add metadata about the validation
        metadata = {
            'validation-status': status,
            'validation-reason': validation_result['reason'][:1000],  # Limit metadata length
            'processed-date': current_date.isoformat(),
            'original-bucket': source_bucket
        }
        
        s3_client.copy_object(
            CopySource=copy_source,
            Bucket=destination_bucket,
            Key=destination_key,
            Metadata=metadata,
            MetadataDirective='REPLACE'
        )
        
        logger.info(f"Copied file to s3://{destination_bucket}/{destination_key}")
        
        # Delete original file from source bucket
        s3_client.delete_object(Bucket=source_bucket, Key=source_key)
        logger.info(f"Deleted original file from s3://{source_bucket}/{source_key}")
        
        return {
            'success': True,
            'destination_key': destination_key,
            'message': f'Successfully moved file to {destination_bucket}'
        }
        
    except Exception as e:
        logger.error(f"Error moving file: {str(e)}")
        return {
            'success': False,
            'destination_key': None,
            'message': f'Failed to move file: {str(e)}'
        }


# Additional utility functions for enhanced functionality

def get_file_metadata(bucket: str, key: str) -> Dict[str, Any]:
    """
    Get metadata for an S3 object.
    
    Args:
        bucket: S3 bucket name
        key: Object key
        
    Returns:
        Dictionary with object metadata
    """
    try:
        response = s3_client.head_object(Bucket=bucket, Key=key)
        return {
            'content_type': response.get('ContentType'),
            'last_modified': response.get('LastModified'),
            'etag': response.get('ETag'),
            'metadata': response.get('Metadata', {})
        }
    except Exception as e:
        logger.warning(f"Could not retrieve metadata for s3://{bucket}/{key}: {str(e)}")
        return {}


def log_validation_metrics(validation_results: List[Dict[str, Any]]) -> None:
    """
    Log metrics about validation results for monitoring.
    
    Args:
        validation_results: List of validation result dictionaries
    """
    if not validation_results:
        return
    
    total_files = len(validation_results)
    valid_files = sum(1 for r in validation_results if r.get('valid', False))
    invalid_files = total_files - valid_files
    
    # Log structured metrics for CloudWatch
    metrics = {
        'total_files_processed': total_files,
        'valid_files': valid_files,
        'invalid_files': invalid_files,
        'validation_success_rate': (valid_files / total_files) * 100 if total_files > 0 else 0
    }
    
    logger.info(f"METRICS: {json.dumps(metrics)}")