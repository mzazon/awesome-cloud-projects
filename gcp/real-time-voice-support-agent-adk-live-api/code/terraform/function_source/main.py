import functions_framework
import json
import logging
import os
from agent_src.voice_agent import create_live_streaming_agent, create_voice_support_agent

# Configure logging based on environment variable
log_level = os.environ.get('LOG_LEVEL', '${log_level}')
logging.basicConfig(level=getattr(logging, log_level.upper()))
logger = logging.getLogger(__name__)

# Configuration from Terraform template variables
PROJECT_ID = os.environ.get('PROJECT_ID', '${project_id}')
REGION = os.environ.get('REGION', '${region}')
GEMINI_MODEL = os.environ.get('GEMINI_MODEL', '${gemini_model}')
VOICE_NAME = os.environ.get('VOICE_NAME', '${voice_name}')
LANGUAGE_CODE = os.environ.get('LANGUAGE_CODE', '${language_code}')

# Feature flags from Terraform variables
CUSTOMER_DB_ENABLED = os.environ.get('CUSTOMER_DATABASE_ENABLED', '${customer_db_enabled}').lower() == 'true'
KNOWLEDGE_ENABLED = os.environ.get('KNOWLEDGE_BASE_ENABLED', '${knowledge_enabled}').lower() == 'true'
TICKET_ENABLED = os.environ.get('TICKET_SYSTEM_ENABLED', '${ticket_enabled}').lower() == 'true'

@functions_framework.http
def voice_support_endpoint(request):
    """HTTP endpoint for voice support agent interactions."""
    try:
        # Handle CORS for web clients
        if request.method == 'OPTIONS':
            headers = {
                'Access-Control-Allow-Origin': '*',
                'Access-Control-Allow-Methods': 'GET, POST',
                'Access-Control-Allow-Headers': 'Content-Type, Authorization',
                'Access-Control-Max-Age': '3600'
            }
            return ('', 204, headers)
        
        # Process voice agent request
        if request.method == 'POST':
            request_data = request.get_json(silent=True)
            
            if not request_data:
                return {'error': 'No JSON data provided'}, 400
            
            # Handle different interaction types
            interaction_type = request_data.get('type', 'text')
            
            if interaction_type == 'voice_start':
                # Initialize voice session
                session_id = request_data.get('session_id')
                logger.info(f"Starting voice session: {session_id}")
                
                # Get available capabilities based on feature flags
                capabilities = []
                if CUSTOMER_DB_ENABLED:
                    capabilities.append('customer_lookup')
                if TICKET_ENABLED:
                    capabilities.append('ticket_creation')
                if KNOWLEDGE_ENABLED:
                    capabilities.append('knowledge_search')
                
                response = {
                    'status': 'voice_session_ready',
                    'session_id': session_id,
                    'websocket_url': f'/voice-stream/{session_id}',
                    'agent_capabilities': capabilities,
                    'configuration': {
                        'model': GEMINI_MODEL,
                        'voice': VOICE_NAME,
                        'language': LANGUAGE_CODE
                    }
                }
                
            elif interaction_type == 'text':
                # Handle text-based interaction for testing
                message = request_data.get('message', '')
                customer_context = request_data.get('customer_context', {})
                
                logger.info(f"Processing text message: {message[:100]}...")
                
                # Initialize agent for text processing
                try:
                    voice_support_agent = create_voice_support_agent()
                    
                    # Process the message (simplified for demonstration)
                    agent_response = f"I received your message: '{message}'. I'm ready to help with your customer service needs."
                    
                    # Add context-aware responses based on message content
                    if "customer" in message.lower() and "12345" in message:
                        agent_response += " I can look up customer 12345 for you."
                    elif "ticket" in message.lower():
                        agent_response += " I can help create a support ticket for your issue."
                    elif "help" in message.lower():
                        agent_response += " I'm here to assist with account issues, billing questions, and technical support."
                    
                    response = {
                        'status': 'success',
                        'response': agent_response,
                        'session_context': customer_context,
                        'capabilities_used': []
                    }
                    
                except Exception as e:
                    logger.error(f"Error processing text message: {str(e)}")
                    response = {
                        'status': 'error',
                        'error': 'Failed to process message',
                        'details': str(e)
                    }
                
            else:
                response = {'error': f'Unsupported interaction type: {interaction_type}'}, 400
        
        else:
            # Health check endpoint
            response = {
                'status': 'Voice Support Agent Ready',
                'agent_name': 'VoiceSupportAgent',
                'configuration': {
                    'project_id': PROJECT_ID,
                    'region': REGION,
                    'model': GEMINI_MODEL,
                    'voice': VOICE_NAME,
                    'language': LANGUAGE_CODE
                },
                'capabilities': {
                    'voice_streaming': True,
                    'customer_service': True,
                    'real_time_response': True,
                    'customer_lookup': CUSTOMER_DB_ENABLED,
                    'ticket_creation': TICKET_ENABLED,
                    'knowledge_search': KNOWLEDGE_ENABLED
                },
                'adk_version': '1.8.0',
                'function_version': '1.0'
            }
        
        headers = {
            'Access-Control-Allow-Origin': '*',
            'Content-Type': 'application/json'
        }
        
        return (json.dumps(response), 200, headers)
        
    except Exception as e:
        logger.error(f"Error processing request: {str(e)}")
        return {
            'error': 'Internal server error', 
            'details': str(e),
            'request_id': request.headers.get('X-Cloud-Trace-Context', 'unknown')
        }, 500

@functions_framework.http  
def voice_stream_handler(request):
    """Simplified voice streaming handler for WebSocket-like functionality."""
    try:
        logger.info("Voice streaming session requested")
        
        # In a real implementation, this would handle WebSocket connections
        # For now, return configuration for client-side streaming setup
        return {
            'status': 'Voice streaming ready',
            'message': 'WebSocket streaming configuration',
            'streaming_config': {
                'protocol': 'WebSocket',
                'audio_format': 'LINEAR16',
                'sample_rate': 24000,
                'chunk_size': 4096
            },
            'implementation_note': 'Full WebSocket streaming requires additional infrastructure setup'
        }
        
    except Exception as e:
        logger.error(f"WebSocket error: {str(e)}")
        return {'error': f"Streaming error: {str(e)}"}, 500