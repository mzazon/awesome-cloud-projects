import json
import os
import logging
from google.cloud import storage
from google.cloud import videointelligence
from typing import Dict, Any, List, Optional
import re
from datetime import datetime, timezone

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def process_analytics_results(cloud_event):
    """
    Process completed video analytics results and generate insights.
    
    Args:
        cloud_event: CloudEvent containing the storage event details
        
    Returns:
        dict: Processing status and generated insights summary
    """
    
    try:
        # Parse event data
        file_name = cloud_event.data["name"]
        bucket_name = cloud_event.data["bucket"]
        
        logger.info(f"Processing analytics results: {file_name} from bucket: {bucket_name}")
        
        # Only process analysis result files
        if not file_name.endswith('_analysis.json'):
            logger.info(f"Skipping non-analysis file: {file_name}")
            return {"status": "skipped", "reason": "not an analysis result"}
        
        # Get environment variables
        project_id = os.environ.get('PROJECT_ID', '${project_id}')
        region = os.environ.get('REGION', '${region}')
        content_bucket = os.environ.get('CONTENT_BUCKET', '')
        
        # Extract original video filename from analysis filename
        original_video_name = file_name.replace('analysis/', '').replace('_analysis.json', '')
        
        logger.info(f"Processing results for original video: {original_video_name}")
        
        # Download and parse analysis results
        storage_client = storage.Client()
        bucket = storage_client.bucket(bucket_name)
        blob = bucket.blob(file_name)
        
        try:
            analysis_data = json.loads(blob.download_as_text())
            logger.info(f"Successfully loaded analysis data for {original_video_name}")
        except Exception as e:
            logger.error(f"Failed to parse analysis results: {str(e)}")
            return {"status": "error", "error": f"Failed to parse analysis results: {str(e)}"}
        
        # Extract comprehensive insights
        insights = extract_comprehensive_insights(analysis_data, original_video_name, cloud_event)
        
        # Generate summary report
        summary = generate_summary_report(insights)
        
        # Store processed insights
        insights_file = f"insights/{original_video_name}_insights.json"
        insights_blob = bucket.blob(insights_file)
        insights_blob.upload_from_string(json.dumps(insights, indent=2))
        
        # Store summary report
        summary_file = f"summaries/{original_video_name}_summary.json"
        summary_blob = bucket.blob(summary_file)
        summary_blob.upload_from_string(json.dumps(summary, indent=2))
        
        # Generate searchable metadata
        metadata = generate_searchable_metadata(insights, summary, original_video_name)
        metadata_file = f"searchable/{original_video_name}_metadata.json"
        metadata_blob = bucket.blob(metadata_file)
        metadata_blob.upload_from_string(json.dumps(metadata, indent=2))
        
        # Create human-readable report
        readable_report = generate_human_readable_report(insights, summary, original_video_name)
        report_file = f"reports/{original_video_name}_report.txt"
        report_blob = bucket.blob(report_file)
        report_blob.upload_from_string(readable_report)
        
        # Log processing completion
        logger.info(f"✅ Processed analytics for: {original_video_name}")
        logger.info(f"   Objects detected: {summary['total_objects']}")
        logger.info(f"   Labels detected: {summary['total_labels']}")
        logger.info(f"   Text elements: {summary['total_text_elements']}")
        logger.info(f"   Shots detected: {summary['total_shots']}")
        logger.info(f"   Video duration: {summary['video_duration_seconds']} seconds")
        
        # Update processing status
        status_data = {
            "video_name": original_video_name,
            "processing_status": "completed",
            "completion_time": datetime.now(timezone.utc).isoformat(),
            "insights_file": f"gs://{bucket_name}/{insights_file}",
            "summary_file": f"gs://{bucket_name}/{summary_file}",
            "metadata_file": f"gs://{bucket_name}/{metadata_file}",
            "report_file": f"gs://{bucket_name}/{report_file}",
            "summary": summary
        }
        
        status_file = f"status/{original_video_name}_status.json"
        status_blob = bucket.blob(status_file)
        status_blob.upload_from_string(json.dumps(status_data, indent=2))
        
        return {
            "status": "success",
            "video_name": original_video_name,
            "insights": summary,
            "files_created": {
                "insights": f"gs://{bucket_name}/{insights_file}",
                "summary": f"gs://{bucket_name}/{summary_file}",
                "metadata": f"gs://{bucket_name}/{metadata_file}",
                "report": f"gs://{bucket_name}/{report_file}",
                "status": f"gs://{bucket_name}/{status_file}"
            }
        }
        
    except Exception as e:
        logger.error(f"Error processing analytics results: {str(e)}")
        
        # Store error information
        try:
            error_data = {
                "file_name": file_name if 'file_name' in locals() else "unknown",
                "original_video_name": original_video_name if 'original_video_name' in locals() else "unknown",
                "error_message": str(e),
                "error_type": type(e).__name__,
                "processing_status": "failed",
                "timestamp": cloud_event.time if hasattr(cloud_event, 'time') else None,
                "function": "results_processor"
            }
            
            if 'bucket' in locals() and 'original_video_name' in locals():
                error_blob = bucket.blob(f"errors/{original_video_name}_processing_error.json")
                error_blob.upload_from_string(json.dumps(error_data, indent=2))
                
        except Exception as error_log_exception:
            logger.error(f"Failed to log error: {str(error_log_exception)}")
        
        return {
            "status": "error",
            "error": str(e),
            "error_type": type(e).__name__,
            "function": "results_processor"
        }


