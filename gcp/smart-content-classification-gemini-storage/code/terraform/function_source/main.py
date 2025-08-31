"""
AI-powered content classification Cloud Function using Gemini 2.5
This function automatically classifies uploaded content into appropriate categories
"""

import json
import logging
import os
import time
from google.cloud import aiplatform
from google.cloud import storage
from google.cloud import logging as cloud_logging
import vertexai
from vertexai.generative_models import GenerativeModel, Part
import mimetypes
import functions_framework

# Initialize cloud logging
cloud_logging.Client().setup_logging()
logger = logging.getLogger(__name__)

# Initialize Vertex AI
PROJECT_ID = os.environ.get('GCP_PROJECT')
REGION = os.environ.get('FUNCTION_REGION', 'us-central1')
vertexai.init(project=PROJECT_ID, location=REGION)

# Initialize clients
storage_client = storage.Client()

# Configuration from environment variables
GEMINI_MODEL = os.environ.get('GEMINI_MODEL', '${gemini_model}')
MAX_FILE_SIZE_MB = int(os.environ.get('MAX_FILE_SIZE_MB', '${max_file_size_mb}'))

# Initialize Gemini model
model = GenerativeModel(GEMINI_MODEL)

# Classification bucket mapping
CLASSIFICATION_BUCKETS = {
    'contracts': os.environ.get('CONTRACTS_BUCKET'),
    'invoices': os.environ.get('INVOICES_BUCKET'),
    'marketing': os.environ.get('MARKETING_BUCKET'),
    'miscellaneous': os.environ.get('MISC_BUCKET')
}

def classify_content_with_gemini(file_content, file_name, mime_type):
    """
    Classify content using Gemini 2.5 multimodal capabilities.
    
    Args:
        file_content: The content of the file to classify
        file_name: Name of the file
        mime_type: MIME type of the file
        
    Returns:
        tuple: (classification, reasoning)
    """
    
    classification_prompt = """
    Analyze the provided content and classify it into one of these categories:
    
    1. CONTRACTS: Legal agreements, terms of service, NDAs, employment contracts, vendor agreements, licensing agreements, service agreements
    2. INVOICES: Bills, receipts, purchase orders, financial statements, payment requests, expense reports, billing statements
    3. MARKETING: Promotional materials, advertisements, brochures, marketing campaigns, social media content, press releases, newsletters
    4. MISCELLANEOUS: Any content that doesn't fit the above categories
    
    Consider these factors:
    - Document structure and layout patterns
    - Text content, terminology, and language patterns
    - Visual elements and design characteristics
    - Business context and document purpose
    - Legal or financial language indicators
    - Marketing or promotional language indicators
    
    Respond with ONLY the category name (contracts, invoices, marketing, or miscellaneous) on the first line.
    Provide your detailed reasoning on the second line.
    """
    
    try:
        # Handle different content types with multimodal capabilities
        if mime_type.startswith('image/'):
            # Image content analysis
            logger.info(f"Processing image file: {file_name}")
            image_part = Part.from_data(file_content, mime_type)
            response = model.generate_content([classification_prompt, image_part])
            
        elif mime_type.startswith('text/') or 'document' in mime_type or 'pdf' in mime_type:
            # Text content analysis
            logger.info(f"Processing text/document file: {file_name}")
            if isinstance(file_content, bytes):
                try:
                    text_content = file_content.decode('utf-8', errors='ignore')
                except UnicodeDecodeError:
                    text_content = file_content.decode('latin-1', errors='ignore')
            else:
                text_content = str(file_content)
            
            # Limit content length for processing efficiency
            text_sample = text_content[:5000] if len(text_content) > 5000 else text_content
            combined_prompt = f"{classification_prompt}\n\nFile name: {file_name}\nContent to classify:\n{text_sample}"
            response = model.generate_content(combined_prompt)
            
        else:
            # Default handling for other file types based on filename and metadata
            logger.info(f"Processing other file type: {file_name} ({mime_type})")
            combined_prompt = f"{classification_prompt}\n\nFile name: {file_name}\nMIME Type: {mime_type}\nPlease classify based on the filename and file type."
            response = model.generate_content(combined_prompt)
        
        # Extract classification from response
        response_text = response.text.strip()
        lines = response_text.split('\n')
        classification = lines[0].strip().lower()
        reasoning = lines[1] if len(lines) > 1 else "No detailed reasoning provided"
        
        # Validate classification against known categories
        if classification in CLASSIFICATION_BUCKETS:
            logger.info(f"Classification successful: {classification}")
            return classification, reasoning
        else:
            logger.warning(f"Unknown classification returned: {classification}, defaulting to miscellaneous")
            return 'miscellaneous', f"Unknown classification '{classification}', defaulted to miscellaneous. Original reasoning: {reasoning}"
            
    except Exception as e:
        logger.error(f"Error in Gemini classification for {file_name}: {e}")
        return 'miscellaneous', f"Classification error: {str(e)}"

