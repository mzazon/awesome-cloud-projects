"""
Lambda function for processing DynamoDB stream events from sensor data table.
Triggers simulation updates when sensor data changes occur.
"""
import json
import boto3
import logging
from datetime import datetime
import os

# Configure logging
logger = logging.getLogger()
logger.setLevel(os.environ.get('LOG_LEVEL', 'INFO'))

# Initialize AWS clients
s3 = boto3.client('s3')

def lambda_handler(event, context):
    """
    Main Lambda handler for processing DynamoDB stream events.
    
    Args:
        event: DynamoDB stream event data
        context: Lambda execution context
        
    Returns:
        dict: Response with processing status
    """
    try:
        logger.info(f"Processing DynamoDB stream event with {len(event['Records'])} records")
        
        processed_count = 0
        simulation_updates = []
        
        # Process each stream record
        for record in event['Records']:
            if process_stream_record(record, context):
                processed_count += 1
                
                # Extract simulation update information
                update_info = extract_simulation_update(record)
                if update_info:
                    simulation_updates.append(update_info)
        
        # Batch simulation updates if any
        if simulation_updates:
            batch_simulation_updates(simulation_updates, context)
        
        logger.info(f"Successfully processed {processed_count} stream records")
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': f'Successfully processed {processed_count} stream records',
                'simulation_updates': len(simulation_updates),
                'timestamp': datetime.utcnow().isoformat()
            })
        }
        
    except Exception as e:
        logger.error(f"Error processing stream events: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': str(e),
                'message': 'Failed to process stream events',
                'timestamp': datetime.utcnow().isoformat()
            })
        }

def process_stream_record(record, context):
    """
    Process a single DynamoDB stream record.
    
    Args:
        record: Individual DynamoDB stream record
        context: Lambda execution context
        
    Returns:
        bool: Success status
    """
    try:
        event_name = record['eventName']
        logger.debug(f"Processing stream record: {event_name}")
        
        # Only process INSERT and MODIFY events
        if event_name not in ['INSERT', 'MODIFY']:
            logger.debug(f"Ignoring event type: {event_name}")
            return True
        
        # Extract record data
        if event_name == 'INSERT':
            sensor_data = record['dynamodb']['NewImage']
        elif event_name == 'MODIFY':
            sensor_data = record['dynamodb']['NewImage']
            old_data = record['dynamodb'].get('OldImage', {})
            
            # Check if this is a significant change worth simulation update
            if not is_significant_change(old_data, sensor_data):
                logger.debug("Change not significant enough for simulation update")
                return True
        
        # Extract key information
        sensor_id = sensor_data.get('sensor_id', {}).get('S', 'unknown')
        sensor_type = sensor_data.get('sensor_type', {}).get('S', 'unknown')
        timestamp = sensor_data.get('timestamp', {}).get('S', datetime.utcnow().isoformat())
        
        logger.info(f"Processed stream record for sensor {sensor_id} of type {sensor_type}")
        
        return True
        
    except Exception as e:
        logger.error(f"Error processing stream record: {str(e)}")
        return False

def extract_simulation_update(record):
    """
    Extract simulation update information from stream record.
    
    Args:
        record: DynamoDB stream record
        
    Returns:
        dict: Simulation update information or None
    """
    try:
        event_name = record['eventName']
        
        if event_name not in ['INSERT', 'MODIFY']:
            return None
            
        sensor_data = record['dynamodb']['NewImage']
        
        # Extract relevant fields for simulation
        update_info = {
            'event_type': event_name,
            'sensor_id': sensor_data.get('sensor_id', {}).get('S'),
            'sensor_type': sensor_data.get('sensor_type', {}).get('S'),
            'timestamp': sensor_data.get('timestamp', {}).get('S'),
            'location': extract_dynamodb_item(sensor_data.get('location', {})),
            'data': extract_dynamodb_item(sensor_data.get('data', {}))
        }
        
        # Only return if we have essential information
        if update_info['sensor_id'] and update_info['sensor_type']:
            return update_info
            
        return None
        
    except Exception as e:
        logger.error(f"Error extracting simulation update: {str(e)}")
        return None

def extract_dynamodb_item(dynamodb_item):
    """
    Extract value from DynamoDB item format.
    
    Args:
        dynamodb_item: DynamoDB item in stream format
        
    Returns:
        dict: Extracted values
    """
    if not dynamodb_item or not isinstance(dynamodb_item, dict):
        return {}
    
    result = {}
    
    for key, value in dynamodb_item.items():
        if isinstance(value, dict):
            if 'S' in value:  # String
                result[key] = value['S']
            elif 'N' in value:  # Number
                try:
                    result[key] = float(value['N'])
                except ValueError:
                    result[key] = value['N']
            elif 'BOOL' in value:  # Boolean
                result[key] = value['BOOL']
            elif 'M' in value:  # Map
                result[key] = extract_dynamodb_item(value['M'])
            elif 'L' in value:  # List
                result[key] = [extract_dynamodb_item(item) if isinstance(item, dict) else item for item in value['L']]
    
    return result

def is_significant_change(old_data, new_data):
    """
    Determine if the change is significant enough to trigger simulation update.
    
    Args:
        old_data: Previous sensor data
        new_data: New sensor data
        
    Returns:
        bool: True if change is significant
    """
    try:
        # Get sensor type to determine significance criteria
        sensor_type = new_data.get('sensor_type', {}).get('S', 'unknown')
        
        # Extract data sections
        old_sensor_data = extract_dynamodb_item(old_data.get('data', {}))
        new_sensor_data = extract_dynamodb_item(new_data.get('data', {}))
        
        if sensor_type == 'traffic':
            return is_significant_traffic_change(old_sensor_data, new_sensor_data)
        elif sensor_type == 'weather':
            return is_significant_weather_change(old_sensor_data, new_sensor_data)
        elif sensor_type == 'parking':
            return is_significant_parking_change(old_sensor_data, new_sensor_data)
        else:
            # For unknown types, consider any change significant
            return True
            
    except Exception as e:
        logger.error(f"Error checking significance of change: {str(e)}")
        return True  # Default to significant to be safe

