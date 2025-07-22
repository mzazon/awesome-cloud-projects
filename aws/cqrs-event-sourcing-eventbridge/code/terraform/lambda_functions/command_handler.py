import json
import boto3
import uuid
import os
from datetime import datetime
from decimal import Decimal

dynamodb = boto3.resource('dynamodb')

def lambda_handler(event, context):
    """
    Command Handler for CQRS Architecture
    Processes business commands and generates domain events with optimistic concurrency control
    """
    try:
        # Parse command from API Gateway or direct invocation
        command = json.loads(event['body']) if 'body' in event else event
        
        # Command validation
        command_type = command.get('commandType')
        aggregate_id = command.get('aggregateId', str(uuid.uuid4()))
        
        if not command_type:
            return {
                'statusCode': 400,
                'headers': {
                    'Content-Type': 'application/json',
                    'Access-Control-Allow-Origin': '*'
                },
                'body': json.dumps({'error': 'commandType is required'})
            }
        
        # Get current version for optimistic concurrency control
        table = dynamodb.Table(os.environ['EVENT_STORE_TABLE'])
        
        # Query existing events for this aggregate to determine current version
        response = table.query(
            KeyConditionExpression='AggregateId = :id',
            ExpressionAttributeValues={':id': aggregate_id},
            ScanIndexForward=False,
            Limit=1
        )
        
        current_version = 0
        if response['Items']:
            current_version = int(response['Items'][0]['Version'])
        
        # Create domain event from command
        event_id = str(uuid.uuid4())
        new_version = current_version + 1
        timestamp = datetime.utcnow().isoformat()
        
        # Transform command into domain event
        event_data = create_event_from_command(command_type, command, aggregate_id)
        
        # Store event in event store with optimistic concurrency control
        table.put_item(
            Item={
                'AggregateId': aggregate_id,
                'Version': new_version,
                'EventId': event_id,
                'EventType': event_data['eventType'],
                'Timestamp': timestamp,
                'EventData': event_data['data'],
                'CommandId': command.get('commandId', str(uuid.uuid4())),
                'CorrelationId': command.get('correlationId', str(uuid.uuid4()))
            },
            # Prevent concurrent modifications to the same aggregate version
            ConditionExpression='attribute_not_exists(AggregateId) AND attribute_not_exists(Version)'
        )
        
        print(f"Event stored: {event_id} for aggregate {aggregate_id} version {new_version}")
        
        return {
            'statusCode': 201,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({
                'aggregateId': aggregate_id,
                'version': new_version,
                'eventId': event_id,
                'eventType': event_data['eventType']
            })
        }
        
    except Exception as e:
        print(f"Error processing command: {str(e)}")
        return {
            'statusCode': 500,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({'error': 'Internal server error', 'details': str(e)})
        }

def create_event_from_command(command_type, command, aggregate_id):
    """
    Transform commands into domain events
    This implements the business logic that converts imperative commands into declarative events
    """
    
    if command_type == 'CreateUser':
        return {
            'eventType': 'UserCreated',
            'data': {
                'userId': aggregate_id,
                'email': command['email'],
                'name': command['name'],
                'createdAt': datetime.utcnow().isoformat()
            }
        }
    
    elif command_type == 'UpdateUserProfile':
        return {
            'eventType': 'UserProfileUpdated',
            'data': {
                'userId': aggregate_id,
                'changes': command['changes'],
                'updatedAt': datetime.utcnow().isoformat()
            }
        }
    
    elif command_type == 'CreateOrder':
        return {
            'eventType': 'OrderCreated',
            'data': {
                'orderId': aggregate_id,
                'userId': command['userId'],
                'items': command['items'],
                'totalAmount': command['totalAmount'],
                'createdAt': datetime.utcnow().isoformat()
            }
        }
    
    elif command_type == 'UpdateOrderStatus':
        return {
            'eventType': 'OrderStatusUpdated',
            'data': {
                'orderId': aggregate_id,
                'status': command['status'],
                'updatedAt': datetime.utcnow().isoformat()
            }
        }
    
    else:
        raise ValueError(f"Unknown command type: {command_type}")