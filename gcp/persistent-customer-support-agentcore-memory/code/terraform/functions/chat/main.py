# AI Chat Cloud Function with Memory Integration
# Main support chat function using Vertex AI Gemini with conversation memory

import functions_framework
from google.cloud import firestore
import vertexai
from vertexai.generative_models import GenerativeModel, GenerationConfig
import json
import requests
import os
from flask import Request
from datetime import datetime
from typing import Dict, List, Any, Optional

# Initialize Vertex AI
PROJECT_ID = "${project_id}"
REGION = "${region}"
MODEL_NAME = "${model_name}"
MAX_OUTPUT_TOKENS = ${max_output_tokens}
TEMPERATURE = ${temperature}
TOP_P = ${top_p}

vertexai.init(project=PROJECT_ID, location=REGION)

# Initialize Firestore client
db = firestore.Client(project=PROJECT_ID)

# Initialize Vertex AI model
model = GenerativeModel(MODEL_NAME)

@functions_framework.http
def support_chat(request: Request):
    """
    Main support chat function with memory integration.
    
    This function orchestrates the AI customer support workflow:
    1. Retrieves conversation memory for context
    2. Generates AI response using Vertex AI Gemini
    3. Stores new conversation in Firestore
    
    Args:
        request: HTTP request containing customer_id and message in JSON body
        
    Returns:
        JSON response with AI-generated response and conversation metadata
    """
    
    # Handle CORS preflight requests
    if request.method == 'OPTIONS':
        headers = {
            'Access-Control-Allow-Origin': '*',
            'Access-Control-Allow-Methods': 'POST, OPTIONS',
            'Access-Control-Allow-Headers': 'Content-Type, Authorization',
            'Access-Control-Max-Age': '3600'
        }
        return ('', 204, headers)
    
    # Set CORS headers for main request
    headers = {
        'Access-Control-Allow-Origin': '*',
        'Content-Type': 'application/json'
    }
    
    try:
        # Parse and validate request
        if not request.is_json:
            return ({'error': 'Request must be JSON'}, 400, headers)
        
        request_json = request.get_json(silent=True)
        if not request_json:
            return ({'error': 'Invalid JSON in request'}, 400, headers)
        
        customer_id = request_json.get('customer_id')
        message = request_json.get('message')
        
        if not customer_id or not message:
            return ({'error': 'Both customer_id and message are required'}, 400, headers)
        
        # Validate inputs
        if not isinstance(customer_id, str) or not isinstance(message, str):
            return ({'error': 'customer_id and message must be strings'}, 400, headers)
        
        customer_id = customer_id.strip()
        message = message.strip()
        
        if len(customer_id) == 0 or len(message) == 0:
            return ({'error': 'customer_id and message cannot be empty'}, 400, headers)
        
        if len(message) > 2000:
            return ({'error': 'Message too long (max 2000 characters)'}, 400, headers)
        
        # Retrieve conversation memory
        memory_data = {}
        memory_context_used = False
        
        try:
            memory_url = os.environ.get('RETRIEVE_MEMORY_URL')
            if memory_url:
                memory_response = requests.post(
                    memory_url,
                    json={'customer_id': customer_id},
                    timeout=30,
                    headers={'Content-Type': 'application/json'}
                )
                
                if memory_response.status_code == 200:
                    memory_data = memory_response.json()
                    memory_context_used = True
                    print(f"Retrieved memory context for customer {customer_id}")
                else:
                    print(f"Failed to retrieve memory: {memory_response.status_code}")
            else:
                print("RETRIEVE_MEMORY_URL not configured")
                
        except Exception as memory_error:
            print(f"Error retrieving memory: {memory_error}")
            # Continue without memory context rather than failing
            memory_data = {}
            memory_context_used = False
        
        # Build context-aware prompt
        system_prompt = build_system_prompt(memory_data)
        user_prompt = f"Customer message: {message}"
        
        # Generate AI response using Vertex AI
        ai_response = generate_ai_response(system_prompt, user_prompt)
        
        # Store conversation in Firestore
        conversation_id = store_conversation(
            customer_id, 
            message, 
            ai_response, 
            memory_data.get('context', {}),
            memory_context_used
        )
        
        # Prepare response
        response_data = {
            'conversation_id': conversation_id,
            'customer_id': customer_id,
            'message': message,
            'ai_response': ai_response,
            'memory_context_used': memory_context_used,
            'timestamp': datetime.now().isoformat(),
            'model_used': MODEL_NAME,
            'response_length': len(ai_response),
            'success': True
        }
        
        return (response_data, 200, headers)
        
    except Exception as e:
        error_message = f"Internal server error: {str(e)}"
        print(f"Error in support_chat: {error_message}")
        return ({
            'error': 'Internal server error', 
            'details': str(e),
            'success': False,
            'timestamp': datetime.now().isoformat()
        }, 500, headers)

