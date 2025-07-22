"""
Cloud Function for processing Cloud IDS threat detection findings.

This function receives threat detection data from Cloud IDS via Pub/Sub,
processes and enriches the data, stores it in BigQuery for analysis,
and triggers alerts for high-severity threats.
"""

import json
import base64
import logging
import os
from datetime import datetime
from typing import Dict, Any, Optional

from google.cloud import bigquery
from google.cloud import pubsub_v1
from google.cloud import logging as cloud_logging

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Initialize Google Cloud clients
bq_client = bigquery.Client()
publisher = pubsub_v1.PublisherClient()

# Configure Cloud Logging
cloud_logging_client = cloud_logging.Client()
cloud_logging_client.setup_logging()

# Environment variables
PROJECT_ID = os.environ.get('PROJECT_ID')
DATASET_ID = os.environ.get('DATASET_ID', 'threat_detection')
ALERTS_TOPIC = os.environ.get('ALERTS_TOPIC')


def validate_finding_data(finding: Dict[str, Any]) -> bool:
    """
    Validate that the finding data contains required fields.
    
    Args:
        finding: Dictionary containing threat finding data
        
    Returns:
        bool: True if data is valid, False otherwise
    """
    required_fields = ['finding_id', 'severity', 'threat_type']
    
    for field in required_fields:
        if not finding.get(field):
            logger.warning(f"Missing required field: {field}")
            return False
    
    # Validate severity level
    valid_severities = ['LOW', 'MEDIUM', 'HIGH', 'CRITICAL', 'INFORMATIONAL']
    if finding.get('severity') not in valid_severities:
        logger.warning(f"Invalid severity level: {finding.get('severity')}")
        return False
    
    return True


def enrich_finding_data(finding: Dict[str, Any]) -> Dict[str, Any]:
    """
    Enrich the finding data with additional context and metadata.
    
    Args:
        finding: Original finding data
        
    Returns:
        Dict: Enriched finding data
    """
    enriched_finding = finding.copy()
    
    # Add processing timestamp
    enriched_finding['processed_timestamp'] = datetime.utcnow().isoformat()
    
    # Add severity score for easier analysis
    severity_scores = {
        'LOW': 1,
        'MEDIUM': 2,
        'HIGH': 3,
        'CRITICAL': 4,
        'INFORMATIONAL': 0
    }
    enriched_finding['severity_score'] = severity_scores.get(
        finding.get('severity', 'INFORMATIONAL'), 0
    )
    
    # Extract additional details if present
    details = finding.get('details', {})
    if isinstance(details, str):
        try:
            details = json.loads(details)
        except json.JSONDecodeError:
            logger.warning("Failed to parse details as JSON")
            details = {}
    
    # Add threat categorization
    threat_type = finding.get('threat_type', '').lower()
    if 'malware' in threat_type:
        enriched_finding['threat_category'] = 'malware'
    elif 'scan' in threat_type:
        enriched_finding['threat_category'] = 'reconnaissance'
    elif 'dos' in threat_type or 'ddos' in threat_type:
        enriched_finding['threat_category'] = 'availability'
    elif 'injection' in threat_type:
        enriched_finding['threat_category'] = 'injection'
    else:
        enriched_finding['threat_category'] = 'other'
    
    return enriched_finding


def store_finding_in_bigquery(finding: Dict[str, Any]) -> bool:
    """
    Store the threat finding in BigQuery for analysis.
    
    Args:
        finding: Threat finding data to store
        
    Returns:
        bool: True if successfully stored, False otherwise
    """
    try:
        table_id = f"{PROJECT_ID}.{DATASET_ID}.ids_findings"
        
        # Prepare data for BigQuery insertion
        row_to_insert = {
            "finding_id": finding.get("finding_id", ""),
            "timestamp": datetime.utcnow(),
            "severity": finding.get("severity", "UNKNOWN"),
            "threat_type": finding.get("threat_type", ""),
            "source_ip": finding.get("source_ip", ""),
            "destination_ip": finding.get("destination_ip", ""),
            "protocol": finding.get("protocol", ""),
            "details": json.dumps(finding.get("details", {})),
            "raw_data": json.dumps(finding)
        }
        
        # Get BigQuery table reference
        table = bq_client.get_table(table_id)
        
        # Insert row into BigQuery
        errors = bq_client.insert_rows_json(table, [row_to_insert])
        
        if errors:
            logger.error(f"BigQuery insert errors: {errors}")
            return False
        
        logger.info(f"Successfully stored finding {finding.get('finding_id')} in BigQuery")
        return True
        
    except Exception as e:
        logger.error(f"Error storing finding in BigQuery: {str(e)}")
        return False


