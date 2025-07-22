# Cloud Functions Main Module Template
# This template provides HTTP endpoints for conversation processing

import os
import json
import uuid
import logging
from datetime import datetime
from flask import Flask, request, jsonify
from google.cloud import firestore
from google.cloud import storage
import functions_framework

# Import conversation agent
from agent_config import ConversationAgent

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Initialize global variables from environment
PROJECT_ID = "${project_id}"
REGION = "${region}"
FIRESTORE_DATABASE = "${firestore_database}"
BUCKET_NAME = "${bucket_name}"

# Initialize conversation agent
try:
    agent = ConversationAgent(PROJECT_ID, REGION, FIRESTORE_DATABASE)
    logger.info("Conversation agent initialized successfully")
except Exception as e:
    logger.error(f"Failed to initialize conversation agent: {str(e)}")
    agent = None

@functions_framework.http
def chat_processor(request):
    """
    HTTP Cloud Function for processing chat messages with Agent Development Kit.
    
    Expects POST requests with JSON body containing:
    - user_id: Unique identifier for the user
    - message: User's message content
    - session_id: Optional session identifier
    
    Returns:
    JSON response with generated reply and session information
    """
    
    # Handle CORS preflight requests
    if request.method == 'OPTIONS':
        headers = {
            'Access-Control-Allow-Origin': '*',
            'Access-Control-Allow-Methods': 'POST, GET, OPTIONS',
            'Access-Control-Allow-Headers': 'Content-Type, Authorization',
            'Access-Control-Max-Age': '3600'
        }
        return ('', 204, headers)
    
    # Set CORS headers for actual requests
    headers = {
        'Access-Control-Allow-Origin': '*',
        'Content-Type': 'application/json'
    }
    
    try:
        # Validate HTTP method
        if request.method != 'POST':
            logger.warning(f"Invalid method: {request.method}")
            return jsonify({
                'error': 'Method not allowed. Use POST.',
                'status': 'error'
            }), 405, headers
        
        # Check if agent is initialized
        if agent is None:
            logger.error("Conversation agent not initialized")
            return jsonify({
                'error': 'Service temporarily unavailable',
                'status': 'error'
            }), 503, headers
        
        # Parse and validate request data
        try:
            data = request.get_json(force=True)
        except Exception as e:
            logger.error(f"Invalid JSON in request: {str(e)}")
            return jsonify({
                'error': 'Invalid JSON format',
                'status': 'error'
            }), 400, headers
        
        # Validate required fields
        if not data:
            return jsonify({
                'error': 'Request body is required',
                'status': 'error'
            }), 400, headers
            
        user_id = data.get('user_id')
        message = data.get('message')
        
        if not user_id or not message:
            return jsonify({
                'error': 'Missing required fields: user_id and message',
                'status': 'error'
            }), 400, headers
        
        # Validate input lengths
        if len(user_id) > 100:
            return jsonify({
                'error': 'user_id too long (max 100 characters)',
                'status': 'error'
            }), 400, headers
            
        if len(message) > 5000:
            return jsonify({
                'error': 'message too long (max 5000 characters)',
                'status': 'error'
            }), 400, headers
        
        # Get or generate session ID
        session_id = data.get('session_id')
        if not session_id:
            session_id = str(uuid.uuid4())
        
        # Process conversation with agent
        logger.info(f"Processing conversation for user: {user_id[:8]}...")
        start_time = datetime.now()
        
        response = agent.process_conversation(user_id, message, session_id)
        
        processing_time = (datetime.now() - start_time).total_seconds()
        logger.info(f"Conversation processed in {processing_time:.2f} seconds")
        
        # Return successful response
        return jsonify({
            'response': response,
            'session_id': session_id,
            'timestamp': datetime.now().isoformat(),
            'processing_time': processing_time,
            'status': 'success'
        }), 200, headers
        
    except Exception as e:
        logger.error(f"Unexpected error in chat_processor: {str(e)}")
        return jsonify({
            'error': 'Internal server error',
            'status': 'error',
            'timestamp': datetime.now().isoformat()
        }), 500, headers

