"""
Cloud Function for processing DLP findings and creating Security Command Center findings.
This function is triggered by Pub/Sub messages containing DLP scan results.
"""
import base64
import json
import logging
import os
import time
from datetime import datetime
from typing import Dict, Any, Optional

import functions_framework
from google.cloud import dlp_v2
from google.cloud import securitycenter
from google.cloud import logging as cloud_logging
from google.cloud import monitoring_v3
from google.cloud.functions_v1 import CloudEvent

# Configuration from environment variables
PROJECT_ID = "${project_id}"
REGION = "${region}"
LOG_LEVEL = os.environ.get("LOG_LEVEL", "INFO")
ENVIRONMENT = os.environ.get("ENVIRONMENT", "prod")

# Initialize clients
dlp_client = dlp_v2.DlpServiceClient()
scc_client = securitycenter.SecurityCenterClient()
logging_client = cloud_logging.Client()
monitoring_client = monitoring_v3.MetricServiceClient()

# Setup logging
logging.basicConfig(level=getattr(logging, LOG_LEVEL))
logger = logging.getLogger(__name__)

# Cloud Logging handler
cloud_handler = cloud_logging.Handler(logging_client)
logger.addHandler(cloud_handler)

@functions_framework.cloud_event
def process_dlp_findings(cloud_event: CloudEvent) -> str:
    """
    Process DLP findings from Pub/Sub messages and create Security Command Center findings.
    
    Args:
        cloud_event: CloudEvent containing Pub/Sub message with DLP findings
        
    Returns:
        str: Processing result message
    """
    try:
        # Decode Pub/Sub message
        if not cloud_event.data.get("message"):
            logger.error("No message data found in cloud event")
            return "Error: No message data"
            
        message_data = base64.b64decode(
            cloud_event.data["message"]["data"]
        ).decode('utf-8')
        
        finding_data = json.loads(message_data)
        logger.info(f"Processing DLP finding: {finding_data.get('name', 'unknown')}")
        
        # Extract finding details
        project_id = finding_data.get('projectId', PROJECT_ID)
        location = finding_data.get('location', REGION)
        resource_name = finding_data.get('resourceName', 'unknown')
        
        # Process individual findings if they exist
        findings = finding_data.get('result', {}).get('findings', [])
        if not findings:
            logger.info("No findings in DLP result")
            return "No findings to process"
            
        processed_count = 0
        for finding in findings:
            try:
                process_individual_finding(finding, project_id, location, resource_name)
                processed_count += 1
            except Exception as e:
                logger.error(f"Error processing individual finding: {str(e)}")
                continue
                
        logger.info(f"Successfully processed {processed_count} DLP findings")
        return f"Processed {processed_count} findings successfully"
        
    except Exception as e:
        logger.error(f"Error processing DLP findings: {str(e)}")
        raise

def process_individual_finding(finding: Dict[str, Any], project_id: str, 
                             location: str, resource_name: str) -> None:
    """
    Process an individual DLP finding and create corresponding SCC finding.
    
    Args:
        finding: Individual DLP finding data
        project_id: GCP project ID
        location: Resource location
        resource_name: Name of the resource being scanned
    """
    info_type = finding.get('infoType', {}).get('name', 'UNKNOWN')
    likelihood = finding.get('likelihood', 'UNKNOWN')
    quote = finding.get('quote', '')
    
    # Determine severity based on info type and likelihood
    severity = determine_severity(info_type, likelihood)
    
    # Log the finding with structured data
    log_finding(finding, severity, info_type, resource_name)
    
    # Create custom metrics
    create_custom_metrics(info_type, severity)
    
    # Create Security Command Center finding if enabled
    try:
        create_scc_finding(finding, project_id, location, resource_name, severity)
    except Exception as e:
        logger.warning(f"Could not create SCC finding: {str(e)}")
    
    # Trigger remediation actions based on severity
    trigger_remediation(finding, severity, resource_name)

