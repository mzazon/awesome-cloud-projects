#!/usr/bin/env python3
"""
Location Processor Cloud Function for Fleet Optimization System

This function processes vehicle location updates from Pub/Sub messages and stores
them in Cloud Bigtable for real-time fleet tracking and historical analysis.
It also triggers route optimization when significant traffic changes are detected.

Project: ${project_id}
Bigtable Instance: ${bigtable_instance}
Traffic Table: ${traffic_table}
Location Table: ${location_table}
"""

import json
import os
import logging
from datetime import datetime, timezone
from typing import Dict, Any, Optional
import base64

from google.cloud import bigtable
from google.cloud.bigtable import row_filters
from google.cloud import pubsub_v1
from google.cloud import error_reporting
import functions_framework

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Initialize Error Reporting
error_client = error_reporting.Client()

# Global clients (initialized once per container)
bigtable_client = None
publisher_client = None

def initialize_clients():
    """Initialize Google Cloud clients with proper error handling."""
    global bigtable_client, publisher_client
    
    try:
        if bigtable_client is None:
            bigtable_client = bigtable.Client(project=os.environ['PROJECT_ID'])
        
        if publisher_client is None:
            publisher_client = pubsub_v1.PublisherClient()
            
        logger.info("Successfully initialized Google Cloud clients")
        
    except Exception as e:
        logger.error(f"Failed to initialize clients: {e}")
        error_client.report_exception()
        raise

@functions_framework.cloud_event
def process_location(cloud_event):
    """
    Main entry point for processing vehicle location updates.
    
    Args:
        cloud_event: CloudEvent object containing Pub/Sub message data
        
    Returns:
        dict: Processing result status
    """
    try:
        # Initialize clients if needed
        initialize_clients()
        
        # Extract and validate message data
        message_data = extract_message_data(cloud_event)
        if not message_data:
            logger.warning("No valid message data found")
            return {"status": "skipped", "reason": "invalid_data"}
        
        # Process vehicle location update
        location_result = process_vehicle_location(message_data)
        
        # Process traffic data if available
        traffic_result = process_traffic_data(message_data)
        
        # Check if route optimization should be triggered
        optimization_triggered = check_optimization_trigger(message_data)
        
        result = {
            "status": "success",
            "location_processed": location_result,
            "traffic_processed": traffic_result,
            "optimization_triggered": optimization_triggered,
            "timestamp": datetime.now(timezone.utc).isoformat()
        }
        
        logger.info(f"Successfully processed location update: {result}")
        return result
        
    except Exception as e:
        logger.error(f"Error processing location update: {e}")
        error_client.report_exception()
        return {"status": "error", "message": str(e)}

def extract_message_data(cloud_event) -> Optional[Dict[str, Any]]:
    """
    Extract and validate message data from Cloud Event.
    
    Args:
        cloud_event: CloudEvent object from Pub/Sub
        
    Returns:
        dict: Parsed message data or None if invalid
    """
    try:
        # Decode Pub/Sub message data
        message_data = base64.b64decode(cloud_event.data.get('message', {}).get('data', ''))
        parsed_data = json.loads(message_data.decode('utf-8'))
        
        # Validate required fields
        required_fields = ['vehicle_id', 'latitude', 'longitude', 'timestamp']
        for field in required_fields:
            if field not in parsed_data:
                logger.warning(f"Missing required field: {field}")
                return None
        
        # Validate data types and ranges
        if not isinstance(parsed_data['latitude'], (int, float)) or not (-90 <= parsed_data['latitude'] <= 90):
            logger.warning(f"Invalid latitude: {parsed_data['latitude']}")
            return None
            
        if not isinstance(parsed_data['longitude'], (int, float)) or not (-180 <= parsed_data['longitude'] <= 180):
            logger.warning(f"Invalid longitude: {parsed_data['longitude']}")
            return None
        
        # Add processing timestamp
        parsed_data['processed_at'] = datetime.now(timezone.utc).isoformat()
        
        return parsed_data
        
    except (json.JSONDecodeError, KeyError, ValueError) as e:
        logger.warning(f"Failed to parse message data: {e}")
        return None

