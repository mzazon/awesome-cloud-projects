"""
Cloud Function for Quality Validation using Gemini
Analyzes generated videos for quality, safety, and social media optimization
"""

import json
import logging
import os
import tempfile
import base64
from datetime import datetime
from typing import Dict, Any, List, Tuple, Optional

from google import genai
from google.genai import types
from google.cloud import storage
from google.cloud import logging as cloud_logging
import functions_framework

# Import for video processing (optional, fallback to basic analysis)
try:
    import cv2
    VIDEO_PROCESSING_AVAILABLE = True
except ImportError:
    VIDEO_PROCESSING_AVAILABLE = False
    logging.warning("OpenCV not available, using basic video analysis")

# Initialize logging
cloud_logging.Client().setup_logging()
logging.basicConfig(level=logging.INFO)

# Configuration constants
GEMINI_MODEL = "${gemini_model_version}"
PROJECT_ID = "${project_id}"
BUCKET_NAME = "${bucket_name}"
REGION = "us-central1"

# Analysis configuration
MAX_FRAMES_TO_ANALYZE = 3
ANALYSIS_TIMEOUT_SECONDS = 240
MIN_QUALITY_SCORE = 6  # Minimum score out of 10 for approval
MAX_FILE_SIZE_MB = 100  # Maximum video file size to analyze

# Quality analysis prompt template
QUALITY_ANALYSIS_PROMPT = """
Analyze this video frame for social media content quality. Provide a detailed evaluation on:

1. Visual Appeal and Engagement Potential (1-10)
   - Color vibrancy and contrast
   - Composition and framing
   - Visual interest and engagement factors
   - Attention-grabbing elements

2. Technical Quality (1-10)
   - Resolution and clarity
   - Lighting quality
   - Motion smoothness (if detectable)
   - Overall production value

3. Brand Safety and Appropriateness (1-10)
   - Content appropriateness for general audiences
   - No harmful, offensive, or inappropriate content
   - Professional and brand-safe appearance
   - Compliance with platform guidelines

4. Social Media Optimization (1-10)
   - Format optimization for mobile viewing
   - Clarity at small screen sizes
   - Effectiveness for social media platforms
   - Thumbnail potential

5. Overall Recommendation
   - "approve" (scores 7+ across all categories)
   - "review" (scores 5-6 in any category, manual review needed)  
   - "reject" (scores below 5 in any category)

Provide your response in the following JSON format:
{
  "visual_appeal": {"score": X, "notes": "explanation"},
  "technical_quality": {"score": X, "notes": "explanation"},
  "brand_safety": {"score": X, "notes": "explanation"},
  "social_media_optimization": {"score": X, "notes": "explanation"},
  "overall_score": X.X,
  "recommendation": "approve/review/reject",
  "summary": "Brief overall assessment",
  "improvement_suggestions": ["suggestion1", "suggestion2"]
}
"""


def validate_request(request_data: Dict[str, Any]) -> Tuple[bool, str, Dict[str, Any]]:
    """
    Validate the incoming validation request.
    
    Args:
        request_data: The request JSON data
        
    Returns:
        Tuple of (is_valid, error_message, validated_params)
    """
    if not request_data or 'video_uri' not in request_data:
        return False, "Missing 'video_uri' in request body", {}
    
    video_uri = request_data.get('video_uri', '').strip()
    if not video_uri:
        return False, "Video URI cannot be empty", {}
    
    # Validate URI format
    if not video_uri.startswith('gs://'):
        return False, "Video URI must be a valid Google Cloud Storage URI (gs://...)", {}
    
    # Parse bucket and object path
    try:
        uri_parts = video_uri.replace('gs://', '').split('/', 1)
        if len(uri_parts) != 2:
            return False, "Invalid Cloud Storage URI format", {}
        
        bucket_name = uri_parts[0]
        object_path = uri_parts[1]
        
        if not bucket_name or not object_path:
            return False, "Invalid bucket name or object path in URI", {}
            
    except Exception:
        return False, "Failed to parse video URI", {}
    
    # Optional: Validate analysis options
    analysis_options = request_data.get('analysis_options', {})
    max_frames = analysis_options.get('max_frames', MAX_FRAMES_TO_ANALYZE)
    
    try:
        max_frames = int(max_frames)
        if max_frames < 1 or max_frames > 10:
            return False, "max_frames must be between 1 and 10", {}
    except (ValueError, TypeError):
        return False, "max_frames must be a valid integer", {}
    
    validated_params = {
        'video_uri': video_uri,
        'bucket_name': bucket_name,
        'object_path': object_path,
        'analysis_options': {
            'max_frames': max_frames,
            'detailed_analysis': analysis_options.get('detailed_analysis', True)
        }
    }
    
    return True, "", validated_params