def is_significant_traffic_change(old_data, new_data):
    """Check if traffic data change is significant."""
    # Vehicle count change of more than 5
    old_count = old_data.get('vehicle_count', 0)
    new_count = new_data.get('vehicle_count', 0)
    if abs(new_count - old_count) >= 5:
        return True
    
    # Speed change of more than 10 km/h
    old_speed = old_data.get('average_speed', 0)
    new_speed = new_data.get('average_speed', 0)
    if abs(new_speed - old_speed) >= 10:
        return True
    
    return False

def is_significant_weather_change(old_data, new_data):
    """Check if weather data change is significant."""
    # Temperature change of more than 2°C
    old_temp = old_data.get('temperature', 0)
    new_temp = new_data.get('temperature', 0)
    if abs(new_temp - old_temp) >= 2:
        return True
    
    # Humidity change of more than 10%
    old_humidity = old_data.get('humidity', 0)
    new_humidity = new_data.get('humidity', 0)
    if abs(new_humidity - old_humidity) >= 10:
        return True
    
    return False

def is_significant_parking_change(old_data, new_data):
    """Check if parking data change is significant."""
    # Any change in occupied spaces is significant
    old_occupied = old_data.get('occupied_spaces', 0)
    new_occupied = new_data.get('occupied_spaces', 0)
    return old_occupied != new_occupied

def batch_simulation_updates(updates, context):
    """
    Batch and send simulation updates.
    
    Args:
        updates: List of simulation updates
        context: Lambda execution context
    """
    try:
        logger.info(f"Batching {len(updates)} simulation updates")
        
        # Group updates by sensor type for more efficient processing
        grouped_updates = {}
        for update in updates:
            sensor_type = update['sensor_type']
            if sensor_type not in grouped_updates:
                grouped_updates[sensor_type] = []
            grouped_updates[sensor_type].append(update)
        
        # Process each sensor type group
        for sensor_type, type_updates in grouped_updates.items():
            process_sensor_type_updates(sensor_type, type_updates, context)
        
        logger.info("Successfully processed all simulation updates")
        
    except Exception as e:
        logger.error(f"Error batching simulation updates: {str(e)}")

def process_sensor_type_updates(sensor_type, updates, context):
    """
    Process simulation updates for a specific sensor type.
    
    Args:
        sensor_type: Type of sensor (traffic, weather, etc.)
        updates: List of updates for this sensor type
        context: Lambda execution context
    """
    try:
        logger.info(f"Processing {len(updates)} updates for sensor type: {sensor_type}")
        
        # Create simulation input based on sensor type
        if sensor_type == 'traffic':
            simulation_input = create_traffic_simulation_input(updates)
        elif sensor_type == 'weather':
            simulation_input = create_weather_simulation_input(updates)
        elif sensor_type == 'parking':
            simulation_input = create_parking_simulation_input(updates)
        else:
            simulation_input = create_generic_simulation_input(updates)
        
        # TODO: Send to actual simulation service
        # For now, log the simulation input
        logger.info(f"Simulation input for {sensor_type}: {json.dumps(simulation_input, default=str)}")
        
        # In a real implementation, you would:
        # 1. Send to SimSpace Weaver (until May 2026)
        # 2. Send to alternative simulation service
        # 3. Store in simulation queue for batch processing
        
    except Exception as e:
        logger.error(f"Error processing {sensor_type} updates: {str(e)}")

def create_traffic_simulation_input(updates):
    """Create simulation input for traffic updates."""
    return {
        'simulation_type': 'traffic',
        'updates': updates,
        'aggregations': {
            'total_sensors': len(set(u['sensor_id'] for u in updates)),
            'total_vehicles': sum(u.get('data', {}).get('vehicle_count', 0) for u in updates),
            'average_speed': sum(u.get('data', {}).get('average_speed', 0) for u in updates) / len(updates) if updates else 0
        },
        'timestamp': datetime.utcnow().isoformat()
    }

def create_weather_simulation_input(updates):
    """Create simulation input for weather updates."""
    return {
        'simulation_type': 'weather',
        'updates': updates,
        'aggregations': {
            'total_sensors': len(set(u['sensor_id'] for u in updates)),
            'average_temperature': sum(u.get('data', {}).get('temperature', 0) for u in updates) / len(updates) if updates else 0,
            'average_humidity': sum(u.get('data', {}).get('humidity', 0) for u in updates) / len(updates) if updates else 0
        },
        'timestamp': datetime.utcnow().isoformat()
    }

def create_parking_simulation_input(updates):
    """Create simulation input for parking updates."""
    return {
        'simulation_type': 'parking',
        'updates': updates,
        'aggregations': {
            'total_sensors': len(set(u['sensor_id'] for u in updates)),
            'total_occupied': sum(u.get('data', {}).get('occupied_spaces', 0) for u in updates),
            'total_available': sum(u.get('data', {}).get('available_spaces', 0) for u in updates)
        },
        'timestamp': datetime.utcnow().isoformat()
    }

def create_generic_simulation_input(updates):
    """Create generic simulation input for unknown sensor types."""
    return {
        'simulation_type': 'generic',
        'updates': updates,
        'aggregations': {
            'total_sensors': len(set(u['sensor_id'] for u in updates)),
            'sensor_types': list(set(u['sensor_type'] for u in updates))
        },
        'timestamp': datetime.utcnow().isoformat()
    }