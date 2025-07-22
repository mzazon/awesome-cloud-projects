"""
Cloud Function for Multi-Language Content Translation
This function processes translation requests using Cloud Translation API
and manages the automated content localization pipeline.
"""

import json
import base64
import logging
import os
import tempfile
from typing import List, Dict, Any
from google.cloud import translate_v3
from google.cloud import storage
from google.cloud import monitoring_v3
import functions_framework

# Configure logging
logging.basicConfig(level=getattr(logging, os.getenv('LOG_LEVEL', 'INFO')))
logger = logging.getLogger(__name__)

# Initialize clients
translate_client = translate_v3.TranslationServiceClient()
storage_client = storage.Client()
monitoring_client = monitoring_v3.MetricServiceClient()

# Configuration from environment variables
PROJECT_ID = os.environ.get('GCP_PROJECT', os.environ.get('PROJECT_ID'))
SOURCE_BUCKET = os.environ.get('SOURCE_BUCKET')
TARGET_BUCKET = os.environ.get('TARGET_BUCKET')
TARGET_LANGUAGES = json.loads(os.environ.get('TARGET_LANGUAGES', '${target_languages}'))
LOCATION = 'global'  # Translation API location

# Supported file types and their MIME types
SUPPORTED_FILE_TYPES = {
    '.txt': 'text/plain',
    '.md': 'text/markdown',
    '.html': 'text/html',
    '.json': 'application/json',
    '.csv': 'text/csv'
}

@functions_framework.cloud_event
def translate_document(cloud_event):
    """
    Cloud Function triggered by Pub/Sub to translate documents.
    
    Args:
        cloud_event: CloudEvent containing the Pub/Sub message
    """
    try:
        # Parse the Pub/Sub message
        message_data = base64.b64decode(cloud_event.data['message']['data']).decode('utf-8')
        message = json.loads(message_data)
        
        logger.info(f"Processing message: {message}")
        
        # Handle different message types
        message_type = message.get('type', 'file_upload')
        
        if message_type == 'file_upload':
            # Handle file upload from Cloud Storage notification
            bucket_id = message.get('bucketId')
            object_id = message.get('objectId')
            
            if bucket_id and object_id:
                process_file_translation(bucket_id, object_id)
            else:
                logger.error(f"Missing bucket or object information in message: {message}")
                
        elif message_type == 'batch':
            # Handle batch processing
            action = message.get('action')
            if action == 'process_pending':
                process_batch_translation(message)
            else:
                logger.warning(f"Unknown batch action: {action}")
                
        elif message_type == 'monitor':
            # Handle health monitoring
            action = message.get('action')
            if action == 'health_check':
                perform_health_check()
            else:
                logger.warning(f"Unknown monitor action: {action}")
        else:
            logger.warning(f"Unknown message type: {message_type}")
            
    except Exception as e:
        logger.error(f"Error processing message: {str(e)}")
        # Send error metric
        send_error_metric('translation_processing_error', str(e))
        raise


def process_file_translation(bucket_name: str, file_name: str):
    """
    Process translation for a single uploaded file.
    
    Args:
        bucket_name: Name of the source bucket
        file_name: Name of the file to translate
    """
    try:
        logger.info(f"Processing file: {file_name} from bucket: {bucket_name}")
        
        # Check if file type is supported
        file_extension = get_file_extension(file_name)
        if file_extension not in SUPPORTED_FILE_TYPES:
            logger.warning(f"Unsupported file type: {file_extension} for file: {file_name}")
            return
            
        # Download source file
        bucket = storage_client.bucket(bucket_name)
        blob = bucket.blob(file_name)
        
        if not blob.exists():
            logger.error(f"File not found: {file_name} in bucket: {bucket_name}")
            return
            
        # Read file content
        content = download_file_content(blob, file_extension)
        if not content:
            logger.warning(f"Empty content or unsupported format for file: {file_name}")
            return
            
        # Detect source language
        source_language = detect_language(content)
        logger.info(f"Detected language: {source_language} for file: {file_name}")
        
        # Translate to each target language
        successful_translations = 0
        for target_lang in TARGET_LANGUAGES:
            if target_lang != source_language:
                try:
                    translated_content = translate_text(content, source_language, target_lang)
                    if translated_content:
                        save_translated_content(file_name, target_lang, translated_content)
                        successful_translations += 1
                        logger.info(f"Successfully translated {file_name} to {target_lang}")
                except Exception as e:
                    logger.error(f"Error translating {file_name} to {target_lang}: {str(e)}")
                    send_error_metric('translation_language_error', f"{target_lang}: {str(e)}")
            else:
                logger.info(f"Skipping translation to source language: {target_lang}")
                
        # Send success metric
        send_success_metric('files_translated', successful_translations)
        logger.info(f"Completed translation of {file_name}. Success count: {successful_translations}")
        
    except Exception as e:
        logger.error(f"Error processing file {file_name}: {str(e)}")
        send_error_metric('file_processing_error', str(e))
        raise


