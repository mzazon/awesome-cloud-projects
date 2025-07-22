import base64
import json
import logging
import os
from datetime import datetime
from google.cloud import logging as cloud_logging
import functions_framework

# Initialize Cloud Logging client
PROJECT_ID = os.environ.get('PROJECT_ID')
logging_client = cloud_logging.Client(project=PROJECT_ID)
audit_logger = logging_client.logger('datastore-sync-audit')

# Configure local logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

@functions_framework.cloud_event
def audit_logger_func(cloud_event):
    """
    Log all synchronization events for audit and compliance.
    
    This function creates comprehensive audit logs for all data synchronization
    operations, including compliance-specific logging for regulatory requirements.
    """
    
    try:
        # Decode Pub/Sub message
        message_data = base64.b64decode(cloud_event.data["message"]["data"])
        event_data = json.loads(message_data.decode('utf-8'))
        
        logger.info(f"Processing audit event for entity: {event_data.get('entity_id')}")
        
        # Extract event information
        entity_id = event_data.get('entity_id')
        operation = event_data.get('operation')
        data = event_data.get('data', {})
        timestamp = event_data.get('timestamp')
        correlation_id = event_data.get('correlation_id')
        source = event_data.get('source', 'unknown')
        
        # Get message metadata
        message_id = cloud_event.data["message"]["messageId"]
        publish_time = cloud_event.data["message"]["publishTime"]
        delivery_attempt = cloud_event.data["message"].get("deliveryAttempt", 1)
        
        # Create comprehensive audit log entry
        audit_entry = {
            'audit_timestamp': datetime.utcnow().isoformat(),
            'event_type': 'data_synchronization',
            'entity_id': entity_id,
            'operation': operation,
            'correlation_id': correlation_id,
            'source_system': source,
            'event_timestamp': timestamp,
            'message_metadata': {
                'message_id': message_id,
                'publish_time': publish_time,
                'delivery_attempt': delivery_attempt,
                'subscription_source': cloud_event.source
            },
            'data_snapshot': sanitize_data_for_audit(data),
            'processing_metadata': {
                'function_name': 'audit_logger',
                'project_id': PROJECT_ID,
                'processing_timestamp': datetime.utcnow().isoformat()
            }
        }
        
        # Add data change tracking for updates
        if operation == 'update' and data:
            audit_entry['data_changes'] = analyze_data_changes(data)
        
        # Log to Cloud Logging with structured data
        audit_logger.log_struct(
            audit_entry,
            severity='INFO',
            labels={
                'component': 'datastore-sync',
                'operation': operation or 'unknown',
                'entity_type': 'sync_entity',
                'correlation_id': correlation_id or 'unknown'
            }
        )
        
        logger.info(f"Audit log created for entity: {entity_id}")
        
        # Additional compliance logging for sensitive operations
        if operation == 'delete':
            create_compliance_log(entity_id, data, correlation_id)
        
        # Log high-value operations
        if is_high_value_operation(data):
            create_security_log(entity_id, operation, data, correlation_id)
            
    except Exception as e:
        logger.error(f"Audit logging failed: {str(e)}")
        
        # Create error audit log
        error_entry = {
            'audit_timestamp': datetime.utcnow().isoformat(),
            'event_type': 'audit_error',
            'error_message': str(e),
            'original_event': event_data if 'event_data' in locals() else None,
            'processing_metadata': {
                'function_name': 'audit_logger',
                'project_id': PROJECT_ID
            }
        }
        
        audit_logger.log_struct(
            error_entry,
            severity='ERROR',
            labels={
                'component': 'datastore-sync',
                'event_type': 'audit_error'
            }
        )
        
        # Don't re-raise as audit failures shouldn't block the main process

def sanitize_data_for_audit(data):
    """
    Sanitize data for audit logging by removing or masking sensitive information.
    
    Args:
        data: Dictionary containing entity data
        
    Returns:
        Dictionary with sanitized data safe for audit logging
    """
    
    if not isinstance(data, dict):
        return data
    
    sanitized = {}
    sensitive_fields = ['password', 'secret', 'token', 'key', 'ssn', 'credit_card']
    
    for key, value in data.items():
        key_lower = key.lower()
        
        # Check if field contains sensitive information
        if any(sensitive in key_lower for sensitive in sensitive_fields):
            sanitized[key] = '***REDACTED***'
        elif isinstance(value, dict):
            sanitized[key] = sanitize_data_for_audit(value)
        elif isinstance(value, list):
            sanitized[key] = [sanitize_data_for_audit(item) if isinstance(item, dict) else item for item in value]
        else:
            sanitized[key] = value
    
    return sanitized

