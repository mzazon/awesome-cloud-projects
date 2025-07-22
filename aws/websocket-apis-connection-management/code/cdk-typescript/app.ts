#!/usr/bin/env node

import 'source-map-support/register';
import { App, Stack, StackProps, Duration, RemovalPolicy } from 'aws-cdk-lib';
import { 
  WebSocketApi, 
  WebSocketStage, 
  WebSocketRoute,
  WebSocketRouteKey,
  WebSocketIntegration,
  WebSocketIntegrationType
} from 'aws-cdk-lib/aws-apigatewayv2';
import { WebSocketLambdaIntegration } from 'aws-cdk-lib/aws-apigatewayv2-integrations';
import { 
  Function as LambdaFunction, 
  Runtime, 
  Code, 
  Architecture 
} from 'aws-cdk-lib/aws-lambda';
import { 
  Table, 
  AttributeType, 
  BillingMode,
  ProjectionType,
  StreamViewType 
} from 'aws-cdk-lib/aws-dynamodb';
import { 
  Role, 
  ServicePrincipal, 
  PolicyStatement, 
  Effect,
  ManagedPolicy 
} from 'aws-cdk-lib/aws-iam';
import { 
  LogGroup, 
  LogStream, 
  RetentionDays 
} from 'aws-cdk-lib/aws-logs';
import { Construct } from 'constructs';

/**
 * Properties for the WebSocket API Stack
 */
interface WebSocketApiStackProps extends StackProps {
  /**
   * Environment prefix for resource naming
   * @default 'dev'
   */
  readonly environmentPrefix?: string;
  
  /**
   * DynamoDB table billing mode
   * @default BillingMode.PAY_PER_REQUEST
   */
  readonly billingMode?: BillingMode;
  
  /**
   * Lambda function memory size
   * @default 256
   */
  readonly lambdaMemorySize?: number;
  
  /**
   * Lambda function timeout
   * @default Duration.seconds(30)
   */
  readonly lambdaTimeout?: Duration;
  
  /**
   * Enable detailed CloudWatch metrics
   * @default true
   */
  readonly enableDetailedMetrics?: boolean;
  
  /**
   * Log retention period
   * @default RetentionDays.ONE_WEEK
   */
  readonly logRetention?: RetentionDays;
}

/**
 * CDK Stack for Real-Time WebSocket APIs with Route Management and Connection Handling
 * 
 * This stack creates a comprehensive WebSocket API solution including:
 * - API Gateway WebSocket API with custom routes
 * - Lambda functions for connection lifecycle and message handling
 * - DynamoDB tables for connection state and message persistence
 * - IAM roles and policies following least privilege principle
 * - CloudWatch logging and monitoring
 */
export class WebSocketApiStack extends Stack {
  public readonly webSocketApi: WebSocketApi;
  public readonly webSocketStage: WebSocketStage;
  public readonly connectionsTable: Table;
  public readonly roomsTable: Table;
  public readonly messagesTable: Table;
  public readonly webSocketEndpoint: string;

