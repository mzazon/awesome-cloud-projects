"""
Cloud Function for handling file uploads to Cloud Storage
This function provides secure file upload functionality with validation and CORS support
"""

import functions_framework
from google.cloud import storage
import tempfile
import os
import json
import logging
from werkzeug.utils import secure_filename
from flask import Request

# Initialize Cloud Storage client
storage_client = storage.Client()
bucket_name = "${bucket_name}"

# Configuration from environment variables
MAX_FILE_SIZE_MB = int(os.environ.get('MAX_FILE_SIZE_MB', ${max_file_size}))
ALLOWED_EXTENSIONS = json.loads(os.environ.get('ALLOWED_EXTENSIONS', '${allowed_extensions}'))
MAX_FILE_SIZE_BYTES = MAX_FILE_SIZE_MB * 1024 * 1024

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def is_allowed_file(filename: str) -> bool:
    """Check if the file extension is allowed."""
    if not filename or '.' not in filename:
        return False
    
    extension = filename.rsplit('.', 1)[1].lower()
    return extension in [ext.lower() for ext in ALLOWED_EXTENSIONS]

def validate_file_size(content_length: int) -> bool:
    """Validate that the file size is within limits."""
    return content_length <= MAX_FILE_SIZE_BYTES

@functions_framework.http
def upload_file(request: Request):
    """
    HTTP Cloud Function for handling file uploads.
    
    Accepts multipart/form-data with a 'file' field.
    Returns JSON response with upload status and filename.
    """
    
    # Handle CORS preflight requests
    if request.method == 'OPTIONS':
        headers = {
            'Access-Control-Allow-Origin': '*',
            'Access-Control-Allow-Methods': 'POST, OPTIONS',
            'Access-Control-Allow-Headers': 'Content-Type',
            'Access-Control-Max-Age': '3600'
        }
        return ('', 204, headers)
    
    # Set CORS headers for all responses
    headers = {
        'Access-Control-Allow-Origin': '*',
        'Content-Type': 'application/json'
    }
    
    # Only allow POST requests
    if request.method != 'POST':
        logger.warning(f"Method {request.method} not allowed")
        return (
            json.dumps({'error': 'Method not allowed', 'allowed_methods': ['POST']}),
            405,
            headers
        )
    
    try:
        # Check if file is present in request
        if 'file' not in request.files:
            logger.warning("No file provided in request")
            return (
                json.dumps({'error': 'No file provided', 'field_name': 'file'}),
                400,
                headers
            )
        
        uploaded_file = request.files['file']
        
        # Check if a file was actually selected
        if uploaded_file.filename == '':
            logger.warning("Empty filename provided")
            return (
                json.dumps({'error': 'No file selected'}),
                400,
                headers
            )
        
        # Validate file extension
        if not is_allowed_file(uploaded_file.filename):
            logger.warning(f"File extension not allowed: {uploaded_file.filename}")
            return (
                json.dumps({
                    'error': 'File type not allowed',
                    'filename': uploaded_file.filename,
                    'allowed_extensions': ALLOWED_EXTENSIONS
                }),
                400,
                headers
            )
        
        # Validate file size
        content_length = request.content_length
        if content_length and not validate_file_size(content_length):
            logger.warning(f"File too large: {content_length} bytes")
            return (
                json.dumps({
                    'error': 'File too large',
                    'max_size_mb': MAX_FILE_SIZE_MB,
                    'received_size_bytes': content_length
                }),
                413,
                headers
            )
        
        # Secure the filename
        filename = secure_filename(uploaded_file.filename)
        if not filename:
            logger.warning("Invalid filename after sanitization")
            return (
                json.dumps({'error': 'Invalid filename'}),
                400,
                headers
            )
        
        # Upload file to Cloud Storage
        bucket = storage_client.bucket(bucket_name)
        blob = bucket.blob(filename)
        
        # Set content type based on file extension
        content_type = uploaded_file.content_type or 'application/octet-stream'
        blob.content_type = content_type
        
        # Upload the file
        blob.upload_from_file(uploaded_file.stream, content_type=content_type)
        
        logger.info(f"File uploaded successfully: {filename}")
        
        # Return success response
        response_data = {
            'message': f'File {filename} uploaded successfully',
            'filename': filename,
            'bucket': bucket_name,
            'size_bytes': blob.size if hasattr(blob, 'size') else None,
            'content_type': content_type,
            'upload_time': blob.time_created.isoformat() if hasattr(blob, 'time_created') and blob.time_created else None
        }
        
        return (json.dumps(response_data), 200, headers)
        
    except Exception as e:
        logger.error(f"Upload error: {str(e)}", exc_info=True)
        return (
            json.dumps({
                'error': 'Upload failed',
                'message': 'An internal error occurred during file upload'
            }),
            500,
            headers
        )