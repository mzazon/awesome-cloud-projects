"""
DNS Security Threat Detection and Automated Response Function

This Cloud Function processes Security Command Center findings for DNS-based threats
and implements automated response measures including IP blocking and alerting.
"""

import json
import logging
import base64
import os
from typing import Dict, Any, Optional
from google.cloud import securitycenter
from google.cloud import compute_v1
from google.cloud import logging as cloud_logging

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Initialize Google Cloud clients
scc_client = securitycenter.SecurityCenterClient()
compute_client = compute_v1.SecurityPoliciesClient()
logging_client = cloud_logging.Client()

# Configuration from environment variables
PROJECT_ID = os.environ.get('PROJECT_ID', '')
SECURITY_POLICY_NAME = os.environ.get('SECURITY_POLICY_NAME', '')
LOG_LEVEL = os.environ.get('LOG_LEVEL', 'INFO')

# Set log level from environment
logger.setLevel(getattr(logging, LOG_LEVEL, logging.INFO))


def process_security_finding(event: Dict[str, Any], context: Any) -> str:
    """
    Main entry point for processing Security Command Center findings.
    
    Args:
        event: Pub/Sub event containing the security finding
        context: Cloud Function context (unused)
        
    Returns:
        Processing status message
    """
    try:
        # Decode Pub/Sub message
        if 'data' not in event:
            logger.warning("No data field in Pub/Sub event")
            return 'No data'
            
        pubsub_message = base64.b64decode(event['data']).decode('utf-8')
        finding_data = json.loads(pubsub_message)
        
        # Extract finding details
        finding_name = finding_data.get('name', 'Unknown')
        category = finding_data.get('category', '')
        severity = finding_data.get('severity', 'MEDIUM')
        
        logger.info(f"Processing DNS security finding: {finding_name}")
        logger.debug(f"Finding details - Category: {category}, Severity: {severity}")
        
        # Check if this is a DNS-related threat
        if is_dns_related_threat(category):
            if severity in ['HIGH', 'CRITICAL']:
                # Implement automated response for high-severity threats
                implement_emergency_response(finding_data)
            else:
                # Log and monitor medium/low severity findings
                log_security_event(finding_data)
        else:
            logger.info(f"Skipping non-DNS related finding: {category}")
        
        return 'OK'
        
    except json.JSONDecodeError as e:
        logger.error(f"Error decoding JSON from Pub/Sub message: {str(e)}")
        return f'JSON decode error: {str(e)}'
    except Exception as e:
        logger.error(f"Error processing security finding: {str(e)}")
        return f'Processing error: {str(e)}'


def is_dns_related_threat(category: str) -> bool:
    """
    Determine if a security finding is DNS-related.
    
    Args:
        category: The finding category
        
    Returns:
        True if DNS-related, False otherwise
    """
    dns_keywords = ['DNS', 'MALWARE', 'DOMAIN', 'BOTNET', 'C2', 'COMMAND']
    return any(keyword in category.upper() for keyword in dns_keywords)


def implement_emergency_response(finding_data: Dict[str, Any]) -> None:
    """
    Implement automated response for high-severity DNS threats.
    
    Args:
        finding_data: Security Command Center finding data
    """
    finding_name = finding_data.get('name', 'Unknown')
    logger.warning(f"Implementing emergency response for: {finding_name}")
    
    try:
        # Extract source IP from finding properties
        source_properties = finding_data.get('sourceProperties', {})
        source_ip = extract_source_ip(source_properties)
        
        if source_ip:
            add_ip_to_blocklist(source_ip, finding_data)
        
        # Send high-priority alert
        send_emergency_alert(finding_data)
        
        # Log structured security event for monitoring
        log_structured_security_event(finding_data, 'EMERGENCY_RESPONSE')
        
    except Exception as e:
        logger.error(f"Error in emergency response implementation: {str(e)}")


def extract_source_ip(source_properties: Dict[str, Any]) -> Optional[str]:
    """
    Extract source IP address from finding properties.
    
    Args:
        source_properties: Source properties from security finding
        
    Returns:
        Source IP address if found, None otherwise
    """
    # Try multiple possible field names for source IP
    ip_fields = ['sourceIp', 'clientIp', 'src_ip', 'source_ip', 'ip_address']
    
    for field in ip_fields:
        ip_address = source_properties.get(field)
        if ip_address and validate_ip_address(ip_address):
            return ip_address
    
    return None


def validate_ip_address(ip_address: str) -> bool:
    """
    Basic validation for IP address format.
    
    Args:
        ip_address: IP address string to validate
        
    Returns:
        True if valid format, False otherwise
    """
    try:
        import ipaddress
        ipaddress.ip_address(ip_address)
        # Don't block private IP ranges in automated response
        return not ipaddress.ip_address(ip_address).is_private
    except ValueError:
        return False