  constructor(scope: Construct, id: string, props: WebSocketApiStackProps = {}) {
    super(scope, id, props);

    // Extract properties with defaults
    const envPrefix = props.environmentPrefix || 'dev';
    const billingMode = props.billingMode || BillingMode.PAY_PER_REQUEST;
    const lambdaMemorySize = props.lambdaMemorySize || 256;
    const lambdaTimeout = props.lambdaTimeout || Duration.seconds(30);
    const enableDetailedMetrics = props.enableDetailedMetrics !== false;
    const logRetention = props.logRetention || RetentionDays.ONE_WEEK;

    // Create DynamoDB tables for connection state management
    this.connectionsTable = this.createConnectionsTable(envPrefix, billingMode);
    this.roomsTable = this.createRoomsTable(envPrefix, billingMode);
    this.messagesTable = this.createMessagesTable(envPrefix, billingMode);

    // Create IAM role for Lambda functions
    const lambdaRole = this.createLambdaRole(envPrefix);

    // Create Lambda functions for WebSocket routes
    const connectHandler = this.createConnectHandler(
      envPrefix, 
      lambdaRole, 
      lambdaMemorySize, 
      lambdaTimeout, 
      logRetention
    );
    
    const disconnectHandler = this.createDisconnectHandler(
      envPrefix, 
      lambdaRole, 
      lambdaMemorySize, 
      lambdaTimeout, 
      logRetention
    );
    
    const messageHandler = this.createMessageHandler(
      envPrefix, 
      lambdaRole, 
      lambdaMemorySize, 
      lambdaTimeout, 
      logRetention
    );

    // Create WebSocket API
    this.webSocketApi = new WebSocketApi(this, 'WebSocketApi', {
      apiName: `${envPrefix}-websocket-api`,
      description: 'Real-Time WebSocket API with Route Management and Connection Handling',
      routeSelectionExpression: '$request.body.type',
      connectRouteOptions: {
        integration: new WebSocketLambdaIntegration('ConnectIntegration', connectHandler),
      },
      disconnectRouteOptions: {
        integration: new WebSocketLambdaIntegration('DisconnectIntegration', disconnectHandler),
      },
      defaultRouteOptions: {
        integration: new WebSocketLambdaIntegration('DefaultIntegration', messageHandler),
      },
    });

    // Create custom routes for specific message types
    this.createCustomRoutes(messageHandler);

    // Create WebSocket stage with monitoring
    this.webSocketStage = new WebSocketStage(this, 'WebSocketStage', {
      webSocketApi: this.webSocketApi,
      stageName: 'staging',
      autoDeploy: true,
      description: 'Staging environment for WebSocket API',
      defaultRouteSettings: {
        detailedMetricsEnabled: enableDetailedMetrics,
        loggingLevel: 'INFO',
        dataTraceEnabled: true,
        throttlingBurstLimit: 500,
        throttlingRateLimit: 1000,
      },
    });

    // Grant DynamoDB permissions to Lambda functions
    this.grantDynamoDBPermissions(connectHandler, disconnectHandler, messageHandler);

    // Grant API Gateway Management permissions to Lambda functions
    this.grantApiGatewayManagementPermissions(connectHandler, messageHandler);

    // Set the WebSocket endpoint
    this.webSocketEndpoint = this.webSocketStage.url;

    // Output important values
    this.createOutputs();
  }

  /**
   * Create DynamoDB table for storing WebSocket connection information
   */
  private createConnectionsTable(envPrefix: string, billingMode: BillingMode): Table {
    const table = new Table(this, 'ConnectionsTable', {
      tableName: `${envPrefix}-websocket-connections`,
      partitionKey: {
        name: 'connectionId',
        type: AttributeType.STRING,
      },
      billingMode,
      removalPolicy: RemovalPolicy.DESTROY,
      pointInTimeRecovery: true,
      stream: StreamViewType.NEW_AND_OLD_IMAGES,
    });

    // Add Global Secondary Index for user-based queries
    table.addGlobalSecondaryIndex({
      indexName: 'UserIndex',
      partitionKey: {
        name: 'userId',
        type: AttributeType.STRING,
      },
      projectionType: ProjectionType.ALL,
    });

    // Add Global Secondary Index for room-based queries
    table.addGlobalSecondaryIndex({
      indexName: 'RoomIndex',
      partitionKey: {
        name: 'roomId',
        type: AttributeType.STRING,
      },
      projectionType: ProjectionType.ALL,
    });

    return table;
  }

  /**
   * Create DynamoDB table for storing room information
   */
  private createRoomsTable(envPrefix: string, billingMode: BillingMode): Table {
    const table = new Table(this, 'RoomsTable', {
      tableName: `${envPrefix}-websocket-rooms`,
      partitionKey: {
        name: 'roomId',
        type: AttributeType.STRING,
      },
      billingMode,
      removalPolicy: RemovalPolicy.DESTROY,
      pointInTimeRecovery: true,
    });

    // Add Global Secondary Index for owner-based queries
    table.addGlobalSecondaryIndex({
      indexName: 'OwnerIndex',
      partitionKey: {
        name: 'ownerId',
        type: AttributeType.STRING,
      },
      projectionType: ProjectionType.ALL,
    });

    return table;
  }

  /**
   * Create DynamoDB table for storing message history
   */
  private createMessagesTable(envPrefix: string, billingMode: BillingMode): Table {
    const table = new Table(this, 'MessagesTable', {
      tableName: `${envPrefix}-websocket-messages`,
      partitionKey: {
        name: 'messageId',
        type: AttributeType.STRING,
      },
      billingMode,
      removalPolicy: RemovalPolicy.DESTROY,
      pointInTimeRecovery: true,
    });

    // Add Global Secondary Index for room-timestamp based queries
    table.addGlobalSecondaryIndex({
      indexName: 'RoomTimestampIndex',
      partitionKey: {
        name: 'roomId',
        type: AttributeType.STRING,
      },
      sortKey: {
        name: 'timestamp',
        type: AttributeType.NUMBER,
      },
      projectionType: ProjectionType.ALL,
    });

    return table;
  }