def extract_comprehensive_insights(analysis_data: Dict[str, Any], video_name: str, cloud_event) -> Dict[str, Any]:
    """
    Extract comprehensive insights from video analysis data.
    
    Args:
        analysis_data: Raw analysis results from Video Intelligence API
        video_name: Name of the original video file
        cloud_event: Original cloud event data
        
    Returns:
        dict: Comprehensive insights with detailed analysis
    """
    
    insights = {
        "video_name": video_name,
        "processing_timestamp": cloud_event.time if hasattr(cloud_event, 'time') else datetime.now(timezone.utc).isoformat(),
        "objects_detected": [],
        "labels_detected": [],
        "text_detected": [],
        "shots_detected": [],
        "video_duration_seconds": 0,
        "confidence_statistics": {},
        "content_categories": [],
        "timeline_analysis": {},
        "quality_metrics": {}
    }
    
    try:
        # Process object tracking results
        if 'object_annotations' in analysis_data:
            for obj in analysis_data['object_annotations']:
                entity = obj.get('entity', {})
                confidence = obj.get('confidence', 0)
                frames = obj.get('frames', [])
                
                object_info = {
                    "entity": entity.get('description', 'Unknown'),
                    "entity_id": entity.get('entity_id', ''),
                    "confidence": confidence,
                    "track_count": len(frames),
                    "duration_seconds": 0,
                    "first_appearance": 0,
                    "last_appearance": 0,
                    "tracking_quality": "high" if confidence > 0.8 else "medium" if confidence > 0.5 else "low",
                    "time_segments": []
                }
                
                # Analyze temporal presence
                if frames:
                    time_offsets = []
                    for frame in frames:
                        time_offset = frame.get('time_offset', {})
                        seconds = time_offset.get('seconds', 0) + time_offset.get('nanos', 0) / 1e9
                        time_offsets.append(seconds)
                        
                        object_info["time_segments"].append({
                            "time": seconds,
                            "bounding_box": frame.get('normalized_bounding_box', {}),
                            "confidence": frame.get('confidence', confidence)
                        })
                    
                    if time_offsets:
                        object_info["first_appearance"] = min(time_offsets)
                        object_info["last_appearance"] = max(time_offsets)
                        object_info["duration_seconds"] = max(time_offsets) - min(time_offsets)
                
                insights['objects_detected'].append(object_info)
        
        # Process label detection results
        if 'label_annotations' in analysis_data:
            for label in analysis_data['label_annotations']:
                entity = label.get('entity', {})
                category_entities = label.get('category_entities', [])
                segments = label.get('segments', [])
                
                label_info = {
                    "description": entity.get('description', 'Unknown'),
                    "entity_id": entity.get('entity_id', ''),
                    "language_code": entity.get('language_code', 'en'),
                    "categories": [cat.get('description', '') for cat in category_entities],
                    "confidence_average": 0,
                    "total_duration": 0,
                    "occurrence_count": len(segments),
                    "segments": []
                }
                
                # Analyze label segments
                confidences = []
                total_duration = 0
                
                for segment in segments:
                    confidence = segment.get('confidence', 0)
                    confidences.append(confidence)
                    
                    segment_data = segment.get('segment', {})
                    start_time = segment_data.get('start_time_offset', {})
                    end_time = segment_data.get('end_time_offset', {})
                    
                    start_seconds = start_time.get('seconds', 0) + start_time.get('nanos', 0) / 1e9
                    end_seconds = end_time.get('seconds', 0) + end_time.get('nanos', 0) / 1e9
                    
                    duration = end_seconds - start_seconds
                    total_duration += duration
                    
                    label_info["segments"].append({
                        "confidence": confidence,
                        "start_time": start_seconds,
                        "end_time": end_seconds,
                        "duration": duration
                    })
                
                if confidences:
                    label_info["confidence_average"] = sum(confidences) / len(confidences)
                label_info["total_duration"] = total_duration
                
                insights['labels_detected'].append(label_info)
                
                # Add to content categories
                for category in label_info["categories"]:
                    if category and category not in insights['content_categories']:
                        insights['content_categories'].append(category)
        
        # Process text detection results
        if 'text_annotations' in analysis_data:
            for text in analysis_data['text_annotations']:
                text_content = text.get('text', '')
                segments = text.get('segments', [])
                
                text_info = {
                    "text": text_content,
                    "text_length": len(text_content),
                    "confidence_average": 0,
                    "total_duration": 0,
                    "occurrence_count": len(segments),
                    "language_detected": detect_text_language(text_content),
                    "text_type": classify_text_type(text_content),
                    "segments": []
                }
                
                # Analyze text segments
                confidences = []
                total_duration = 0
                
                for segment in segments:
                    confidence = segment.get('confidence', 0)
                    confidences.append(confidence)
                    
                    segment_data = segment.get('segment', {})
                    start_time = segment_data.get('start_time_offset', {})
                    end_time = segment_data.get('end_time_offset', {})
                    
                    start_seconds = start_time.get('seconds', 0) + start_time.get('nanos', 0) / 1e9
                    end_seconds = end_time.get('seconds', 0) + end_time.get('nanos', 0) / 1e9
                    
                    duration = end_seconds - start_seconds
                    total_duration += duration
                    
                    text_info["segments"].append({
                        "confidence": confidence,
                        "start_time": start_seconds,
                        "end_time": end_seconds,
                        "duration": duration,
                        "frames": len(segment.get('frames', []))
                    })
                
                if confidences:
                    text_info["confidence_average"] = sum(confidences) / len(confidences)
                text_info["total_duration"] = total_duration
                
                insights['text_detected'].append(text_info)
        
        # Process shot detection results
        if 'shot_annotations' in analysis_data:
            shots = analysis_data['shot_annotations']
            insights['shots_detected'] = []
            
            for i, shot in enumerate(shots):
                start_time = shot.get('start_time_offset', {})
                end_time = shot.get('end_time_offset', {})
                
                start_seconds = start_time.get('seconds', 0) + start_time.get('nanos', 0) / 1e9
                end_seconds = end_time.get('seconds', 0) + end_time.get('nanos', 0) / 1e9
                
                shot_info = {
                    "shot_number": i + 1,
                    "start_time": start_seconds,
                    "end_time": end_seconds,
                    "duration": end_seconds - start_seconds
                }
                
                insights['shots_detected'].append(shot_info)
            
            # Calculate total video duration
            if shots:
                last_shot = shots[-1]
                end_time = last_shot.get('end_time_offset', {})
                insights['video_duration_seconds'] = end_time.get('seconds', 0) + end_time.get('nanos', 0) / 1e9
        
        # Calculate confidence statistics
        insights['confidence_statistics'] = calculate_confidence_statistics(insights)
        
        # Generate timeline analysis
        insights['timeline_analysis'] = generate_timeline_analysis(insights)
        
        # Calculate quality metrics
        insights['quality_metrics'] = calculate_quality_metrics(insights)
        
    except Exception as e:
        logger.error(f"Error extracting insights: {str(e)}")
        insights["extraction_error"] = str(e)
    
    return insights


