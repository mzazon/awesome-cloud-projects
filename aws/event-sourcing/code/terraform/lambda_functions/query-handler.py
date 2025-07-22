import json
import boto3
import os
from boto3.dynamodb.conditions import Key
from decimal import Decimal
from datetime import datetime

# Initialize DynamoDB resource
dynamodb = boto3.resource('dynamodb')
event_store_table = dynamodb.Table(os.environ['EVENT_STORE_TABLE'])
read_model_table = dynamodb.Table(os.environ['READ_MODEL_TABLE'])

def lambda_handler(event, context):
    """
    Query handler Lambda function for event sourcing architecture.
    
    This function provides various query capabilities including:
    1. Retrieving current state from projections (fast queries)
    2. Reconstructing historical state from events (temporal queries)
    3. Getting complete event history for aggregates
    4. Supporting multiple query types and patterns
    
    Args:
        event: Lambda event containing query parameters
        context: Lambda context object
        
    Returns:
        dict: Response containing query results
    """
    try:
        # Parse query from event (handle both API Gateway and direct invocation)
        query = json.loads(event['body']) if 'body' in event else event
        
        # Get query type
        query_type = query.get('queryType')
        
        if not query_type:
            return {
                'statusCode': 400,
                'headers': {
                    'Content-Type': 'application/json',
                    'Access-Control-Allow-Origin': '*'
                },
                'body': json.dumps({
                    'error': 'Missing required field: queryType',
                    'supportedQueryTypes': [
                        'getAggregateEvents',
                        'getAccountSummary',
                        'getAuditTrail',
                        'reconstructState',
                        'getEventsByType',
                        'getEventsByTimeRange'
                    ]
                })
            }
        
        # Route to appropriate query handler
        if query_type == 'getAggregateEvents':
            return get_aggregate_events(query)
        elif query_type == 'getAccountSummary':
            return get_account_summary(query)
        elif query_type == 'getAuditTrail':
            return get_audit_trail(query)
        elif query_type == 'reconstructState':
            return reconstruct_state(query)
        elif query_type == 'getEventsByType':
            return get_events_by_type(query)
        elif query_type == 'getEventsByTimeRange':
            return get_events_by_time_range(query)
        else:
            return {
                'statusCode': 400,
                'headers': {
                    'Content-Type': 'application/json',
                    'Access-Control-Allow-Origin': '*'
                },
                'body': json.dumps({
                    'error': f'Unknown query type: {query_type}',
                    'supportedQueryTypes': [
                        'getAggregateEvents',
                        'getAccountSummary',
                        'getAuditTrail',
                        'reconstructState',
                        'getEventsByType',
                        'getEventsByTimeRange'
                    ]
                })
            }
            
    except Exception as e:
        print(f"Error in query handler: {str(e)}")
        return {
            'statusCode': 500,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({
                'error': str(e),
                'type': 'QueryProcessingError'
            })
        }

def get_aggregate_events(query):
    """
    Get all events for a specific aggregate in chronological order.
    
    Args:
        query: Query parameters containing aggregateId
        
    Returns:
        dict: Response containing all events for the aggregate
    """
    try:
        aggregate_id = query.get('aggregateId')
        
        if not aggregate_id:
            return {
                'statusCode': 400,
                'headers': {'Content-Type': 'application/json'},
                'body': json.dumps({'error': 'Missing required field: aggregateId'})
            }
        
        # Query events from event store
        response = event_store_table.query(
            KeyConditionExpression=Key('AggregateId').eq(aggregate_id),
            ScanIndexForward=True  # Chronological order
        )
        
        return {
            'statusCode': 200,
            'headers': {'Content-Type': 'application/json'},
            'body': json.dumps({
                'aggregateId': aggregate_id,
                'events': response['Items'],
                'eventCount': len(response['Items'])
            }, default=decimal_default)
        }
        
    except Exception as e:
        print(f"Error in get_aggregate_events: {str(e)}")
        return {
            'statusCode': 500,
            'headers': {'Content-Type': 'application/json'},
            'body': json.dumps({'error': str(e)})
        }

