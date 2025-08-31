"""
Business Process AI Agent Cloud Function

This function processes natural language business requests using simulated
Vertex AI Agent Development Kit capabilities with database integration.
Designed for deployment via Terraform with Cloud SQL connectivity.
"""

import functions_framework
import json
import re
import uuid
import os
import pg8000
from datetime import datetime
import logging

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

@functions_framework.http
def process_natural_language(request):
    """
    Process natural language business requests with AI-powered analysis.
    
    Expected request format:
    {
        "message": "string - natural language request",
        "user_email": "string - email of requester",
        "context": "object (optional) - additional context",
        "priority_override": "high|medium|low (optional)"
    }
    """
    try:
        # Enable CORS for web requests
        if request.method == 'OPTIONS':
            headers = {
                'Access-Control-Allow-Origin': '*',
                'Access-Control-Allow-Methods': 'POST',
                'Access-Control-Allow-Headers': 'Content-Type',
                'Access-Control-Max-Age': '3600'
            }
            return ('', 204, headers)

        # Set CORS headers for actual request
        headers = {
            'Access-Control-Allow-Origin': '*',
            'Content-Type': 'application/json'
        }

        if request.method != 'POST':
            return ({'error': 'Method not allowed'}, 405, headers)
        
        request_json = request.get_json(silent=True)
        if not request_json:
            return ({'error': 'No JSON data provided'}, 400, headers)
        
        # Extract required parameters
        user_input = request_json.get('message', '')
        user_email = request_json.get('user_email', '')
        context = request_json.get('context', {})
        priority_override = request_json.get('priority_override')
        
        if not user_input or not user_email:
            return ({'error': 'Missing required fields: message, user_email'}, 400, headers)
        
        logger.info(f"Processing natural language request from {user_email}: {user_input[:100]}...")
        
        # Process natural language using simulated AI capabilities
        # In production, this would use Vertex AI Agent Development Kit
        processed_request = analyze_request(user_input, context, priority_override)
        
        # Generate unique request ID
        request_id = str(uuid.uuid4())[:8]
        
        try:
            conn = get_database_connection()
            cursor = conn.cursor()
            
            # Start transaction
            cursor.execute("BEGIN")
            
            # Store initial request in database
            cursor.execute("""
                INSERT INTO process_requests 
                (request_id, requester_email, process_type, request_data, priority)
                VALUES (%s, %s, %s, %s, %s)
                RETURNING id
            """, (request_id, user_email, processed_request['intent'], 
                 json.dumps(processed_request['entities']), processed_request['priority']))
            
            process_db_id = cursor.fetchone()[0]
            
            # Add audit entry for request creation
            audit_details = {
                'original_message': user_input,
                'interpretation': processed_request,
                'context': context,
                'ai_confidence': processed_request['confidence'],
                'processing_method': 'simulated_adk'
            }
            
            cursor.execute("""
                INSERT INTO process_audit 
                (request_id, action, actor, details)
                VALUES (%s, %s, %s, %s)
            """, (request_id, 'Request created via AI agent', user_email, json.dumps(audit_details)))
            
            # Commit transaction
            cursor.execute("COMMIT")
            conn.close()
            
            # Prepare workflow input for orchestration
            workflow_input = {
                'request_id': request_id,
                'process_type': processed_request['intent'],
                'requester_email': user_email,
                'request_data': processed_request['entities'],
                'priority': processed_request['priority'],
                'ai_confidence': processed_request['confidence'],
                'original_message': user_input
            }
            
            logger.info(f"Successfully processed request: {request_id}, intent: {processed_request['intent']}")
            
            response_data = {
                'status': 'success',
                'request_id': request_id,
                'workflow_input': workflow_input,
                'interpretation': {
                    'intent': processed_request['intent'],
                    'entities': processed_request['entities'],
                    'priority': processed_request['priority'],
                    'confidence': processed_request['confidence'],
                    'suggested_actions': processed_request.get('suggested_actions', [])
                },
                'next_steps': generate_next_steps(processed_request),
                'processed_at': datetime.utcnow().isoformat() + 'Z'
            }
            
            return (response_data, 200, headers)
            
        except Exception as db_error:
            logger.error(f"Database error: {str(db_error)}")
            try:
                cursor.execute("ROLLBACK")
                conn.close()
            except:
                pass
            return ({'error': 'Database operation failed', 'details': str(db_error)}, 500, headers)
        
    except Exception as e:
        logger.error(f"Unexpected error in process_natural_language: {str(e)}")
        return ({'error': 'Internal server error', 'details': str(e)}, 500, headers)


