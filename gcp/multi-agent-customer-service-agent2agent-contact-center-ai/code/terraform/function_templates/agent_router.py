"""
Agent Router Function - Intelligent routing for multi-agent customer service
Analyzes incoming customer inquiries and routes them to specialized agents
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
DATASET_ID = os.environ.get('DATASET_ID')

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

@functions_framework.http
def route_agent(request):
    """Route customer inquiry to appropriate specialist agent"""
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

        # Extract and validate required fields
        customer_message = request_json.get('message', '').strip()
        session_id = request_json.get('session_id', '').strip()
        
        if not customer_message:
            return {'error': 'Message field is required and cannot be empty'}, 400, headers
        
        if not session_id:
            return {'error': 'Session ID field is required and cannot be empty'}, 400, headers

        logger.info(f"Processing routing request for session: {session_id}")

        # Analyze message intent and determine optimal routing
        routing_decision = analyze_intent(customer_message)
        
        # Log routing decision for analytics and optimization
        log_routing_decision(session_id, customer_message, routing_decision)
        
        # Store conversation context
        store_conversation_context(session_id, customer_message, routing_decision)

        response = {
            'agent_type': routing_decision['agent'],
            'confidence': routing_decision['confidence'],
            'reasoning': routing_decision['reasoning'],
            'session_id': session_id,
            'timestamp': datetime.utcnow().isoformat() + 'Z'
        }

        logger.info(f"Routing decision: {routing_decision['agent']} (confidence: {routing_decision['confidence']:.2f})")
        return response, 200, headers
        
    except Exception as e:
        logger.error(f"Routing error: {str(e)}", exc_info=True)
        return {'error': f'Internal server error: {str(e)}'}, 500, headers

def analyze_intent(message):
    """Analyze customer message and determine best agent using keyword analysis"""
    message_lower = message.lower()
    
    # Domain-specific keywords for intelligent routing with weights
    billing_keywords = {
        'bill': 3, 'payment': 3, 'invoice': 3, 'charge': 2, 'refund': 3, 
        'subscription': 2, 'billing': 3, 'cost': 2, 'price': 1, 'money': 2,
        'credit': 2, 'debit': 2, 'receipt': 2, 'account': 1
    }
    
    technical_keywords = {
        'not working': 4, 'error': 3, 'install': 3, 'setup': 3, 'configure': 3,
        'trouble': 3, 'problem': 2, 'issue': 2, 'bug': 3, 'broken': 3,
        'help': 1, 'support': 2, 'fix': 2, 'troubleshoot': 4
    }
    
    sales_keywords = {
        'price': 2, 'purchase': 3, 'demo': 3, 'upgrade': 3, 'plan': 2,
        'features': 2, 'buy': 3, 'subscription': 1, 'trial': 2, 'product': 2,
        'service': 1, 'offer': 2, 'discount': 2, 'quote': 3
    }
    
    # Calculate weighted keyword match scores
    billing_score = calculate_weighted_score(message_lower, billing_keywords)
    technical_score = calculate_weighted_score(message_lower, technical_keywords)
    sales_score = calculate_weighted_score(message_lower, sales_keywords)
    
    # Add contextual scoring for phrases
    billing_score += check_billing_phrases(message_lower)
    technical_score += check_technical_phrases(message_lower)
    sales_score += check_sales_phrases(message_lower)
    
    # Determine best agent based on weighted analysis
    max_score = max(billing_score, technical_score, sales_score)
    
    if max_score == 0:
        # Default routing when no clear intent is detected
        return {
            'agent': 'sales',
            'confidence': 0.3,
            'reasoning': 'No specific keywords detected, routing to sales for general inquiry'
        }
    
    confidence_base = min(0.95, max_score / 10.0)  # Scale confidence based on score
    
    if billing_score == max_score:
        return {
            'agent': 'billing',
            'confidence': confidence_base,
            'reasoning': f'Billing keywords detected with score: {billing_score}'
        }
    elif technical_score == max_score:
        return {
            'agent': 'technical',
            'confidence': confidence_base,
            'reasoning': f'Technical keywords detected with score: {technical_score}'
        }
    else:
        return {
            'agent': 'sales',
            'confidence': confidence_base,
            'reasoning': f'Sales keywords detected with score: {sales_score}'
        }

def calculate_weighted_score(message, keywords):
    """Calculate weighted score based on keyword presence and weights"""
    score = 0
    for keyword, weight in keywords.items():
        if keyword in message:
            # Count occurrences and apply weight
            occurrences = message.count(keyword)
            score += occurrences * weight
    return score

def check_billing_phrases(message):
    """Check for billing-specific phrases and return additional score"""
    billing_phrases = [
        'monthly bill', 'payment failed', 'credit card', 'billing cycle',
        'invoice number', 'refund request', 'payment method', 'account balance'
    ]
    score = 0
    for phrase in billing_phrases:
        if phrase in message:
            score += 5  # Higher weight for specific phrases
    return score

def check_technical_phrases(message):
    """Check for technical-specific phrases and return additional score"""
    technical_phrases = [
        'not working', 'error message', 'installation failed', 'cannot access',
        'system down', 'configuration issue', 'technical support', 'bug report'
    ]
    score = 0
    for phrase in technical_phrases:
        if phrase in message:
            score += 5  # Higher weight for specific phrases
    return score

def check_sales_phrases(message):
    """Check for sales-specific phrases and return additional score"""
    sales_phrases = [
        'pricing information', 'product demo', 'upgrade plan', 'new features',
        'sales team', 'purchase decision', 'product comparison', 'free trial'
    ]
    score = 0
    for phrase in sales_phrases:
        if phrase in message:
            score += 5  # Higher weight for specific phrases
    return score

def log_routing_decision(session_id, message, decision):
    """Log routing decision to Firestore for analytics"""
    try:
        doc_ref = db.collection('routing_logs').document()
        doc_ref.set({
            'session_id': session_id,
            'message': message,
            'agent_selected': decision['agent'],
            'confidence': decision['confidence'],
            'reasoning': decision['reasoning'],
            'timestamp': firestore.SERVER_TIMESTAMP,
            'message_length': len(message),
            'project_id': PROJECT_ID,
            'region': REGION
        })
        logger.info(f"Routing decision logged for session: {session_id}")
    except Exception as e:
        logger.error(f"Failed to log routing decision: {str(e)}")

def store_conversation_context(session_id, message, routing_decision):
    """Store conversation context for agent handoffs"""
    try:
        doc_ref = db.collection('conversations').document(session_id)
        doc_ref.set({
            'latest_message': message,
            'current_agent': routing_decision['agent'],
            'routing_confidence': routing_decision['confidence'],
            'routing_reasoning': routing_decision['reasoning'],
            'last_updated': firestore.SERVER_TIMESTAMP,
            'message_count': firestore.Increment(1)
        }, merge=True)
        logger.info(f"Conversation context stored for session: {session_id}")
    except Exception as e:
        logger.error(f"Failed to store conversation context: {str(e)}")

def log_to_bigquery(session_id, message, decision):
    """Log routing data to BigQuery for advanced analytics"""
    if not DATASET_ID:
        logger.warning("BigQuery dataset ID not configured, skipping BigQuery logging")
        return
    
    try:
        table_id = f"{PROJECT_ID}.{DATASET_ID}.conversation_logs"
        rows_to_insert = [{
            'session_id': session_id,
            'agent_type': decision['agent'],
            'customer_message': message,
            'confidence_score': decision['confidence'],
            'routing_reasoning': decision['reasoning'],
            'timestamp': datetime.utcnow()
        }]
        
        errors = bq_client.insert_rows_json(table_id, rows_to_insert)
        if errors:
            logger.error(f"BigQuery insert errors: {errors}")
        else:
            logger.info(f"Routing data logged to BigQuery for session: {session_id}")
    except Exception as e:
        logger.error(f"Failed to log to BigQuery: {str(e)}")