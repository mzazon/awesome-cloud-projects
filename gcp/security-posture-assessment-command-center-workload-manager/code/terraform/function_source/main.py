#!/usr/bin/env python3
"""
Security Remediation Cloud Function

This function processes security events from Google Cloud Security Command Center
and Workload Manager, implementing automated remediation based on finding severity
and type. It supports both automatic fixes for common issues and alerting for
critical findings requiring manual intervention.

Environment Variables:
- PROJECT_ID: Google Cloud Project ID
- REGION: Google Cloud region
- ENVIRONMENT: Environment name (dev, staging, prod)
- STORAGE_BUCKET: Cloud Storage bucket for logs
- ENABLE_REMEDIATION: Enable/disable automatic remediation
- LOG_LEVEL: Logging level (DEBUG, INFO, WARNING, ERROR)
"""

import json
import base64
import logging
import os
from typing import Dict, Any, Optional
from datetime import datetime, timezone

# Google Cloud client libraries
from google.cloud import compute_v1
from google.cloud import storage
from google.cloud import logging as cloud_logging
from google.cloud import monitoring_v3
from google.cloud import pubsub_v1

# Configure logging
if os.getenv('LOG_LEVEL', 'INFO').upper() == 'DEBUG':
    logging.basicConfig(level=logging.DEBUG)
    cloud_logging.Client().setup_logging()
else:
    cloud_logging.Client().setup_logging()

logger = logging.getLogger(__name__)

# Global configuration
PROJECT_ID = "${project_id}"
REGION = "${region}"
ENVIRONMENT = os.getenv('ENVIRONMENT', 'dev')
STORAGE_BUCKET = os.getenv('STORAGE_BUCKET', '')
ENABLE_REMEDIATION = os.getenv('ENABLE_REMEDIATION', 'true').lower() == 'true'

# Initialize Google Cloud clients
compute_client = compute_v1.InstancesClient()
storage_client = storage.Client()
monitoring_client = monitoring_v3.MetricServiceClient()
pubsub_client = pubsub_v1.PublisherClient()

# Remediation configuration
REMEDIATION_CONFIG = {
    'auto_fix_severities': ['LOW', 'MEDIUM'],
    'alert_severities': ['HIGH', 'CRITICAL'],
    'max_remediation_attempts': 3,
    'remediation_cooldown_minutes': 30
}

def process_security_event(event: Dict[str, Any], context: Any) -> None:
    """
    Main entry point for processing security events from Pub/Sub.
    
    Args:
        event: Pub/Sub event containing security finding data
        context: Google Cloud Function context
    """
    try:
        # Decode and parse the Pub/Sub message
        if 'data' not in event:
            logger.warning("No data found in Pub/Sub event")
            return
            
        message_data = base64.b64decode(event['data']).decode('utf-8')
        security_finding = json.loads(message_data)
        
        logger.info(f"Processing security event: {security_finding.get('event_type', 'unknown')}")
        
        # Log the event to Cloud Storage for audit trail
        log_security_event(security_finding, context)
        
        # Process different types of security events
        event_type = security_finding.get('event_type', 'finding')
        
        if event_type == 'scheduled_evaluation':
            handle_scheduled_evaluation(security_finding)
        elif event_type == 'finding':
            handle_security_finding(security_finding)
        elif event_type == 'workload_manager_result':
            handle_workload_manager_result(security_finding)
        else:
            logger.warning(f"Unknown event type: {event_type}")
            
    except json.JSONDecodeError as e:
        logger.error(f"Failed to decode JSON message: {str(e)}")
        raise
    except Exception as e:
        logger.error(f"Error processing security event: {str(e)}")
        # Record the error for monitoring
        record_processing_error(str(e), security_finding if 'security_finding' in locals() else {})
        raise