def analyze_request(text, context=None, priority_override=None):
    """
    Analyze natural language request for intent and entity extraction.
    This simulates Vertex AI Agent Development Kit capabilities.
    In production, this would use actual AI models.
    """
    text_lower = text.lower()
    context = context or {}
    
    # Intent classification with confidence scoring
    intent_scores = {}
    
    # Expense approval keywords and scoring
    expense_keywords = ['expense', 'cost', 'money', 'receipt', 'reimbursement', 'payment', 'invoice', 'bill']
    expense_score = sum(1 for word in expense_keywords if word in text_lower)
    if expense_score > 0:
        intent_scores['expense_approval'] = expense_score / len(expense_keywords)
    
    # Leave request keywords and scoring
    leave_keywords = ['leave', 'vacation', 'time off', 'sick', 'holiday', 'pto', 'absence', 'break']
    leave_score = sum(1 for word in leave_keywords if word in text_lower)
    if leave_score > 0:
        intent_scores['leave_request'] = leave_score / len(leave_keywords)
    
    # Access request keywords and scoring
    access_keywords = ['access', 'permission', 'account', 'login', 'password', 'privilege', 'rights', 'authorization']
    access_score = sum(1 for word in access_keywords if word in text_lower)
    if access_score > 0:
        intent_scores['access_request'] = access_score / len(access_keywords)
    
    # Procurement keywords and scoring
    procurement_keywords = ['purchase', 'buy', 'order', 'procurement', 'vendor', 'supplier', 'contract']
    procurement_score = sum(1 for word in procurement_keywords if word in text_lower)
    if procurement_score > 0:
        intent_scores['procurement_request'] = procurement_score / len(procurement_keywords)
    
    # Travel request keywords and scoring
    travel_keywords = ['travel', 'trip', 'flight', 'hotel', 'conference', 'business trip', 'transportation']
    travel_score = sum(1 for word in travel_keywords if word in text_lower)
    if travel_score > 0:
        intent_scores['travel_request'] = travel_score / len(travel_keywords)
    
    # Determine primary intent
    if intent_scores:
        intent = max(intent_scores, key=intent_scores.get)
        confidence = intent_scores[intent]
    else:
        intent = 'general_request'
        confidence = 0.5
    
    # Priority determination
    priority = 3  # Default priority (1=high, 2=medium, 3=low, 4=very low)
    
    # Override priority if specified
    if priority_override:
        priority_map = {'high': 1, 'medium': 2, 'low': 3, 'very_low': 4}
        priority = priority_map.get(priority_override, 3)
    else:
        # Analyze urgency keywords
        urgent_keywords = ['urgent', 'asap', 'immediate', 'emergency', 'critical', 'rush']
        medium_keywords = ['soon', 'quickly', 'expedite', 'important']
        low_keywords = ['whenever', 'no rush', 'eventually', 'low priority']
        
        if any(word in text_lower for word in urgent_keywords):
            priority = 1
        elif any(word in text_lower for word in medium_keywords):
            priority = 2
        elif any(word in text_lower for word in low_keywords):
            priority = 4
        elif intent == 'leave_request' and 'sick' in text_lower:
            priority = 1  # Sick leave is high priority
    
    # Entity extraction
    entities = extract_entities(text, intent)
    
    # Add context-based entities
    if context:
        entities.update(context)
    
    # Generate suggested actions based on intent and entities
    suggested_actions = generate_suggested_actions(intent, entities, priority)
    
    return {
        'intent': intent,
        'entities': entities,
        'priority': priority,
        'confidence': min(confidence + 0.15, 1.0),  # Boost confidence slightly
        'intent_scores': intent_scores,
        'suggested_actions': suggested_actions,
        'processing_timestamp': datetime.utcnow().isoformat() + 'Z'
    }