def process_batch_translation(message: Dict[str, Any]):
    """
    Process batch translation for multiple files.
    
    Args:
        message: Batch processing message with configuration
    """
    try:
        logger.info("Starting batch translation processing")
        
        source_bucket_name = message.get('source_bucket', SOURCE_BUCKET)
        target_bucket_name = message.get('target_bucket', TARGET_BUCKET)
        target_languages = message.get('target_languages', TARGET_LANGUAGES)
        
        # List all files in source bucket
        source_bucket = storage_client.bucket(source_bucket_name)
        blobs = source_bucket.list_blobs()
        
        processed_count = 0
        error_count = 0
        
        for blob in blobs:
            try:
                # Skip directories and non-supported files
                if blob.name.endswith('/'):
                    continue
                    
                file_extension = get_file_extension(blob.name)
                if file_extension not in SUPPORTED_FILE_TYPES:
                    continue
                    
                # Check if already translated (basic check)
                if not needs_translation(blob.name, target_languages):
                    logger.info(f"File {blob.name} already translated, skipping")
                    continue
                    
                # Process the file
                process_file_translation(source_bucket_name, blob.name)
                processed_count += 1
                
                # Rate limiting to avoid quota issues
                if processed_count % 10 == 0:
                    logger.info(f"Batch processing: {processed_count} files processed")
                    
            except Exception as e:
                logger.error(f"Error in batch processing file {blob.name}: {str(e)}")
                error_count += 1
                
        logger.info(f"Batch processing completed. Processed: {processed_count}, Errors: {error_count}")
        send_success_metric('batch_files_processed', processed_count)
        
        if error_count > 0:
            send_error_metric('batch_processing_errors', str(error_count))
            
    except Exception as e:
        logger.error(f"Error in batch processing: {str(e)}")
        send_error_metric('batch_processing_error', str(e))
        raise


def perform_health_check():
    """
    Perform health check of the translation pipeline.
    """
    try:
        logger.info("Performing health check")
        
        health_status = {
            'translation_api': False,
            'source_bucket': False,
            'target_bucket': False,
            'timestamp': 'unknown'
        }
        
        # Check Translation API
        try:
            parent = f"projects/{PROJECT_ID}/locations/{LOCATION}"
            translate_client.get_supported_languages(parent=parent)
            health_status['translation_api'] = True
        except Exception as e:
            logger.error(f"Translation API health check failed: {str(e)}")
            
        # Check source bucket
        try:
            source_bucket = storage_client.bucket(SOURCE_BUCKET)
            source_bucket.reload()
            health_status['source_bucket'] = True
        except Exception as e:
            logger.error(f"Source bucket health check failed: {str(e)}")
            
        # Check target bucket
        try:
            target_bucket = storage_client.bucket(TARGET_BUCKET)
            target_bucket.reload()
            health_status['target_bucket'] = True
        except Exception as e:
            logger.error(f"Target bucket health check failed: {str(e)}")
            
        # Overall health status
        overall_health = all(health_status.values())
        
        logger.info(f"Health check completed. Status: {health_status}")
        
        # Send health metric
        send_health_metric(overall_health)
        
        return health_status
        
    except Exception as e:
        logger.error(f"Error during health check: {str(e)}")
        send_error_metric('health_check_error', str(e))
        raise


def download_file_content(blob: storage.Blob, file_extension: str) -> str:
    """
    Download and decode file content based on file type.
    
    Args:
        blob: Cloud Storage blob object
        file_extension: File extension to determine processing method
        
    Returns:
        File content as string
    """
    try:
        if file_extension in ['.txt', '.md', '.html', '.csv']:
            return blob.download_as_text(encoding='utf-8')
        elif file_extension == '.json':
            content = blob.download_as_text(encoding='utf-8')
            # Validate JSON and return formatted
            json_data = json.loads(content)
            return json.dumps(json_data, ensure_ascii=False, indent=2)
        else:
            logger.warning(f"Unsupported file extension: {file_extension}")
            return ""
    except Exception as e:
        logger.error(f"Error downloading file content: {str(e)}")
        return ""