def determine_severity(info_type: str, likelihood: str) -> str:
    """
    Determine finding severity based on information type and likelihood.
    
    Args:
        info_type: Type of sensitive information detected
        likelihood: DLP likelihood score
        
    Returns:
        str: Severity level (HIGH, MEDIUM, LOW)
    """
    # High-risk information types
    high_risk_types = {
        'US_SOCIAL_SECURITY_NUMBER',
        'CREDIT_CARD_NUMBER', 
        'US_HEALTHCARE_NPI',
        'PASSPORT'
    }
    
    # Medium-risk information types
    medium_risk_types = {
        'EMAIL_ADDRESS',
        'PHONE_NUMBER',
        'DATE_OF_BIRTH',
        'PERSON_NAME'
    }
    
    # Adjust severity based on likelihood
    likelihood_multiplier = {
        'VERY_LIKELY': 2,
        'LIKELY': 1.5,
        'POSSIBLE': 1,
        'UNLIKELY': 0.5,
        'VERY_UNLIKELY': 0.25
    }
    
    base_severity = 1
    if info_type in high_risk_types:
        base_severity = 3
    elif info_type in medium_risk_types:
        base_severity = 2
        
    adjusted_severity = base_severity * likelihood_multiplier.get(likelihood, 1)
    
    if adjusted_severity >= 3:
        return "HIGH"
    elif adjusted_severity >= 1.5:
        return "MEDIUM"
    else:
        return "LOW"

def get_compliance_impact(info_type: str) -> str:
    """
    Get compliance regulations impacted by the information type.
    
    Args:
        info_type: Type of sensitive information
        
    Returns:
        str: Comma-separated list of impacted regulations
    """
    pii_types = {
        'US_SOCIAL_SECURITY_NUMBER', 'EMAIL_ADDRESS', 'PERSON_NAME', 
        'PHONE_NUMBER', 'DATE_OF_BIRTH'
    }
    phi_types = {'US_HEALTHCARE_NPI', 'DATE_OF_BIRTH'}
    pci_types = {'CREDIT_CARD_NUMBER'}
    
    impacts = []
    if info_type in pii_types:
        impacts.extend(['GDPR', 'CCPA'])
    if info_type in phi_types:
        impacts.append('HIPAA')
    if info_type in pci_types:
        impacts.append('PCI-DSS')
        
    return ','.join(impacts) if impacts else 'General Privacy'

def get_recommended_action(info_type: str, severity: str) -> str:
    """
    Get recommended remediation action based on finding type and severity.
    
    Args:
        info_type: Type of sensitive information
        severity: Severity level of the finding
        
    Returns:
        str: Recommended action description
    """
    high_priority_actions = {
        'US_SOCIAL_SECURITY_NUMBER': 'Encrypt or redact immediately, audit access logs',
        'CREDIT_CARD_NUMBER': 'Remove from storage, review PCI compliance',
        'US_HEALTHCARE_NPI': 'Encrypt PHI data, verify HIPAA compliance'
    }
    
    medium_priority_actions = {
        'EMAIL_ADDRESS': 'Review data retention policy and consent',
        'PHONE_NUMBER': 'Verify consent for storage and processing',
        'PERSON_NAME': 'Check data processing lawfulness'
    }
    
    if severity == "HIGH" and info_type in high_priority_actions:
        return high_priority_actions[info_type]
    elif info_type in medium_priority_actions:
        return medium_priority_actions[info_type]
    else:
        return 'Review data classification and access controls'

def log_finding(finding: Dict[str, Any], severity: str, info_type: str, resource_name: str) -> None:
    """
    Log finding to Cloud Logging with structured data.
    
    Args:
        finding: DLP finding data
        severity: Determined severity level
        info_type: Type of sensitive information
        resource_name: Resource where finding was detected
    """
    log_entry = {
        'message': 'DLP finding processed',
        'severity': severity,
        'info_type': info_type,
        'resource_name': resource_name,
        'likelihood': finding.get('likelihood'),
        'compliance_impact': get_compliance_impact(info_type),
        'recommended_action': get_recommended_action(info_type, severity),
        'timestamp': datetime.utcnow().isoformat(),
        'environment': ENVIRONMENT,
        'project_id': PROJECT_ID
    }
    
    # Use appropriate log level based on severity
    if severity == "HIGH":
        logger.error(json.dumps(log_entry))
    elif severity == "MEDIUM":
        logger.warning(json.dumps(log_entry))
    else:
        logger.info(json.dumps(log_entry))