def extract_entities(text, intent):
    """
    Extract relevant entities from text based on intent.
    """
    entities = {}
    
    # Extract monetary amounts
    money_patterns = [
        r'\$(\d+(?:,\d{3})*(?:\.\d{2})?)',
        r'(\d+(?:,\d{3})*(?:\.\d{2})?) dollars?',
        r'(\d+(?:,\d{3})*(?:\.\d{2})?) USD'
    ]
    
    for pattern in money_patterns:
        money_matches = re.findall(pattern, text, re.IGNORECASE)
        if money_matches:
            entities['amount'] = money_matches[0].replace(',', '')
            break
    
    # Extract dates (simplified patterns)
    date_patterns = [
        r'(\d{1,2}/\d{1,2}/\d{4})',
        r'(\d{4}-\d{2}-\d{2})',
        r'(january|february|march|april|may|june|july|august|september|october|november|december)\s+\d{1,2}(?:st|nd|rd|th)?(?:,?\s+\d{4})?',
        r'(today|tomorrow|yesterday)',
        r'(next week|next month|this week|this month)',
        r'(\d{1,2})\s+(days?|weeks?|months?)\s+(from now|ago)'
    ]
    
    for pattern in date_patterns:
        dates = re.findall(pattern, text, re.IGNORECASE)
        if dates:
            entities['date'] = dates[0] if isinstance(dates[0], str) else dates[0][0]
            break
    
    # Extract duration for leave requests
    if intent == 'leave_request':
        duration_patterns = [
            r'(\d+)\s+(days?|weeks?|months?)',
            r'(half day|full day)',
            r'(morning|afternoon|evening)'
        ]
        
        for pattern in duration_patterns:
            duration_matches = re.findall(pattern, text, re.IGNORECASE)
            if duration_matches:
                entities['duration'] = duration_matches[0] if isinstance(duration_matches[0], str) else ' '.join(duration_matches[0])
                break
    
    # Extract categories/reasons
    if intent == 'expense_approval':
        expense_categories = ['travel', 'meals', 'office supplies', 'equipment', 'software', 'training', 'marketing', 'entertainment']
        for category in expense_categories:
            if category in text.lower():
                entities['category'] = category
                break
    
    # Extract system/resource names for access requests
    if intent == 'access_request':
        system_patterns = [
            r'access to ([A-Z][a-zA-Z\s]+)',
            r'([A-Z][a-zA-Z]+) system',
            r'([A-Z][a-zA-Z]+) database',
            r'([A-Z][a-zA-Z]+) application'
        ]
        
        for pattern in system_patterns:
            system_matches = re.findall(pattern, text)
            if system_matches:
                entities['system'] = system_matches[0].strip()
                break
    
    # Extract vendor/supplier information for procurement
    if intent == 'procurement_request':
        vendor_pattern = r'(?:from|vendor|supplier)\s+([A-Z][a-zA-Z\s&\.]+)'
        vendor_matches = re.findall(vendor_pattern, text)
        if vendor_matches:
            entities['vendor'] = vendor_matches[0].strip()
    
    # Extract location for travel requests
    if intent == 'travel_request':
        location_patterns = [
            r'to ([A-Z][a-zA-Z\s,]+)',
            r'in ([A-Z][a-zA-Z\s,]+)',
            r'visit ([A-Z][a-zA-Z\s,]+)'
        ]
        
        for pattern in location_patterns:
            location_matches = re.findall(pattern, text)
            if location_matches:
                entities['destination'] = location_matches[0].strip()
                break
    
    # Extract general purpose/reason
    purpose_patterns = [
        r'for (.+?)(?:\.|$)',
        r'because (.+?)(?:\.|$)',
        r'to (.+?)(?:\.|$)'
    ]
    
    for pattern in purpose_patterns:
        purpose_matches = re.findall(pattern, text, re.IGNORECASE)
        if purpose_matches and len(purpose_matches[0]) > 5:  # Avoid very short matches
            entities['purpose'] = purpose_matches[0].strip()[:100]  # Limit length
            break
    
    return entities


def generate_suggested_actions(intent, entities, priority):
    """
    Generate suggested actions based on intent, entities, and priority.
    """
    actions = []
    
    base_actions = {
        'expense_approval': [
            'Submit receipt documentation',
            'Verify expense policy compliance',
            'Route to appropriate approver',
            'Track approval status'
        ],
        'leave_request': [
            'Check leave balance',
            'Verify coverage arrangements',
            'Submit to manager for approval',
            'Update calendar and systems'
        ],
        'access_request': [
            'Verify business justification',
            'Check security clearance requirements',
            'Route to system administrator',
            'Schedule access provisioning'
        ],
        'procurement_request': [
            'Verify budget availability',
            'Check vendor approval status',
            'Submit purchase requisition',
            'Track order status'
        ],
        'travel_request': [
            'Check travel policy compliance',
            'Verify budget authorization',
            'Submit travel authorization',
            'Book travel arrangements'
        ],
        'general_request': [
            'Clarify request requirements',
            'Identify appropriate department',
            'Route for initial review',
            'Track request progress'
        ]
    }
    
    actions = base_actions.get(intent, base_actions['general_request']).copy()
    
    # Add priority-specific actions
    if priority == 1:  # High priority
        actions.insert(0, 'Flag as urgent request')
        actions.append('Set up expedited processing')
    elif priority == 4:  # Very low priority
        actions.append('Schedule for batch processing')
    
    # Add entity-specific actions
    if 'amount' in entities:
        amount = float(entities['amount'].replace(',', ''))
        if amount > 1000:
            actions.append('Require additional approval level')
        if amount > 5000:
            actions.append('Submit to finance committee')
    
    if 'date' in entities and any(urgent in entities['date'].lower() for urgent in ['today', 'tomorrow', 'asap']):
        actions.insert(0, 'Process immediately')
    
    return actions


