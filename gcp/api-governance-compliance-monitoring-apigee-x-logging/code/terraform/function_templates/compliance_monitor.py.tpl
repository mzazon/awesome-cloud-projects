"""
API Compliance Monitoring Cloud Function

This function monitors API governance events and processes compliance violations.
It analyzes API usage patterns, detects policy violations, and triggers alerts.
"""

import json
import logging
import base64
import os
from datetime import datetime, timezone
from typing import Dict, List, Optional, Any

import functions_framework
from google.cloud import logging as cloud_logging
from google.cloud import monitoring_v3
from google.cloud import bigquery
from google.cloud import pubsub_v1

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Initialize Google Cloud clients
logging_client = cloud_logging.Client()
monitoring_client = monitoring_v3.MetricServiceClient()
pubsub_client = pubsub_v1.PublisherClient()

# Configuration from environment variables
PROJECT_ID = "${project_id}"
DATASET_ID = "${dataset_id}"
ERROR_RATE_THRESHOLD = float(os.environ.get("ERROR_RATE_THRESHOLD", "0.1"))
ENABLE_BIGQUERY_EXPORT = os.environ.get("ENABLE_BIGQUERY_EXPORT", "true").lower() == "true"

# Initialize BigQuery client if export is enabled
if ENABLE_BIGQUERY_EXPORT:
    bigquery_client = bigquery.Client(project=PROJECT_ID)
    table_id = f"{PROJECT_ID}.{DATASET_ID}.api_events"
else:
    bigquery_client = None
    table_id = None


@functions_framework.cloud_event
def monitor_api_compliance(cloud_event):
    """
    Cloud Function entry point for monitoring API compliance.
    
    Args:
        cloud_event: CloudEvent containing Pub/Sub message
        
    Returns:
        str: Processing result message
    """
    try:
        # Decode and parse the Pub/Sub message
        message_data = base64.b64decode(cloud_event.data["message"]["data"]).decode("utf-8")
        log_entry = json.loads(message_data)
        
        logger.info(f"Processing compliance event: {log_entry.get('logName', 'Unknown')}")
        
        # Extract compliance-relevant information
        compliance_event = extract_compliance_data(log_entry)
        
        # Analyze for policy violations
        violations = analyze_policy_violations(compliance_event)
        
        # Process each violation
        for violation in violations:
            process_compliance_violation(violation)
            
        # Store event data if BigQuery export is enabled
        if ENABLE_BIGQUERY_EXPORT and bigquery_client:
            store_compliance_event(compliance_event)
            
        # Update monitoring metrics
        update_monitoring_metrics(compliance_event, violations)
        
        return f"Processed {len(violations)} compliance violations"
        
    except Exception as e:
        logger.error(f"Error processing compliance event: {str(e)}")
        raise


def extract_compliance_data(log_entry: Dict[str, Any]) -> Dict[str, Any]:
    """
    Extract compliance-relevant data from log entry.
    
    Args:
        log_entry: Raw log entry from Cloud Logging
        
    Returns:
        Dict containing extracted compliance data
    """
    resource = log_entry.get("resource", {})
    proto_payload = log_entry.get("protoPayload", {})
    
    compliance_event = {
        "timestamp": log_entry.get("timestamp", datetime.now(timezone.utc).isoformat()),
        "severity": log_entry.get("severity", "INFO"),
        "resource_type": resource.get("type", ""),
        "resource_labels": resource.get("labels", {}),
        "service_name": proto_payload.get("serviceName", ""),
        "method_name": proto_payload.get("methodName", ""),
        "request_metadata": proto_payload.get("requestMetadata", {}),
        "authentication_info": proto_payload.get("authenticationInfo", {}),
        "authorization_info": proto_payload.get("authorizationInfo", []),
        "resource_name": proto_payload.get("resourceName", ""),
        "response": proto_payload.get("response", {}),
        "api_proxy": extract_api_proxy_info(proto_payload),
        "client_info": extract_client_info(proto_payload),
        "policy_context": extract_policy_context(proto_payload)
    }
    
    return compliance_event


def extract_api_proxy_info(proto_payload: Dict[str, Any]) -> Dict[str, Any]:
    """Extract API proxy information from proto payload."""
    resource_name = proto_payload.get("resourceName", "")
    
    # Extract proxy name from resource path
    proxy_name = None
    if "/proxies/" in resource_name:
        parts = resource_name.split("/proxies/")
        if len(parts) > 1:
            proxy_name = parts[1].split("/")[0]
    
    return {
        "proxy_name": proxy_name,
        "resource_path": resource_name,
        "api_version": proto_payload.get("response", {}).get("apiVersion", ""),
        "proxy_revision": proto_payload.get("response", {}).get("revision", "")
    }