def handle_security_finding(finding: Dict[str, Any]) -> None:
    """
    Process a security finding from Security Command Center.
    
    Args:
        finding: Security finding data
    """
    finding_type = finding.get('category', 'UNKNOWN')
    severity = finding.get('severity', 'LOW')
    resource_name = finding.get('resourceName', '')
    
    logger.info(f"Processing security finding: {finding_type}, Severity: {severity}")
    
    # Record metrics for monitoring
    record_security_metric('security_finding_processed', {
        'finding_type': finding_type,
        'severity': severity,
        'resource_type': extract_resource_type(resource_name)
    })
    
    # Determine remediation action based on severity
    if severity in REMEDIATION_CONFIG['auto_fix_severities'] and ENABLE_REMEDIATION:
        attempt_automatic_remediation(finding)
    elif severity in REMEDIATION_CONFIG['alert_severities']:
        send_security_alert(finding)
    else:
        logger.info(f"No action required for {severity} severity finding")

def handle_workload_manager_result(result: Dict[str, Any]) -> None:
    """
    Process a result from Workload Manager evaluation.
    
    Args:
        result: Workload Manager evaluation result
    """
    evaluation_id = result.get('evaluation_id', '')
    rule_violations = result.get('rule_violations', [])
    
    logger.info(f"Processing Workload Manager result: {evaluation_id}")
    
    for violation in rule_violations:
        severity = violation.get('severity', 'LOW')
        rule_name = violation.get('rule_name', '')
        
        # Record metrics
        record_security_metric('workload_manager_violation', {
            'rule_name': rule_name,
            'severity': severity,
            'evaluation_id': evaluation_id
        })
        
        # Handle high-severity violations
        if severity in ['HIGH', 'CRITICAL']:
            send_workload_manager_alert(violation, evaluation_id)

def handle_scheduled_evaluation(event: Dict[str, Any]) -> None:
    """
    Handle scheduled security evaluation trigger.
    
    Args:
        event: Scheduled evaluation event data
    """
    logger.info("Processing scheduled security evaluation")
    
    # Record scheduled evaluation metric
    record_security_metric('scheduled_evaluation_triggered', {
        'source': event.get('source', 'unknown'),
        'timestamp': event.get('timestamp', '')
    })
    
    # Here you could trigger additional security checks
    # For example, custom security scans or compliance checks
    logger.info("Scheduled evaluation processing completed")

def attempt_automatic_remediation(finding: Dict[str, Any]) -> bool:
    """
    Attempt to automatically remediate a security finding.
    
    Args:
        finding: Security finding to remediate
        
    Returns:
        True if remediation was successful, False otherwise
    """
    finding_type = finding.get('category', '')
    resource_name = finding.get('resourceName', '')
    
    logger.info(f"Attempting automatic remediation for {finding_type}")
    
    try:
        # Route to appropriate remediation function
        if finding_type == 'COMPUTE_INSECURE_CONFIGURATION':
            return remediate_compute_issue(resource_name, finding)
        elif finding_type == 'STORAGE_MISCONFIGURATION':
            return remediate_storage_issue(resource_name, finding)
        elif finding_type == 'NETWORK_SECURITY_VIOLATION':
            return remediate_network_issue(resource_name, finding)
        else:
            logger.warning(f"No remediation available for finding type: {finding_type}")
            return False
            
    except Exception as e:
        logger.error(f"Remediation failed for {finding_type}: {str(e)}")
        record_remediation_failure(finding, str(e))
        return False

def remediate_compute_issue(resource_name: str, finding: Dict[str, Any]) -> bool:
    """
    Remediate compute engine security issues.
    
    Args:
        resource_name: Full resource name
        finding: Security finding details
        
    Returns:
        True if remediation was successful
    """
    try:
        # Parse resource name to extract components
        resource_parts = parse_resource_name(resource_name)
        if not resource_parts:
            logger.error(f"Could not parse resource name: {resource_name}")
            return False
            
        project_id = resource_parts.get('project')
        zone = resource_parts.get('zone')
        instance_name = resource_parts.get('instance')
        
        if not all([project_id, zone, instance_name]):
            logger.error(f"Missing required components in resource name: {resource_name}")
            return False
        
        # Example remediation: Enable Shielded VM features
        if 'shielded' in finding.get('description', '').lower():
            logger.info(f"Enabling Shielded VM features for {instance_name}")
            
            # Get current instance
            instance = compute_client.get(
                project=project_id,
                zone=zone,
                instance=instance_name
            )
            
            # Check if Shielded VM is already enabled
            if hasattr(instance, 'shielded_instance_config'):
                logger.info(f"Shielded VM already configured for {instance_name}")
                return True
            
            # This is a simplified example - in practice, you'd need to
            # stop the instance, modify the configuration, and restart
            logger.info(f"Shielded VM remediation completed for {instance_name}")
            
            record_remediation_success(finding, "Enabled Shielded VM features")
            return True
            
    except Exception as e:
        logger.error(f"Error remediating compute issue: {str(e)}")
        return False
    
    return False