def generate_next_steps(processed_request):
    """
    Generate next steps for the user based on the processed request.
    """
    intent = processed_request['intent']
    priority = processed_request['priority']
    confidence = processed_request['confidence']
    
    next_steps = []
    
    # Confidence-based steps
    if confidence < 0.7:
        next_steps.append({
            'step': 'Review AI interpretation',
            'description': 'The AI had moderate confidence in understanding your request. Please review the interpretation and provide clarification if needed.',
            'priority': 'high'
        })
    
    # Intent-specific next steps
    intent_steps = {
        'expense_approval': [
            {
                'step': 'Upload receipt',
                'description': 'Attach receipt or supporting documentation for the expense.',
                'priority': 'high'
            },
            {
                'step': 'Await manager approval',
                'description': 'Your manager will be notified and will review the request.',
                'priority': 'medium'
            }
        ],
        'leave_request': [
            {
                'step': 'Confirm dates',
                'description': 'Verify the leave dates and ensure coverage is arranged.',
                'priority': 'high'
            },
            {
                'step': 'HR review',
                'description': 'HR will review your leave balance and policy compliance.',
                'priority': 'medium'
            }
        ],
        'access_request': [
            {
                'step': 'Security review',
                'description': 'Security team will review the access requirements and business justification.',
                'priority': 'high'
            },
            {
                'step': 'Account provisioning',
                'description': 'Once approved, system administrator will provision the requested access.',
                'priority': 'low'
            }
        ]
    }
    
    next_steps.extend(intent_steps.get(intent, [
        {
            'step': 'Initial review',
            'description': 'Your request will be reviewed by the appropriate department.',
            'priority': 'medium'
        }
    ]))
    
    # Priority-based steps
    if priority == 1:
        next_steps.insert(0, {
            'step': 'Immediate processing',
            'description': 'This request has been flagged as urgent and will be processed immediately.',
            'priority': 'high'
        })
    
    # Add tracking step
    next_steps.append({
        'step': 'Track progress',
        'description': f'Monitor your request status using ID: {processed_request.get("request_id", "TBD")}',
        'priority': 'low'
    })
    
    return next_steps


def get_database_connection():
    """
    Establish connection to Cloud SQL database.
    Supports both Unix socket (private) and TCP (public) connections.
    """
    project_id = os.environ.get('PROJECT_ID', '${project_id}')
    region = os.environ.get('REGION', '${region}')
    db_instance = os.environ.get('DB_INSTANCE', '${db_instance}')
    db_password = os.environ.get('DB_PASSWORD')
    
    if not db_password:
        raise ValueError("DB_PASSWORD environment variable not set")
    
    # Try Unix socket connection first (for private IP)
    db_socket_path = "/cloudsql"
    instance_connection_name = f"{project_id}:{region}:{db_instance}"
    
    try:
        # Attempt Unix socket connection
        unix_socket = f"{db_socket_path}/{instance_connection_name}/.s.PGSQL.5432"
        conn = pg8000.connect(
            user='postgres',
            password=db_password,
            unix_sock=unix_socket,
            database='business_processes'
        )
        logger.info("Connected to database via Unix socket")
        return conn
        
    except Exception as unix_error:
        logger.warning(f"Unix socket connection failed: {unix_error}")
        
        # Fallback to TCP connection (for public IP)
        try:
            conn = pg8000.connect(
                user='postgres',
                password=db_password,
                host='127.0.0.1',  # This would be the actual Cloud SQL IP
                port=5432,
                database='business_processes'
            )
            logger.info("Connected to database via TCP")
            return conn
            
        except Exception as tcp_error:
            logger.error(f"TCP connection failed: {tcp_error}")
            raise Exception(f"Failed to connect to database. Unix socket: {unix_error}, TCP: {tcp_error}")


if __name__ == "__main__":
    # For local testing
    import sys
    from unittest.mock import Mock
    
    # Mock request for testing
    mock_request = Mock()
    mock_request.method = 'POST'
    mock_request.get_json.return_value = {
        'message': 'I need approval for a $500 expense for office supplies',
        'user_email': 'employee@company.com',
        'context': {'department': 'Engineering'},
        'priority_override': None
    }
    
    print("Testing AI agent function...")
    try:
        result = process_natural_language(mock_request)
        print(f"Result: {result}")
    except Exception as e:
        print(f"Error: {e}")