"""
Cloud Function to Process Infrastructure Change Events
=====================================================
This function processes asset change events from Cloud Asset Inventory,
transforms them into structured audit records, and stores them in BigQuery
for compliance reporting and analysis.

Author: Infrastructure Monitoring System
Version: 1.0
"""

import base64
import json
import logging
import os
from datetime import datetime
from typing import Dict, Any, Optional

from google.cloud import bigquery
from google.cloud import monitoring_v3
from google.cloud.exceptions import GoogleCloudError

# Configure logging for Cloud Functions
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Global clients for connection reuse
BQ_CLIENT = None
MONITORING_CLIENT = None

def get_bigquery_client():
    """Get or create BigQuery client with connection reuse."""
    global BQ_CLIENT
    if BQ_CLIENT is None:
        BQ_CLIENT = bigquery.Client()
    return BQ_CLIENT

def get_monitoring_client():
    """Get or create Cloud Monitoring client with connection reuse."""
    global MONITORING_CLIENT
    if MONITORING_CLIENT is None:
        MONITORING_CLIENT = monitoring_v3.MetricServiceClient()
    return MONITORING_CLIENT

def validate_environment():
    """Validate required environment variables are present."""
    required_vars = ['PROJECT_ID', 'DATASET_NAME']
    missing_vars = [var for var in required_vars if not os.environ.get(var)]
    
    if missing_vars:
        raise ValueError(f"Missing required environment variables: {missing_vars}")
    
    return {
        'project_id': os.environ['PROJECT_ID'],
        'dataset_name': os.environ['DATASET_NAME'],
        'region': os.environ.get('REGION', 'us-central1')
    }

def decode_pubsub_message(event: Dict[str, Any]) -> Optional[str]:
    """
    Decode Pub/Sub message from event data.
    
    Args:
        event: Cloud Functions event data
        
    Returns:
        Decoded message string or None if invalid
    """
    try:
        if 'data' not in event:
            logger.warning("No data field in event")
            return None
            
        # Decode base64 message
        message_data = base64.b64decode(event['data']).decode('utf-8')
        
        # Skip welcome messages from feed initialization
        if message_data.startswith('Welcome'):
            logger.info('Received welcome message, skipping processing')
            return None
            
        return message_data
        
    except Exception as e:
        logger.error(f"Failed to decode Pub/Sub message: {str(e)}")
        return None

def parse_asset_change(message_data: str) -> Optional[Dict[str, Any]]:
    """
    Parse asset change data from message.
    
    Args:
        message_data: Raw message data from Pub/Sub
        
    Returns:
        Parsed change data or None if invalid
    """
    try:
        change_data = json.loads(message_data)
        
        # Extract asset information
        asset = change_data.get('asset', {})
        prior_asset = change_data.get('priorAsset', {})
        window = change_data.get('window', {})
        
        # Determine change type based on asset presence
        if prior_asset and not asset:
            change_type = 'DELETED'
            primary_asset = prior_asset
        elif asset and not prior_asset:
            change_type = 'CREATED'
            primary_asset = asset
        elif asset and prior_asset:
            change_type = 'UPDATED'
            primary_asset = asset
        else:
            logger.warning("Unable to determine change type from asset data")
            return None
        
        # Extract resource data safely
        def safe_get_resource_data(asset_data: Dict) -> Dict:
            return asset_data.get('resource', {}).get('data', {})
        
        # Build structured change record
        change_record = {
            'asset_name': primary_asset.get('name', ''),
            'asset_type': primary_asset.get('assetType', ''),
            'change_type': change_type,
            'prior_state': json.dumps(safe_get_resource_data(prior_asset)) if prior_asset else '',
            'current_state': json.dumps(safe_get_resource_data(asset)) if asset else '',
            'location': primary_asset.get('resource', {}).get('location', ''),
            'change_time': window.get('startTime', ''),
            'ancestors': ','.join(primary_asset.get('ancestors', [])),
            'raw_change_data': message_data  # Store raw data for debugging
        }
        
        return change_record
        
    except json.JSONDecodeError as e:
        logger.error(f"Failed to parse JSON message: {str(e)}")
        return None
    except Exception as e:
        logger.error(f"Error parsing asset change: {str(e)}")
        return None

def extract_project_from_asset_name(asset_name: str) -> str:
    """
    Extract project ID from asset name.
    
    Args:
        asset_name: Full asset name (e.g., //compute.googleapis.com/projects/my-project/...)
        
    Returns:
        Project ID or empty string if not found
    """
    try:
        # Asset names typically follow pattern: //service/projects/PROJECT_ID/...
        parts = asset_name.split('/')
        for i, part in enumerate(parts):
            if part == 'projects' and i + 1 < len(parts):
                return parts[i + 1]
        return ''
    except Exception:
        return ''