def extract_client_info(proto_payload: Dict[str, Any]) -> Dict[str, Any]:
    """Extract client information from proto payload."""
    request_metadata = proto_payload.get("requestMetadata", {})
    
    return {
        "caller_ip": request_metadata.get("callerIp", ""),
        "caller_supplied_user_agent": request_metadata.get("callerSuppliedUserAgent", ""),
        "destination_attributes": request_metadata.get("destinationAttributes", {}),
        "request_attributes": request_metadata.get("requestAttributes", {})
    }


def extract_policy_context(proto_payload: Dict[str, Any]) -> Dict[str, Any]:
    """Extract policy-related context from proto payload."""
    return {
        "policy_violations": [],
        "quota_exceeded": "quota" in proto_payload.get("methodName", "").lower(),
        "authentication_failed": "authentication" in proto_payload.get("methodName", "").lower(),
        "authorization_denied": any(
            auth.get("granted", False) is False 
            for auth in proto_payload.get("authorizationInfo", [])
        )
    }


def analyze_policy_violations(compliance_event: Dict[str, Any]) -> List[Dict[str, Any]]:
    """
    Analyze compliance event for policy violations.
    
    Args:
        compliance_event: Processed compliance event data
        
    Returns:
        List of detected policy violations
    """
    violations = []
    
    # Check for authentication failures
    if compliance_event["policy_context"]["authentication_failed"]:
        violations.append({
            "type": "AUTHENTICATION_FAILURE",
            "severity": "HIGH",
            "timestamp": compliance_event["timestamp"],
            "details": {
                "service": compliance_event["service_name"],
                "method": compliance_event["method_name"],
                "client_ip": compliance_event["client_info"]["caller_ip"],
                "resource": compliance_event["resource_name"]
            },
            "remediation": "Review authentication configuration and client credentials"
        })
    
    # Check for authorization failures
    if compliance_event["policy_context"]["authorization_denied"]:
        violations.append({
            "type": "AUTHORIZATION_FAILURE",
            "severity": "HIGH",
            "timestamp": compliance_event["timestamp"],
            "details": {
                "service": compliance_event["service_name"],
                "method": compliance_event["method_name"],
                "client_ip": compliance_event["client_info"]["caller_ip"],
                "resource": compliance_event["resource_name"]
            },
            "remediation": "Review API access permissions and IAM policies"
        })
    
    # Check for quota violations
    if compliance_event["policy_context"]["quota_exceeded"]:
        violations.append({
            "type": "QUOTA_VIOLATION",
            "severity": "MEDIUM",
            "timestamp": compliance_event["timestamp"],
            "details": {
                "service": compliance_event["service_name"],
                "method": compliance_event["method_name"],
                "client_ip": compliance_event["client_info"]["caller_ip"],
                "api_proxy": compliance_event["api_proxy"]["proxy_name"]
            },
            "remediation": "Review API quota limits and client usage patterns"
        })
    
    # Check for high-severity log events
    if compliance_event["severity"] in ["ERROR", "CRITICAL"]:
        violations.append({
            "type": "HIGH_SEVERITY_EVENT",
            "severity": compliance_event["severity"],
            "timestamp": compliance_event["timestamp"],
            "details": {
                "service": compliance_event["service_name"],
                "method": compliance_event["method_name"],
                "resource": compliance_event["resource_name"],
                "response": compliance_event["response"]
            },
            "remediation": "Investigate the root cause of the high-severity event"
        })
    
    return violations


def process_compliance_violation(violation: Dict[str, Any]) -> None:
    """
    Process a detected compliance violation.
    
    Args:
        violation: Violation details dictionary
    """
    logger.warning(f"Compliance violation detected: {violation['type']}")
    
    # Log violation for audit trail
    log_violation_for_audit(violation)
    
    # Create monitoring alert if severity is high
    if violation["severity"] in ["HIGH", "CRITICAL"]:
        create_monitoring_alert(violation)
    
    # Trigger automated response based on violation type
    trigger_automated_response(violation)


def log_violation_for_audit(violation: Dict[str, Any]) -> None:
    """Log violation for compliance audit trail."""
    audit_logger = logging_client.logger("api-governance-audit")
    
    audit_entry = {
        "violation_type": violation["type"],
        "severity": violation["severity"],
        "timestamp": violation["timestamp"],
        "details": violation["details"],
        "remediation": violation["remediation"],
        "audit_timestamp": datetime.now(timezone.utc).isoformat(),
        "processor": "compliance-monitor-function"
    }
    
    audit_logger.log_struct(audit_entry, severity=violation["severity"])


def create_monitoring_alert(violation: Dict[str, Any]) -> None:
    """Create monitoring alert for high-severity violations."""
    try:
        # Create custom metric for the violation
        project_name = f"projects/{PROJECT_ID}"
        
        # This would create a custom metric in Cloud Monitoring
        # Implementation depends on specific monitoring requirements
        logger.info(f"Creating monitoring alert for violation: {violation['type']}")
        
    except Exception as e:
        logger.error(f"Error creating monitoring alert: {str(e)}")


