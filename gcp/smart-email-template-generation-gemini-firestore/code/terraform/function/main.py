"""
AI-Powered Email Template Generator using Vertex AI Gemini and Firestore

This Cloud Function generates personalized email templates using Vertex AI Gemini
based on user preferences and campaign data stored in Firestore. It provides
intelligent content creation with proper error handling and CORS support.

Author: Cloud Recipe Generator
Version: 1.0
"""

import json
import logging
import os
from typing import Dict, Any, Tuple, Optional
from google.cloud import firestore
import vertexai
from vertexai.generative_models import GenerativeModel, GenerationConfig
import functions_framework
from flask import Request

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Initialize Firestore client with specific database
DATABASE_ID = "${database_id}"
db = firestore.Client(database=DATABASE_ID)

# Initialize Vertex AI
PROJECT_ID = os.environ.get('PROJECT_ID', os.environ.get('GCP_PROJECT'))
REGION = os.environ.get('REGION', 'us-central1')

try:
    vertexai.init(project=PROJECT_ID, location=REGION)
    logger.info(f"Vertex AI initialized for project {PROJECT_ID} in {REGION}")
except Exception as e:
    logger.error(f"Failed to initialize Vertex AI: {str(e)}")

# Gemini model configuration
GEMINI_MODEL = "gemini-1.5-flash"

# Default generation configuration
DEFAULT_GENERATION_CONFIG = GenerationConfig(
    temperature=0.7,
    top_p=0.8,
    top_k=40,
    max_output_tokens=1024,
)


@functions_framework.http
def generate_email_template(request: Request) -> Tuple[Dict[str, Any], int, Dict[str, str]]:
    """
    Generate personalized email templates using Gemini and Firestore.
    
    Args:
        request: HTTP request object containing campaign parameters
        
    Returns:
        Tuple containing response data, HTTP status code, and headers
    """
    # Set CORS headers for web requests
    headers = {
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Headers': 'Content-Type, Authorization',
        'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
        'Content-Type': 'application/json'
    }
    
    # Handle preflight CORS requests
    if request.method == 'OPTIONS':
        headers['Access-Control-Max-Age'] = '3600'
        return ('', 204, headers)
    
    try:
        logger.info(f"Received {request.method} request for email template generation")
        
        # Handle GET requests for health checks
        if request.method == 'GET':
            return {
                "status": "healthy",
                "service": "email-template-generator",
                "version": "1.0",
                "endpoints": {
                    "generate": "POST / with JSON payload",
                    "health": "GET /"
                }
            }, 200, headers
        
        # Parse and validate request data
        request_data = _parse_request_data(request)
        if isinstance(request_data, tuple):  # Error response
            return request_data
            
        campaign_type = request_data.get('campaign_type', 'newsletter')
        subject_theme = request_data.get('subject_theme', 'company updates')
        custom_context = request_data.get('custom_context', '')
        
        logger.info(f"Processing template generation for campaign: {campaign_type}")
        
        # Fetch user preferences and campaign configuration
        user_prefs = _get_user_preferences()
        campaign_config = _get_campaign_configuration(campaign_type)
        
        # Generate email template using Gemini
        template = _generate_with_gemini(
            user_prefs, campaign_config, subject_theme, custom_context
        )
        
        # Store generated template in Firestore
        template_id = _store_template(
            campaign_type, subject_theme, template, user_prefs
        )
        
        # Return successful response
        response_data = {
            "success": True,
            "template_id": template_id,
            "template": template,
            "campaign_type": campaign_type,
            "generation_timestamp": firestore.SERVER_TIMESTAMP
        }
        
        logger.info(f"Successfully generated template with ID: {template_id}")
        return response_data, 200, headers
        
    except Exception as e:
        logger.error(f"Error generating email template: {str(e)}", exc_info=True)
        error_response = {
            "success": False,
            "error": f"Template generation failed: {str(e)}",
            "error_type": type(e).__name__
        }
        return error_response, 500, headers


def _parse_request_data(request: Request) -> Dict[str, Any]:
    """Parse and validate request JSON data."""
    try:
        request_json = request.get_json(silent=True)
        if not request_json:
            return ({
                "success": False,
                "error": "Invalid JSON request. Please provide valid JSON data."
            }, 400, {'Content-Type': 'application/json'})
        
        return request_json
    except Exception as e:
        logger.error(f"Failed to parse request data: {str(e)}")
        return ({
            "success": False,
            "error": "Failed to parse request data"
        }, 400, {'Content-Type': 'application/json'})


