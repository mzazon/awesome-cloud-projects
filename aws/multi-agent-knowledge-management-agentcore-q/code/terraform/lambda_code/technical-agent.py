# Technical Agent for Multi-Agent Knowledge Management System
# Specializes in engineering documentation and system procedures

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
    Technical specialist agent for engineering and system queries
    """
    try:
        # Parse request
        query = event.get('query', '')
        session_id = event.get('sessionId', str(uuid.uuid4()))
        context_info = event.get('context', '')
        
        logger.info(f"Technical agent processing query: {query}")
        
        # Try Q Business integration first, fallback to static responses
        try:
            # Q Business integration (when available)
            q_app_id = os.environ.get('Q_APP_ID')
            if q_app_id and q_app_id != 'placeholder':
                response = query_q_business(q_app_id, query, session_id)
            else:
                response = get_technical_fallback(query)
        except Exception as qb_error:
            logger.error(f"Q Business error: {str(qb_error)}")
            response = get_technical_fallback(query)
        
        # Format response with technical context
        formatted_response = format_technical_response(response, query)
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'agent': 'technical',
                'response': formatted_response,
                'sources': ['Technical Guidelines Documentation'],
                'domain': 'technical'
            })
        }
        
    except Exception as e:
        logger.error(f"Technical agent error: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': f"Technical agent error: {str(e)}"
            })
        }

def query_q_business(app_id: str, query: str, session_id: str) -> str:
    """Query Q Business for technical-specific information"""
    try:
        qbusiness = boto3.client('qbusiness')
        
        # Create or get conversation
        conversation_response = qbusiness.create_conversation(
            applicationId=app_id,
            title=f"Technical Query - {session_id[:8]}"
        )
        conversation_id = conversation_response['conversationId']
        
        # Query Q Business with technical context
        chat_response = qbusiness.chat_sync(
            applicationId=app_id,
            conversationId=conversation_id,
            userMessage=f"Technical documentation and system procedures context: {query}. Focus on development standards, infrastructure management, API guidelines, and security procedures.",
            userGroups=['engineering'],
            userId='technical-agent'
        )
        
        # Extract relevant information
        system_message = chat_response.get('systemMessage', '')
        return system_message if system_message else get_technical_fallback(query)
        
    except Exception as e:
        logger.error(f"Q Business query error: {str(e)}")
        return get_technical_fallback(query)

def format_technical_response(message: str, query: str) -> str:
    """Format technical response with appropriate context and standards"""
    if not message:
        return get_technical_fallback(query)
    
    formatted = f"Technical Documentation:\\n{message}"
    
    # Add standards compliance note
    formatted += "\\n\\n*Ensure all implementations follow current security and development standards.*"
    
    return formatted

def get_technical_fallback(query: str) -> str:
    """Provide fallback technical information when Q Business is unavailable"""
    query_lower = query.lower()
    
    if 'code' in query_lower or 'development' in query_lower:
        return "Development standards: All code requires automated testing before deployment, minimum 80% code coverage for production, security scans for external applications."
    elif 'backup' in query_lower or 'database' in query_lower:
        return "Infrastructure management: Database backups performed nightly at 2 AM UTC, 30-day local retention, 90-day archive retention, quarterly DR testing."
    elif 'api' in query_lower:
        return "API standards: 1000 requests per minute rate limit, authentication required for all endpoints, SSL/TLS 1.2 minimum for communications."
    elif 'security' in query_lower:
        return "Security procedures: Security patching within 48 hours for critical vulnerabilities, SSL/TLS 1.2 minimum, authentication required for all API endpoints."
    elif 'deployment' in query_lower or 'deploy' in query_lower:
        return "Deployment standards: Automated testing pipeline required, staging environment validation, blue-green deployment for zero-downtime releases."
    elif 'monitoring' in query_lower:
        return "Monitoring guidelines: CloudWatch metrics for all services, custom dashboards for business KPIs, alerting for system health and performance thresholds."
    elif 'docker' in query_lower or 'container' in query_lower:
        return "Container standards: Official base images only, vulnerability scanning in CI/CD, resource limits defined, health checks implemented."
    else:
        return "Technical guidelines cover development standards, infrastructure management, API protocols, and security procedures. Consult complete documentation for implementation details."