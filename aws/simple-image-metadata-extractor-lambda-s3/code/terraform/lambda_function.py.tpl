#!/usr/bin/env python3
"""
Lambda Function for Simple Image Metadata Extraction
====================================================

This Lambda function automatically extracts metadata from images uploaded to S3.
It processes S3 events, downloads images, and extracts comprehensive metadata
including dimensions, format, file size, and EXIF data using the PIL library.

Project: ${project_name}
Environment: ${environment}
Runtime: Python 3.12
Dependencies: PIL/Pillow (via Lambda Layer)

Architecture:
- Event-driven processing via S3 triggers
- Serverless compute with AWS Lambda
- PIL/Pillow for image processing
- CloudWatch for logging and monitoring
"""

import json
import boto3
import logging
import os
from PIL import Image
from urllib.parse import unquote_plus
import io
from typing import Dict, Any, List
import time

# Initialize AWS clients outside handler for connection reuse
s3_client = boto3.client('s3')

# Configure logging with structured format
logger = logging.getLogger()
logger.setLevel(os.environ.get('LOG_LEVEL', 'INFO'))

# Configure logging format for better CloudWatch parsing
logging.basicConfig(
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    level=logging.INFO
)

def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Main Lambda handler for S3 image upload events.
    
    Processes S3 event records and extracts metadata from uploaded images.
    Implements error handling, performance monitoring, and structured logging.
    
    Args:
        event: S3 event notification containing bucket and object information
        context: Lambda runtime context with request ID and time remaining
        
    Returns:
        Dict containing status code and processing results
        
    Raises:
        Exception: Re-raises exceptions after logging for Lambda error handling
    """
    start_time = time.time()
    processed_images = []
    errors = []
    
    try:
        logger.info(f"Starting image metadata extraction - Request ID: {context.aws_request_id}")
        logger.info(f"Event received with {len(event.get('Records', []))} records")
        
        # Process each S3 event record
        for record_index, record in enumerate(event.get('Records', [])):
            try:
                # Extract S3 bucket and object information
                s3_info = record.get('s3', {})
                bucket_name = s3_info.get('bucket', {}).get('name')
                object_key = unquote_plus(s3_info.get('object', {}).get('key', ''))
                
                if not bucket_name or not object_key:
                    raise ValueError(f"Invalid S3 event data in record {record_index}")
                
                logger.info(f"Processing image {record_index + 1}: {object_key} from bucket: {bucket_name}")
                
                # Validate image format before processing
                if not _is_supported_image_format(object_key):
                    logger.warning(f"Skipping unsupported file format: {object_key}")
                    continue
                
                # Download and process image
                image_metadata = _process_image(bucket_name, object_key, context)
                
                processed_images.append({
                    'bucket': bucket_name,
                    'key': object_key,
                    'metadata': image_metadata,
                    'status': 'success'
                })
                
                logger.info(f"Successfully processed {object_key}")
                
            except Exception as e:
                error_msg = f"Error processing record {record_index}: {str(e)}"
                logger.error(error_msg)
                errors.append({
                    'record_index': record_index,
                    'error': str(e),
                    'bucket': bucket_name if 'bucket_name' in locals() else 'unknown',
                    'key': object_key if 'object_key' in locals() else 'unknown'
                })
        
        # Calculate processing metrics
        processing_time = time.time() - start_time
        success_count = len(processed_images)
        error_count = len(errors)
        
        logger.info(f"Processing completed - Success: {success_count}, Errors: {error_count}, Time: {processing_time:.2f}s")
        
        # Return comprehensive response
        response = {
            'statusCode': 200 if error_count == 0 else 207,  # 207 = Multi-Status
            'body': json.dumps({
                'message': f'Processed {success_count} images successfully',
                'processed_count': success_count,
                'error_count': error_count,
                'processing_time_seconds': round(processing_time, 2),
                'request_id': context.aws_request_id,
                'processed_images': processed_images,
                'errors': errors if errors else None
            }, default=str),
            'headers': {
                'Content-Type': 'application/json'
            }
        }
        
        return response
        
    except Exception as e:
        processing_time = time.time() - start_time
        error_msg = f"Fatal error in Lambda handler: {str(e)}"
        logger.error(error_msg)
        
        # Return error response
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': error_msg,
                'request_id': context.aws_request_id,
                'processing_time_seconds': round(processing_time, 2)
            }),
            'headers': {
                'Content-Type': 'application/json'
            }
        }

def _process_image(bucket_name: str, object_key: str, context: Any) -> Dict[str, Any]:
    """
    Download image from S3 and extract comprehensive metadata.
    
    Args:
        bucket_name: S3 bucket name
        object_key: S3 object key
        context: Lambda context for timeout monitoring
        
    Returns:
        Dict containing extracted image metadata
        
    Raises:
        Exception: If image download or processing fails
    """
    try:
        # Check remaining execution time
        remaining_time = context.get_remaining_time_in_millis()
        if remaining_time < 5000:  # Less than 5 seconds remaining
            raise TimeoutError(f"Insufficient time remaining: {remaining_time}ms")
        
        # Download image from S3 with timeout
        logger.debug(f"Downloading image from S3: s3://{bucket_name}/{object_key}")
        
        try:
            response = s3_client.get_object(Bucket=bucket_name, Key=object_key)
            image_content = response['Body'].read()
            content_length = len(image_content)
            
            logger.debug(f"Downloaded {content_length} bytes from S3")
            
        except Exception as e:
            raise Exception(f"Failed to download image from S3: {str(e)}")
        
        # Validate content size
        max_size = int(os.environ.get('MAX_IMAGE_SIZE_MB', '10')) * 1024 * 1024
        if content_length > max_size:
            raise ValueError(f"Image too large: {content_length} bytes (max: {max_size})")
        
        # Extract metadata using PIL
        metadata = _extract_image_metadata(image_content, object_key)
        
        # Add S3 metadata
        metadata.update({
            'bucket_name': bucket_name,
            'object_key': object_key,
            's3_content_length': content_length,
            's3_last_modified': response.get('LastModified', '').isoformat() if response.get('LastModified') else None,
            's3_content_type': response.get('ContentType'),
            's3_etag': response.get('ETag', '').strip('"'),
            'processing_timestamp': time.time(),
            'processing_datetime': time.strftime('%Y-%m-%d %H:%M:%S UTC', time.gmtime())
        })
        
        return metadata
        
    except Exception as e:
        logger.error(f"Error processing image {object_key}: {str(e)}")
        raise

def _extract_image_metadata(image_content: bytes, filename: str) -> Dict[str, Any]:
    """
    Extract comprehensive metadata from image content using PIL.
    
    Args:
        image_content: Raw image bytes
        filename: Original filename for reference
        
    Returns:
        Dict containing comprehensive image metadata
        
    Raises:
        Exception: If image processing fails
    """
    try:
        # Open image with PIL
        with Image.open(io.BytesIO(image_content)) as img:
            # Basic image information
            metadata = {
                'filename': filename,
                'format': img.format,
                'mode': img.mode,
                'size': img.size,
                'width': img.width,
                'height': img.height,
                'file_size_bytes': len(image_content),
                'file_size_kb': round(len(image_content) / 1024, 2),
                'file_size_mb': round(len(image_content) / (1024 * 1024), 3),
                'aspect_ratio': round(img.width / img.height, 3) if img.height > 0 else 0,
                'total_pixels': img.width * img.height,
                'bits_per_pixel': len(img.getbands()) * 8 if hasattr(img, 'getbands') else None
            }
            
            # Color information
            if hasattr(img, 'getbands'):
                bands = img.getbands()
                metadata.update({
                    'color_bands': bands,
                    'color_band_count': len(bands),
                    'has_transparency': 'A' in bands or 'transparency' in img.info
                })
            
            # Image classification by dimensions
            metadata['image_classification'] = _classify_image_size(img.width, img.height)
            
            # Extract EXIF data if available
            try:
                exif_dict = img.getexif()
                if exif_dict:
                    metadata.update({
                        'has_exif': True,
                        'exif_tags_count': len(exif_dict),
                        'exif_data': _extract_important_exif(exif_dict)
                    })
                else:
                    metadata['has_exif'] = False
            except Exception as e:
                logger.warning(f"EXIF extraction failed: {str(e)}")
                metadata['has_exif'] = False
                metadata['exif_error'] = str(e)
            
            # Additional PIL info
            if hasattr(img, 'info') and img.info:
                metadata['pil_info_keys'] = list(img.info.keys())
                metadata['has_additional_info'] = len(img.info) > 0
            
            # Format-specific information
            if img.format:
                metadata['format_description'] = _get_format_description(img.format)
            
            return metadata
            
    except Exception as e:
        logger.error(f"Error extracting metadata from {filename}: {str(e)}")
        return {
            'filename': filename,
            'error': str(e),
            'file_size_bytes': len(image_content),
            'processing_failed': True
        }

def _extract_important_exif(exif_dict: Dict) -> Dict[str, Any]:
    """
    Extract important EXIF tags with human-readable names.
    
    Args:
        exif_dict: Raw EXIF dictionary from PIL
        
    Returns:
        Dict containing important EXIF data with readable keys
    """
    important_tags = {
        256: 'image_width',
        257: 'image_height',
        258: 'bits_per_sample',
        259: 'compression',
        262: 'photometric_interpretation',
        271: 'make',
        272: 'model',
        274: 'orientation',
        282: 'x_resolution',
        283: 'y_resolution',
        296: 'resolution_unit',
        306: 'datetime',
        315: 'artist',
        33432: 'copyright'
    }
    
    extracted_exif = {}
    for tag_id, tag_name in important_tags.items():
        if tag_id in exif_dict:
            try:
                value = exif_dict[tag_id]
                # Convert bytes to string if needed
                if isinstance(value, bytes):
                    value = value.decode('utf-8', errors='ignore')
                extracted_exif[tag_name] = value
            except Exception as e:
                logger.debug(f"Error extracting EXIF tag {tag_name}: {str(e)}")
    
    return extracted_exif

def _classify_image_size(width: int, height: int) -> str:
    """
    Classify image by dimensions for analysis purposes.
    
    Args:
        width: Image width in pixels
        height: Image height in pixels
        
    Returns:
        String classification of image size
    """
    total_pixels = width * height
    
    if total_pixels >= 8000000:  # 8MP+
        return 'high_resolution'
    elif total_pixels >= 2000000:  # 2MP+
        return 'medium_resolution'
    elif total_pixels >= 500000:   # 0.5MP+
        return 'standard_resolution'
    elif total_pixels >= 100000:   # 0.1MP+
        return 'low_resolution'
    else:
        return 'thumbnail'

def _get_format_description(format_name: str) -> str:
    """
    Get human-readable description for image format.
    
    Args:
        format_name: PIL format name
        
    Returns:
        Human-readable format description
    """
    format_descriptions = {
        'JPEG': 'Joint Photographic Experts Group',
        'PNG': 'Portable Network Graphics',
        'GIF': 'Graphics Interchange Format',
        'BMP': 'Bitmap Image File',
        'TIFF': 'Tagged Image File Format',
        'WEBP': 'WebP Image Format',
        'ICO': 'Icon File Format',
        'PSD': 'Photoshop Document'
    }
    
    return format_descriptions.get(format_name, format_name)

def _is_supported_image_format(filename: str) -> bool:
    """
    Check if file has supported image format extension.
    
    Args:
        filename: File name to check
        
    Returns:
        True if format is supported, False otherwise
    """
    supported_formats = os.environ.get('SUPPORTED_FORMATS', 'jpg,jpeg,png,gif,webp,tiff,bmp').lower().split(',')
    file_extension = filename.lower().split('.')[-1] if '.' in filename else ''
    
    return file_extension in supported_formats

# Performance monitoring decorator for development
def monitor_performance(func):
    """Decorator to monitor function performance."""
    def wrapper(*args, **kwargs):
        start_time = time.time()
        try:
            result = func(*args, **kwargs)
            execution_time = time.time() - start_time
            logger.debug(f"{func.__name__} executed in {execution_time:.3f}s")
            return result
        except Exception as e:
            execution_time = time.time() - start_time
            logger.error(f"{func.__name__} failed after {execution_time:.3f}s: {str(e)}")
            raise
    return wrapper

# Apply performance monitoring in development
if os.environ.get('ENVIRONMENT', '').lower() == 'dev':
    _process_image = monitor_performance(_process_image)
    _extract_image_metadata = monitor_performance(_extract_image_metadata)