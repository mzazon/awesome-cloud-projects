import json
import boto3
import logging
import os
from datetime import datetime, timedelta
from typing import Dict, Any, Optional
import uuid

# Configure logging
logger = logging.getLogger()
logger.setLevel(os.environ.get('LOG_LEVEL', 'INFO'))

# Initialize AWS clients
eventbridge = boto3.client('events')
dynamodb = boto3.resource('dynamodb')
bedrock_agent = boto3.client('bedrock-agent-runtime')

# Environment variables
EVENT_BUS_NAME = os.environ['EVENT_BUS_NAME']
MEMORY_TABLE_NAME = os.environ['MEMORY_TABLE_NAME']
SUPERVISOR_AGENT_ID = os.environ['SUPERVISOR_AGENT_ID']
FINANCE_AGENT_ID = os.environ['FINANCE_AGENT_ID']
SUPPORT_AGENT_ID = os.environ['SUPPORT_AGENT_ID']
ANALYTICS_AGENT_ID = os.environ['ANALYTICS_AGENT_ID']

# Agent mapping for routing
AGENT_MAPPING = {
    'financial_analysis': FINANCE_AGENT_ID,
    'customer_support': SUPPORT_AGENT_ID,
    'data_analytics': ANALYTICS_AGENT_ID,
    'supervisor': SUPERVISOR_AGENT_ID
}

