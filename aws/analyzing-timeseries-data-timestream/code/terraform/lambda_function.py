#!/usr/bin/env python3
"""
Lambda Function for Amazon Timestream Data Ingestion

This function processes IoT sensor data and writes it to Amazon Timestream.
It supports multiple data formats and provides error handling for robust operation.

Environment Variables:
- DATABASE_NAME: Timestream database name
- TABLE_NAME: Timestream table name  
- AWS_REGION: AWS region for Timestream client

Supported Input Formats:
1. Direct invocation with sensor data
2. SQS records containing sensor data
3. SNS records with sensor data
4. IoT Core messages
"""

import json
import boto3
import os
import time
import logging
from datetime import datetime, timezone
from typing import Dict, List, Any, Optional

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize Timestream client
timestream = boto3.client('timestream-write')

def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Main Lambda handler for processing IoT sensor data and writing to Timestream.
    
    Args:
        event: Lambda event containing sensor data
        context: Lambda context object
        
    Returns:
        Dict containing status code and response message
    """
    try:
        database_name = os.environ['DATABASE_NAME']
        table_name = os.environ['TABLE_NAME']
        
        logger.info(f"Processing event: {json.dumps(event, default=str)}")
        
        # Parse different event sources
        if 'Records' in event:
            # Handle SQS/SNS records
            for record in event['Records']:
                if 'body' in record:
                    # SQS record
                    body = json.loads(record['body'])
                    write_to_timestream(database_name, table_name, body)
                elif 'Sns' in record and 'Message' in record['Sns']:
                    # SNS record
                    message = json.loads(record['Sns']['Message'])
                    write_to_timestream(database_name, table_name, message)
                else:
                    logger.warning(f"Unknown record format: {record}")
        else:
            # Direct invocation or IoT Core message
            write_to_timestream(database_name, table_name, event)
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Data written to Timestream successfully',
                'database': database_name,
                'table': table_name
            })
        }
        
    except Exception as e:
        logger.error(f"Error processing event: {str(e)}", exc_info=True)
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': str(e),
                'message': 'Failed to write data to Timestream'
            })
        }

def write_to_timestream(database_name: str, table_name: str, data: Dict[str, Any]) -> None:
    """
    Write sensor data to Timestream database.
    
    Args:
        database_name: Name of the Timestream database
        table_name: Name of the Timestream table
        data: Sensor data to write
    """
    current_time = str(int(time.time() * 1000))
    
    records = []
    
    # Handle different data structures
    if isinstance(data, list):
        for item in data:
            records.extend(create_timestream_records(item, current_time))
    else:
        records.extend(create_timestream_records(data, current_time))
    
    if records:
        try:
            # Write records to Timestream in batches
            batch_size = 100  # Timestream limit is 100 records per request
            for i in range(0, len(records), batch_size):
                batch = records[i:i + batch_size]
                
                result = timestream.write_records(
                    DatabaseName=database_name,
                    TableName=table_name,
                    Records=batch
                )
                
                logger.info(f"Successfully wrote batch of {len(batch)} records. RequestId: {result.get('ResponseMetadata', {}).get('RequestId')}")
            
            logger.info(f"Total records written: {len(records)}")
            
        except Exception as e:
            logger.error(f"Error writing to Timestream: {str(e)}")
            raise

def create_timestream_records(data: Dict[str, Any], current_time: str) -> List[Dict[str, Any]]:
    """
    Create Timestream records from sensor data.
    
    Args:
        data: Sensor data dictionary
        current_time: Current timestamp in milliseconds
        
    Returns:
        List of Timestream record dictionaries
    """
    records = []
    
    # Extract device metadata
    device_id = str(data.get('device_id', 'unknown'))
    location = str(data.get('location', 'unknown'))
    
    # Use provided timestamp or current time
    timestamp = data.get('timestamp')
    if timestamp:
        try:
            # Try parsing ISO format timestamp
            dt = datetime.fromisoformat(timestamp.replace('Z', '+00:00'))
            record_time = str(int(dt.timestamp() * 1000))
        except (ValueError, AttributeError):
            # Fallback to current time if parsing fails
            record_time = current_time
            logger.warning(f"Unable to parse timestamp '{timestamp}', using current time")
    else:
        record_time = current_time
    
    # Create base dimensions (metadata) for all records
    base_dimensions = [
        {'Name': 'device_id', 'Value': device_id},
        {'Name': 'location', 'Value': location}
    ]
    
    # Add device type if provided
    if 'device_type' in data:
        base_dimensions.append({
            'Name': 'device_type', 
            'Value': str(data['device_type'])
        })
    
    # Add facility or zone information if available
    if 'facility' in data:
        base_dimensions.append({
            'Name': 'facility', 
            'Value': str(data['facility'])
        })
    
    # Handle sensor readings as individual measures
    if 'sensors' in data:
        for sensor_type, value in data['sensors'].items():
            if value is not None:
                record = create_sensor_record(
                    dimensions=base_dimensions.copy(),
                    measure_name=sensor_type,
                    measure_value=value,
                    timestamp=record_time
                )
                if record:
                    records.append(record)
    
    # Handle individual sensor measurements
    sensor_fields = ['temperature', 'humidity', 'pressure', 'vibration', 'voltage', 'current', 'power']
    for field in sensor_fields:
        if field in data and data[field] is not None:
            record = create_sensor_record(
                dimensions=base_dimensions.copy(),
                measure_name=field,
                measure_value=data[field],
                timestamp=record_time
            )
            if record:
                records.append(record)
    
    # Handle generic measurement field
    if 'measurement' in data and data['measurement'] is not None:
        metric_name = data.get('metric_name', 'value')
        record = create_sensor_record(
            dimensions=base_dimensions.copy(),
            measure_name=metric_name,
            measure_value=data['measurement'],
            timestamp=record_time
        )
        if record:
            records.append(record)
    
    # Handle multi-value records for efficiency
    if 'measurements' in data and isinstance(data['measurements'], dict):
        for measure_name, measure_value in data['measurements'].items():
            if measure_value is not None:
                record = create_sensor_record(
                    dimensions=base_dimensions.copy(),
                    measure_name=measure_name,
                    measure_value=measure_value,
                    timestamp=record_time
                )
                if record:
                    records.append(record)
    
    if not records:
        logger.warning(f"No valid sensor data found in: {data}")
    
    return records

def create_sensor_record(dimensions: List[Dict[str, str]], measure_name: str, 
                        measure_value: Any, timestamp: str) -> Optional[Dict[str, Any]]:
    """
    Create a single Timestream record for a sensor measurement.
    
    Args:
        dimensions: List of dimension dictionaries
        measure_name: Name of the measurement
        measure_value: Value of the measurement
        timestamp: Timestamp for the record
        
    Returns:
        Timestream record dictionary or None if invalid
    """
    try:
        # Determine measure value type and convert appropriately
        if isinstance(measure_value, (int, float)):
            value_type = 'DOUBLE'
            value_str = str(float(measure_value))
        elif isinstance(measure_value, bool):
            value_type = 'BOOLEAN'
            value_str = str(measure_value).lower()
        elif isinstance(measure_value, str):
            # Try to convert string to number
            try:
                float_val = float(measure_value)
                value_type = 'DOUBLE'
                value_str = str(float_val)
            except ValueError:
                value_type = 'VARCHAR'
                value_str = measure_value
        else:
            # Convert other types to string
            value_type = 'VARCHAR'
            value_str = str(measure_value)
        
        # Create the record
        record = {
            'Dimensions': dimensions,
            'MeasureName': measure_name,
            'MeasureValue': value_str,
            'MeasureValueType': value_type,
            'Time': timestamp,
            'TimeUnit': 'MILLISECONDS'
        }
        
        return record
        
    except Exception as e:
        logger.error(f"Error creating record for {measure_name}={measure_value}: {str(e)}")
        return None

def validate_record(record: Dict[str, Any]) -> bool:
    """
    Validate a Timestream record before writing.
    
    Args:
        record: Timestream record dictionary
        
    Returns:
        True if record is valid, False otherwise
    """
    required_fields = ['Dimensions', 'MeasureName', 'MeasureValue', 'MeasureValueType', 'Time', 'TimeUnit']
    
    for field in required_fields:
        if field not in record:
            logger.error(f"Missing required field '{field}' in record")
            return False
    
    # Validate dimensions
    if not isinstance(record['Dimensions'], list) or len(record['Dimensions']) == 0:
        logger.error("Dimensions must be a non-empty list")
        return False
    
    for dim in record['Dimensions']:
        if not isinstance(dim, dict) or 'Name' not in dim or 'Value' not in dim:
            logger.error(f"Invalid dimension format: {dim}")
            return False
    
    # Validate measure name
    if not record['MeasureName'] or not isinstance(record['MeasureName'], str):
        logger.error(f"Invalid measure name: {record['MeasureName']}")
        return False
    
    # Validate measure value type
    valid_types = ['DOUBLE', 'BIGINT', 'VARCHAR', 'BOOLEAN', 'TIMESTAMP']
    if record['MeasureValueType'] not in valid_types:
        logger.error(f"Invalid measure value type: {record['MeasureValueType']}")
        return False
    
    return True