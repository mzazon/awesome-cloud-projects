"""
Lambda function for processing IoT sensor data from smart city sensors.
Processes incoming IoT messages, validates data, and stores in DynamoDB.
"""
import json
import boto3
import uuid
import logging
from datetime import datetime
from decimal import Decimal
import os

# Configure logging
logger = logging.getLogger()
logger.setLevel(os.environ.get('LOG_LEVEL', 'INFO'))

# Initialize AWS clients
dynamodb = boto3.resource('dynamodb')
table = dynamodb.Table('${table_name}')

def lambda_handler(event, context):
    """
    Main Lambda handler for processing IoT sensor data.
    
    Args:
        event: IoT message event data
        context: Lambda execution context
        
    Returns:
        dict: Response with processing status
    """
    try:
        logger.info(f"Processing event: {json.dumps(event, default=str)}")
        
        # Handle different event sources (IoT Rule, direct invoke, etc.)
        if 'Records' in event:
            # Process multiple records (from SQS, SNS, etc.)
            processed_count = 0
            for record in event['Records']:
                if process_sensor_record(record, context):
                    processed_count += 1
        else:
            # Direct invocation or single message
            if process_sensor_data(event, context):
                processed_count = 1
            else:
                processed_count = 0
        
        logger.info(f"Successfully processed {processed_count} sensor records")
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': f'Successfully processed {processed_count} sensor records',
                'timestamp': datetime.utcnow().isoformat()
            })
        }
        
    except Exception as e:
        logger.error(f"Error processing sensor data: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': str(e),
                'message': 'Failed to process sensor data',
                'timestamp': datetime.utcnow().isoformat()
            })
        }

def process_sensor_record(record, context):
    """
    Process a single sensor record from event sources.
    
    Args:
        record: Individual record from event
        context: Lambda execution context
        
    Returns:
        bool: Success status
    """
    try:
        # Extract message body based on source
        if 'body' in record:
            message = json.loads(record['body'])
        else:
            message = record
            
        return process_sensor_data(message, context)
        
    except Exception as e:
        logger.error(f"Error processing sensor record: {str(e)}")
        return False

def process_sensor_data(sensor_message, context):
    """
    Process and validate sensor data message.
    
    Args:
        sensor_message: Raw sensor data message
        context: Lambda execution context
        
    Returns:
        bool: Success status
    """
    try:
        # Validate required fields
        required_fields = ['sensor_id', 'sensor_type', 'data']
        for field in required_fields:
            if field not in sensor_message:
                logger.warning(f"Missing required field: {field}")
                return False
        
        # Extract sensor information
        sensor_id = sensor_message.get('sensor_id')
        sensor_type = sensor_message.get('sensor_type')
        sensor_data = sensor_message.get('data', {})
        location = sensor_message.get('location', {})
        
        # Generate timestamp if not provided
        timestamp = sensor_message.get('timestamp')
        if not timestamp:
            timestamp = datetime.utcnow().isoformat()
        
        # Create DynamoDB item
        item = {
            'sensor_id': sensor_id,
            'timestamp': timestamp,
            'sensor_type': sensor_type,
            'data': convert_floats_to_decimal(sensor_data),
            'location': convert_floats_to_decimal(location),
            'ingestion_timestamp': datetime.utcnow().isoformat(),
            'processed_by': context.function_name,
            'processing_id': str(uuid.uuid4())
        }
        
        # Add optional fields
        if 'quality_score' in sensor_message:
            item['quality_score'] = Decimal(str(sensor_message['quality_score']))
        
        if 'battery_level' in sensor_message:
            item['battery_level'] = Decimal(str(sensor_message['battery_level']))
            
        if 'firmware_version' in sensor_message:
            item['firmware_version'] = sensor_message['firmware_version']
        
        # Store in DynamoDB
        table.put_item(Item=item)
        
        # Log successful processing
        logger.info(f"Stored sensor data for {sensor_id} of type {sensor_type}")
        
        # Perform data validation and quality checks
        perform_data_quality_checks(item)
        
        return True
        
    except Exception as e:
        logger.error(f"Error processing sensor data: {str(e)}")
        return False

def convert_floats_to_decimal(obj):
    """
    Convert float values to Decimal for DynamoDB compatibility.
    
    Args:
        obj: Object containing potential float values
        
    Returns:
        obj: Object with floats converted to Decimal
    """
    if isinstance(obj, float):
        return Decimal(str(obj))
    elif isinstance(obj, dict):
        return {k: convert_floats_to_decimal(v) for k, v in obj.items()}
    elif isinstance(obj, list):
        return [convert_floats_to_decimal(item) for item in obj]
    else:
        return obj

def perform_data_quality_checks(sensor_item):
    """
    Perform data quality checks on sensor data.
    
    Args:
        sensor_item: Processed sensor item
    """
    try:
        sensor_type = sensor_item.get('sensor_type')
        sensor_data = sensor_item.get('data', {})
        
        # Type-specific validation
        if sensor_type == 'traffic':
            validate_traffic_data(sensor_data)
        elif sensor_type == 'weather':
            validate_weather_data(sensor_data)
        elif sensor_type == 'air_quality':
            validate_air_quality_data(sensor_data)
        elif sensor_type == 'parking':
            validate_parking_data(sensor_data)
        
        logger.debug(f"Data quality checks passed for sensor type: {sensor_type}")
        
    except Exception as e:
        logger.warning(f"Data quality check failed: {str(e)}")

def validate_traffic_data(data):
    """Validate traffic sensor data."""
    if 'vehicle_count' in data:
        count = float(data['vehicle_count'])
        if count < 0 or count > 1000:
            raise ValueError(f"Invalid vehicle count: {count}")
    
    if 'average_speed' in data:
        speed = float(data['average_speed'])
        if speed < 0 or speed > 200:  # km/h
            raise ValueError(f"Invalid average speed: {speed}")

def validate_weather_data(data):
    """Validate weather sensor data."""
    if 'temperature' in data:
        temp = float(data['temperature'])
        if temp < -50 or temp > 60:  # Celsius
            raise ValueError(f"Invalid temperature: {temp}")
    
    if 'humidity' in data:
        humidity = float(data['humidity'])
        if humidity < 0 or humidity > 100:
            raise ValueError(f"Invalid humidity: {humidity}")

def validate_air_quality_data(data):
    """Validate air quality sensor data."""
    if 'pm2_5' in data:
        pm25 = float(data['pm2_5'])
        if pm25 < 0 or pm25 > 500:  # μg/m³
            raise ValueError(f"Invalid PM2.5 level: {pm25}")
    
    if 'co2' in data:
        co2 = float(data['co2'])
        if co2 < 300 or co2 > 5000:  # ppm
            raise ValueError(f"Invalid CO2 level: {co2}")

def validate_parking_data(data):
    """Validate parking sensor data."""
    if 'occupied_spaces' in data:
        occupied = float(data['occupied_spaces'])
        total = float(data.get('total_spaces', occupied))
        if occupied < 0 or occupied > total:
            raise ValueError(f"Invalid parking occupancy: {occupied}/{total}")