def process_vehicle_location(message_data: Dict[str, Any]) -> bool:
    """
    Store vehicle location data in Bigtable.
    
    Args:
        message_data: Parsed vehicle location data
        
    Returns:
        bool: True if successful, False otherwise
    """
    try:
        instance = bigtable_client.instance(os.environ['BIGTABLE_INSTANCE_ID'])
        table = instance.table(os.environ['LOCATION_TABLE'])
        
        # Create row key: vehicle_id#reverse_timestamp for efficient queries
        timestamp = int(message_data['timestamp'])
        reverse_timestamp = 9999999999 - timestamp  # For reverse chronological order
        row_key = f"{message_data['vehicle_id']}#{reverse_timestamp:010d}"
        
        # Create row and set cell values
        row = table.direct_row(row_key)
        
        # Location data
        row.set_cell('location', 'latitude', str(message_data['latitude']))
        row.set_cell('location', 'longitude', str(message_data['longitude']))
        row.set_cell('location', 'timestamp', str(timestamp))
        
        # Optional fields
        if 'speed' in message_data:
            row.set_cell('status', 'speed', str(message_data['speed']))
        if 'heading' in message_data:
            row.set_cell('status', 'heading', str(message_data['heading']))
        if 'road_segment' in message_data:
            row.set_cell('route_info', 'road_segment', str(message_data['road_segment']))
        
        # Metadata
        row.set_cell('status', 'processed_at', message_data['processed_at'])
        row.set_cell('status', 'processing_version', '1.0')
        
        # Commit the row
        row.commit()
        
        logger.info(f"Stored location for vehicle {message_data['vehicle_id']} at {timestamp}")
        return True
        
    except Exception as e:
        logger.error(f"Failed to store vehicle location: {e}")
        error_client.report_exception()
        return False

def process_traffic_data(message_data: Dict[str, Any]) -> bool:
    """
    Process and store traffic data if available in the message.
    
    Args:
        message_data: Parsed message data potentially containing traffic info
        
    Returns:
        bool: True if traffic data was processed, False otherwise
    """
    try:
        # Check if message contains traffic data
        if 'road_segment' not in message_data and 'traffic_speed' not in message_data:
            return False
        
        instance = bigtable_client.instance(os.environ['BIGTABLE_INSTANCE_ID'])
        table = instance.table(os.environ['TRAFFIC_TABLE'])
        
        # Use road segment from message or derive from location
        road_segment = message_data.get('road_segment', 
                                      f"seg_{abs(hash(f\"{message_data['latitude']}{message_data['longitude']}\"))}")
        
        # Create row key: road_segment#reverse_timestamp
        timestamp = int(message_data['timestamp'])
        reverse_timestamp = 9999999999 - timestamp
        row_key = f"{road_segment}#{reverse_timestamp:010d}"
        
        row = table.direct_row(row_key)
        
        # Store traffic data
        if 'speed' in message_data:
            row.set_cell('traffic_speed', 'current', str(message_data['speed']))
        
        if 'traffic_volume' in message_data:
            row.set_cell('traffic_volume', 'vehicles_per_hour', str(message_data['traffic_volume']))
        
        if 'conditions' in message_data:
            row.set_cell('road_conditions', 'weather', str(message_data['conditions']))
        
        # Metadata
        row.set_cell('metadata', 'source', 'vehicle_location')
        row.set_cell('metadata', 'vehicle_id', message_data['vehicle_id'])
        row.set_cell('metadata', 'processed_at', message_data['processed_at'])
        
        row.commit()
        
        logger.info(f"Stored traffic data for segment {road_segment}")
        return True
        
    except Exception as e:
        logger.error(f"Failed to store traffic data: {e}")
        error_client.report_exception()
        return False

def check_optimization_trigger(message_data: Dict[str, Any]) -> bool:
    """
    Check if route optimization should be triggered based on the current data.
    
    Args:
        message_data: Current vehicle location/traffic data
        
    Returns:
        bool: True if optimization was triggered, False otherwise
    """
    try:
        # Trigger optimization if speed is significantly below normal
        if 'speed' in message_data:
            speed = float(message_data['speed'])
            # Trigger if speed is below 20 km/h (likely traffic congestion)
            if speed < 20.0:
                return trigger_route_optimization(message_data, 'traffic_congestion')
        
        # Trigger optimization if specific road conditions are detected
        if 'conditions' in message_data:
            conditions = message_data['conditions'].lower()
            if conditions in ['accident', 'construction', 'severe_weather']:
                return trigger_route_optimization(message_data, f'road_condition_{conditions}')
        
        # Additional triggers can be added here based on business requirements
        
        return False
        
    except Exception as e:
        logger.error(f"Error checking optimization trigger: {e}")
        return False

