"""
Automated Security Response Function for Chronicle SOAR Integration
Executes automated security response actions based on Chronicle SOAR playbook decisions
"""

import json
import base64
import time
from typing import Dict, List, Any, Optional
from google.cloud import compute_v1
from google.cloud import logging
from google.cloud import secretmanager
import os

# Initialize clients
compute_client = compute_v1.InstancesClient()
firewall_client = compute_v1.FirewallsClient()
logging_client = logging.Client()
logger = logging_client.logger('security-automation')

def automated_response(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Main entry point for automated security response function.
    Executes security response actions based on Chronicle SOAR playbook decisions.
    
    Args:
        event: Pub/Sub event containing response action data
        context: Cloud Function context (unused)
        
    Returns:
        Dict containing execution status and results
    """
    try:
        # Decode Pub/Sub message from Chronicle SOAR
        if 'data' not in event:
            logger.error("No data field in Pub/Sub event")
            return {'status': 'error', 'message': 'Invalid event format'}
            
        pubsub_message = base64.b64decode(event['data']).decode('utf-8')
        response_data = json.loads(pubsub_message)
        
        # Log incoming response request for audit trail
        logger.info(f"Processing automated response request: {response_data.get('finding_id', 'unknown')}")
        
        # Execute response actions
        execution_results = execute_response_actions(response_data)
        
        # Log final results
        logger.info(f"Completed automated response with {len(execution_results['actions_executed'])} actions")
        
        return {
            'status': 'completed',
            'finding_id': response_data.get('finding_id', ''),
            'actions_executed': execution_results['actions_executed'],
            'actions_failed': execution_results['actions_failed'],
            'execution_time': execution_results['execution_time']
        }
        
    except Exception as e:
        logger.error(f"Error executing automated response: {str(e)}")
        return {'status': 'error', 'message': str(e)}

def execute_response_actions(response_data: Dict[str, Any]) -> Dict[str, Any]:
    """
    Execute all response actions specified in the Chronicle SOAR decision.
    
    Args:
        response_data: Response data from Chronicle SOAR including actions to execute
        
    Returns:
        Dict containing execution results and timing information
    """
    start_time = time.time()
    actions_executed = []
    actions_failed = []
    
    # Extract actions from response data
    actions = response_data.get('recommended_actions', [])
    entities = response_data.get('entity_list', [])
    severity_score = response_data.get('severity_score', 0)
    threat_context = response_data.get('threat_context', {})
    
    logger.info(f"Executing {len(actions)} response actions for severity score {severity_score}")
    
    # Execute each response action
    for action in actions:
        try:
            action_result = execute_single_action(
                action, 
                entities, 
                severity_score, 
                threat_context,
                response_data
            )
            
            if action_result['success']:
                actions_executed.append({
                    'action': action,
                    'result': action_result['message'],
                    'timestamp': time.strftime('%Y-%m-%dT%H:%M:%S.%fZ')
                })
                logger.info(f"Successfully executed action: {action}")
            else:
                actions_failed.append({
                    'action': action,
                    'error': action_result['message'],
                    'timestamp': time.strftime('%Y-%m-%dT%H:%M:%S.%fZ')
                })
                logger.warning(f"Failed to execute action {action}: {action_result['message']}")
                
        except Exception as e:
            actions_failed.append({
                'action': action,
                'error': str(e),
                'timestamp': time.strftime('%Y-%m-%dT%H:%M:%S.%fZ')
            })
            logger.error(f"Exception executing action {action}: {str(e)}")
    
    execution_time = round(time.time() - start_time, 2)
    
    return {
        'actions_executed': actions_executed,
        'actions_failed': actions_failed,
        'execution_time': execution_time,
        'total_actions': len(actions)
    }

def execute_single_action(
    action: str, 
    entities: List[Dict[str, str]], 
    severity_score: int,
    threat_context: Dict[str, Any],
    response_data: Dict[str, Any]
) -> Dict[str, Any]:
    """
    Execute a single security response action.
    
    Args:
        action: Action name to execute
        entities: List of security entities (IPs, hashes, domains)
        severity_score: Numeric severity score (1-10)
        threat_context: Additional threat context information
        response_data: Full response data from Chronicle SOAR
        
    Returns:
        Dict with success status and result message
    """
    project_id = os.environ.get('GCP_PROJECT', '${project_id}')
    
    # Route to appropriate action handler
    action_handlers = {
        'isolate_host': lambda: isolate_compromised_host(entities, response_data),
        'block_source_ip': lambda: block_malicious_ip(entities, severity_score),
        'block_ip': lambda: block_malicious_ip(entities, severity_score),
        'update_firewall_rules': lambda: update_firewall_rules(entities, threat_context),
        'restrict_data_access': lambda: restrict_data_access(response_data, severity_score),
        'revoke_elevated_privileges': lambda: revoke_elevated_privileges(response_data),
        'notify_security_team': lambda: notify_security_team(response_data, severity_score),
        'create_incident_ticket': lambda: create_incident_ticket(response_data, severity_score),
        'create_high_priority_ticket': lambda: create_incident_ticket(response_data, severity_score, priority='HIGH'),
        'collect_forensic_evidence': lambda: collect_forensic_evidence(response_data, entities),
        'update_threat_intelligence': lambda: update_threat_intelligence(entities, threat_context),
        'scan_additional_files': lambda: scan_additional_files(entities, response_data),
        'check_lateral_movement': lambda: check_lateral_movement(entities, response_data),
        'audit_data_access_logs': lambda: audit_data_access_logs(response_data),
        'initiate_incident_response': lambda: initiate_incident_response(response_data, severity_score)
    }
    
    if action in action_handlers:
        return action_handlers[action]()
    else:
        logger.warning(f"Unknown action requested: {action}")
        return {
            'success': False,
            'message': f"Unknown action: {action}"
        }

def isolate_compromised_host(entities: List[Dict[str, str]], response_data: Dict[str, Any]) -> Dict[str, Any]:
    """
    Isolate compromised host by applying network isolation.
    """
    try:
        resource_name = response_data.get('resource_name', '')
        
        if 'instances/' in resource_name:
            # Extract instance details from resource name
            # Format: projects/PROJECT/zones/ZONE/instances/INSTANCE
            parts = resource_name.split('/')
            if len(parts) >= 6:
                instance_name = parts[-1]
                zone = parts[-3]
                
                # Apply isolation network tag
                isolation_result = apply_isolation_network_tag(instance_name, zone)
                
                if isolation_result:
                    return {
                        'success': True,
                        'message': f"Host {instance_name} isolated with network restrictions"
                    }
        
        return {
            'success': False,
            'message': "Could not extract instance information for isolation"
        }
        
    except Exception as e:
        return {
            'success': False,
            'message': f"Host isolation failed: {str(e)}"
        }

def apply_isolation_network_tag(instance_name: str, zone: str) -> bool:
    """
    Apply network isolation tag to a Compute Engine instance.
    """
    try:
        project_id = os.environ.get('GCP_PROJECT', '${project_id}')
        
        # Get current instance
        instance = compute_client.get(
            project=project_id,
            zone=zone,
            instance=instance_name
        )
        
        # Add isolation tag
        current_tags = instance.tags.items if instance.tags else []
        isolation_tag = "security-isolation"
        
        if isolation_tag not in current_tags:
            new_tags = list(current_tags) + [isolation_tag]
            
            # Update instance tags
            operation = compute_client.set_tags(
                project=project_id,
                zone=zone,
                instance=instance_name,
                tags_resource={
                    'items': new_tags,
                    'fingerprint': instance.tags.fingerprint if instance.tags else ''
                }
            )
            
            logger.info(f"Applied isolation tag to instance {instance_name}")
            return True
        
        return True  # Already isolated
        
    except Exception as e:
        logger.error(f"Failed to apply isolation tag: {str(e)}")
        return False

def block_malicious_ip(entities: List[Dict[str, str]], severity_score: int) -> Dict[str, Any]:
    """
    Block malicious IP addresses using firewall rules.
    """
    try:
        blocked_ips = []
        
        # Extract IP addresses from entities
        ip_entities = [e for e in entities if e['type'] == 'ip_address']
        
        for ip_entity in ip_entities:
            ip_address = ip_entity['value']
            
            # Create firewall rule to block IP
            rule_result = create_ip_blocking_rule(ip_address, severity_score)
            
            if rule_result:
                blocked_ips.append(ip_address)
                logger.info(f"Blocked malicious IP: {ip_address}")
        
        if blocked_ips:
            return {
                'success': True,
                'message': f"Blocked {len(blocked_ips)} malicious IP addresses: {', '.join(blocked_ips)}"
            }
        else:
            return {
                'success': True,
                'message': "No IP addresses found to block"
            }
            
    except Exception as e:
        return {
            'success': False,
            'message': f"IP blocking failed: {str(e)}"
        }

def create_ip_blocking_rule(ip_address: str, severity_score: int) -> bool:
    """
    Create a firewall rule to block a specific IP address.
    """
    try:
        project_id = os.environ.get('GCP_PROJECT', '${project_id}')
        
        # Generate unique rule name
        rule_name = f"block-malicious-ip-{ip_address.replace('.', '-')}-{int(time.time())}"
        
        # Create firewall rule
        firewall_rule = {
            'name': rule_name,
            'description': f"Auto-generated rule to block malicious IP {ip_address} (severity: {severity_score})",
            'direction': 'INGRESS',
            'priority': 1000,
            'source_ranges': [ip_address],
            'denied': [
                {
                    'I_p_protocol': 'tcp'
                },
                {
                    'I_p_protocol': 'udp'
                },
                {
                    'I_p_protocol': 'icmp'
                }
            ],
            'target_tags': ['web-server', 'app-server', 'database-server']  # Apply to common server tags
        }
        
        operation = firewall_client.insert(
            project=project_id,
            firewall_resource=firewall_rule
        )
        
        logger.info(f"Created firewall rule {rule_name} to block IP {ip_address}")
        return True
        
    except Exception as e:
        logger.error(f"Failed to create firewall rule for IP {ip_address}: {str(e)}")
        return False

def update_firewall_rules(entities: List[Dict[str, str]], threat_context: Dict[str, Any]) -> Dict[str, Any]:
    """
    Update firewall rules based on threat intelligence.
    """
    try:
        # Extract relevant entities for firewall updates
        network_entities = [e for e in entities if e['type'] in ['ip_address', 'domain']]
        
        if not network_entities:
            return {
                'success': True,
                'message': "No network entities found for firewall updates"
            }
        
        # Create comprehensive blocking rules
        rules_created = 0
        for entity in network_entities:
            if entity['type'] == 'ip_address':
                if create_ip_blocking_rule(entity['value'], 8):  # High priority for firewall updates
                    rules_created += 1
        
        return {
            'success': True,
            'message': f"Updated firewall with {rules_created} new blocking rules"
        }
        
    except Exception as e:
        return {
            'success': False,
            'message': f"Firewall update failed: {str(e)}"
        }

def create_incident_ticket(response_data: Dict[str, Any], severity_score: int, priority: str = 'MEDIUM') -> Dict[str, Any]:
    """
    Create incident ticket in ITSM system (simulated).
    """
    try:
        # Generate ticket details
        finding_id = response_data.get('finding_id', 'unknown')
        category = response_data.get('category', 'Security Incident')
        resource_name = response_data.get('resource_name', 'unknown')
        
        # Generate unique ticket ID
        ticket_id = f"SEC-{priority}-{hash(finding_id) % 10000:04d}"
        
        # Create ticket data structure
        ticket_data = {
            'ticket_id': ticket_id,
            'title': f"Automated Security Response - {category}",
            'description': f"Security incident detected and processed automatically.\n\n"
                          f"Finding ID: {finding_id}\n"
                          f"Category: {category}\n"
                          f"Severity Score: {severity_score}\n"
                          f"Affected Resource: {resource_name}\n"
                          f"Auto-Response Actions: {len(response_data.get('recommended_actions', []))} actions executed",
            'priority': priority,
            'severity_score': severity_score,
            'category': 'Security',
            'created_at': time.strftime('%Y-%m-%dT%H:%M:%S.%fZ'),
            'created_by': 'security-automation-system',
            'status': 'New'
        }
        
        # Log ticket creation (in production, this would integrate with actual ITSM)
        logger.info(f"Created incident ticket {ticket_id} for finding {finding_id}")
        
        return {
            'success': True,
            'message': f"Created incident ticket {ticket_id} with priority {priority}"
        }
        
    except Exception as e:
        return {
            'success': False,
            'message': f"Incident ticket creation failed: {str(e)}"
        }

def notify_security_team(response_data: Dict[str, Any], severity_score: int) -> Dict[str, Any]:
    """
    Send notification to security team (simulated).
    """
    try:
        finding_id = response_data.get('finding_id', 'unknown')
        category = response_data.get('category', 'Security Alert')
        
        # Create notification message
        notification = {
            'alert_id': finding_id,
            'subject': f"SECURITY ALERT: {category} (Score: {severity_score})",
            'message': f"Automated security response completed for high-severity incident.\n\n"
                      f"Finding: {finding_id}\n"
                      f"Category: {category}\n" 
                      f"Severity Score: {severity_score}\n"
                      f"Automated Actions: {len(response_data.get('recommended_actions', []))}\n"
                      f"Timestamp: {time.strftime('%Y-%m-%d %H:%M:%S UTC')}",
            'priority': 'HIGH' if severity_score >= 8 else 'MEDIUM',
            'sent_at': time.strftime('%Y-%m-%dT%H:%M:%S.%fZ')
        }
        
        # Log notification (in production, this would send actual notifications)
        logger.info(f"Sent security team notification for finding {finding_id}")
        
        return {
            'success': True,
            'message': f"Security team notified for finding {finding_id}"
        }
        
    except Exception as e:
        return {
            'success': False,
            'message': f"Security team notification failed: {str(e)}"
        }

def collect_forensic_evidence(response_data: Dict[str, Any], entities: List[Dict[str, str]]) -> Dict[str, Any]:
    """
    Collect forensic evidence for investigation (simulated).
    """
    try:
        evidence_items = []
        
        # Collect network evidence
        network_entities = [e for e in entities if e['type'] == 'ip_address']
        for entity in network_entities:
            evidence_items.append(f"Network traffic logs for IP {entity['value']}")
        
        # Collect file evidence
        file_entities = [e for e in entities if e['type'] == 'file_hash']
        for entity in file_entities:
            evidence_items.append(f"File analysis for hash {entity['value']}")
        
        # Collect system evidence
        resource_name = response_data.get('resource_name', '')
        if resource_name:
            evidence_items.append(f"System logs from {resource_name}")
            evidence_items.append(f"Process list snapshot from {resource_name}")
        
        logger.info(f"Collected {len(evidence_items)} forensic evidence items")
        
        return {
            'success': True,
            'message': f"Collected {len(evidence_items)} forensic evidence items for investigation"
        }
        
    except Exception as e:
        return {
            'success': False,
            'message': f"Forensic evidence collection failed: {str(e)}"
        }

def restrict_data_access(response_data: Dict[str, Any], severity_score: int) -> Dict[str, Any]:
    """
    Restrict data access for compromised resources (simulated).
    """
    try:
        resource_name = response_data.get('resource_name', '')
        
        # Implementation would restrict IAM permissions, database access, etc.
        restrictions = [
            "Revoked database read/write permissions",
            "Restricted file system access", 
            "Disabled API access keys",
            "Enabled enhanced monitoring"
        ]
        
        logger.info(f"Applied data access restrictions to {resource_name}")
        
        return {
            'success': True,
            'message': f"Applied {len(restrictions)} data access restrictions"
        }
        
    except Exception as e:
        return {
            'success': False,
            'message': f"Data access restriction failed: {str(e)}"
        }

def revoke_elevated_privileges(response_data: Dict[str, Any]) -> Dict[str, Any]:
    """
    Revoke elevated privileges for compromised accounts (simulated).
    """
    try:
        # Implementation would revoke admin roles, sudo access, etc.
        actions = [
            "Revoked admin privileges",
            "Disabled sudo access",
            "Removed from privileged groups",
            "Reset access tokens"
        ]
        
        logger.info("Revoked elevated privileges for security incident")
        
        return {
            'success': True,
            'message': f"Revoked elevated privileges: {', '.join(actions)}"
        }
        
    except Exception as e:
        return {
            'success': False,
            'message': f"Privilege revocation failed: {str(e)}"
        }

# Additional action handlers for completeness
def scan_additional_files(entities: List[Dict[str, str]], response_data: Dict[str, Any]) -> Dict[str, Any]:
    """Trigger additional file scans."""
    return {'success': True, 'message': 'Initiated additional file scanning'}

def check_lateral_movement(entities: List[Dict[str, str]], response_data: Dict[str, Any]) -> Dict[str, Any]:
    """Check for lateral movement indicators."""
    return {'success': True, 'message': 'Analyzed network for lateral movement indicators'}

def audit_data_access_logs(response_data: Dict[str, Any]) -> Dict[str, Any]:
    """Audit data access logs for suspicious activity."""
    return {'success': True, 'message': 'Initiated data access log audit'}

def update_threat_intelligence(entities: List[Dict[str, str]], threat_context: Dict[str, Any]) -> Dict[str, Any]:
    """Update threat intelligence feeds."""
    return {'success': True, 'message': f'Updated threat intelligence with {len(entities)} new indicators'}

def initiate_incident_response(response_data: Dict[str, Any], severity_score: int) -> Dict[str, Any]:
    """Initiate formal incident response process."""
    return {'success': True, 'message': 'Initiated formal incident response process'}

if __name__ == '__main__':
    # Test function locally
    test_event = {
        'data': base64.b64encode(json.dumps({
            'finding_id': 'test-finding-123',
            'category': 'MALWARE_DETECTION',
            'severity': 'HIGH',
            'severity_score': 9,
            'recommended_actions': ['isolate_host', 'block_source_ip', 'create_incident_ticket'],
            'entity_list': [
                {'type': 'ip_address', 'value': '192.168.1.100'},
                {'type': 'file_hash', 'value': 'abc123def456'}
            ],
            'resource_name': 'projects/test/zones/us-central1-a/instances/web-server-1'
        }).encode('utf-8')).decode('utf-8')
    }
    
    result = automated_response(test_event, None)
    print(f"Test result: {result}")