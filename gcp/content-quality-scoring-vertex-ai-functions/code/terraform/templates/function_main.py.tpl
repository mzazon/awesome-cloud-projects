#!/usr/bin/env python3
"""
Content Quality Analysis Cloud Function

This Cloud Function analyzes text content using Vertex AI Gemini models
to provide comprehensive quality scoring across multiple dimensions.

Triggered by: Cloud Storage object uploads
Output: JSON analysis results in a separate Cloud Storage bucket
"""

import functions_framework
import json
import time
import logging
import os
import sys
from typing import Dict, Any, Optional
from google.cloud import storage
from google.cloud import aiplatform
from vertexai.generative_models import GenerativeModel

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# Configuration from environment variables
PROJECT_ID = "${project_id}"
REGION = "${region}"
RESULTS_BUCKET = "${results_bucket}"

# Vertex AI model configuration
MODEL_NAME = "gemini-1.5-flash"
MODEL_CONFIG = {
    "temperature": 0.2,
    "max_output_tokens": 2048,
    "top_p": 0.8,
    "top_k": 40
}

# Initialize Vertex AI
try:
    aiplatform.init(project=PROJECT_ID, location=REGION)
    logger.info(f"Vertex AI initialized for project {PROJECT_ID} in region {REGION}")
except Exception as e:
    logger.error(f"Failed to initialize Vertex AI: {str(e)}")
    sys.exit(1)

# Content quality analysis prompt template
ANALYSIS_PROMPT_TEMPLATE = """
Analyze the following content for quality across multiple dimensions and provide detailed feedback.

CONTENT TO ANALYZE:
{content}

Please evaluate the content and provide a JSON response with the following exact structure:
{{
    "overall_score": <number 1-10>,
    "readability": {{
        "score": <number 1-10>,
        "feedback": "Specific feedback on readability, sentence complexity, and clarity"
    }},
    "engagement": {{
        "score": <number 1-10>,
        "feedback": "Feedback on engagement potential, storytelling, and audience connection"
    }},
    "clarity": {{
        "score": <number 1-10>,
        "feedback": "Feedback on clarity, comprehension, and message effectiveness"
    }},
    "structure": {{
        "score": <number 1-10>,
        "feedback": "Feedback on content organization, flow, and logical progression"
    }},
    "tone": {{
        "score": <number 1-10>,
        "feedback": "Feedback on tone appropriateness, consistency, and brand alignment"
    }},
    "actionability": {{
        "score": <number 1-10>,
        "feedback": "Feedback on actionable insights, practical value, and implementation guidance"
    }},
    "improvement_suggestions": [
        "Specific actionable suggestion 1",
        "Specific actionable suggestion 2", 
        "Specific actionable suggestion 3"
    ],
    "content_analysis": {{
        "word_count": <number>,
        "estimated_reading_time_minutes": <number>,
        "key_themes": ["theme1", "theme2", "theme3"],
        "content_type": "article|blog_post|marketing_copy|technical_documentation|other"
    }}
}}

Evaluation Criteria:
- Readability: Sentence length, vocabulary complexity, reading level
- Engagement: Hook effectiveness, emotional connection, call-to-action strength
- Clarity: Message precision, jargon usage, logical flow
- Structure: Heading usage, paragraph organization, information hierarchy
- Tone: Consistency, appropriateness for audience, brand voice alignment
- Actionability: Practical value, implementable advice, next steps clarity

Focus on providing constructive, specific, and actionable feedback that content creators can immediately implement to improve their writing effectiveness.
"""


