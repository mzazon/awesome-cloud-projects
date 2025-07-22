import json
import boto3
import os
import time
import uuid
from botocore.exceptions import ClientError
from boto3.dynamodb.conditions import Key

dynamodb = boto3.resource('dynamodb')
connections_table = dynamodb.Table('${connections_table}')
rooms_table = dynamodb.Table('${rooms_table}')
messages_table = dynamodb.Table('${messages_table}')

def lambda_handler(event, context):
    """
    WebSocket message handler for $default route and custom routes
    Processes all real-time communication including chat, room management, and private messaging
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
    
    # Get sender connection info
    try:
        sender_response = connections_table.get_item(
            Key={'connectionId': connection_id}
        )
        
        if 'Item' not in sender_response:
            return send_error(connection_id, domain_name, stage, 'Connection not found')
        
        sender_info = sender_response['Item']
        
        # Update last activity
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
        return handle_ping(connection_id, domain_name, stage)
    else:
        return send_error(connection_id, domain_name, stage, f'Unknown message type: {message_type}')

def handle_chat_message(message_data, sender_info, domain_name, stage):
    """Handle chat messages sent to rooms"""
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
        'type': 'chat',
        'ttl': int(time.time()) + 2592000  # 30 days TTL
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
    """Handle room joining requests"""
    new_room_id = message_data.get('roomId')
    
    if not new_room_id:
        return send_error(connection_id, domain_name, stage, 'Room ID required')
    
    old_room_id = sender_info.get('roomId')
    
    # Update connection's room
    connections_table.update_item(
        Key={'connectionId': connection_id},
        UpdateExpression='SET roomId = :room_id, lastActivity = :timestamp',
        ExpressionAttributeValues={
            ':room_id': new_room_id,
            ':timestamp': int(time.time())
        }
    )
    
    # Notify old room of user leaving
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
    
    # Notify new room of user joining
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
    """Handle room leaving requests"""
    room_id = sender_info.get('roomId')
    
    if not room_id:
        return send_error(connection_id, domain_name, stage, 'Not in any room')
    
    # Update connection to default room
    connections_table.update_item(
        Key={'connectionId': connection_id},
        UpdateExpression='SET roomId = :room_id, lastActivity = :timestamp',
        ExpressionAttributeValues={
            ':room_id': 'general',
            ':timestamp': int(time.time())
        }
    )
    
    # Notify room of user leaving
    leave_message = {
        'type': 'user_left',
        'data': {
            'userId': sender_info['userId'],
            'username': sender_info.get('username', sender_info['userId']),
            'roomId': room_id,
            'timestamp': int(time.time())
        }
    }
    
    broadcast_to_room(room_id, leave_message, domain_name, stage)
    
    return {'statusCode': 200}

def handle_private_message(message_data, sender_info, domain_name, stage):
    """Handle private messages between users"""
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
    """Handle room list requests"""
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
    
    try:
        api_gateway.post_to_connection(
            ConnectionId=connection_id,
            Data=json.dumps(room_list_message)
        )
    except ClientError as e:
        if e.response['Error']['Code'] == 'GoneException':
            # Remove stale connection
            connections_table.delete_item(Key={'connectionId': connection_id})
    
    return {'statusCode': 200}

def handle_ping(connection_id, domain_name, stage):
    """Handle ping messages for connection health checking"""
    pong_message = {
        'type': 'pong',
        'data': {
            'timestamp': int(time.time())
        }
    }
    
    api_gateway = boto3.client('apigatewaymanagementapi',
        endpoint_url=f'https://{domain_name}/{stage}')
    
    try:
        api_gateway.post_to_connection(
            ConnectionId=connection_id,
            Data=json.dumps(pong_message)
        )
    except ClientError as e:
        if e.response['Error']['Code'] == 'GoneException':
            # Remove stale connection
            connections_table.delete_item(Key={'connectionId': connection_id})
    
    return {'statusCode': 200}

def broadcast_to_room(room_id, message, domain_name, stage):
    """Broadcast message to all connections in a room"""
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