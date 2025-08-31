"""
Cloud Function for generating signed URLs for file downloads
This function creates time-limited shareable links for files stored in Cloud Storage
"""

import functions_framework
from google.cloud import storage
from datetime import datetime, timedelta
import json
import logging
import os
from flask import Request

# Initialize Cloud Storage client
storage_client = storage.Client()
bucket_name = "${bucket_name}"

# Configuration from environment variables
EXPIRATION_HOURS = int(os.environ.get('EXPIRATION_HOURS', ${expiration_hours}))

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def validate_filename(filename: str) -> bool:
    """Validate that the filename is safe and non-empty."""
    if not filename or filename.strip() == '':
        return False
    
    # Check for path traversal attempts
    if '..' in filename or '/' in filename or '\\' in filename:
        return False
    
    return True

@functions_framework.http
def generate_link(request: Request):
    """
    HTTP Cloud Function for generating signed URLs for file downloads.
    
    Accepts JSON with 'filename' field or GET request with filename parameter.
    Returns JSON response with signed URL and expiration information.
    """
    
    # Handle CORS preflight requests
    if request.method == 'OPTIONS':
        headers = {
            'Access-Control-Allow-Origin': '*',
            'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
            'Access-Control-Allow-Headers': 'Content-Type',
            'Access-Control-Max-Age': '3600'
        }
        return ('', 204, headers)
    
    # Set CORS headers for all responses
    headers = {
        'Access-Control-Allow-Origin': '*',
        'Content-Type': 'application/json'
    }
    
    try:
        # Extract filename from request
        filename = None
        
        if request.method == 'POST':
            # Handle JSON POST request
            try:
                request_json = request.get_json(silent=True)
                if request_json and 'filename' in request_json:
                    filename = request_json['filename']
            except Exception as e:
                logger.warning(f"Failed to parse JSON: {str(e)}")
                return (
                    json.dumps({'error': 'Invalid JSON in request body'}),
                    400,
                    headers
                )
        
        elif request.method == 'GET':
            # Handle GET request with query parameter
            filename = request.args.get('filename')
        
        else:
            logger.warning(f"Method {request.method} not allowed")
            return (
                json.dumps({'error': 'Method not allowed', 'allowed_methods': ['GET', 'POST']}),
                405,
                headers
            )
        
        # Validate filename presence
        if not filename:
            logger.warning("No filename provided in request")
            return (
                json.dumps({
                    'error': 'Filename required',
                    'usage': {
                        'POST': 'Send JSON with {"filename": "your-file.txt"}',
                        'GET': 'Use query parameter: ?filename=your-file.txt'
                    }
                }),
                400,
                headers
            )
        
        # Validate filename format
        if not validate_filename(filename):
            logger.warning(f"Invalid filename: {filename}")
            return (
                json.dumps({
                    'error': 'Invalid filename',
                    'filename': filename,
                    'requirements': 'Filename must be non-empty and not contain path traversal characters'
                }),
                400,
                headers
            )
        
        # Check if file exists in Cloud Storage
        bucket = storage_client.bucket(bucket_name)
        blob = bucket.blob(filename)
        
        if not blob.exists():
            logger.warning(f"File not found: {filename}")
            return (
                json.dumps({
                    'error': 'File not found',
                    'filename': filename,
                    'bucket': bucket_name
                }),
                404,
                headers
            )
        
        # Generate signed URL
        expiration_time = datetime.utcnow() + timedelta(hours=EXPIRATION_HOURS)
        
        try:
            signed_url = blob.generate_signed_url(
                version="v4",
                expiration=expiration_time,
                method="GET"
            )
        except Exception as e:
            logger.error(f"Failed to generate signed URL: {str(e)}")
            return (
                json.dumps({
                    'error': 'Failed to generate signed URL',
                    'message': 'Unable to create shareable link'
                }),
                500,
                headers
            )
        
        # Get file metadata
        blob.reload()  # Refresh blob attributes
        
        logger.info(f"Generated signed URL for file: {filename}")
        
        # Prepare response data
        response_data = {
            'filename': filename,
            'download_url': signed_url,
            'expires_at': expiration_time.isoformat() + 'Z',
            'expires_in': f'{EXPIRATION_HOURS} hour(s)',
            'bucket': bucket_name,
            'file_info': {
                'size_bytes': blob.size,
                'content_type': blob.content_type,
                'created': blob.time_created.isoformat() + 'Z' if blob.time_created else None,
                'updated': blob.updated.isoformat() + 'Z' if blob.updated else None,
                'etag': blob.etag
            }
        }
        
        return (json.dumps(response_data), 200, headers)
        
    except Exception as e:
        logger.error(f"Link generation error: {str(e)}", exc_info=True)
        return (
            json.dumps({
                'error': 'Link generation failed',
                'message': 'An internal error occurred while generating the shareable link'
            }),
            500,
            headers
        )