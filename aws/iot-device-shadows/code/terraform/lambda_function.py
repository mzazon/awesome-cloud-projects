"""
Lambda function to process IoT Device Shadow updates and store state history.

This function is triggered by IoT Rules Engine when device shadows are updated.
It processes the shadow update event and stores the state change in DynamoDB
for historical tracking and analytics.

Environment Variables:
    TABLE_NAME: Name of the DynamoDB table to store state history
"""

import json
import boto3
import time
import os
import logging
from decimal import Decimal
from typing import Dict, Any, Union

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize DynamoDB resource
dynamodb = boto3.resource('dynamodb')


def convert_floats_to_decimal(obj: Any) -> Any:
    """
    Convert float values to Decimal for DynamoDB compatibility.
    
    DynamoDB requires numeric values to be Decimal type, not float.
    This function recursively converts all float values in nested
    dictionaries and lists to Decimal objects.
    
    Args:
        obj: Object to convert (can be dict, list, float, or other types)
        
    Returns:
        Object with all float values converted to Decimal
    """
    if isinstance(obj, float):
        return Decimal(str(obj))
    elif isinstance(obj, dict):
        return {k: convert_floats_to_decimal(v) for k, v in obj.items()}
    elif isinstance(obj, list):
        return [convert_floats_to_decimal(v) for v in obj]
    return obj


def extract_thing_name_from_topic(topic: str) -> str:
    """
    Extract thing name from IoT shadow topic.
    
    Args:
        topic: IoT shadow topic (e.g., $aws/things/device123/shadow/update/accepted)
        
    Returns:
        Thing name extracted from the topic
        
    Raises:
        ValueError: If topic format is invalid
    """
    try:
        # Topic format: $aws/things/{thingName}/shadow/update/accepted
        parts = topic.split('/')
        if len(parts) >= 4 and parts[0] == '$aws' and parts[1] == 'things':
            return parts[2]
        else:
            raise ValueError(f"Invalid shadow topic format: {topic}")
    except Exception as e:
        logger.error(f"Failed to extract thing name from topic {topic}: {str(e)}")
        raise


def validate_shadow_event(event: Dict[str, Any]) -> Dict[str, Any]:
    """
    Validate and normalize IoT shadow update event.
    
    Args:
        event: IoT shadow update event from Rules Engine
        
    Returns:
        Validated and normalized event data
        
    Raises:
        ValueError: If event structure is invalid
    """
    # Check if event has required fields
    if 'state' not in event:
        raise ValueError("Event missing 'state' field")
    
    # Extract thing name from topic if available, otherwise from thingName field
    thing_name = None
    if 'thingName' in event:
        thing_name = event['thingName']
    elif 'topic' in event:
        thing_name = extract_thing_name_from_topic(event['topic'])
    else:
        raise ValueError("Event missing 'thingName' or 'topic' field")
    
    return {
        'thing_name': thing_name,
        'state': event['state'],
        'metadata': event.get('metadata', {}),
        'timestamp': event.get('timestamp', int(time.time())),
        'version': event.get('version', 1)
    }


def store_state_history(table_name: str, thing_name: str, 
                       shadow_data: Dict[str, Any], 
                       metadata: Dict[str, Any] = None,
                       event_version: int = 1) -> None:
    """
    Store device shadow state change in DynamoDB.
    
    Args:
        table_name: Name of DynamoDB table
        thing_name: Name of the IoT Thing
        shadow_data: Shadow state data
        metadata: Optional metadata about the shadow update
        event_version: Version of the shadow update event
        
    Raises:
        Exception: If DynamoDB operation fails
    """
    table = dynamodb.Table(table_name)
    
    # Prepare item for DynamoDB
    item = {
        'ThingName': thing_name,
        'Timestamp': int(time.time()),
        'ShadowState': convert_floats_to_decimal(shadow_data),
        'EventType': 'shadow_update',
        'Version': event_version
    }
    
    # Add metadata if provided
    if metadata:
        item['Metadata'] = convert_floats_to_decimal(metadata)
    
    # Add derived fields for analytics
    if 'reported' in shadow_data:
        reported_state = shadow_data['reported']
        if 'temperature' in reported_state:
            item['CurrentTemperature'] = Decimal(str(reported_state['temperature']))
        if 'target_temperature' in reported_state:
            item['TargetTemperature'] = Decimal(str(reported_state['target_temperature']))
        if 'hvac_mode' in reported_state:
            item['HvacMode'] = reported_state['hvac_mode']
        if 'connectivity' in reported_state:
            item['DeviceStatus'] = reported_state['connectivity']
    
    try:
        # Store item in DynamoDB
        table.put_item(Item=item)
        logger.info(f"Successfully stored shadow update for {thing_name}")
        
    except Exception as e:
        logger.error(f"Failed to store shadow update in DynamoDB: {str(e)}")
        raise


def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Main Lambda handler for processing IoT Device Shadow updates.
    
    This function is triggered by IoT Rules Engine when device shadows
    are updated. It validates the event, processes the shadow data,
    and stores the state change in DynamoDB for historical tracking.
    
    Args:
        event: IoT shadow update event from Rules Engine
        context: Lambda context object
        
    Returns:
        Response dictionary with status and message
    """
    try:
        # Log incoming event for debugging
        logger.info(f"Processing shadow update event: {json.dumps(event, default=str)}")
        
        # Get table name from environment variable
        table_name = os.environ.get('TABLE_NAME')
        if not table_name:
            raise ValueError("TABLE_NAME environment variable not set")
        
        # Validate and normalize event
        validated_event = validate_shadow_event(event)
        
        # Store state change in DynamoDB
        store_state_history(
            table_name=table_name,
            thing_name=validated_event['thing_name'],
            shadow_data=validated_event['state'],
            metadata=validated_event['metadata'],
            event_version=validated_event['version']
        )
        
        # Log successful processing
        logger.info(f"Successfully processed shadow update for {validated_event['thing_name']}")
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Successfully processed shadow update',
                'thingName': validated_event['thing_name'],
                'timestamp': validated_event['timestamp']
            })
        }
        
    except ValueError as e:
        # Handle validation errors
        logger.error(f"Validation error: {str(e)}")
        return {
            'statusCode': 400,
            'body': json.dumps({
                'error': 'Validation error',
                'message': str(e)
            })
        }
        
    except Exception as e:
        # Handle unexpected errors
        logger.error(f"Unexpected error processing shadow update: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': 'Internal error',
                'message': 'Failed to process shadow update'
            })
        }


# Example shadow update event for testing:
# {
#   "thingName": "smart-thermostat-abc123",
#   "state": {
#     "reported": {
#       "temperature": 22.5,
#       "humidity": 45,
#       "hvac_mode": "heat",
#       "target_temperature": 23.0,
#       "firmware_version": "1.2.3",
#       "connectivity": "online"
#     },
#     "desired": {
#       "target_temperature": 24.0,
#       "hvac_mode": "auto"
#     }
#   },
#   "metadata": {
#     "reported": {
#       "temperature": {"timestamp": 1234567890},
#       "hvac_mode": {"timestamp": 1234567890}
#     }
#   },
#   "version": 1,
#   "timestamp": 1234567890
# }