def build_system_prompt(memory_data: Dict[str, Any]) -> str:
    """
    Build context-aware system prompt using memory data.
    
    Args:
        memory_data: Dictionary containing customer conversation history and context
        
    Returns:
        String containing the complete system prompt for the AI model
    """
    
    base_prompt = """You are a helpful and professional customer support agent. You provide empathetic, solution-focused responses to customer inquiries. 

Key guidelines:
- Be professional, friendly, and helpful
- Provide clear and actionable solutions when possible
- Ask clarifying questions if you need more information
- Acknowledge the customer's concerns and show empathy
- If you cannot resolve an issue, guide the customer to appropriate resources
- Keep responses concise but comprehensive
- Use a warm, conversational tone

"""
    
    if memory_data and memory_data.get('conversations'):
        context = memory_data.get('context', {})
        conversations = memory_data.get('conversations', [])
        
        # Add customer context section
        base_prompt += f"""
CUSTOMER CONTEXT:
- Previous conversations: {context.get('total_conversations', 0)}
- Unresolved issues: {context.get('unresolved_issues', 0)}
- Interaction frequency: {context.get('interaction_frequency', 'unknown')}
- Satisfaction trend: {context.get('satisfaction_trend', 'neutral')}
- Common issue types: {', '.join(context.get('common_issues', [])[:3])}

RECENT CONVERSATION HISTORY:
"""
        
        # Add recent conversation snippets
        for i, conv in enumerate(conversations[:3], 1):
            message_preview = conv.get('message', '')[:100]
            response_preview = conv.get('response', '')[:100]
            
            if len(conv.get('message', '')) > 100:
                message_preview += "..."
            if len(conv.get('response', '')) > 100:
                response_preview += "..."
                
            base_prompt += f"""
{i}. Customer: "{message_preview}"
   Previous Response: "{response_preview}"
   Status: {'Resolved' if conv.get('resolved', False) else 'Unresolved'}
"""
        
        base_prompt += """
Use this context to provide personalized and relevant responses. Reference previous conversations when appropriate, but don't assume the customer remembers all details.

"""
    
    base_prompt += """
CURRENT CONVERSATION:
Please respond to the following customer message:

"""
    
    return base_prompt

def generate_ai_response(system_prompt: str, user_prompt: str) -> str:
    """
    Generate AI response using Vertex AI Gemini model.
    
    Args:
        system_prompt: System prompt containing context and instructions
        user_prompt: User's message to respond to
        
    Returns:
        Generated AI response string
    """
    
    try:
        # Combine prompts
        full_prompt = f"{system_prompt}\n{user_prompt}"
        
        # Configure generation parameters
        generation_config = GenerationConfig(
            max_output_tokens=MAX_OUTPUT_TOKENS,
            temperature=TEMPERATURE,
            top_p=TOP_P,
            top_k=40,  # Add some diversity control
        )
        
        # Generate response
        response = model.generate_content(
            full_prompt,
            generation_config=generation_config
        )
        
        # Extract and validate response text
        if response and response.text:
            response_text = response.text.strip()
            
            # Basic response validation and cleanup
            if len(response_text) == 0:
                return get_fallback_response("empty_response")
            
            # Remove any potential harmful content markers
            response_text = clean_response_text(response_text)
            
            return response_text
        else:
            return get_fallback_response("no_response")
            
    except Exception as e:
        print(f"Error generating AI response: {e}")
        return get_fallback_response("generation_error", str(e))