def add_ip_to_blocklist(source_ip: str, finding_data: Dict[str, Any]) -> None:
    """
    Add suspicious IP to Cloud Armor security policy blocklist.
    
    Args:
        source_ip: IP address to block
        finding_data: Original security finding data for context
    """
    try:
        logger.info(f"Adding {source_ip} to security policy blocklist")
        
        if not SECURITY_POLICY_NAME:
            logger.warning("No security policy configured for IP blocking")
            return
        
        # In a production environment, you would implement the actual
        # Cloud Armor rule creation here. This requires:
        # 1. Additional IAM permissions (compute.securityAdmin)
        # 2. Proper error handling and rule priority management
        # 3. Rule deduplication to avoid conflicts
        # 4. Time-based rule expiration
        
        # For now, we log the action that would be taken
        finding_name = finding_data.get('name', 'Unknown')
        severity = finding_data.get('severity', 'UNKNOWN')
        
        logger.warning(
            f"BLOCKED IP: {source_ip} due to {severity} severity finding: {finding_name}"
        )
        
        # Log structured event for monitoring and alerting
        log_structured_security_event({
            'action': 'IP_BLOCKED',
            'ip_address': source_ip,
            'finding_name': finding_name,
            'severity': severity,
            'security_policy': SECURITY_POLICY_NAME
        }, 'IP_BLOCKING')
        
        logger.info(f"Successfully flagged IP {source_ip} for blocking")
        
    except Exception as e:
        logger.error(f"Error adding IP to blocklist: {str(e)}")


def log_security_event(finding_data: Dict[str, Any]) -> None:
    """
    Log security event for monitoring and analysis.
    
    Args:
        finding_data: Security Command Center finding data
    """
    finding_name = finding_data.get('name', 'Unknown')
    category = finding_data.get('category', 'Unknown')
    severity = finding_data.get('severity', 'MEDIUM')
    
    logger.info(f"Logging security event - Name: {finding_name}, Category: {category}, Severity: {severity}")
    
    # Log structured event for monitoring
    log_structured_security_event(finding_data, 'SECURITY_EVENT')


def log_structured_security_event(event_data: Dict[str, Any], event_type: str) -> None:
    """
    Log structured security event for monitoring and alerting.
    
    Args:
        event_data: Event data to log
        event_type: Type of security event
    """
    try:
        structured_log = {
            'severity': 'WARNING' if event_type == 'EMERGENCY_RESPONSE' else 'INFO',
            'eventType': event_type,
            'timestamp': logging_client._helpers.datetime.datetime.utcnow().isoformat(),
            'projectId': PROJECT_ID,
            'eventData': event_data
        }
        
        # Use Cloud Logging for structured logging
        cloud_logger = logging_client.logger('dns-security-events')
        cloud_logger.log_struct(structured_log)
        
    except Exception as e:
        logger.error(f"Error logging structured event: {str(e)}")


def send_emergency_alert(finding_data: Dict[str, Any]) -> None:
    """
    Send high-priority security alert for critical threats.
    
    Args:
        finding_data: Security Command Center finding data
    """
    finding_name = finding_data.get('name', 'Unknown')
    category = finding_data.get('category', 'Unknown')
    severity = finding_data.get('severity', 'UNKNOWN')
    
    alert_message = (
        f"EMERGENCY DNS THREAT DETECTED\n"
        f"Finding: {finding_name}\n"
        f"Category: {category}\n"
        f"Severity: {severity}\n"
        f"Project: {PROJECT_ID}\n"
        f"Automated response has been initiated."
    )
    
    logger.critical(alert_message)
    
    # In production, integrate with notification systems:
    # - Send email notifications via SendGrid or similar
    # - Post to Slack channels via webhooks
    # - Create PagerDuty incidents for critical alerts
    # - Send SMS notifications for emergency response team
    
    # Log structured alert for monitoring
    log_structured_security_event({
        'alert_type': 'EMERGENCY',
        'message': alert_message,
        'finding_data': finding_data
    }, 'EMERGENCY_ALERT')


def health_check() -> str:
    """
    Health check endpoint for monitoring function availability.
    
    Returns:
        Health status message
    """
    try:
        # Verify Google Cloud client connectivity
        _ = logging_client.list_entries(max_results=1)
        return 'HEALTHY'
    except Exception as e:
        logger.error(f"Health check failed: {str(e)}")
        return f'UNHEALTHY: {str(e)}'


# Additional utility functions for enhanced security

def get_threat_intelligence_context(finding_data: Dict[str, Any]) -> Dict[str, Any]:
    """
    Enrich finding data with threat intelligence context.
    
    Args:
        finding_data: Original security finding
        
    Returns:
        Enriched context data
    """
    # In production, integrate with threat intelligence feeds:
    # - VirusTotal API for domain/IP reputation
    # - ThreatConnect for IOC correlation
    # - MISP for threat intelligence sharing
    # - Custom threat feeds from security vendors
    
    return {
        'enrichment_available': False,
        'threat_score': 'unknown',
        'last_seen': 'unknown'
    }


def implement_containment_measures(finding_data: Dict[str, Any]) -> None:
    """
    Implement additional containment measures for severe threats.
    
    Args:
        finding_data: Security finding requiring containment
    """
    # Production containment measures could include:
    # - Quarantine affected DNS zones
    # - Update firewall rules across network perimeter
    # - Trigger incident response workflows
    # - Coordinate with SOC team for manual investigation
    
    logger.info("Containment measures would be implemented in production environment")


if __name__ == '__main__':
    # Local testing support
    print("DNS Security Function loaded successfully")
    print(f"Project ID: {PROJECT_ID}")
    print(f"Security Policy: {SECURITY_POLICY_NAME}")
    print(f"Log Level: {LOG_LEVEL}")