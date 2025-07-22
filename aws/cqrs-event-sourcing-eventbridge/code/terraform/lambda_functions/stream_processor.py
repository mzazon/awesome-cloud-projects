import json
import boto3
import os
from decimal import Decimal

eventbridge = boto3.client('events')

def lambda_handler(event, context):
    """
    DynamoDB Stream Processor for Event Sourcing
    Transforms DynamoDB stream events into domain events and publishes to EventBridge
    """
    try:
        processed_events = 0
        
        for record in event['Records']:
            # Only process INSERT events (new events in the event store)
            if record['eventName'] in ['INSERT']:
                # Extract event data from DynamoDB stream record
                dynamodb_event = record['dynamodb']['NewImage']
                
                # Convert DynamoDB format to standard domain event format
                domain_event = {
                    'EventId': dynamodb_event['EventId']['S'],
                    'AggregateId': dynamodb_event['AggregateId']['S'],
                    'EventType': dynamodb_event['EventType']['S'],
                    'Version': int(dynamodb_event['Version']['N']),
                    'Timestamp': dynamodb_event['Timestamp']['S'],
                    'EventData': deserialize_dynamodb_item(dynamodb_event['EventData']['M']),
                    'CommandId': dynamodb_event.get('CommandId', {}).get('S'),
                    'CorrelationId': dynamodb_event.get('CorrelationId', {}).get('S')
                }
                
                # Publish domain event to EventBridge for distribution to projections
                eventbridge.put_events(
                    Entries=[{
                        'Source': 'cqrs.demo',
                        'DetailType': domain_event['EventType'],
                        'Detail': json.dumps(domain_event, default=str),
                        'EventBusName': os.environ['EVENT_BUS_NAME']
                    }]
                )
                
                processed_events += 1
                print(f"Published event {domain_event['EventId']} ({domain_event['EventType']}) to EventBridge")
        
        print(f"Successfully processed {processed_events} events")
        return {'statusCode': 200, 'processedEvents': processed_events}
        
    except Exception as e:
        print(f"Error processing DynamoDB stream: {str(e)}")
        # Re-raise the exception to trigger Lambda retry mechanism
        raise

def deserialize_dynamodb_item(item):
    """
    Convert DynamoDB item format to regular Python objects
    Handles all DynamoDB data types including nested structures
    """
    if isinstance(item, dict):
        if len(item) == 1:
            key, value = next(iter(item.items()))
            
            # Handle DynamoDB data type indicators
            if key == 'S':  # String
                return value
            elif key == 'N':  # Number
                return Decimal(value)
            elif key == 'B':  # Binary
                return value
            elif key == 'SS':  # String Set
                return set(value)
            elif key == 'NS':  # Number Set
                return set(Decimal(v) for v in value)
            elif key == 'BS':  # Binary Set
                return set(value)
            elif key == 'M':  # Map
                return {k: deserialize_dynamodb_item(v) for k, v in value.items()}
            elif key == 'L':  # List
                return [deserialize_dynamodb_item(v) for v in value]
            elif key == 'NULL':  # Null
                return None
            elif key == 'BOOL':  # Boolean
                return value
        else:
            # Handle nested maps
            return {k: deserialize_dynamodb_item(v) for k, v in item.items()}
    
    return item