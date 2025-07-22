import json
import boto3
import os
from decimal import Decimal
from datetime import datetime

# Initialize DynamoDB resource
dynamodb = boto3.resource('dynamodb')
read_model_table = dynamodb.Table(os.environ['READ_MODEL_TABLE'])

def lambda_handler(event, context):
    """
    Projection handler Lambda function for event sourcing architecture.
    
    This function implements the read side of the CQRS pattern by:
    1. Processing events from EventBridge
    2. Materializing read models from events
    3. Maintaining optimized views for queries
    4. Supporting multiple projection types per aggregate
    
    Args:
        event: Lambda event containing EventBridge event data
        context: Lambda context object
        
    Returns:
        dict: Response indicating processing status
    """
    try:
        processed_events = 0
        failed_events = 0
        
        # Process EventBridge events
        # Events can come from direct EventBridge invocation or SQS
        records = event.get('Records', [])
        
        # Handle direct EventBridge invocation
        if not records and 'detail' in event:
            records = [{'body': json.dumps(event['detail'])}]
        
        for record in records:
            try:
                # Parse event detail
                if 'body' in record:
                    detail = json.loads(record['body'])
                else:
                    detail = record.get('detail', record)
                
                # Extract event information
                event_type = detail.get('EventType')
                aggregate_id = detail.get('AggregateId')
                event_data = detail.get('EventData', {})
                event_id = detail.get('EventId')
                timestamp = detail.get('Timestamp')
                
                if not event_type or not aggregate_id:
                    print(f"Skipping event with missing required fields: {detail}")
                    failed_events += 1
                    continue
                
                # Route to appropriate event handler
                if event_type == 'AccountCreated':
                    handle_account_created(aggregate_id, event_data, event_id, timestamp)
                elif event_type == 'TransactionProcessed':
                    handle_transaction_processed(aggregate_id, event_data, event_id, timestamp)
                elif event_type == 'AccountClosed':
                    handle_account_closed(aggregate_id, event_data, event_id, timestamp)
                else:
                    print(f"Unknown event type: {event_type}")
                    failed_events += 1
                    continue
                
                processed_events += 1
                print(f"Successfully processed event: {event_type} for aggregate: {aggregate_id}")
                
            except Exception as e:
                print(f"Error processing individual event: {str(e)}")
                failed_events += 1
                continue
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'processedEvents': processed_events,
                'failedEvents': failed_events,
                'totalEvents': len(records)
            })
        }
        
    except Exception as e:
        print(f"Error in projection handler: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': str(e),
                'type': 'ProjectionProcessingError'
            })
        }

def handle_account_created(aggregate_id, event_data, event_id, timestamp):
    """
    Handle AccountCreated events by creating initial account summary projection.
    
    Args:
        aggregate_id: The account ID
        event_data: Event payload containing account details
        event_id: Unique event identifier
        timestamp: Event timestamp
    """
    try:
        # Create initial account summary projection
        read_model_table.put_item(
            Item={
                'AccountId': aggregate_id,
                'ProjectionType': 'AccountSummary',
                'Balance': Decimal('0.00'),
                'Status': 'Active',
                'AccountType': event_data.get('accountType', 'unknown'),
                'CustomerId': event_data.get('customerId', 'unknown'),
                'CreatedAt': event_data.get('createdAt', timestamp),
                'TransactionCount': 0,
                'LastEventId': event_id,
                'LastUpdated': timestamp or datetime.utcnow().isoformat(),
                'Version': 1
            }
        )
        
        # Create account audit trail projection
        read_model_table.put_item(
            Item={
                'AccountId': aggregate_id,
                'ProjectionType': 'AuditTrail',
                'Events': [
                    {
                        'EventId': event_id,
                        'EventType': 'AccountCreated',
                        'Timestamp': timestamp or datetime.utcnow().isoformat(),
                        'Data': event_data
                    }
                ],
                'LastEventId': event_id,
                'LastUpdated': timestamp or datetime.utcnow().isoformat(),
                'Version': 1
            }
        )
        
    except Exception as e:
        print(f"Error handling AccountCreated event: {str(e)}")
        raise

