import json
import boto3
import os
from decimal import Decimal

dynamodb = boto3.resource('dynamodb')

def lambda_handler(event, context):
    """
    Order Projection Handler for CQRS Read Model
    Maintains the order summaries read model based on order-related domain events
    """
    try:
        processed_events = 0
        
        # Extract event details from EventBridge
        detail = event['detail']
        event_type = detail['EventType']
        event_data = detail['EventData']
        
        table = dynamodb.Table(os.environ['ORDER_READ_MODEL_TABLE'])
        
        # Process order events to maintain read model
        if event_type == 'OrderCreated':
            # Create new order summary in read model
            table.put_item(
                Item={
                    'OrderId': event_data['orderId'],
                    'UserId': event_data['userId'],
                    'Items': event_data['items'],
                    'TotalAmount': Decimal(str(event_data['totalAmount'])),
                    'Status': 'Created',
                    'CreatedAt': event_data['createdAt'],
                    'UpdatedAt': event_data['createdAt'],
                    'Version': detail['Version'],
                    'LastEventId': detail['EventId']
                }
            )
            processed_events += 1
            print(f"Created order summary for {event_data['orderId']}")
            
        elif event_type == 'OrderStatusUpdated':
            # Update order status in read model
            table.update_item(
                Key={'OrderId': event_data['orderId']},
                UpdateExpression="SET #status = :status, UpdatedAt = :updated, Version = :version, LastEventId = :eventId",
                ExpressionAttributeNames={
                    '#status': 'Status'  # Use expression attribute names to handle reserved words
                },
                ExpressionAttributeValues={
                    ':status': event_data['status'],
                    ':updated': event_data['updatedAt'],
                    ':version': detail['Version'],
                    ':eventId': detail['EventId']
                },
                # Ensure the order exists before updating
                ConditionExpression="attribute_exists(OrderId)"
            )
            processed_events += 1
            print(f"Updated order status for {event_data['orderId']} to {event_data['status']}")
        
        elif event_type == 'OrderCancelled':
            # Handle order cancellation
            table.update_item(
                Key={'OrderId': event_data['orderId']},
                UpdateExpression="SET #status = :status, UpdatedAt = :updated, Version = :version, LastEventId = :eventId, CancelledAt = :cancelled",
                ExpressionAttributeNames={
                    '#status': 'Status'
                },
                ExpressionAttributeValues={
                    ':status': 'Cancelled',
                    ':updated': event_data['updatedAt'],
                    ':version': detail['Version'],
                    ':eventId': detail['EventId'],
                    ':cancelled': event_data.get('cancelledAt', event_data['updatedAt'])
                },
                ConditionExpression="attribute_exists(OrderId)"
            )
            processed_events += 1
            print(f"Cancelled order {event_data['orderId']}")
        
        elif event_type == 'OrderCompleted':
            # Handle order completion
            table.update_item(
                Key={'OrderId': event_data['orderId']},
                UpdateExpression="SET #status = :status, UpdatedAt = :updated, Version = :version, LastEventId = :eventId, CompletedAt = :completed",
                ExpressionAttributeNames={
                    '#status': 'Status'
                },
                ExpressionAttributeValues={
                    ':status': 'Completed',
                    ':updated': event_data['updatedAt'],
                    ':version': detail['Version'],
                    ':eventId': detail['EventId'],
                    ':completed': event_data.get('completedAt', event_data['updatedAt'])
                },
                ConditionExpression="attribute_exists(OrderId)"
            )
            processed_events += 1
            print(f"Completed order {event_data['orderId']}")
        
        else:
            print(f"Unhandled event type in order projection: {event_type}")
        
        return {
            'statusCode': 200,
            'processedEvents': processed_events,
            'eventType': event_type
        }
        
    except Exception as e:
        print(f"Error in order projection: {str(e)}")
        print(f"Event details: {json.dumps(event, default=str)}")
        # Re-raise to trigger EventBridge retry mechanism
        raise

def convert_decimal_to_float(obj):
    """
    Helper function to convert Decimal objects to float for JSON serialization
    """
    if isinstance(obj, Decimal):
        return float(obj)
    raise TypeError(f"Object of type {type(obj)} is not JSON serializable")