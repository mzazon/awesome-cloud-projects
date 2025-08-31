"""
Message Broker Function - Agent2Agent protocol implementation
Manages inter-agent communication for seamless handoffs and collaboration
"""
import json
import functions_framework
from google.cloud import firestore
from google.cloud import bigquery
import uuid
import logging
import os
from datetime import datetime

# Initialize Google Cloud clients
db = firestore.Client(project="${project_id}")
bq_client = bigquery.Client(project="${project_id}")

# Environment configuration
PROJECT_ID = "${project_id}"
REGION = "${region}"
DATASET_ID = os.environ.get('DATASET_ID')

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

@functions_framework.http
def broker_message(request):
    """Broker messages between agents using A2A protocol principles"""
    # Enable CORS for web applications
    if request.method == 'OPTIONS':
        headers = {
            'Access-Control-Allow-Origin': '*',
            'Access-Control-Allow-Methods': 'POST',
            'Access-Control-Allow-Headers': 'Content-Type',
            'Access-Control-Max-Age': '3600'
        }
        return ('', 204, headers)

    headers = {'Access-Control-Allow-Origin': '*'}

    try:
        # Validate request method
        if request.method != 'POST':
            return {'error': 'Only POST method is allowed'}, 405, headers

        # Parse request JSON
        request_json = request.get_json(silent=True)
        if not request_json:
            return {'error': 'Request must contain valid JSON'}, 400, headers

        # Extract Agent2Agent protocol message details
        source_agent = request_json.get('source_agent', '').strip()
        target_agent = request_json.get('target_agent', '').strip()
        message_content = request_json.get('message', '').strip()
        session_id = request_json.get('session_id', '').strip()
        handoff_reason = request_json.get('handoff_reason', 'escalation').strip()
        
        # Validate required fields
        if not all([source_agent, target_agent, message_content, session_id]):
            return {
                'error': 'Missing required fields: source_agent, target_agent, message, session_id'
            }, 400, headers

        # Validate agent types
        valid_agents = ['billing', 'technical', 'sales', 'router']
        if source_agent not in valid_agents or target_agent not in valid_agents:
            return {
                'error': f'Invalid agent type. Valid agents: {valid_agents}'
            }, 400, headers

        logger.info(f"Processing A2A handoff from {source_agent} to {target_agent} for session: {session_id}")

        # Create A2A protocol compliant message
        a2a_message = create_a2a_message(
            source_agent, target_agent, message_content, 
            session_id, handoff_reason
        )
        
        # Store conversation context for seamless handoffs
        store_conversation_context(session_id, a2a_message)
        
        # Log handoff for analytics
        log_agent_handoff(session_id, source_agent, target_agent, handoff_reason)
        
        # Route to target agent with context preservation
        routing_result = route_to_agent(target_agent, a2a_message)

        response = {
            'status': 'success',
            'message_id': a2a_message['message_id'],
            'protocol_version': a2a_message['protocol_version'],
            'source_agent': source_agent,
            'target_agent': target_agent,
            'handoff_reason': handoff_reason,
            'routing_result': routing_result,
            'timestamp': datetime.utcnow().isoformat() + 'Z'
        }

        logger.info(f"A2A handoff completed: {source_agent} -> {target_agent}")
        return response, 200, headers
        
    except Exception as e:
        logger.error(f"Message broker error: {str(e)}", exc_info=True)
        return {'error': f'Internal server error: {str(e)}'}, 500, headers

