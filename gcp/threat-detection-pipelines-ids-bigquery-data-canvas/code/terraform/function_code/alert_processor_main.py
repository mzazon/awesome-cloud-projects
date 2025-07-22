"""
Cloud Function for processing high-severity security alerts.

This function receives security alerts for high-severity threats,
implements automated response workflows, and integrates with
external security systems for comprehensive incident response.
"""

import json
import base64
import logging
import os
from datetime import datetime
from typing import Dict, Any, List, Optional

from google.cloud import pubsub_v1
from google.cloud import compute_v1
from google.cloud import logging as cloud_logging

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Initialize Google Cloud clients
publisher = pubsub_v1.PublisherClient()
compute_client = compute_v1.InstancesClient()

# Configure Cloud Logging
cloud_logging_client = cloud_logging.Client()
cloud_logging_client.setup_logging()

# Environment variables
PROJECT_ID = os.environ.get('PROJECT_ID')


def validate_alert_data(alert: Dict[str, Any]) -> bool:
    """
    Validate that the alert data contains required fields.
    
    Args:
        alert: Dictionary containing security alert data
        
    Returns:
        bool: True if data is valid, False otherwise
    """
    required_fields = ['alert_type', 'finding_id', 'severity']
    
    for field in required_fields:
        if not alert.get(field):
            logger.warning(f"Missing required field in alert: {field}")
            return False
    
    # Validate alert type
    valid_alert_types = [
        'HIGH_SEVERITY_THREAT',
        'CRITICAL_THREAT',
        'MALWARE_DETECTION',
        'SUSPICIOUS_ACTIVITY'
    ]
    
    if alert.get('alert_type') not in valid_alert_types:
        logger.warning(f"Invalid alert type: {alert.get('alert_type')}")
        return False
    
    return True


def classify_threat_response(alert: Dict[str, Any]) -> str:
    """
    Classify the type of response needed based on the threat.
    
    Args:
        alert: Security alert data
        
    Returns:
        str: Response classification (immediate, urgent, standard, monitoring)
    """
    threat_type = alert.get('threat_type', '').lower()
    severity = alert.get('severity', 'LOW')
    
    # Critical threats requiring immediate response
    critical_indicators = ['malware', 'ransomware', 'command and control', 'data exfiltration']
    if any(indicator in threat_type for indicator in critical_indicators):
        return 'immediate'
    
    # High severity threats requiring urgent response
    if severity in ['HIGH', 'CRITICAL']:
        return 'urgent'
    
    # Medium severity threats requiring standard response
    if severity == 'MEDIUM':
        return 'standard'
    
    # Low severity threats requiring monitoring
    return 'monitoring'


def get_automated_response_actions(alert: Dict[str, Any]) -> List[Dict[str, Any]]:
    """
    Determine automated response actions based on the threat type and severity.
    
    Args:
        alert: Security alert data
        
    Returns:
        List[Dict]: List of automated response actions to execute
    """
    threat_type = alert.get('threat_type', '').lower()
    severity = alert.get('severity', 'LOW')
    source_ip = alert.get('source_ip', '')
    
    actions = []
    
    # Malware detection responses
    if 'malware' in threat_type:
        actions.extend([
            {
                'action_type': 'log_critical',
                'message': f'CRITICAL MALWARE DETECTED: {threat_type} from {source_ip}',
                'priority': 1
            },
            {
                'action_type': 'notify_security_team',
                'message': f'Immediate investigation required for malware detection',
                'priority': 1
            }
        ])
        
        # For critical malware, consider VM isolation
        if severity == 'CRITICAL':
            actions.append({
                'action_type': 'recommend_vm_isolation',
                'target_ips': [alert.get('destination_ip')],
                'reason': 'Critical malware detection',
                'priority': 1
            })
    
    # Port scan responses
    elif 'scan' in threat_type:
        actions.extend([
            {
                'action_type': 'log_warning',
                'message': f'SUSPICIOUS PORT SCAN: {threat_type} from {source_ip}',
                'priority': 2
            },
            {
                'action_type': 'monitor_source_ip',
                'target_ip': source_ip,
                'duration_hours': 24,
                'priority': 2
            }
        ])
    
    # DDoS/DoS responses
    elif any(attack in threat_type for attack in ['dos', 'ddos']):
        actions.extend([
            {
                'action_type': 'log_critical',
                'message': f'AVAILABILITY THREAT DETECTED: {threat_type} from {source_ip}',
                'priority': 1
            },
            {
                'action_type': 'recommend_rate_limiting',
                'target_ip': source_ip,
                'priority': 1
            }
        ])
    
    # Command and Control responses
    elif 'command and control' in threat_type:
        actions.extend([
            {
                'action_type': 'log_critical',
                'message': f'COMMAND AND CONTROL DETECTED: {threat_type}',
                'priority': 1
            },
            {
                'action_type': 'emergency_notification',
                'message': 'Potential APT activity detected - immediate investigation required',
                'priority': 1
            },
            {
                'action_type': 'recommend_network_isolation',
                'target_ips': [alert.get('destination_ip')],
                'priority': 1
            }
        ])
    
    # High/Critical severity generic responses
    if severity in ['HIGH', 'CRITICAL']:
        actions.append({
            'action_type': 'escalate_to_soc',
            'alert_data': alert,
            'urgency': 'immediate' if severity == 'CRITICAL' else 'high',
            'priority': 1
        })
    
    return sorted(actions, key=lambda x: x.get('priority', 3))