def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Main Lambda handler for multi-agent workflow coordination.
    
    Processes EventBridge events and coordinates tasks between specialized agents.
    Maintains workflow state in DynamoDB and publishes coordination events.
    """
    try:
        logger.info(f"Processing event: {json.dumps(event)}")
        
        # Handle different event sources
        if 'source' in event and event['source'] == 'aws.events':
            # EventBridge scheduled event
            return handle_scheduled_event(event, context)
        elif 'Records' in event:
            # EventBridge event via SQS or direct invocation
            return handle_eventbridge_event(event, context)
        else:
            # Direct API Gateway invocation
            return handle_api_request(event, context)
            
    except Exception as e:
        logger.error(f"Error processing event: {str(e)}", exc_info=True)
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': str(e),
                'requestId': context.aws_request_id
            })
        }

def handle_api_request(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """Handle direct API Gateway requests for agent coordination."""
    try:
        # Parse request body
        body = json.loads(event.get('body', '{}'))
        
        task_type = body.get('taskType', 'supervisor')
        user_input = body.get('input', '')
        session_id = body.get('sessionId', f"session-{uuid.uuid4()}")
        correlation_id = body.get('correlationId', f"corr-{uuid.uuid4()}")
        
        logger.info(f"API request - Task: {task_type}, Session: {session_id}")
        
        # Route to appropriate agent
        if task_type == 'multi_agent_coordination':
            # Use supervisor for complex multi-agent tasks
            result = invoke_supervisor_agent(user_input, session_id, correlation_id)
        else:
            # Direct agent invocation
            result = invoke_specialized_agent(task_type, user_input, session_id, correlation_id)
        
        # Store interaction in memory table
        store_interaction_memory(session_id, task_type, user_input, result, correlation_id)
        
        return {
            'statusCode': 200,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({
                'result': result,
                'sessionId': session_id,
                'correlationId': correlation_id,
                'timestamp': datetime.utcnow().isoformat()
            })
        }
        
    except Exception as e:
        logger.error(f"API request error: {str(e)}", exc_info=True)
        return {
            'statusCode': 400,
            'body': json.dumps({'error': str(e)})
        }

def handle_eventbridge_event(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """Handle EventBridge events for agent task coordination."""
    try:
        # Extract EventBridge event details
        if 'Records' in event:
            # SQS wrapped EventBridge event
            for record in event['Records']:
                if 'body' in record:
                    event_body = json.loads(record['body'])
                    process_coordination_event(event_body, context)
        else:
            # Direct EventBridge event
            process_coordination_event(event, context)
        
        return {
            'statusCode': 200,
            'body': json.dumps({'message': 'Events processed successfully'})
        }
        
    except Exception as e:
        logger.error(f"EventBridge event error: {str(e)}", exc_info=True)
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }

def handle_scheduled_event(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """Handle scheduled maintenance and monitoring events."""
    try:
        logger.info("Processing scheduled maintenance event")
        
        # Cleanup old memory records
        cleanup_old_memory_records()
        
        # Publish system health metrics
        publish_health_metrics()
        
        return {
            'statusCode': 200,
            'body': json.dumps({'message': 'Scheduled maintenance completed'})
        }
        
    except Exception as e:
        logger.error(f"Scheduled event error: {str(e)}", exc_info=True)
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }

def process_coordination_event(event_data: Dict[str, Any], context: Any) -> None:
    """Process individual coordination events between agents."""
    detail = event_data.get('detail', {})
    
    task_type = detail.get('taskType')
    request_data = detail.get('requestData')
    correlation_id = detail.get('correlationId')
    session_id = detail.get('sessionId', correlation_id)
    
    logger.info(f"Processing coordination event - Task: {task_type}, Correlation: {correlation_id}")
    
    # Route task to appropriate agent
    if task_type in AGENT_MAPPING:
        agent_response = invoke_specialized_agent(task_type, request_data, session_id, correlation_id)
        
        # Store result in memory
        store_interaction_memory(session_id, task_type, request_data, agent_response, correlation_id)
        
        # Publish completion event
        publish_completion_event(correlation_id, task_type, agent_response, 'completed')
    else:
        logger.warning(f"Unknown task type: {task_type}")
        publish_completion_event(correlation_id, task_type, "Unknown task type", 'failed')

def invoke_supervisor_agent(user_input: str, session_id: str, correlation_id: str) -> str:
    """Invoke the supervisor agent for complex multi-agent coordination."""
    try:
        logger.info(f"Invoking supervisor agent for session: {session_id}")
        
        response = bedrock_agent.invoke_agent(
            agentId=SUPERVISOR_AGENT_ID,
            agentAliasId='production',
            sessionId=session_id,
            inputText=user_input
        )
        
        # Process the response stream
        result = ""
        event_stream = response['completion']
        
        for event in event_stream:
            if 'chunk' in event:
                chunk = event['chunk']
                if 'bytes' in chunk:
                    result += chunk['bytes'].decode('utf-8')
        
        logger.info(f"Supervisor agent response received for session: {session_id}")
        return result
        
    except Exception as e:
        logger.error(f"Supervisor agent error: {str(e)}", exc_info=True)
        return f"Error invoking supervisor agent: {str(e)}"

def invoke_specialized_agent(task_type: str, user_input: str, session_id: str, correlation_id: str) -> str:
    """Invoke a specialized agent based on task type."""
    try:
        agent_id = AGENT_MAPPING.get(task_type)
        if not agent_id:
            return f"No agent found for task type: {task_type}"
        
        logger.info(f"Invoking {task_type} agent for session: {session_id}")
        
        response = bedrock_agent.invoke_agent(
            agentId=agent_id,
            agentAliasId='production',
            sessionId=session_id,
            inputText=user_input
        )
        
        # Process the response stream
        result = ""
        event_stream = response['completion']
        
        for event in event_stream:
            if 'chunk' in event:
                chunk = event['chunk']
                if 'bytes' in chunk:
                    result += chunk['bytes'].decode('utf-8')
        
        logger.info(f"Agent {task_type} response received for session: {session_id}")
        return result
        
    except Exception as e:
        logger.error(f"Specialized agent error for {task_type}: {str(e)}", exc_info=True)
        return f"Error invoking {task_type} agent: {str(e)}"

def store_interaction_memory(session_id: str, task_type: str, user_input: str, 
                           agent_response: str, correlation_id: str) -> None:
    """Store agent interaction in DynamoDB memory table."""
    try:
        memory_table = dynamodb.Table(MEMORY_TABLE_NAME)
        
        timestamp = int(datetime.utcnow().timestamp() * 1000)  # Milliseconds for precision
        expires_at = int((datetime.utcnow() + timedelta(days=30)).timestamp())
        
        memory_table.put_item(
            Item={
                'SessionId': session_id,
                'Timestamp': timestamp,
                'TaskType': task_type,
                'UserInput': user_input,
                'AgentResponse': agent_response,
                'CorrelationId': correlation_id,
                'AgentId': AGENT_MAPPING.get(task_type, 'unknown'),
                'ExpiresAt': expires_at,
                'CreatedAt': datetime.utcnow().isoformat(),
                'Status': 'completed'
            }
        )
        
        logger.debug(f"Stored memory for session: {session_id}, task: {task_type}")
        
    except Exception as e:
        logger.error(f"Error storing memory: {str(e)}", exc_info=True)

def publish_completion_event(correlation_id: str, task_type: str, result: str, status: str) -> None:
    """Publish task completion event to EventBridge."""
    try:
        eventbridge.put_events(
            Entries=[
                {
                    'Source': 'multi-agent.coordinator',
                    'DetailType': f'Agent Task {status.title()}',
                    'Detail': json.dumps({
                        'correlationId': correlation_id,
                        'taskType': task_type,
                        'result': result[:1000],  # Truncate for event size limits
                        'status': status,
                        'timestamp': datetime.utcnow().isoformat()
                    }),
                    'EventBusName': EVENT_BUS_NAME
                }
            ]
        )
        
        logger.debug(f"Published {status} event for correlation: {correlation_id}")
        
    except Exception as e:
        logger.error(f"Error publishing event: {str(e)}", exc_info=True)

def cleanup_old_memory_records() -> None:
    """Clean up old memory records beyond retention period."""
    try:
        memory_table = dynamodb.Table(MEMORY_TABLE_NAME)
        
        # DynamoDB TTL will handle automatic cleanup
        # This could implement additional cleanup logic if needed
        
        logger.info("Memory cleanup completed")
        
    except Exception as e:
        logger.error(f"Memory cleanup error: {str(e)}", exc_info=True)

def publish_health_metrics() -> None:
    """Publish system health metrics to CloudWatch."""
    try:
        cloudwatch = boto3.client('cloudwatch')
        
        # Example health metrics
        cloudwatch.put_metric_data(
            Namespace='MultiAgent/Coordinator',
            MetricData=[
                {
                    'MetricName': 'HealthCheck',
                    'Value': 1,
                    'Unit': 'Count',
                    'Timestamp': datetime.utcnow()
                }
            ]
        )
        
        logger.debug("Health metrics published")
        
    except Exception as e:
        logger.error(f"Health metrics error: {str(e)}", exc_info=True)