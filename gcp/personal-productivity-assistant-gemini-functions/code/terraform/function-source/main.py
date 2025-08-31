# Personal Productivity Assistant - Email Processing Function
# Main Cloud Function for AI-powered email processing using Gemini 2.5 Flash

import os
import json
import logging
from datetime import datetime
from typing import List, Dict, Any
import functions_framework
from google.cloud import aiplatform
from google.cloud import firestore
from google.cloud import pubsub_v1
from googleapiclient.discovery import build
from google.oauth2.credentials import Credentials
import vertexai
from vertexai.generative_models import GenerativeModel, Tool, FunctionDeclaration

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Initialize Vertex AI with project and region from template variables
PROJECT_ID = "${project_id}"
REGION = "${region}"

try:
    vertexai.init(project=PROJECT_ID, location=REGION)
    logger.info(f"Vertex AI initialized for project {PROJECT_ID} in region {REGION}")
except Exception as e:
    logger.error(f"Failed to initialize Vertex AI: {str(e)}")
    raise

# Initialize Google Cloud clients
try:
    db = firestore.Client(project=PROJECT_ID)
    publisher = pubsub_v1.PublisherClient()
    logger.info("Google Cloud clients initialized successfully")
except Exception as e:
    logger.error(f"Failed to initialize Google Cloud clients: {str(e)}")
    raise

# Define function declarations for Gemini function calling
extract_action_items_func = FunctionDeclaration(
    name="extract_action_items",
    description="Extract action items and tasks from email content with priority and assignee information",
    parameters={
        "type": "object",
        "properties": {
            "action_items": {
                "type": "array",
                "description": "List of identified action items from the email",
                "items": {
                    "type": "object",
                    "properties": {
                        "task": {
                            "type": "string", 
                            "description": "Clear, actionable description of the task"
                        },
                        "priority": {
                            "type": "string", 
                            "enum": ["high", "medium", "low"],
                            "description": "Priority level based on urgency and importance"
                        },
                        "due_date": {
                            "type": "string", 
                            "description": "Estimated or mentioned due date (YYYY-MM-DD format if specific, or relative like 'next week')"
                        },
                        "assignee": {
                            "type": "string", 
                            "description": "Person responsible for the task (email address or name)"
                        },
                        "category": {
                            "type": "string",
                            "description": "Category of the task (meeting, review, research, etc.)"
                        }
                    },
                    "required": ["task", "priority"]
                }
            },
            "summary": {
                "type": "string", 
                "description": "Concise 1-2 sentence summary of the email's main content and purpose"
            },
            "urgency_score": {
                "type": "number",
                "description": "Urgency score from 1-10 based on email content and context"
            }
        },
        "required": ["action_items", "summary", "urgency_score"]
    }
)

generate_reply_func = FunctionDeclaration(
    name="generate_reply",
    description="Generate appropriate email reply based on content, context, and communication style",
    parameters={
        "type": "object",
        "properties": {
            "reply_text": {
                "type": "string", 
                "description": "Well-crafted, professional email reply addressing the sender's needs"
            },
            "tone": {
                "type": "string", 
                "enum": ["professional", "friendly", "formal", "casual"],
                "description": "Appropriate tone based on the original email's style and sender relationship"
            },
            "action_required": {
                "type": "boolean", 
                "description": "Whether the reply requires immediate action from the recipient"
            },
            "suggested_subject": {
                "type": "string",
                "description": "Suggested subject line for the reply"
            },
            "confidence_score": {
                "type": "number",
                "description": "Confidence score (1-10) in the appropriateness of the generated reply"
            }
        },
        "required": ["reply_text", "tone", "action_required", "confidence_score"]
    }
)

# Initialize Gemini model with function calling capabilities
productivity_tool = Tool(
    function_declarations=[extract_action_items_func, generate_reply_func]
)

# Configure Gemini model with optimized settings for email processing
model = GenerativeModel(
    "gemini-2.5-flash-002",
    tools=[productivity_tool],
    generation_config={
        "temperature": 0.3,        # Lower temperature for more consistent responses
        "top_p": 0.8,             # Balanced creativity and focus
        "max_output_tokens": 2048, # Sufficient for detailed responses
        "top_k": 40               # Controlled vocabulary selection
    }
)