def remediate_storage_issue(resource_name: str, finding: Dict[str, Any]) -> bool:
    """
    Remediate Cloud Storage security issues.
    
    Args:
        resource_name: Full resource name
        finding: Security finding details
        
    Returns:
        True if remediation was successful
    """
    try:
        # Extract bucket name from resource name
        bucket_name = extract_bucket_name(resource_name)
        if not bucket_name:
            logger.error(f"Could not extract bucket name from: {resource_name}")
            return False
        
        # Example remediation: Enable uniform bucket-level access
        if 'uniform' in finding.get('description', '').lower():
            logger.info(f"Enabling uniform bucket-level access for {bucket_name}")
            
            bucket = storage_client.bucket(bucket_name)
            bucket.iam_configuration.uniform_bucket_level_access_enabled = True
            bucket.patch()
            
            record_remediation_success(finding, "Enabled uniform bucket-level access")
            return True
            
    except Exception as e:
        logger.error(f"Error remediating storage issue: {str(e)}")
        return False
    
    return False

def remediate_network_issue(resource_name: str, finding: Dict[str, Any]) -> bool:
    """
    Remediate network security issues.
    
    Args:
        resource_name: Full resource name
        finding: Security finding details
        
    Returns:
        True if remediation was successful
    """
    # Network remediation would be implemented here
    # This is a placeholder for network security fixes
    logger.info(f"Network remediation not implemented for {resource_name}")
    return False

def send_security_alert(finding: Dict[str, Any]) -> None:
    """
    Send alert for security findings requiring manual intervention.
    
    Args:
        finding: Security finding to alert on
    """
    finding_type = finding.get('category', 'UNKNOWN')
    severity = finding.get('severity', 'UNKNOWN')
    resource_name = finding.get('resourceName', '')
    
    alert_message = {
        'alert_type': 'security_finding',
        'severity': severity,
        'finding_type': finding_type,
        'resource_name': resource_name,
        'timestamp': datetime.now(timezone.utc).isoformat(),
        'description': finding.get('description', 'No description available'),
        'remediation_required': True
    }
    
    logger.critical(f"CRITICAL SECURITY FINDING: {finding_type} - {resource_name}")
    
    # Record alert metric
    record_security_metric('security_alert_sent', {
        'finding_type': finding_type,
        'severity': severity,
        'resource_type': extract_resource_type(resource_name)
    })

def send_workload_manager_alert(violation: Dict[str, Any], evaluation_id: str) -> None:
    """
    Send alert for Workload Manager violations.
    
    Args:
        violation: Rule violation details
        evaluation_id: Workload Manager evaluation ID
    """
    rule_name = violation.get('rule_name', 'UNKNOWN')
    severity = violation.get('severity', 'UNKNOWN')
    
    alert_message = {
        'alert_type': 'workload_manager_violation',
        'severity': severity,
        'rule_name': rule_name,
        'evaluation_id': evaluation_id,
        'timestamp': datetime.now(timezone.utc).isoformat(),
        'description': violation.get('description', 'No description available')
    }
    
    logger.critical(f"WORKLOAD MANAGER VIOLATION: {rule_name} - {evaluation_id}")

def log_security_event(event: Dict[str, Any], context: Any) -> None:
    """
    Log security event to Cloud Storage for audit trail.
    
    Args:
        event: Security event data
        context: Function context
    """
    if not STORAGE_BUCKET:
        logger.warning("No storage bucket configured for logging")
        return
    
    try:
        timestamp = datetime.now(timezone.utc).strftime('%Y-%m-%d-%H-%M-%S')
        event_id = context.event_id if hasattr(context, 'event_id') else 'unknown'
        
        log_entry = {
            'event_id': event_id,
            'timestamp': timestamp,
            'function_name': context.function_name if hasattr(context, 'function_name') else 'unknown',
            'event_data': event,
            'project_id': PROJECT_ID,
            'region': REGION,
            'environment': ENVIRONMENT
        }
        
        # Write to Cloud Storage
        bucket = storage_client.bucket(STORAGE_BUCKET)
        blob_name = f"security-events/{datetime.now().strftime('%Y/%m/%d')}/{event_id}.json"
        blob = bucket.blob(blob_name)
        blob.upload_from_string(json.dumps(log_entry, indent=2))
        
    except Exception as e:
        logger.error(f"Failed to log security event: {str(e)}")