def trigger_security_alert(finding: Dict[str, Any]) -> bool:
    """
    Trigger a security alert for high-severity threats.
    
    Args:
        finding: Threat finding data
        
    Returns:
        bool: True if alert was successfully triggered, False otherwise
    """
    try:
        if not ALERTS_TOPIC:
            logger.warning("ALERTS_TOPIC not configured, skipping alert")
            return False
        
        topic_path = publisher.topic_path(PROJECT_ID, ALERTS_TOPIC.split('/')[-1])
        
        alert_data = {
            "alert_type": "HIGH_SEVERITY_THREAT",
            "finding_id": finding.get("finding_id"),
            "threat_type": finding.get("threat_type"),
            "source_ip": finding.get("source_ip"),
            "destination_ip": finding.get("destination_ip"),
            "severity": finding.get("severity"),
            "timestamp": datetime.utcnow().isoformat(),
            "details": finding.get("details", {}),
            "recommended_actions": get_recommended_actions(finding)
        }
        
        # Publish alert message
        message_data = json.dumps(alert_data).encode('utf-8')
        future = publisher.publish(topic_path, message_data)
        
        # Wait for publish to complete
        future.result(timeout=30)
        
        logger.info(f"Security alert triggered for finding {finding.get('finding_id')}")
        return True
        
    except Exception as e:
        logger.error(f"Error triggering security alert: {str(e)}")
        return False


def get_recommended_actions(finding: Dict[str, Any]) -> list:
    """
    Get recommended actions based on the threat type and severity.
    
    Args:
        finding: Threat finding data
        
    Returns:
        list: Recommended actions for the threat
    """
    threat_type = finding.get('threat_type', '').lower()
    severity = finding.get('severity', 'LOW')
    
    actions = []
    
    if 'malware' in threat_type:
        actions.extend([
            "Isolate affected systems immediately",
            "Run full antivirus scan on affected hosts",
            "Review network connections from affected IPs",
            "Check for lateral movement indicators"
        ])
    elif 'scan' in threat_type:
        actions.extend([
            "Block source IP if external",
            "Review firewall rules and access controls",
            "Monitor for follow-up attacks",
            "Check for successful connections after scan"
        ])
    elif 'dos' in threat_type or 'ddos' in threat_type:
        actions.extend([
            "Enable DDoS protection if not already active",
            "Consider rate limiting from source networks",
            "Monitor service availability",
            "Scale infrastructure if needed"
        ])
    
    if severity in ['HIGH', 'CRITICAL']:
        actions.extend([
            "Notify security team immediately",
            "Document incident for compliance reporting",
            "Consider emergency response procedures"
        ])
    
    return actions


def process_threat_finding(event: Dict[str, Any], context: Any) -> None:
    """
    Main Cloud Function entry point for processing threat findings.
    
    This function is triggered by Pub/Sub messages containing Cloud IDS findings.
    It validates, enriches, stores the data in BigQuery, and triggers alerts
    for high-severity threats.
    
    Args:
        event: Pub/Sub event containing the threat finding data
        context: Cloud Function context (unused)
    """
    try:
        # Decode Pub/Sub message
        if 'data' not in event:
            logger.error("No data in Pub/Sub message")
            return
        
        message_data = base64.b64decode(event['data']).decode('utf-8')
        finding = json.loads(message_data)
        
        logger.info(f"Processing threat finding: {finding.get('finding_id', 'unknown')}")
        
        # Validate finding data
        if not validate_finding_data(finding):
            logger.error("Invalid finding data, skipping processing")
            return
        
        # Enrich finding data
        enriched_finding = enrich_finding_data(finding)
        
        # Store in BigQuery
        storage_success = store_finding_in_bigquery(enriched_finding)
        if not storage_success:
            logger.error("Failed to store finding in BigQuery")
            # Don't return here - still try to trigger alerts for critical threats
        
        # Trigger alert for high severity findings
        severity = finding.get("severity", "LOW")
        if severity in ["HIGH", "CRITICAL"]:
            alert_success = trigger_security_alert(enriched_finding)
            if not alert_success:
                logger.warning("Failed to trigger security alert")
        
        # Log successful processing
        logger.info(f"Successfully processed threat finding: {finding.get('finding_id')}")
        
        # Update processing metrics (could be expanded to use Cloud Monitoring)
        logger.info(f"Threat processing completed - Severity: {severity}, Type: {finding.get('threat_type')}")
        
    except json.JSONDecodeError as e:
        logger.error(f"Failed to decode JSON message: {str(e)}")
        raise
    except Exception as e:
        logger.error(f"Error processing threat finding: {str(e)}")
        raise


# For local testing
if __name__ == "__main__":
    # Sample test data
    test_event = {
        'data': base64.b64encode(json.dumps({
            "finding_id": "test-001",
            "severity": "HIGH",
            "threat_type": "Malware Detection",
            "source_ip": "203.0.113.1",
            "destination_ip": "10.0.1.5",
            "protocol": "TCP",
            "details": {"port": 80, "payload": "suspicious"}
        }).encode('utf-8')).decode('utf-8')
    }
    
    process_threat_finding(test_event, None)