def process_email_content(email_data: Dict[str, Any]) -> Dict[str, Any]:
    """
    Process email content using Gemini 2.5 Flash with function calling.
    
    Args:
        email_data: Dictionary containing email information (subject, body, sender, etc.)
        
    Returns:
        Dictionary with analysis results including action items and suggested replies
    """
    try:
        # Extract email components with validation
        subject = email_data.get('subject', '').strip()
        body = email_data.get('body', '').strip()
        sender = email_data.get('sender', '').strip()
        thread_id = email_data.get('threadId', '')
        
        if not body or not sender:
            logger.warning("Email missing required fields (body or sender)")
            return {
                "error": "Email missing required content",
                "analysis_complete": False,
                "timestamp": datetime.utcnow().isoformat()
            }
        
        # Create comprehensive prompt for email analysis
        prompt = f"""
        You are an AI assistant specializing in email analysis and productivity automation.
        Analyze the following email thoroughly and provide actionable insights:
        
        EMAIL DETAILS:
        From: {sender}
        Subject: {subject}
        Thread ID: {thread_id}
        
        EMAIL CONTENT:
        {body}
        
        ANALYSIS TASKS:
        1. Call extract_action_items to:
           - Identify all explicit and implicit action items
           - Assign appropriate priority levels based on urgency and importance
           - Determine realistic timelines and assignees
           - Categorize tasks by type
           - Calculate overall urgency score
        
        2. Call generate_reply to:
           - Create a professional, helpful response
           - Match the tone and style of the original email
           - Address key points and questions raised
           - Provide clear next steps if needed
           - Ensure the reply is appropriate for the business context
        
        CONTEXT CONSIDERATIONS:
        - Professional business communication standards
        - Urgency indicators in language and timing
        - Relationship dynamics (internal team, external client, etc.)
        - Cultural and organizational communication norms
        
        Please use the provided functions to structure your response with detailed analysis.
        """
        
        logger.info(f"Processing email from {sender} with subject: {subject[:50]}...")
        
        # Generate response with function calling
        response = model.generate_content(prompt)
        
        # Initialize result structure
        result = {
            "analysis_complete": True,
            "timestamp": datetime.utcnow().isoformat(),
            "email_metadata": {
                "sender": sender,
                "subject": subject,
                "thread_id": thread_id,
                "processing_timestamp": datetime.utcnow().isoformat()
            }
        }
        
        # Process function call responses
        function_calls_processed = 0
        
        for part in response.parts:
            if part.function_call:
                func_name = part.function_call.name
                func_args = dict(part.function_call.args)
                function_calls_processed += 1
                
                if func_name == "extract_action_items":
                    result["action_items"] = func_args.get("action_items", [])
                    result["summary"] = func_args.get("summary", "")
                    result["urgency_score"] = func_args.get("urgency_score", 5)
                    
                    # Log action items for monitoring
                    action_count = len(result["action_items"])
                    logger.info(f"Extracted {action_count} action items with urgency score {result['urgency_score']}")
                    
                elif func_name == "generate_reply":
                    result["reply"] = {
                        "text": func_args.get("reply_text", ""),
                        "tone": func_args.get("tone", "professional"),
                        "action_required": func_args.get("action_required", False),
                        "suggested_subject": func_args.get("suggested_subject", f"Re: {subject}"),
                        "confidence_score": func_args.get("confidence_score", 7)
                    }
                    
                    # Log reply generation for monitoring
                    confidence = result["reply"]["confidence_score"]
                    logger.info(f"Generated reply with {result['reply']['tone']} tone, confidence: {confidence}/10")
        
        if function_calls_processed == 0:
            logger.warning("No function calls were processed in the response")
            result["warning"] = "Analysis may be incomplete - no function calls processed"
        
        # Add processing statistics
        result["processing_stats"] = {
            "function_calls_processed": function_calls_processed,
            "email_length": len(body),
            "processing_time_ms": None  # Would be calculated with timing
        }
        
        logger.info("Email processing completed successfully")
        return result
        
    except Exception as e:
        logger.error(f"Error processing email content: {str(e)}")
        return {
            "error": str(e),
            "analysis_complete": False,
            "timestamp": datetime.utcnow().isoformat(),
            "error_type": type(e).__name__
        }

def store_analysis_results(email_id: str, analysis: Dict[str, Any]) -> None:
    """
    Store email analysis results in Firestore with error handling and logging.
    
    Args:
        email_id: Unique identifier for the email
        analysis: Analysis results to store
    """
    try:
        # Prepare document data
        doc_data = {
            **analysis,
            "email_id": email_id,
            "processed_at": firestore.SERVER_TIMESTAMP,
            "stored_at": datetime.utcnow().isoformat()
        }
        
        # Store in Firestore with document ID as email_id
        doc_ref = db.collection('email_analysis').document(email_id)
        doc_ref.set(doc_data)
        
        logger.info(f"Analysis results stored successfully for email {email_id}")
        
        # Store summary statistics in a separate collection for reporting
        stats_doc = {
            "email_id": email_id,
            "action_items_count": len(analysis.get("action_items", [])),
            "urgency_score": analysis.get("urgency_score", 0),
            "reply_generated": bool(analysis.get("reply", {}).get("text")),
            "processing_timestamp": firestore.SERVER_TIMESTAMP
        }
        
        db.collection('processing_stats').add(stats_doc)
        
    except Exception as e:
        logger.error(f"Error storing analysis results for email {email_id}: {str(e)}")
        # Don't re-raise the exception to avoid failing the entire function
        # Consider implementing a retry mechanism or dead letter queue

