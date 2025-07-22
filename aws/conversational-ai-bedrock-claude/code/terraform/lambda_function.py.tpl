import json
import boto3
import uuid
import time
import os
from datetime import datetime
import logging

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize AWS clients
bedrock_runtime = boto3.client('bedrock-runtime')
dynamodb = boto3.resource('dynamodb')

# Environment variables and configuration
TABLE_NAME = os.environ.get('TABLE_NAME', '${table_name}')
CLAUDE_MODEL_ID = os.environ.get('CLAUDE_MODEL_ID', '${claude_model_id}')
MAX_TOKENS = int(os.environ.get('MAX_TOKENS', '${max_tokens}'))
TEMPERATURE = float(os.environ.get('TEMPERATURE', '${temperature}'))
CONVERSATION_HISTORY_LIMIT = int(os.environ.get('CONVERSATION_HISTORY_LIMIT', '${conversation_history_limit}'))

# Initialize DynamoDB table
table = dynamodb.Table(TABLE_NAME)

def lambda_handler(event, context):
    """Main handler for conversational AI requests"""
    
    try:
        # Log the incoming event for debugging
        logger.info(f"Received event: {json.dumps(event, default=str)}")
        
        # Handle CORS preflight requests
        if event.get('httpMethod') == 'OPTIONS':
            return {
                'statusCode': 200,
                'headers': {
                    'Access-Control-Allow-Origin': '*',
                    'Access-Control-Allow-Methods': 'POST, OPTIONS',
                    'Access-Control-Allow-Headers': 'Content-Type, X-Amz-Date, Authorization, X-Api-Key, X-Amz-Security-Token'
                },
                'body': ''
            }
        
        # Parse request body from API Gateway
        body = json.loads(event.get('body', '{}'))
        user_message = body.get('message', '').strip()
        session_id = body.get('session_id', str(uuid.uuid4()))
        user_id = body.get('user_id', 'anonymous')
        
        # Validate required fields
        if not user_message:
            return create_error_response(400, 'Message is required and cannot be empty')
        
        # Get conversation history for context
        conversation_history = get_conversation_history(session_id)
        
        # Build prompt with conversation context
        messages = build_messages_with_context(user_message, conversation_history)
        
        # Call Bedrock Claude model for AI response
        response = invoke_claude_model(messages)
        
        # Save this conversation turn to DynamoDB
        save_conversation_turn(session_id, user_id, user_message, response)
        
        # Return successful response
        return {
            'statusCode': 200,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*',
                'Access-Control-Allow-Methods': 'POST, OPTIONS',
                'Access-Control-Allow-Headers': 'Content-Type, X-Amz-Date, Authorization, X-Api-Key, X-Amz-Security-Token'
            },
            'body': json.dumps({
                'response': response,
                'session_id': session_id,
                'timestamp': datetime.utcnow().isoformat(),
                'model_id': CLAUDE_MODEL_ID,
                'user_id': user_id
            })
        }
        
    except Exception as e:
        logger.error(f"Error processing request: {str(e)}", exc_info=True)
        return create_error_response(500, 'Internal server error')

def create_error_response(status_code, error_message):
    """Create standardized error response"""
    return {
        'statusCode': status_code,
        'headers': {
            'Content-Type': 'application/json',
            'Access-Control-Allow-Origin': '*'
        },
        'body': json.dumps({
            'error': error_message,
            'timestamp': datetime.utcnow().isoformat()
        })
    }

def get_conversation_history(session_id, limit=None):
    """Retrieve recent conversation history for context"""
    
    if limit is None:
        limit = CONVERSATION_HISTORY_LIMIT
    
    try:
        logger.info(f"Retrieving conversation history for session: {session_id}")
        
        response = table.query(
            KeyConditionExpression='session_id = :session_id',
            ExpressionAttributeValues={':session_id': session_id},
            ScanIndexForward=False,  # Most recent first
            Limit=limit * 2  # Get both user and assistant messages
        )
        
        # Format conversation history
        history = []
        for item in reversed(response['Items']):
            history.append({
                'role': item['role'],
                'content': item['content']
            })
        
        # Limit to specified number of turns
        return history[-limit:] if len(history) > limit else history
        
    except Exception as e:
        logger.error(f"Error retrieving conversation history: {str(e)}")
        return []

