# Supervisor Agent for Multi-Agent Knowledge Management System
# Coordinates specialized agents for comprehensive knowledge retrieval

import json
import boto3
import os
from typing import List, Dict, Any
import uuid
import logging

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    """
    Supervisor agent that coordinates specialized agents for knowledge retrieval
    """
    try:
        # Initialize AWS clients
        lambda_client = boto3.client('lambda')
        dynamodb = boto3.resource('dynamodb')
        
        # Handle API Gateway event format
        if 'body' in event:
            if isinstance(event['body'], str):
                body = json.loads(event['body'])
            else:
                body = event['body']
        else:
            body = event
        
        # Handle health check
        if event.get('requestContext', {}).get('http', {}).get('path') == '/health':
            return {
                'statusCode': 200,
                'headers': {
                    'Content-Type': 'application/json',
                    'Access-Control-Allow-Origin': '*'
                },
                'body': json.dumps({
                    'status': 'healthy',
                    'service': 'multi-agent-supervisor',
                    'timestamp': context.aws_request_id
                })
            }
        
        # Parse request
        query = body.get('query', '')
        session_id = body.get('sessionId', str(uuid.uuid4()))
        
        logger.info(f"Processing query: {query} for session: {session_id}")
        
        # Determine which agents to engage based on query analysis
        agents_to_engage = determine_agents(query)
        logger.info(f"Engaging agents: {agents_to_engage}")
        
        # Collect responses from specialized agents
        agent_responses = []
        for agent_name in agents_to_engage:
            try:
                response = invoke_specialized_agent(lambda_client, agent_name, query, session_id)
                agent_responses.append({
                    'agent': agent_name,
                    'response': response,
                    'confidence': calculate_confidence(agent_name, query)
                })
            except Exception as e:
                logger.error(f"Error invoking {agent_name} agent: {str(e)}")
                agent_responses.append({
                    'agent': agent_name,
                    'response': f"Error retrieving {agent_name} information",
                    'confidence': 0.0
                })
        
        # Synthesize comprehensive answer
        final_response = synthesize_responses(query, agent_responses)
        
        # Store session information for context
        store_session_context(session_id, query, final_response, agents_to_engage, context)
        
        return {
            'statusCode': 200,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({
                'query': query,
                'response': final_response,
                'agents_consulted': agents_to_engage,
                'session_id': session_id,
                'confidence_scores': {resp['agent']: resp['confidence'] for resp in agent_responses}
            })
        }
        
    except Exception as e:
        logger.error(f"Supervisor agent error: {str(e)}")
        return {
            'statusCode': 500,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({
                'error': f"Supervisor agent error: {str(e)}"
            })
        }

def determine_agents(query: str) -> List[str]:
    """Determine which specialized agents to engage based on query analysis"""
    query_lower = query.lower()
    agents = []
    
    # Finance-related keywords
    finance_keywords = ['budget', 'expense', 'cost', 'finance', 'money', 'approval', 
                       'reimbursement', 'travel', 'spending', 'capital', 'cfo']
    if any(word in query_lower for word in finance_keywords):
        agents.append('finance')
    
    # HR-related keywords
    hr_keywords = ['employee', 'hr', 'vacation', 'onboard', 'performance', 'leave',
                   'remote', 'work', 'benefits', 'policy', 'review', 'sick']
    if any(word in query_lower for word in hr_keywords):
        agents.append('hr')
    
    # Technical-related keywords
    tech_keywords = ['technical', 'code', 'api', 'database', 'security', 'backup',
                     'system', 'development', 'infrastructure', 'server', 'ssl']
    if any(word in query_lower for word in tech_keywords):
        agents.append('technical')
    
    # If no specific domain detected, engage all agents for comprehensive coverage
    return agents if agents else ['finance', 'hr', 'technical']

def calculate_confidence(agent_name: str, query: str) -> float:
    """Calculate confidence score for agent relevance to query"""
    query_lower = query.lower()
    
    if agent_name == 'finance':
        finance_keywords = ['budget', 'expense', 'cost', 'finance', 'money', 'approval']
        matches = sum(1 for word in finance_keywords if word in query_lower)
        return min(matches * 0.2, 1.0)
    elif agent_name == 'hr':
        hr_keywords = ['employee', 'hr', 'vacation', 'onboard', 'performance', 'leave']
        matches = sum(1 for word in hr_keywords if word in query_lower)
        return min(matches * 0.2, 1.0)
    elif agent_name == 'technical':
        tech_keywords = ['technical', 'code', 'api', 'database', 'security', 'backup']
        matches = sum(1 for word in tech_keywords if word in query_lower)
        return min(matches * 0.2, 1.0)
    
    return 0.5  # Default confidence

def invoke_specialized_agent(lambda_client, agent_name: str, query: str, session_id: str) -> str:
    """Invoke a specialized agent Lambda function"""
    function_name = f"{agent_name}-agent-${random_suffix}"
    
    try:
        response = lambda_client.invoke(
            FunctionName=function_name,
            InvocationType='RequestResponse',
            Payload=json.dumps({
                'query': query,
                'sessionId': session_id,
                'context': f"Domain-specific query for {agent_name} expertise"
            })
        )
        
        result = json.loads(response['Payload'].read())
        if result.get('statusCode') == 200:
            body = json.loads(result.get('body', '{}'))
            return body.get('response', f"No {agent_name} information available")
        else:
            return f"Error retrieving {agent_name} information"
            
    except Exception as e:
        logger.error(f"Error invoking {agent_name} agent: {str(e)}")
        return f"Error accessing {agent_name} knowledge base"

def synthesize_responses(query: str, responses: List[Dict]) -> str:
    """Synthesize responses from multiple agents into a comprehensive answer"""
    if not responses:
        return "No relevant information found in the knowledge base."
    
    # Filter responses by confidence score
    high_confidence_responses = [r for r in responses if r.get('confidence', 0) > 0.3]
    responses_to_use = high_confidence_responses if high_confidence_responses else responses
    
    synthesis = f"Based on consultation with {len(responses_to_use)} specialized knowledge domains:\\n\\n"
    
    for resp in responses_to_use:
        if resp['response'] and not resp['response'].startswith('Error'):
            confidence_indicator = "🔷" if resp.get('confidence', 0) > 0.6 else "🔹"
            synthesis += f"{confidence_indicator} **{resp['agent'].title()} Domain**: {resp['response']}\\n\\n"
    
    synthesis += "\\n*This response was generated by consulting multiple specialized knowledge agents.*"
    return synthesis

def store_session_context(session_id: str, query: str, response: str, agents: List[str], context):
    """Store session context for future reference"""
    try:
        table_name = os.environ.get('SESSION_TABLE', '${session_table}')
        dynamodb = boto3.resource('dynamodb')
        table = dynamodb.Table(table_name)
        
        import time
        ttl_timestamp = int(time.time()) + (24 * 60 * 60)  # 24 hours from now
        
        table.put_item(
            Item={
                'sessionId': session_id,
                'timestamp': context.aws_request_id,
                'query': query,
                'response': response,
                'agents_consulted': agents,
                'ttl': ttl_timestamp
            }
        )
    except Exception as e:
        logger.error(f"Error storing session context: {str(e)}")