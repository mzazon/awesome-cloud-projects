"""
Amazon Textract Document Processing Lambda Function

This function processes documents uploaded to S3 using Amazon Textract for intelligent
text extraction. It supports various document formats and provides comprehensive
analysis results including confidence metrics and structured data extraction.

Author: AWS CDK Generator
Version: 1.0
"""

import json
import boto3
import urllib.parse
import logging
import os
from typing import Dict, Any, List, Optional
from botocore.exceptions import ClientError, BotoCoreError
from datetime import datetime

# Configure logging
logger = logging.getLogger()
log_level = os.environ.get('LOG_LEVEL', 'INFO').upper()
logger.setLevel(getattr(logging, log_level, logging.INFO))

# Initialize AWS clients (reused across invocations)
s3_client = boto3.client('s3')
textract_client = boto3.client('textract')

# Configuration from environment variables
BUCKET_NAME = os.environ.get('BUCKET_NAME', '')
RESULTS_PREFIX = os.environ.get('RESULTS_PREFIX', 'results/')

# Supported file extensions for Textract
SUPPORTED_EXTENSIONS = ['.pdf', '.png', '.jpg', '.jpeg', '.tiff', '.tif']

# Maximum file size for synchronous processing (5MB)
MAX_SYNC_FILE_SIZE = 5 * 1024 * 1024  # 5MB in bytes


def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Process documents uploaded to S3 using Amazon Textract
    
    Args:
        event: S3 event notification containing bucket and object information
        context: Lambda context object with runtime information
        
    Returns:
        Response dictionary with processing status and results location
    """
    try:
        # Validate event structure
        if not event.get('Records'):
            logger.error("No Records found in event")
            return create_error_response(400, "Invalid event structure", "No Records found")
        
        # Process each record (typically one per invocation)
        for record in event['Records']:
            result = process_document_record(record, context)
            if result['statusCode'] != 200:
                return result
        
        return create_success_response("All documents processed successfully")
        
    except Exception as e:
        logger.error(f"Unexpected error in lambda_handler: {str(e)}", exc_info=True)
        return create_error_response(500, "Unexpected processing error", str(e))


def process_document_record(record: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Process a single document record from S3 event
    
    Args:
        record: S3 event record
        context: Lambda context
        
    Returns:
        Processing result dictionary
    """
    try:
        # Extract S3 information from the event record
        s3_info = record.get('s3', {})
        bucket = s3_info.get('bucket', {}).get('name', '')
        key = urllib.parse.unquote_plus(
            s3_info.get('object', {}).get('key', ''), 
            encoding='utf-8'
        )
        
        if not bucket or not key:
            logger.error("Missing bucket or key in S3 event")
            return create_error_response(400, "Invalid S3 event", "Missing bucket or key")
        
        logger.info(f"Processing document: {key} from bucket: {bucket}")
        
        # Validate file type
        if not is_supported_file_type(key):
            logger.warning(f"Unsupported file type: {key}")
            return create_error_response(400, "Unsupported file type", 
                                       f"File {key} is not a supported document type")
        
        # Get object metadata to check file size
        try:
            object_info = s3_client.head_object(Bucket=bucket, Key=key)
            file_size = object_info.get('ContentLength', 0)
            logger.info(f"Document size: {file_size} bytes")
        except ClientError as e:
            logger.error(f"Failed to get object metadata: {e}")
            return create_error_response(500, "Object access error", str(e))
        
        # Process document with Textract
        textract_result = analyze_document_with_textract(bucket, key, file_size)
        if not textract_result:
            return create_error_response(500, "Textract processing failed", 
                                       "Failed to analyze document with Textract")
        
        # Extract and structure the results
        analysis_results = extract_text_and_metadata(textract_result, key, context)
        
        # Save results to S3
        results_location = save_results_to_s3(bucket, key, analysis_results)
        if not results_location:
            logger.warning("Failed to save results to S3, returning in-memory results")
        
        logger.info(f"Document processing completed successfully: {key}")
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Document processed successfully',
                'document': key,
                'results_location': results_location,
                'statistics': analysis_results.get('extraction_results', {}).get('statistics', {}),
                'confidence': analysis_results.get('extraction_results', {}).get('confidence_metrics', {})
            })
        }
        
    except Exception as e:
        logger.error(f"Error processing document record: {str(e)}", exc_info=True)
        return create_error_response(500, "Document processing error", str(e))


def is_supported_file_type(filename: str) -> bool:
    """
    Check if the file type is supported by Textract
    
    Args:
        filename: Name of the file to check
        
    Returns:
        True if file type is supported, False otherwise
    """
    return any(filename.lower().endswith(ext) for ext in SUPPORTED_EXTENSIONS)


def analyze_document_with_textract(bucket: str, key: str, file_size: int) -> Optional[Dict[str, Any]]:
    """
    Analyze document using Amazon Textract
    
    Args:
        bucket: S3 bucket name
        key: S3 object key
        file_size: Size of the file in bytes
        
    Returns:
        Textract analysis response or None if failed
    """
    try:
        # For now, use synchronous text detection
        # In production, consider using asynchronous APIs for large documents
        logger.info(f"Starting Textract analysis for {key}")
        
        response = textract_client.detect_document_text(
            Document={
                'S3Object': {
                    'Bucket': bucket,
                    'Name': key
                }
            }
        )
        
        logger.info(f"Textract analysis completed. Found {len(response.get('Blocks', []))} blocks")
        return response
        
    except ClientError as e:
        error_code = e.response['Error']['Code']
        error_message = e.response['Error']['Message']
        logger.error(f"Textract service error: {error_code} - {error_message}")
        return None
    except Exception as e:
        logger.error(f"Unexpected error calling Textract: {str(e)}")
        return None