def build_messages_with_context(user_message, conversation_history):
    """Build Claude messages array with conversation context"""
    
    # System prompt defines the AI's behavior and personality
    system_prompt = """You are a helpful AI assistant powered by Claude. You provide accurate, helpful, and engaging responses to user questions. You maintain context from previous messages in the conversation and provide personalized assistance. Be concise but thorough in your responses."""
    
    # Start with system message
    messages = [{"role": "system", "content": system_prompt}]
    
    # Add conversation history for context
    for turn in conversation_history:
        if turn['role'] in ['user', 'assistant']:
            messages.append({
                "role": turn['role'],
                "content": turn['content']
            })
    
    # Add current user message
    messages.append({
        "role": "user",
        "content": user_message
    })
    
    return messages

def invoke_claude_model(messages):
    """Invoke Claude model through Bedrock"""
    
    try:
        logger.info(f"Invoking Claude model: {CLAUDE_MODEL_ID}")
        
        # Prepare request body for Claude API format
        # Extract system message if present
        system_message = None
        conversation_messages = []
        
        for msg in messages:
            if msg["role"] == "system":
                system_message = msg["content"]
            else:
                conversation_messages.append(msg)
        
        request_body = {
            "anthropic_version": "bedrock-2023-05-31",
            "max_tokens": MAX_TOKENS,
            "temperature": TEMPERATURE,
            "messages": conversation_messages
        }
        
        # Add system message if present
        if system_message:
            request_body["system"] = system_message
        
        logger.info(f"Request body: {json.dumps(request_body, indent=2)}")
        
        # Invoke model through Bedrock Runtime
        response = bedrock_runtime.invoke_model(
            modelId=CLAUDE_MODEL_ID,
            body=json.dumps(request_body),
            contentType='application/json'
        )
        
        # Parse response
        response_body = json.loads(response['body'].read())
        logger.info(f"Claude response: {json.dumps(response_body, indent=2)}")
        
        # Extract text from Claude response
        if 'content' in response_body and len(response_body['content']) > 0:
            return response_body['content'][0]['text']
        else:
            logger.warning("No content in Claude response")
            return "I apologize, but I couldn't generate a response. Please try again."
            
    except Exception as e:
        logger.error(f"Error invoking Claude model: {str(e)}", exc_info=True)
        return "I'm experiencing technical difficulties. Please try again later."

def save_conversation_turn(session_id, user_id, user_message, assistant_response):
    """Save conversation turn to DynamoDB"""
    
    try:
        timestamp = int(time.time() * 1000)  # Milliseconds for better sorting
        current_time = datetime.utcnow().isoformat()
        
        logger.info(f"Saving conversation turn for session: {session_id}")
        
        # Save user message
        table.put_item(
            Item={
                'session_id': session_id,
                'timestamp': timestamp,
                'role': 'user',
                'content': user_message,
                'user_id': user_id,
                'created_at': current_time,
                'model_id': CLAUDE_MODEL_ID
            }
        )
        
        # Save assistant response
        table.put_item(
            Item={
                'session_id': session_id,
                'timestamp': timestamp + 1,  # Ensure assistant response comes after user message
                'role': 'assistant',
                'content': assistant_response,
                'user_id': user_id,
                'created_at': current_time,
                'model_id': CLAUDE_MODEL_ID
            }
        )
        
        logger.info(f"Successfully saved conversation turn for session {session_id}")
        
    except Exception as e:
        logger.error(f"Error saving conversation: {str(e)}", exc_info=True)
        # Don't raise exception here to avoid failing the whole request
        # Conversation saving is important but not critical for user experience