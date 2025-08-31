#!/usr/bin/env python3
"""
Music Generation API Cloud Function
REST API endpoint for submitting music generation requests.
Validates input, generates unique request IDs, and queues requests for processing.
"""

import os
import json
import uuid
import logging
from datetime import datetime, timezone
from typing import Dict, Any, Tuple, List
from google.cloud import storage
import functions_framework
from flask import Request, jsonify, Response

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Initialize storage client
storage_client = storage.Client()

# Configuration from environment variables
INPUT_BUCKET = "${input_bucket}"

# Validation constants
MIN_PROMPT_LENGTH = 5
MAX_PROMPT_LENGTH = 500
MAX_DURATION_SECONDS = 300
VALID_STYLES = ['instrumental', 'ambient', 'classical', 'rock', 'electronic', 'jazz']
VALID_TEMPOS = ['slow', 'moderate', 'fast']

@functions_framework.http
def music_api(request: Request) -> Tuple[Response, int]:
    """
    HTTP Cloud Function for music generation API.
    
    Args:
        request: Flask Request object containing the HTTP request
        
    Returns:
        Tuple[Response, int]: Flask response and HTTP status code
    """
    
    # CORS headers for cross-origin requests
    cors_headers = {
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Methods': 'POST, OPTIONS',
        'Access-Control-Allow-Headers': 'Content-Type, Authorization',
        'Access-Control-Max-Age': '3600'
    }
    
    # Handle preflight OPTIONS request
    if request.method == 'OPTIONS':
        return ('', 204, cors_headers)
    
    # Only allow POST requests for API calls
    if request.method != 'POST':
        error_response = {
            'error': 'Method not allowed',
            'message': 'Only POST method is supported for music generation requests',
            'allowed_methods': ['POST']
        }
        return jsonify(error_response), 405, cors_headers
    
    try:
        # Parse and validate JSON request body
        request_json = request.get_json()
        if not request_json:
            error_response = {
                'error': 'Missing request body',
                'message': 'Request must include JSON body with music generation parameters'
            }
            return jsonify(error_response), 400, cors_headers
        
        # Validate request structure and content
        validation_result = _validate_request(request_json)
        if not validation_result['valid']:
            error_response = {
                'error': 'Validation failed',
                'message': validation_result['message'],
                'details': validation_result.get('details', {})
            }
            return jsonify(error_response), 400, cors_headers
        
        # Generate unique request ID
        request_id = str(uuid.uuid4())
        
        # Prepare validated music generation request
        music_request = {
            'request_id': request_id,
            'prompt': request_json['prompt'].strip(),
            'style': request_json.get('style', 'instrumental').lower(),
            'duration_seconds': min(request_json.get('duration_seconds', 30), MAX_DURATION_SECONDS),
            'tempo': request_json.get('tempo', 'moderate').lower(),
            'created_at': datetime.now(timezone.utc).isoformat(),
            'status': 'queued',
            'model': 'lyria-002',
            'api_version': '1.0',
            'priority': request_json.get('priority', 'normal'),
            'metadata': {
                'user_agent': request.headers.get('User-Agent', 'unknown'),
                'client_ip': request.remote_addr,
                'request_size_bytes': len(request.data) if request.data else 0
            }
        }
        
        # Apply final validation and sanitization
        music_request = _sanitize_request(music_request)
        
        # Upload request to Cloud Storage to trigger processing
        success = _queue_music_request(music_request)
        if not success:
            error_response = {
                'error': 'Queue error',
                'message': 'Failed to queue music generation request. Please try again.',
                'request_id': request_id
            }
            return jsonify(error_response), 500, cors_headers
        
        # Prepare successful response
        response_data = {
            'request_id': request_id,
            'status': 'queued',
            'message': 'Music generation request submitted successfully',
            'estimated_completion': _estimate_completion_time(music_request['duration_seconds']),
            'model': 'lyria-002',
            'parameters': {
                'prompt': music_request['prompt'][:100] + ('...' if len(music_request['prompt']) > 100 else ''),
                'style': music_request['style'],
                'duration_seconds': music_request['duration_seconds'],
                'tempo': music_request['tempo']
            },
            'tracking': {
                'status_endpoint': f'/status/{request_id}',  # Future enhancement
                'download_endpoint': f'/download/{request_id}',  # Future enhancement
                'created_at': music_request['created_at']
            }
        }
        
        logger.info(f"Successfully queued music generation request {request_id}")
        return jsonify(response_data), 200, cors_headers
        
    except json.JSONDecodeError as e:
        logger.error(f"JSON decode error: {str(e)}")
        error_response = {
            'error': 'Invalid JSON',
            'message': 'Request body must be valid JSON format',
            'details': str(e)
        }
        return jsonify(error_response), 400, cors_headers
        
    except Exception as e:
        logger.error(f"Unexpected error in music API: {str(e)}")
        error_response = {
            'error': 'Internal server error',
            'message': 'An unexpected error occurred while processing your request',
            'request_id': locals().get('request_id', 'unknown')
        }
        return jsonify(error_response), 500, cors_headers


