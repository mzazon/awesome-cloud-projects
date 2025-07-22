# Cloud Function for Real-Time Streaming Analytics Processing
# This function processes streaming events and stores analytics data in BigQuery

import json
import logging
import os
from datetime import datetime
from typing import Dict, Any

import functions_framework
from google.cloud import bigquery
from google.cloud import error_reporting
from google.cloud.functions_v2 import CloudEvent

# Initialize clients
bigquery_client = bigquery.Client()
error_client = error_reporting.Client()

# Configuration from environment variables
PROJECT_ID = os.environ.get('PROJECT_ID')
DATASET_NAME = os.environ.get('DATASET_NAME')
LOG_LEVEL = os.environ.get('LOG_LEVEL', 'INFO')
REGION = os.environ.get('REGION', 'us-central1')

# Configure logging
logging.basicConfig(level=getattr(logging, LOG_LEVEL.upper()))
logger = logging.getLogger(__name__)

# BigQuery table references
STREAMING_EVENTS_TABLE = f"{PROJECT_ID}.{DATASET_NAME}.streaming_events"
CDN_ACCESS_LOGS_TABLE = f"{PROJECT_ID}.{DATASET_NAME}.cdn_access_logs"


def validate_streaming_event(event_data: Dict[str, Any]) -> Dict[str, Any]:
    """
    Validate and normalize streaming event data.
    
    Args:
        event_data: Raw event data from Pub/Sub message
        
    Returns:
        Validated and normalized event data
        
    Raises:
        ValueError: If required fields are missing or invalid
    """
    # Required fields
    required_fields = ['eventType', 'streamId']
    for field in required_fields:
        if field not in event_data:
            raise ValueError(f"Missing required field: {field}")
    
    # Create normalized event with default values
    normalized_event = {
        'timestamp': datetime.utcnow().isoformat() + 'Z',
        'event_type': str(event_data.get('eventType', 'unknown')),
        'viewer_id': str(event_data.get('viewerId', '')),
        'session_id': str(event_data.get('sessionId', '')),
        'stream_id': str(event_data.get('streamId', '')),
        'quality': str(event_data.get('quality', '')),
        'buffer_health': float(event_data.get('bufferHealth', 0.0)),
        'latency_ms': int(event_data.get('latency', 0)),
        'location': str(event_data.get('location', '')),
        'user_agent': str(event_data.get('userAgent', '')),
        'bitrate': int(event_data.get('bitrate', 0)),
        'resolution': str(event_data.get('resolution', '')),
        'cdn_cache_status': str(event_data.get('cacheStatus', '')),
        'edge_location': str(event_data.get('edgeLocation', ''))
    }
    
    # Validate numeric ranges
    if not 0.0 <= normalized_event['buffer_health'] <= 1.0:
        logger.warning(f"Buffer health {normalized_event['buffer_health']} outside valid range [0.0, 1.0]")
        normalized_event['buffer_health'] = max(0.0, min(1.0, normalized_event['buffer_health']))
    
    if normalized_event['latency_ms'] < 0:
        logger.warning(f"Negative latency {normalized_event['latency_ms']} corrected to 0")
        normalized_event['latency_ms'] = 0
    
    if normalized_event['bitrate'] < 0:
        logger.warning(f"Negative bitrate {normalized_event['bitrate']} corrected to 0")
        normalized_event['bitrate'] = 0
    
    return normalized_event


def validate_cdn_log_entry(log_data: Dict[str, Any]) -> Dict[str, Any]:
    """
    Validate and normalize CDN access log data.
    
    Args:
        log_data: Raw CDN log data
        
    Returns:
        Validated and normalized log entry
    """
    normalized_log = {
        'timestamp': datetime.utcnow().isoformat() + 'Z',
        'client_ip': str(log_data.get('clientIp', '')),
        'request_method': str(log_data.get('requestMethod', 'GET')),
        'request_uri': str(log_data.get('requestUri', '')),
        'response_code': int(log_data.get('responseCode', 200)),
        'response_size': int(log_data.get('responseSize', 0)),
        'cache_status': str(log_data.get('cacheStatus', 'UNKNOWN')),
        'edge_location': str(log_data.get('edgeLocation', '')),
        'user_agent': str(log_data.get('userAgent', '')),
        'referer': str(log_data.get('referer', '')),
        'latency_ms': int(log_data.get('latencyMs', 0))
    }
    
    # Validate response code range
    if not 100 <= normalized_log['response_code'] <= 599:
        logger.warning(f"Invalid response code {normalized_log['response_code']}")
        normalized_log['response_code'] = 500
    
    # Ensure non-negative values
    normalized_log['response_size'] = max(0, normalized_log['response_size'])
    normalized_log['latency_ms'] = max(0, normalized_log['latency_ms'])
    
    return normalized_log


def insert_to_bigquery(table_id: str, rows: list) -> None:
    """
    Insert rows into BigQuery table with error handling.
    
    Args:
        table_id: Full BigQuery table ID
        rows: List of rows to insert
        
    Raises:
        Exception: If BigQuery insert fails
    """
    try:
        table = bigquery_client.get_table(table_id)
        errors = bigquery_client.insert_rows_json(table, rows)
        
        if errors:
            error_msg = f"BigQuery insert errors for table {table_id}: {errors}"
            logger.error(error_msg)
            error_client.report_exception()
            raise Exception(error_msg)
        else:
            logger.info(f"Successfully inserted {len(rows)} rows into {table_id}")
            
    except Exception as e:
        logger.error(f"Failed to insert into BigQuery table {table_id}: {str(e)}")
        error_client.report_exception()
        raise


