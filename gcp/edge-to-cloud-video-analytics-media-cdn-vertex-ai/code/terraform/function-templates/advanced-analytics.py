import os
import json
import asyncio
import logging
from google.cloud import videointelligence
from google.cloud import storage
from google.cloud import aiplatform
from typing import Dict, Any, List

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def analyze_video_content(cloud_event):
    """
    Advanced video analysis using Vertex AI Video Intelligence.
    
    Args:
        cloud_event: CloudEvent containing the storage event details
        
    Returns:
        dict: Status and operation details for the video analysis
    """
    
    try:
        # Parse event data
        file_name = cloud_event.data["name"]
        bucket_name = cloud_event.data["bucket"]
        
        logger.info(f"Starting advanced analytics for: {file_name} from bucket: {bucket_name}")
        
        # Skip non-video files
        video_extensions = ('.mp4', '.mov', '.avi', '.mkv', '.webm', '.flv', '.wmv')
        if not file_name.lower().endswith(video_extensions):
            logger.info(f"Skipping non-video file: {file_name}")
            return {"status": "skipped", "reason": "not a video file"}
        
        # Get environment variables
        project_id = os.environ.get('PROJECT_ID', '${project_id}')
        region = os.environ.get('REGION', '${region}')
        results_bucket = os.environ.get('RESULTS_BUCKET', '${results_bucket}')
        
        video_uri = f"gs://{bucket_name}/{file_name}"
        logger.info(f"Analyzing video: {video_uri}")
        
        # Initialize Video Intelligence client
        video_client = videointelligence.VideoIntelligenceServiceClient()
        
        # Configure analysis features
        features = [
            videointelligence.Feature.OBJECT_TRACKING,
            videointelligence.Feature.LABEL_DETECTION,
            videointelligence.Feature.SHOT_CHANGE_DETECTION,
            videointelligence.Feature.TEXT_DETECTION
        ]
        
        # Configure analysis settings
        config = videointelligence.VideoContext(
            object_tracking_config=videointelligence.ObjectTrackingConfig(
                model="builtin/latest"
            ),
            label_detection_config=videointelligence.LabelDetectionConfig(
                model="builtin/latest",
                label_detection_mode=videointelligence.LabelDetectionMode.SHOT_AND_FRAME_MODE
            ),
            shot_change_detection_config=videointelligence.ShotChangeDetectionConfig(
                model="builtin/latest"
            ),
            text_detection_config=videointelligence.TextDetectionConfig(
                model="builtin/latest"
            )
        )
        
        # Set output URI for results
        output_uri = f"gs://{results_bucket}/analysis/{file_name}_analysis.json"
        
        # Start video analysis operation
        operation = video_client.annotate_video(
            request={
                "features": features,
                "input_uri": video_uri,
                "video_context": config,
                "output_uri": output_uri
            }
        )
        
        logger.info(f"Analysis operation started: {operation.operation.name}")
        
        # Store analysis operation metadata
        storage_client = storage.Client()
        results_bucket_obj = storage_client.bucket(results_bucket)
        
        analysis_metadata = {
            "video_uri": video_uri,
            "file_name": file_name,
            "operation_name": operation.operation.name,
            "operation_id": operation.operation.name.split('/')[-1],
            "features_analyzed": [feature.name for feature in features],
            "status": "processing",
            "timestamp": cloud_event.time if hasattr(cloud_event, 'time') else None,
            "output_uri": output_uri,
            "project_id": project_id,
            "region": region,
            "analysis_config": {
                "object_tracking_model": "builtin/latest",
                "label_detection_model": "builtin/latest",
                "label_detection_mode": "SHOT_AND_FRAME_MODE",
                "shot_detection_model": "builtin/latest",
                "text_detection_model": "builtin/latest"
            }
        }
        
        metadata_file = f"operations/{file_name}_operation.json"
        metadata_blob = results_bucket_obj.blob(metadata_file)
        metadata_blob.upload_from_string(json.dumps(analysis_metadata, indent=2))
        
        logger.info(f"Operation metadata stored: gs://{results_bucket}/{metadata_file}")
        
        # Create progress tracking file
        progress_data = {
            "video_uri": video_uri,
            "file_name": file_name,
            "operation_name": operation.operation.name,
            "current_status": "analysis_in_progress",
            "progress_percentage": 0,
            "estimated_completion": None,
            "last_updated": cloud_event.time if hasattr(cloud_event, 'time') else None
        }
        
        progress_file = f"progress/{file_name}_progress.json"
        progress_blob = results_bucket_obj.blob(progress_file)
        progress_blob.upload_from_string(json.dumps(progress_data, indent=2))
        
        logger.info(f"✅ Advanced video analytics initiated for: {file_name}")
        logger.info(f"Operation: {operation.operation.name}")
        logger.info(f"Expected output: {output_uri}")
        
        return {
            "status": "analysis_started",
            "operation_name": operation.operation.name,
            "operation_id": operation.operation.name.split('/')[-1],
            "video_uri": video_uri,
            "output_uri": output_uri,
            "metadata_file": f"gs://{results_bucket}/{metadata_file}",
            "progress_file": f"gs://{results_bucket}/{progress_file}",
            "features": [feature.name for feature in features]
        }
        
    except Exception as e:
        logger.error(f"Error in advanced video analytics: {str(e)}")
        
        # Store error information
        try:
            error_data = {
                "video_uri": f"gs://{bucket_name}/{file_name}" if 'bucket_name' in locals() and 'file_name' in locals() else "unknown",
                "error_message": str(e),
                "error_type": type(e).__name__,
                "analysis_status": "failed",
                "timestamp": cloud_event.time if hasattr(cloud_event, 'time') else None,
                "function": "advanced_analytics"
            }
            
            if 'results_bucket' in locals() and 'file_name' in locals():
                storage_client = storage.Client()
                results_bucket_obj = storage_client.bucket(results_bucket)
                error_blob = results_bucket_obj.blob(f"errors/{file_name}_analytics_error.json")
                error_blob.upload_from_string(json.dumps(error_data, indent=2))
                logger.info(f"Error logged to: gs://{results_bucket}/errors/{file_name}_analytics_error.json")
                
        except Exception as error_log_exception:
            logger.error(f"Failed to log error: {str(error_log_exception)}")
        
        return {
            "status": "error",
            "error": str(e),
            "error_type": type(e).__name__,
            "function": "advanced_analytics"
        }