def create_custom_metrics(info_type: str, severity: str) -> None:
    """
    Create custom metrics for monitoring DLP findings.
    
    Args:
        info_type: Type of sensitive information
        severity: Severity level of the finding
    """
    try:
        project_name = f"projects/{PROJECT_ID}"
        
        # Create time series for findings count
        series = monitoring_v3.TimeSeries()
        series.metric.type = "custom.googleapis.com/dlp/findings_count"
        series.resource.type = "global"
        series.metric.labels['info_type'] = info_type
        series.metric.labels['severity'] = severity
        series.metric.labels['environment'] = ENVIRONMENT
        
        # Add data point
        point = monitoring_v3.Point()
        point.value.int64_value = 1
        now = time.time()
        point.interval.end_time.seconds = int(now)
        series.points = [point]
        
        # Write time series
        monitoring_client.create_time_series(
            name=project_name,
            time_series=[series]
        )
        
        logger.debug(f"Created custom metric for {info_type} with severity {severity}")
        
    except Exception as e:
        logger.warning(f"Could not create custom metrics: {str(e)}")

def create_scc_finding(finding: Dict[str, Any], project_id: str, location: str, 
                      resource_name: str, severity: str) -> None:
    """
    Create Security Command Center finding.
    
    Args:
        finding: DLP finding data
        project_id: GCP project ID
        location: Resource location
        resource_name: Resource where finding was detected
        severity: Severity level of the finding
    """
    try:
        info_type = finding.get('infoType', {}).get('name', 'UNKNOWN')
        
        # This would require SCC to be properly configured with an organization
        # For demo purposes, we'll log what would be created
        scc_finding = {
            'category': 'DATA_LEAK',
            'severity': severity,
            'resource_name': resource_name,
            'state': 'ACTIVE',
            'source_properties': {
                'dlp_info_type': info_type,
                'scan_location': location,
                'compliance_impact': get_compliance_impact(info_type),
                'recommended_action': get_recommended_action(info_type, severity),
                'detection_time': datetime.utcnow().isoformat()
            }
        }
        
        logger.info(f"Would create SCC finding: {json.dumps(scc_finding)}")
        
    except Exception as e:
        logger.warning(f"Could not create SCC finding: {str(e)}")

def trigger_remediation(finding: Dict[str, Any], severity: str, resource_name: str) -> None:
    """
    Trigger automated remediation actions based on finding severity.
    
    Args:
        finding: DLP finding data
        severity: Severity level of the finding
        resource_name: Resource where finding was detected
    """
    info_type = finding.get('infoType', {}).get('name', 'UNKNOWN')
    
    if severity == "HIGH":
        logger.error(f"HIGH SEVERITY FINDING: {info_type} detected in {resource_name}")
        # High severity: immediate action required
        send_alert_notification(finding, "CRITICAL", resource_name)
        
    elif severity == "MEDIUM":
        logger.warning(f"MEDIUM SEVERITY FINDING: {info_type} detected in {resource_name}")
        # Medium severity: review required
        send_alert_notification(finding, "WARNING", resource_name)
        
    else:
        logger.info(f"LOW SEVERITY FINDING: {info_type} detected in {resource_name}")

def send_alert_notification(finding: Dict[str, Any], alert_level: str, resource_name: str) -> None:
    """
    Send alert notification for critical findings.
    
    Args:
        finding: DLP finding data
        alert_level: Alert severity level
        resource_name: Resource where finding was detected
    """
    # This would integrate with your notification system
    # For demo purposes, we'll create a structured log entry
    alert_data = {
        'alert_type': 'DLP_PRIVACY_VIOLATION',
        'alert_level': alert_level,
        'info_type': finding.get('infoType', {}).get('name', 'UNKNOWN'),
        'resource_name': resource_name,
        'detection_time': datetime.utcnow().isoformat(),
        'quote_preview': finding.get('quote', '')[:50] + "..." if finding.get('quote') else None,
        'recommended_action': get_recommended_action(
            finding.get('infoType', {}).get('name', 'UNKNOWN'),
            alert_level
        )
    }
    
    logger.error(f"PRIVACY ALERT: {json.dumps(alert_data)}")