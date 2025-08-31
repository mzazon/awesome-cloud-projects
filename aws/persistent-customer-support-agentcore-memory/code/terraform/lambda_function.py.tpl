"""
Customer Support Agent Lambda Function
Recipe: Persistent Customer Support Agent with Bedrock AgentCore Memory

This Lambda function serves as the central processing unit for customer support
interactions, integrating with AgentCore Memory to maintain context and
leveraging Bedrock foundation models for intelligent responses.

Dependencies:
- boto3 (AWS SDK for Python)
- json (built-in)
- os (built-in)
- datetime (built-in)

Environment Variables:
- MEMORY_ID: Bedrock AgentCore Memory ID
- DDB_TABLE_NAME: DynamoDB table name for customer data
- BEDROCK_MODEL_ID: Bedrock foundation model ID
"""

import json
import boto3
import os
from datetime import datetime
from typing import Dict, List, Any, Optional

# Initialize AWS clients
bedrock_agentcore = boto3.client('bedrock-agentcore')
bedrock_runtime = boto3.client('bedrock-runtime')
dynamodb = boto3.resource('dynamodb')

# Configuration
BEDROCK_MODEL_ID = os.environ.get('BEDROCK_MODEL_ID', '${bedrock_model_id}')
MEMORY_ID = os.environ['MEMORY_ID']
DDB_TABLE_NAME = os.environ['DDB_TABLE_NAME']
MAX_TOKENS = 500
DEFAULT_TIMEOUT = 30


