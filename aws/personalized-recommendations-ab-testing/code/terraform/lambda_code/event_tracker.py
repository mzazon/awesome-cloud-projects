import json
import boto3
import os
from datetime import datetime

personalize_events = boto3.client('personalize-events')
dynamodb = boto3.resource('dynamodb')

def lambda_handler(event, context):
    """
    Event Tracker Lambda Function
    
    Tracks user interaction events for both analytics and 
    Amazon Personalize real-time training.
    """
    try:
        # Parse request body if it's a string (API Gateway format)
        if isinstance(event.get('body'), str):
            body = json.loads(event['body'])
        else:
            body = event
        
        # Parse event data
        user_id = body.get('user_id')
        session_id = body.get('session_id', user_id)
        event_type = body.get('event_type')
        item_id = body.get('item_id')
        recommendation_id = body.get('recommendation_id')
        properties = body.get('properties', {})
        
        if not all([user_id, event_type]):
            return {
                'statusCode': 400,
                'headers': {
                    'Content-Type': 'application/json',
                    'Access-Control-Allow-Origin': '*'
                },
                'body': json.dumps({'error': 'user_id and event_type are required'})
            }
        
        # Store event in DynamoDB for analytics
        analytics_success = store_event_analytics(body)
        
        # Send event to Personalize (if real-time tracking is enabled and item_id provided)
        personalize_success = False
        if os.environ.get('EVENT_TRACKER_ARN') and item_id:
            personalize_success = send_to_personalize(user_id, session_id, event_type, item_id, properties)
        
        return {
            'statusCode': 200,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({
                'message': 'Event tracked successfully',
                'analytics_stored': analytics_success,
                'personalize_sent': personalize_success,
                'timestamp': datetime.now().isoformat()
            })
        }
        
    except Exception as e:
        print(f"Error in event tracker: {str(e)}")
        return {
            'statusCode': 500,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({'error': str(e)})
        }

def store_event_analytics(event_data):
    """Store detailed event data in DynamoDB for analytics"""
    events_table = dynamodb.Table(os.environ['EVENTS_TABLE'])
    
    try:
        # Calculate TTL (90 days from now for analytics data retention)
        ttl_timestamp = int(datetime.now().timestamp()) + (90 * 24 * 60 * 60)
        
        # Store detailed event for analytics
        events_table.put_item(
            Item={
                'UserId': event_data['user_id'],
                'Timestamp': int(datetime.now().timestamp() * 1000),
                'EventType': event_data['event_type'],
                'ItemId': event_data.get('item_id', ''),
                'SessionId': event_data.get('session_id', ''),
                'RecommendationId': event_data.get('recommendation_id', ''),
                'Properties': json.dumps(event_data.get('properties', {})),
                'EventValue': calculate_event_value(event_data['event_type']),
                'ExpirationTime': ttl_timestamp,  # TTL for automatic cleanup
                'Source': event_data.get('source', 'api'),
                'UserAgent': event_data.get('user_agent', ''),
                'IPAddress': event_data.get('ip_address', ''),
                'DeviceType': event_data.get('device_type', 'unknown')
            }
        )
        return True
        
    except Exception as e:
        print(f"Error storing event analytics: {str(e)}")
        return False

def send_to_personalize(user_id, session_id, event_type, item_id, properties):
    """Send event to Amazon Personalize for real-time training"""
    try:
        event_tracker_arn = os.environ.get('EVENT_TRACKER_ARN')
        if not event_tracker_arn:
            print("No EVENT_TRACKER_ARN configured")
            return False
        
        # Prepare event for Personalize
        personalize_event = {
            'userId': user_id,
            'sessionId': session_id,
            'eventType': event_type,
            'sentAt': datetime.now().timestamp()
        }
        
        if item_id:
            personalize_event['itemId'] = item_id
        
        # Add properties if provided and valid
        if properties and isinstance(properties, dict):
            # Convert properties to string format as required by Personalize
            personalize_event['properties'] = json.dumps(properties)
        
        # Extract tracking ID from ARN
        tracking_id = event_tracker_arn.split('/')[-1]
        
        # Send to Personalize
        response = personalize_events.put_events(
            trackingId=tracking_id,
            userId=user_id,
            sessionId=session_id,
            eventList=[personalize_event]
        )
        
        print(f"Successfully sent event to Personalize: {response}")
        return True
        
    except Exception as e:
        print(f"Error sending to Personalize: {str(e)}")
        return False

def calculate_event_value(event_type):
    """Calculate numerical value for different event types"""
    event_values = {
        'view': 0.1,
        'like': 0.3,
        'share': 0.4,
        'add_to_cart': 0.5,
        'add_to_wishlist': 0.6,
        'purchase': 1.0,
        'rate': 0.7,
        'review': 0.8,
        'download': 0.9,
        'subscribe': 1.0
    }
    
    return event_values.get(event_type.lower(), 0.1)

def validate_event_data(event_data):
    """Validate event data before processing"""
    required_fields = ['user_id', 'event_type']
    
    for field in required_fields:
        if not event_data.get(field):
            raise ValueError(f"Missing required field: {field}")
    
    # Validate event type
    valid_event_types = [
        'view', 'purchase', 'add_to_cart', 'add_to_wishlist', 
        'like', 'dislike', 'share', 'rate', 'review', 
        'download', 'subscribe', 'unsubscribe'
    ]
    
    if event_data['event_type'].lower() not in valid_event_types:
        print(f"Warning: Unknown event type {event_data['event_type']}")
    
    # Validate user_id format
    if len(event_data['user_id']) > 256:
        raise ValueError("user_id too long (max 256 characters)")
    
    return True

def enrich_event_data(event_data, context):
    """Enrich event data with additional context information"""
    try:
        # Add timestamp if not provided
        if 'timestamp' not in event_data:
            event_data['timestamp'] = datetime.now().isoformat()
        
        # Extract source information from API Gateway context
        if context and hasattr(context, 'identity'):
            event_data['source_ip'] = getattr(context.identity, 'sourceIp', '')
            event_data['user_agent'] = getattr(context.identity, 'userAgent', '')
        
        # Add session tracking
        if 'session_id' not in event_data:
            event_data['session_id'] = event_data['user_id']
        
        return event_data
        
    except Exception as e:
        print(f"Error enriching event data: {str(e)}")
        return event_data

def batch_process_events(events_list):
    """Process multiple events in batch for efficiency"""
    results = []
    
    for event_data in events_list:
        try:
            # Validate event
            validate_event_data(event_data)
            
            # Store in analytics
            analytics_success = store_event_analytics(event_data)
            
            # Send to Personalize if applicable
            personalize_success = False
            if event_data.get('item_id'):
                personalize_success = send_to_personalize(
                    event_data['user_id'],
                    event_data.get('session_id', event_data['user_id']),
                    event_data['event_type'],
                    event_data['item_id'],
                    event_data.get('properties', {})
                )
            
            results.append({
                'event': event_data,
                'analytics_stored': analytics_success,
                'personalize_sent': personalize_success,
                'status': 'success'
            })
            
        except Exception as e:
            results.append({
                'event': event_data,
                'error': str(e),
                'status': 'failed'
            })
    
    return results