  /**
   * Create IAM role for Lambda functions with comprehensive permissions
   */
  private createLambdaRole(envPrefix: string): Role {
    const role = new Role(this, 'WebSocketLambdaRole', {
      roleName: `${envPrefix}-websocket-lambda-role`,
      assumedBy: new ServicePrincipal('lambda.amazonaws.com'),
      description: 'IAM role for WebSocket Lambda functions',
    });

    // Attach AWS managed policy for basic Lambda execution
    role.addManagedPolicy(
      ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole')
    );

    // Add custom policy for DynamoDB access
    role.addToPolicy(new PolicyStatement({
      effect: Effect.ALLOW,
      actions: [
        'dynamodb:Query',
        'dynamodb:Scan',
        'dynamodb:GetItem',
        'dynamodb:PutItem',
        'dynamodb:UpdateItem',
        'dynamodb:DeleteItem',
        'dynamodb:BatchGetItem',
        'dynamodb:BatchWriteItem',
      ],
      resources: [
        this.connectionsTable.tableArn,
        `${this.connectionsTable.tableArn}/index/*`,
        this.roomsTable.tableArn,
        `${this.roomsTable.tableArn}/index/*`,
        this.messagesTable.tableArn,
        `${this.messagesTable.tableArn}/index/*`,
      ],
    }));

    return role;
  }

  /**
   * Create Lambda function for handling WebSocket $connect route
   */
  private createConnectHandler(
    envPrefix: string, 
    role: Role, 
    memorySize: number, 
    timeout: Duration,
    logRetention: RetentionDays
  ): LambdaFunction {
    // Create CloudWatch Log Group
    const logGroup = new LogGroup(this, 'ConnectHandlerLogGroup', {
      logGroupName: `/aws/lambda/${envPrefix}-websocket-connect`,
      retention: logRetention,
      removalPolicy: RemovalPolicy.DESTROY,
    });

    return new LambdaFunction(this, 'ConnectHandler', {
      functionName: `${envPrefix}-websocket-connect`,
      runtime: Runtime.PYTHON_3_9,
      architecture: Architecture.ARM_64,
      handler: 'index.lambda_handler',
      code: Code.fromInline(`
import json
import boto3
import os
import time
from botocore.exceptions import ClientError

# Initialize DynamoDB resource
dynamodb = boto3.resource('dynamodb')
connections_table = dynamodb.Table(os.environ['CONNECTIONS_TABLE'])

def lambda_handler(event, context):
    """
    Handle WebSocket connection establishment ($connect route)
    
    This function:
    1. Validates authentication tokens
    2. Stores connection metadata in DynamoDB
    3. Sends welcome message to client
    4. Handles connection errors gracefully
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
            # Simulate token validation - in production, verify JWT tokens
            if not auth_token.startswith('valid_'):
                return {
                    'statusCode': 401,
                    'body': json.dumps({'error': 'Invalid authentication token'})
                }
        
        # Store connection information with comprehensive metadata
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
        
        # Store connection in DynamoDB
        connections_table.put_item(Item=connection_data)
        
        # Send welcome message to establish bidirectional communication
        api_gateway = boto3.client('apigatewaymanagementapi',
            endpoint_url=f'https://{domain_name}/{stage}')
        
        welcome_message = {
            'type': 'welcome',
            'data': {
                'connectionId': connection_id,
                'userId': user_id,
                'roomId': room_id,
                'message': f'Welcome to room {room_id}! You are now connected.',
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
`),
      role,
      timeout,
      memorySize,
      description: 'WebSocket connection handler for $connect route',
      environment: {
        CONNECTIONS_TABLE: this.connectionsTable.tableName,
      },
      logGroup,
    });
  }