def create_a2a_message(source, target, content, session_id, reason):
    """Create Agent2Agent protocol compliant message"""
    message_id = str(uuid.uuid4())
    
    a2a_message = {
        'message_id': message_id,
        'protocol_version': '1.0',
        'source_agent': {
            'id': source,
            'type': source,
            'capabilities': get_agent_capabilities(source),
            'timestamp': datetime.utcnow().isoformat() + 'Z'
        },
        'target_agent': {
            'id': target,
            'type': target,
            'capabilities': get_agent_capabilities(target)
        },
        'message_content': content,
        'session_id': session_id,
        'handoff_reason': reason,
        'created_timestamp': datetime.utcnow().isoformat() + 'Z',
        'context': {
            'conversation_history': get_conversation_history(session_id),
            'customer_data': get_customer_context(session_id),
            'previous_agents': get_previous_agents(session_id)
        },
        'metadata': {
            'project_id': PROJECT_ID,
            'region': REGION,
            'broker_version': '1.0'
        }
    }
    
    logger.info(f"Created A2A message {message_id} for {source} -> {target}")
    return a2a_message

def get_agent_capabilities(agent_type):
    """Retrieve agent capabilities from knowledge base"""
    try:
        doc_ref = db.collection('knowledge').document(agent_type)
        doc = doc_ref.get()
        if doc.exists:
            data = doc.to_dict()
            return {
                'capabilities': data.get('capabilities', []),
                'expertise_level': data.get('expertise_level', 'basic'),
                'domain': data.get('domain', agent_type)
            }
        else:
            logger.warning(f"No capabilities found for agent type: {agent_type}")
            return {
                'capabilities': [],
                'expertise_level': 'basic',
                'domain': agent_type
            }
    except Exception as e:
        logger.error(f"Capability lookup error for {agent_type}: {str(e)}")
        return {
            'capabilities': [],
            'expertise_level': 'basic',
            'domain': agent_type
        }

def store_conversation_context(session_id, message):
    """Store conversation context for seamless agent transitions"""
    try:
        doc_ref = db.collection('conversations').document(session_id)
        
        # Get existing conversation data
        existing_doc = doc_ref.get()
        history = []
        if existing_doc.exists:
            existing_data = existing_doc.to_dict()
            history = existing_data.get('history', [])
        
        # Add current handoff to history
        history.append({
            'message_id': message['message_id'],
            'source_agent': message['source_agent']['id'],
            'target_agent': message['target_agent']['id'],
            'handoff_reason': message['handoff_reason'],
            'timestamp': message['created_timestamp'],
            'content': message['message_content']
        })
        
        # Keep only last 10 handoffs to manage storage
        if len(history) > 10:
            history = history[-10:]
        
        # Update conversation document
        doc_ref.set({
            'session_id': session_id,
            'current_agent': message['target_agent']['id'],
            'last_message': message,
            'history': history,
            'last_handoff_timestamp': firestore.SERVER_TIMESTAMP,
            'total_handoffs': firestore.Increment(1)
        }, merge=True)
        
        logger.info(f"Conversation context updated for session: {session_id}")
    except Exception as e:
        logger.error(f"Context storage error: {str(e)}")

def get_conversation_history(session_id):
    """Retrieve conversation history for context continuity"""
    try:
        doc_ref = db.collection('conversations').document(session_id)
        doc = doc_ref.get()
        if doc.exists:
            data = doc.to_dict()
            return data.get('history', [])
        return []
    except Exception as e:
        logger.error(f"History retrieval error: {str(e)}")
        return []

def get_customer_context(session_id):
    """Retrieve customer context data for personalization"""
    try:
        # Check for existing customer context
        doc_ref = db.collection('customer_context').document(session_id)
        doc = doc_ref.get()
        if doc.exists:
            return doc.to_dict()
        else:
            # Return basic context structure
            return {
                'session_id': session_id,
                'preferences': {},
                'interaction_history': [],
                'customer_tier': 'standard',
                'language': 'en'
            }
    except Exception as e:
        logger.error(f"Customer context retrieval error: {str(e)}")
        return {
            'session_id': session_id,
            'preferences': {},
            'interaction_history': [],
            'customer_tier': 'standard',
            'language': 'en'
        }

