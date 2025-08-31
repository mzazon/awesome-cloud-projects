import json
import logging
from flask import Request, jsonify
from google.cloud import storage
from google.cloud import logging as cloud_logging
import functions_framework
import traceback
from typing import Dict, Any, Union

# Configure logging
cloud_logging.Client().setup_logging()
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Initialize Cloud Storage client
storage_client = storage.Client()

def validate_json_content(content: str) -> Dict[str, Any]:
    """
    Validate and format JSON content.
    
    Args:
        content: String containing JSON data
        
    Returns:
        Dictionary with validation results
    """
    try:
        # Parse JSON to validate syntax
        parsed_json = json.loads(content)
        
        # Format with proper indentation
        formatted_json = json.dumps(parsed_json, indent=2, sort_keys=True)
        
        # Calculate basic statistics
        stats = {
            'size_bytes': len(content),
            'formatted_size_bytes': len(formatted_json),
            'keys_count': len(parsed_json) if isinstance(parsed_json, dict) else 0,
            'type': type(parsed_json).__name__
        }
        
        return {
            'valid': True,
            'formatted_json': formatted_json,
            'original_json': parsed_json,
            'statistics': stats,
            'message': 'JSON is valid and properly formatted'
        }
        
    except json.JSONDecodeError as e:
        return {
            'valid': False,
            'error': str(e),
            'error_type': 'JSONDecodeError',
            'line': getattr(e, 'lineno', None),
            'column': getattr(e, 'colno', None),
            'message': f'Invalid JSON syntax: {str(e)}'
        }
    except Exception as e:
        logger.error(f"Unexpected error during JSON validation: {str(e)}")
        return {
            'valid': False,
            'error': str(e),
            'error_type': type(e).__name__,
            'message': 'Unexpected error occurred during validation'
        }

def process_storage_file(bucket_name: str, file_name: str) -> Dict[str, Any]:
    """
    Process JSON file from Cloud Storage.
    
    Args:
        bucket_name: Name of the storage bucket
        file_name: Name of the file to process
        
    Returns:
        Dictionary with validation results
    """
    try:
        bucket = storage_client.bucket(bucket_name)
        blob = bucket.blob(file_name)
        
        if not blob.exists():
            return {
                'valid': False,
                'error': f'File {file_name} not found in bucket {bucket_name}',
                'message': 'File not found in storage'
            }
        
        # Download and validate the file content
        content = blob.download_as_text()
        result = validate_json_content(content)
        
        # Add storage metadata
        result['storage_info'] = {
            'bucket': bucket_name,
            'file': file_name,
            'size': blob.size,
            'content_type': blob.content_type,
            'updated': blob.updated.isoformat() if blob.updated else None
        }
        
        return result
        
    except Exception as e:
        logger.error(f"Error processing storage file: {str(e)}")
        return {
            'valid': False,
            'error': str(e),
            'message': 'Error accessing or processing storage file'
        }

@functions_framework.http
def json_validator_api(request: Request) -> Union[str, tuple]:
    """
    HTTP Cloud Function for JSON validation and formatting.
    
    Accepts JSON data via POST request body or processes files from Cloud Storage
    via query parameters.
    """
    try:
        # Set CORS headers for web applications
        headers = {
            'Access-Control-Allow-Origin': '*',
            'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
            'Access-Control-Allow-Headers': 'Content-Type',
            'Content-Type': 'application/json'
        }
        
        # Handle preflight OPTIONS request
        if request.method == 'OPTIONS':
            return ('', 200, headers)
        
        # Handle GET request for health check
        if request.method == 'GET':
            return jsonify({
                'status': 'healthy',
                'service': 'JSON Validator API',
                'version': '1.0',
                'endpoints': {
                    'POST /': 'Validate JSON in request body',
                    'GET /?bucket=BUCKET&file=FILE': 'Validate JSON file from storage'
                }
            }), 200, headers
        
        # Handle storage file processing
        bucket_name = request.args.get('bucket')
        file_name = request.args.get('file')
        
        if bucket_name and file_name:
            logger.info(f"Processing file {file_name} from bucket {bucket_name}")
            result = process_storage_file(bucket_name, file_name)
            return jsonify(result), 200, headers
        
        # Handle POST request with JSON in body
        if request.method == 'POST':
            if not request.data:
                return jsonify({
                    'valid': False,
                    'error': 'No data provided',
                    'message': 'Please provide JSON data in the request body'
                }), 400, headers
            
            # Get content as string for validation
            content = request.get_data(as_text=True)
            logger.info(f"Validating JSON content, size: {len(content)} bytes")
            
            result = validate_json_content(content)
            
            # Return appropriate HTTP status code
            status_code = 200 if result['valid'] else 400
            return jsonify(result), status_code, headers
        
        # Method not allowed
        return jsonify({
            'valid': False,
            'error': 'Method not allowed',
            'message': 'Only GET and POST methods are supported'
        }), 405, headers
        
    except Exception as e:
        logger.error(f"Unexpected error in function: {str(e)}")
        logger.error(traceback.format_exc())
        
        return jsonify({
            'valid': False,
            'error': str(e),
            'message': 'Internal server error occurred'
        }), 500, {'Content-Type': 'application/json'}