def _get_user_preferences() -> Dict[str, Any]:
    """Fetch user preferences from Firestore."""
    try:
        prefs_ref = db.collection('userPreferences').document('default')
        prefs_doc = prefs_ref.get()
        
        if not prefs_doc.exists:
            # Create and return default preferences
            default_prefs = {
                "company": "Your Company",
                "industry": "Technology",
                "tone": "professional yet friendly",
                "targetAudience": "business professionals",
                "brandVoice": "trustworthy and innovative",
                "primaryColor": "#2196F3"
            }
            prefs_ref.set(default_prefs)
            logger.info("Created default user preferences")
            return default_prefs
        else:
            prefs_data = prefs_doc.to_dict()
            logger.info("Retrieved existing user preferences")
            return prefs_data
            
    except Exception as e:
        logger.error(f"Error fetching user preferences: {str(e)}")
        # Return fallback preferences
        return {
            "company": "Your Company",
            "industry": "Technology",
            "tone": "professional",
            "targetAudience": "professionals",
            "brandVoice": "professional"
        }


def _get_campaign_configuration(campaign_type: str) -> Dict[str, Any]:
    """Fetch campaign configuration from Firestore."""
    try:
        campaign_ref = db.collection('campaignTypes').document(campaign_type)
        campaign_doc = campaign_ref.get()
        
        if not campaign_doc.exists:
            # Create and return default campaign configuration
            default_campaign = {
                "purpose": "general communication",
                "cta": "Learn More",
                "length": "medium"
            }
            campaign_ref.set(default_campaign)
            logger.info(f"Created default configuration for campaign type: {campaign_type}")
            return default_campaign
        else:
            campaign_data = campaign_doc.to_dict()
            logger.info(f"Retrieved configuration for campaign type: {campaign_type}")
            return campaign_data
            
    except Exception as e:
        logger.error(f"Error fetching campaign configuration: {str(e)}")
        # Return fallback configuration
        return {
            "purpose": "general communication",
            "cta": "Learn More",
            "length": "medium"
        }


def _generate_with_gemini(
    user_prefs: Dict[str, Any],
    campaign_config: Dict[str, Any],
    subject_theme: str,
    custom_context: str
) -> Dict[str, str]:
    """Generate email content using Vertex AI Gemini."""
    try:
        # Initialize Gemini model
        model = GenerativeModel(GEMINI_MODEL)
        
        # Construct detailed prompt for email generation
        prompt = f"""
You are an expert email marketing copywriter. Generate a professional email template with the following specifications:

Company Information:
- Company: {user_prefs.get('company', 'Your Company')}
- Industry: {user_prefs.get('industry', 'Technology')}
- Brand Voice: {user_prefs.get('brandVoice', 'professional')}
- Target Audience: {user_prefs.get('targetAudience', 'professionals')}

Email Configuration:
- Campaign Purpose: {campaign_config.get('purpose', 'general communication')}
- Tone: {user_prefs.get('tone', 'professional')}
- Call-to-Action: {campaign_config.get('cta', 'Learn More')}
- Content Length: {campaign_config.get('length', 'medium')}
- Subject Theme: {subject_theme}

Additional Context: {custom_context}

Requirements:
1. Generate a compelling subject line (under 60 characters)
2. Create email body with proper structure:
   - Professional greeting
   - Engaging opening paragraph
   - 2-3 body paragraphs with relevant content
   - Clear call-to-action
   - Professional closing
3. Maintain the specified tone and brand voice throughout
4. Include placeholders for personalization: [First Name], [Company Name]
5. Ensure content is relevant to the subject theme and context

Format your response as valid JSON with exactly these two fields:
{{"subject": "subject line here", "body": "email body content here"}}

Important: Return ONLY the JSON object, no additional text or formatting.
"""
        
        logger.info("Generating content with Gemini model")
        
        # Generate content with Gemini
        response = model.generate_content(
            prompt,
            generation_config=DEFAULT_GENERATION_CONFIG
        )
        
        # Parse and validate response
        template_data = _parse_gemini_response(response.text, user_prefs, subject_theme)
        
        logger.info("Successfully generated email template with Gemini")
        return template_data
        
    except Exception as e:
        logger.error(f"Gemini generation error: {str(e)}")
        # Return fallback template
        return _create_fallback_template(user_prefs, subject_theme)


