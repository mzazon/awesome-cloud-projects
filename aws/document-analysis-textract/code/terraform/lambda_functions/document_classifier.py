"""
Document Classifier Lambda Function
Analyzes incoming documents and determines processing strategy
"""
import json
import boto3
import os
from urllib.parse import unquote_plus

# Initialize AWS clients
s3 = boto3.client('s3')

def lambda_handler(event, context):
    """
    Lambda handler for document classification
    
    Args:
        event: S3 event notification or direct invocation
        context: Lambda runtime context
        
    Returns:
        dict: Classification results with processing strategy
    """
    try:
        # Parse S3 event or direct input
        if 'Records' in event:
            # S3 event notification
            bucket = event['Records'][0]['s3']['bucket']['name']
            key = unquote_plus(event['Records'][0]['s3']['object']['key'])
        else:
            # Direct invocation
            bucket = event.get('bucket')
            key = event.get('key')
            
        if not bucket or not key:
            raise ValueError("Missing bucket or key in event")
            
        print(f"Processing document: s3://{bucket}/{key}")
        
        # Get object metadata
        response = s3.head_object(Bucket=bucket, Key=key)
        file_size = response['ContentLength']
        content_type = response.get('ContentType', '')
        
        # Determine processing type based on file size and type
        # Files under 5MB for synchronous, larger for asynchronous
        processing_type = 'sync' if file_size < 5 * 1024 * 1024 else 'async'
        
        # Determine document type based on filename and metadata
        doc_type = classify_document_type(key, content_type)
        
        # Validate file type
        if not is_supported_file_type(key, content_type):
            raise ValueError(f"Unsupported file type: {content_type}")
            
        print(f"Classification results: type={doc_type}, processing={processing_type}, size={file_size}")
        
        return {
            'statusCode': 200,
            'body': {
                'bucket': bucket,
                'key': key,
                'processingType': processing_type,
                'documentType': doc_type,
                'fileSize': file_size,
                'contentType': content_type
            }
        }
        
    except Exception as e:
        print(f"Error classifying document: {str(e)}")
        return {
            'statusCode': 500,
            'body': {
                'error': str(e),
                'errorType': type(e).__name__
            }
        }

def classify_document_type(key, content_type):
    """
    Classify document type based on filename and content type
    
    Args:
        key (str): S3 object key (filename)
        content_type (str): MIME content type
        
    Returns:
        str: Document type classification
    """
    key_lower = key.lower()
    
    # Invoice detection
    invoice_keywords = ['invoice', 'bill', 'receipt', 'payment']
    if any(keyword in key_lower for keyword in invoice_keywords):
        return 'invoice'
    
    # Form detection  
    form_keywords = ['form', 'application', 'survey', 'questionnaire']
    if any(keyword in key_lower for keyword in form_keywords):
        return 'form'
        
    # Contract detection
    contract_keywords = ['contract', 'agreement', 'terms', 'legal']
    if any(keyword in key_lower for keyword in contract_keywords):
        return 'contract'
        
    # Report detection
    report_keywords = ['report', 'analysis', 'summary', 'statement']
    if any(keyword in key_lower for keyword in report_keywords):
        return 'report'
        
    # Default classification
    return 'general'

def is_supported_file_type(key, content_type):
    """
    Check if the file type is supported by Amazon Textract
    
    Args:
        key (str): S3 object key (filename)
        content_type (str): MIME content type
        
    Returns:
        bool: True if file type is supported
    """
    # Supported file extensions
    supported_extensions = ['.pdf', '.png', '.jpg', '.jpeg', '.tiff', '.tif']
    
    # Check file extension
    key_lower = key.lower()
    if any(key_lower.endswith(ext) for ext in supported_extensions):
        return True
        
    # Check MIME type
    supported_mime_types = [
        'application/pdf',
        'image/png', 
        'image/jpeg',
        'image/tiff'
    ]
    
    return content_type in supported_mime_types