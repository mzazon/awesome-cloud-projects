#!/usr/bin/env python3
"""
CDK Python Application for Real-Time WebSocket APIs with Route Management and Connection Handling

This application creates a comprehensive WebSocket API infrastructure including:
- API Gateway WebSocket API with custom routes
- Lambda functions for connection lifecycle and message handling
- DynamoDB tables for connection state, rooms, and message persistence
- IAM roles and policies with least privilege access
- CloudWatch logging and monitoring
"""

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    Duration,
    RemovalPolicy,
    aws_apigatewayv2 as apigatewayv2,
    aws_apigatewayv2_integrations as apigatewayv2_integrations,
    aws_lambda as lambda_,
    aws_dynamodb as dynamodb,
    aws_iam as iam,
    aws_logs as logs,
    CfnOutput,
)
from constructs import Construct
import os


class WebSocketApiStack(Stack):
    """
    Stack for deploying a comprehensive WebSocket API with connection management,
    message routing, and real-time communication capabilities.
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Create DynamoDB tables for state management
        self.create_dynamodb_tables()
        
        # Create IAM role for Lambda functions
        self.create_lambda_role()
        
        # Create Lambda functions for WebSocket handling
        self.create_lambda_functions()
        
        # Create WebSocket API Gateway
        self.create_websocket_api()
        
        # Create outputs
        self.create_outputs()

    def create_dynamodb_tables(self) -> None:
        """Create DynamoDB tables for connection state, rooms, and messages."""
        
        # Connections table for managing active WebSocket connections
        self.connections_table = dynamodb.Table(
            self,
            "ConnectionsTable",
            table_name=f"websocket-connections-{self.stack_name}",
            partition_key=dynamodb.Attribute(
                name="connectionId",
                type=dynamodb.AttributeType.STRING
            ),
            billing_mode=dynamodb.BillingMode.PAY_PER_REQUEST,
            removal_policy=RemovalPolicy.DESTROY,
            point_in_time_recovery=True,
            stream=dynamodb.StreamViewType.NEW_AND_OLD_IMAGES,
        )
        
        # Add Global Secondary Indexes for efficient queries
        self.connections_table.add_global_secondary_index(
            index_name="UserIndex",
            partition_key=dynamodb.Attribute(
                name="userId",
                type=dynamodb.AttributeType.STRING
            ),
            projection_type=dynamodb.ProjectionType.ALL,
        )
        
        self.connections_table.add_global_secondary_index(
            index_name="RoomIndex",
            partition_key=dynamodb.Attribute(
                name="roomId",
                type=dynamodb.AttributeType.STRING
            ),
            projection_type=dynamodb.ProjectionType.ALL,
        )
        
        # Rooms table for managing chat rooms and their metadata
        self.rooms_table = dynamodb.Table(
            self,
            "RoomsTable",
            table_name=f"websocket-rooms-{self.stack_name}",
            partition_key=dynamodb.Attribute(
                name="roomId",
                type=dynamodb.AttributeType.STRING
            ),
            billing_mode=dynamodb.BillingMode.PAY_PER_REQUEST,
            removal_policy=RemovalPolicy.DESTROY,
            point_in_time_recovery=True,
        )
        
        self.rooms_table.add_global_secondary_index(
            index_name="OwnerIndex",
            partition_key=dynamodb.Attribute(
                name="ownerId",
                type=dynamodb.AttributeType.STRING
            ),
            projection_type=dynamodb.ProjectionType.ALL,
        )
        
        # Messages table for storing chat message history
        self.messages_table = dynamodb.Table(
            self,
            "MessagesTable",
            table_name=f"websocket-messages-{self.stack_name}",
            partition_key=dynamodb.Attribute(
                name="messageId",
                type=dynamodb.AttributeType.STRING
            ),
            billing_mode=dynamodb.BillingMode.PAY_PER_REQUEST,
            removal_policy=RemovalPolicy.DESTROY,
            point_in_time_recovery=True,
            # TTL for automatic message cleanup (optional)
            time_to_live_attribute="ttl",
        )
        
        self.messages_table.add_global_secondary_index(
            index_name="RoomTimestampIndex",
            partition_key=dynamodb.Attribute(
                name="roomId",
                type=dynamodb.AttributeType.STRING
            ),
            sort_key=dynamodb.Attribute(
                name="timestamp",
                type=dynamodb.AttributeType.NUMBER
            ),
            projection_type=dynamodb.ProjectionType.ALL,
        )

    def create_lambda_role(self) -> None:
        """Create IAM role for Lambda functions with necessary permissions."""
        
        self.lambda_role = iam.Role(
            self,
            "WebSocketLambdaRole",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSLambdaBasicExecutionRole"
                )
            ],
        )
        
        # DynamoDB permissions for all tables
        dynamodb_policy = iam.PolicyStatement(
            effect=iam.Effect.ALLOW,
            actions=[
                "dynamodb:Query",
                "dynamodb:Scan",
                "dynamodb:GetItem",
                "dynamodb:PutItem",
                "dynamodb:UpdateItem",
                "dynamodb:DeleteItem",
                "dynamodb:BatchGetItem",
                "dynamodb:BatchWriteItem",
            ],
            resources=[
                self.connections_table.table_arn,
                f"{self.connections_table.table_arn}/index/*",
                self.rooms_table.table_arn,
                f"{self.rooms_table.table_arn}/index/*",
                self.messages_table.table_arn,
                f"{self.messages_table.table_arn}/index/*",
            ],
        )
        
        # API Gateway Management API permissions for sending messages
        apigateway_policy = iam.PolicyStatement(
            effect=iam.Effect.ALLOW,
            actions=["execute-api:ManageConnections"],
            resources=[
                f"arn:aws:execute-api:{self.region}:{self.account}:*/@connections/*"
            ],
        )
        
        self.lambda_role.add_to_policy(dynamodb_policy)
        self.lambda_role.add_to_policy(apigateway_policy)

    def create_lambda_functions(self) -> None:
        """Create Lambda functions for WebSocket connection and message handling."""
        
        # Common Lambda function configuration
        lambda_config = {
            "runtime": lambda_.Runtime.PYTHON_3_11,
            "timeout": Duration.seconds(30),
            "memory_size": 512,
            "role": self.lambda_role,
            "environment": {
                "CONNECTIONS_TABLE": self.connections_table.table_name,
                "ROOMS_TABLE": self.rooms_table.table_name,
                "MESSAGES_TABLE": self.messages_table.table_name,
            },
            "tracing": lambda_.Tracing.ACTIVE,
            "log_retention": logs.RetentionDays.ONE_WEEK,
        }
        
        # Connection handler for $connect route
        self.connect_handler = lambda_.Function(
            self,
            "ConnectHandler",
            function_name=f"websocket-connect-{self.stack_name}",
            description="Handles WebSocket connection establishment and authentication",
            code=lambda_.Code.from_inline(self._get_connect_handler_code()),
            handler="index.lambda_handler",
            **lambda_config,
        )
        
        # Disconnect handler for $disconnect route
        self.disconnect_handler = lambda_.Function(
            self,
            "DisconnectHandler",
            function_name=f"websocket-disconnect-{self.stack_name}",
            description="Handles WebSocket connection cleanup and state management",
            code=lambda_.Code.from_inline(self._get_disconnect_handler_code()),
            handler="index.lambda_handler",
            **lambda_config,
        )
        
        # Message handler for $default and custom routes
        self.message_handler = lambda_.Function(
            self,
            "MessageHandler",
            function_name=f"websocket-message-{self.stack_name}",
            description="Handles WebSocket message routing and broadcasting",
            code=lambda_.Code.from_inline(self._get_message_handler_code()),
            handler="index.lambda_handler",
            timeout=Duration.seconds(60),  # Increased timeout for message processing
            **lambda_config,
        )

    def create_websocket_api(self) -> None:
        """Create WebSocket API Gateway with routes and integrations."""
        
        # Create WebSocket API
        self.websocket_api = apigatewayv2.WebSocketApi(
            self,
            "WebSocketApi",
            api_name=f"websocket-api-{self.stack_name}",
            description="Real-time WebSocket API with route management and connection handling",
            route_selection_expression="$request.body.type",
        )
        
        # Create integrations for Lambda functions
        connect_integration = apigatewayv2_integrations.WebSocketLambdaIntegration(
            "ConnectIntegration",
            self.connect_handler,
        )
        
        disconnect_integration = apigatewayv2_integrations.WebSocketLambdaIntegration(
            "DisconnectIntegration",
            self.disconnect_handler,
        )
        
        message_integration = apigatewayv2_integrations.WebSocketLambdaIntegration(
            "MessageIntegration",
            self.message_handler,
        )
        
        # Add routes to WebSocket API
        self.websocket_api.add_route(
            "$connect",
            integration=connect_integration,
        )
        
        self.websocket_api.add_route(
            "$disconnect",
            integration=disconnect_integration,
        )
        
        self.websocket_api.add_route(
            "$default",
            integration=message_integration,
        )
        
        # Add custom routes for specific message types
        custom_routes = [
            "chat",
            "join_room",
            "leave_room",
            "private_message",
            "room_list",
        ]
        
        for route in custom_routes:
            self.websocket_api.add_route(
                route,
                integration=message_integration,
            )
        
        # Create WebSocket stage
        self.websocket_stage = apigatewayv2.WebSocketStage(
            self,
            "WebSocketStage",
            web_socket_api=self.websocket_api,
            stage_name="prod",
            auto_deploy=True,
            default_route_options=apigatewayv2.WebSocketRouteOptions(
                throttle=apigatewayv2.ThrottleSettings(
                    rate_limit=1000,
                    burst_limit=2000,
                ),
            ),
        )

    def create_outputs(self) -> None:
        """Create CloudFormation outputs for key resources."""
        
        # WebSocket API endpoint
        CfnOutput(
            self,
            "WebSocketApiEndpoint",
            value=f"wss://{self.websocket_api.api_id}.execute-api.{self.region}.amazonaws.com/{self.websocket_stage.stage_name}",
            description="WebSocket API endpoint for client connections",
        )
        
        # WebSocket API ID
        CfnOutput(
            self,
            "WebSocketApiId",
            value=self.websocket_api.api_id,
            description="WebSocket API ID for reference",
        )
        
        # DynamoDB table names
        CfnOutput(
            self,
            "ConnectionsTableName",
            value=self.connections_table.table_name,
            description="DynamoDB table for connection state management",
        )
        
        CfnOutput(
            self,
            "RoomsTableName",
            value=self.rooms_table.table_name,
            description="DynamoDB table for room management",
        )
        
        CfnOutput(
            self,
            "MessagesTableName",
            value=self.messages_table.table_name,
            description="DynamoDB table for message persistence",
        )
        
        # Lambda function names
        CfnOutput(
            self,
            "ConnectHandlerName",
            value=self.connect_handler.function_name,
            description="Lambda function for connection handling",
        )
        
        CfnOutput(
            self,
            "DisconnectHandlerName",
            value=self.disconnect_handler.function_name,
            description="Lambda function for disconnect handling",
        )
        
        CfnOutput(
            self,
            "MessageHandlerName",
            value=self.message_handler.function_name,
            description="Lambda function for message handling",
        )

    def _get_connect_handler_code(self) -> str:
        """Return the Lambda function code for connection handling."""
        return '''
import json
import boto3
import os
import time
from botocore.exceptions import ClientError

dynamodb = boto3.resource('dynamodb')
connections_table = dynamodb.Table(os.environ['CONNECTIONS_TABLE'])

def lambda_handler(event, context):
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
'''

    def _get_disconnect_handler_code(self) -> str:
        """Return the Lambda function code for disconnect handling."""
        return '''
import json
import boto3
import os
from botocore.exceptions import ClientError

dynamodb = boto3.resource('dynamodb')
connections_table = dynamodb.Table(os.environ['CONNECTIONS_TABLE'])

def lambda_handler(event, context):
    connection_id = event['requestContext']['connectionId']
    
    try:
        # Get connection information before deletion
        response = connections_table.get_item(
            Key={'connectionId': connection_id}
        )
        
        if 'Item' in response:
            connection_data = response['Item']
            user_id = connection_data.get('userId', 'unknown')
            room_id = connection_data.get('roomId', 'unknown')
            
            print(f"Disconnecting user {user_id} from room {room_id}")
        
        # Remove connection from table
        connections_table.delete_item(
            Key={'connectionId': connection_id}
        )
        
        print(f"Connection removed: {connection_id}")
        
        return {
            'statusCode': 200,
            'body': json.dumps({'message': 'Disconnected successfully'})
        }
        
    except ClientError as e:
        print(f"DynamoDB error: {e}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': 'Disconnect failed'})
        }
    except Exception as e:
        print(f"Unexpected error: {e}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': 'Internal server error'})
        }
'''

    def _get_message_handler_code(self) -> str:
        """Return the Lambda function code for message handling."""
        return '''
import json
import boto3
import os
import time
import uuid
from botocore.exceptions import ClientError
from boto3.dynamodb.conditions import Key

dynamodb = boto3.resource('dynamodb')
connections_table = dynamodb.Table(os.environ['CONNECTIONS_TABLE'])
rooms_table = dynamodb.Table(os.environ['ROOMS_TABLE'])
messages_table = dynamodb.Table(os.environ['MESSAGES_TABLE'])

def lambda_handler(event, context):
    connection_id = event['requestContext']['connectionId']
    domain_name = event['requestContext']['domainName']
    stage = event['requestContext']['stage']
    route_key = event['requestContext']['routeKey']
    
    # Parse message from client
    try:
        message_data = json.loads(event.get('body', '{}'))
    except json.JSONDecodeError:
        return send_error(connection_id, domain_name, stage, 'Invalid JSON format')
    
    # Get sender connection info
    try:
        sender_response = connections_table.get_item(
            Key={'connectionId': connection_id}
        )
        
        if 'Item' not in sender_response:
            return send_error(connection_id, domain_name, stage, 'Connection not found')
        
        sender_info = sender_response['Item']
        
    except ClientError as e:
        print(f"Error getting sender info: {e}")
        return {'statusCode': 500}
    
    # Route message based on type
    message_type = message_data.get('type', 'chat')
    
    if message_type == 'chat':
        return handle_chat_message(message_data, sender_info, domain_name, stage)
    elif message_type == 'join_room':
        return handle_join_room(message_data, sender_info, connection_id, domain_name, stage)
    elif message_type == 'leave_room':
        return handle_leave_room(message_data, sender_info, connection_id, domain_name, stage)
    elif message_type == 'private_message':
        return handle_private_message(message_data, sender_info, domain_name, stage)
    elif message_type == 'room_list':
        return handle_room_list(sender_info, connection_id, domain_name, stage)
    else:
        return send_error(connection_id, domain_name, stage, f'Unknown message type: {message_type}')

def handle_chat_message(message_data, sender_info, domain_name, stage):
    room_id = message_data.get('roomId', sender_info['roomId'])
    message_content = message_data.get('message', '')
    
    if not message_content.strip():
        return send_error(sender_info['connectionId'], domain_name, stage, 'Message cannot be empty')
    
    # Store message in database
    message_id = str(uuid.uuid4())
    timestamp = int(time.time())
    
    message_record = {
        'messageId': message_id,
        'roomId': room_id,
        'senderId': sender_info['userId'],
        'senderName': sender_info.get('username', sender_info['userId']),
        'message': message_content,
        'timestamp': timestamp,
        'type': 'chat'
    }
    
    messages_table.put_item(Item=message_record)
    
    # Broadcast to all connections in the room
    broadcast_message = {
        'type': 'chat',
        'data': {
            'messageId': message_id,
            'roomId': room_id,
            'senderId': sender_info['userId'],
            'senderName': sender_info.get('username', sender_info['userId']),
            'message': message_content,
            'timestamp': timestamp
        }
    }
    
    broadcast_to_room(room_id, broadcast_message, domain_name, stage)
    
    return {'statusCode': 200}

def handle_join_room(message_data, sender_info, connection_id, domain_name, stage):
    new_room_id = message_data.get('roomId')
    
    if not new_room_id:
        return send_error(connection_id, domain_name, stage, 'Room ID required')
    
    # Update connection's room
    connections_table.update_item(
        Key={'connectionId': connection_id},
        UpdateExpression='SET roomId = :room_id, lastActivity = :timestamp',
        ExpressionAttributeValues={
            ':room_id': new_room_id,
            ':timestamp': int(time.time())
        }
    )
    
    # Notify room of new member
    join_message = {
        'type': 'user_joined',
        'data': {
            'userId': sender_info['userId'],
            'username': sender_info.get('username', sender_info['userId']),
            'roomId': new_room_id,
            'timestamp': int(time.time())
        }
    }
    
    broadcast_to_room(new_room_id, join_message, domain_name, stage)
    
    return {'statusCode': 200}

def handle_leave_room(message_data, sender_info, connection_id, domain_name, stage):
    old_room_id = sender_info['roomId']
    
    # Update connection to general room
    connections_table.update_item(
        Key={'connectionId': connection_id},
        UpdateExpression='SET roomId = :room_id, lastActivity = :timestamp',
        ExpressionAttributeValues={
            ':room_id': 'general',
            ':timestamp': int(time.time())
        }
    )
    
    # Notify room of member leaving
    leave_message = {
        'type': 'user_left',
        'data': {
            'userId': sender_info['userId'],
            'username': sender_info.get('username', sender_info['userId']),
            'roomId': old_room_id,
            'timestamp': int(time.time())
        }
    }
    
    broadcast_to_room(old_room_id, leave_message, domain_name, stage)
    
    return {'statusCode': 200}

def handle_private_message(message_data, sender_info, domain_name, stage):
    target_user_id = message_data.get('targetUserId')
    message_content = message_data.get('message')
    
    if not target_user_id or not message_content:
        return send_error(sender_info['connectionId'], domain_name, stage, 
                        'Target user ID and message required for private messages')
    
    # Find target user's connections
    response = connections_table.query(
        IndexName='UserIndex',
        KeyConditionExpression=Key('userId').eq(target_user_id)
    )
    
    if not response['Items']:
        return send_error(sender_info['connectionId'], domain_name, stage, 
                        'Target user not found or offline')
    
    # Send private message to all target user's connections
    private_message = {
        'type': 'private_message',
        'data': {
            'senderId': sender_info['userId'],
            'senderName': sender_info.get('username', sender_info['userId']),
            'message': message_content,
            'timestamp': int(time.time())
        }
    }
    
    api_gateway = boto3.client('apigatewaymanagementapi',
        endpoint_url=f'https://{domain_name}/{stage}')
    
    for target_connection in response['Items']:
        try:
            api_gateway.post_to_connection(
                ConnectionId=target_connection['connectionId'],
                Data=json.dumps(private_message)
            )
        except ClientError as e:
            if e.response['Error']['Code'] == 'GoneException':
                # Remove stale connection
                connections_table.delete_item(
                    Key={'connectionId': target_connection['connectionId']}
                )
    
    return {'statusCode': 200}

def handle_room_list(sender_info, connection_id, domain_name, stage):
    # Get active rooms (rooms with at least one connection)
    response = connections_table.scan(
        ProjectionExpression='roomId'
    )
    
    active_rooms = {}
    for item in response['Items']:
        room_id = item['roomId']
        active_rooms[room_id] = active_rooms.get(room_id, 0) + 1
    
    room_list_message = {
        'type': 'room_list',
        'data': {
            'rooms': [
                {'roomId': room_id, 'activeUsers': count}
                for room_id, count in active_rooms.items()
            ],
            'timestamp': int(time.time())
        }
    }
    
    api_gateway = boto3.client('apigatewaymanagementapi',
        endpoint_url=f'https://{domain_name}/{stage}')
    
    api_gateway.post_to_connection(
        ConnectionId=connection_id,
        Data=json.dumps(room_list_message)
    )
    
    return {'statusCode': 200}

def broadcast_to_room(room_id, message, domain_name, stage):
    # Get all connections in the room
    response = connections_table.query(
        IndexName='RoomIndex',
        KeyConditionExpression=Key('roomId').eq(room_id)
    )
    
    api_gateway = boto3.client('apigatewaymanagementapi',
        endpoint_url=f'https://{domain_name}/{stage}')
    
    message_data = json.dumps(message)
    stale_connections = []
    
    for connection in response['Items']:
        try:
            api_gateway.post_to_connection(
                ConnectionId=connection['connectionId'],
                Data=message_data
            )
        except ClientError as e:
            if e.response['Error']['Code'] == 'GoneException':
                stale_connections.append(connection['connectionId'])
    
    # Clean up stale connections
    for connection_id in stale_connections:
        connections_table.delete_item(Key={'connectionId': connection_id})

def send_error(connection_id, domain_name, stage, error_message):
    api_gateway = boto3.client('apigatewaymanagementapi',
        endpoint_url=f'https://{domain_name}/{stage}')
    
    error_response = {
        'type': 'error',
        'data': {
            'message': error_message,
            'timestamp': int(time.time())
        }
    }
    
    try:
        api_gateway.post_to_connection(
            ConnectionId=connection_id,
            Data=json.dumps(error_response)
        )
    except ClientError:
        pass  # Connection might be gone
    
    return {'statusCode': 400}
'''


def main():
    """Main function to deploy the WebSocket API stack."""
    app = cdk.App()
    
    # Get stack name from context or use default
    stack_name = app.node.try_get_context("stackName") or "websocket-api-stack"
    
    # Create the WebSocket API stack
    WebSocketApiStack(
        app,
        stack_name,
        description="Real-time WebSocket API with route management and connection handling",
        env=cdk.Environment(
            account=os.getenv('CDK_DEFAULT_ACCOUNT'),
            region=os.getenv('CDK_DEFAULT_REGION')
        ),
    )
    
    app.synth()


if __name__ == "__main__":
    main()