def handle_transaction_processed(aggregate_id, event_data, event_id, timestamp):
    """
    Handle TransactionProcessed events by updating account balance and transaction count.
    
    Args:
        aggregate_id: The account ID
        event_data: Event payload containing transaction details
        event_id: Unique event identifier
        timestamp: Event timestamp
    """
    try:
        # Get current account summary
        response = read_model_table.get_item(
            Key={'AccountId': aggregate_id, 'ProjectionType': 'AccountSummary'}
        )
        
        if 'Item' not in response:
            print(f"Account summary not found for {aggregate_id}, creating new one")
            # Create account summary if it doesn't exist
            handle_account_created(aggregate_id, {
                'accountType': 'unknown',
                'customerId': 'unknown',
                'createdAt': timestamp
            }, event_id, timestamp)
            
            # Get the newly created item
            response = read_model_table.get_item(
                Key={'AccountId': aggregate_id, 'ProjectionType': 'AccountSummary'}
            )
        
        current_item = response['Item']
        current_balance = current_item.get('Balance', Decimal('0.00'))
        transaction_count = current_item.get('TransactionCount', 0)
        
        # Calculate new balance
        transaction_amount = Decimal(str(event_data.get('amount', 0)))
        new_balance = current_balance + transaction_amount
        
        # Update account summary
        read_model_table.update_item(
            Key={'AccountId': aggregate_id, 'ProjectionType': 'AccountSummary'},
            UpdateExpression='SET Balance = :balance, TransactionCount = :count, '
                           'LastTransactionAt = :trans_time, LastEventId = :event_id, '
                           'LastUpdated = :updated, Version = Version + :inc',
            ExpressionAttributeValues={
                ':balance': new_balance,
                ':count': transaction_count + 1,
                ':trans_time': timestamp or datetime.utcnow().isoformat(),
                ':event_id': event_id,
                ':updated': timestamp or datetime.utcnow().isoformat(),
                ':inc': 1
            }
        )
        
        # Update audit trail (append new event)
        read_model_table.update_item(
            Key={'AccountId': aggregate_id, 'ProjectionType': 'AuditTrail'},
            UpdateExpression='SET Events = list_append(if_not_exists(Events, :empty_list), :new_event), '
                           'LastEventId = :event_id, LastUpdated = :updated, Version = Version + :inc',
            ExpressionAttributeValues={
                ':empty_list': [],
                ':new_event': [
                    {
                        'EventId': event_id,
                        'EventType': 'TransactionProcessed',
                        'Timestamp': timestamp or datetime.utcnow().isoformat(),
                        'Data': event_data
                    }
                ],
                ':event_id': event_id,
                ':updated': timestamp or datetime.utcnow().isoformat(),
                ':inc': 1
            }
        )
        
    except Exception as e:
        print(f"Error handling TransactionProcessed event: {str(e)}")
        raise

def handle_account_closed(aggregate_id, event_data, event_id, timestamp):
    """
    Handle AccountClosed events by updating account status.
    
    Args:
        aggregate_id: The account ID
        event_data: Event payload containing closure details
        event_id: Unique event identifier
        timestamp: Event timestamp
    """
    try:
        # Update account summary status
        read_model_table.update_item(
            Key={'AccountId': aggregate_id, 'ProjectionType': 'AccountSummary'},
            UpdateExpression='SET #status = :status, ClosedAt = :closed_at, '
                           'LastEventId = :event_id, LastUpdated = :updated, Version = Version + :inc',
            ExpressionAttributeNames={
                '#status': 'Status'
            },
            ExpressionAttributeValues={
                ':status': 'Closed',
                ':closed_at': event_data.get('closedAt', timestamp),
                ':event_id': event_id,
                ':updated': timestamp or datetime.utcnow().isoformat(),
                ':inc': 1
            }
        )
        
        # Update audit trail
        read_model_table.update_item(
            Key={'AccountId': aggregate_id, 'ProjectionType': 'AuditTrail'},
            UpdateExpression='SET Events = list_append(if_not_exists(Events, :empty_list), :new_event), '
                           'LastEventId = :event_id, LastUpdated = :updated, Version = Version + :inc',
            ExpressionAttributeValues={
                ':empty_list': [],
                ':new_event': [
                    {
                        'EventId': event_id,
                        'EventType': 'AccountClosed',
                        'Timestamp': timestamp or datetime.utcnow().isoformat(),
                        'Data': event_data
                    }
                ],
                ':event_id': event_id,
                ':updated': timestamp or datetime.utcnow().isoformat(),
                ':inc': 1
            }
        )
        
    except Exception as e:
        print(f"Error handling AccountClosed event: {str(e)}")
        raise