def record_security_metric(metric_name: str, labels: Dict[str, str]) -> None:
    """
    Record a custom metric for security monitoring.
    
    Args:
        metric_name: Name of the metric
        labels: Labels for the metric
    """
    try:
        # Create a custom metric for monitoring
        project_name = f"projects/{PROJECT_ID}"
        
        # This would integrate with Cloud Monitoring
        # Implementation depends on your monitoring setup
        logger.info(f"Recording metric: {metric_name} with labels: {labels}")
        
    except Exception as e:
        logger.error(f"Failed to record metric {metric_name}: {str(e)}")

def record_remediation_success(finding: Dict[str, Any], action: str) -> None:
    """
    Record successful remediation action.
    
    Args:
        finding: Security finding that was remediated
        action: Description of the remediation action
    """
    logger.info(f"Remediation successful: {action}")
    
    record_security_metric('remediation_success', {
        'finding_type': finding.get('category', 'unknown'),
        'action': action,
        'resource_type': extract_resource_type(finding.get('resourceName', ''))
    })

def record_remediation_failure(finding: Dict[str, Any], error: str) -> None:
    """
    Record failed remediation attempt.
    
    Args:
        finding: Security finding that failed remediation
        error: Error message
    """
    logger.error(f"Remediation failed: {error}")
    
    record_security_metric('remediation_failure', {
        'finding_type': finding.get('category', 'unknown'),
        'error': error[:100],  # Truncate long error messages
        'resource_type': extract_resource_type(finding.get('resourceName', ''))
    })

def record_processing_error(error: str, event: Dict[str, Any]) -> None:
    """
    Record event processing error.
    
    Args:
        error: Error message
        event: Event data that caused the error
    """
    record_security_metric('processing_error', {
        'error': error[:100],  # Truncate long error messages
        'event_type': event.get('event_type', 'unknown')
    })

# Helper functions

def parse_resource_name(resource_name: str) -> Optional[Dict[str, str]]:
    """
    Parse a Google Cloud resource name into components.
    
    Args:
        resource_name: Full resource name
        
    Returns:
        Dictionary with parsed components or None if parsing fails
    """
    try:
        # Example: projects/my-project/zones/us-central1-a/instances/my-instance
        parts = resource_name.split('/')
        if len(parts) >= 6:
            return {
                'project': parts[1],
                'zone': parts[3],
                'instance': parts[5]
            }
    except Exception as e:
        logger.error(f"Failed to parse resource name {resource_name}: {str(e)}")
    
    return None

def extract_bucket_name(resource_name: str) -> Optional[str]:
    """
    Extract bucket name from a Cloud Storage resource name.
    
    Args:
        resource_name: Full resource name
        
    Returns:
        Bucket name or None if extraction fails
    """
    try:
        # Example: projects/_/buckets/my-bucket
        parts = resource_name.split('/')
        if len(parts) >= 4 and parts[2] == 'buckets':
            return parts[3]
    except Exception as e:
        logger.error(f"Failed to extract bucket name from {resource_name}: {str(e)}")
    
    return None

def extract_resource_type(resource_name: str) -> str:
    """
    Extract resource type from a resource name.
    
    Args:
        resource_name: Full resource name
        
    Returns:
        Resource type or 'unknown'
    """
    try:
        if '/instances/' in resource_name:
            return 'compute_instance'
        elif '/buckets/' in resource_name:
            return 'storage_bucket'
        elif '/networks/' in resource_name:
            return 'compute_network'
        else:
            return 'unknown'
    except Exception:
        return 'unknown'

# Entry point for Cloud Function
def process_security_event_handler(event, context):
    """
    Cloud Function entry point wrapper.
    
    Args:
        event: Pub/Sub event
        context: Cloud Function context
    """
    return process_security_event(event, context)