def calculate_derived_metrics(event_data: Dict[str, Any]) -> Dict[str, Any]:
    """
    Calculate derived metrics from streaming event data.
    
    Args:
        event_data: Normalized streaming event data
        
    Returns:
        Event data with additional derived metrics
    """
    # Calculate quality score based on buffer health and latency
    buffer_score = event_data['buffer_health'] * 100
    
    # Latency scoring (lower is better)
    if event_data['latency_ms'] <= 100:
        latency_score = 100
    elif event_data['latency_ms'] <= 500:
        latency_score = 80
    elif event_data['latency_ms'] <= 1000:
        latency_score = 60
    else:
        latency_score = 40
    
    # Overall quality score (weighted average)
    quality_score = (buffer_score * 0.6) + (latency_score * 0.4)
    
    # Add derived metrics
    event_data['quality_score'] = round(quality_score, 2)
    event_data['is_buffering'] = event_data['buffer_health'] < 0.5
    event_data['is_high_latency'] = event_data['latency_ms'] > 500
    
    return event_data


@functions_framework.cloud_event
def process_streaming_event(cloud_event: CloudEvent) -> Dict[str, str]:
    """
    Main function to process streaming events from Pub/Sub.
    
    Args:
        cloud_event: CloudEvent containing the Pub/Sub message
        
    Returns:
        Processing status result
    """
    try:
        # Extract message data from CloudEvent
        message_data = cloud_event.data.get('message', {})
        
        if 'data' not in message_data:
            logger.warning("No data field in Pub/Sub message")
            return {'status': 'skipped', 'reason': 'no_data'}
        
        # Decode base64 message data
        import base64
        message_json = base64.b64decode(message_data['data']).decode('utf-8')
        event_data = json.loads(message_json)
        
        logger.info(f"Processing event: {event_data.get('eventType', 'unknown')}")
        
        # Determine event type and process accordingly
        event_type = event_data.get('eventType', 'unknown')
        
        if event_type in ['stream_start', 'stream_stop', 'quality_change', 'buffer_start', 'buffer_end', 'viewer_join', 'viewer_leave']:
            # Process as streaming event
            try:
                validated_event = validate_streaming_event(event_data)
                enriched_event = calculate_derived_metrics(validated_event)
                
                # Insert into streaming events table
                insert_to_bigquery(STREAMING_EVENTS_TABLE, [enriched_event])
                
                logger.info(f"Successfully processed streaming event: {event_type}")
                
            except ValueError as e:
                logger.error(f"Validation error for streaming event: {str(e)}")
                return {'status': 'error', 'message': f'validation_error: {str(e)}'}
                
        elif event_type in ['cdn_request', 'cdn_response']:
            # Process as CDN access log
            try:
                validated_log = validate_cdn_log_entry(event_data)
                
                # Insert into CDN access logs table
                insert_to_bigquery(CDN_ACCESS_LOGS_TABLE, [validated_log])
                
                logger.info(f"Successfully processed CDN log entry: {event_type}")
                
            except ValueError as e:
                logger.error(f"Validation error for CDN log: {str(e)}")
                return {'status': 'error', 'message': f'validation_error: {str(e)}'}
                
        else:
            # Unknown event type - log for monitoring
            logger.warning(f"Unknown event type: {event_type}")
            
            # Still try to process as generic streaming event
            try:
                validated_event = validate_streaming_event(event_data)
                insert_to_bigquery(STREAMING_EVENTS_TABLE, [validated_event])
                
                logger.info(f"Processed unknown event type as streaming event: {event_type}")
                
            except Exception as e:
                logger.error(f"Failed to process unknown event type: {str(e)}")
                return {'status': 'error', 'message': f'unknown_event_error: {str(e)}'}
        
        return {'status': 'success', 'event_type': event_type}
        
    except json.JSONDecodeError as e:
        logger.error(f"JSON decode error: {str(e)}")
        error_client.report_exception()
        return {'status': 'error', 'message': f'json_error: {str(e)}'}
        
    except Exception as e:
        logger.error(f"Unexpected error processing streaming event: {str(e)}")
        error_client.report_exception()
        return {'status': 'error', 'message': f'unexpected_error: {str(e)}'}


# Health check endpoint for monitoring
@functions_framework.http
def health_check(request):
    """
    Simple health check endpoint for monitoring.
    
    Args:
        request: HTTP request object
        
    Returns:
        Health status response
    """
    try:
        # Test BigQuery connectivity
        bigquery_client.get_dataset(DATASET_NAME)
        
        return {
            'status': 'healthy',
            'timestamp': datetime.utcnow().isoformat(),
            'project': PROJECT_ID,
            'dataset': DATASET_NAME,
            'region': REGION
        }
        
    except Exception as e:
        logger.error(f"Health check failed: {str(e)}")
        return {
            'status': 'unhealthy',
            'error': str(e),
            'timestamp': datetime.utcnow().isoformat()
        }, 500