def analyze_data_changes(data):
    """
    Analyze data changes for audit purposes.
    
    Args:
        data: Dictionary containing new data
        
    Returns:
        Dictionary with change analysis
    """
    
    changes = {
        'fields_modified': list(data.keys()) if data else [],
        'modification_count': len(data) if data else 0,
        'has_sensitive_changes': False
    }
    
    # Check for sensitive field changes
    sensitive_fields = ['status', 'permissions', 'access_level', 'role']
    for field in sensitive_fields:
        if field in data:
            changes['has_sensitive_changes'] = True
            break
    
    return changes

def create_compliance_log(entity_id, data, correlation_id):
    """
    Create compliance-specific log entry for data deletion.
    
    Args:
        entity_id: Unique identifier for the entity
        data: Data that was deleted
        correlation_id: Operation correlation ID
    """
    
    compliance_entry = {
        'compliance_timestamp': datetime.utcnow().isoformat(),
        'compliance_event': 'data_deletion',
        'entity_id': entity_id,
        'correlation_id': correlation_id,
        'deletion_metadata': {
            'deleted_fields': list(data.keys()) if data else [],
            'retention_policy': 'applied',
            'deletion_method': 'soft_delete_with_audit'
        },
        'regulatory_context': {
            'gdpr_compliance': True,
            'data_subject_request': False,  # Would be True if deletion was due to user request
            'retention_period_expired': False
        },
        'audit_trail': {
            'deletion_authorized': True,
            'deletion_logged': True,
            'backup_status': 'preserved_in_audit'
        }
    }
    
    audit_logger.log_struct(
        compliance_entry,
        severity='NOTICE',
        labels={
            'compliance': 'data_deletion',
            'regulation': 'gdpr',
            'entity_id': entity_id,
            'correlation_id': correlation_id or 'unknown'
        }
    )
    
    logger.info(f"Compliance log created for deletion of entity: {entity_id}")

def create_security_log(entity_id, operation, data, correlation_id):
    """
    Create security-specific log entry for high-value operations.
    
    Args:
        entity_id: Unique identifier for the entity
        operation: Type of operation
        data: Entity data
        correlation_id: Operation correlation ID
    """
    
    security_entry = {
        'security_timestamp': datetime.utcnow().isoformat(),
        'security_event': 'high_value_operation',
        'entity_id': entity_id,
        'operation': operation,
        'correlation_id': correlation_id,
        'risk_assessment': {
            'risk_level': determine_risk_level(data),
            'requires_review': True,
            'automated_approval': False
        },
        'security_context': {
            'data_classification': classify_data(data),
            'access_pattern': 'programmatic',
            'source_verification': 'pubsub_authenticated'
        }
    }
    
    audit_logger.log_struct(
        security_entry,
        severity='WARNING',
        labels={
            'security': 'high_value_operation',
            'entity_id': entity_id,
            'risk_level': determine_risk_level(data),
            'correlation_id': correlation_id or 'unknown'
        }
    )
    
    logger.info(f"Security log created for high-value operation on entity: {entity_id}")

def is_high_value_operation(data):
    """
    Determine if an operation involves high-value data.
    
    Args:
        data: Dictionary containing entity data
        
    Returns:
        Boolean indicating if this is a high-value operation
    """
    
    if not isinstance(data, dict):
        return False
    
    high_value_indicators = [
        'financial_amount', 'payment_info', 'bank_account', 'credit_card',
        'personal_id', 'ssn', 'passport', 'driver_license',
        'medical_record', 'health_info', 'diagnosis',
        'security_clearance', 'access_token', 'api_key'
    ]
    
    # Check for high-value fields
    for key in data.keys():
        key_lower = key.lower()
        if any(indicator in key_lower for indicator in high_value_indicators):
            return True
    
    # Check for high monetary values
    if 'amount' in data:
        try:
            amount = float(data['amount'])
            if amount > 10000:  # Configurable threshold
                return True
        except (ValueError, TypeError):
            pass
    
    return False

def determine_risk_level(data):
    """
    Determine risk level based on data content.
    
    Args:
        data: Dictionary containing entity data
        
    Returns:
        String indicating risk level (low, medium, high)
    """
    
    if not isinstance(data, dict):
        return 'low'
    
    # High risk indicators
    high_risk_fields = ['password', 'secret', 'token', 'ssn', 'credit_card']
    if any(field in str(data).lower() for field in high_risk_fields):
        return 'high'
    
    # Medium risk indicators
    medium_risk_fields = ['email', 'phone', 'address', 'name', 'id']
    if any(field in str(data).lower() for field in medium_risk_fields):
        return 'medium'
    
    return 'low'

def classify_data(data):
    """
    Classify data based on sensitivity.
    
    Args:
        data: Dictionary containing entity data
        
    Returns:
        String indicating data classification
    """
    
    if not isinstance(data, dict):
        return 'public'
    
    # Classification based on content
    if is_high_value_operation(data):
        return 'confidential'
    
    personal_fields = ['name', 'email', 'phone', 'address']
    if any(field in str(data).lower() for field in personal_fields):
        return 'internal'
    
    return 'public'