def _validate_request(request_data: Dict[str, Any]) -> Dict[str, Any]:
    """
    Validate music generation request data.
    
    Args:
        request_data: Dictionary containing request parameters
        
    Returns:
        Dict[str, Any]: Validation result with 'valid' boolean and 'message'
    """
    
    # Check for required fields
    required_fields = ['prompt']
    missing_fields = [field for field in required_fields if field not in request_data]
    
    if missing_fields:
        return {
            'valid': False,
            'message': f"Missing required fields: {', '.join(missing_fields)}",
            'details': {'missing_fields': missing_fields, 'required_fields': required_fields}
        }
    
    # Validate prompt
    prompt = request_data.get('prompt', '').strip()
    if len(prompt) < MIN_PROMPT_LENGTH:
        return {
            'valid': False,
            'message': f'Prompt must be at least {MIN_PROMPT_LENGTH} characters long',
            'details': {'current_length': len(prompt), 'minimum_length': MIN_PROMPT_LENGTH}
        }
    
    if len(prompt) > MAX_PROMPT_LENGTH:
        return {
            'valid': False,
            'message': f'Prompt must be less than {MAX_PROMPT_LENGTH} characters',
            'details': {'current_length': len(prompt), 'maximum_length': MAX_PROMPT_LENGTH}
        }
    
    # Validate optional parameters
    style = request_data.get('style', 'instrumental').lower()
    if style not in VALID_STYLES:
        return {
            'valid': False,
            'message': f'Invalid style. Must be one of: {", ".join(VALID_STYLES)}',
            'details': {'provided_style': style, 'valid_styles': VALID_STYLES}
        }
    
    tempo = request_data.get('tempo', 'moderate').lower()
    if tempo not in VALID_TEMPOS:
        return {
            'valid': False,
            'message': f'Invalid tempo. Must be one of: {", ".join(VALID_TEMPOS)}',
            'details': {'provided_tempo': tempo, 'valid_tempos': VALID_TEMPOS}
        }
    
    # Validate duration
    duration = request_data.get('duration_seconds', 30)
    if not isinstance(duration, (int, float)):
        return {
            'valid': False,
            'message': 'Duration must be a number',
            'details': {'provided_duration': duration, 'expected_type': 'number'}
        }
    
    if duration <= 0 or duration > MAX_DURATION_SECONDS:
        return {
            'valid': False,
            'message': f'Duration must be between 1 and {MAX_DURATION_SECONDS} seconds',
            'details': {'provided_duration': duration, 'valid_range': f'1-{MAX_DURATION_SECONDS}'}
        }
    
    return {'valid': True, 'message': 'Request validation passed'}


def _sanitize_request(request_data: Dict[str, Any]) -> Dict[str, Any]:
    """
    Sanitize and normalize request data.
    
    Args:
        request_data: Dictionary containing request parameters
        
    Returns:
        Dict[str, Any]: Sanitized request data
    """
    
    # Ensure style and tempo are valid (fallback to defaults if somehow invalid)
    if request_data.get('style', '').lower() not in VALID_STYLES:
        request_data['style'] = 'instrumental'
    
    if request_data.get('tempo', '').lower() not in VALID_TEMPOS:
        request_data['tempo'] = 'moderate'
    
    # Ensure duration is within bounds
    duration = request_data.get('duration_seconds', 30)
    request_data['duration_seconds'] = max(1, min(duration, MAX_DURATION_SECONDS))
    
    # Sanitize prompt (remove excessive whitespace, normalize)
    prompt = request_data.get('prompt', '').strip()
    # Remove multiple consecutive spaces
    prompt = ' '.join(prompt.split())
    request_data['prompt'] = prompt
    
    return request_data


def _queue_music_request(request_data: Dict[str, Any]) -> bool:
    """
    Queue music generation request by uploading to Cloud Storage.
    
    Args:
        request_data: Dictionary containing validated request parameters
        
    Returns:
        bool: True if successfully queued, False otherwise
    """
    
    try:
        bucket = storage_client.bucket(INPUT_BUCKET)
        blob_name = f"requests/{request_data['request_id']}.json"
        blob = bucket.blob(blob_name)
        
        # Upload request as JSON
        blob.upload_from_string(
            json.dumps(request_data, indent=2, ensure_ascii=False),
            content_type='application/json'
        )
        
        # Set metadata for better organization
        blob.metadata = {
            'request_id': request_data['request_id'],
            'style': request_data['style'],
            'duration_seconds': str(request_data['duration_seconds']),
            'queued_at': request_data['created_at'],
            'api_version': request_data.get('api_version', '1.0')
        }
        blob.patch()
        
        logger.info(f"Successfully queued request {request_data['request_id']} in {INPUT_BUCKET}/{blob_name}")
        return True
        
    except Exception as e:
        logger.error(f"Failed to queue request {request_data.get('request_id', 'unknown')}: {str(e)}")
        return False


def _estimate_completion_time(duration_seconds: int) -> str:
    """
    Estimate completion time based on audio duration.
    
    Args:
        duration_seconds: Duration of requested audio in seconds
        
    Returns:
        str: Human-readable completion estimate
    """
    
    # Base processing time + duration-dependent time
    base_time = 30  # seconds
    processing_multiplier = 2  # 2x the audio duration for processing
    
    total_seconds = base_time + (duration_seconds * processing_multiplier)
    
    if total_seconds < 60:
        return f"{total_seconds} seconds"
    elif total_seconds < 300:  # 5 minutes
        minutes = total_seconds // 60
        return f"{minutes} minute{'s' if minutes > 1 else ''}"
    else:
        minutes = total_seconds // 60
        return f"{minutes} minutes (longer requests may take additional time)"


# Health check endpoint (future enhancement)
@functions_framework.http
def health_check(request: Request) -> Tuple[Response, int]:
    """
    Health check endpoint for monitoring.
    This would be deployed as a separate function or added to the main API.
    """
    
    if request.path == '/health':
        health_data = {
            'status': 'healthy',
            'timestamp': datetime.now(timezone.utc).isoformat(),
            'service': 'music-generation-api',
            'version': '1.0'
        }
        return jsonify(health_data), 200
    
    return music_api(request)