def get_operation_status(operation_name: str, project_id: str) -> Dict[str, Any]:
    """
    Check the status of a Video Intelligence operation.
    
    Args:
        operation_name: The name of the operation to check
        project_id: Google Cloud project ID
        
    Returns:
        dict: Operation status and details
    """
    try:
        video_client = videointelligence.VideoIntelligenceServiceClient()
        operation = video_client.get_operation(name=operation_name)
        
        return {
            "name": operation.name,
            "done": operation.done,
            "error": str(operation.error) if operation.error else None,
            "metadata": operation.metadata
        }
        
    except Exception as e:
        logger.error(f"Error checking operation status: {str(e)}")
        return {
            "error": str(e),
            "status": "check_failed"
        }


def extract_video_insights(analysis_results: Dict[str, Any]) -> Dict[str, Any]:
    """
    Extract key insights from Video Intelligence analysis results.
    
    Args:
        analysis_results: Raw analysis results from Video Intelligence API
        
    Returns:
        dict: Structured insights and summary
    """
    insights = {
        "objects_detected": [],
        "labels_detected": [],
        "text_detected": [],
        "shots_detected": 0,
        "total_duration": 0,
        "confidence_scores": {
            "object_detection": [],
            "label_detection": [],
            "text_detection": []
        }
    }
    
    try:
        # Process object tracking results
        if 'object_annotations' in analysis_results:
            for obj in analysis_results['object_annotations']:
                entity = obj.get('entity', {})
                confidence = obj.get('confidence', 0)
                
                object_info = {
                    "entity": entity.get('description', 'Unknown'),
                    "entity_id": entity.get('entity_id', ''),
                    "confidence": confidence,
                    "track_count": len(obj.get('frames', [])),
                    "time_segments": []
                }
                
                # Extract time segments for this object
                for frame in obj.get('frames', []):
                    time_offset = frame.get('time_offset', {})
                    object_info["time_segments"].append({
                        "start_time": time_offset.get('seconds', 0),
                        "bounding_box": frame.get('normalized_bounding_box', {})
                    })
                
                insights['objects_detected'].append(object_info)
                insights['confidence_scores']['object_detection'].append(confidence)
        
        # Process label detection results
        if 'label_annotations' in analysis_results:
            for label in analysis_results['label_annotations']:
                entity = label.get('entity', {})
                category_entities = label.get('category_entities', [])
                
                label_info = {
                    "description": entity.get('description', 'Unknown'),
                    "entity_id": entity.get('entity_id', ''),
                    "language_code": entity.get('language_code', 'en'),
                    "categories": [cat.get('description', '') for cat in category_entities],
                    "segments": []
                }
                
                # Extract segments for this label
                for segment in label.get('segments', []):
                    confidence = segment.get('confidence', 0)
                    segment_info = {
                        "confidence": confidence,
                        "start_time": segment.get('segment', {}).get('start_time_offset', {}).get('seconds', 0),
                        "end_time": segment.get('segment', {}).get('end_time_offset', {}).get('seconds', 0)
                    }
                    label_info["segments"].append(segment_info)
                    insights['confidence_scores']['label_detection'].append(confidence)
                
                insights['labels_detected'].append(label_info)
        
        # Process text detection results
        if 'text_annotations' in analysis_results:
            for text in analysis_results['text_annotations']:
                text_info = {
                    "text": text.get('text', ''),
                    "confidence": text.get('confidence', 0),
                    "segments": []
                }
                
                for segment in text.get('segments', []):
                    confidence = segment.get('confidence', 0)
                    segment_info = {
                        "confidence": confidence,
                        "start_time": segment.get('segment', {}).get('start_time_offset', {}).get('seconds', 0),
                        "end_time": segment.get('segment', {}).get('end_time_offset', {}).get('seconds', 0),
                        "frames": []
                    }
                    
                    for frame in segment.get('frames', []):
                        frame_info = {
                            "time_offset": frame.get('time_offset', {}).get('seconds', 0),
                            "rotated_bounding_box": frame.get('rotated_bounding_box', {})
                        }
                        segment_info["frames"].append(frame_info)
                    
                    text_info["segments"].append(segment_info)
                    insights['confidence_scores']['text_detection'].append(confidence)
                
                insights['text_detected'].append(text_info)
        
        # Process shot detection results
        if 'shot_annotations' in analysis_results:
            insights['shots_detected'] = len(analysis_results['shot_annotations'])
            
            # Calculate total video duration from last shot
            if analysis_results['shot_annotations']:
                last_shot = analysis_results['shot_annotations'][-1]
                end_time = last_shot.get('end_time_offset', {})
                insights['total_duration'] = end_time.get('seconds', 0)
        
        # Calculate average confidence scores
        for detection_type in insights['confidence_scores']:
            scores = insights['confidence_scores'][detection_type]
            if scores:
                insights['confidence_scores'][detection_type] = {
                    "average": sum(scores) / len(scores),
                    "min": min(scores),
                    "max": max(scores),
                    "count": len(scores)
                }
            else:
                insights['confidence_scores'][detection_type] = {
                    "average": 0,
                    "min": 0,
                    "max": 0,
                    "count": 0
                }
        
    except Exception as e:
        logger.error(f"Error extracting insights: {str(e)}")
        insights["extraction_error"] = str(e)
    
    return insights