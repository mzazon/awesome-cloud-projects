import json
import base64
import logging
import os
from datetime import datetime, timezone
from google.cloud import healthcare_v1
from google.cloud import tasks_v2
from google.cloud import storage
from google.cloud import bigquery
from google.cloud import logging as cloud_logging

# Configure logging
cloud_logging.Client().setup_logging()
logger = logging.getLogger(__name__)

def process_fhir_event(event, context):
    """Process FHIR store events for compliance validation."""
    try:
        # Decode Pub/Sub message
        if 'data' in event:
            message_data = base64.b64decode(event['data']).decode('utf-8')
            message = json.loads(message_data)
        else:
            message = event
        
        # Extract event details
        resource_name = message.get('resourceName', '')
        event_type = message.get('eventType', 'UNKNOWN')
        timestamp = datetime.now(timezone.utc).isoformat()
        
        # Log compliance event
        compliance_event = {
            'timestamp': timestamp,
            'resource_name': resource_name,
            'event_type': event_type,
            'compliance_status': 'PROCESSING',
            'message_id': context.eventId if hasattr(context, 'eventId') else 'unknown'
        }
        
        logger.info(f"Processing compliance event: {compliance_event}")
        
        # Validate PHI access patterns
        validation_result = validate_phi_access(message)
        compliance_event['validation_result'] = validation_result
        
        # Store compliance event in BigQuery
        store_compliance_event_bigquery(compliance_event)
        
        # Create compliance task for detailed processing
        if validation_result.get('requires_audit', False):
            create_compliance_task(compliance_event)
        
        # Store compliance event in Cloud Storage
        store_compliance_event_storage(compliance_event)
        
        return {'status': 'success', 'event_id': compliance_event['message_id']}
        
    except Exception as e:
        logger.error(f"Error processing FHIR event: {str(e)}")
        return {'status': 'error', 'error': str(e)}

def validate_phi_access(message):
    """Validate PHI access patterns and compliance requirements."""
    resource_name = message.get('resourceName', '')
    event_type = message.get('eventType', '')
    
    validation = {
        'is_phi_access': 'Patient' in resource_name or 'Person' in resource_name,
        'requires_audit': True,
        'compliance_level': 'STANDARD',
        'risk_score': calculate_risk_score(message)
    }
    
    # Enhanced validation for high-risk operations
    if event_type in ['CREATE', 'UPDATE', 'DELETE']:
        validation['requires_audit'] = True
        validation['compliance_level'] = 'ENHANCED'
    
    return validation

def calculate_risk_score(message):
    """Calculate risk score based on access patterns."""
    base_score = 1
    
    # Increase score for sensitive operations
    if message.get('eventType') == 'DELETE':
        base_score += 3
    elif message.get('eventType') in ['CREATE', 'UPDATE']:
        base_score += 2
    
    # Increase score for patient data
    if 'Patient' in message.get('resourceName', ''):
        base_score += 2
    
    return min(base_score, 5)  # Cap at 5

def create_compliance_task(event_data):
    """Create Cloud Task for detailed compliance processing."""
    try:
        client = tasks_v2.CloudTasksClient()
        parent = client.queue_path(
            project="${project_id}",
            location="${region}",
            queue="${queue_name}"
        )
        
        task = {
            'http_request': {
                'http_method': tasks_v2.HttpMethod.POST,
                'url': f"https://${region}-${project_id}.cloudfunctions.net/compliance-audit-${random_suffix}",
                'headers': {'Content-Type': 'application/json'},
                'body': json.dumps(event_data).encode()
            }
        }
        
        client.create_task(request={'parent': parent, 'task': task})
        logger.info(f"Created compliance task for event: {event_data['message_id']}")
        
    except Exception as e:
        logger.error(f"Error creating compliance task: {str(e)}")

def store_compliance_event_bigquery(event_data):
    """Store compliance event in BigQuery."""
    try:
        client = bigquery.Client()
        table_id = f"${project_id}.${dataset_id}.compliance_events"
        
        # Convert timestamp to datetime object
        timestamp_dt = datetime.fromisoformat(event_data['timestamp'].replace('Z', '+00:00'))
        
        row = {
            'timestamp': timestamp_dt,
            'resource_name': event_data.get('resource_name'),
            'event_type': event_data.get('event_type'),
            'compliance_status': event_data.get('compliance_status'),
            'validation_result': event_data.get('validation_result'),
            'risk_score': event_data.get('validation_result', {}).get('risk_score'),
            'message_id': event_data.get('message_id')
        }
        
        client.insert_rows_json(table_id, [row])
        logger.info(f"Stored compliance event in BigQuery: {table_id}")
        
    except Exception as e:
        logger.error(f"Error storing compliance event in BigQuery: {str(e)}")

def store_compliance_event_storage(event_data):
    """Store compliance event in Cloud Storage."""
    try:
        client = storage.Client()
        bucket_name = "${bucket_name}"
        bucket = client.bucket(bucket_name)
        
        # Create timestamped blob name
        timestamp = datetime.now(timezone.utc)
        blob_name = f"compliance-events/{timestamp.strftime('%Y/%m/%d')}/{event_data['message_id']}.json"
        
        blob = bucket.blob(blob_name)
        blob.upload_from_string(
            json.dumps(event_data, indent=2),
            content_type='application/json'
        )
        
        logger.info(f"Stored compliance event in Cloud Storage: {blob_name}")
        
    except Exception as e:
        logger.error(f"Error storing compliance event in Cloud Storage: {str(e)}")