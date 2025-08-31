"""
Specialized Agent Function - Domain-specific customer service agents
Provides expert responses for billing, technical, and sales inquiries
"""
import json
import functions_framework
from google.cloud import firestore
from google.cloud import bigquery
import logging
import os
from datetime import datetime

# Initialize Google Cloud clients
db = firestore.Client(project="${project_id}")
bq_client = bigquery.Client(project="${project_id}")

# Environment configuration
PROJECT_ID = "${project_id}"
REGION = "${region}"
AGENT_TYPE = "${agent_type}"
DATASET_ID = os.environ.get('DATASET_ID')

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Agent-specific response templates and logic
AGENT_RESPONSES = {
    'billing': {
        'refund': "I can help you with refunds. Please provide your order number or invoice ID, and I'll check your refund eligibility and process it immediately.",
        'invoice': "I can access your billing information. Let me pull up your recent invoices and payment history to assist you with any billing questions.",
        'payment': "I can help with payment issues. I can update payment methods, process payments, or troubleshoot payment failures. What specific payment assistance do you need?",
        'subscription': "I can manage your subscription details including upgrades, downgrades, cancellations, and billing cycles. How can I help with your subscription?",
        'default': "I'm your billing specialist. I can help with payments, invoices, refunds, and subscription management. What billing question do you have?"
    },
    'technical': {
        'not_working': "I can help troubleshoot that issue. Let me run some diagnostics and provide step-by-step solutions to get everything working properly.",
        'install': "I'll guide you through the installation process with detailed instructions and verify each step works correctly on your system.",
        'configure': "I can help optimize your configuration settings for best performance and security. Let me check your current setup and recommend improvements.",
        'error': "I can help diagnose and resolve that error. Let me analyze the issue and provide you with specific troubleshooting steps.",
        'default': "I'm your technical specialist. I can help with troubleshooting, installations, configurations, and system diagnostics. What technical issue can I resolve?"
    },
    'sales': {
        'price': "I can provide detailed pricing information for all our products and services. Let me share our current rates and help you find the best plan for your needs.",
        'demo': "I'd be happy to arrange a product demonstration. I can show you all the features and how they'll benefit your specific use case.",
        'upgrade': "I can help you upgrade your current plan to unlock additional features and capabilities. Let me review your current usage and recommend the best upgrade path.",
        'features': "Let me walk you through our product features and explain how each one can benefit your business operations and goals.",
        'default': "I'm your sales specialist. I can help with pricing, product information, demos, upgrades, and finding the perfect solution for your needs. How can I assist you today?"
    }
}

@functions_framework.http
def billing_agent(request):
    """Specialized billing agent with A2A communication capability"""
    return handle_agent_request(request, 'billing')

@functions_framework.http
def technical_agent(request):
    """Specialized technical support agent with diagnostic capabilities"""
    return handle_agent_request(request, 'technical')

@functions_framework.http
def sales_agent(request):
    """Specialized sales agent with product expertise"""
    return handle_agent_request(request, 'sales')

def handle_agent_request(request, agent_type):
    """Generic handler for all specialized agents"""
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

        # Extract required fields
        customer_message = request_json.get('message', '').strip()
        session_id = request_json.get('session_id', '').strip()
        context = request_json.get('context', {})
        
        # Validate required fields
        if not customer_message:
            return {'error': 'Message field is required and cannot be empty'}, 400, headers
        
        if not session_id:
            return {'error': 'Session ID field is required and cannot be empty'}, 400, headers

        logger.info(f"{agent_type.title()} agent processing request for session: {session_id}")

        # Process inquiry with domain expertise
        response = process_agent_inquiry(agent_type, customer_message, context)
        
        # Check if handoff to another agent is needed
        handoff_needed = check_handoff_needed(agent_type, customer_message)
        
        # Log agent interaction for analytics and learning
        log_agent_interaction(session_id, agent_type, customer_message, response)
        
        # Update conversation context
        update_conversation_context(session_id, agent_type, customer_message, response)

        result = {
            'agent_type': agent_type,
            'response': response,
            'session_id': session_id,
            'confidence': calculate_response_confidence(agent_type, customer_message),
            'timestamp': datetime.utcnow().isoformat() + 'Z',
            'capabilities': get_agent_capabilities(agent_type)
        }
        
        if handoff_needed:
            result['handoff'] = handoff_needed
            logger.info(f"Handoff recommended: {agent_type} -> {handoff_needed['target_agent']}")
            
        logger.info(f"{agent_type.title()} agent response generated for session: {session_id}")
        return result, 200, headers
        
    except Exception as e:
        logger.error(f"{agent_type.title()} agent error: {str(e)}", exc_info=True)
        return {'error': f'Internal server error: {str(e)}'}, 500, headers

