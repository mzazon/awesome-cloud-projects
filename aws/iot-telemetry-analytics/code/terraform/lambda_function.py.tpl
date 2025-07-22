import json
import boto3
import time
import base64
import logging
from datetime import datetime
from typing import Dict, Any, List

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize Timestream client
timestream = boto3.client('timestream-write')

def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    AWS Lambda function to process IoT sensor data from Kinesis and write to Timestream.
    
    Args:
        event: Lambda event containing Kinesis records
        context: Lambda context object
        
    Returns:
        Response dictionary with status code and processing results
    """
    
    database_name = '${timestream_database}'
    table_name = '${timestream_table}'
    device_location = '${device_location}'
    
    # Track processing statistics
    processed_records = 0
    failed_records = 0
    timestream_records = []
    
    try:
        # Process each Kinesis record
        for record in event['Records']:
            try:
                # Decode Kinesis data
                kinesis_data = record['kinesis']['data']
                decoded_data = base64.b64decode(kinesis_data).decode('utf-8')
                sensor_data = json.loads(decoded_data)
                
                logger.info(f"Processing sensor data: {sensor_data}")
                
                # Validate required fields
                if not all(key in sensor_data for key in ['deviceId', 'temperature', 'timestamp']):
                    logger.warning(f"Missing required fields in sensor data: {sensor_data}")
                    failed_records += 1
                    continue
                
                # Filter temperature readings (same logic as IoT Analytics pipeline)
                temperature = float(sensor_data.get('temperature', 0))
                if temperature <= 0 or temperature >= 100:
                    logger.warning(f"Temperature out of range: {temperature}")
                    failed_records += 1
                    continue
                
                # Parse timestamp or use current time
                try:
                    timestamp = sensor_data.get('timestamp')
                    if timestamp:
                        # Convert ISO timestamp to milliseconds
                        dt = datetime.fromisoformat(timestamp.replace('Z', '+00:00'))
                        timestamp_ms = int(dt.timestamp() * 1000)
                    else:
                        timestamp_ms = int(time.time() * 1000)
                except (ValueError, TypeError):
                    logger.warning(f"Invalid timestamp format: {timestamp}")
                    timestamp_ms = int(time.time() * 1000)
                
                # Create temperature measurement record
                temperature_record = {
                    'Time': str(timestamp_ms),
                    'TimeUnit': 'MILLISECONDS',
                    'Dimensions': [
                        {
                            'Name': 'DeviceId',
                            'Value': str(sensor_data.get('deviceId', 'unknown'))
                        },
                        {
                            'Name': 'Location',
                            'Value': device_location
                        },
                        {
                            'Name': 'DeviceType',
                            'Value': 'temperature_sensor'
                        }
                    ],
                    'MeasureName': 'temperature',
                    'MeasureValue': str(temperature),
                    'MeasureValueType': 'DOUBLE'
                }
                
                timestream_records.append(temperature_record)
                
                # Create humidity measurement record if available
                if 'humidity' in sensor_data:
                    humidity = float(sensor_data['humidity'])
                    humidity_record = {
                        'Time': str(timestamp_ms),
                        'TimeUnit': 'MILLISECONDS',
                        'Dimensions': [
                            {
                                'Name': 'DeviceId',
                                'Value': str(sensor_data.get('deviceId', 'unknown'))
                            },
                            {
                                'Name': 'Location',
                                'Value': device_location
                            },
                            {
                                'Name': 'DeviceType',
                                'Value': 'humidity_sensor'
                            }
                        ],
                        'MeasureName': 'humidity',
                        'MeasureValue': str(humidity),
                        'MeasureValueType': 'DOUBLE'
                    }
                    timestream_records.append(humidity_record)
                
                processed_records += 1
                
            except Exception as e:
                logger.error(f"Error processing record: {str(e)}")
                failed_records += 1
                continue
        
        # Write records to Timestream in batches
        if timestream_records:
            # Timestream allows up to 100 records per request
            batch_size = 100
            for i in range(0, len(timestream_records), batch_size):
                batch = timestream_records[i:i + batch_size]
                
                try:
                    response = timestream.write_records(
                        DatabaseName=database_name,
                        TableName=table_name,
                        Records=batch
                    )
                    
                    logger.info(f"Successfully wrote {len(batch)} records to Timestream")
                    
                except Exception as e:
                    logger.error(f"Error writing batch to Timestream: {str(e)}")
                    failed_records += len(batch)
        
        # Return processing results
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'IoT data processed successfully',
                'processed_records': processed_records,
                'failed_records': failed_records,
                'timestream_records_written': len(timestream_records)
            })
        }
        
    except Exception as e:
        logger.error(f"Lambda function error: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': str(e),
                'processed_records': processed_records,
                'failed_records': failed_records
            })
        }