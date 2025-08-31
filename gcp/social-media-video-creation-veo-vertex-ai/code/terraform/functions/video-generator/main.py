"""
Cloud Function for Video Generation using Veo 3
Handles video generation requests and manages long-running operations
"""

import json
import logging
import os
import time
from datetime import datetime
from typing import Dict, Any, Tuple

from google import genai
from google.genai import types
from google.cloud import storage
from google.cloud import logging as cloud_logging
import functions_framework

# Initialize logging
cloud_logging.Client().setup_logging()
logging.basicConfig(level=logging.INFO)

# Configuration constants
VEO_MODEL = "${veo_model_version}"
PROJECT_ID = "${project_id}"
BUCKET_NAME = "${bucket_name}"
REGION = "us-central1"

# Video generation limits and defaults
DEFAULT_DURATION = 8
MAX_DURATION = 30
MIN_DURATION = 2
DEFAULT_ASPECT_RATIO = "9:16"
DEFAULT_RESOLUTION = "720p"

# Valid configuration values
VALID_ASPECT_RATIOS = ["16:9", "9:16", "1:1", "4:3", "3:4"]
VALID_RESOLUTIONS = ["480p", "720p", "1080p"]
VALID_PERSON_GENERATION = ["allow_adult", "allow_minor", "none"]


def validate_request(request_data: Dict[str, Any]) -> Tuple[bool, str, Dict[str, Any]]:
    """
    Validate the incoming video generation request.
    
    Args:
        request_data: The request JSON data
        
    Returns:
        Tuple of (is_valid, error_message, validated_params)
    """
    if not request_data or 'prompt' not in request_data:
        return False, "Missing 'prompt' in request body", {}
    
    prompt = request_data.get('prompt', '').strip()
    if not prompt:
        return False, "Prompt cannot be empty", {}
    
    if len(prompt) > 1000:
        return False, "Prompt cannot exceed 1000 characters", {}
    
    # Validate duration
    duration = request_data.get('duration', DEFAULT_DURATION)
    try:
        duration = int(duration)
        if duration < MIN_DURATION or duration > MAX_DURATION:
            return False, f"Duration must be between {MIN_DURATION} and {MAX_DURATION} seconds", {}
    except (ValueError, TypeError):
        return False, "Duration must be a valid integer", {}
    
    # Validate aspect ratio
    aspect_ratio = request_data.get('aspect_ratio', DEFAULT_ASPECT_RATIO)
    if aspect_ratio not in VALID_ASPECT_RATIOS:
        return False, f"Aspect ratio must be one of: {', '.join(VALID_ASPECT_RATIOS)}", {}
    
    # Validate resolution
    resolution = request_data.get('resolution', DEFAULT_RESOLUTION)
    if resolution not in VALID_RESOLUTIONS:
        return False, f"Resolution must be one of: {', '.join(VALID_RESOLUTIONS)}", {}
    
    # Validate person generation setting
    person_generation = request_data.get('person_generation', 'allow_adult')
    if person_generation not in VALID_PERSON_GENERATION:
        return False, f"Person generation must be one of: {', '.join(VALID_PERSON_GENERATION)}", {}
    
    validated_params = {
        'prompt': prompt,
        'duration': duration,
        'aspect_ratio': aspect_ratio,
        'resolution': resolution,
        'person_generation': person_generation,
        'number_of_videos': 1  # Fixed to 1 for simplicity
    }
    
    return True, "", validated_params


def optimize_prompt_for_social_media(prompt: str, duration: int, aspect_ratio: str) -> str:
    """
    Optimize the user prompt for social media video generation.
    
    Args:
        prompt: Original user prompt
        duration: Video duration in seconds
        aspect_ratio: Video aspect ratio
        
    Returns:
        Optimized prompt for Veo 3
    """
    # Add social media optimization instructions
    optimization_prefix = f"Create a {duration}-second engaging social media video: "
    
    # Add quality and style instructions
    quality_suffix = ". High quality, vibrant colors, smooth motion, professional lighting"
    
    # Add aspect ratio specific optimizations
    if aspect_ratio == "9:16":
        format_optimization = ", optimized for vertical mobile viewing"
    elif aspect_ratio == "16:9":
        format_optimization = ", optimized for horizontal viewing"
    else:
        format_optimization = ", optimized for square format social posts"
    
    # Combine all optimizations
    optimized_prompt = optimization_prefix + prompt + quality_suffix + format_optimization
    
    # Ensure prompt doesn't exceed Veo 3 limits
    if len(optimized_prompt) > 1500:
        # Truncate while preserving the optimization instructions
        available_length = 1500 - len(optimization_prefix) - len(quality_suffix) - len(format_optimization)
        truncated_prompt = prompt[:available_length].strip()
        optimized_prompt = optimization_prefix + truncated_prompt + quality_suffix + format_optimization
    
    return optimized_prompt