def extract_video_frames(video_path: str, max_frames: int = MAX_FRAMES_TO_ANALYZE) -> List[str]:
    """
    Extract frames from video for analysis.
    
    Args:
        video_path: Path to the video file
        max_frames: Maximum number of frames to extract
        
    Returns:
        List of base64-encoded frames
    """
    frames = []
    
    if not VIDEO_PROCESSING_AVAILABLE:
        logging.warning("Video processing not available, skipping frame extraction")
        return frames
    
    try:
        cap = cv2.VideoCapture(video_path)
        if not cap.isOpened():
            logging.error(f"Failed to open video file: {video_path}")
            return frames
        
        total_frames = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
        fps = cap.get(cv2.CAP_PROP_FPS)
        duration = total_frames / fps if fps > 0 else 0
        
        logging.info(f"Video info: {total_frames} frames, {fps} FPS, {duration:.2f}s duration")
        
        # Calculate frame positions to extract (evenly distributed)
        if total_frames <= max_frames:
            frame_positions = list(range(0, total_frames, max(1, total_frames // max_frames)))
        else:
            frame_positions = [int(i * total_frames / max_frames) for i in range(max_frames)]
        
        for position in frame_positions:
            cap.set(cv2.CAP_PROP_POS_FRAMES, position)
            ret, frame = cap.read()
            
            if not ret:
                logging.warning(f"Failed to read frame at position {position}")
                continue
            
            # Encode frame as JPEG and then to base64
            success, buffer = cv2.imencode('.jpg', frame, [cv2.IMWRITE_JPEG_QUALITY, 85])
            if success:
                frame_b64 = base64.b64encode(buffer).decode('utf-8')
                frames.append(frame_b64)
                logging.info(f"Extracted frame {len(frames)} at position {position}")
            else:
                logging.warning(f"Failed to encode frame at position {position}")
        
        cap.release()
        logging.info(f"Successfully extracted {len(frames)} frames from video")
        
    except Exception as e:
        logging.error(f"Error extracting video frames: {str(e)}")
    
    return frames


def analyze_frame_with_gemini(client: genai.Client, frame_b64: str, frame_number: int) -> Optional[Dict[str, Any]]:
    """
    Analyze a single frame using Gemini vision model.
    
    Args:
        client: Gemini client instance
        frame_b64: Base64-encoded frame image
        frame_number: Frame number for logging
        
    Returns:
        Analysis results dictionary or None if failed
    """
    try:
        # Create image part from base64 data
        image_part = types.Part.from_data(
            data=base64.b64decode(frame_b64),
            mime_type="image/jpeg"
        )
        
        # Generate content analysis
        response = client.models.generate_content(
            model=GEMINI_MODEL,
            contents=[QUALITY_ANALYSIS_PROMPT, image_part],
            generation_config=types.GenerationConfig(
                temperature=0.1,  # Low temperature for consistent analysis
                max_output_tokens=1000
            )
        )
        
        if not response or not response.text:
            logging.error(f"Empty response from Gemini for frame {frame_number}")
            return None
        
        # Try to parse JSON response
        try:
            analysis_result = json.loads(response.text.strip())
            logging.info(f"Successfully analyzed frame {frame_number}")
            return analysis_result
        except json.JSONDecodeError:
            # If JSON parsing fails, create a structured response from text
            logging.warning(f"Failed to parse JSON from Gemini response for frame {frame_number}, using text analysis")
            return {
                "visual_appeal": {"score": 5, "notes": "Unable to parse detailed analysis"},
                "technical_quality": {"score": 5, "notes": "Unable to parse detailed analysis"},
                "brand_safety": {"score": 8, "notes": "Content appears safe based on text analysis"},
                "social_media_optimization": {"score": 5, "notes": "Unable to parse detailed analysis"},
                "overall_score": 5.0,
                "recommendation": "review",
                "summary": response.text[:200] + "..." if len(response.text) > 200 else response.text,
                "improvement_suggestions": ["Manual review recommended due to parsing issues"]
            }
        
    except Exception as e:
        logging.error(f"Error analyzing frame {frame_number} with Gemini: {str(e)}")
        return None


def aggregate_frame_analyses(frame_analyses: List[Dict[str, Any]]) -> Dict[str, Any]:
    """
    Aggregate analysis results from multiple frames.
    
    Args:
        frame_analyses: List of individual frame analysis results
        
    Returns:
        Aggregated analysis results
    """
    if not frame_analyses:
        return {
            "visual_appeal": {"score": 0, "notes": "No frames analyzed"},
            "technical_quality": {"score": 0, "notes": "No frames analyzed"},
            "brand_safety": {"score": 0, "notes": "No frames analyzed"},
            "social_media_optimization": {"score": 0, "notes": "No frames analyzed"},
            "overall_score": 0.0,
            "recommendation": "reject",
            "summary": "Analysis failed - no frames could be processed",
            "improvement_suggestions": ["Re-upload video with supported format"]
        }
    
    # Calculate average scores
    categories = ["visual_appeal", "technical_quality", "brand_safety", "social_media_optimization"]
    aggregated = {}
    
    for category in categories:
        scores = [analysis.get(category, {}).get("score", 0) for analysis in frame_analyses]
        avg_score = sum(scores) / len(scores) if scores else 0
        
        # Collect notes from all frames
        notes = [analysis.get(category, {}).get("notes", "") for analysis in frame_analyses]
        combined_notes = "; ".join([note for note in notes if note])
        
        aggregated[category] = {
            "score": round(avg_score, 1),
            "notes": combined_notes[:500] + "..." if len(combined_notes) > 500 else combined_notes
        }
    
    # Calculate overall score
    overall_score = sum(aggregated[cat]["score"] for cat in categories) / len(categories)
    aggregated["overall_score"] = round(overall_score, 1)
    
    # Determine recommendation based on minimum scores
    min_score = min(aggregated[cat]["score"] for cat in categories)
    if min_score >= 7 and overall_score >= 7:
        recommendation = "approve"
    elif min_score >= 5 and overall_score >= 6:
        recommendation = "review"
    else:
        recommendation = "reject"
    
    aggregated["recommendation"] = recommendation
    
    # Create summary
    summaries = [analysis.get("summary", "") for analysis in frame_analyses]
    combined_summary = " | ".join([summary[:100] for summary in summaries if summary])
    aggregated["summary"] = combined_summary[:300] + "..." if len(combined_summary) > 300 else combined_summary
    
    # Collect improvement suggestions
    all_suggestions = []
    for analysis in frame_analyses:
        suggestions = analysis.get("improvement_suggestions", [])
        all_suggestions.extend(suggestions)
    
    # Remove duplicates and limit to top 5
    unique_suggestions = list(dict.fromkeys(all_suggestions))[:5]
    aggregated["improvement_suggestions"] = unique_suggestions
    
    # Add frame-level details
    aggregated["frame_count"] = len(frame_analyses)
    aggregated["frame_details"] = frame_analyses
    
    return aggregated


def save_quality_report(bucket: storage.Bucket, video_uri: str, analysis_result: Dict[str, Any]) -> bool:
    """
    Save quality analysis report to Cloud Storage.
    
    Args:
        bucket: Cloud Storage bucket instance
        video_uri: Original video URI
        analysis_result: Analysis results to save
        
    Returns:
        True if successful, False otherwise
    """
    try:
        # Extract filename from video URI for report naming
        video_filename = video_uri.split('/')[-1]
        report_filename = f"quality_{video_filename}.json"
        
        quality_report = {
            'video_uri': video_uri,
            'analysis_timestamp': datetime.now().isoformat(),
            'analysis_result': analysis_result,
            'analyzer': {
                'model': GEMINI_MODEL,
                'version': '1.0.0',
                'project_id': PROJECT_ID
            },
            'status': 'analyzed'
        }
        
        blob = bucket.blob(f"metadata/{report_filename}")
        blob.upload_from_string(
            json.dumps(quality_report, indent=2),
            content_type='application/json'
        )
        
        logging.info(f"Quality report saved: metadata/{report_filename}")
        return True
        
    except Exception as e:
        logging.error(f"Failed to save quality report: {str(e)}")
        return False


@functions_framework.http
def validate_content(request):
    """
    Main Cloud Function entry point for content validation.
    
    Args:
        request: HTTP request object
        
    Returns:
        JSON response with analysis results or error message
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
        
        # Initialize Cloud Storage client
        try:
            storage_client = storage.Client()
            bucket = storage_client.bucket(validated_params['bucket_name'])
            blob = bucket.blob(validated_params['object_path'])
            
            if not blob.exists():
                return {'error': 'Video file not found in storage'}, 404, headers
            
            # Check file size
            file_size_mb = blob.size / (1024 * 1024)
            if file_size_mb > MAX_FILE_SIZE_MB:
                return {'error': f'Video file too large ({file_size_mb:.1f}MB > {MAX_FILE_SIZE_MB}MB)'}, 413, headers
            
            logging.info(f"Video file found: {validated_params['object_path']} ({file_size_mb:.1f}MB)")
            
        except Exception as e:
            logging.error(f"Storage operation failed: {str(e)}")
            return {'error': 'Failed to access video file'}, 500, headers
        
        # Download video file for analysis
        frames = []
        try:
            with tempfile.NamedTemporaryFile(suffix='.mp4', delete=False) as temp_video:
                blob.download_to_filename(temp_video.name)
                logging.info(f"Video downloaded to temporary file: {temp_video.name}")
                
                # Extract frames for analysis
                frames = extract_video_frames(
                    temp_video.name, 
                    validated_params['analysis_options']['max_frames']
                )
                
                # Clean up temporary file
                os.unlink(temp_video.name)
                
        except Exception as e:
            logging.error(f"Error processing video file: {str(e)}")
            return {'error': f'Failed to process video file: {str(e)}'}, 500, headers
        
        if not frames:
            return {'error': 'No frames could be extracted from video'}, 422, headers
        
        # Analyze frames with Gemini
        frame_analyses = []
        for i, frame_b64 in enumerate(frames):
            analysis = analyze_frame_with_gemini(client, frame_b64, i + 1)
            if analysis:
                frame_analyses.append(analysis)
        
        if not frame_analyses:
            return {'error': 'Failed to analyze any video frames'}, 500, headers
        
        # Aggregate results from all frames
        final_analysis = aggregate_frame_analyses(frame_analyses)
        
        # Save quality report to storage
        try:
            report_saved = save_quality_report(bucket, validated_params['video_uri'], final_analysis)
            if not report_saved:
                logging.warning("Failed to save quality report, but continuing...")
        except Exception as e:
            logging.error(f"Error saving quality report: {str(e)}")
        
        # Prepare response
        response = {
            'status': 'success',
            'video_uri': validated_params['video_uri'],
            'analysis_timestamp': datetime.now().isoformat(),
            'quality_analysis': final_analysis,
            'metadata': {
                'frames_analyzed': len(frame_analyses),
                'video_size_mb': round(file_size_mb, 1),
                'model_version': GEMINI_MODEL,
                'analysis_version': '1.0.0'
            }
        }
        
        logging.info(f"Successfully analyzed video: {validated_params['video_uri']} "
                    f"(Recommendation: {final_analysis['recommendation']}, "
                    f"Score: {final_analysis['overall_score']}/10)")
        
        return response, 200, headers
        
    except Exception as e:
        logging.error(f"Unexpected error in validate_content: {str(e)}")
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
        'service': 'quality-validator',
        'version': '1.0.0',
        'video_processing_available': VIDEO_PROCESSING_AVAILABLE
    }