def _parse_gemini_response(
    response_text: str,
    user_prefs: Dict[str, Any],
    subject_theme: str
) -> Dict[str, str]:
    """Parse and validate Gemini response."""
    try:
        # Clean up response text
        content = response_text.strip()
        
        # Remove markdown code blocks if present
        if content.startswith('```json'):
            content = content[7:-3]
        elif content.startswith('```'):
            content = content[3:-3]
        
        # Parse JSON response
        template_data = json.loads(content)
        
        # Validate required fields
        if "subject" not in template_data or "body" not in template_data:
            raise ValueError("Missing required fields in generated template")
        
        # Validate content quality
        if len(template_data["subject"]) > 80:
            template_data["subject"] = template_data["subject"][:77] + "..."
        
        if len(template_data["body"]) < 50:
            raise ValueError("Generated email body is too short")
        
        return template_data
        
    except json.JSONDecodeError as e:
        logger.warning(f"Failed to parse JSON response: {str(e)}")
        # Create structured template from unstructured response
        return _create_structured_template(response_text, user_prefs, subject_theme)
    
    except Exception as e:
        logger.error(f"Error parsing Gemini response: {str(e)}")
        return _create_fallback_template(user_prefs, subject_theme)


def _create_structured_template(
    raw_content: str,
    user_prefs: Dict[str, Any],
    subject_theme: str
) -> Dict[str, str]:
    """Create structured template from unstructured Gemini response."""
    company = user_prefs.get('company', 'Your Company')
    
    # Generate fallback subject line
    subject_line = f"Exciting Updates from {company}"
    if len(subject_theme) > 0:
        subject_line = f"{subject_theme.title()} - {company}"
    
    # Use raw content as body with some formatting
    body_content = raw_content.strip()
    
    return {
        "subject": subject_line[:77] + "..." if len(subject_line) > 80 else subject_line,
        "body": body_content
    }


def _create_fallback_template(
    user_prefs: Dict[str, Any],
    subject_theme: str
) -> Dict[str, str]:
    """Create fallback template when Gemini fails."""
    company = user_prefs.get('company', 'Your Company')
    
    return {
        "subject": f"Updates from {company}",
        "body": f"""Hello [First Name],

We hope this email finds you well. We wanted to share some exciting updates about {subject_theme}.

Our team has been working hard to bring you the latest developments in our industry. We believe these updates will be valuable for your business and help you stay ahead of the curve.

We'd love to share more details with you and discuss how these updates might benefit your organization.

Best regards,
The {company} Team

P.S. Stay tuned for more exciting announcements coming soon!"""
    }


def _store_template(
    campaign_type: str,
    subject_theme: str,
    template: Dict[str, str],
    user_prefs: Dict[str, Any]
) -> str:
    """Store generated template in Firestore."""
    try:
        template_data = {
            "campaign_type": campaign_type,
            "subject_theme": subject_theme,
            "subject_line": template["subject"],
            "email_body": template["body"],
            "generated_at": firestore.SERVER_TIMESTAMP,
            "user_preferences": user_prefs,
            "model_used": GEMINI_MODEL,
            "version": "1.0"
        }
        
        # Add document to generatedTemplates collection
        doc_ref = db.collection('generatedTemplates').add(template_data)
        template_id = doc_ref[1].id
        
        logger.info(f"Stored template in Firestore with ID: {template_id}")
        return template_id
        
    except Exception as e:
        logger.error(f"Error storing template: {str(e)}")
        # Return a fallback ID
        import time
        return f"fallback_{int(time.time())}"


# Health check endpoint
def health_check() -> Dict[str, Any]:
    """Health check endpoint for monitoring."""
    try:
        # Test Firestore connectivity
        db.collection('healthCheck').document('test').set({'timestamp': firestore.SERVER_TIMESTAMP})
        
        # Test Vertex AI availability
        vertexai.init(project=PROJECT_ID, location=REGION)
        
        return {
            "status": "healthy",
            "timestamp": firestore.SERVER_TIMESTAMP,
            "services": {
                "firestore": "connected",
                "vertex_ai": "available",
                "gemini_model": GEMINI_MODEL
            }
        }
    except Exception as e:
        logger.error(f"Health check failed: {str(e)}")
        return {
            "status": "unhealthy",
            "error": str(e)
        }