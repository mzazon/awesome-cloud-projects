"""
Cloud Function Trigger for Multi-Agent Content Analysis Workflows

This function is triggered by Cloud Storage object creation events and initiates
the multi-agent content analysis workflow using Cloud Workflows.

Features:
- Automatic content type detection
- Intelligent routing to appropriate agents
- Error handling and logging
- Integration with Cloud Workflows
- Support for multi-modal content processing
"""

import functions_framework
from google.cloud import workflows_v1
from google.cloud import storage
from google.cloud import logging as cloud_logging
import json
import os
import mimetypes
import re
from typing import Dict, Any, Optional
from datetime import datetime


# Initialize Cloud Logging
logging_client = cloud_logging.Client()
logging_client.setup_logging()

# Initialize clients
workflows_client = workflows_v1.WorkflowsClient()
storage_client = storage.Client()


@functions_framework.cloud_event
def trigger_content_analysis(cloud_event):
    """
    Triggered by Cloud Storage object creation to start content analysis workflow.
    
    Args:
        cloud_event: CloudEvent containing the Storage event data
    """
    try:
        # Extract file information from the cloud event
        data = cloud_event.data
        bucket_name = data['bucket']
        file_name = data['name']
        content_type = data.get('contentType', '')
        file_size = int(data.get('size', 0))
        
        # Log the trigger event
        print(f"Content analysis triggered for: gs://{bucket_name}/{file_name}")
        print(f"Content type: {content_type}, Size: {file_size} bytes")
        
        # Skip processing for result files and configuration files
        if should_skip_file(file_name):
            print(f"Skipping file: {file_name} (excluded pattern)")
            return {"status": "skipped", "reason": "excluded_pattern"}
        
        # Validate file size
        max_size_mb = int(os.environ.get('MAX_FILE_SIZE_MB', '100'))
        if file_size > max_size_mb * 1024 * 1024:
            print(f"File too large: {file_size} bytes (max: {max_size_mb}MB)")
            return {"status": "skipped", "reason": "file_too_large"}
        
        # Determine content processing type
        processing_type = determine_content_type(content_type, file_name)
        
        if processing_type == 'unsupported':
            print(f"Unsupported content type: {content_type}")
            return {"status": "skipped", "reason": "unsupported_content_type"}
        
        # Extract content metadata
        content_metadata = extract_content_metadata(bucket_name, file_name, data)
        
        # Prepare workflow input
        workflow_input = {
            'content_uri': f'gs://{bucket_name}/{file_name}',
            'content_type': processing_type,
            'metadata': {
                'bucket': bucket_name,
                'filename': file_name,
                'content_type': content_type,
                'size': file_size,
                'triggered_at': datetime.utcnow().isoformat() + 'Z',
                'function_version': '2.0',
                **content_metadata
            }
        }
        
        # Execute the workflow
        execution_result = execute_workflow(workflow_input)
        
        print(f"Workflow execution started: {execution_result.get('execution_name', 'unknown')}")
        print(f"Processing {processing_type} content: {file_name}")
        
        return {
            "status": "success",
            "workflow_execution": execution_result.get('execution_name'),
            "content_type": processing_type,
            "processing_started": True
        }
        
    except Exception as e:
        error_msg = f"Error starting workflow: {str(e)}"
        print(error_msg)
        
        # Log error to Cloud Logging
        logger = cloud_logging.Client().logger("content-analysis-trigger")
        logger.log_struct({
            "severity": "ERROR",
            "message": error_msg,
            "event_data": cloud_event.data,
            "error_type": type(e).__name__
        })
        
        return {
            "status": "error",
            "error_message": error_msg,
            "processing_started": False
        }


def should_skip_file(filename: str) -> bool:
    """
    Determine if a file should be skipped based on its path and name.
    
    Args:
        filename: The full path/name of the file
        
    Returns:
        True if the file should be skipped, False otherwise
    """
    skip_patterns = [
        r'^results/',           # Skip result files
        r'^config/',            # Skip configuration files
        r'^\..*',              # Skip hidden files
        r'.*\.tmp$',           # Skip temporary files
        r'.*\.log$',           # Skip log files
        r'.*_analysis\.json$', # Skip existing analysis files
        r'^sample-content/',   # Skip sample content (optional)
    ]
    
    for pattern in skip_patterns:
        if re.match(pattern, filename):
            return True
    
    return False


def determine_content_type(mime_type: str, filename: str) -> str:
    """
    Determine the appropriate processing type based on file characteristics.
    
    Args:
        mime_type: MIME type from the storage event
        filename: Name of the file
        
    Returns:
        Processing type: 'text', 'image', 'video', 'multi_modal', or 'unsupported'
    """
    filename_lower = filename.lower()
    
    # Text content types
    text_extensions = ['.txt', '.md', '.csv', '.json', '.xml', '.html', '.rtf']
    if (mime_type.startswith('text/') or 
        any(filename_lower.endswith(ext) for ext in text_extensions)):
        return 'text'
    
    # Image content types
    image_extensions = ['.jpg', '.jpeg', '.png', '.gif', '.bmp', '.webp', '.tiff', '.svg']
    if (mime_type.startswith('image/') or 
        any(filename_lower.endswith(ext) for ext in image_extensions)):
        return 'image'
    
    # Video content types
    video_extensions = ['.mp4', '.avi', '.mov', '.wmv', '.flv', '.webm', '.mkv']
    if (mime_type.startswith('video/') or 
        any(filename_lower.endswith(ext) for ext in video_extensions)):
        return 'video'
    
    # Audio files (processed as video for transcript extraction)
    audio_extensions = ['.mp3', '.wav', '.flac', '.aac', '.ogg', '.m4a']
    if (mime_type.startswith('audio/') or 
        any(filename_lower.endswith(ext) for ext in audio_extensions)):
        return 'video'
    
    # Multi-modal documents (contain multiple content types)
    multimodal_extensions = ['.pdf', '.docx', '.pptx', '.xlsx', '.odt', '.odp']
    if any(filename_lower.endswith(ext) for ext in multimodal_extensions):
        return 'multi_modal'
    
    # Unsupported content type
    return 'unsupported'


