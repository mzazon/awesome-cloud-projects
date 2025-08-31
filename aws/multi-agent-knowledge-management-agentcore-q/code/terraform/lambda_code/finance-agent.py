# Finance Agent for Multi-Agent Knowledge Management System
# Specializes in financial policy and budget-related queries

import json
import boto3
import os
import logging
import uuid

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    """
    Finance specialist agent for budget and financial policy queries
    """
    try:
        # Parse request
        query = event.get('query', '')
        session_id = event.get('sessionId', str(uuid.uuid4()))
        context_info = event.get('context', '')
        
        logger.info(f"Finance agent processing query: {query}")
        
        # Try Q Business integration first, fallback to static responses
        try:
            # Q Business integration (when available)
            q_app_id = os.environ.get('Q_APP_ID')
            if q_app_id and q_app_id != 'placeholder':
                response = query_q_business(q_app_id, query, session_id)
            else:
                response = get_finance_fallback(query)
        except Exception as qb_error:
            logger.error(f"Q Business error: {str(qb_error)}")
            response = get_finance_fallback(query)
        
        # Format response with finance context
        formatted_response = format_finance_response(response, query)
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'agent': 'finance',
                'response': formatted_response,
                'sources': ['Finance Policy Documentation'],
                'domain': 'finance'
            })
        }
        
    except Exception as e:
        logger.error(f"Finance agent error: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': f"Finance agent error: {str(e)}"
            })
        }

def query_q_business(app_id: str, query: str, session_id: str) -> str:
    """Query Q Business for finance-specific information"""
    try:
        qbusiness = boto3.client('qbusiness')
        
        # Create or get conversation
        conversation_response = qbusiness.create_conversation(
            applicationId=app_id,
            title=f"Finance Query - {session_id[:8]}"
        )
        conversation_id = conversation_response['conversationId']
        
        # Query Q Business with finance-specific context
        chat_response = qbusiness.chat_sync(
            applicationId=app_id,
            conversationId=conversation_id,
            userMessage=f"Finance policy and budget context: {query}. Focus on financial procedures, approval processes, and budget guidelines.",
            userGroups=['finance'],
            userId='finance-agent'
        )
        
        # Extract relevant information
        system_message = chat_response.get('systemMessage', '')
        return system_message if system_message else get_finance_fallback(query)
        
    except Exception as e:
        logger.error(f"Q Business query error: {str(e)}")
        return get_finance_fallback(query)

def format_finance_response(message: str, query: str) -> str:
    """Format finance response with context and sources"""
    if not message:
        return get_finance_fallback(query)
    
    formatted = f"Financial Policy Information:\\n{message}"
    return formatted

def get_finance_fallback(query: str) -> str:
    """Provide fallback finance information when Q Business is unavailable"""
    query_lower = query.lower()
    
    if 'expense' in query_lower or 'approval' in query_lower:
        return "Expense approval process: Expenses over $1000 require manager approval, over $5000 require director approval, and over $10000 require CFO approval."
    elif 'budget' in query_lower:
        return "Budget management: Quarterly reviews conducted in March, June, September, December. Annual allocations updated in January."
    elif 'travel' in query_lower or 'reimbursement' in query_lower:
        return "Travel policy: Reimbursement requires receipts within 30 days. International travel needs 2-week pre-approval. Daily allowances: $75 domestic, $100 international."
    elif 'capital' in query_lower:
        return "Capital expenditure approval: Amounts over $10000 require CFO approval with detailed business justification and ROI analysis."
    elif 'emergency' in query_lower:
        return "Emergency budget requests: Require 48-hour approval window with director sign-off and detailed justification for urgency."
    else:
        return "Finance policies cover expense approvals, budget management, and travel procedures. Specific policies require review of complete documentation."