@functions_framework.cloud_event
def analyze_content_quality(cloud_event) -> None:
    """
    Main Cloud Function entry point triggered by Cloud Storage events.
    
    Args:
        cloud_event: CloudEvent containing the storage event data
    """
    try:
        # Extract event information
        event_data = cloud_event.data
        bucket_name = event_data.get("bucket")
        file_name = event_data.get("name")
        event_type = event_data.get("eventType", "unknown")
        
        logger.info(f"Processing event: {event_type} for file: {file_name} in bucket: {bucket_name}")
        
        # Validate event data
        if not bucket_name or not file_name:
            logger.error(f"Invalid event data: bucket={bucket_name}, file={file_name}")
            return
            
        # Skip processing for certain file types or paths
        if should_skip_file(file_name):
            logger.info(f"Skipping file: {file_name} (excluded type or path)")
            return
        
        # Read content from Cloud Storage
        content_text = read_file_from_storage(bucket_name, file_name)
        if not content_text:
            logger.warning(f"No content found or unable to read file: {file_name}")
            return
            
        # Validate content size
        if len(content_text) > 100000:  # 100KB limit
            logger.warning(f"Content too large ({len(content_text)} chars), truncating to 100KB")
            content_text = content_text[:100000]
        
        if len(content_text.strip()) < 10:
            logger.warning(f"Content too short ({len(content_text)} chars), skipping analysis")
            return
        
        # Analyze content quality using Vertex AI
        logger.info(f"Starting Vertex AI analysis for file: {file_name}")
        quality_analysis = analyze_with_vertex_ai(content_text)
        
        # Store analysis results
        store_analysis_results(file_name, quality_analysis, bucket_name)
        
        logger.info(f"Analysis completed successfully for file: {file_name}")
        
    except Exception as e:
        logger.error(f"Error processing cloud event: {str(e)}", exc_info=True)
        # Don't re-raise to avoid function retries for permanent failures


def should_skip_file(file_name: str) -> bool:
    """
    Determine if a file should be skipped based on name or type.
    
    Args:
        file_name: Name of the file to check
        
    Returns:
        True if the file should be skipped, False otherwise
    """
    skip_patterns = [
        'analysis_',  # Skip result files
        '.zip', '.tar', '.gz',  # Skip archive files
        '.jpg', '.jpeg', '.png', '.gif', '.pdf',  # Skip non-text files
        '.exe', '.bin', '.so', '.dll',  # Skip binary files
        'temp_', 'tmp_', '.tmp',  # Skip temporary files
        'backup_', '.bak',  # Skip backup files
    ]
    
    file_lower = file_name.lower()
    return any(pattern in file_lower for pattern in skip_patterns)


def read_file_from_storage(bucket_name: str, file_name: str) -> Optional[str]:
    """
    Read text content from a Cloud Storage file.
    
    Args:
        bucket_name: Name of the storage bucket
        file_name: Name of the file to read
        
    Returns:
        File content as string, or None if reading fails
    """
    try:
        # Initialize storage client
        storage_client = storage.Client()
        bucket = storage_client.bucket(bucket_name)
        blob = bucket.blob(file_name)
        
        # Check if file exists
        if not blob.exists():
            logger.error(f"File does not exist: {file_name}")
            return None
            
        # Download and decode content
        content_bytes = blob.download_as_bytes()
        
        # Try different encodings
        encodings = ['utf-8', 'utf-16', 'latin-1', 'ascii']
        for encoding in encodings:
            try:
                content_text = content_bytes.decode(encoding)
                logger.info(f"Successfully decoded file {file_name} using {encoding}")
                return content_text
            except UnicodeDecodeError:
                continue
                
        logger.error(f"Failed to decode file {file_name} with any supported encoding")
        return None
        
    except Exception as e:
        logger.error(f"Error reading file {file_name} from bucket {bucket_name}: {str(e)}")
        return None


def analyze_with_vertex_ai(content: str) -> Dict[str, Any]:
    """
    Analyze content quality using Vertex AI Gemini model.
    
    Args:
        content: Text content to analyze
        
    Returns:
        Dictionary containing quality analysis results
    """
    try:
        # Prepare the analysis prompt
        prompt = ANALYSIS_PROMPT_TEMPLATE.format(content=content)
        
        # Initialize Gemini model
        model = GenerativeModel(MODEL_NAME)
        logger.info(f"Using Vertex AI model: {MODEL_NAME}")
        
        # Generate analysis
        response = model.generate_content(
            prompt,
            generation_config=MODEL_CONFIG
        )
        
        # Parse and validate JSON response
        response_text = response.text.strip()
        logger.info(f"Received response from Vertex AI ({len(response_text)} chars)")
        
        # Extract JSON from response (handle markdown formatting)
        json_start = response_text.find('{')
        json_end = response_text.rfind('}') + 1
        
        if json_start == -1 or json_end == 0:
            raise ValueError("No JSON found in response")
            
        json_text = response_text[json_start:json_end]
        quality_analysis = json.loads(json_text)
        
        # Validate required fields
        required_fields = ['overall_score', 'readability', 'engagement', 'clarity', 
                          'structure', 'tone', 'actionability', 'improvement_suggestions']
        
        for field in required_fields:
            if field not in quality_analysis:
                raise ValueError(f"Missing required field: {field}")
        
        # Add metadata
        quality_analysis['analysis_metadata'] = {
            'model_used': MODEL_NAME,
            'analysis_timestamp': time.time(),
            'content_length': len(content),
            'model_config': MODEL_CONFIG
        }
        
        logger.info("Content analysis completed successfully")
        return quality_analysis
        
    except json.JSONDecodeError as e:
        logger.error(f"Failed to parse JSON response from Vertex AI: {str(e)}")
        return create_fallback_analysis(content, f"JSON parsing error: {str(e)}")
        
    except Exception as e:
        logger.error(f"Vertex AI analysis failed: {str(e)}")
        return create_fallback_analysis(content, f"Analysis failed: {str(e)}")


