import json
import boto3
import uuid
from datetime import datetime
import os

# Initialize AWS clients
events_client = boto3.client('events')
dynamodb = boto3.resource('dynamodb')
table = dynamodb.Table(os.environ['EVENT_STORE_TABLE'])

def lambda_handler(event, context):
    """
    Command handler Lambda function for event sourcing architecture.
    
    This function processes business commands and converts them into immutable events.
    It implements the write side of the CQRS pattern by:
    1. Receiving commands from various sources
    2. Generating unique events with proper sequencing
    3. Storing events in DynamoDB event store
    4. Publishing events to EventBridge for downstream processing
    
    Args:
        event: Lambda event containing command data
        context: Lambda context object
        
    Returns:
        dict: Response containing event ID, aggregate ID, and sequence number
    """
    try:
        # Parse command from event (handle both API Gateway and direct invocation)
        command = json.loads(event['body']) if 'body' in event else event
        
        # Validate required command fields
        required_fields = ['aggregateId', 'eventType', 'eventData']
        for field in required_fields:
            if field not in command:
                return {
                    'statusCode': 400,
                    'body': json.dumps({
                        'error': f'Missing required field: {field}'
                    })
                }
        
        # Extract command details
        aggregate_id = command['aggregateId']
        event_type = command['eventType']
        event_data = command['eventData']
        
        # Generate unique event ID
        event_id = str(uuid.uuid4())
        
        # Get next sequence number for this aggregate
        # This ensures proper ordering of events within the aggregate
        response = table.query(
            KeyConditionExpression='AggregateId = :aid',
            ExpressionAttributeValues={':aid': aggregate_id},
            ScanIndexForward=False,  # Get most recent event first
            Limit=1
        )
        
        # Determine next sequence number
        next_sequence = 1
        if response['Items']:
            next_sequence = response['Items'][0]['EventSequence'] + 1
        
        # Create event record with all necessary metadata
        timestamp = datetime.utcnow().isoformat()
        event_record = {
            'EventId': event_id,
            'AggregateId': aggregate_id,
            'EventSequence': next_sequence,
            'EventType': event_type,
            'EventData': event_data,
            'Timestamp': timestamp,
            'Version': '1.0',
            'CommandId': command.get('commandId', event_id),
            'UserId': command.get('userId', 'system'),
            'CorrelationId': command.get('correlationId', event_id)
        }
        
        # Store event in DynamoDB event store
        # This is the "single source of truth" for all events
        table.put_item(Item=event_record)
        
        # Publish event to EventBridge for downstream processing
        # This triggers projections and other event-driven processes
        event_bus_name = os.environ['EVENT_BUS_NAME']
        
        events_client.put_events(
            Entries=[
                {
                    'Source': 'event-sourcing.financial',
                    'DetailType': event_type,
                    'Detail': json.dumps(event_record),
                    'EventBusName': event_bus_name,
                    'Resources': [
                        f'arn:aws:dynamodb:{os.environ.get("AWS_REGION", "us-east-1")}:'
                        f'{os.environ.get("AWS_ACCOUNT_ID", "123456789012")}:table/'
                        f'{os.environ["EVENT_STORE_TABLE"]}'
                    ]
                }
            ]
        )
        
        print(f"Successfully processed command: {event_type} for aggregate: {aggregate_id}")
        
        return {
            'statusCode': 200,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({
                'eventId': event_id,
                'aggregateId': aggregate_id,
                'sequence': next_sequence,
                'timestamp': timestamp,
                'eventType': event_type
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
            'body': json.dumps({
                'error': str(e),
                'type': 'CommandProcessingError'
            })
        }