def execute_logging_action(action: Dict[str, Any]) -> bool:
    """
    Execute logging-based response actions.
    
    Args:
        action: Action configuration
        
    Returns:
        bool: True if successful, False otherwise
    """
    try:
        action_type = action.get('action_type')
        message = action.get('message', '')
        
        if action_type == 'log_critical':
            logger.critical(message)
        elif action_type == 'log_warning':
            logger.warning(message)
        elif action_type == 'log_info':
            logger.info(message)
        else:
            logger.info(f"Unknown logging action: {action_type} - {message}")
        
        return True
        
    except Exception as e:
        logger.error(f"Error executing logging action: {str(e)}")
        return False


def execute_notification_action(action: Dict[str, Any]) -> bool:
    """
    Execute notification-based response actions.
    
    Args:
        action: Action configuration
        
    Returns:
        bool: True if successful, False otherwise
    """
    try:
        action_type = action.get('action_type')
        message = action.get('message', '')
        
        # In a production environment, this would integrate with:
        # - Email notification systems
        # - Slack/Teams webhooks
        # - PagerDuty/VictorOps
        # - SMS alerting systems
        
        if action_type == 'notify_security_team':
            logger.critical(f"SECURITY TEAM NOTIFICATION: {message}")
            # TODO: Integrate with actual notification system
            
        elif action_type == 'emergency_notification':
            logger.critical(f"EMERGENCY ALERT: {message}")
            # TODO: Integrate with emergency response system
            
        elif action_type == 'escalate_to_soc':
            urgency = action.get('urgency', 'medium')
            logger.critical(f"SOC ESCALATION ({urgency.upper()}): {message}")
            # TODO: Integrate with SOC ticketing system
        
        return True
        
    except Exception as e:
        logger.error(f"Error executing notification action: {str(e)}")
        return False


def execute_monitoring_action(action: Dict[str, Any]) -> bool:
    """
    Execute monitoring-based response actions.
    
    Args:
        action: Action configuration
        
    Returns:
        bool: True if successful, False otherwise
    """
    try:
        action_type = action.get('action_type')
        
        if action_type == 'monitor_source_ip':
            target_ip = action.get('target_ip', '')
            duration = action.get('duration_hours', 24)
            logger.warning(f"ENHANCED MONITORING: IP {target_ip} for {duration} hours")
            # TODO: Integrate with monitoring system to flag IP for enhanced tracking
            
        elif action_type == 'recommend_rate_limiting':
            target_ip = action.get('target_ip', '')
            logger.warning(f"RATE LIMITING RECOMMENDED: IP {target_ip}")
            # TODO: Integrate with firewall/load balancer for automatic rate limiting
            
        elif action_type == 'recommend_vm_isolation':
            target_ips = action.get('target_ips', [])
            reason = action.get('reason', 'Security threat')
            logger.critical(f"VM ISOLATION RECOMMENDED: IPs {target_ips} - Reason: {reason}")
            # TODO: Integrate with VM management system for isolation
            
        elif action_type == 'recommend_network_isolation':
            target_ips = action.get('target_ips', [])
            logger.critical(f"NETWORK ISOLATION RECOMMENDED: IPs {target_ips}")
            # TODO: Integrate with network security controls
        
        return True
        
    except Exception as e:
        logger.error(f"Error executing monitoring action: {str(e)}")
        return False