def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Main Lambda handler for customer support interactions.
    
    Args:
        event: API Gateway event containing customer request
        context: Lambda runtime context
        
    Returns:
        API Gateway response with AI-generated support response
    """
    try:
        # Parse incoming request
        body = parse_request_body(event)
        
        # Validate required fields
        customer_id = body.get('customerId')
        message = body.get('message')
        
        if not customer_id or not message:
            return create_error_response(400, "Missing required fields: customerId and message")
        
        # Generate session ID if not provided
        session_id = body.get('sessionId', f"session-{customer_id}-{int(datetime.now().timestamp())}")
        
        # Retrieve customer context from DynamoDB
        table = dynamodb.Table(DDB_TABLE_NAME)
        customer_data = get_customer_data(table, customer_id)
        
        # Retrieve relevant memories from AgentCore
        memory_context = retrieve_memory_context(customer_id, message)
        
        # Generate AI response using Bedrock
        ai_response = generate_support_response(message, memory_context, customer_data)
        
        # Store interaction in AgentCore Memory
        store_interaction(customer_id, session_id, message, ai_response)
        
        # Update customer data if metadata provided
        metadata = body.get('metadata', {})
        if metadata:
            update_customer_data(table, customer_id, metadata)
        
        # Return successful response
        return create_success_response({
            'response': ai_response,
            'sessionId': session_id,
            'customerId': customer_id,
            'timestamp': datetime.now().isoformat()
        })
        
    except ValueError as e:
        print(f"Validation error: {str(e)}")
        return create_error_response(400, f"Invalid request: {str(e)}")
    
    except Exception as e:
        print(f"Unexpected error: {str(e)}")
        return create_error_response(500, "Internal server error")


def parse_request_body(event: Dict[str, Any]) -> Dict[str, Any]:
    """
    Parse and validate the request body from API Gateway event.
    
    Args:
        event: API Gateway event
        
    Returns:
        Parsed request body as dictionary
        
    Raises:
        ValueError: If request body is invalid or missing
    """
    # Handle direct invocation vs API Gateway
    if 'body' in event:
        if event['body'] is None:
            raise ValueError("Request body is empty")
        
        if isinstance(event['body'], str):
            try:
                return json.loads(event['body'])
            except json.JSONDecodeError:
                raise ValueError("Invalid JSON in request body")
        else:
            return event['body']
    else:
        # Direct invocation
        return event


def get_customer_data(table: Any, customer_id: str) -> Dict[str, Any]:
    """
    Retrieve customer data from DynamoDB.
    
    Args:
        table: DynamoDB table resource
        customer_id: Customer identifier
        
    Returns:
        Customer data dictionary (empty if not found)
    """
    try:
        response = table.get_item(Key={'customerId': customer_id})
        customer_data = response.get('Item', {})
        
        # Convert DynamoDB types to standard Python types
        return convert_dynamodb_item(customer_data)
        
    except Exception as e:
        print(f"Error retrieving customer data for {customer_id}: {e}")
        return {}


def convert_dynamodb_item(item: Dict[str, Any]) -> Dict[str, Any]:
    """
    Convert DynamoDB item format to standard dictionary.
    
    Args:
        item: DynamoDB item with type descriptors
        
    Returns:
        Standard dictionary with converted values
    """
    if not item:
        return {}
    
    converted = {}
    for key, value in item.items():
        if isinstance(value, dict):
            # Handle DynamoDB type descriptors
            if 'S' in value:  # String
                converted[key] = value['S']
            elif 'N' in value:  # Number
                converted[key] = float(value['N']) if '.' in value['N'] else int(value['N'])
            elif 'SS' in value:  # String Set
                converted[key] = list(value['SS'])
            elif 'NS' in value:  # Number Set
                converted[key] = [float(n) if '.' in n else int(n) for n in value['NS']]
            elif 'BOOL' in value:  # Boolean
                converted[key] = value['BOOL']
            else:
                converted[key] = value
        else:
            # Already converted or direct value
            converted[key] = value
    
    return converted


def retrieve_memory_context(customer_id: str, query: str) -> List[str]:
    """
    Retrieve relevant conversation context from AgentCore Memory.
    
    Args:
        customer_id: Customer identifier for filtering
        query: Current customer query for semantic search
        
    Returns:
        List of relevant memory context strings
    """
    try:
        response = bedrock_agentcore.retrieve_memory_records(
            memoryId=MEMORY_ID,
            query=query,
            filter={'customerId': customer_id},
            maxResults=5
        )
        
        # Extract content from memory records
        memory_records = response.get('memoryRecords', [])
        return [record.get('content', '') for record in memory_records if record.get('content')]
        
    except Exception as e:
        print(f"Error retrieving memory context for {customer_id}: {e}")
        return []


def generate_support_response(message: str, memory_context: List[str], customer_data: Dict[str, Any]) -> str:
    """
    Generate AI-powered support response using Bedrock.
    
    Args:
        message: Customer's current message
        memory_context: Relevant conversation history
        customer_data: Customer profile information
        
    Returns:
        AI-generated support response
    """
    try:
        # Prepare context for AI model
        context_parts = [
            "You are a helpful customer support agent. Provide personalized, empathetic responses.",
            f"Customer query: {message}"
        ]
        
        # Add memory context if available
        if memory_context:
            context_parts.append(f"Previous interactions: {'; '.join(memory_context)}")
        
        # Add customer profile context
        if customer_data:
            profile_info = []
            if customer_data.get('name'):
                profile_info.append(f"Customer name: {customer_data['name']}")
            if customer_data.get('supportTier'):
                profile_info.append(f"Support tier: {customer_data['supportTier']}")
            if customer_data.get('productInterests'):
                profile_info.append(f"Product interests: {', '.join(customer_data['productInterests'])}")
            if customer_data.get('preferredChannel'):
                profile_info.append(f"Preferred channel: {customer_data['preferredChannel']}")
            
            if profile_info:
                context_parts.append(f"Customer profile: {'; '.join(profile_info)}")
        
        context_parts.append(
            "Provide a helpful, professional response. Reference past interactions when relevant. "
            "Be empathetic and focus on solving the customer's issue."
        )
        
        context = "\n\n".join(context_parts)
        
        # Prepare request for Bedrock model
        request_body = {
            'anthropic_version': 'bedrock-2023-05-31',
            'max_tokens': MAX_TOKENS,
            'messages': [
                {
                    'role': 'user',
                    'content': context
                }
            ]
        }
        
        # Invoke Bedrock model
        response = bedrock_runtime.invoke_model(
            modelId=BEDROCK_MODEL_ID,
            body=json.dumps(request_body)
        )
        
        # Parse response
        result = json.loads(response['body'].read())
        
        # Extract text content based on model type
        if 'content' in result and result['content']:
            return result['content'][0].get('text', '')
        elif 'completion' in result:
            return result['completion']
        else:
            return "I apologize, but I'm having trouble generating a response right now. Please try again."
        
    except Exception as e:
        print(f"Error generating support response: {e}")
        return "I apologize, but I'm experiencing technical difficulties. Please try again or contact our support team directly."


def store_interaction(customer_id: str, session_id: str, user_message: str, agent_response: str) -> None:
    """
    Store conversation interaction in AgentCore Memory.
    
    Args:
        customer_id: Customer identifier
        session_id: Session identifier
        user_message: Customer's message
        agent_response: Agent's response
    """
    timestamp = datetime.now().isoformat()
    
    try:
        # Store user message
        bedrock_agentcore.create_event(
            memoryId=MEMORY_ID,
            sessionId=session_id,
            eventData={
                'type': 'user_message',
                'customerId': customer_id,
                'content': user_message,
                'timestamp': timestamp,
                'metadata': {
                    'messageType': 'customer_query',
                    'processed': True
                }
            }
        )
        
        # Store agent response
        bedrock_agentcore.create_event(
            memoryId=MEMORY_ID,
            sessionId=session_id,
            eventData={
                'type': 'agent_response',
                'customerId': customer_id,
                'content': agent_response,
                'timestamp': timestamp,
                'metadata': {
                    'messageType': 'agent_reply',
                    'modelId': BEDROCK_MODEL_ID,
                    'processed': True
                }
            }
        )
        
        print(f"Stored interaction for customer {customer_id} in session {session_id}")
        
    except Exception as e:
        print(f"Error storing interaction for {customer_id}: {e}")
        # Don't raise exception - this shouldn't fail the main request


def update_customer_data(table: Any, customer_id: str, metadata: Dict[str, Any]) -> None:
    """
    Update customer data in DynamoDB with new metadata.
    
    Args:
        table: DynamoDB table resource
        customer_id: Customer identifier
        metadata: Additional metadata to store
    """
    try:
        # Prepare update item
        update_item = {
            'customerId': customer_id,
            'lastInteraction': datetime.now().isoformat()
        }
        
        # Add safe metadata fields
        safe_fields = ['userAgent', 'sessionLocation', 'device', 'channel']
        for field in safe_fields:
            if field in metadata:
                update_item[field] = metadata[field]
        
        # Update DynamoDB item
        table.put_item(Item=update_item)
        
        print(f"Updated customer data for {customer_id}")
        
    except Exception as e:
        print(f"Error updating customer data for {customer_id}: {e}")
        # Don't raise exception - this shouldn't fail the main request


def create_success_response(data: Dict[str, Any]) -> Dict[str, Any]:
    """
    Create successful API Gateway response.
    
    Args:
        data: Response data
        
    Returns:
        API Gateway response dictionary
    """
    return {
        'statusCode': 200,
        'headers': {
            'Content-Type': 'application/json',
            'Access-Control-Allow-Origin': '*',
            'Access-Control-Allow-Headers': 'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token',
            'Access-Control-Allow-Methods': 'POST,OPTIONS'
        },
        'body': json.dumps(data, default=str)
    }


def create_error_response(status_code: int, message: str) -> Dict[str, Any]:
    """
    Create error API Gateway response.
    
    Args:
        status_code: HTTP status code
        message: Error message
        
    Returns:
        API Gateway error response dictionary
    """
    return {
        'statusCode': status_code,
        'headers': {
            'Content-Type': 'application/json',
            'Access-Control-Allow-Origin': '*',
            'Access-Control-Allow-Headers': 'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token',
            'Access-Control-Allow-Methods': 'POST,OPTIONS'
        },
        'body': json.dumps({
            'error': message,
            'timestamp': datetime.now().isoformat()
        })
    }


# Additional utility functions for enhanced functionality

def validate_customer_id(customer_id: str) -> bool:
    """
    Validate customer ID format.
    
    Args:
        customer_id: Customer identifier to validate
        
    Returns:
        True if valid, False otherwise
    """
    if not customer_id or not isinstance(customer_id, str):
        return False
    
    # Basic validation - adjust as needed for your customer ID format
    return len(customer_id.strip()) >= 3 and len(customer_id.strip()) <= 100


def sanitize_message(message: str) -> str:
    """
    Sanitize customer message for security.
    
    Args:
        message: Raw customer message
        
    Returns:
        Sanitized message
    """
    if not message:
        return ""
    
    # Basic sanitization - expand as needed
    sanitized = message.strip()
    
    # Remove potential script tags and other dangerous content
    dangerous_patterns = ['<script', '</script>', 'javascript:', 'data:', 'vbscript:']
    for pattern in dangerous_patterns:
        sanitized = sanitized.replace(pattern.lower(), '').replace(pattern.upper(), '')
    
    return sanitized[:2000]  # Limit message length


def get_session_metadata(event: Dict[str, Any]) -> Dict[str, Any]:
    """
    Extract session metadata from API Gateway event.
    
    Args:
        event: API Gateway event
        
    Returns:
        Session metadata dictionary
    """
    metadata = {}
    
    # Extract request context information
    if 'requestContext' in event:
        context = event['requestContext']
        metadata['requestId'] = context.get('requestId')
        metadata['sourceIp'] = context.get('identity', {}).get('sourceIp')
        metadata['userAgent'] = context.get('identity', {}).get('userAgent')
    
    # Extract headers
    if 'headers' in event:
        headers = event['headers']
        metadata['userAgent'] = metadata.get('userAgent') or headers.get('User-Agent')
        metadata['origin'] = headers.get('Origin')
        metadata['referer'] = headers.get('Referer')
    
    return metadata