def generate_summary_report(insights: Dict[str, Any]) -> Dict[str, Any]:
    """
    Generate a summary report from comprehensive insights.
    
    Args:
        insights: Comprehensive insights data
        
    Returns:
        dict: Summary report with key metrics
    """
    
    summary = {
        "video_name": insights.get("video_name", "unknown"),
        "processing_timestamp": insights.get("processing_timestamp"),
        "video_duration_seconds": insights.get("video_duration_seconds", 0),
        "video_duration_formatted": format_duration(insights.get("video_duration_seconds", 0)),
        "total_objects": len(insights.get("objects_detected", [])),
        "total_labels": len(insights.get("labels_detected", [])),
        "total_text_elements": len(insights.get("text_detected", [])),
        "total_shots": len(insights.get("shots_detected", [])),
        "content_categories": insights.get("content_categories", []),
        "top_objects": [],
        "top_labels": [],
        "detected_text_summary": [],
        "shot_analysis": {},
        "quality_score": 0,
        "processing_quality": "unknown"
    }
    
    try:
        # Top objects by confidence and duration
        objects = insights.get("objects_detected", [])
        if objects:
            sorted_objects = sorted(objects, key=lambda x: (x.get('confidence', 0) * x.get('duration_seconds', 0)), reverse=True)
            summary["top_objects"] = [
                {
                    "entity": obj.get("entity", "unknown"),
                    "confidence": obj.get("confidence", 0),
                    "duration_seconds": obj.get("duration_seconds", 0),
                    "tracking_quality": obj.get("tracking_quality", "unknown")
                }
                for obj in sorted_objects[:10]
            ]
        
        # Top labels by confidence and duration
        labels = insights.get("labels_detected", [])
        if labels:
            sorted_labels = sorted(labels, key=lambda x: (x.get('confidence_average', 0) * x.get('total_duration', 0)), reverse=True)
            summary["top_labels"] = [
                {
                    "description": label.get("description", "unknown"),
                    "confidence_average": label.get("confidence_average", 0),
                    "total_duration": label.get("total_duration", 0),
                    "occurrence_count": label.get("occurrence_count", 0),
                    "categories": label.get("categories", [])
                }
                for label in sorted_labels[:10]
            ]
        
        # Text summary
        text_elements = insights.get("text_detected", [])
        if text_elements:
            summary["detected_text_summary"] = [
                {
                    "text": text.get("text", "")[:100] + "..." if len(text.get("text", "")) > 100 else text.get("text", ""),
                    "text_type": text.get("text_type", "unknown"),
                    "confidence_average": text.get("confidence_average", 0),
                    "total_duration": text.get("total_duration", 0)
                }
                for text in sorted(text_elements, key=lambda x: x.get('confidence_average', 0), reverse=True)[:5]
            ]
        
        # Shot analysis
        shots = insights.get("shots_detected", [])
        if shots:
            shot_durations = [shot.get("duration", 0) for shot in shots]
            summary["shot_analysis"] = {
                "total_shots": len(shots),
                "average_shot_duration": sum(shot_durations) / len(shot_durations) if shot_durations else 0,
                "shortest_shot": min(shot_durations) if shot_durations else 0,
                "longest_shot": max(shot_durations) if shot_durations else 0,
                "shot_variety": "high" if len(shots) > 20 else "medium" if len(shots) > 10 else "low"
            }
        
        # Overall quality score (0-100)
        quality_metrics = insights.get("quality_metrics", {})
        summary["quality_score"] = quality_metrics.get("overall_score", 0)
        summary["processing_quality"] = quality_metrics.get("processing_quality", "unknown")
        
    except Exception as e:
        logger.error(f"Error generating summary: {str(e)}")
        summary["summary_error"] = str(e)
    
    return summary


