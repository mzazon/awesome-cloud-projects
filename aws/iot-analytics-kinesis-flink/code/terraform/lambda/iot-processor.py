import json
import boto3
import base64
from datetime import datetime
import os

# Initialize AWS clients
s3 = boto3.client('s3')
sns = boto3.client('sns')

def lambda_handler(event, context):
    """
    Lambda function to process IoT sensor data from Kinesis stream.
    
    This function:
    1. Processes incoming IoT sensor data from Kinesis
    2. Stores raw data in S3
    3. Performs anomaly detection
    4. Sends alerts via SNS if anomalies are detected
    """
    bucket_name = os.environ['S3_BUCKET_NAME']
    topic_arn = os.environ['SNS_TOPIC_ARN']
    
    processed_records = []
    
    try:
        for record in event['Records']:
            # Decode Kinesis data
            payload = base64.b64decode(record['kinesis']['data']).decode('utf-8')
            data = json.loads(payload)
            
            # Process the IoT data
            processed_data = process_iot_data(data)
            processed_records.append(processed_data)
            
            # Store raw data in S3 with time-based partitioning
            timestamp = datetime.now().strftime('%Y/%m/%d/%H')
            key = f"raw-data/{timestamp}/{record['kinesis']['sequenceNumber']}.json"
            
            s3.put_object(
                Bucket=bucket_name,
                Key=key,
                Body=json.dumps(data),
                ContentType='application/json'
            )
            
            # Check for anomalies and send alerts
            if is_anomaly(processed_data):
                send_alert(processed_data, topic_arn)
        
        return {
            'statusCode': 200,
            'body': json.dumps(f'Successfully processed {len(processed_records)} records')
        }
        
    except Exception as e:
        print(f"Error processing records: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps(f'Error processing records: {str(e)}')
        }

def process_iot_data(data):
    """
    Process IoT sensor data and add metadata.
    
    Args:
        data: Raw IoT sensor data
        
    Returns:
        dict: Processed IoT data with additional metadata
    """
    return {
        'device_id': data.get('device_id'),
        'timestamp': data.get('timestamp'),
        'sensor_type': data.get('sensor_type'),
        'value': data.get('value'),
        'unit': data.get('unit'),
        'location': data.get('location'),
        'processed_at': datetime.now().isoformat()
    }

def is_anomaly(data):
    """
    Simple anomaly detection logic based on configurable thresholds.
    
    Args:
        data: Processed IoT sensor data
        
    Returns:
        bool: True if anomaly detected, False otherwise
    """
    sensor_type = data.get('sensor_type')
    value = data.get('value', 0)
    
    # Get thresholds from environment variables
    temperature_threshold = float(os.environ.get('TEMPERATURE_THRESHOLD', '${temperature_threshold}'))
    pressure_threshold = float(os.environ.get('PRESSURE_THRESHOLD', '${pressure_threshold}'))
    vibration_threshold = float(os.environ.get('VIBRATION_THRESHOLD', '${vibration_threshold}'))
    flow_threshold = float(os.environ.get('FLOW_THRESHOLD', '${flow_threshold}'))
    
    # Check thresholds based on sensor type
    if sensor_type == 'temperature' and value > temperature_threshold:
        return True
    elif sensor_type == 'pressure' and value > pressure_threshold:
        return True
    elif sensor_type == 'vibration' and value > vibration_threshold:
        return True
    elif sensor_type == 'flow' and value > flow_threshold:
        return True
    
    return False

def send_alert(data, topic_arn):
    """
    Send alert via SNS for anomaly detection.
    
    Args:
        data: Processed IoT data containing anomaly
        topic_arn: SNS topic ARN for sending alerts
    """
    try:
        device_id = data.get('device_id', 'unknown')
        sensor_type = data.get('sensor_type', 'unknown')
        value = data.get('value', 0)
        unit = data.get('unit', '')
        location = data.get('location', 'unknown')
        
        message = f"""
ALERT: IoT Sensor Anomaly Detected

Device ID: {device_id}
Sensor Type: {sensor_type}
Location: {location}
Value: {value} {unit}
Timestamp: {data.get('timestamp', 'unknown')}

Please investigate immediately.
        """.strip()
        
        sns.publish(
            TopicArn=topic_arn,
            Message=message,
            Subject=f"IoT Sensor Anomaly Alert - {sensor_type.title()} Sensor {device_id}"
        )
        
        print(f"Alert sent for device {device_id}: {sensor_type} value {value} {unit}")
        
    except Exception as e:
        print(f"Error sending alert: {str(e)}")
        # Don't fail the entire function if alert fails
        pass