def get_account_summary(query):
    """
    Get current account summary from read model (fast query).
    
    Args:
        query: Query parameters containing accountId
        
    Returns:
        dict: Response containing account summary
    """
    try:
        account_id = query.get('accountId')
        
        if not account_id:
            return {
                'statusCode': 400,
                'headers': {'Content-Type': 'application/json'},
                'body': json.dumps({'error': 'Missing required field: accountId'})
            }
        
        # Get account summary from read model
        response = read_model_table.get_item(
            Key={'AccountId': account_id, 'ProjectionType': 'AccountSummary'}
        )
        
        if 'Item' in response:
            return {
                'statusCode': 200,
                'headers': {'Content-Type': 'application/json'},
                'body': json.dumps(response['Item'], default=decimal_default)
            }
        else:
            return {
                'statusCode': 404,
                'headers': {'Content-Type': 'application/json'},
                'body': json.dumps({'error': 'Account not found'})
            }
            
    except Exception as e:
        print(f"Error in get_account_summary: {str(e)}")
        return {
            'statusCode': 500,
            'headers': {'Content-Type': 'application/json'},
            'body': json.dumps({'error': str(e)})
        }

def get_audit_trail(query):
    """
    Get audit trail for an account from read model.
    
    Args:
        query: Query parameters containing accountId
        
    Returns:
        dict: Response containing audit trail
    """
    try:
        account_id = query.get('accountId')
        
        if not account_id:
            return {
                'statusCode': 400,
                'headers': {'Content-Type': 'application/json'},
                'body': json.dumps({'error': 'Missing required field: accountId'})
            }
        
        # Get audit trail from read model
        response = read_model_table.get_item(
            Key={'AccountId': account_id, 'ProjectionType': 'AuditTrail'}
        )
        
        if 'Item' in response:
            return {
                'statusCode': 200,
                'headers': {'Content-Type': 'application/json'},
                'body': json.dumps(response['Item'], default=decimal_default)
            }
        else:
            return {
                'statusCode': 404,
                'headers': {'Content-Type': 'application/json'},
                'body': json.dumps({'error': 'Audit trail not found'})
            }
            
    except Exception as e:
        print(f"Error in get_audit_trail: {str(e)}")
        return {
            'statusCode': 500,
            'headers': {'Content-Type': 'application/json'},
            'body': json.dumps({'error': str(e)})
        }

def reconstruct_state(query):
    """
    Reconstruct aggregate state at a specific point in time by replaying events.
    
    Args:
        query: Query parameters containing aggregateId and optional upToSequence
        
    Returns:
        dict: Response containing reconstructed state
    """
    try:
        aggregate_id = query.get('aggregateId')
        up_to_sequence = query.get('upToSequence')
        
        if not aggregate_id:
            return {
                'statusCode': 400,
                'headers': {'Content-Type': 'application/json'},
                'body': json.dumps({'error': 'Missing required field: aggregateId'})
            }
        
        # Build key condition for event query
        key_condition = Key('AggregateId').eq(aggregate_id)
        
        # Add sequence constraint if provided
        if up_to_sequence:
            key_condition = key_condition & Key('EventSequence').lte(up_to_sequence)
        
        # Query events from event store
        response = event_store_table.query(
            KeyConditionExpression=key_condition,
            ScanIndexForward=True  # Chronological order
        )
        
        # Reconstruct state by replaying events
        state = {
            'aggregateId': aggregate_id,
            'balance': Decimal('0.00'),
            'status': 'Unknown',
            'transactionCount': 0,
            'accountType': 'unknown',
            'customerId': 'unknown',
            'createdAt': None,
            'closedAt': None,
            'lastTransactionAt': None
        }
        
        for event in response['Items']:
            event_type = event.get('EventType')
            event_data = event.get('EventData', {})
            
            if event_type == 'AccountCreated':
                state['status'] = 'Active'
                state['accountType'] = event_data.get('accountType', 'unknown')
                state['customerId'] = event_data.get('customerId', 'unknown')
                state['createdAt'] = event_data.get('createdAt')
                
            elif event_type == 'TransactionProcessed':
                amount = Decimal(str(event_data.get('amount', 0)))
                state['balance'] += amount
                state['transactionCount'] += 1
                state['lastTransactionAt'] = event_data.get('timestamp')
                
            elif event_type == 'AccountClosed':
                state['status'] = 'Closed'
                state['closedAt'] = event_data.get('closedAt')
        
        return {
            'statusCode': 200,
            'headers': {'Content-Type': 'application/json'},
            'body': json.dumps({
                'aggregateId': aggregate_id,
                'reconstructedState': state,
                'eventsProcessed': len(response['Items']),
                'upToSequence': up_to_sequence,
                'reconstructionTimestamp': datetime.utcnow().isoformat()
            }, default=decimal_default)
        }
        
    except Exception as e:
        print(f"Error in reconstruct_state: {str(e)}")
        return {
            'statusCode': 500,
            'headers': {'Content-Type': 'application/json'},
            'body': json.dumps({'error': str(e)})
        }

