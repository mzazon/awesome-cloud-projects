import json
import boto3
import os
import time
from botocore.exceptions import ClientError

dynamodb = boto3.resource('dynamodb')
connections_table = dynamodb.Table('${connections_table}')

def lambda_handler(event, context):
    """
    WebSocket $connect route handler
    Manages new WebSocket connections, validates authentication, and stores connection state
    """
    connection_id = event['requestContext']['connectionId']
    domain_name = event['requestContext']['domainName']
    stage = event['requestContext']['stage']
    
    # Extract query parameters for authentication and room joining
    query_params = event.get('queryStringParameters') or {}
    user_id = query_params.get('userId', 'anonymous')
    room_id = query_params.get('roomId', 'general')
    auth_token = query_params.get('token')
    
    try:
        # Basic token validation (in production, integrate with Cognito)
        if auth_token:
            # Simulate token validation
            if not auth_token.startswith('valid_'):
                return {
                    'statusCode': 401,
                    'body': json.dumps({'error': 'Invalid authentication token'})
                }
        
        # Store connection information
        connection_data = {
            'connectionId': connection_id,
            'userId': user_id,
            'roomId': room_id,
            'connectedAt': int(time.time()),
            'domainName': domain_name,
            'stage': stage,
            'lastActivity': int(time.time()),
            'status': 'connected'
        }
        
        # Add optional user metadata
        if 'username' in query_params:
            connection_data['username'] = query_params['username']
        
        # Add TTL for automatic cleanup (24 hours)
        connection_data['ttl'] = int(time.time()) + 86400
        
        connections_table.put_item(Item=connection_data)
        
        # Send welcome message
        api_gateway = boto3.client('apigatewaymanagementapi',
            endpoint_url=f'https://{domain_name}/{stage}')
        
        welcome_message = {
            'type': 'welcome',
            'data': {
                'connectionId': connection_id,
                'userId': user_id,
                'roomId': room_id,
                'message': f'Welcome to room {room_id}!',
                'timestamp': int(time.time())
            }
        }
        
        api_gateway.post_to_connection(
            ConnectionId=connection_id,
            Data=json.dumps(welcome_message)
        )
        
        print(f"Connection established: {connection_id} for user {user_id} in room {room_id}")
        
        return {
            'statusCode': 200,
            'body': json.dumps({'message': 'Connected successfully'})
        }
        
    except ClientError as e:
        print(f"DynamoDB error: {e}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': 'Connection failed'})
        }
    except Exception as e:
        print(f"Unexpected error: {e}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': 'Internal server error'})
        }