def execute_response_actions(actions: List[Dict[str, Any]]) -> Dict[str, int]:
    """
    Execute all automated response actions.
    
    Args:
        actions: List of response actions to execute
        
    Returns:
        Dict: Execution results summary
    """
    results = {
        'total_actions': len(actions),
        'successful': 0,
        'failed': 0,
        'skipped': 0
    }
    
    for action in actions:
        try:
            action_type = action.get('action_type', '')
            
            if action_type.startswith('log_'):
                success = execute_logging_action(action)
            elif action_type in ['notify_security_team', 'emergency_notification', 'escalate_to_soc']:
                success = execute_notification_action(action)
            elif action_type.startswith(('monitor_', 'recommend_')):
                success = execute_monitoring_action(action)
            else:
                logger.warning(f"Unknown action type: {action_type}")
                results['skipped'] += 1
                continue
            
            if success:
                results['successful'] += 1
            else:
                results['failed'] += 1
                
        except Exception as e:
            logger.error(f"Error executing action {action.get('action_type', 'unknown')}: {str(e)}")
            results['failed'] += 1
    
    return results


def process_security_alert(event: Dict[str, Any], context: Any) -> None:
    """
    Main Cloud Function entry point for processing security alerts.
    
    This function is triggered by Pub/Sub messages containing high-severity
    security alerts. It implements automated response workflows and
    integrates with external security systems.
    
    Args:
        event: Pub/Sub event containing the security alert data
        context: Cloud Function context (unused)
    """
    try:
        # Decode Pub/Sub message
        if 'data' not in event:
            logger.error("No data in Pub/Sub message")
            return
        
        message_data = base64.b64decode(event['data']).decode('utf-8')
        alert = json.loads(message_data)
        
        alert_id = alert.get('finding_id', 'unknown')
        logger.info(f"Processing security alert: {alert_id}")
        
        # Validate alert data
        if not validate_alert_data(alert):
            logger.error("Invalid alert data, skipping processing")
            return
        
        # Log alert details
        alert_type = alert.get('alert_type')
        threat_type = alert.get('threat_type', 'Unknown')
        severity = alert.get('severity')
        source_ip = alert.get('source_ip', 'Unknown')
        
        logger.info(f"Alert Details - Type: {alert_type}, Threat: {threat_type}, "
                   f"Severity: {severity}, Source: {source_ip}")
        
        # Classify threat response level
        response_level = classify_threat_response(alert)
        logger.info(f"Response level classified as: {response_level}")
        
        # Get automated response actions
        response_actions = get_automated_response_actions(alert)
        logger.info(f"Identified {len(response_actions)} response actions")
        
        # Execute response actions
        if response_actions:
            execution_results = execute_response_actions(response_actions)
            logger.info(f"Response execution completed - "
                       f"Total: {execution_results['total_actions']}, "
                       f"Successful: {execution_results['successful']}, "
                       f"Failed: {execution_results['failed']}, "
                       f"Skipped: {execution_results['skipped']}")
        else:
            logger.info("No automated response actions identified for this alert")
        
        # Create incident record (for audit and compliance)
        incident_record = {
            'incident_id': f"INC-{alert_id}",
            'timestamp': datetime.utcnow().isoformat(),
            'alert_data': alert,
            'response_level': response_level,
            'actions_taken': len(response_actions),
            'status': 'automated_response_completed'
        }
        
        logger.info(f"Incident record created: {incident_record['incident_id']}")
        
        # Log successful processing
        logger.info(f"Security alert processing completed for: {alert_id}")
        
    except json.JSONDecodeError as e:
        logger.error(f"Failed to decode JSON alert message: {str(e)}")
        raise
    except Exception as e:
        logger.error(f"Error processing security alert: {str(e)}")
        raise


# For local testing
if __name__ == "__main__":
    # Sample test data
    test_event = {
        'data': base64.b64encode(json.dumps({
            "alert_type": "HIGH_SEVERITY_THREAT",
            "finding_id": "test-alert-001",
            "threat_type": "Malware Detection",
            "source_ip": "203.0.113.1",
            "destination_ip": "10.0.1.5",
            "severity": "HIGH",
            "timestamp": "2025-07-12T10:00:00Z",
            "details": {"port": 80, "payload": "malicious"},
            "recommended_actions": ["Isolate affected systems", "Run antivirus scan"]
        }).encode('utf-8')).decode('utf-8')
    }
    
    process_security_alert(test_event, None)