def generate_searchable_metadata(insights: Dict[str, Any], summary: Dict[str, Any], video_name: str) -> Dict[str, Any]:
    """
    Generate searchable metadata for video content discovery.
    
    Args:
        insights: Comprehensive insights data
        summary: Summary report data
        video_name: Original video filename
        
    Returns:
        dict: Searchable metadata structure
    """
    
    metadata = {
        "video_name": video_name,
        "file_extension": video_name.split('.')[-1].lower() if '.' in video_name else '',
        "processing_date": datetime.now(timezone.utc).isoformat(),
        "duration_seconds": summary.get("video_duration_seconds", 0),
        "duration_category": categorize_duration(summary.get("video_duration_seconds", 0)),
        "content_type": determine_content_type(insights, summary),
        "keywords": extract_keywords(insights, summary),
        "entities": extract_entities(insights),
        "confidence_rating": calculate_confidence_rating(insights),
        "quality_rating": summary.get("quality_score", 0),
        "searchable_text": generate_searchable_text(insights),
        "tags": generate_tags(insights, summary),
        "categories": summary.get("content_categories", []),
        "statistics": {
            "object_count": summary.get("total_objects", 0),
            "label_count": summary.get("total_labels", 0),
            "text_element_count": summary.get("total_text_elements", 0),
            "shot_count": summary.get("total_shots", 0)
        }
    }
    
    return metadata


