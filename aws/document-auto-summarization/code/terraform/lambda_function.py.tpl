import json
import boto3
import os
import logging
from urllib.parse import unquote_plus
from datetime import datetime
import traceback

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize AWS clients
s3_client = boto3.client('s3')
textract_client = boto3.client('textract')
bedrock_client = boto3.client('bedrock-runtime')
${enable_sns ? "sns_client = boto3.client('sns')" : "# SNS client not enabled"}

# Environment variables
OUTPUT_BUCKET = os.environ['OUTPUT_BUCKET']
BEDROCK_MODEL_ID = os.environ.get('BEDROCK_MODEL_ID', '${bedrock_model_id}')
BEDROCK_MAX_TOKENS = int(os.environ.get('BEDROCK_MAX_TOKENS', '${max_tokens}'))
MAX_DOCUMENT_SIZE_MB = int(os.environ.get('MAX_DOCUMENT_SIZE_MB', '${max_doc_size_mb}'))
DOCUMENT_PREFIX = os.environ.get('DOCUMENT_PREFIX', 'documents/')
${enable_sns ? "SNS_TOPIC_ARN = os.environ.get('SNS_TOPIC_ARN')" : "# SNS topic ARN not configured"}

# Supported file extensions
SUPPORTED_EXTENSIONS = ['.pdf', '.txt', '.docx', '.png', '.jpg', '.jpeg', '.tiff', '.bmp']

def lambda_handler(event, context):
    """
    Main Lambda handler for document summarization.
    Processes S3 events, extracts text, and generates summaries using Bedrock.
    """
    try:
        logger.info(f"Processing event: {json.dumps(event, default=str)}")
        
        # Process each record in the event
        for record in event.get('Records', []):
            if record.get('eventSource') == 'aws:s3':
                process_s3_event(record)
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Documents processed successfully',
                'timestamp': datetime.utcnow().isoformat()
            })
        }
        
    except Exception as e:
        logger.error(f"Error in lambda_handler: {str(e)}")
        logger.error(f"Traceback: {traceback.format_exc()}")
        
        # Send error notification if SNS is enabled
        ${enable_sns ? "send_error_notification(str(e))" : "# Error notification not enabled"}
        
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': str(e),
                'timestamp': datetime.utcnow().isoformat()
            })
        }

def process_s3_event(record):
    """Process a single S3 event record."""
    try:
        # Extract S3 information
        bucket_name = record['s3']['bucket']['name']
        object_key = unquote_plus(record['s3']['object']['key'])
        
        logger.info(f"Processing document: {object_key} from bucket: {bucket_name}")
        
        # Validate file extension
        if not is_supported_file(object_key):
            logger.warning(f"Unsupported file type: {object_key}")
            return
        
        # Check file size
        if not is_valid_size(bucket_name, object_key):
            logger.warning(f"File too large: {object_key}")
            return
        
        # Extract text from document
        text_content = extract_text_from_document(bucket_name, object_key)
        
        if not text_content or len(text_content.strip()) < 50:
            logger.warning(f"Insufficient text content extracted from: {object_key}")
            return
        
        # Generate summary using Bedrock
        summary = generate_summary_with_bedrock(text_content)
        
        # Store summary and metadata
        store_summary_and_metadata(object_key, summary, text_content)
        
        # Send success notification if SNS is enabled
        ${enable_sns ? "send_success_notification(object_key, len(summary))" : "# Success notification not enabled"}
        
        logger.info(f"Successfully processed document: {object_key}")
        
    except Exception as e:
        logger.error(f"Error processing S3 event: {str(e)}")
        logger.error(f"Record: {json.dumps(record, default=str)}")
        raise

def is_supported_file(object_key):
    """Check if the file extension is supported."""
    file_extension = os.path.splitext(object_key.lower())[1]
    return file_extension in SUPPORTED_EXTENSIONS

def is_valid_size(bucket_name, object_key):
    """Check if the file size is within limits."""
    try:
        response = s3_client.head_object(Bucket=bucket_name, Key=object_key)
        file_size_mb = response['ContentLength'] / (1024 * 1024)
        return file_size_mb <= MAX_DOCUMENT_SIZE_MB
    except Exception as e:
        logger.error(f"Error checking file size: {str(e)}")
        return False

def extract_text_from_document(bucket_name, object_key):
    """Extract text from document using Amazon Textract."""
    try:
        logger.info(f"Extracting text from: {object_key}")
        
        # Handle text files directly
        if object_key.lower().endswith('.txt'):
            response = s3_client.get_object(Bucket=bucket_name, Key=object_key)
            return response['Body'].read().decode('utf-8')
        
        # Use Textract for other document types
        response = textract_client.detect_document_text(
            Document={
                'S3Object': {
                    'Bucket': bucket_name,
                    'Name': object_key
                }
            }
        )
        
        # Extract text blocks
        text_blocks = []
        for block in response.get('Blocks', []):
            if block.get('BlockType') == 'LINE':
                text_blocks.append(block.get('Text', ''))
        
        extracted_text = '\n'.join(text_blocks)
        logger.info(f"Extracted {len(extracted_text)} characters from {object_key}")
        
        return extracted_text
        
    except Exception as e:
        logger.error(f"Error extracting text from {object_key}: {str(e)}")
        raise