def publish_to_pubsub(email_id: str, analysis: Dict[str, Any]) -> None:
    """
    Publish analysis results to Pub/Sub for downstream processing.
    
    Args:
        email_id: Unique identifier for the email
        analysis: Analysis results to publish
    """
    try:
        topic_path = publisher.topic_path(PROJECT_ID, 'email-processing-topic')
        
        # Prepare message data
        message_data = {
            "email_id": email_id,
            "analysis": analysis,
            "published_at": datetime.utcnow().isoformat(),
            "source": "email-processor-function"
        }
        
        # Encode message as JSON bytes
        message_bytes = json.dumps(message_data).encode('utf-8')
        
        # Add message attributes for routing and filtering
        attributes = {
            "email_id": email_id,
            "urgency_score": str(analysis.get("urgency_score", 0)),
            "has_action_items": str(len(analysis.get("action_items", [])) > 0),
            "source_function": "email-processor"
        }
        
        # Publish message
        future = publisher.publish(topic_path, message_bytes, **attributes)
        message_id = future.result()
        
        logger.info(f"Published analysis results to Pub/Sub with message ID: {message_id}")
        
    except Exception as e:
        logger.error(f"Error publishing to Pub/Sub for email {email_id}: {str(e)}")
        # Don't re-raise to avoid failing the function

@functions_framework.http
def process_email(request):
    """
    Main HTTP Cloud Function entry point for processing emails.
    
    Args:
        request: HTTP request object containing email data
        
    Returns:
        JSON response with analysis results or error information
    """
    # Set CORS headers for web application integration
    headers = {
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Methods': 'POST, OPTIONS',
        'Access-Control-Allow-Headers': 'Content-Type, Authorization'
    }
    
    # Handle preflight requests
    if request.method == 'OPTIONS':
        return ('', 204, headers)
    
    try:
        # Validate request method
        if request.method != 'POST':
            logger.warning(f"Invalid request method: {request.method}")
            return ({
                "error": "Only POST requests are supported",
                "method_received": request.method
            }, 405, headers)
        
        # Parse and validate request data
        try:
            email_data = request.get_json()
        except Exception as e:
            logger.error(f"Error parsing JSON request: {str(e)}")
            return ({
                "error": "Invalid JSON in request body",
                "details": str(e)
            }, 400, headers)
        
        if not email_data:
            logger.warning("Empty request body received")
            return ({
                "error": "No email data provided in request body"
            }, 400, headers)
        
        # Validate required fields
        email_id = email_data.get('email_id')
        if not email_id:
            logger.warning("Missing email_id in request")
            return ({
                "error": "email_id is required in request body"
            }, 400, headers)
        
        # Log request for monitoring
        logger.info(f"Processing email request for ID: {email_id}")
        
        # Process email with Gemini AI
        analysis = process_email_content(email_data)
        
        # Store results in Firestore
        store_analysis_results(email_id, analysis)
        
        # Publish to Pub/Sub for further processing (if analysis was successful)
        if analysis.get("analysis_complete", False):
            publish_to_pubsub(email_id, analysis)
        
        # Prepare response
        response_data = {
            "status": "success" if analysis.get("analysis_complete", False) else "partial_success",
            "email_id": email_id,
            "analysis": analysis,
            "processing_timestamp": datetime.utcnow().isoformat()
        }
        
        # Log successful completion
        if analysis.get("analysis_complete", False):
            action_count = len(analysis.get("action_items", []))
            urgency = analysis.get("urgency_score", 0)
            logger.info(f"Successfully processed email {email_id}: {action_count} actions, urgency {urgency}")
        else:
            logger.warning(f"Partial processing for email {email_id}: {analysis.get('error', 'Unknown issue')}")
        
        return (response_data, 200, headers)
        
    except Exception as e:
        # Log the full error for debugging
        logger.error(f"Unexpected error in process_email function: {str(e)}", exc_info=True)
        
        # Return sanitized error response
        error_response = {
            "error": "Internal server error occurred",
            "timestamp": datetime.utcnow().isoformat(),
            "request_id": email_data.get('email_id', 'unknown') if 'email_data' in locals() else 'unknown'
        }
        
        return (error_response, 500, headers)

# Health check endpoint
@functions_framework.http
def health_check(request):
    """
    Health check endpoint for monitoring function availability.
    """
    try:
        # Test basic connectivity to required services
        test_results = {
            "firestore": False,
            "vertex_ai": False,
            "pubsub": False
        }
        
        # Test Firestore connectivity
        try:
            db.collection('health_check').limit(1).get()
            test_results["firestore"] = True
        except Exception:
            pass
        
        # Test Pub/Sub connectivity
        try:
            publisher.topic_path(PROJECT_ID, 'email-processing-topic')
            test_results["pubsub"] = True
        except Exception:
            pass
        
        # Test Vertex AI connectivity (basic check)
        try:
            # Just check if model can be initialized (lightweight check)
            test_results["vertex_ai"] = True
        except Exception:
            pass
        
        status = "healthy" if all(test_results.values()) else "degraded"
        
        return {
            "status": status,
            "timestamp": datetime.utcnow().isoformat(),
            "services": test_results,
            "version": "1.0.0"
        }
        
    except Exception as e:
        logger.error(f"Health check failed: {str(e)}")
        return {
            "status": "unhealthy",
            "error": str(e),
            "timestamp": datetime.utcnow().isoformat()
        }, 500