  /**
   * Create Lambda function for handling WebSocket $disconnect route
   */
  private createDisconnectHandler(
    envPrefix: string, 
    role: Role, 
    memorySize: number, 
    timeout: Duration,
    logRetention: RetentionDays
  ): LambdaFunction {
    // Create CloudWatch Log Group
    const logGroup = new LogGroup(this, 'DisconnectHandlerLogGroup', {
      logGroupName: `/aws/lambda/${envPrefix}-websocket-disconnect`,
      retention: logRetention,
      removalPolicy: RemovalPolicy.DESTROY,
    });

    return new LambdaFunction(this, 'DisconnectHandler', {
      functionName: `${envPrefix}-websocket-disconnect`,
      runtime: Runtime.PYTHON_3_9,
      architecture: Architecture.ARM_64,
      handler: 'index.lambda_handler',
      code: Code.fromInline(`
import json
import boto3
import os
from botocore.exceptions import ClientError

# Initialize DynamoDB resource
dynamodb = boto3.resource('dynamodb')
connections_table = dynamodb.Table(os.environ['CONNECTIONS_TABLE'])

def lambda_handler(event, context):
    """
    Handle WebSocket connection termination ($disconnect route)
    
    This function:
    1. Retrieves connection information before cleanup
    2. Removes connection state from DynamoDB
    3. Logs disconnection for monitoring
    4. Handles cleanup errors gracefully
    """
    connection_id = event['requestContext']['connectionId']
    
    try:
        # Get connection information before deletion for logging
        response = connections_table.get_item(
            Key={'connectionId': connection_id}
        )
        
        if 'Item' in response:
            connection_data = response['Item']
            user_id = connection_data.get('userId', 'unknown')
            room_id = connection_data.get('roomId', 'unknown')
            
            print(f"Disconnecting user {user_id} from room {room_id}")
        
        # Remove connection from table to prevent stale connections
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
`),
      role,
      timeout,
      memorySize,
      description: 'WebSocket disconnection handler for $disconnect route',
      environment: {
        CONNECTIONS_TABLE: this.connectionsTable.tableName,
      },
      logGroup,
    });
  }

