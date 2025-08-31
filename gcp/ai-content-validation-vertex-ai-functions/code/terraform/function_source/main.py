# AI Content Validation Cloud Function
# This function processes content uploads and validates them using Vertex AI Gemini models
# Template variables are replaced during Terraform deployment

import functions_framework
import json
import logging
import os
from google.cloud import storage
import vertexai
from vertexai.generative_models import GenerativeModel, SafetySetting, HarmCategory, HarmBlockThreshold

# Initialize logging with configurable level
LOG_LEVEL = os.environ.get('LOG_LEVEL', 'INFO')
logging.basicConfig(level=getattr(logging, LOG_LEVEL))
logger = logging.getLogger(__name__)

# Configuration from environment variables (set by Terraform)
PROJECT_ID = os.environ.get('GCP_PROJECT', '${project_id}')
REGION = os.environ.get('FUNCTION_REGION', '${region}')
RESULTS_BUCKET = os.environ.get('RESULTS_BUCKET', '${results_bucket}')
GEMINI_MODEL = os.environ.get('GEMINI_MODEL', '${gemini_model}')
SAFETY_THRESHOLD = os.environ.get('SAFETY_THRESHOLD', '${safety_threshold}')
ENVIRONMENT = os.environ.get('ENVIRONMENT', 'dev')

# Initialize Vertex AI with project and region
vertexai.init(project=PROJECT_ID, location=REGION)

# Safety threshold mapping
THRESHOLD_MAP = {
    "BLOCK_NONE": HarmBlockThreshold.BLOCK_NONE,
    "BLOCK_LOW_AND_ABOVE": HarmBlockThreshold.BLOCK_LOW_AND_ABOVE,
    "BLOCK_MEDIUM_AND_ABOVE": HarmBlockThreshold.BLOCK_MEDIUM_AND_ABOVE,
    "BLOCK_ONLY_HIGH": HarmBlockThreshold.BLOCK_ONLY_HIGH
}

@functions_framework.cloud_event
def validate_content(cloud_event):
    """
    Cloud Function triggered by Cloud Storage uploads for AI content validation.
    
    Args:
        cloud_event: CloudEvent containing file upload information
        
    Returns:
        None - Results are stored in Cloud Storage
    """
    
    try:
        # Extract file information from Cloud Event
        event_data = cloud_event.data
        bucket_name = event_data.get('bucket')
        file_name = event_data.get('name')
        content_type = event_data.get('contentType', 'text/plain')
        
        logger.info(f"Processing file: {file_name} from bucket: {bucket_name}")
        logger.info(f"Content type: {content_type}")
        
        # Validate that this is a text file
        if not _is_text_file(file_name, content_type):
            logger.warning(f"Skipping non-text file: {file_name}")
            return
        
        # Download content from Cloud Storage
        content = _download_file_content(bucket_name, file_name)
        if not content:
            logger.error(f"Failed to download content from {file_name}")
            return
        
        # Perform AI content validation using Vertex AI
        validation_result = _analyze_content_safety(content, file_name)
        
        # Store validation results in Cloud Storage
        _store_validation_results(validation_result, file_name)
        
        logger.info(f"Validation completed successfully for {file_name}")
        
    except Exception as e:
        logger.error(f"Error processing file {file_name}: {str(e)}", exc_info=True)
        
        # Store error result for debugging
        error_result = {
            "file_name": file_name,
            "error": str(e),
            "recommendation": "review_required",
            "timestamp": _get_timestamp(),
            "environment": ENVIRONMENT
        }
        _store_validation_results(error_result, file_name)
        raise

def _is_text_file(file_name, content_type):
    """
    Check if the uploaded file is a text file suitable for validation.
    
    Args:
        file_name: Name of the uploaded file
        content_type: MIME type of the file
        
    Returns:
        bool: True if file should be processed, False otherwise
    """
    
    # Check file extension
    text_extensions = ['.txt', '.md', '.json', '.csv', '.log', '.xml', '.html']
    file_ext = os.path.splitext(file_name.lower())[1]
    
    # Check content type
    text_content_types = [
        'text/plain', 'text/markdown', 'application/json',
        'text/csv', 'text/xml', 'text/html', 'application/xml'
    ]
    
    return (file_ext in text_extensions or 
            content_type in text_content_types or
            content_type.startswith('text/'))

def _download_file_content(bucket_name, file_name):
    """
    Download file content from Cloud Storage.
    
    Args:
        bucket_name: Name of the source bucket
        file_name: Name of the file to download
        
    Returns:
        str: File content as string, or None if error
    """
    
    try:
        storage_client = storage.Client()
        bucket = storage_client.bucket(bucket_name)
        blob = bucket.blob(file_name)
        
        # Download as text with encoding detection
        content = blob.download_as_text(encoding='utf-8')
        
        logger.info(f"Downloaded {len(content)} characters from {file_name}")
        return content
        
    except UnicodeDecodeError:
        logger.warning(f"UTF-8 decode failed for {file_name}, trying latin-1")
        try:
            content = blob.download_as_text(encoding='latin-1')
            return content
        except Exception as e:
            logger.error(f"Failed to decode {file_name}: {str(e)}")
            return None
            
    except Exception as e:
        logger.error(f"Failed to download {file_name}: {str(e)}")
        return None