def create_fallback_analysis(content: str, error_message: str) -> Dict[str, Any]:
    """
    Create a basic fallback analysis when Vertex AI fails.
    
    Args:
        content: Original content
        error_message: Error message explaining the failure
        
    Returns:
        Dictionary with basic analysis and error information
    """
    word_count = len(content.split())
    reading_time = max(1, word_count // 200)  # ~200 words per minute
    
    return {
        "overall_score": 5,
        "error": error_message,
        "readability": {
            "score": 5, 
            "feedback": "Analysis unavailable due to processing error"
        },
        "engagement": {
            "score": 5, 
            "feedback": "Analysis unavailable due to processing error"
        },
        "clarity": {
            "score": 5, 
            "feedback": "Analysis unavailable due to processing error"
        },
        "structure": {
            "score": 5, 
            "feedback": "Analysis unavailable due to processing error"
        },
        "tone": {
            "score": 5, 
            "feedback": "Analysis unavailable due to processing error"
        },
        "actionability": {
            "score": 5, 
            "feedback": "Analysis unavailable due to processing error"
        },
        "improvement_suggestions": [
            "Retry analysis when service is available",
            "Check content format and encoding",
            "Verify Vertex AI service status"
        ],
        "content_analysis": {
            "word_count": word_count,
            "estimated_reading_time_minutes": reading_time,
            "key_themes": ["analysis_unavailable"],
            "content_type": "unknown"
        },
        "analysis_metadata": {
            "model_used": "fallback",
            "analysis_timestamp": time.time(),
            "content_length": len(content),
            "error_occurred": True
        }
    }


def store_analysis_results(original_filename: str, analysis_results: Dict[str, Any], 
                          source_bucket: str) -> None:
    """
    Store analysis results in the results Cloud Storage bucket.
    
    Args:
        original_filename: Name of the original content file
        analysis_results: Analysis results dictionary
        source_bucket: Name of the source bucket
    """
    try:
        # Initialize storage client
        storage_client = storage.Client()
        results_bucket = storage_client.bucket(RESULTS_BUCKET)
        
        # Create results filename with timestamp
        timestamp = int(time.time())
        results_filename = f"analysis_{original_filename}_{timestamp}.json"
        
        # Prepare complete results data
        results_data = {
            "original_file": original_filename,
            "source_bucket": source_bucket,
            "timestamp": timestamp,
            "iso_timestamp": time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime()),
            "analysis": analysis_results,
            "processing_info": {
                "function_name": os.environ.get('K_SERVICE', 'unknown'),
                "function_version": os.environ.get('K_REVISION', 'unknown'),
                "region": REGION,
                "project_id": PROJECT_ID
            }
        }
        
        # Upload results as JSON
        blob = results_bucket.blob(results_filename)
        blob.upload_from_string(
            json.dumps(results_data, indent=2, ensure_ascii=False),
            content_type='application/json'
        )
        
        # Set metadata
        blob.metadata = {
            'original_file': original_filename,
            'analysis_timestamp': str(timestamp),
            'content_type': 'quality_analysis'
        }
        blob.patch()
        
        logger.info(f"Analysis results stored successfully: {results_filename}")
        
    except Exception as e:
        logger.error(f"Failed to store analysis results: {str(e)}")
        raise


# Health check endpoint (for local testing)
@functions_framework.http
def health_check(request):
    """Health check endpoint for function validation."""
    return {
        'status': 'healthy',
        'timestamp': time.time(),
        'project_id': PROJECT_ID,
        'region': REGION,
        'model': MODEL_NAME
    }


if __name__ == "__main__":
    # Local testing support
    print("Content Quality Analysis Function")
    print(f"Project: {PROJECT_ID}")
    print(f"Region: {REGION}")
    print(f"Results Bucket: {RESULTS_BUCKET}")
    print(f"Model: {MODEL_NAME}")