def get_events_by_type(query):
    """
    Get events by event type using GSI.
    
    Args:
        query: Query parameters containing eventType and optional timeRange
        
    Returns:
        dict: Response containing events of specified type
    """
    try:
        event_type = query.get('eventType')
        start_time = query.get('startTime')
        end_time = query.get('endTime')
        limit = query.get('limit', 100)
        
        if not event_type:
            return {
                'statusCode': 400,
                'headers': {'Content-Type': 'application/json'},
                'body': json.dumps({'error': 'Missing required field: eventType'})
            }
        
        # Build query parameters
        query_params = {
            'IndexName': 'EventType-Timestamp-index',
            'KeyConditionExpression': Key('EventType').eq(event_type),
            'ScanIndexForward': False,  # Most recent first
            'Limit': limit
        }
        
        # Add timestamp range if provided
        if start_time and end_time:
            query_params['KeyConditionExpression'] = query_params['KeyConditionExpression'] & \
                Key('Timestamp').between(start_time, end_time)
        elif start_time:
            query_params['KeyConditionExpression'] = query_params['KeyConditionExpression'] & \
                Key('Timestamp').gte(start_time)
        elif end_time:
            query_params['KeyConditionExpression'] = query_params['KeyConditionExpression'] & \
                Key('Timestamp').lte(end_time)
        
        # Execute query
        response = event_store_table.query(**query_params)
        
        return {
            'statusCode': 200,
            'headers': {'Content-Type': 'application/json'},
            'body': json.dumps({
                'eventType': event_type,
                'events': response['Items'],
                'eventCount': len(response['Items']),
                'startTime': start_time,
                'endTime': end_time
            }, default=decimal_default)
        }
        
    except Exception as e:
        print(f"Error in get_events_by_type: {str(e)}")
        return {
            'statusCode': 500,
            'headers': {'Content-Type': 'application/json'},
            'body': json.dumps({'error': str(e)})
        }

def get_events_by_time_range(query):
    """
    Get events within a specific time range across all event types.
    
    Args:
        query: Query parameters containing startTime and endTime
        
    Returns:
        dict: Response containing events within time range
    """
    try:
        start_time = query.get('startTime')
        end_time = query.get('endTime')
        limit = query.get('limit', 100)
        
        if not start_time or not end_time:
            return {
                'statusCode': 400,
                'headers': {'Content-Type': 'application/json'},
                'body': json.dumps({'error': 'Missing required fields: startTime and endTime'})
            }
        
        # Use scan with filter for time range queries across all event types
        response = event_store_table.scan(
            FilterExpression=Key('Timestamp').between(start_time, end_time),
            Limit=limit
        )
        
        # Sort events by timestamp
        events = sorted(response['Items'], key=lambda x: x.get('Timestamp', ''))
        
        return {
            'statusCode': 200,
            'headers': {'Content-Type': 'application/json'},
            'body': json.dumps({
                'events': events,
                'eventCount': len(events),
                'startTime': start_time,
                'endTime': end_time
            }, default=decimal_default)
        }
        
    except Exception as e:
        print(f"Error in get_events_by_time_range: {str(e)}")
        return {
            'statusCode': 500,
            'headers': {'Content-Type': 'application/json'},
            'body': json.dumps({'error': str(e)})
        }

def decimal_default(obj):
    """
    JSON serializer for objects not serializable by default json code.
    Handles Decimal types from DynamoDB.
    """
    if isinstance(obj, Decimal):
        return float(obj)
    raise TypeError(f"Object of type {type(obj)} is not JSON serializable")