def save_operation_metadata(bucket: storage.Bucket, operation_name: str, 
                          request_params: Dict[str, Any]) -> bool:
    """
    Save operation metadata to Cloud Storage for tracking.
    
    Args:
        bucket: Cloud Storage bucket instance
        operation_name: Long-running operation name
        request_params: Original request parameters
        
    Returns:
        True if successful, False otherwise
    """
    try:
        operation_id = operation_name.split('/')[-1]
        metadata = {
            'operation_name': operation_name,
            'operation_id': operation_id,
            'prompt': request_params['prompt'],
            'timestamp': datetime.now().isoformat(),
            'status': 'processing',
            'duration': request_params['duration'],
            'aspect_ratio': request_params['aspect_ratio'],
            'resolution': request_params['resolution'],
            'person_generation': request_params['person_generation'],
            'optimized_prompt': request_params.get('optimized_prompt', ''),
            'estimated_completion_time': 'URL_HERE_IF_AVAILABLE',
            'project_id': PROJECT_ID,
            'model_version': VEO_MODEL
        }
        
        blob = bucket.blob(f"metadata/{operation_id}.json")
        blob.upload_from_string(
            json.dumps(metadata, indent=2),
            content_type='application/json'
        )
        
        logging.info(f"Metadata saved for operation {operation_id}")
        return True
        
    except Exception as e:
        logging.error(f"Failed to save operation metadata: {str(e)}")
        return False


@functions_framework.http
def generate_video(request):
    """
    Main Cloud Function entry point for video generation.
    
    Args:
        request: HTTP request object
        
    Returns:
        JSON response with operation details or error message
    """
    # Set CORS headers for web requests
    if request.method == 'OPTIONS':
        headers = {
            'Access-Control-Allow-Origin': '*',
            'Access-Control-Allow-Methods': 'POST, OPTIONS',
            'Access-Control-Allow-Headers': 'Content-Type',
            'Access-Control-Max-Age': '3600'
        }
        return ('', 204, headers)
    
    headers = {'Access-Control-Allow-Origin': '*'}
    
    try:
        # Parse and validate request
        request_json = request.get_json(silent=True)
        if not request_json:
            return {'error': 'Request must contain valid JSON'}, 400, headers
        
        is_valid, error_msg, validated_params = validate_request(request_json)
        if not is_valid:
            logging.warning(f"Invalid request: {error_msg}")
            return {'error': error_msg}, 400, headers
        
        # Initialize Vertex AI client
        try:
            client = genai.Client(
                vertexai=True,
                project=PROJECT_ID,
                location=REGION
            )
            logging.info("Vertex AI client initialized successfully")
        except Exception as e:
            logging.error(f"Failed to initialize Vertex AI client: {str(e)}")
            return {'error': 'Failed to initialize AI service'}, 500, headers
        
        # Optimize prompt for social media
        optimized_prompt = optimize_prompt_for_social_media(
            validated_params['prompt'],
            validated_params['duration'],
            validated_params['aspect_ratio']
        )
        validated_params['optimized_prompt'] = optimized_prompt
        
        # Generate video using Veo 3
        try:
            operation = client.models.generate_videos(
                model=VEO_MODEL,
                prompt=optimized_prompt,
                config=types.GenerateVideosConfig(
                    aspect_ratio=validated_params['aspect_ratio'],
                    output_gcs_uri=f"gs://{BUCKET_NAME}/raw-videos/",
                    number_of_videos=validated_params['number_of_videos'],
                    duration_seconds=validated_params['duration'],
                    person_generation=validated_params['person_generation'],
                    resolution=validated_params['resolution']
                ),
            )
            
            logging.info(f"Video generation operation started: {operation.name}")
            
        except Exception as e:
            logging.error(f"Failed to start video generation: {str(e)}")
            return {'error': f'Failed to start video generation: {str(e)}'}, 500, headers
        
        # Save operation metadata to Cloud Storage
        try:
            storage_client = storage.Client()
            bucket = storage_client.bucket(BUCKET_NAME)
            
            metadata_saved = save_operation_metadata(bucket, operation.name, validated_params)
            if not metadata_saved:
                logging.warning("Failed to save operation metadata, but continuing...")
            
        except Exception as e:
            logging.error(f"Storage operation failed: {str(e)}")
            return {'error': 'Failed to initialize storage'}, 500, headers
        
        # Return success response
        response = {
            'status': 'success',
            'operation_name': operation.name,
            'operation_id': operation.name.split('/')[-1],
            'estimated_completion': '60-120 seconds',
            'prompt': validated_params['prompt'],
            'optimized_prompt': optimized_prompt,
            'video_settings': {
                'duration': validated_params['duration'],
                'aspect_ratio': validated_params['aspect_ratio'],
                'resolution': validated_params['resolution'],
                'person_generation': validated_params['person_generation']
            },
            'model_version': VEO_MODEL,
            'timestamp': datetime.now().isoformat(),
            'next_steps': {
                'monitor_url': f'https://{REGION}-{PROJECT_ID}.cloudfunctions.net/monitor-operations',
                'check_status': 'Use the operation_name to check status via monitor function'
            }
        }
        
        logging.info(f"Successfully initiated video generation for operation {operation.name}")
        return response, 200, headers
        
    except Exception as e:
        logging.error(f"Unexpected error in generate_video: {str(e)}")
        return {
            'error': 'Internal server error occurred',
            'timestamp': datetime.now().isoformat()
        }, 500, headers


# Health check endpoint for monitoring
@functions_framework.http  
def health_check(request):
    """Simple health check endpoint."""
    return {
        'status': 'healthy',
        'timestamp': datetime.now().isoformat(),
        'service': 'video-generator',
        'version': '1.0.0'
    }