  /**
   * Create Lambda function for handling WebSocket messages ($default and custom routes)
   */
  private createMessageHandler(
    envPrefix: string, 
    role: Role, 
    memorySize: number, 
    timeout: Duration,
    logRetention: RetentionDays
  ): LambdaFunction {
    // Create CloudWatch Log Group
    const logGroup = new LogGroup(this, 'MessageHandlerLogGroup', {
      logGroupName: `/aws/lambda/${envPrefix}-websocket-message`,
      retention: logRetention,
      removalPolicy: RemovalPolicy.DESTROY,
    });

    return new LambdaFunction(this, 'MessageHandler', {
      functionName: `${envPrefix}-websocket-message`,
      runtime: Runtime.PYTHON_3_9,
      architecture: Architecture.ARM_64,
      handler: 'index.lambda_handler',
      code: Code.fromInline(`
import json
import boto3
import os
import time
import uuid
from botocore.exceptions import ClientError
from boto3.dynamodb.conditions import Key

# Initialize DynamoDB resource and clients
dynamodb = boto3.resource('dynamodb')
connections_table = dynamodb.Table(os.environ['CONNECTIONS_TABLE'])
rooms_table = dynamodb.Table(os.environ['ROOMS_TABLE'])
messages_table = dynamodb.Table(os.environ['MESSAGES_TABLE'])

def lambda_handler(event, context):
    """
    Handle WebSocket message routing and processing
    
    This function:
    1. Parses incoming messages and routes based on type
    2. Handles chat messages, room management, and private messaging
    3. Stores messages in DynamoDB for persistence
    4. Broadcasts messages to appropriate recipients
    5. Manages connection state and user presence
    """
    connection_id = event['requestContext']['connectionId']
    domain_name = event['requestContext']['domainName']
    stage = event['requestContext']['stage']
    route_key = event['requestContext']['routeKey']
    
    # Parse message from client
    try:
        message_data = json.loads(event.get('body', '{}'))
    except json.JSONDecodeError:
        return send_error(connection_id, domain_name, stage, 'Invalid JSON format')
    
    # Get sender connection information
    try:
        sender_response = connections_table.get_item(
            Key={'connectionId': connection_id}
        )
        
        if 'Item' not in sender_response:
            return send_error(connection_id, domain_name, stage, 'Connection not found')
        
        sender_info = sender_response['Item']
        
        # Update last activity timestamp
        connections_table.update_item(
            Key={'connectionId': connection_id},
            UpdateExpression='SET lastActivity = :timestamp',
            ExpressionAttributeValues={':timestamp': int(time.time())}
        )
        
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
    elif message_type == 'ping':
        return handle_ping(sender_info, connection_id, domain_name, stage)
    else:
        return send_error(connection_id, domain_name, stage, f'Unknown message type: {message_type}')

def handle_chat_message(message_data, sender_info, domain_name, stage):
    """Handle chat messages with room broadcasting"""
    room_id = message_data.get('roomId', sender_info['roomId'])
    message_content = message_data.get('message', '')
    
    if not message_content.strip():
        return send_error(sender_info['connectionId'], domain_name, stage, 'Message cannot be empty')
    
    # Store message in database for persistence
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
    
    try:
        messages_table.put_item(Item=message_record)
    except ClientError as e:
        print(f"Error storing message: {e}")
        return send_error(sender_info['connectionId'], domain_name, stage, 'Failed to store message')
    
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
    """Handle room joining with user notifications"""
    new_room_id = message_data.get('roomId')
    
    if not new_room_id:
        return send_error(connection_id, domain_name, stage, 'Room ID required')
    
    old_room_id = sender_info.get('roomId')
    
    try:
        # Update connection's room
        connections_table.update_item(
            Key={'connectionId': connection_id},
            UpdateExpression='SET roomId = :room_id, lastActivity = :timestamp',
            ExpressionAttributeValues={
                ':room_id': new_room_id,
                ':timestamp': int(time.time())
            }
        )
        
        # Notify old room of departure if applicable
        if old_room_id and old_room_id != new_room_id:
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
        
        # Notify new room of new member
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
        
    except ClientError as e:
        print(f"Error joining room: {e}")
        return send_error(connection_id, domain_name, stage, 'Failed to join room')

def handle_leave_room(message_data, sender_info, connection_id, domain_name, stage):
    """Handle room leaving with fallback to general room"""
    current_room_id = sender_info.get('roomId')
    
    if not current_room_id:
        return send_error(connection_id, domain_name, stage, 'Not currently in a room')
    
    try:
        # Move to general room as default
        connections_table.update_item(
            Key={'connectionId': connection_id},
            UpdateExpression='SET roomId = :room_id, lastActivity = :timestamp',
            ExpressionAttributeValues={
                ':room_id': 'general',
                ':timestamp': int(time.time())
            }
        )
        
        # Notify room of departure
        leave_message = {
            'type': 'user_left',
            'data': {
                'userId': sender_info['userId'],
                'username': sender_info.get('username', sender_info['userId']),
                'roomId': current_room_id,
                'timestamp': int(time.time())
            }
        }
        
        broadcast_to_room(current_room_id, leave_message, domain_name, stage)
        
        return {'statusCode': 200}
        
    except ClientError as e:
        print(f"Error leaving room: {e}")
        return send_error(connection_id, domain_name, stage, 'Failed to leave room')

def handle_private_message(message_data, sender_info, domain_name, stage):
    """Handle private messaging between users"""
    target_user_id = message_data.get('targetUserId')
    message_content = message_data.get('message')
    
    if not target_user_id or not message_content:
        return send_error(sender_info['connectionId'], domain_name, stage, 
                        'Target user ID and message required for private messages')
    
    try:
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
        
    except ClientError as e:
        print(f"Error handling private message: {e}")
        return send_error(sender_info['connectionId'], domain_name, stage, 'Failed to send private message')

def handle_room_list(sender_info, connection_id, domain_name, stage):
    """Handle room listing with active user counts"""
    try:
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
        
    except ClientError as e:
        print(f"Error getting room list: {e}")
        return send_error(connection_id, domain_name, stage, 'Failed to get room list')

def handle_ping(sender_info, connection_id, domain_name, stage):
    """Handle ping messages for connection keepalive"""
    try:
        pong_message = {
            'type': 'pong',
            'data': {
                'timestamp': int(time.time())
            }
        }
        
        api_gateway = boto3.client('apigatewaymanagementapi',
            endpoint_url=f'https://{domain_name}/{stage}')
        
        api_gateway.post_to_connection(
            ConnectionId=connection_id,
            Data=json.dumps(pong_message)
        )
        
        return {'statusCode': 200}
        
    except ClientError as e:
        print(f"Error handling ping: {e}")
        return {'statusCode': 500}

def broadcast_to_room(room_id, message, domain_name, stage):
    """Broadcast message to all connections in a room"""
    try:
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
            
    except ClientError as e:
        print(f"Error broadcasting to room: {e}")

def send_error(connection_id, domain_name, stage, error_message):
    """Send error message to a specific connection"""
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
`),
      role,
      timeout: Duration.seconds(60),
      memorySize: 512,
      description: 'WebSocket message handler for routing and processing',
      environment: {
        CONNECTIONS_TABLE: this.connectionsTable.tableName,
        ROOMS_TABLE: this.roomsTable.tableName,
        MESSAGES_TABLE: this.messagesTable.tableName,
      },
      logGroup,
    });
  }

