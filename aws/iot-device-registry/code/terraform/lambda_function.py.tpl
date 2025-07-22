import json
import boto3
import logging
import os
from datetime import datetime

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Environment variables
TEMPERATURE_THRESHOLD = float(os.environ.get('TEMPERATURE_THRESHOLD', '${temperature_threshold}'))
ENVIRONMENT = os.environ.get('ENVIRONMENT', 'dev')

def lambda_handler(event, context):
    """
    Lambda function to process IoT sensor data from AWS IoT Core.
    
    This function receives temperature sensor data, validates it,
    and triggers alerts for high temperature readings.
    
    Args:
        event: IoT message containing sensor data
        context: Lambda runtime context
        
    Returns:
        dict: Processing status and results
    """
    try:
        logger.info(f"Received IoT data: {json.dumps(event)}")
        
        # Extract device data from IoT message
        device_name = event.get('device', 'unknown')
        temperature = event.get('temperature', 0)
        humidity = event.get('humidity', 0)
        timestamp = event.get('timestamp', datetime.utcnow().isoformat())
        
        # Validate temperature data
        if not isinstance(temperature, (int, float)):
            logger.error(f"Invalid temperature data type: {type(temperature)}")
            raise ValueError("Temperature must be a numeric value")
        
        # Process temperature data and check thresholds
        if temperature > TEMPERATURE_THRESHOLD:
            logger.warning(f"🌡️ High temperature alert: {temperature}°C from device {device_name}")
            
            # In a production environment, you could:
            # - Send SNS notification
            # - Write to DynamoDB for historical tracking
            # - Trigger automated cooling systems
            # - Update device shadow with alert status
            
            alert_data = {
                'alert_type': 'high_temperature',
                'device': device_name,
                'temperature': temperature,
                'threshold': TEMPERATURE_THRESHOLD,
                'timestamp': timestamp,
                'severity': 'warning' if temperature < TEMPERATURE_THRESHOLD + 10 else 'critical'
            }
            
            logger.info(f"Alert data: {json.dumps(alert_data)}")
        
        elif temperature < -10:
            logger.warning(f"🧊 Low temperature alert: {temperature}°C from device {device_name}")
        
        else:
            logger.info(f"✅ Normal temperature reading: {temperature}°C from device {device_name}")
        
        # Log additional sensor data
        if humidity > 0:
            logger.info(f"Humidity reading: {humidity}% from device {device_name}")
        
        # Prepare response
        response = {
            'statusCode': 200,
            'body': {
                'message': 'IoT data processed successfully',
                'device': device_name,
                'temperature': temperature,
                'humidity': humidity,
                'timestamp': timestamp,
                'environment': ENVIRONMENT,
                'threshold_exceeded': temperature > TEMPERATURE_THRESHOLD
            }
        }
        
        logger.info(f"Processing completed for device: {device_name}")
        return response
        
    except Exception as e:
        logger.error(f"Error processing IoT data: {str(e)}")
        logger.error(f"Event data: {json.dumps(event)}")
        
        # Return error response
        return {
            'statusCode': 500,
            'body': {
                'message': 'Error processing IoT data',
                'error': str(e),
                'device': event.get('device', 'unknown'),
                'timestamp': datetime.utcnow().isoformat()
            }
        }

def validate_sensor_data(data):
    """
    Validate incoming sensor data structure and values.
    
    Args:
        data: Dictionary containing sensor readings
        
    Returns:
        bool: True if data is valid, False otherwise
    """
    required_fields = ['device', 'temperature']
    
    for field in required_fields:
        if field not in data:
            logger.error(f"Missing required field: {field}")
            return False
    
    # Validate temperature range (assuming typical sensor ranges)
    temperature = data.get('temperature', 0)
    if not isinstance(temperature, (int, float)) or temperature < -50 or temperature > 150:
        logger.error(f"Temperature out of valid range: {temperature}")
        return False
    
    return True