def generate_human_readable_report(insights: Dict[str, Any], summary: Dict[str, Any], video_name: str) -> str:
    """
    Generate a human-readable text report of the video analysis.
    
    Args:
        insights: Comprehensive insights data
        summary: Summary report data
        video_name: Original video filename
        
    Returns:
        str: Human-readable report text
    """
    
    report_lines = [
        f"Video Analysis Report",
        f"=" * 50,
        f"",
        f"Video: {video_name}",
        f"Duration: {summary.get('video_duration_formatted', 'unknown')}",
        f"Processed: {summary.get('processing_timestamp', 'unknown')}",
        f"Quality Score: {summary.get('quality_score', 0)}/100",
        f"",
        f"SUMMARY",
        f"-" * 20,
        f"Objects detected: {summary.get('total_objects', 0)}",
        f"Labels identified: {summary.get('total_labels', 0)}",
        f"Text elements found: {summary.get('total_text_elements', 0)}",
        f"Scene changes: {summary.get('total_shots', 0)}",
        f"",
    ]
    
    # Top objects
    if summary.get('top_objects'):
        report_lines.extend([
            f"TOP DETECTED OBJECTS",
            f"-" * 20
        ])
        for i, obj in enumerate(summary['top_objects'][:5], 1):
            duration = obj.get('duration_seconds', 0)
            confidence = obj.get('confidence', 0)
            report_lines.append(f"{i}. {obj.get('entity', 'unknown')} (confidence: {confidence:.2f}, duration: {duration:.1f}s)")
        report_lines.append("")
    
    # Top labels
    if summary.get('top_labels'):
        report_lines.extend([
            f"TOP CONTENT LABELS",
            f"-" * 20
        ])
        for i, label in enumerate(summary['top_labels'][:5], 1):
            confidence = label.get('confidence_average', 0)
            duration = label.get('total_duration', 0)
            report_lines.append(f"{i}. {label.get('description', 'unknown')} (confidence: {confidence:.2f}, duration: {duration:.1f}s)")
        report_lines.append("")
    
    # Detected text
    if summary.get('detected_text_summary'):
        report_lines.extend([
            f"DETECTED TEXT",
            f"-" * 20
        ])
        for i, text in enumerate(summary['detected_text_summary'][:3], 1):
            text_content = text.get('text', 'unknown')
            confidence = text.get('confidence_average', 0)
            report_lines.append(f"{i}. \"{text_content}\" (confidence: {confidence:.2f})")
        report_lines.append("")
    
    # Shot analysis
    shot_analysis = summary.get('shot_analysis', {})
    if shot_analysis:
        report_lines.extend([
            f"SHOT ANALYSIS",
            f"-" * 20,
            f"Total shots: {shot_analysis.get('total_shots', 0)}",
            f"Average shot duration: {shot_analysis.get('average_shot_duration', 0):.1f}s",
            f"Shot variety: {shot_analysis.get('shot_variety', 'unknown')}",
            f""
        ])
    
    # Content categories
    if summary.get('content_categories'):
        report_lines.extend([
            f"CONTENT CATEGORIES",
            f"-" * 20,
            f"{', '.join(summary['content_categories'][:10])}",
            f""
        ])
    
    return "\n".join(report_lines)


# Helper functions
def detect_text_language(text: str) -> str:
    """Simple language detection based on character patterns."""
    if not text:
        return "unknown"
    
    # Simple heuristic - could be enhanced with proper language detection
    if any(ord(char) > 127 for char in text):
        return "non-english"
    return "english"


def classify_text_type(text: str) -> str:
    """Classify the type of detected text."""
    if not text:
        return "unknown"
    
    text_lower = text.lower()
    
    if any(word in text_lower for word in ['news', 'breaking', 'live']):
        return "news"
    elif any(word in text_lower for word in ['advertisement', 'ad', 'buy', 'sale']):
        return "advertisement"
    elif text.isupper() and len(text) > 5:
        return "title"
    elif any(char.isdigit() for char in text):
        return "informational"
    else:
        return "general"


