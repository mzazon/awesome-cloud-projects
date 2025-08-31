import json
import base64
import logging
from google.cloud import bigquery
from google.cloud import monitoring_v3
from datetime import datetime, timezone
import os
import hashlib

def process_sensor_data(event, context):
    """Process IoT sensor data with validation and BigQuery insertion"""
    
    try:
        # Decode Pub/Sub message
        if 'data' in event:
            message_data = base64.b64decode(event['data']).decode('utf-8')
            sensor_data = json.loads(message_data)
        else:
            logging.error("No data field in Pub/Sub message")
            return 'Error: Missing data'
        
        # Validate required fields
        required_fields = ['device_id', 'sensor_type', 'value']
        for field in required_fields:
            if field not in sensor_data:
                logging.error(f"Missing required field: {field}")
                return f'Error: Missing {field}'
        
        # Initialize BigQuery client
        client = bigquery.Client()
        table_id = f"${project_id}.${dataset_name}.sensor_readings"
        
        # Add data quality checks
        sensor_value = sensor_data.get('value')
        if not isinstance(sensor_value, (int, float)):
            logging.error(f"Invalid sensor value type: {type(sensor_value)}")
            return 'Error: Invalid value type'
        
        # Generate data hash for deduplication
        data_hash = hashlib.md5(
            f"{sensor_data.get('device_id')}{sensor_data.get('timestamp', '')}{sensor_value}".encode()
        ).hexdigest()
        
        # Prepare enriched row for insertion
        current_time = datetime.now(timezone.utc)
        row = {
            "device_id": sensor_data.get("device_id"),
            "sensor_type": sensor_data.get("sensor_type"),
            "location": sensor_data.get("location", "unknown"),
            "timestamp": sensor_data.get("timestamp", current_time.isoformat()),
            "value": float(sensor_value),
            "unit": sensor_data.get("unit", ""),
            "metadata": sensor_data.get("metadata", {}),
            "ingestion_time": current_time.isoformat()
        }
        
        # Insert into BigQuery with streaming
        errors = client.insert_rows_json(table_id, [row])
        
        if errors:
            logging.error(f"BigQuery insertion errors: {errors}")
            return f'Error: {errors}'
        
        # Log successful processing
        logging.info(f"Successfully processed data from {sensor_data.get('device_id')}")
        
        # Send custom metric to Cloud Monitoring
        monitoring_client = monitoring_v3.MetricServiceClient()
        project_name = f"projects/${project_id}"
        
        # Create time series data point
        series = monitoring_v3.TimeSeries()
        series.metric.type = "custom.googleapis.com/iot/sensor_messages_processed"
        series.resource.type = "global"
        
        point = monitoring_v3.Point()
        point.value.int64_value = 1
        point.interval.end_time.seconds = int(current_time.timestamp())
        series.points = [point]
        
        # Send metric
        monitoring_client.create_time_series(
            name=project_name, 
            time_series=[series]
        )
        
        return 'OK'
        
    except Exception as e:
        logging.error(f"Error processing sensor data: {str(e)}")
        return f'Error: {str(e)}'