def move_file_to_classified_bucket(source_bucket, source_blob_name, classification):
    """
    Move file to appropriate classification bucket with metadata.
    
    Args:
        source_bucket: Name of the source bucket
        source_blob_name: Name of the source blob
        classification: Determined classification category
        
    Returns:
        bool: True if successful, False otherwise
    """
    
    try:
        target_bucket_name = CLASSIFICATION_BUCKETS[classification]
        if not target_bucket_name:
            logger.error(f"No bucket configured for classification: {classification}")
            return False
        
        # Get source blob
        source_bucket_obj = storage_client.bucket(source_bucket)
        source_blob = source_bucket_obj.blob(source_blob_name)
        
        if not source_blob.exists():
            logger.error(f"Source blob {source_blob_name} does not exist in bucket {source_bucket}")
            return False
        
        # Get target bucket
        target_bucket_obj = storage_client.bucket(target_bucket_name)
        
        # Copy to target bucket with original content and metadata
        target_blob = target_bucket_obj.blob(source_blob_name)
        target_blob.upload_from_string(
            source_blob.download_as_bytes(),
            content_type=source_blob.content_type
        )
        
        # Add classification metadata
        metadata = source_blob.metadata or {}
        metadata.update({
            'classification': classification,
            'classified_by': GEMINI_MODEL,
            'original_bucket': source_bucket,
            'classification_timestamp': str(int(time.time()))
        })
        target_blob.metadata = metadata
        target_blob.patch()
        
        # Delete from source bucket
        source_blob.delete()
        
        logger.info(f"Successfully moved {source_blob_name} from {source_bucket} to {target_bucket_name}")
        return True
        
    except Exception as e:
        logger.error(f"Error moving file {source_blob_name} to {classification}: {e}")
        return False

@functions_framework.cloud_event
def content_classifier(cloud_event):
    """
    Main Cloud Function entry point for content classification.
    Triggered by Cloud Storage object finalization events.
    
    Args:
        cloud_event: CloudEvent containing the storage event data
    """
    
    try:
        # Extract event data
        data = cloud_event.data
        bucket_name = data['bucket']
        blob_name = data['name']
        
        logger.info(f"Processing file: {blob_name} from bucket: {bucket_name}")
        
        # Skip if already in a classification bucket (prevent infinite loops)
        if bucket_name in CLASSIFICATION_BUCKETS.values():
            logger.info(f"File {blob_name} is already in classification bucket {bucket_name}, skipping")
            return
        
        # Skip hidden files and directories
        if blob_name.startswith('.') or blob_name.endswith('/'):
            logger.info(f"Skipping hidden file or directory: {blob_name}")
            return
        
        # Download and analyze file
        bucket = storage_client.bucket(bucket_name)
        blob = bucket.blob(blob_name)
        
        # Check if blob exists
        if not blob.exists():
            logger.warning(f"Blob {blob_name} no longer exists in bucket {bucket_name}")
            return
        
        # Get file metadata
        blob.reload()
        mime_type = blob.content_type or mimetypes.guess_type(blob_name)[0] or 'application/octet-stream'
        file_size_mb = blob.size / (1024 * 1024) if blob.size else 0
        
        logger.info(f"File details - Size: {file_size_mb:.2f}MB, MIME type: {mime_type}")
        
        # Check file size limit
        if file_size_mb > MAX_FILE_SIZE_MB:
            logger.warning(f"File {blob_name} is too large ({file_size_mb:.2f}MB > {MAX_FILE_SIZE_MB}MB), classifying as miscellaneous")
            classification = 'miscellaneous'
            reasoning = f"File too large for content analysis ({file_size_mb:.2f}MB exceeds {MAX_FILE_SIZE_MB}MB limit)"
        else:
            # Download content for analysis
            try:
                file_content = blob.download_as_bytes()
                classification, reasoning = classify_content_with_gemini(file_content, blob_name, mime_type)
            except Exception as e:
                logger.error(f"Error downloading or analyzing file {blob_name}: {e}")
                classification = 'miscellaneous'
                reasoning = f"Error during file analysis: {str(e)}"
        
        logger.info(f"Classification result - Category: {classification}, Reasoning: {reasoning}")
        
        # Move file to appropriate bucket
        success = move_file_to_classified_bucket(bucket_name, blob_name, classification)
        
        if success:
            logger.info(f"✅ Successfully classified and moved {blob_name} to {classification} category")
        else:
            logger.error(f"❌ Failed to move {blob_name} to {classification} category")
            
    except Exception as e:
        logger.error(f"❌ Unexpected error in content classification for {cloud_event.data.get('name', 'unknown')}: {e}")
        # Don't re-raise to prevent function retry loops

if __name__ == "__main__":
    # For local testing and development
    print(f"Content Classifier Cloud Function using {GEMINI_MODEL}")
    print("Classification categories:", list(CLASSIFICATION_BUCKETS.keys()))
    print(f"Max file size: {MAX_FILE_SIZE_MB}MB")