def format_duration(seconds: float) -> str:
    """Format duration in seconds to human-readable format."""
    if seconds < 60:
        return f"{seconds:.1f} seconds"
    elif seconds < 3600:
        minutes = seconds / 60
        return f"{minutes:.1f} minutes"
    else:
        hours = seconds / 3600
        return f"{hours:.1f} hours"


def categorize_duration(seconds: float) -> str:
    """Categorize video duration."""
    if seconds < 30:
        return "very_short"
    elif seconds < 300:  # 5 minutes
        return "short"
    elif seconds < 1800:  # 30 minutes
        return "medium"
    elif seconds < 3600:  # 1 hour
        return "long"
    else:
        return "very_long"


def determine_content_type(insights: Dict[str, Any], summary: Dict[str, Any]) -> str:
    """Determine the type of video content based on analysis."""
    categories = summary.get('content_categories', [])
    labels = [label.get('description', '').lower() for label in summary.get('top_labels', [])]
    
    # Simple content type classification
    if any(cat.lower() in ['news', 'journalism'] for cat in categories):
        return "news"
    elif any(cat.lower() in ['entertainment', 'music', 'movie'] for cat in categories):
        return "entertainment"
    elif any(cat.lower() in ['education', 'tutorial', 'learning'] for cat in categories):
        return "educational"
    elif any(cat.lower() in ['sports', 'game', 'competition'] for cat in categories):
        return "sports"
    else:
        return "general"


def extract_keywords(insights: Dict[str, Any], summary: Dict[str, Any]) -> List[str]:
    """Extract keywords for search indexing."""
    keywords = set()
    
    # Add top object entities
    for obj in summary.get('top_objects', []):
        entity = obj.get('entity', '').lower()
        if entity and len(entity) > 2:
            keywords.add(entity)
    
    # Add top label descriptions
    for label in summary.get('top_labels', []):
        description = label.get('description', '').lower()
        if description and len(description) > 2:
            keywords.add(description)
    
    # Add content categories
    for category in summary.get('content_categories', []):
        if category and len(category) > 2:
            keywords.add(category.lower())
    
    return list(keywords)[:20]  # Limit to top 20 keywords


def extract_entities(insights: Dict[str, Any]) -> List[str]:
    """Extract named entities from the video analysis."""
    entities = set()
    
    # Extract object entities
    for obj in insights.get('objects_detected', []):
        entity = obj.get('entity', '')
        if entity:
            entities.add(entity)
    
    # Extract label entities
    for label in insights.get('labels_detected', []):
        description = label.get('description', '')
        if description:
            entities.add(description)
    
    return list(entities)


def calculate_confidence_rating(insights: Dict[str, Any]) -> str:
    """Calculate overall confidence rating for the analysis."""
    confidence_stats = insights.get('confidence_statistics', {})
    overall_confidence = confidence_stats.get('overall_average', 0)
    
    if overall_confidence >= 0.8:
        return "high"
    elif overall_confidence >= 0.6:
        return "medium"
    elif overall_confidence >= 0.4:
        return "low"
    else:
        return "very_low"


def generate_searchable_text(insights: Dict[str, Any]) -> str:
    """Generate searchable text content from all detected text."""
    text_elements = insights.get('text_detected', [])
    return " ".join([text.get('text', '') for text in text_elements])


def generate_tags(insights: Dict[str, Any], summary: Dict[str, Any]) -> List[str]:
    """Generate tags for categorization and search."""
    tags = set()
    
    # Duration-based tags
    duration = summary.get('video_duration_seconds', 0)
    tags.add(categorize_duration(duration))
    
    # Content type tags
    content_type = determine_content_type(insights, summary)
    tags.add(content_type)
    
    # Quality tags
    quality_score = summary.get('quality_score', 0)
    if quality_score >= 80:
        tags.add('high_quality')
    elif quality_score >= 60:
        tags.add('medium_quality')
    else:
        tags.add('low_quality')
    
    # Feature-based tags
    if summary.get('total_objects', 0) > 10:
        tags.add('object_rich')
    if summary.get('total_text_elements', 0) > 5:
        tags.add('text_heavy')
    if summary.get('total_shots', 0) > 20:
        tags.add('fast_paced')
    
    return list(tags)


