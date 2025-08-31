"""
Cloud Function for Operation Monitoring
Tracks video generation operations and updates status metadata
"""

import json
import logging
import os
from datetime import datetime, timedelta
from typing import Dict, Any, Tuple, Optional

from google import genai
from google.genai import types
from google.cloud import storage
from google.cloud import logging as cloud_logging
import functions_framework

# Initialize logging
cloud_logging.Client().setup_logging()
logging.basicConfig(level=logging.INFO)

# Configuration constants
PROJECT_ID = "${project_id}"
BUCKET_NAME = "${bucket_name}"
REGION = "us-central1"

# Operation monitoring configuration
OPERATION_TIMEOUT_HOURS = 2  # Maximum time to wait for operation completion
MAX_RETRY_ATTEMPTS = 3
OPERATION_CHECK_INTERVAL_SECONDS = 30


def validate_request(request_data: Dict[str, Any]) -> Tuple[bool, str, Dict[str, Any]]:
    """
    Validate the incoming monitoring request.
    
    Args:
        request_data: The request JSON data
        
    Returns:
        Tuple of (is_valid, error_message, validated_params)
    """
    if not request_data:
        return False, "Request body cannot be empty", {}
    
    # Handle both operation_name and operation_id formats
    operation_name = request_data.get('operation_name', '')
    operation_id = request_data.get('operation_id', '')
    
    if not operation_name and not operation_id:
        return False, "Either 'operation_name' or 'operation_id' must be provided", {}
    
    # If only operation_id is provided, construct the full operation name
    if operation_id and not operation_name:
        operation_name = f"projects/{PROJECT_ID}/locations/{REGION}/operations/{operation_id}"
    
    # If only operation_name is provided, extract operation_id
    if operation_name and not operation_id:
        try:
            operation_id = operation_name.split('/')[-1]
        except Exception:
            return False, "Invalid operation_name format", {}
    
    # Validate operation name format
    expected_prefix = f"projects/{PROJECT_ID}/locations/{REGION}/operations/"
    if not operation_name.startswith(expected_prefix):
        return False, f"Invalid operation_name format. Expected format: {expected_prefix}{{operation_id}}", {}
    
    # Optional: Check for additional monitoring options
    monitoring_options = request_data.get('options', {})
    include_details = monitoring_options.get('include_details', True)
    update_metadata = monitoring_options.get('update_metadata', True)
    
    validated_params = {
        'operation_name': operation_name,
        'operation_id': operation_id,
        'monitoring_options': {
            'include_details': include_details,
            'update_metadata': update_metadata
        }
    }
    
    return True, "", validated_params


def get_operation_metadata(bucket: storage.Bucket, operation_id: str) -> Optional[Dict[str, Any]]:
    """
    Retrieve operation metadata from Cloud Storage.
    
    Args:
        bucket: Cloud Storage bucket instance
        operation_id: Operation ID
        
    Returns:
        Metadata dictionary or None if not found
    """
    try:
        blob = bucket.blob(f"metadata/{operation_id}.json")
        if not blob.exists():
            logging.warning(f"Metadata file not found for operation {operation_id}")
            return None
        
        metadata_content = blob.download_as_text()
        metadata = json.loads(metadata_content)
        
        logging.info(f"Retrieved metadata for operation {operation_id}")
        return metadata
        
    except Exception as e:
        logging.error(f"Failed to retrieve metadata for operation {operation_id}: {str(e)}")
        return None


def update_operation_metadata(bucket: storage.Bucket, operation_id: str, 
                            status_update: Dict[str, Any]) -> bool:
    """
    Update operation metadata in Cloud Storage.
    
    Args:
        bucket: Cloud Storage bucket instance
        operation_id: Operation ID
        status_update: Status update information
        
    Returns:
        True if successful, False otherwise
    """
    try:
        # First, get existing metadata
        existing_metadata = get_operation_metadata(bucket, operation_id)
        if not existing_metadata:
            logging.warning(f"No existing metadata found for operation {operation_id}")
            existing_metadata = {
                'operation_id': operation_id,
                'status': 'unknown'
            }
        
        # Update with new status information
        existing_metadata.update(status_update)
        existing_metadata['last_updated'] = datetime.now().isoformat()
        
        # Save updated metadata
        blob = bucket.blob(f"metadata/{operation_id}.json")
        blob.upload_from_string(
            json.dumps(existing_metadata, indent=2),
            content_type='application/json'
        )
        
        logging.info(f"Updated metadata for operation {operation_id}")
        return True
        
    except Exception as e:
        logging.error(f"Failed to update metadata for operation {operation_id}: {str(e)}")
        return False