def process_agent_inquiry(agent_type, message, context=None):
    """Process agent-specific inquiry with domain expertise"""
    message_lower = message.lower()
    responses = AGENT_RESPONSES.get(agent_type, {})
    
    # Check for specific keywords and return appropriate response
    for keyword, response in responses.items():
        if keyword == 'default':
            continue
        
        # Handle multi-word keywords
        if keyword == 'not_working':
            if 'not working' in message_lower or 'not work' in message_lower:
                return response
        else:
            if keyword in message_lower:
                return response
    
    # Return default response if no specific keyword matches
    return responses.get('default', f"I'm your {agent_type} specialist. How can I help you today?")

def calculate_response_confidence(agent_type, message):
    """Calculate confidence score for agent response"""
    message_lower = message.lower()
    
    # Agent-specific confidence keywords
    confidence_keywords = {
        'billing': ['bill', 'payment', 'invoice', 'refund', 'subscription', 'charge'],
        'technical': ['error', 'install', 'setup', 'configure', 'not working', 'problem'],
        'sales': ['price', 'demo', 'upgrade', 'features', 'purchase', 'plan']
    }
    
    keywords = confidence_keywords.get(agent_type, [])
    matches = sum(1 for keyword in keywords if keyword in message_lower)
    
    # Base confidence based on keyword matches
    base_confidence = min(0.95, 0.6 + (matches * 0.1))
    
    # Adjust for message length (longer messages often have more context)
    length_factor = min(1.0, len(message) / 100.0)
    
    return round(base_confidence * (0.8 + length_factor * 0.2), 2)

def check_handoff_needed(current_agent, message):
    """Check if handoff to another agent is needed based on context"""
    message_lower = message.lower()
    
    # Define handoff triggers for each agent type
    handoff_triggers = {
        'billing': {
            'technical': ['not working', 'error', 'broken', 'install', 'setup', 'configure'],
            'sales': ['upgrade', 'new plan', 'demo', 'features', 'purchase']
        },
        'technical': {
            'billing': ['bill', 'payment', 'invoice', 'refund', 'charge'],
            'sales': ['price', 'upgrade', 'plan', 'demo', 'purchase']
        },
        'sales': {
            'billing': ['bill', 'payment', 'invoice', 'refund'],
            'technical': ['not working', 'error', 'install', 'setup', 'broken']
        }
    }
    
    triggers = handoff_triggers.get(current_agent, {})
    
    for target_agent, keywords in triggers.items():
        if any(keyword in message_lower for keyword in keywords):
            return {
                'target_agent': target_agent,
                'reason': f'{target_agent.title()} keywords detected in {current_agent} context',
                'confidence': 0.8,
                'recommended_message': f"I notice you may need {target_agent} assistance. Let me connect you with our {target_agent} specialist who can better help with this request."
            }
    
    return None

def get_agent_capabilities(agent_type):
    """Get agent capabilities from knowledge base"""
    try:
        doc_ref = db.collection('knowledge').document(agent_type)
        doc = doc_ref.get()
        if doc.exists:
            data = doc.to_dict()
            return {
                'capabilities': data.get('capabilities', []),
                'expertise_level': data.get('expertise_level', 'expert'),
                'domain': data.get('domain', agent_type)
            }
        else:
            # Return default capabilities if not found in knowledge base
            default_capabilities = {
                'billing': ['payments', 'invoices', 'refunds', 'subscriptions'],
                'technical': ['troubleshooting', 'installations', 'configurations', 'diagnostics'],
                'sales': ['product_info', 'pricing', 'demos', 'upgrades']
            }
            return {
                'capabilities': default_capabilities.get(agent_type, []),
                'expertise_level': 'expert',
                'domain': agent_type
            }
    except Exception as e:
        logger.error(f"Failed to get capabilities for {agent_type}: {str(e)}")
        return {
            'capabilities': [],
            'expertise_level': 'expert',
            'domain': agent_type
        }