def insert_bigquery_record(env_config: Dict[str, str], change_record: Dict[str, Any]) -> bool:
    """
    Insert asset change record into BigQuery.
    
    Args:
        env_config: Environment configuration
        change_record: Parsed change data
        
    Returns:
        True if successful, False otherwise
    """
    try:
        bq_client = get_bigquery_client()
        
        # Add timestamp and project information
        row = {
            'timestamp': datetime.utcnow().isoformat(),
            'project_id': extract_project_from_asset_name(change_record['asset_name']) or env_config['project_id'],
            **change_record
        }
        
        # Remove raw data field for BigQuery storage
        row.pop('raw_change_data', None)
        
        # Get table reference
        table_ref = bq_client.dataset(env_config['dataset_name']).table('asset_changes')
        table = bq_client.get_table(table_ref)
        
        # Insert row
        errors = bq_client.insert_rows_json(table, [row])
        
        if errors:
            logger.error(f'BigQuery insert errors: {errors}')
            return False
        else:
            logger.info(f'Successfully inserted {change_record["change_type"]} record for {change_record["asset_name"]}')
            return True
            
    except GoogleCloudError as e:
        logger.error(f'BigQuery operation failed: {str(e)}')
        return False
    except Exception as e:
        logger.error(f'Unexpected error inserting BigQuery record: {str(e)}')
        return False

def send_monitoring_metric(env_config: Dict[str, str], change_record: Dict[str, Any]) -> bool:
    """
    Send custom metric to Cloud Monitoring.
    
    Args:
        env_config: Environment configuration
        change_record: Parsed change data
        
    Returns:
        True if successful, False otherwise
    """
    try:
        monitoring_client = get_monitoring_client()
        
        # Create time series for custom metric
        project_name = f"projects/{env_config['project_id']}"
        
        series = monitoring_v3.TimeSeries()
        series.metric.type = 'custom.googleapis.com/infrastructure/changes'
        series.metric.labels['change_type'] = change_record['change_type']
        series.metric.labels['asset_type'] = change_record['asset_type']
        series.metric.labels['region'] = env_config['region']
        
        # Set timestamp
        now = datetime.utcnow()
        interval = monitoring_v3.TimeInterval()
        interval.end_time.seconds = int(now.timestamp())
        interval.end_time.nanos = int((now.timestamp() % 1) * 10**9)
        
        # Create data point
        point = monitoring_v3.Point()
        point.interval = interval
        point.value.int64_value = 1
        series.points = [point]
        
        # Set resource information
        series.resource.type = 'global'
        series.resource.labels['project_id'] = env_config['project_id']
        
        # Send metric
        monitoring_client.create_time_series(
            name=project_name,
            time_series=[series]
        )
        
        logger.info(f'Successfully sent monitoring metric for {change_record["change_type"]} event')
        return True
        
    except GoogleCloudError as e:
        logger.error(f'Cloud Monitoring operation failed: {str(e)}')
        return False
    except Exception as e:
        logger.error(f'Unexpected error sending monitoring metric: {str(e)}')
        return False

def process_asset_change(event: Dict[str, Any], context: Any) -> None:
    """
    Main Cloud Function entry point for processing asset changes.
    
    Args:
        event: Cloud Functions event data from Pub/Sub trigger
        context: Cloud Functions context object
    """
    try:
        # Validate environment configuration
        env_config = validate_environment()
        logger.info(f'Processing asset change event in project {env_config["project_id"]}')
        
        # Decode Pub/Sub message
        message_data = decode_pubsub_message(event)
        if not message_data:
            return
        
        # Parse asset change data
        change_record = parse_asset_change(message_data)
        if not change_record:
            logger.warning('Unable to parse asset change data, skipping processing')
            return
        
        logger.info(f'Processing {change_record["change_type"]} event for {change_record["asset_type"]}')
        
        # Track processing success
        bigquery_success = False
        monitoring_success = False
        
        # Insert record into BigQuery
        try:
            bigquery_success = insert_bigquery_record(env_config, change_record)
        except Exception as e:
            logger.error(f'BigQuery processing failed: {str(e)}')
        
        # Send monitoring metric
        try:
            monitoring_success = send_monitoring_metric(env_config, change_record)
        except Exception as e:
            logger.error(f'Monitoring metric processing failed: {str(e)}')
        
        # Log processing results
        if bigquery_success and monitoring_success:
            logger.info('Successfully processed asset change event')
        elif bigquery_success:
            logger.warning('Asset change recorded in BigQuery but monitoring metric failed')
        elif monitoring_success:
            logger.warning('Monitoring metric sent but BigQuery insert failed')
        else:
            logger.error('Failed to process asset change event completely')
            # Re-raise to trigger retry
            raise Exception('Asset change processing failed')
        
    except Exception as e:
        logger.error(f'Error processing asset change event: {str(e)}')
        # Re-raise exception to trigger Cloud Functions retry mechanism
        raise

# Health check endpoint for testing
def health_check(request):
    """Simple health check endpoint for testing function deployment."""
    return {
        'status': 'healthy',
        'timestamp': datetime.utcnow().isoformat(),
        'function': 'process_asset_change',
        'version': '1.0'
    }