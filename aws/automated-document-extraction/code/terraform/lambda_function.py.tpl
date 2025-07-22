import json
import boto3
import urllib.parse
import os
import logging
from datetime import datetime
from typing import Dict, List, Any, Optional

# Configure logging
log_level = os.environ.get('LOG_LEVEL', 'INFO')
logging.basicConfig(level=getattr(logging, log_level))
logger = logging.getLogger(__name__)

# Initialize AWS clients
s3_client = boto3.client('s3')
textract_client = boto3.client('textract')

# Configuration from environment variables
BUCKET_NAME = os.environ.get('BUCKET_NAME', '${bucket_name}')
DOCUMENTS_PREFIX = os.environ.get('DOCUMENTS_PREFIX', '${documents_prefix}')
RESULTS_PREFIX = os.environ.get('RESULTS_PREFIX', '${results_prefix}')
SUPPORTED_FORMATS = os.environ.get('SUPPORTED_FORMATS', 'pdf,png,jpg,jpeg,tiff,txt').split(',')
TEXTRACT_API_VERSION = os.environ.get('TEXTRACT_API_VERSION', '2018-06-27')

def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Process documents uploaded to S3 using Amazon Textract
    
    Args:
        event: S3 event notification containing bucket and object information
        context: Lambda context object with runtime information
        
    Returns:
        Dictionary containing processing status and results location
    """
    
    # Log the incoming event for debugging
    logger.info(f"Processing event: {json.dumps(event, indent=2)}")
    
    try:
        # Extract S3 bucket and object information from the event
        records = event.get('Records', [])
        if not records:
            logger.error("No records found in event")
            return create_error_response("No S3 records found in event", 400)
            
        # Process each record (typically one for S3 events)
        for record in records:
            s3_info = record.get('s3', {})
            bucket = s3_info.get('bucket', {}).get('name')
            key = urllib.parse.unquote_plus(
                s3_info.get('object', {}).get('key', ''), 
                encoding='utf-8'
            )
            
            if not bucket or not key:
                logger.error(f"Invalid S3 information: bucket={bucket}, key={key}")
                continue
                
            logger.info(f"Processing document: {key} from bucket: {bucket}")
            
            # Validate document format
            if not is_supported_format(key):
                logger.warning(f"Unsupported file format for document: {key}")
                continue
                
            # Process the document
            result = process_document(bucket, key, context)
            
            if result['status'] == 'success':
                logger.info(f"Successfully processed document: {key}")
            else:
                logger.error(f"Failed to process document: {key}, Error: {result.get('error')}")
                
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Document processing completed',
                'processed_records': len(records)
            })
        }
        
    except Exception as e:
        logger.error(f"Unexpected error processing event: {str(e)}", exc_info=True)
        return create_error_response(f"Unexpected error: {str(e)}", 500)

def process_document(bucket: str, key: str, context: Any) -> Dict[str, Any]:
    """
    Process a single document using Amazon Textract
    
    Args:
        bucket: S3 bucket name
        key: S3 object key
        context: Lambda context object
        
    Returns:
        Dictionary containing processing results and metadata
    """
    
    try:
        # Get document metadata from S3
        s3_response = s3_client.head_object(Bucket=bucket, Key=key)
        file_size = s3_response.get('ContentLength', 0)
        content_type = s3_response.get('ContentType', '')
        last_modified = s3_response.get('LastModified')
        
        logger.info(f"Document metadata - Size: {file_size} bytes, Type: {content_type}")
        
        # Choose appropriate Textract API based on document characteristics
        textract_response = call_textract_api(bucket, key, file_size)
        
        # Extract and process results
        extracted_data = extract_text_and_metadata(textract_response)
        
        # Prepare comprehensive results
        results = {
            'document_info': {
                'bucket': bucket,
                'key': key,
                'file_size_bytes': file_size,
                'content_type': content_type,
                'last_modified': last_modified.isoformat() if last_modified else None
            },
            'processing_info': {
                'processed_at': datetime.utcnow().isoformat(),
                'lambda_request_id': context.aws_request_id,
                'textract_api_version': TEXTRACT_API_VERSION,
                'processing_status': 'completed'
            },
            'extracted_content': extracted_data,
            'statistics': {
                'total_blocks': len(textract_response.get('Blocks', [])),
                'confidence_scores': extracted_data.get('confidence_scores', []),
                'average_confidence': extracted_data.get('average_confidence', 0),
                'text_length': len(extracted_data.get('extracted_text', ''))
            }
        }
        
        # Save results to S3
        results_key = generate_results_key(key)
        save_results_to_s3(bucket, results_key, results)
        
        logger.info(f"Results saved to: s3://{bucket}/{results_key}")
        logger.info(f"Average confidence: {extracted_data.get('average_confidence', 0):.2f}%")
        
        return {
            'status': 'success',
            'results_location': f"s3://{bucket}/{results_key}",
            'confidence': extracted_data.get('average_confidence', 0),
            'text_length': len(extracted_data.get('extracted_text', ''))
        }
        
    except Exception as e:
        logger.error(f"Error processing document {key}: {str(e)}", exc_info=True)
        
        # Save error information for debugging
        error_results = {
            'document_info': {
                'bucket': bucket,
                'key': key
            },
            'processing_info': {
                'processed_at': datetime.utcnow().isoformat(),
                'lambda_request_id': context.aws_request_id,
                'processing_status': 'failed',
                'error_message': str(e)
            }
        }
        
        error_key = generate_error_key(key)
        try:
            save_results_to_s3(bucket, error_key, error_results)
            logger.info(f"Error details saved to: s3://{bucket}/{error_key}")
        except Exception as save_error:
            logger.error(f"Failed to save error details: {str(save_error)}")
            
        return {
            'status': 'error',
            'error': str(e),
            'document': key
        }

def call_textract_api(bucket: str, key: str, file_size: int) -> Dict[str, Any]:
    """
    Call appropriate Textract API based on document characteristics
    
    Args:
        bucket: S3 bucket name
        key: S3 object key  
        file_size: File size in bytes
        
    Returns:
        Textract API response
    """
    
    document_spec = {
        'S3Object': {
            'Bucket': bucket,
            'Name': key
        }
    }
    
    # For larger documents or complex layouts, use AnalyzeDocument
    # For simple text extraction, use DetectDocumentText (more cost-effective)
    if file_size > 1024 * 1024 or key.lower().endswith(('.pdf', '.tiff')):  # > 1MB or complex formats
        logger.info("Using AnalyzeDocument API for complex document")
        response = textract_client.analyze_document(
            Document=document_spec,
            FeatureTypes=['TABLES', 'FORMS']  # Extract tables and forms for comprehensive analysis
        )
    else:
        logger.info("Using DetectDocumentText API for simple text extraction")
        response = textract_client.detect_document_text(
            Document=document_spec
        )
    
    return response

def extract_text_and_metadata(textract_response: Dict[str, Any]) -> Dict[str, Any]:
    """
    Extract text and metadata from Textract response
    
    Args:
        textract_response: Response from Textract API
        
    Returns:
        Dictionary containing extracted text and metadata
    """
    
    extracted_text = ""
    confidence_scores = []
    blocks_by_type = {}
    
    # Process all blocks in the Textract response
    for block in textract_response.get('Blocks', []):
        block_type = block.get('BlockType', '')
        
        # Count blocks by type for statistics
        blocks_by_type[block_type] = blocks_by_type.get(block_type, 0) + 1
        
        # Extract text from LINE blocks for readable output
        if block_type == 'LINE':
            text = block.get('Text', '')
            confidence = block.get('Confidence', 0)
            
            extracted_text += text + '\n'
            confidence_scores.append(confidence)
            
        # Extract additional data from TABLE and FORM blocks if present
        elif block_type in ['CELL', 'KEY_VALUE_SET']:
            if 'Text' in block:
                # Additional structured data could be processed here
                pass
    
    # Calculate statistics
    average_confidence = sum(confidence_scores) / len(confidence_scores) if confidence_scores else 0
    
    return {
        'extracted_text': extracted_text.strip(),
        'confidence_scores': confidence_scores,
        'average_confidence': round(average_confidence, 2),
        'blocks_by_type': blocks_by_type,
        'total_lines': len([b for b in textract_response.get('Blocks', []) if b.get('BlockType') == 'LINE'])
    }

def is_supported_format(file_key: str) -> bool:
    """
    Check if the file format is supported for processing
    
    Args:
        file_key: S3 object key
        
    Returns:
        True if format is supported, False otherwise
    """
    
    file_extension = file_key.lower().split('.')[-1] if '.' in file_key else ''
    is_supported = file_extension in [fmt.lower() for fmt in SUPPORTED_FORMATS]
    
    if not is_supported:
        logger.warning(f"Unsupported file format: {file_extension}")
        
    return is_supported

def generate_results_key(original_key: str) -> str:
    """
    Generate S3 key for storing processing results
    
    Args:
        original_key: Original document S3 key
        
    Returns:
        S3 key for results file
    """
    
    filename = original_key.split('/')[-1]
    timestamp = datetime.utcnow().strftime('%Y%m%d_%H%M%S')
    return f"{RESULTS_PREFIX}/{filename}_{timestamp}_results.json"

def generate_error_key(original_key: str) -> str:
    """
    Generate S3 key for storing error information
    
    Args:
        original_key: Original document S3 key
        
    Returns:
        S3 key for error file
    """
    
    filename = original_key.split('/')[-1]
    timestamp = datetime.utcnow().strftime('%Y%m%d_%H%M%S')
    return f"{RESULTS_PREFIX}/errors/{filename}_{timestamp}_error.json"

def save_results_to_s3(bucket: str, key: str, results: Dict[str, Any]) -> None:
    """
    Save processing results to S3
    
    Args:
        bucket: S3 bucket name
        key: S3 key for results file
        results: Results dictionary to save
    """
    
    try:
        s3_client.put_object(
            Bucket=bucket,
            Key=key,
            Body=json.dumps(results, indent=2, default=str),
            ContentType='application/json',
            Metadata={
                'ProcessedBy': 'TextractLambdaProcessor',
                'ProcessedAt': datetime.utcnow().isoformat()
            }
        )
        logger.info(f"Successfully saved results to s3://{bucket}/{key}")
        
    except Exception as e:
        logger.error(f"Failed to save results to S3: {str(e)}")
        raise

def create_error_response(message: str, status_code: int) -> Dict[str, Any]:
    """
    Create standardized error response
    
    Args:
        message: Error message
        status_code: HTTP status code
        
    Returns:
        Error response dictionary
    """
    
    return {
        'statusCode': status_code,
        'body': json.dumps({
            'error': message,
            'timestamp': datetime.utcnow().isoformat()
        })
    }