@functions_framework.http
def get_conversation_history(request):
    """
    HTTP Cloud Function for retrieving conversation history from Firestore.
    
    Expects GET requests with query parameter:
    - user_id: Unique identifier for the user
    - limit: Optional limit for number of messages (default: 50)
    
    Returns:
    JSON response with conversation history array
    """
    
    # Handle CORS preflight requests
    if request.method == 'OPTIONS':
        headers = {
            'Access-Control-Allow-Origin': '*',
            'Access-Control-Allow-Methods': 'GET, OPTIONS',
            'Access-Control-Allow-Headers': 'Content-Type, Authorization',
            'Access-Control-Max-Age': '3600'
        }
        return ('', 204, headers)
    
    # Set CORS headers
    headers = {
        'Access-Control-Allow-Origin': '*',
        'Content-Type': 'application/json'
    }
    
    try:
        # Validate HTTP method
        if request.method != 'GET':
            return jsonify({
                'error': 'Method not allowed. Use GET.',
                'status': 'error'
            }), 405, headers
        
        # Get and validate user_id parameter
        user_id = request.args.get('user_id')
        if not user_id:
            return jsonify({
                'error': 'user_id parameter is required',
                'status': 'error'
            }), 400, headers
        
        # Get optional limit parameter
        limit = request.args.get('limit', '50')
        try:
            limit = int(limit)
            if limit < 1 or limit > 100:
                limit = 50
        except ValueError:
            limit = 50
        
        # Initialize Firestore client
        firestore_client = firestore.Client(project=PROJECT_ID, database=FIRESTORE_DATABASE)
        
        # Retrieve conversation from Firestore
        conversation_ref = firestore_client.collection('conversations').document(user_id)
        conversation_doc = conversation_ref.get()
        
        if not conversation_doc.exists:
            logger.info(f"No conversation history found for user: {user_id[:8]}...")
            return jsonify({
                'messages': [],
                'user_id': user_id,
                'total_messages': 0,
                'status': 'success'
            }), 200, headers
        
        # Parse conversation data
        conversation_data = conversation_doc.to_dict()
        messages = conversation_data.get('messages', [])
        
        # Apply limit to messages (get most recent)
        if len(messages) > limit:
            messages = messages[-limit:]
        
        # Get user context for additional information
        user_context_ref = firestore_client.collection('user_contexts').document(user_id)
        user_context_doc = user_context_ref.get()
        user_context = user_context_doc.to_dict() if user_context_doc.exists else {}
        
        logger.info(f"Retrieved {len(messages)} messages for user: {user_id[:8]}...")
        
        return jsonify({
            'messages': messages,
            'user_id': user_id,
            'total_messages': len(conversation_data.get('messages', [])),
            'returned_messages': len(messages),
            'last_updated': conversation_data.get('last_updated').isoformat() if conversation_data.get('last_updated') else None,
            'user_context': {
                'total_conversations': user_context.get('total_conversations', 0),
                'first_interaction': user_context.get('first_interaction').isoformat() if user_context.get('first_interaction') else None
            },
            'status': 'success'
        }), 200, headers
        
    except Exception as e:
        logger.error(f"Error in get_conversation_history: {str(e)}")
        return jsonify({
            'error': 'Internal server error',
            'status': 'error',
            'timestamp': datetime.now().isoformat()
        }), 500, headers

@functions_framework.http
def health_check(request):
    """
    Health check endpoint for monitoring and load balancing.
    """
    headers = {
        'Access-Control-Allow-Origin': '*',
        'Content-Type': 'application/json'
    }
    
    try:
        # Basic health checks
        health_status = {
            'status': 'healthy',
            'timestamp': datetime.now().isoformat(),
            'service': 'conversational-ai-backend',
            'version': '1.0',
            'checks': {
                'agent_initialized': agent is not None,
                'firestore_connection': True,  # Assume healthy if no exception
                'environment_variables': {
                    'project_id': bool(PROJECT_ID),
                    'region': bool(REGION),
                    'firestore_database': bool(FIRESTORE_DATABASE),
                    'bucket_name': bool(BUCKET_NAME)
                }
            }
        }
        
        # Quick Firestore connectivity test
        try:
            firestore_client = firestore.Client(project=PROJECT_ID, database=FIRESTORE_DATABASE)
            # Simple collection list to test connectivity
            collections = list(firestore_client.collections())
            health_status['checks']['firestore_connection'] = True
        except Exception as e:
            logger.warning(f"Firestore health check failed: {str(e)}")
            health_status['checks']['firestore_connection'] = False
            health_status['status'] = 'degraded'
        
        # Determine overall status
        if not health_status['checks']['agent_initialized']:
            health_status['status'] = 'unhealthy'
        
        status_code = 200 if health_status['status'] == 'healthy' else 503
        
        return jsonify(health_status), status_code, headers
        
    except Exception as e:
        logger.error(f"Health check failed: {str(e)}")
        return jsonify({
            'status': 'unhealthy',
            'error': str(e),
            'timestamp': datetime.now().isoformat()
        }), 503, headers