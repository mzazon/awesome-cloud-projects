import base64
import json
import logging
import os
from google.cloud import compute_v1
from google.cloud import resource_manager
from google.cloud import securitycenter
from google.cloud import logging as cloud_logging
from datetime import datetime

def main(event, context):
    """Automated remediation function for critical security threats."""
    
    # Decode security finding from Pub/Sub
    message_data = base64.b64decode(event['data']).decode('utf-8')
    security_finding = json.loads(message_data)
    
    finding_name = security_finding.get('name', 'Unknown')
    category = security_finding.get('category', 'Unknown')
    resource_name = security_finding.get('resourceName', '')
    
    logging.info(f"Executing remediation for finding: {finding_name}")
    logging.info(f"Category: {category}, Resource: {resource_name}")
    
    # Determine remediation actions based on finding category
    remediation_actions = []
    
    if category == 'PRIVILEGE_ESCALATION':
        remediation_actions.extend(remediate_privilege_escalation(security_finding))
    elif category == 'MALWARE':
        remediation_actions.extend(remediate_malware_detection(security_finding))
    elif category == 'DATA_EXFILTRATION':
        remediation_actions.extend(remediate_data_exfiltration(security_finding))
    elif category == 'NETWORK_INTRUSION':
        remediation_actions.extend(remediate_network_intrusion(security_finding))
    else:
        remediation_actions.append(f"Generic isolation applied for category: {category}")
        apply_generic_isolation(security_finding)
    
    # Log all remediation actions
    log_remediation_actions(finding_name, remediation_actions)
    
    return f"Remediation completed for: {finding_name}"

def remediate_privilege_escalation(finding):
    """Remediate privilege escalation attacks."""
    actions = []
    
    # Extract suspicious IAM members from finding
    source_properties = finding.get('sourceProperties', {})
    suspicious_members = source_properties.get('suspiciousMembers', [])
    
    project_id = "${project_id}"
    
    for member in suspicious_members:
        try:
            # Remove suspicious IAM bindings
            remove_iam_member(project_id, member)
            actions.append(f"Removed suspicious IAM member: {member}")
        except Exception as e:
            logging.error(f"Failed to remove IAM member {member}: {str(e)}")
            actions.append(f"Failed to remove IAM member: {member}")
    
    return actions

def remediate_malware_detection(finding):
    """Remediate malware detection on compute instances."""
    actions = []
    resource_name = finding.get('resourceName', '')
    
    if 'instances/' in resource_name:
        try:
            # Parse instance details from resource name
            instance_name = resource_name.split('/')[-1]
            zone = resource_name.split('/')[-3] if len(resource_name.split('/')) >= 3 else 'us-central1-a'
            project_id = "${project_id}"
            
            # Isolate infected instance
            isolate_compute_instance(project_id, zone, instance_name)
            actions.append(f"Isolated infected instance: {instance_name}")
            
        except Exception as e:
            logging.error(f"Failed to isolate instance: {str(e)}")
            actions.append(f"Failed to isolate instance: {resource_name}")
    
    return actions

def remediate_data_exfiltration(finding):
    """Remediate data exfiltration attempts."""
    actions = []
    
    # Apply network restrictions
    try:
        apply_network_restrictions(finding)
        actions.append("Applied network restrictions to prevent data exfiltration")
    except Exception as e:
        logging.error(f"Failed to apply network restrictions: {str(e)}")
        actions.append("Failed to apply network restrictions")
    
    return actions

def remediate_network_intrusion(finding):
    """Remediate network intrusion attempts."""
    actions = []
    
    # Block suspicious IP addresses
    source_properties = finding.get('sourceProperties', {})
    suspicious_ips = source_properties.get('suspiciousIPs', [])
    
    for ip in suspicious_ips:
        try:
            block_ip_address(ip)
            actions.append(f"Blocked suspicious IP: {ip}")
        except Exception as e:
            logging.error(f"Failed to block IP {ip}: {str(e)}")
            actions.append(f"Failed to block IP: {ip}")
    
    return actions

def apply_generic_isolation(finding):
    """Apply generic isolation measures for unknown threat categories."""
    resource_name = finding.get('resourceName', '')
    
    if 'instances/' in resource_name:
        instance_name = resource_name.split('/')[-1]
        zone = resource_name.split('/')[-3] if len(resource_name.split('/')) >= 3 else 'us-central1-a'
        project_id = "${project_id}"
        isolate_compute_instance(project_id, zone, instance_name)

def remove_iam_member(project_id, member):
    """Remove suspicious IAM member from project."""
    # Implementation would use Cloud Resource Manager API
    # This is a simplified version for demonstration
    logging.info(f"Would remove IAM member: {member} from project: {project_id}")

def isolate_compute_instance(project_id, zone, instance_name):
    """Isolate compute instance by applying restrictive firewall rules."""
    # Implementation would use Compute Engine API
    # This is a simplified version for demonstration
    logging.info(f"Would isolate instance: {instance_name} in zone: {zone}")

def apply_network_restrictions(finding):
    """Apply network-level restrictions."""
    # Implementation would create firewall rules
    logging.info("Would apply network restrictions based on finding details")

def block_ip_address(ip):
    """Block suspicious IP address."""
    # Implementation would create firewall rules
    logging.info(f"Would block IP address: {ip}")

def log_remediation_actions(finding_name, actions):
    """Log all remediation actions for audit purposes."""
    try:
        client = cloud_logging.Client()
        client.setup_logging()
        
        audit_entry = {
            'finding_name': finding_name,
            'remediation_actions': actions,
            'timestamp': str(datetime.utcnow()),
            'function': 'automated-remediation',
            'deployment_id': os.environ.get('DEPLOYMENT_ID', 'default')
        }
        
        logging.info(f"Remediation audit: {json.dumps(audit_entry)}")
    except Exception as e:
        logging.error(f"Failed to log remediation actions: {str(e)}")