# HR Agent for Multi-Agent Knowledge Management System
# Specializes in human resources policies and employee-related queries

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
    HR specialist agent for employee and policy queries
    """
    try:
        # Parse request
        query = event.get('query', '')
        session_id = event.get('sessionId', str(uuid.uuid4()))
        context_info = event.get('context', '')
        
        logger.info(f"HR agent processing query: {query}")
        
        # Try Q Business integration first, fallback to static responses
        try:
            # Q Business integration (when available)
            q_app_id = os.environ.get('Q_APP_ID')
            if q_app_id and q_app_id != 'placeholder':
                response = query_q_business(q_app_id, query, session_id)
            else:
                response = get_hr_fallback(query)
        except Exception as qb_error:
            logger.error(f"Q Business error: {str(qb_error)}")
            response = get_hr_fallback(query)
        
        # Format response with HR context
        formatted_response = format_hr_response(response, query)
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'agent': 'hr',
                'response': formatted_response,
                'sources': ['HR Handbook and Policies'],
                'domain': 'hr'
            })
        }
        
    except Exception as e:
        logger.error(f"HR agent error: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': f"HR agent error: {str(e)}"
            })
        }

def query_q_business(app_id: str, query: str, session_id: str) -> str:
    """Query Q Business for HR-specific information"""
    try:
        qbusiness = boto3.client('qbusiness')
        
        # Create or get conversation
        conversation_response = qbusiness.create_conversation(
            applicationId=app_id,
            title=f"HR Query - {session_id[:8]}"
        )
        conversation_id = conversation_response['conversationId']
        
        # Query Q Business with HR-specific context
        chat_response = qbusiness.chat_sync(
            applicationId=app_id,
            conversationId=conversation_id,
            userMessage=f"HR policy and employee procedures context: {query}. Focus on employee policies, benefits, performance management, and workplace procedures.",
            userGroups=['hr'],
            userId='hr-agent'
        )
        
        # Extract relevant information
        system_message = chat_response.get('systemMessage', '')
        return system_message if system_message else get_hr_fallback(query)
        
    except Exception as e:
        logger.error(f"Q Business query error: {str(e)}")
        return get_hr_fallback(query)

def format_hr_response(message: str, query: str) -> str:
    """Format HR response with appropriate context and confidentiality notices"""
    if not message:
        return get_hr_fallback(query)
    
    formatted = f"HR Policy Information:\\n{message}"
    
    # Add confidentiality notice for sensitive HR information
    formatted += "\\n\\n*Note: HR information is confidential and subject to privacy policies.*"
    
    return formatted

def get_hr_fallback(query: str) -> str:
    """Provide fallback HR information when Q Business is unavailable"""
    query_lower = query.lower()
    
    if 'onboard' in query_lower:
        return "Onboarding process: 3-5 business days completion, IT setup on first day, benefits enrollment within 30 days of start date."
    elif 'performance' in query_lower or 'review' in query_lower:
        return "Performance management: Annual reviews in Q4, mid-year check-ins in Q2, performance improvement plans have 90-day duration."
    elif 'vacation' in query_lower or 'leave' in query_lower:
        return "Time off policies: Vacation requires 2-week advance notice, 10 sick days annually (5 carry-over), 12 weeks paid parental leave plus 4 weeks unpaid."
    elif 'remote' in query_lower or 'work' in query_lower:
        return "Remote work policy: Up to 3 days per week remote work allowed, subject to role requirements and manager approval."
    elif 'benefits' in query_lower:
        return "Benefits enrollment: 30-day window from start date. Includes health insurance, dental, vision, 401k with company match, and wellness programs."
    elif 'pto' in query_lower or 'time off' in query_lower:
        return "PTO policy: Accrual based on tenure, minimum 2-week advance notice for vacation, sick leave separate allocation, holidays per company calendar."
    else:
        return "HR policies cover onboarding, performance management, time off, and workplace procedures. Consult complete handbook for specific guidance."