def detect_language(content: str) -> str:
    """
    Detect the language of the input content.
    
    Args:
        content: Text content to analyze
        
    Returns:
        Detected language code
    """
    try:
        parent = f"projects/{PROJECT_ID}/locations/{LOCATION}"
        response = translate_client.detect_language(
            parent=parent,
            content=content,
            mime_type="text/plain"
        )
        
        if response.languages:
            detected_language = response.languages[0].language_code
            confidence = response.languages[0].confidence
            logger.info(f"Detected language: {detected_language} (confidence: {confidence})")
            return detected_language
        else:
            logger.warning("No language detected, defaulting to 'en'")
            return 'en'
            
    except Exception as e:
        logger.error(f"Error detecting language: {str(e)}")
        return 'en'  # Default to English


def translate_text(content: str, source_language: str, target_language: str) -> str:
    """
    Translate text content to target language.
    
    Args:
        content: Source text to translate
        source_language: Source language code
        target_language: Target language code
        
    Returns:
        Translated text
    """
    try:
        parent = f"projects/{PROJECT_ID}/locations/{LOCATION}"
        
        response = translate_client.translate_text(
            parent=parent,
            contents=[content],
            source_language_code=source_language,
            target_language_code=target_language,
            mime_type="text/plain"
        )
        
        if response.translations:
            translated_text = response.translations[0].translated_text
            logger.debug(f"Translation successful: {source_language} -> {target_language}")
            return translated_text
        else:
            logger.error(f"No translation returned for {source_language} -> {target_language}")
            return ""
            
    except Exception as e:
        logger.error(f"Error translating text: {str(e)}")
        return ""


def save_translated_content(original_filename: str, target_language: str, content: str):
    """
    Save translated content to target bucket.
    
    Args:
        original_filename: Original file name
        target_language: Target language code
        content: Translated content
    """
    try:
        target_bucket = storage_client.bucket(TARGET_BUCKET)
        
        # Create language-specific path
        translated_filename = f"{target_language}/{original_filename}"
        
        # Create blob and upload content
        blob = target_bucket.blob(translated_filename)
        blob.upload_from_string(
            content,
            content_type=SUPPORTED_FILE_TYPES.get(get_file_extension(original_filename), 'text/plain')
        )
        
        # Add metadata
        blob.metadata = {
            'source_language': 'auto-detected',
            'target_language': target_language,
            'translated_by': 'cloud-translation-api',
            'original_file': original_filename
        }
        blob.patch()
        
        logger.info(f"Saved translated content: {translated_filename}")
        
    except Exception as e:
        logger.error(f"Error saving translated content: {str(e)}")
        raise


def needs_translation(filename: str, target_languages: List[str]) -> bool:
    """
    Check if a file needs translation by looking for existing translations.
    
    Args:
        filename: Source filename
        target_languages: List of target language codes
        
    Returns:
        True if translation is needed
    """
    try:
        target_bucket = storage_client.bucket(TARGET_BUCKET)
        
        # Check if translations exist for all target languages
        for lang in target_languages:
            translated_path = f"{lang}/{filename}"
            blob = target_bucket.blob(translated_path)
            if not blob.exists():
                return True
                
        return False  # All translations exist
        
    except Exception as e:
        logger.error(f"Error checking translation status: {str(e)}")
        return True  # Default to needing translation


def get_file_extension(filename: str) -> str:
    """
    Get file extension from filename.
    
    Args:
        filename: File name
        
    Returns:
        File extension including the dot
    """
    if '.' in filename:
        return '.' + filename.split('.')[-1].lower()
    return ''


def send_success_metric(metric_name: str, value: int):
    """
    Send success metric to Cloud Monitoring.
    
    Args:
        metric_name: Name of the metric
        value: Metric value
    """
    try:
        # This is a simplified metric sending - in production, implement proper monitoring
        logger.info(f"Success metric: {metric_name} = {value}")
    except Exception as e:
        logger.error(f"Error sending success metric: {str(e)}")


def send_error_metric(metric_name: str, error_message: str):
    """
    Send error metric to Cloud Monitoring.
    
    Args:
        metric_name: Name of the error metric
        error_message: Error description
    """
    try:
        # This is a simplified metric sending - in production, implement proper monitoring
        logger.error(f"Error metric: {metric_name} = {error_message}")
    except Exception as e:
        logger.error(f"Error sending error metric: {str(e)}")


def send_health_metric(is_healthy: bool):
    """
    Send health status metric to Cloud Monitoring.
    
    Args:
        is_healthy: Boolean indicating system health
    """
    try:
        # This is a simplified metric sending - in production, implement proper monitoring
        logger.info(f"Health metric: translation_pipeline_healthy = {is_healthy}")
    except Exception as e:
        logger.error(f"Error sending health metric: {str(e)}")