def extract_content_metadata(bucket_name: str, file_name: str, event_data: Dict[str, Any]) -> Dict[str, Any]:
    """
    Extract additional metadata about the content for processing context.
    
    Args:
        bucket_name: Name of the storage bucket
        file_name: Name of the file
        event_data: Storage event data
        
    Returns:
        Dictionary containing extracted metadata
    """
    metadata = {}
    
    try:
        # Get bucket and blob information
        bucket = storage_client.bucket(bucket_name)
        blob = bucket.blob(file_name)
        
        # Extract custom metadata if available
        if blob.metadata:
            metadata['custom_metadata'] = blob.metadata
        
        # Extract file path components
        path_parts = file_name.split('/')
        if len(path_parts) > 1:
            metadata['directory'] = '/'.join(path_parts[:-1])
            metadata['base_filename'] = path_parts[-1]
        else:
            metadata['directory'] = ''
            metadata['base_filename'] = file_name
        
        # Extract file extension
        if '.' in metadata['base_filename']:
            metadata['file_extension'] = metadata['base_filename'].split('.')[-1].lower()
        
        # Add processing hints based on directory structure
        if 'input' in metadata.get('directory', ''):
            metadata['processing_priority'] = 'high'
        elif 'batch' in metadata.get('directory', ''):
            metadata['processing_priority'] = 'normal'
        else:
            metadata['processing_priority'] = 'normal'
            
        # Add creation timestamp from event
        if 'timeCreated' in event_data:
            metadata['content_created_at'] = event_data['timeCreated']
        
        # Add content generation hint
        if 'generation' in event_data:
            metadata['storage_generation'] = event_data['generation']
            
    except Exception as e:
        print(f"Warning: Could not extract extended metadata: {str(e)}")
        metadata['metadata_extraction_error'] = str(e)
    
    return metadata


def execute_workflow(workflow_input: Dict[str, Any]) -> Dict[str, Any]:
    """
    Execute the Cloud Workflows workflow with the provided input.
    
    Args:
        workflow_input: Input data for the workflow
        
    Returns:
        Dictionary containing execution information
    """
    try:
        # Get environment variables
        project_id = os.environ['GCP_PROJECT']
        location = os.environ['FUNCTION_REGION']
        workflow_name = os.environ['WORKFLOW_NAME']
        
        # Construct the fully qualified workflow name
        parent = f"projects/{project_id}/locations/{location}/workflows/{workflow_name}"
        
        # Prepare the execution request
        execution_request = workflows_v1.CreateExecutionRequest(
            parent=parent,
            execution=workflows_v1.Execution(
                argument=json.dumps(workflow_input)
            )
        )
        
        # Execute the workflow
        operation = workflows_client.create_execution(request=execution_request)
        
        return {
            "execution_name": operation.name,
            "workflow_name": workflow_name,
            "project_id": project_id,
            "location": location,
            "status": "started"
        }
        
    except Exception as e:
        raise Exception(f"Failed to execute workflow: {str(e)}")


def validate_environment() -> bool:
    """
    Validate that all required environment variables are set.
    
    Returns:
        True if all required variables are present, False otherwise
    """
    required_vars = [
        'WORKFLOW_NAME',
        'GCP_PROJECT', 
        'FUNCTION_REGION',
        'BUCKET_NAME'
    ]
    
    missing_vars = []
    for var in required_vars:
        if not os.environ.get(var):
            missing_vars.append(var)
    
    if missing_vars:
        print(f"Missing required environment variables: {missing_vars}")
        return False
    
    return True


# Validate environment on module load
if not validate_environment():
    print("Warning: Environment validation failed - function may not work correctly")


# Health check endpoint for monitoring
@functions_framework.http
def health_check(request):
    """
    Health check endpoint for monitoring the function status.
    
    Args:
        request: HTTP request object
        
    Returns:
        JSON response with health status
    """
    try:
        # Basic environment check
        env_valid = validate_environment()
        
        # Test workflow client connection
        workflows_healthy = True
        try:
            workflows_client.list_workflows(
                parent=f"projects/{os.environ.get('GCP_PROJECT', '')}/locations/{os.environ.get('FUNCTION_REGION', '')}"
            )
        except Exception as e:
            workflows_healthy = False
            print(f"Workflows health check failed: {str(e)}")
        
        # Test storage client connection
        storage_healthy = True
        try:
            bucket_name = os.environ.get('BUCKET_NAME', '')
            if bucket_name:
                bucket = storage_client.bucket(bucket_name)
                bucket.exists()
        except Exception as e:
            storage_healthy = False
            print(f"Storage health check failed: {str(e)}")
        
        overall_health = env_valid and workflows_healthy and storage_healthy
        
        return {
            "status": "healthy" if overall_health else "unhealthy",
            "timestamp": datetime.utcnow().isoformat() + 'Z',
            "checks": {
                "environment": env_valid,
                "workflows": workflows_healthy,
                "storage": storage_healthy
            },
            "version": "2.0"
        }
        
    except Exception as e:
        return {
            "status": "error",
            "error": str(e),
            "timestamp": datetime.utcnow().isoformat() + 'Z'
        }