def _analyze_content_safety(content, file_name):
    """
    Analyze content safety using Vertex AI Gemini models.
    
    Args:
        content: Text content to analyze
        file_name: Original file name for reference
        
    Returns:
        dict: Validation results with safety analysis
    """
    
    try:
        # Configure safety settings based on threshold
        threshold = THRESHOLD_MAP.get(SAFETY_THRESHOLD, HarmBlockThreshold.BLOCK_MEDIUM_AND_ABOVE)
        
        safety_settings = [
            SafetySetting(
                category=HarmCategory.HARM_CATEGORY_HATE_SPEECH,
                threshold=threshold
            ),
            SafetySetting(
                category=HarmCategory.HARM_CATEGORY_DANGEROUS_CONTENT,
                threshold=threshold
            ),
            SafetySetting(
                category=HarmCategory.HARM_CATEGORY_SEXUALLY_EXPLICIT,
                threshold=threshold
            ),
            SafetySetting(
                category=HarmCategory.HARM_CATEGORY_HARASSMENT,
                threshold=threshold
            )
        ]
        
        # Initialize Gemini model with safety settings
        model = GenerativeModel(
            GEMINI_MODEL,
            safety_settings=safety_settings
        )
        
        # Create analysis prompt
        analysis_prompt = f"""
        Analyze this content for safety, quality, and appropriateness. 
        Provide a brief assessment of:
        1. Overall safety level
        2. Content quality
        3. Any potential issues
        4. Recommendation for approval
        
        Content to analyze:
        {content}
        """
        
        # Generate response with safety analysis
        response = model.generate_content(analysis_prompt)
        
        # Extract safety ratings from response
        safety_ratings = []
        if response.candidates and response.candidates[0].safety_ratings:
            safety_ratings = [
                {
                    "category": rating.category.name,
                    "probability": rating.probability.name,
                    "blocked": rating.blocked
                }
                for rating in response.candidates[0].safety_ratings
            ]
        
        # Determine if content is safe based on safety ratings
        content_blocked = any(rating.get("blocked", False) for rating in safety_ratings)
        overall_safe = not content_blocked
        
        # Build comprehensive validation result
        validation_result = {
            "file_name": file_name,
            "content_length": len(content),
            "model_used": GEMINI_MODEL,
            "safety_threshold": SAFETY_THRESHOLD,
            "timestamp": _get_timestamp(),
            "environment": ENVIRONMENT,
            "safety_analysis": {
                "overall_safe": overall_safe,
                "content_blocked": content_blocked,
                "safety_ratings": safety_ratings,
                "analysis_text": response.text if response.text else "Content analysis completed"
            },
            "recommendation": _get_recommendation(overall_safe, safety_ratings),
            "processing_info": {
                "project_id": PROJECT_ID,
                "region": REGION,
                "function_version": "1.0"
            }
        }
        
        logger.info(f"Safety analysis completed for {file_name}: {validation_result['recommendation']}")
        return validation_result
        
    except Exception as e:
        logger.error(f"Error in safety analysis for {file_name}: {str(e)}")
        return {
            "file_name": file_name,
            "content_length": len(content) if content else 0,
            "error": str(e),
            "recommendation": "review_required",
            "timestamp": _get_timestamp(),
            "environment": ENVIRONMENT
        }

def _get_recommendation(overall_safe, safety_ratings):
    """
    Generate recommendation based on safety analysis.
    
    Args:
        overall_safe: Boolean indicating if content is safe
        safety_ratings: List of safety rating dictionaries
        
    Returns:
        str: Recommendation (approved, rejected, review_required)
    """
    
    if overall_safe:
        return "approved"
    
    # Check if any high-risk categories were flagged
    high_risk_blocked = any(
        rating.get("blocked", False) and 
        rating.get("probability") in ["HIGH", "VERY_HIGH"]
        for rating in safety_ratings
    )
    
    if high_risk_blocked:
        return "rejected"
    else:
        return "review_required"

def _store_validation_results(validation_result, file_name):
    """
    Store validation results in Cloud Storage.
    
    Args:
        validation_result: Dictionary containing validation results
        file_name: Original file name for result naming
    """
    
    try:
        storage_client = storage.Client()
        results_bucket = storage_client.bucket(RESULTS_BUCKET)
        
        # Create results file name with timestamp
        base_name = os.path.splitext(file_name)[0]
        timestamp = _get_timestamp().replace(":", "-").replace(".", "-")
        results_file_name = f"validation_results/{base_name}_results_{timestamp}.json"
        
        # Upload results as JSON
        results_blob = results_bucket.blob(results_file_name)
        results_blob.upload_from_string(
            json.dumps(validation_result, indent=2, ensure_ascii=False),
            content_type='application/json'
        )
        
        logger.info(f"Results stored: {results_file_name}")
        
        # Also store a latest result for easy access
        latest_file_name = f"validation_results/latest_{base_name}_results.json"
        latest_blob = results_bucket.blob(latest_file_name)
        latest_blob.upload_from_string(
            json.dumps(validation_result, indent=2, ensure_ascii=False),
            content_type='application/json'
        )
        
    except Exception as e:
        logger.error(f"Error storing validation results: {str(e)}")
        raise

def _get_timestamp():
    """
    Get current timestamp in ISO format.
    
    Returns:
        str: Current timestamp
    """
    from datetime import datetime
    return datetime.utcnow().isoformat() + "Z"

# Health check endpoint for monitoring
@functions_framework.http
def health_check(request):
    """
    HTTP endpoint for health checking the function.
    
    Args:
        request: HTTP request object
        
    Returns:
        dict: Health status information
    """
    
    return {
        "status": "healthy",
        "timestamp": _get_timestamp(),
        "environment": ENVIRONMENT,
        "model": GEMINI_MODEL,
        "project": PROJECT_ID,
        "region": REGION
    }