def log_agent_interaction(session_id, agent_type, message, response):
    """Log agent interaction for analytics and optimization"""
    try:
        doc_ref = db.collection('agent_interactions').document()
        doc_ref.set({
            'session_id': session_id,
            'agent_type': agent_type,
            'customer_message': message,
            'agent_response': response,
            'message_length': len(message),
            'response_length': len(response),
            'timestamp': firestore.SERVER_TIMESTAMP,
            'project_id': PROJECT_ID,
            'region': REGION
        })
        
        # Also log to BigQuery for advanced analytics
        if DATASET_ID:
            log_to_bigquery(session_id, agent_type, message, response)
        
        logger.info(f"Interaction logged for {agent_type} agent, session: {session_id}")
    except Exception as e:
        logger.error(f"Interaction logging error: {str(e)}")

def update_conversation_context(session_id, agent_type, message, response):
    """Update conversation context with current interaction"""
    try:
        doc_ref = db.collection('conversations').document(session_id)
        
        # Get existing conversation
        existing_doc = doc_ref.get()
        interaction_count = 1
        if existing_doc.exists:
            existing_data = existing_doc.to_dict()
            interaction_count = existing_data.get('interaction_count', 0) + 1
        
        # Update conversation document
        doc_ref.set({
            'session_id': session_id,
            'current_agent': agent_type,
            'last_customer_message': message,
            'last_agent_response': response,
            'interaction_count': interaction_count,
            'last_interaction_timestamp': firestore.SERVER_TIMESTAMP,
            'agent_confidence': calculate_response_confidence(agent_type, message)
        }, merge=True)
        
        logger.info(f"Conversation context updated for session: {session_id}")
    except Exception as e:
        logger.error(f"Failed to update conversation context: {str(e)}")

def log_to_bigquery(session_id, agent_type, message, response):
    """Log interaction data to BigQuery for advanced analytics"""
    try:
        table_id = f"{PROJECT_ID}.{DATASET_ID}.conversation_logs"
        rows_to_insert = [{
            'session_id': session_id,
            'agent_type': agent_type,
            'customer_message': message,
            'agent_response': response,
            'confidence_score': calculate_response_confidence(agent_type, message),
            'timestamp': datetime.utcnow()
        }]
        
        errors = bq_client.insert_rows_json(table_id, rows_to_insert)
        if errors:
            logger.error(f"BigQuery insert errors: {errors}")
        else:
            logger.info(f"Interaction logged to BigQuery for {agent_type} agent")
    except Exception as e:
        logger.error(f"Failed to log to BigQuery: {str(e)}")

def get_conversation_history(session_id):
    """Get conversation history for context-aware responses"""
    try:
        doc_ref = db.collection('conversations').document(session_id)
        doc = doc_ref.get()
        if doc.exists:
            data = doc.to_dict()
            return {
                'interaction_count': data.get('interaction_count', 0),
                'previous_agents': data.get('previous_agents', []),
                'last_interaction': data.get('last_interaction_timestamp'),
                'customer_sentiment': data.get('customer_sentiment', 'neutral')
            }
        return {}
    except Exception as e:
        logger.error(f"Failed to get conversation history: {str(e)}")
        return {}

def analyze_customer_intent(message):
    """Analyze customer intent for more personalized responses"""
    message_lower = message.lower()
    
    intent_indicators = {
        'urgent': ['urgent', 'asap', 'immediately', 'emergency', 'critical'],
        'frustrated': ['frustrated', 'angry', 'disappointed', 'terrible', 'awful'],
        'confused': ['confused', 'don\'t understand', 'unclear', 'help me understand'],
        'satisfied': ['thank you', 'thanks', 'great', 'excellent', 'perfect']
    }
    
    detected_intents = []
    for intent, indicators in intent_indicators.items():
        if any(indicator in message_lower for indicator in indicators):
            detected_intents.append(intent)
    
    return detected_intents if detected_intents else ['neutral']