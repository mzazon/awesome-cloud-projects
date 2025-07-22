import os
import json
import logging
from google.cloud import aiplatform
from google.cloud import storage
from google.cloud import functions_v1
import base64
from typing import Dict, Any

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def process_video(cloud_event):
    """
    Triggered by Cloud Storage object upload.
    Initiates video processing workflow for uploaded videos.
    
    Args:
        cloud_event: CloudEvent containing the storage event details
        
    Returns:
        dict: Status and metadata about the processing operation
    """
    
    try:
        # Parse the Cloud Storage event
        file_name = cloud_event.data["name"]
        bucket_name = cloud_event.data["bucket"]
        
        logger.info(f"Processing video upload event: {file_name} from bucket: {bucket_name}")
        
        # Skip if not a video file
        video_extensions = ('.mp4', '.mov', '.avi', '.mkv', '.webm', '.flv', '.wmv')
        if not file_name.lower().endswith(video_extensions):
            logger.info(f"Skipping non-video file: {file_name}")
            return {"status": "skipped", "reason": "not a video file"}
        
        # Get environment variables
        project_id = os.environ.get('PROJECT_ID', '${project_id}')
        region = os.environ.get('REGION', '${region}')
        results_bucket = os.environ.get('RESULTS_BUCKET', '${results_bucket}')
        
        logger.info(f"Configuration - Project: {project_id}, Region: {region}")
        
        # Initialize Vertex AI client
        aiplatform.init(project=project_id, location=region)
        
        # Create video URI
        video_uri = f"gs://{bucket_name}/{file_name}"
        
        # Create analytics job metadata
        analytics_metadata = {
            "video_uri": video_uri,
            "file_name": file_name,
            "bucket_name": bucket_name,
            "processing_status": "initiated",
            "timestamp": cloud_event.time if hasattr(cloud_event, 'time') else None,
            "processor_version": "1.0",
            "project_id": project_id,
            "region": region
        }
        
        # Store metadata in results bucket
        storage_client = storage.Client()
        results_bucket_obj = storage_client.bucket(results_bucket)
        
        # Create metadata file
        metadata_file_name = f"metadata/{file_name}_metadata.json"
        metadata_blob = results_bucket_obj.blob(metadata_file_name)
        metadata_blob.upload_from_string(json.dumps(analytics_metadata, indent=2))
        
        logger.info(f"✅ Video processing initiated for: {file_name}")
        logger.info(f"Metadata stored at: gs://{results_bucket}/{metadata_file_name}")
        
        # Create processing queue entry for advanced analytics
        queue_entry = {
            "video_uri": video_uri,
            "file_name": file_name,
            "bucket_name": bucket_name,
            "queued_at": cloud_event.time if hasattr(cloud_event, 'time') else None,
            "status": "queued_for_analysis"
        }
        
        queue_file_name = f"queue/{file_name}_queue.json"
        queue_blob = results_bucket_obj.blob(queue_file_name)
        queue_blob.upload_from_string(json.dumps(queue_entry, indent=2))
        
        logger.info(f"Video queued for advanced analytics: gs://{results_bucket}/{queue_file_name}")
        
        return {
            "status": "success", 
            "video_uri": video_uri,
            "metadata_file": f"gs://{results_bucket}/{metadata_file_name}",
            "queue_file": f"gs://{results_bucket}/{queue_file_name}"
        }
        
    except Exception as e:
        logger.error(f"Error processing video upload: {str(e)}")
        
        # Store error metadata if possible
        try:
            error_metadata = {
                "video_uri": f"gs://{bucket_name}/{file_name}" if 'bucket_name' in locals() and 'file_name' in locals() else "unknown",
                "error_message": str(e),
                "error_type": type(e).__name__,
                "processing_status": "failed",
                "timestamp": cloud_event.time if hasattr(cloud_event, 'time') else None
            }
            
            if 'results_bucket' in locals() and 'file_name' in locals():
                storage_client = storage.Client()
                results_bucket_obj = storage_client.bucket(results_bucket)
                error_blob = results_bucket_obj.blob(f"errors/{file_name}_error.json")
                error_blob.upload_from_string(json.dumps(error_metadata, indent=2))
                
        except Exception as error_log_exception:
            logger.error(f"Failed to log error metadata: {str(error_log_exception)}")
        
        return {
            "status": "error",
            "error": str(e),
            "error_type": type(e).__name__
        }