def check_operation_timeout(operation_metadata: Dict[str, Any]) -> bool:
    """
    Check if operation has exceeded timeout limits.
    
    Args:
        operation_metadata: Operation metadata dictionary
        
    Returns:
        True if operation has timed out
    """
    try:
        timestamp_str = operation_metadata.get('timestamp')
        if not timestamp_str:
            return False
        
        operation_start = datetime.fromisoformat(timestamp_str.replace('Z', '+00:00'))
        current_time = datetime.now()
        
        # Convert operation_start to naive datetime for comparison
        if operation_start.tzinfo is not None:
            operation_start = operation_start.replace(tzinfo=None)
        
        elapsed_time = current_time - operation_start
        timeout_threshold = timedelta(hours=OPERATION_TIMEOUT_HOURS)
        
        if elapsed_time > timeout_threshold:
            logging.warning(f"Operation {operation_metadata.get('operation_id')} has timed out "
                          f"(elapsed: {elapsed_time}, threshold: {timeout_threshold})")
            return True
        
        return False
        
    except Exception as e:
        logging.error(f"Error checking operation timeout: {str(e)}")
        return False


def parse_video_results(operation_result) -> Dict[str, Any]:
    """
    Parse video generation results from operation response.
    
    Args:
        operation_result: Operation result object
        
    Returns:
        Parsed video information
    """
    video_info = {
        'videos_generated': 0,
        'video_uris': [],
        'video_details': []
    }
    
    try:
        if hasattr(operation_result, 'generated_videos') and operation_result.generated_videos:
            videos = operation_result.generated_videos
            video_info['videos_generated'] = len(videos)
            
            for i, video in enumerate(videos):
                if hasattr(video, 'video') and hasattr(video.video, 'uri'):
                    video_uri = video.video.uri
                    video_info['video_uris'].append(video_uri)
                    
                    # Extract additional video details if available
                    video_detail = {
                        'index': i,
                        'uri': video_uri,
                        'filename': video_uri.split('/')[-1] if video_uri else None
                    }
                    
                    # Add any additional video metadata if available
                    if hasattr(video.video, 'display_name'):
                        video_detail['display_name'] = video.video.display_name
                    
                    video_info['video_details'].append(video_detail)
            
            logging.info(f"Parsed {video_info['videos_generated']} video results")
        else:
            logging.warning("No generated videos found in operation result")
            
    except Exception as e:
        logging.error(f"Error parsing video results: {str(e)}")
    
    return video_info