def trigger_automated_response(violation: Dict[str, Any]) -> None:
    """Trigger automated response based on violation type."""
    try:
        # Publish violation to governance topic for policy enforcement
        governance_topic = f"projects/{PROJECT_ID}/topics/api-governance-events"
        
        message_data = {
            "action": "POLICY_VIOLATION",
            "violation": violation,
            "timestamp": datetime.now(timezone.utc).isoformat()
        }
        
        future = pubsub_client.publish(
            governance_topic,
            json.dumps(message_data).encode("utf-8")
        )
        
        logger.info(f"Published violation to governance topic: {future.result()}")
        
    except Exception as e:
        logger.error(f"Error triggering automated response: {str(e)}")


def store_compliance_event(compliance_event: Dict[str, Any]) -> None:
    """Store compliance event in BigQuery for analytics."""
    if not bigquery_client or not table_id:
        return
    
    try:
        # Transform compliance event for BigQuery schema
        bq_row = {
            "timestamp": compliance_event["timestamp"],
            "api_proxy": compliance_event["api_proxy"]["proxy_name"],
            "response_code": extract_response_code(compliance_event),
            "request_size": extract_request_size(compliance_event),
            "response_size": extract_response_size(compliance_event),
            "latency_ms": extract_latency(compliance_event),
            "client_ip": compliance_event["client_info"]["caller_ip"],
            "user_agent": compliance_event["client_info"]["caller_supplied_user_agent"],
            "api_key": hash_api_key(compliance_event),
            "policy_violations": extract_policy_violations(compliance_event),
            "severity": compliance_event["severity"],
            "compliance_status": determine_compliance_status(compliance_event)
        }
        
        # Insert row into BigQuery
        errors = bigquery_client.insert_rows_json(table_id, [bq_row])
        
        if errors:
            logger.error(f"Error inserting row into BigQuery: {errors}")
        else:
            logger.info("Successfully stored compliance event in BigQuery")
            
    except Exception as e:
        logger.error(f"Error storing compliance event: {str(e)}")


def extract_response_code(compliance_event: Dict[str, Any]) -> Optional[int]:
    """Extract HTTP response code from compliance event."""
    try:
        return compliance_event.get("response", {}).get("code", None)
    except:
        return None


def extract_request_size(compliance_event: Dict[str, Any]) -> Optional[int]:
    """Extract request size from compliance event."""
    try:
        return compliance_event.get("request_metadata", {}).get("requestSize", None)
    except:
        return None


def extract_response_size(compliance_event: Dict[str, Any]) -> Optional[int]:
    """Extract response size from compliance event."""
    try:
        return compliance_event.get("response", {}).get("size", None)
    except:
        return None


def extract_latency(compliance_event: Dict[str, Any]) -> Optional[int]:
    """Extract request latency from compliance event."""
    try:
        return compliance_event.get("request_metadata", {}).get("latency", None)
    except:
        return None


def hash_api_key(compliance_event: Dict[str, Any]) -> Optional[str]:
    """Hash API key for privacy while maintaining tracking capability."""
    try:
        api_key = compliance_event.get("authentication_info", {}).get("apiKey", "")
        if api_key:
            import hashlib
            return hashlib.sha256(api_key.encode()).hexdigest()[:16]
        return None
    except:
        return None


def extract_policy_violations(compliance_event: Dict[str, Any]) -> List[str]:
    """Extract policy violations list from compliance event."""
    violations = []
    
    policy_context = compliance_event.get("policy_context", {})
    
    if policy_context.get("authentication_failed"):
        violations.append("AUTHENTICATION_FAILURE")
    
    if policy_context.get("authorization_denied"):
        violations.append("AUTHORIZATION_FAILURE")
    
    if policy_context.get("quota_exceeded"):
        violations.append("QUOTA_VIOLATION")
    
    return violations


def determine_compliance_status(compliance_event: Dict[str, Any]) -> str:
    """Determine overall compliance status for the event."""
    severity = compliance_event.get("severity", "INFO")
    policy_violations = extract_policy_violations(compliance_event)
    
    if severity in ["ERROR", "CRITICAL"] or policy_violations:
        return "FAIL"
    elif severity == "WARNING":
        return "WARNING"
    else:
        return "PASS"


def update_monitoring_metrics(compliance_event: Dict[str, Any], violations: List[Dict[str, Any]]) -> None:
    """Update custom monitoring metrics for compliance tracking."""
    try:
        project_name = f"projects/{PROJECT_ID}"
        
        # Update violation count metric
        violation_count = len(violations)
        
        # Update compliance status metric
        compliance_status = determine_compliance_status(compliance_event)
        
        # Log metrics for monitoring
        logger.info(f"Compliance metrics - Violations: {violation_count}, Status: {compliance_status}")
        
        # This would create custom metrics in Cloud Monitoring
        # Implementation depends on specific monitoring requirements
        
    except Exception as e:
        logger.error(f"Error updating monitoring metrics: {str(e)}")