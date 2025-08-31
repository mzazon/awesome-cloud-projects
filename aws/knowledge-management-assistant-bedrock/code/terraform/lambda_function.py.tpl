import json
import boto3
import os
import logging
from botocore.exceptions import ClientError

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    """
    Enhanced Lambda handler for Bedrock Agent integration
    with improved error handling and logging
    """
    # Initialize Bedrock Agent Runtime client
    bedrock_agent = boto3.client('bedrock-agent-runtime')
    
    try:
        # Parse request body with enhanced validation
        if 'body' in event:
            body = json.loads(event['body']) if isinstance(event['body'], str) else event['body']
        else:
            body = event
        
        query = body.get('query', '').strip()
        session_id = body.get('sessionId', 'default-session')
        
        # Validate input
        if not query:
            logger.warning("Empty query received")
            return {
                'statusCode': 400,
                'headers': {
                    'Content-Type': 'application/json',
                    'Access-Control-Allow-Origin': '*',
                    'Access-Control-Allow-Headers': 'Content-Type',
                    'Access-Control-Allow-Methods': 'POST, OPTIONS'
                },
                'body': json.dumps({
                    'error': 'Query parameter is required and cannot be empty'
                })
            }
        
        if len(query) > 1000:
            logger.warning(f"Query too long: {len(query)} characters")
            return {
                'statusCode': 400,
                'headers': {
                    'Content-Type': 'application/json',
                    'Access-Control-Allow-Origin': '*'
                },
                'body': json.dumps({
                    'error': 'Query too long. Please limit to 1000 characters.'
                })
            }
        
        logger.info(f"Processing query for session: {session_id}")
        
        # Invoke Bedrock Agent with enhanced configuration
        response = bedrock_agent.invoke_agent(
            agentId='${agent_id}',
            agentAliasId='TSTALIASID',
            sessionId=session_id,
            inputText=query,
            enableTrace=True
        )
        
        # Process response stream with better error handling
        response_text = ""
        trace_info = []
        
        for chunk in response['completion']:
            if 'chunk' in chunk:
                chunk_data = chunk['chunk']
                if 'bytes' in chunk_data:
                    response_text += chunk_data['bytes'].decode('utf-8')
            elif 'trace' in chunk:
                trace_info.append(chunk['trace'])
        
        logger.info(f"Successfully processed query, response length: {len(response_text)}")
        
        return {
            'statusCode': 200,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*',
                'Access-Control-Allow-Headers': 'Content-Type',
                'Access-Control-Allow-Methods': 'POST, OPTIONS'
            },
            'body': json.dumps({
                'response': response_text,
                'sessionId': session_id,
                'timestamp': context.aws_request_id
            })
        }
        
    except ClientError as e:
        error_code = e.response['Error']['Code']
        logger.error(f"AWS service error: {error_code} - {str(e)}")
        
        return {
            'statusCode': 503 if error_code in ['ThrottlingException', 'ServiceQuotaExceededException'] else 500,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({
                'error': f'Service temporarily unavailable. Please try again later.',
                'requestId': context.aws_request_id
            })
        }
        
    except json.JSONDecodeError as e:
        logger.error(f"JSON decode error: {str(e)}")
        return {
            'statusCode': 400,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({
                'error': 'Invalid JSON format in request body'
            })
        }
        
    except Exception as e:
        logger.error(f"Unexpected error: {str(e)}")
        return {
            'statusCode': 500,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({
                'error': 'Internal server error',
                'requestId': context.aws_request_id
            })
        }