@functions_framework.http
def monitor_operations(request):
    """
    Main Cloud Function entry point for operation monitoring.
    
    Args:
        request: HTTP request object
        
    Returns:
        JSON response with operation status or error message
    """
    # Set CORS headers for web requests
    if request.method == 'OPTIONS':
        headers = {
            'Access-Control-Allow-Origin': '*',
            'Access-Control-Allow-Methods': 'POST, GET, OPTIONS',
            'Access-Control-Allow-Headers': 'Content-Type',
            'Access-Control-Max-Age': '3600'
        }
        return ('', 204, headers)
    
    headers = {'Access-Control-Allow-Origin': '*'}
    
    try:
        # Handle both GET and POST requests
        if request.method == 'GET':
            request_data = {
                'operation_name': request.args.get('operation_name'),
                'operation_id': request.args.get('operation_id')
            }
        else:
            request_data = request.get_json(silent=True) or {}
        
        # Parse and validate request
        is_valid, error_msg, validated_params = validate_request(request_data)
        if not is_valid:
            logging.warning(f"Invalid request: {error_msg}")
            return {'error': error_msg}, 400, headers
        
        operation_name = validated_params['operation_name']
        operation_id = validated_params['operation_id']
        
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
        
        # Initialize Cloud Storage client
        try:
            storage_client = storage.Client()
            bucket = storage_client.bucket(BUCKET_NAME)
            logging.info("Cloud Storage client initialized successfully")
        except Exception as e:
            logging.error(f"Storage operation failed: {str(e)}")
            return {'error': 'Failed to initialize storage'}, 500, headers
        
        # Get existing operation metadata
        operation_metadata = None
        if validated_params['monitoring_options']['include_details']:
            operation_metadata = get_operation_metadata(bucket, operation_id)
        
        # Check operation status using Vertex AI
        try:
            operation = client.operations.get(operation_name)
            logging.info(f"Retrieved operation status for {operation_id}")
        except Exception as e:
            logging.error(f"Failed to get operation status: {str(e)}")
            return {'error': f'Failed to get operation status: {str(e)}'}, 500, headers
        
        # Prepare status response
        status_response = {
            'operation_name': operation_name,
            'operation_id': operation_id,
            'timestamp': datetime.now().isoformat(),
            'done': operation.done
        }
        
        # Process based on operation status
        if operation.done:
            logging.info(f"Operation {operation_id} is completed")
            
            # Check for errors
            if hasattr(operation, 'error') and operation.error:
                error_message = str(operation.error)
                logging.error(f"Operation {operation_id} failed: {error_message}")
                
                status_response.update({
                    'status': 'failed',
                    'error': error_message,
                    'completion_time': datetime.now().isoformat()
                })
                
                # Update metadata with error status
                if validated_params['monitoring_options']['update_metadata']:
                    update_operation_metadata(bucket, operation_id, {
                        'status': 'failed',
                        'error': error_message,
                        'completion_time': datetime.now().isoformat()
                    })
                
            else:
                # Operation completed successfully
                status_response['status'] = 'completed'
                status_response['completion_time'] = datetime.now().isoformat()
                
                # Parse video results
                if hasattr(operation, 'result') and operation.result:
                    video_info = parse_video_results(operation.result)
                    status_response['video_results'] = video_info
                    
                    # Update metadata with completion status and video URIs
                    if validated_params['monitoring_options']['update_metadata']:
                        update_data = {
                            'status': 'completed',
                            'completion_time': datetime.now().isoformat(),
                            'video_results': video_info
                        }
                        
                        # Add primary video URI for backward compatibility
                        if video_info['video_uris']:
                            update_data['video_uri'] = video_info['video_uris'][0]
                        
                        update_operation_metadata(bucket, operation_id, update_data)
                    
                    logging.info(f"Operation {operation_id} completed successfully with "
                               f"{video_info['videos_generated']} videos")
                else:
                    logging.warning(f"Operation {operation_id} completed but no results found")
                    status_response['video_results'] = {
                        'videos_generated': 0,
                        'video_uris': [],
                        'message': 'Operation completed but no videos were generated'
                    }
        
        else:
            # Operation still in progress
            logging.info(f"Operation {operation_id} is still processing")
            status_response['status'] = 'processing'
            
            # Check for timeout
            if operation_metadata and check_operation_timeout(operation_metadata):
                status_response['status'] = 'timeout'
                status_response['warning'] = f'Operation has been running for more than {OPERATION_TIMEOUT_HOURS} hours'
                
                # Update metadata with timeout status
                if validated_params['monitoring_options']['update_metadata']:
                    update_operation_metadata(bucket, operation_id, {
                        'status': 'timeout',
                        'warning': status_response['warning']
                    })
            
            # Provide estimated completion time if available from metadata
            if operation_metadata:
                estimated_completion = operation_metadata.get('estimated_completion_time')
                if estimated_completion:
                    status_response['estimated_completion'] = estimated_completion
        
        # Include original metadata if requested
        if (validated_params['monitoring_options']['include_details'] and 
            operation_metadata):
            status_response['original_request'] = {
                'prompt': operation_metadata.get('prompt'),
                'duration': operation_metadata.get('duration'),
                'aspect_ratio': operation_metadata.get('aspect_ratio'),
                'timestamp': operation_metadata.get('timestamp')
            }
        
        logging.info(f"Operation {operation_id} status check completed: {status_response['status']}")
        return status_response, 200, headers
        
    except Exception as e:
        logging.error(f"Unexpected error in monitor_operations: {str(e)}")
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
        'service': 'operation-monitor',
        'version': '1.0.0'
    }


# Bulk operation monitoring endpoint
@functions_framework.http
def monitor_bulk_operations(request):
    """
    Monitor multiple operations at once.
    """
    headers = {'Access-Control-Allow-Origin': '*'}
    
    try:
        request_data = request.get_json(silent=True) or {}
        operation_ids = request_data.get('operation_ids', [])
        
        if not operation_ids or not isinstance(operation_ids, list):
            return {'error': 'operation_ids must be a non-empty list'}, 400, headers
        
        if len(operation_ids) > 10:
            return {'error': 'Maximum 10 operations can be monitored at once'}, 400, headers
        
        results = {}
        for op_id in operation_ids:
            # Simulate individual monitoring call
            mock_request_data = {'operation_id': op_id}
            is_valid, error_msg, validated_params = validate_request(mock_request_data)
            
            if not is_valid:
                results[op_id] = {'error': error_msg}
                continue
            
            # This would call the main monitoring logic
            # For now, return a placeholder
            results[op_id] = {
                'operation_id': op_id,
                'status': 'processing',
                'message': 'Use individual monitoring endpoint for detailed status'
            }
        
        return {
            'bulk_results': results,
            'timestamp': datetime.now().isoformat()
        }, 200, headers
        
    except Exception as e:
        logging.error(f"Error in bulk monitoring: {str(e)}")
        return {'error': 'Internal server error'}, 500, headers