def trigger_route_optimization(message_data: Dict[str, Any], trigger_reason: str) -> bool:
    """
    Trigger route optimization by publishing a message to the optimization topic.
    
    Args:
        message_data: Current vehicle/traffic data
        trigger_reason: Reason for triggering optimization
        
    Returns:
        bool: True if optimization request was published successfully
    """
    try:
        # Create optimization request
        optimization_request = {
            'trigger_reason': trigger_reason,
            'affected_area': {
                'latitude': message_data['latitude'],
                'longitude': message_data['longitude'],
                'radius_km': 5.0  # 5km radius around the incident
            },
            'trigger_data': {
                'vehicle_id': message_data['vehicle_id'],
                'speed': message_data.get('speed'),
                'road_segment': message_data.get('road_segment'),
                'timestamp': message_data['timestamp']
            },
            'priority': 'high' if trigger_reason.startswith('road_condition') else 'medium',
            'requested_at': datetime.now(timezone.utc).isoformat()
        }
        
        # Publish to route optimization topic
        topic_path = f"projects/{os.environ['PROJECT_ID']}/topics/route-optimization-requests"
        
        # Convert to JSON and encode
        message_json = json.dumps(optimization_request)
        message_bytes = message_json.encode('utf-8')
        
        # Publish with attributes for filtering
        future = publisher_client.publish(
            topic_path, 
            message_bytes,
            trigger_reason=trigger_reason,
            priority=optimization_request['priority'],
            vehicle_id=message_data['vehicle_id']
        )
        
        # Wait for publish to complete
        message_id = future.result(timeout=30)
        
        logger.info(f"Triggered route optimization: {trigger_reason}, message_id: {message_id}")
        return True
        
    except Exception as e:
        logger.error(f"Failed to trigger route optimization: {e}")
        error_client.report_exception()
        return False

def get_historical_traffic_data(road_segment: str, hours_back: int = 1) -> Dict[str, Any]:
    """
    Retrieve historical traffic data for analysis.
    
    Args:
        road_segment: Road segment identifier
        hours_back: Number of hours of historical data to retrieve
        
    Returns:
        dict: Historical traffic statistics
    """
    try:
        instance = bigtable_client.instance(os.environ['BIGTABLE_INSTANCE_ID'])
        table = instance.table(os.environ['TRAFFIC_TABLE'])
        
        # Calculate time range
        current_time = int(datetime.now(timezone.utc).timestamp())
        start_time = current_time - (hours_back * 3600)
        
        # Convert to reverse timestamps
        end_reverse = 9999999999 - start_time
        start_reverse = 9999999999 - current_time
        
        # Query historical data
        start_key = f"{road_segment}#{start_reverse:010d}"
        end_key = f"{road_segment}#{end_reverse:010d}"
        
        rows = table.read_rows(start_key=start_key, end_key=end_key)
        
        speeds = []
        volumes = []
        
        for row in rows:
            if 'traffic_speed' in row.cells:
                speed_cell = row.cells['traffic_speed']['current'][0]
                speeds.append(float(speed_cell.value.decode('utf-8')))
            
            if 'traffic_volume' in row.cells:
                volume_cell = row.cells['traffic_volume']['vehicles_per_hour'][0]
                volumes.append(float(volume_cell.value.decode('utf-8')))
        
        # Calculate statistics
        stats = {
            'road_segment': road_segment,
            'sample_count': len(speeds),
            'average_speed': sum(speeds) / len(speeds) if speeds else 0,
            'min_speed': min(speeds) if speeds else 0,
            'max_speed': max(speeds) if speeds else 0,
            'average_volume': sum(volumes) / len(volumes) if volumes else 0,
            'analysis_period_hours': hours_back
        }
        
        return stats
        
    except Exception as e:
        logger.error(f"Failed to get historical traffic data: {e}")
        return {'error': str(e)}

# Health check endpoint
@functions_framework.http
def health_check(request):
    """Simple health check endpoint for monitoring."""
    try:
        initialize_clients()
        return {"status": "healthy", "timestamp": datetime.now(timezone.utc).isoformat()}
    except Exception as e:
        return {"status": "unhealthy", "error": str(e)}, 500