def generate_summary_with_bedrock(text_content):
    """Generate summary using Amazon Bedrock Claude model."""
    try:
        logger.info("Generating summary with Bedrock")
        
        # Truncate text if too long (Claude has token limits)
        max_input_length = 50000  # Conservative limit for input text
        if len(text_content) > max_input_length:
            text_content = text_content[:max_input_length] + "..."
            logger.info(f"Text truncated to {max_input_length} characters")
        
        # Create prompt for summarization
        prompt = f"""Please provide a comprehensive summary of the following document. Your summary should include:

1. **Main Topics**: Key themes and subjects covered
2. **Important Facts**: Critical data points, figures, and statistics
3. **Key Conclusions**: Main findings and outcomes
4. **Actionable Insights**: Recommendations or next steps mentioned
5. **Important Dates**: Any deadlines, milestones, or significant dates

Please structure your summary clearly and make it concise but comprehensive.

Document content:
{text_content}

Summary:"""
        
        # Invoke Bedrock model
        request_body = {
            "anthropic_version": "bedrock-2023-05-31",
            "max_tokens": BEDROCK_MAX_TOKENS,
            "messages": [
                {
                    "role": "user",
                    "content": prompt
                }
            ],
            "temperature": 0.1,
            "top_p": 0.9
        }
        
        response = bedrock_client.invoke_model(
            modelId=BEDROCK_MODEL_ID,
            body=json.dumps(request_body)
        )
        
        response_body = json.loads(response['body'].read())
        summary = response_body['content'][0]['text']
        
        logger.info(f"Generated summary of {len(summary)} characters")
        return summary
        
    except Exception as e:
        logger.error(f"Error generating summary with Bedrock: {str(e)}")
        raise

def store_summary_and_metadata(original_key, summary, full_text):
    """Store summary and metadata in S3."""
    try:
        logger.info(f"Storing summary for: {original_key}")
        
        # Create summary file key
        summary_key = f"summaries/{original_key}.summary.txt"
        
        # Create metadata
        metadata = {
            'original-document': original_key,
            'processing-timestamp': datetime.utcnow().isoformat(),
            'summary-generated': 'true',
            'original-text-length': str(len(full_text)),
            'summary-length': str(len(summary)),
            'bedrock-model': BEDROCK_MODEL_ID,
            'processor-version': '1.0'
        }
        
        # Store summary
        s3_client.put_object(
            Bucket=OUTPUT_BUCKET,
            Key=summary_key,
            Body=summary,
            ContentType='text/plain',
            Metadata=metadata
        )
        
        # Store detailed metadata as JSON
        metadata_key = f"metadata/{original_key}.metadata.json"
        detailed_metadata = {
            'document': {
                'original_key': original_key,
                'processing_timestamp': datetime.utcnow().isoformat(),
                'text_length': len(full_text),
                'summary_length': len(summary)
            },
            'processing': {
                'bedrock_model': BEDROCK_MODEL_ID,
                'max_tokens': BEDROCK_MAX_TOKENS,
                'processor_version': '1.0'
            },
            'storage': {
                'summary_key': summary_key,
                'metadata_key': metadata_key
            }
        }
        
        s3_client.put_object(
            Bucket=OUTPUT_BUCKET,
            Key=metadata_key,
            Body=json.dumps(detailed_metadata, indent=2),
            ContentType='application/json'
        )
        
        logger.info(f"Successfully stored summary and metadata for: {original_key}")
        
    except Exception as e:
        logger.error(f"Error storing summary for {original_key}: {str(e)}")
        raise

%{ if enable_sns }
def send_success_notification(document_key, summary_length):
    """Send success notification via SNS."""
    try:
        if not SNS_TOPIC_ARN:
            return
            
        message = {
            'event': 'document_processed',
            'status': 'success',
            'document': document_key,
            'summary_length': summary_length,
            'timestamp': datetime.utcnow().isoformat(),
            'output_bucket': OUTPUT_BUCKET
        }
        
        sns_client.publish(
            TopicArn=SNS_TOPIC_ARN,
            Subject=f'Document Summarization Complete: {os.path.basename(document_key)}',
            Message=json.dumps(message, indent=2)
        )
        
        logger.info(f"Success notification sent for: {document_key}")
        
    except Exception as e:
        logger.error(f"Error sending success notification: {str(e)}")

def send_error_notification(error_message):
    """Send error notification via SNS."""
    try:
        if not SNS_TOPIC_ARN:
            return
            
        message = {
            'event': 'document_processing_error',
            'status': 'error',
            'error': error_message,
            'timestamp': datetime.utcnow().isoformat(),
            'function_name': context.function_name if 'context' in globals() else 'unknown'
        }
        
        sns_client.publish(
            TopicArn=SNS_TOPIC_ARN,
            Subject='Document Summarization Error',
            Message=json.dumps(message, indent=2)
        )
        
        logger.info("Error notification sent")
        
    except Exception as e:
        logger.error(f"Error sending error notification: {str(e)}")
%{ endif }

# Health check function for testing
def health_check():
    """Basic health check for the Lambda function."""
    try:
        # Test AWS service connectivity
        s3_client.list_buckets()
        textract_client.describe_document_text_detection(JobId='test')  # This will fail but confirms connectivity
    except s3_client.exceptions.NoSuchBucket:
        pass  # Expected for health check
    except textract_client.exceptions.InvalidJobIdException:
        pass  # Expected for health check
    except Exception as e:
        if 'InvalidJobIdException' not in str(e):
            logger.error(f"Health check failed: {str(e)}")
            raise
    
    return {
        'status': 'healthy',
        'timestamp': datetime.utcnow().isoformat(),
        'configuration': {
            'output_bucket': OUTPUT_BUCKET,
            'bedrock_model': BEDROCK_MODEL_ID,
            'max_tokens': BEDROCK_MAX_TOKENS,
            'max_document_size_mb': MAX_DOCUMENT_SIZE_MB
        }
    }