def clean_response_text(text: str) -> str:
    """
    Clean and validate the AI response text.
    
    Args:
        text: Raw response text from AI model
        
    Returns:
        Cleaned response text
    """
    
    # Remove excessive whitespace
    text = ' '.join(text.split())
    
    # Ensure response is not too long
    if len(text) > 1500:
        # Truncate at last complete sentence before limit
        truncated = text[:1500]
        last_period = truncated.rfind('.')
        if last_period > 1000:  # Only truncate if we have a reasonable amount of text
            text = truncated[:last_period + 1]
        else:
            text = truncated + "..."
    
    return text

def get_fallback_response(error_type: str, error_details: str = "") -> str:
    """
    Generate fallback responses for error conditions.
    
    Args:
        error_type: Type of error encountered
        error_details: Additional error details
        
    Returns:
        Appropriate fallback response
    """
    
    fallback_responses = {
        "empty_response": "I apologize, but I'm having trouble generating a response right now. Could you please rephrase your question or try again?",
        "no_response": "I'm experiencing a technical issue and cannot generate a proper response at the moment. Please try again or contact our support team directly.",
        "generation_error": "I apologize for the technical difficulty. Our AI system is temporarily unavailable, but I'd be happy to help you another way. Please try again in a few moments or contact our support team.",
        "timeout": "The response is taking longer than expected. Please try again with a shorter message or contact our support team for immediate assistance.",
        "default": "I apologize, but I'm experiencing technical difficulties. Please try again or contact our support team directly for assistance."
    }
    
    base_response = fallback_responses.get(error_type, fallback_responses["default"])
    
    if error_details and len(error_details) < 100:
        return f"{base_response} (Technical details: {error_details})"
    else:
        return base_response

def store_conversation(
    customer_id: str, 
    message: str, 
    response: str, 
    context: Dict[str, Any],
    memory_context_used: bool
) -> Optional[str]:
    """
    Store conversation in Firestore.
    
    Args:
        customer_id: Customer identifier
        message: Customer's message
        response: AI-generated response
        context: Customer context from memory retrieval
        memory_context_used: Whether memory context was used
        
    Returns:
        Document ID of stored conversation, or None if storage failed
    """
    
    try:
        # Prepare conversation data
        conversation_data = {
            'customer_id': customer_id,
            'message': message,
            'response': response,
            'timestamp': datetime.now(),
            'context_used': context,
            'memory_context_available': memory_context_used,
            'resolved': False,  # Can be updated later through additional endpoints
            'sentiment': 'neutral',  # Can be enhanced with sentiment analysis
            'model_used': MODEL_NAME,
            'response_length': len(response),
            'message_length': len(message),
            'session_id': None,  # Can be enhanced with session tracking
            'channel': 'api',  # Source channel for the conversation
            'priority': 'normal',  # Can be determined based on content analysis
            'created_by': 'ai_system',
            'updated_at': datetime.now()
        }
        
        # Add conversation to Firestore
        doc_ref = db.collection('conversations').add(conversation_data)
        document_id = doc_ref[1].id
        
        print(f"Conversation stored with ID: {document_id}")
        return document_id
        
    except Exception as e:
        print(f"Error storing conversation: {e}")
        return None

if __name__ == "__main__":
    # For local testing
    print("AI Chat function initialized")
    print(f"Project: {PROJECT_ID}")
    print(f"Region: {REGION}")
    print(f"Model: {MODEL_NAME}")
    print(f"Configuration: temp={TEMPERATURE}, top_p={TOP_P}, max_tokens={MAX_OUTPUT_TOKENS}")