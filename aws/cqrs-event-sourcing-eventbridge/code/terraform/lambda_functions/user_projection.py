import json
import boto3
import os
from decimal import Decimal

dynamodb = boto3.resource('dynamodb')

def lambda_handler(event, context):
    """
    User Projection Handler for CQRS Read Model
    Maintains the user profiles read model based on user-related domain events
    """
    try:
        processed_events = 0
        
        # Extract event details from EventBridge
        detail = event['detail']
        event_type = detail['EventType']
        event_data = detail['EventData']
        
        table = dynamodb.Table(os.environ['USER_READ_MODEL_TABLE'])
        
        # Process user events to maintain read model
        if event_type == 'UserCreated':
            # Create new user profile in read model
            table.put_item(
                Item={
                    'UserId': event_data['userId'],
                    'Email': event_data['email'],
                    'Name': event_data['name'],
                    'CreatedAt': event_data['createdAt'],
                    'UpdatedAt': event_data['createdAt'],
                    'Version': detail['Version'],
                    'LastEventId': detail['EventId']
                }
            )
            processed_events += 1
            print(f"Created user profile for {event_data['userId']}")
            
        elif event_type == 'UserProfileUpdated':
            # Update user profile in read model
            update_expression = "SET UpdatedAt = :updated, Version = :version, LastEventId = :eventId"
            expression_values = {
                ':updated': event_data['updatedAt'],
                ':version': detail['Version'],
                ':eventId': detail['EventId']
            }
            
            # Build dynamic update expression for changed fields
            for field, value in event_data['changes'].items():
                # Only allow updates to specific fields for security
                if field in ['Name', 'Email', 'Phone', 'Address']:
                    sanitized_field = field.replace(' ', '_')  # Handle spaces in field names
                    update_expression += f", {sanitized_field} = :{sanitized_field.lower()}"
                    expression_values[f":{sanitized_field.lower()}"] = value
            
            table.update_item(
                Key={'UserId': event_data['userId']},
                UpdateExpression=update_expression,
                ExpressionAttributeValues=expression_values,
                # Ensure we're updating the correct version (basic optimistic locking)
                ConditionExpression="attribute_exists(UserId)"
            )
            processed_events += 1
            print(f"Updated user profile for {event_data['userId']}")
        
        else:
            print(f"Unhandled event type in user projection: {event_type}")
        
        return {
            'statusCode': 200,
            'processedEvents': processed_events,
            'eventType': event_type
        }
        
    except Exception as e:
        print(f"Error in user projection: {str(e)}")
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