def calculate_confidence_statistics(insights: Dict[str, Any]) -> Dict[str, Any]:
    """Calculate confidence statistics across all analysis types."""
    stats = {
        'object_confidence': {'values': [], 'average': 0, 'min': 0, 'max': 0},
        'label_confidence': {'values': [], 'average': 0, 'min': 0, 'max': 0},
        'text_confidence': {'values': [], 'average': 0, 'min': 0, 'max': 0},
        'overall_average': 0
    }
    
    # Object confidence
    object_confidences = [obj.get('confidence', 0) for obj in insights.get('objects_detected', [])]
    if object_confidences:
        stats['object_confidence'] = {
            'values': object_confidences,
            'average': sum(object_confidences) / len(object_confidences),
            'min': min(object_confidences),
            'max': max(object_confidences)
        }
    
    # Label confidence
    label_confidences = [label.get('confidence_average', 0) for label in insights.get('labels_detected', [])]
    if label_confidences:
        stats['label_confidence'] = {
            'values': label_confidences,
            'average': sum(label_confidences) / len(label_confidences),
            'min': min(label_confidences),
            'max': max(label_confidences)
        }
    
    # Text confidence
    text_confidences = [text.get('confidence_average', 0) for text in insights.get('text_detected', [])]
    if text_confidences:
        stats['text_confidence'] = {
            'values': text_confidences,
            'average': sum(text_confidences) / len(text_confidences),
            'min': min(text_confidences),
            'max': max(text_confidences)
        }
    
    # Overall average
    all_averages = [
        stats['object_confidence']['average'],
        stats['label_confidence']['average'],
        stats['text_confidence']['average']
    ]
    non_zero_averages = [avg for avg in all_averages if avg > 0]
    stats['overall_average'] = sum(non_zero_averages) / len(non_zero_averages) if non_zero_averages else 0
    
    return stats


def generate_timeline_analysis(insights: Dict[str, Any]) -> Dict[str, Any]:
    """Generate timeline-based analysis of video content."""
    timeline = {
        'total_duration': insights.get('video_duration_seconds', 0),
        'temporal_segments': [],
        'content_density': {},
        'activity_peaks': []
    }
    
    # This is a simplified timeline analysis
    # In a full implementation, you would analyze temporal patterns more thoroughly
    
    duration = timeline['total_duration']
    if duration > 0:
        # Simple content density calculation
        objects_per_second = len(insights.get('objects_detected', [])) / duration
        labels_per_second = len(insights.get('labels_detected', [])) / duration
        text_per_second = len(insights.get('text_detected', [])) / duration
        
        timeline['content_density'] = {
            'objects_per_second': objects_per_second,
            'labels_per_second': labels_per_second,
            'text_per_second': text_per_second,
            'overall_density': (objects_per_second + labels_per_second + text_per_second) / 3
        }
    
    return timeline


def calculate_quality_metrics(insights: Dict[str, Any]) -> Dict[str, Any]:
    """Calculate quality metrics for the video analysis."""
    metrics = {
        'overall_score': 0,
        'processing_quality': 'unknown',
        'detection_quality': {},
        'completeness_score': 0
    }
    
    # Calculate detection quality scores
    confidence_stats = insights.get('confidence_statistics', {})
    
    object_score = min(100, confidence_stats.get('object_confidence', {}).get('average', 0) * 100)
    label_score = min(100, confidence_stats.get('label_confidence', {}).get('average', 0) * 100)
    text_score = min(100, confidence_stats.get('text_confidence', {}).get('average', 0) * 100)
    
    metrics['detection_quality'] = {
        'object_detection': object_score,
        'label_detection': label_score,
        'text_detection': text_score
    }
    
    # Calculate completeness score based on feature coverage
    features_detected = 0
    if insights.get('objects_detected'):
        features_detected += 1
    if insights.get('labels_detected'):
        features_detected += 1
    if insights.get('text_detected'):
        features_detected += 1
    if insights.get('shots_detected'):
        features_detected += 1
    
    metrics['completeness_score'] = (features_detected / 4) * 100
    
    # Overall score
    metrics['overall_score'] = (object_score + label_score + text_score + metrics['completeness_score']) / 4
    
    # Processing quality classification
    if metrics['overall_score'] >= 80:
        metrics['processing_quality'] = 'excellent'
    elif metrics['overall_score'] >= 60:
        metrics['processing_quality'] = 'good'
    elif metrics['overall_score'] >= 40:
        metrics['processing_quality'] = 'fair'
    else:
        metrics['processing_quality'] = 'poor'
    
    return metrics