def extract_text_and_metadata(textract_response: Dict[str, Any], 
                             document_key: str, 
                             context: Any) -> Dict[str, Any]:
    """
    Extract text and metadata from Textract response
    
    Args:
        textract_response: Response from Textract API
        document_key: S3 object key
        context: Lambda context
        
    Returns:
        Structured analysis results
    """
    extracted_text = ""
    confidence_scores = []
    line_count = 0
    word_count = 0
    pages = set()
    
    for block in textract_response.get('Blocks', []):
        block_type = block.get('BlockType', '')
        
        if block_type == 'LINE':
            text = block.get('Text', '')
            confidence = block.get('Confidence', 0)
            
            extracted_text += text + '\n'
            confidence_scores.append(confidence)
            line_count += 1
            
            # Track page numbers
            if 'Page' in block:
                pages.add(block['Page'])
                
        elif block_type == 'WORD':
            word_count += 1
            if 'Page' in block:
                pages.add(block['Page'])
    
    # Calculate confidence statistics
    if confidence_scores:
        avg_confidence = sum(confidence_scores) / len(confidence_scores)
        min_confidence = min(confidence_scores)
        max_confidence = max(confidence_scores)
    else:
        avg_confidence = min_confidence = max_confidence = 0
    
    # Prepare comprehensive results
    return {
        'document_info': {
            'filename': document_key.split('/')[-1],
            'full_path': document_key,
            'processing_timestamp': datetime.utcnow().isoformat() + 'Z',
            'function_version': context.function_version,
            'request_id': context.aws_request_id,
            'pages_detected': len(pages)
        },
        'extraction_results': {
            'extracted_text': extracted_text.strip(),
            'statistics': {
                'total_blocks': len(textract_response.get('Blocks', [])),
                'line_count': line_count,
                'word_count': word_count,
                'character_count': len(extracted_text.strip()),
                'page_count': len(pages)
            },
            'confidence_metrics': {
                'average_confidence': round(avg_confidence, 2),
                'min_confidence': round(min_confidence, 2),
                'max_confidence': round(max_confidence, 2),
                'total_confidence_scores': len(confidence_scores)
            }
        },
        'processing_status': 'completed',
        'metadata': {
            'textract_job_id': textract_response.get('JobId'),
            'processing_time_ms': context.get_remaining_time_in_millis(),
            'textract_service_version': textract_response.get('DocumentMetadata', {}).get('Pages')
        }
    }


def save_results_to_s3(bucket: str, document_key: str, results: Dict[str, Any]) -> Optional[str]:
    """
    Save analysis results to S3
    
    Args:
        bucket: S3 bucket name
        document_key: Original document key
        results: Analysis results to save
        
    Returns:
        S3 URI of saved results or None if failed
    """
    try:
        # Generate results key
        filename = document_key.split('/')[-1]
        results_key = f"{RESULTS_PREFIX}{filename}_results.json"
        
        # Add metadata for the results object
        metadata = {
            'source-document': document_key,
            'processing-status': results.get('processing_status', 'completed'),
            'confidence-score': str(results.get('extraction_results', {})
                                  .get('confidence_metrics', {})
                                  .get('average_confidence', 0)),
            'content-type': 'application/json'
        }
        
        # Save to S3
        s3_client.put_object(
            Bucket=bucket,
            Key=results_key,
            Body=json.dumps(results, indent=2, ensure_ascii=False),
            ContentType='application/json',
            Metadata=metadata
        )
        
        results_uri = f"s3://{bucket}/{results_key}"
        logger.info(f"Results saved to: {results_uri}")
        return results_uri
        
    except ClientError as e:
        logger.error(f"Failed to save results to S3: {e}")
        return None
    except Exception as e:
        logger.error(f"Unexpected error saving results: {e}")
        return None


def create_success_response(message: str, data: Optional[Dict[str, Any]] = None) -> Dict[str, Any]:
    """
    Create a standardized success response
    
    Args:
        message: Success message
        data: Optional additional data
        
    Returns:
        Formatted success response
    """
    response = {
        'statusCode': 200,
        'body': json.dumps({
            'message': message,
            'timestamp': datetime.utcnow().isoformat() + 'Z'
        })
    }
    
    if data:
        response['body'] = json.dumps({**json.loads(response['body']), **data})
    
    return response


def create_error_response(status_code: int, error: str, message: str, 
                         document: Optional[str] = None) -> Dict[str, Any]:
    """
    Create a standardized error response
    
    Args:
        status_code: HTTP status code
        error: Error type
        message: Error message
        document: Optional document identifier
        
    Returns:
        Formatted error response
    """
    response_body = {
        'error': error,
        'message': message,
        'timestamp': datetime.utcnow().isoformat() + 'Z'
    }
    
    if document:
        response_body['document'] = document
    
    return {
        'statusCode': status_code,
        'body': json.dumps(response_body)
    }