def get_previous_agents(session_id):
    """Get list of agents that have handled this session"""
    try:
        doc_ref = db.collection('conversations').document(session_id)
        doc = doc_ref.get()
        if doc.exists:
            data = doc.to_dict()
            history = data.get('history', [])
            agents = set()
            for entry in history:
                agents.add(entry.get('source_agent'))
                agents.add(entry.get('target_agent'))
            return list(agents)
        return []
    except Exception as e:
        logger.error(f"Previous agents retrieval error: {str(e)}")
        return []

def route_to_agent(agent_type, message):
    """Route message to specific agent endpoint"""
    try:
        # Store routing information
        routing_doc = db.collection('routing_queue').document()
        routing_doc.set({
            'target_agent': agent_type,
            'message_id': message['message_id'],
            'session_id': message['session_id'],
            'priority': determine_priority(message),
            'created_timestamp': firestore.SERVER_TIMESTAMP,
            'status': 'queued'
        })
        
        return {
            'status': 'routed',
            'agent': agent_type,
            'message_id': message['message_id'],
            'queue_position': 1,  # Simplified queue position
            'estimated_wait_time': '< 1 minute'
        }
    except Exception as e:
        logger.error(f"Routing error: {str(e)}")
        return {
            'status': 'error',
            'agent': agent_type,
            'message_id': message['message_id'],
            'error': str(e)
        }

def determine_priority(message):
    """Determine message priority based on content and context"""
    high_priority_reasons = ['urgent', 'critical', 'escalation', 'complaint']
    handoff_reason = message.get('handoff_reason', '').lower()
    
    if any(reason in handoff_reason for reason in high_priority_reasons):
        return 'high'
    
    # Check conversation history for multiple handoffs (indicates complexity)
    history = message.get('context', {}).get('conversation_history', [])
    if len(history) > 3:
        return 'medium'
    
    return 'normal'

def log_agent_handoff(session_id, source_agent, target_agent, reason):
    """Log agent handoff for analytics and monitoring"""
    try:
        doc_ref = db.collection('agent_handoffs').document()
        doc_ref.set({
            'session_id': session_id,
            'source_agent': source_agent,
            'target_agent': target_agent,
            'handoff_reason': reason,
            'timestamp': firestore.SERVER_TIMESTAMP,
            'project_id': PROJECT_ID,
            'region': REGION
        })
        
        # Also log to BigQuery if available
        if DATASET_ID:
            log_handoff_to_bigquery(session_id, source_agent, target_agent, reason)
            
        logger.info(f"Handoff logged: {source_agent} -> {target_agent} for session: {session_id}")
    except Exception as e:
        logger.error(f"Handoff logging error: {str(e)}")

def log_handoff_to_bigquery(session_id, source_agent, target_agent, reason):
    """Log handoff data to BigQuery for advanced analytics"""
    try:
        table_id = f"{PROJECT_ID}.{DATASET_ID}.conversation_logs"
        rows_to_insert = [{
            'session_id': session_id,
            'agent_type': f"{source_agent}_to_{target_agent}",
            'customer_message': f"Agent handoff: {reason}",
            'agent_response': f"Transferred from {source_agent} to {target_agent}",
            'confidence_score': 1.0,
            'handoff_reason': reason,
            'timestamp': datetime.utcnow()
        }]
        
        errors = bq_client.insert_rows_json(table_id, rows_to_insert)
        if errors:
            logger.error(f"BigQuery handoff insert errors: {errors}")
        else:
            logger.info(f"Handoff data logged to BigQuery for session: {session_id}")
    except Exception as e:
        logger.error(f"Failed to log handoff to BigQuery: {str(e)}")

def validate_a2a_message(message):
    """Validate A2A protocol message structure"""
    required_fields = [
        'message_id', 'protocol_version', 'source_agent', 'target_agent',
        'message_content', 'session_id', 'handoff_reason'
    ]
    
    for field in required_fields:
        if field not in message:
            return False, f"Missing required field: {field}"
    
    if message['protocol_version'] != '1.0':
        return False, f"Unsupported protocol version: {message['protocol_version']}"
    
    return True, "Valid A2A message"