"""
Video Quality Control Lambda Function
Validates video processing outputs for quality standards in the video workflow.
"""

import json
import boto3
import os
from datetime import datetime
from typing import Dict, Any, List

# Initialize AWS clients
s3_client = boto3.client('s3')
dynamodb = boto3.resource('dynamodb')

def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Lambda function handler for video quality control validation.
    
    Args:
        event: Event data containing jobId, outputs, and metadata
        context: Lambda runtime context
        
    Returns:
        Dict containing quality results and pass/fail status
    """
    try:
        # Extract input parameters
        job_id = event.get('jobId')
        outputs = event.get('outputs', [])
        metadata = event.get('metadata', {})
        
        if not job_id:
            raise ValueError("Missing required parameter: jobId")
        
        print(f"Starting quality control for job {job_id} with {len(outputs)} outputs")
        
        # Perform quality validation on each output
        quality_results = []
        for output in outputs:
            quality_check = perform_quality_validation(output, metadata)
            quality_results.append(quality_check)
            print(f"Quality check for {output.get('format', 'unknown')}: score={quality_check.get('score', 0)}")
        
        # Calculate overall quality score
        overall_score = calculate_overall_quality(quality_results)
        quality_threshold = float(os.environ.get('QUALITY_THRESHOLD', '0.8'))
        quality_passed = overall_score >= quality_threshold
        
        print(f"Overall quality score: {overall_score:.3f}, threshold: {quality_threshold}, passed: {quality_passed}")
        
        # Store quality results in DynamoDB
        table = dynamodb.Table(os.environ['JOBS_TABLE'])
        update_quality_results(table, job_id, quality_results, overall_score, quality_passed)
        
        return {
            'statusCode': 200,
            'jobId': job_id,
            'qualityResults': quality_results,
            'qualityScore': overall_score,
            'qualityThreshold': quality_threshold,
            'passed': quality_passed,
            'message': f"Quality control completed - {'PASSED' if quality_passed else 'FAILED'}"
        }
        
    except Exception as e:
        error_message = f"Error in quality control: {str(e)}"
        print(error_message)
        
        # Update job with error status
        try:
            table = dynamodb.Table(os.environ['JOBS_TABLE'])
            update_quality_error(table, event.get('jobId', 'unknown'), error_message)
        except Exception as db_error:
            print(f"Failed to update job error status: {str(db_error)}")
        
        return {
            'statusCode': 500,
            'jobId': event.get('jobId', 'unknown'),
            'error': error_message,
            'passed': False,
            'message': 'Quality control failed due to error'
        }

def perform_quality_validation(output: Dict[str, Any], metadata: Dict[str, Any]) -> Dict[str, Any]:
    """
    Perform quality validation on a single output file.
    
    Args:
        output: Output file information (bucket, key, format)
        metadata: Source video metadata
        
    Returns:
        Dict containing quality validation results
    """
    bucket = output.get('bucket')
    key = output.get('key')
    format_type = output.get('format', 'unknown')
    
    print(f"Validating quality for {format_type}: s3://{bucket}/{key}")
    
    # Initialize quality checks dictionary
    quality_checks = {
        'file_exists': False,
        'file_size_valid': False,
        'format_supported': False,
        'resolution_appropriate': False,
        'duration_consistent': False,
        'no_corruption_detected': False
    }
    
    try:
        # Check if output file exists and get basic info
        try:
            s3_response = s3_client.head_object(Bucket=bucket, Key=key)
            output_file_size = s3_response['ContentLength']
            quality_checks['file_exists'] = True
            print(f"Output file exists, size: {output_file_size} bytes")
            
        except s3_client.exceptions.NoSuchKey:
            print(f"Output file not found: s3://{bucket}/{key}")
            return create_quality_result(output, quality_checks, 0.0, "File not found")
        except Exception as e:
            print(f"Error checking file existence: {str(e)}")
            return create_quality_result(output, quality_checks, 0.0, f"S3 error: {str(e)}")
        
        # Validate file size
        min_file_size = get_minimum_file_size(format_type)
        max_file_size = get_maximum_file_size(format_type, metadata)
        quality_checks['file_size_valid'] = min_file_size <= output_file_size <= max_file_size
        
        print(f"File size validation: {output_file_size} bytes (min: {min_file_size}, max: {max_file_size})")
        
        # Validate format
        quality_checks['format_supported'] = validate_format(format_type, key)
        
        # Validate resolution (based on file size and format)
        quality_checks['resolution_appropriate'] = validate_resolution(output_file_size, format_type, metadata)
        
        # Validate duration consistency (estimated)
        quality_checks['duration_consistent'] = validate_duration_consistency(output_file_size, format_type, metadata)
        
        # Check for potential corruption (basic checks)
        quality_checks['no_corruption_detected'] = check_file_integrity(bucket, key, output_file_size, format_type)
        
        # Calculate quality score
        score = calculate_quality_score(quality_checks, format_type, output_file_size, metadata)
        
        return create_quality_result(output, quality_checks, score, "Quality validation completed", {
            'output_file_size': output_file_size,
            'validation_timestamp': datetime.utcnow().isoformat()
        })
        
    except Exception as e:
        error_msg = f"Quality validation error: {str(e)}"
        print(error_msg)
        return create_quality_result(output, quality_checks, 0.0, error_msg)

def get_minimum_file_size(format_type: str) -> int:
    """Get minimum expected file size for the format."""
    min_sizes = {
        'mp4': 1024 * 1024,      # 1 MB
        'hls': 500 * 1024,       # 500 KB (for short segments)
        'dash': 500 * 1024,      # 500 KB
        'thumbnails': 10 * 1024   # 10 KB
    }
    return min_sizes.get(format_type, 1024)

def get_maximum_file_size(format_type: str, metadata: Dict[str, Any]) -> int:
    """Get maximum expected file size based on source metadata."""
    source_size = metadata.get('file_size_bytes', 1024 * 1024 * 1024)  # Default 1GB
    
    # Maximum sizes as multipliers of source size
    max_multipliers = {
        'mp4': 1.2,      # MP4 should not be much larger than source
        'hls': 1.1,      # HLS might be slightly larger due to segmentation
        'dash': 1.1,     # Similar to HLS
        'thumbnails': 0.01  # Thumbnails should be very small
    }
    
    multiplier = max_multipliers.get(format_type, 2.0)
    return int(source_size * multiplier)

def validate_format(format_type: str, key: str) -> bool:
    """Validate that the output format matches expectations."""
    format_extensions = {
        'mp4': ['.mp4'],
        'hls': ['.m3u8', '.ts'],
        'dash': ['.mpd', '.m4s'],
        'thumbnails': ['.jpg', '.jpeg', '.png']
    }
    
    expected_extensions = format_extensions.get(format_type, [])
    if not expected_extensions:
        return True  # Unknown format, assume valid
    
    file_extension = '.' + key.lower().split('.')[-1] if '.' in key else ''
    return file_extension in expected_extensions

def validate_resolution(file_size: int, format_type: str, metadata: Dict[str, Any]) -> bool:
    """Validate that the output resolution is appropriate."""
    if format_type == 'thumbnails':
        return True  # Thumbnails have different resolution requirements
    
    # Get source resolution from metadata
    source_resolution = metadata.get('resolution', {})
    source_pixels = source_resolution.get('width', 1920) * source_resolution.get('height', 1080)
    
    # Estimate output pixels based on file size and format
    estimated_pixels = estimate_resolution_from_size(file_size, format_type)
    
    # Resolution should be reasonable compared to source
    min_pixels = source_pixels * 0.1   # At least 10% of source
    max_pixels = source_pixels * 1.5   # At most 150% of source
    
    return min_pixels <= estimated_pixels <= max_pixels

def estimate_resolution_from_size(file_size: int, format_type: str) -> int:
    """Estimate pixel count from file size."""
    # Very rough estimation based on typical compression ratios
    bytes_per_pixel = {
        'mp4': 0.5,   # H.264 compression
        'hls': 0.5,   # Similar to MP4
        'dash': 0.5   # Similar to MP4
    }
    
    bpp = bytes_per_pixel.get(format_type, 0.5)
    return int(file_size / bpp) if bpp > 0 else 1920 * 1080

def validate_duration_consistency(file_size: int, format_type: str, metadata: Dict[str, Any]) -> bool:
    """Validate that output duration is consistent with source."""
    if format_type == 'thumbnails':
        return True  # Thumbnails don't have duration
    
    source_duration = metadata.get('estimated_duration_seconds', 60)
    estimated_bitrate = (file_size * 8) / source_duration if source_duration > 0 else 0
    
    # Reasonable bitrate ranges for different formats
    min_bitrate = 100000    # 100 kbps minimum
    max_bitrate = 50000000  # 50 Mbps maximum
    
    return min_bitrate <= estimated_bitrate <= max_bitrate

def check_file_integrity(bucket: str, key: str, file_size: int, format_type: str) -> bool:
    """Perform basic file integrity checks."""
    try:
        # For now, just check if we can read the first and last bytes
        # In production, you might want to download and validate file headers
        
        if file_size < 1024:  # Very small files might be corrupt
            return False
        
        # Try to read first 1KB to check file header
        try:
            response = s3_client.get_object(
                Bucket=bucket,
                Key=key,
                Range='bytes=0-1023'
            )
            first_bytes = response['Body'].read()
            
            # Basic file signature validation
            return validate_file_signature(first_bytes, format_type)
            
        except Exception as e:
            print(f"Error reading file header: {str(e)}")
            return False
    
    except Exception as e:
        print(f"Error in integrity check: {str(e)}")
        return False

def validate_file_signature(data: bytes, format_type: str) -> bool:
    """Validate file signature/magic bytes."""
    if len(data) < 4:
        return False
    
    # Common file signatures
    signatures = {
        'mp4': [b'ftyp', b'\x00\x00\x00\x18ftypmp4', b'\x00\x00\x00 ftypisom'],
        'hls': [b'#EXTM3U'],
        'dash': [b'<?xml', b'<MPD'],
        'thumbnails': [b'\xff\xd8\xff', b'\x89PNG']  # JPEG, PNG
    }
    
    expected_sigs = signatures.get(format_type, [])
    if not expected_sigs:
        return True  # Unknown format, assume valid
    
    return any(data.startswith(sig) or sig in data[:100] for sig in expected_sigs)

def calculate_quality_score(checks: Dict[str, bool], format_type: str, file_size: int, metadata: Dict[str, Any]) -> float:
    """Calculate overall quality score based on validation checks."""
    # Weight different checks based on importance
    check_weights = {
        'file_exists': 0.3,              # Critical
        'file_size_valid': 0.2,          # Important
        'format_supported': 0.15,        # Important
        'resolution_appropriate': 0.15,   # Important
        'duration_consistent': 0.1,      # Moderate
        'no_corruption_detected': 0.1    # Moderate
    }
    
    # Calculate weighted score
    total_score = 0.0
    total_weight = 0.0
    
    for check, passed in checks.items():
        weight = check_weights.get(check, 0.1)
        total_score += weight if passed else 0.0
        total_weight += weight
    
    base_score = total_score / total_weight if total_weight > 0 else 0.0
    
    # Apply format-specific adjustments
    format_bonus = get_format_quality_bonus(format_type, file_size, metadata)
    
    # Final score (capped at 1.0)
    final_score = min(1.0, base_score + format_bonus)
    
    print(f"Quality score calculation: base={base_score:.3f}, bonus={format_bonus:.3f}, final={final_score:.3f}")
    return final_score

def get_format_quality_bonus(format_type: str, file_size: int, metadata: Dict[str, Any]) -> float:
    """Get format-specific quality bonus."""
    # Bonus for appropriate file sizes relative to source
    source_size = metadata.get('file_size_bytes', file_size)
    size_ratio = file_size / source_size if source_size > 0 else 1.0
    
    # Different expectations for different formats
    if format_type == 'mp4':
        # MP4 should be reasonably compressed but not too small
        if 0.3 <= size_ratio <= 0.9:
            return 0.1
    elif format_type == 'hls':
        # HLS might be slightly larger due to segmentation
        if 0.4 <= size_ratio <= 1.0:
            return 0.05
    elif format_type == 'thumbnails':
        # Thumbnails should be very small
        if size_ratio < 0.01:
            return 0.1
    
    return 0.0

def create_quality_result(output: Dict[str, Any], checks: Dict[str, bool], score: float, message: str, extra_data: Dict[str, Any] = None) -> Dict[str, Any]:
    """Create a standardized quality result dictionary."""
    result = {
        'bucket': output.get('bucket'),
        'key': output.get('key'),
        'format': output.get('format'),
        'checks': checks,
        'score': round(score, 3),
        'message': message,
        'timestamp': datetime.utcnow().isoformat()
    }
    
    if extra_data:
        result.update(extra_data)
    
    return result

def calculate_overall_quality(quality_results: List[Dict[str, Any]]) -> float:
    """Calculate overall quality score across all outputs."""
    if not quality_results:
        return 0.0
    
    # Weight different formats
    format_weights = {
        'mp4': 0.4,         # Primary output
        'hls': 0.3,         # Streaming format
        'dash': 0.2,        # Alternative streaming
        'thumbnails': 0.1   # Supporting content
    }
    
    total_score = 0.0
    total_weight = 0.0
    
    for result in quality_results:
        format_type = result.get('format', 'unknown')
        score = result.get('score', 0.0)
        weight = format_weights.get(format_type, 0.1)
        
        total_score += score * weight
        total_weight += weight
    
    return total_score / total_weight if total_weight > 0 else 0.0

def update_quality_results(table: Any, job_id: str, quality_results: List[Dict[str, Any]], overall_score: float, passed: bool) -> None:
    """Update DynamoDB job record with quality control results."""
    try:
        table.update_item(
            Key={'JobId': job_id},
            UpdateExpression='SET QualityResults = :results, QualityScore = :score, QualityPassed = :passed, QCCompletedAt = :timestamp, JobStatus = :status',
            ExpressionAttributeValues={
                ':results': quality_results,
                ':score': overall_score,
                ':passed': passed,
                ':timestamp': datetime.utcnow().isoformat(),
                ':status': 'QUALITY_CONTROL_COMPLETED'
            }
        )
        print(f"Updated job {job_id} with quality results in DynamoDB")
        
    except Exception as e:
        print(f"Error updating DynamoDB: {str(e)}")
        raise

def update_quality_error(table: Any, job_id: str, error_message: str) -> None:
    """Update DynamoDB job record with quality control error."""
    try:
        table.update_item(
            Key={'JobId': job_id},
            UpdateExpression='SET JobStatus = :status, QCErrorMessage = :error, QCErrorTimestamp = :timestamp',
            ExpressionAttributeValues={
                ':status': 'QUALITY_CONTROL_FAILED',
                ':error': error_message,
                ':timestamp': datetime.utcnow().isoformat()
            }
        )
        print(f"Updated job {job_id} with QC error status in DynamoDB")
        
    except Exception as e:
        print(f"Error updating DynamoDB with QC error status: {str(e)}")