  /**
   * Create custom routes for specific message types
   */
  private createCustomRoutes(messageHandler: LambdaFunction): void {
    const integration = new WebSocketLambdaIntegration('MessageIntegration', messageHandler);

    // Create custom routes for specific message types
    new WebSocketRoute(this, 'ChatRoute', {
      webSocketApi: this.webSocketApi,
      routeKey: 'chat',
      integration,
    });

    new WebSocketRoute(this, 'JoinRoomRoute', {
      webSocketApi: this.webSocketApi,
      routeKey: 'join_room',
      integration,
    });

    new WebSocketRoute(this, 'LeaveRoomRoute', {
      webSocketApi: this.webSocketApi,
      routeKey: 'leave_room',
      integration,
    });

    new WebSocketRoute(this, 'PrivateMessageRoute', {
      webSocketApi: this.webSocketApi,
      routeKey: 'private_message',
      integration,
    });

    new WebSocketRoute(this, 'RoomListRoute', {
      webSocketApi: this.webSocketApi,
      routeKey: 'room_list',
      integration,
    });

    new WebSocketRoute(this, 'PingRoute', {
      webSocketApi: this.webSocketApi,
      routeKey: 'ping',
      integration,
    });
  }

  /**
   * Grant DynamoDB permissions to Lambda functions
   */
  private grantDynamoDBPermissions(...lambdaFunctions: LambdaFunction[]): void {
    lambdaFunctions.forEach(func => {
      this.connectionsTable.grantReadWriteData(func);
      this.roomsTable.grantReadWriteData(func);
      this.messagesTable.grantReadWriteData(func);
    });
  }

  /**
   * Grant API Gateway Management API permissions to Lambda functions
   */
  private grantApiGatewayManagementPermissions(...lambdaFunctions: LambdaFunction[]): void {
    lambdaFunctions.forEach(func => {
      func.addToRolePolicy(new PolicyStatement({
        effect: Effect.ALLOW,
        actions: ['execute-api:ManageConnections'],
        resources: [
          `arn:aws:execute-api:${this.region}:${this.account}:${this.webSocketApi.apiId}/*/@connections/*`,
        ],
      }));
    });
  }

  /**
   * Create CloudFormation outputs for important values
   */
  private createOutputs(): void {
    // WebSocket endpoint URL
    const { CfnOutput } = require('aws-cdk-lib');
    
    new CfnOutput(this, 'WebSocketEndpoint', {
      value: this.webSocketEndpoint,
      description: 'WebSocket API endpoint URL',
      exportName: 'WebSocketApiEndpoint',
    });

    new CfnOutput(this, 'WebSocketApiId', {
      value: this.webSocketApi.apiId,
      description: 'WebSocket API ID',
      exportName: 'WebSocketApiId',
    });

    new CfnOutput(this, 'ConnectionsTableName', {
      value: this.connectionsTable.tableName,
      description: 'DynamoDB connections table name',
      exportName: 'ConnectionsTableName',
    });

    new CfnOutput(this, 'RoomsTableName', {
      value: this.roomsTable.tableName,
      description: 'DynamoDB rooms table name',
      exportName: 'RoomsTableName',
    });

    new CfnOutput(this, 'MessagesTableName', {
      value: this.messagesTable.tableName,
      description: 'DynamoDB messages table name',
      exportName: 'MessagesTableName',
    });
  }
}

/**
 * CDK App entry point
 */
const app = new App();

// Create the WebSocket API stack with customizable properties
new WebSocketApiStack(app, 'WebSocketApiStack', {
  description: 'Real-Time WebSocket APIs with Route Management and Connection Handling',
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
  
  // Customizable stack properties
  environmentPrefix: app.node.tryGetContext('environment') || 'dev',
  billingMode: BillingMode.PAY_PER_REQUEST, // Change to PROVISIONED for predictable costs
  lambdaMemorySize: 512,
  lambdaTimeout: Duration.seconds(60),
  enableDetailedMetrics: true,
  logRetention: RetentionDays.ONE_WEEK,
  
  // Standard stack properties
  stackName: `websocket-api-${app.node.tryGetContext('environment') || 'dev'}`,
  tags: {
    Project: 'WebSocket API',
    Environment: app.node.tryGetContext('environment') || 'dev',
    ManagedBy: 'CDK',
  },
});

// Synthesize the CloudFormation template
app.synth();