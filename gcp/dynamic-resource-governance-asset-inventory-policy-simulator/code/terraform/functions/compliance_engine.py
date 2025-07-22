"""
Compliance Engine Cloud Function
Central orchestrator for governance automation and compliance enforcement.
"""

import json
import base64
import logging
import os
import requests
import time
from typing import Dict, Any, List, Optional
from google.cloud import pubsub_v1
from google.cloud import logging as cloud_logging
from google.cloud import monitoring_v3
from google.cloud import asset_v1

# Configure logging
cloud_logging.Client().setup_logging()
logger = logging.getLogger(__name__)

# Configuration from environment variables
PROJECT_ID = os.environ.get('PROJECT_ID', '${project_id}')
REGION = os.environ.get('REGION', 'us-central1')
COMPLIANCE_POLICIES = json.loads(os.environ.get('COMPLIANCE_POLICIES', '${compliance_policies}'))
POLICY_VALIDATOR_URL = os.environ.get('POLICY_VALIDATOR_URL', '')

def enforce_compliance(cloud_event: Dict[str, Any]) -> Dict[str, Any]:
    """
    Main compliance enforcement function.
    
    Args:
        cloud_event: Cloud Event from Pub/Sub containing compliance data
        
    Returns:
        Dictionary containing enforcement results
    """
    try:
        # Decode Pub/Sub message
        pubsub_message = base64.b64decode(
            cloud_event.data['message']['data']
        ).decode('utf-8')
        
        # Parse compliance data
        compliance_data = json.loads(pubsub_message)
        
        logger.info("Processing compliance enforcement request")
        
        # Extract compliance requirements
        asset_name = compliance_data.get('asset_name', '')
        asset_type = compliance_data.get('asset_type', '')
        risk_level = compliance_data.get('risk_level', 'LOW')
        risk_factors = compliance_data.get('risk_factors', [])
        governance_actions = compliance_data.get('actions', [])
        
        # Determine violations
        violations = identify_compliance_violations(
            asset_name, asset_type, risk_factors, compliance_data
        )
        
        # Apply governance policies
        enforcement_actions = determine_enforcement_actions(
            risk_level, violations, governance_actions
        )
        
        # Execute enforcement actions
        execution_results = execute_enforcement_actions(
            asset_name, asset_type, enforcement_actions, compliance_data
        )
        
        # Record compliance metrics
        record_compliance_metrics(
            asset_name, asset_type, risk_level, violations, execution_results
        )
        
        # Generate compliance report
        compliance_report = generate_compliance_report(
            asset_name, asset_type, risk_level, violations, 
            enforcement_actions, execution_results
        )
        
        return {
            'status': 'success',
            'asset_name': asset_name,
            'asset_type': asset_type,
            'risk_level': risk_level,
            'violations': violations,
            'actions_taken': execution_results,
            'compliance_report': compliance_report
        }
        
    except Exception as e:
        logger.error(f"Error in compliance enforcement: {str(e)}")
        return {
            'status': 'error',
            'message': str(e)
        }

def identify_compliance_violations(asset_name: str, asset_type: str,
                                 risk_factors: List[str], 
                                 compliance_data: Dict[str, Any]) -> List[Dict[str, Any]]:
    """Identify compliance violations based on policies and risk factors."""
    
    violations = []
    
    # Check against configured compliance policies
    for policy_name, policy_config in COMPLIANCE_POLICIES.items():
        if not policy_config.get('enabled', True):
            continue
        
        violation = check_policy_violation(
            policy_name, policy_config, asset_name, asset_type, 
            risk_factors, compliance_data
        )
        
        if violation:
            violations.append(violation)
    
    # Check for general compliance issues
    general_violations = check_general_compliance(
        asset_name, asset_type, risk_factors, compliance_data
    )
    violations.extend(general_violations)
    
    return violations

def check_policy_violation(policy_name: str, policy_config: Dict[str, Any],
                          asset_name: str, asset_type: str,
                          risk_factors: List[str], 
                          compliance_data: Dict[str, Any]) -> Optional[Dict[str, Any]]:
    """Check if a specific policy is violated."""
    
    violation = None
    
    if policy_name == 'public-storage-bucket':
        if (asset_type == 'storage.googleapis.com/Bucket' and 
            'potential_public_access' in risk_factors):
            violation = {
                'policy': policy_name,
                'severity': policy_config.get('risk_level', 'MEDIUM'),
                'description': 'Storage bucket may have public access enabled',
                'asset_name': asset_name,
                'asset_type': asset_type,
                'remediation_required': True
            }
    
    elif policy_name == 'unrestricted-firewall':
        if (asset_type == 'compute.googleapis.com/Firewall' and
            'unrestricted_access' in risk_factors):
            violation = {
                'policy': policy_name,
                'severity': policy_config.get('risk_level', 'HIGH'),
                'description': 'Firewall rule allows unrestricted access',
                'asset_name': asset_name,
                'asset_type': asset_type,
                'remediation_required': True
            }
    
    elif policy_name == 'overprivileged-sa':
        if (asset_type == 'iam.googleapis.com/ServiceAccount' and
            'admin_privileges' in risk_factors):
            violation = {
                'policy': policy_name,
                'severity': policy_config.get('risk_level', 'MEDIUM'),
                'description': 'Service account has excessive privileges',
                'asset_name': asset_name,
                'asset_type': asset_type,
                'remediation_required': policy_config.get('auto_remediate', False)
            }
    
    return violation

def check_general_compliance(asset_name: str, asset_type: str,
                           risk_factors: List[str],
                           compliance_data: Dict[str, Any]) -> List[Dict[str, Any]]:
    """Check for general compliance issues."""
    
    violations = []
    
    # Check for missing labels
    resource_data = compliance_data.get('resource', {}).get('data', {})
    labels = resource_data.get('labels', {})
    
    required_labels = ['environment', 'owner', 'purpose']
    missing_labels = [label for label in required_labels if label not in labels]
    
    if missing_labels:
        violations.append({
            'policy': 'required-labels',
            'severity': 'LOW',
            'description': f'Missing required labels: {", ".join(missing_labels)}',
            'asset_name': asset_name,
            'asset_type': asset_type,
            'remediation_required': False
        })
    
    # Check for non-compliant regions
    location = resource_data.get('location', '')
    if location and not location.startswith('us-'):
        violations.append({
            'policy': 'approved-regions',
            'severity': 'MEDIUM',
            'description': f'Resource deployed in non-approved region: {location}',
            'asset_name': asset_name,
            'asset_type': asset_type,
            'remediation_required': False
        })
    
    return violations

def determine_enforcement_actions(risk_level: str, violations: List[Dict[str, Any]],
                                governance_actions: List[str]) -> List[Dict[str, Any]]:
    """Determine appropriate enforcement actions based on risk and violations."""
    
    actions = []
    
    # Base actions based on risk level
    if risk_level == 'HIGH':
        actions.extend([
            {'type': 'alert_security_team', 'priority': 'IMMEDIATE'},
            {'type': 'create_incident_ticket', 'priority': 'HIGH'},
            {'type': 'escalate_to_management', 'priority': 'HIGH'}
        ])
    elif risk_level == 'MEDIUM':
        actions.extend([
            {'type': 'alert_team_lead', 'priority': 'MEDIUM'},
            {'type': 'create_review_ticket', 'priority': 'MEDIUM'}
        ])
    else:
        actions.append({'type': 'log_compliance_event', 'priority': 'LOW'})
    
    # Violation-specific actions
    for violation in violations:
        if violation['severity'] == 'HIGH':
            actions.append({
                'type': 'immediate_remediation',
                'priority': 'IMMEDIATE',
                'violation': violation['policy'],
                'description': violation['description']
            })
        elif violation['remediation_required']:
            actions.append({
                'type': 'scheduled_remediation',
                'priority': 'MEDIUM',
                'violation': violation['policy'],
                'description': violation['description']
            })
    
    # Governance-specific actions
    for gov_action in governance_actions:
        if gov_action == 'review_public_access':
            actions.append({
                'type': 'public_access_review',
                'priority': 'HIGH',
                'description': 'Review and restrict public access'
            })
        elif gov_action == 'review_permissions':
            actions.append({
                'type': 'permission_review',
                'priority': 'MEDIUM',
                'description': 'Review and optimize IAM permissions'
            })
        elif gov_action == 'review_network_config':
            actions.append({
                'type': 'network_review',
                'priority': 'HIGH',
                'description': 'Review and secure network configuration'
            })
    
    return actions

def execute_enforcement_actions(asset_name: str, asset_type: str,
                               actions: List[Dict[str, Any]],
                               compliance_data: Dict[str, Any]) -> List[Dict[str, Any]]:
    """Execute the determined enforcement actions."""
    
    results = []
    
    for action in actions:
        try:
            action_type = action['type']
            
            if action_type == 'alert_security_team':
                result = send_security_alert(asset_name, asset_type, action, compliance_data)
                results.append(result)
            
            elif action_type == 'create_incident_ticket':
                result = create_incident_ticket(asset_name, asset_type, action, compliance_data)
                results.append(result)
            
            elif action_type == 'create_review_ticket':
                result = create_review_ticket(asset_name, asset_type, action, compliance_data)
                results.append(result)
            
            elif action_type == 'alert_team_lead':
                result = alert_team_lead(asset_name, asset_type, action, compliance_data)
                results.append(result)
            
            elif action_type == 'immediate_remediation':
                result = trigger_immediate_remediation(asset_name, asset_type, action, compliance_data)
                results.append(result)
            
            elif action_type == 'scheduled_remediation':
                result = schedule_remediation(asset_name, asset_type, action, compliance_data)
                results.append(result)
            
            elif action_type == 'public_access_review':
                result = initiate_public_access_review(asset_name, asset_type, action, compliance_data)
                results.append(result)
            
            elif action_type == 'permission_review':
                result = initiate_permission_review(asset_name, asset_type, action, compliance_data)
                results.append(result)
            
            elif action_type == 'network_review':
                result = initiate_network_review(asset_name, asset_type, action, compliance_data)
                results.append(result)
            
            elif action_type == 'log_compliance_event':
                result = log_compliance_event(asset_name, asset_type, action, compliance_data)
                results.append(result)
            
            else:
                logger.warning(f"Unknown action type: {action_type}")
                results.append({
                    'action': action_type,
                    'status': 'skipped',
                    'message': f'Unknown action type: {action_type}'
                })
                
        except Exception as e:
            logger.error(f"Error executing action {action_type}: {str(e)}")
            results.append({
                'action': action_type,
                'status': 'failed',
                'message': str(e)
            })
    
    return results

def send_security_alert(asset_name: str, asset_type: str, 
                       action: Dict[str, Any], compliance_data: Dict[str, Any]) -> Dict[str, Any]:
    """Send alert to security team."""
    
    alert_message = f"HIGH RISK COMPLIANCE VIOLATION: {asset_name} ({asset_type})"
    logger.warning(alert_message)
    
    # In a real implementation, this would integrate with alerting systems
    # such as PagerDuty, Slack, or email notifications
    
    return {
        'action': 'alert_security_team',
        'status': 'success',
        'message': f'Security alert sent for {asset_name}',
        'alert_id': f'sec-alert-{asset_name.split("/")[-1]}'
    }

def create_incident_ticket(asset_name: str, asset_type: str,
                          action: Dict[str, Any], compliance_data: Dict[str, Any]) -> Dict[str, Any]:
    """Create incident ticket for high-priority violations."""
    
    logger.info(f"Creating incident ticket for {asset_name}")
    
    # In a real implementation, this would integrate with ITSM systems
    # such as ServiceNow, Jira, or similar ticketing systems
    
    ticket_data = {
        'title': f'High-Risk Compliance Violation: {asset_name}',
        'description': f'Asset {asset_name} ({asset_type}) has been flagged for high-risk compliance violations',
        'priority': 'HIGH',
        'category': 'Security',
        'asset_name': asset_name,
        'asset_type': asset_type
    }
    
    return {
        'action': 'create_incident_ticket',
        'status': 'success',
        'message': f'Incident ticket created for {asset_name}',
        'ticket_id': f'INC-{asset_name.split("/")[-1]}'
    }

def create_review_ticket(asset_name: str, asset_type: str,
                        action: Dict[str, Any], compliance_data: Dict[str, Any]) -> Dict[str, Any]:
    """Create review ticket for compliance issues."""
    
    logger.info(f"Creating review ticket for {asset_name}")
    
    ticket_data = {
        'title': f'Compliance Review Required: {asset_name}',
        'description': f'Asset {asset_name} ({asset_type}) requires compliance review',
        'priority': 'MEDIUM',
        'category': 'Compliance',
        'asset_name': asset_name,
        'asset_type': asset_type
    }
    
    return {
        'action': 'create_review_ticket',
        'status': 'success',
        'message': f'Review ticket created for {asset_name}',
        'ticket_id': f'REV-{asset_name.split("/")[-1]}'
    }

def alert_team_lead(asset_name: str, asset_type: str,
                   action: Dict[str, Any], compliance_data: Dict[str, Any]) -> Dict[str, Any]:
    """Alert team lead about compliance issue."""
    
    logger.info(f"Alerting team lead about {asset_name}")
    
    # In a real implementation, this would send notifications to team leads
    
    return {
        'action': 'alert_team_lead',
        'status': 'success',
        'message': f'Team lead alerted about {asset_name}',
        'notification_id': f'alert-{asset_name.split("/")[-1]}'
    }

def trigger_immediate_remediation(asset_name: str, asset_type: str,
                                 action: Dict[str, Any], compliance_data: Dict[str, Any]) -> Dict[str, Any]:
    """Trigger immediate remediation for critical violations."""
    
    logger.warning(f"Triggering immediate remediation for {asset_name}")
    
    # In a real implementation, this would trigger automated remediation
    # such as disabling public access, removing excessive permissions, etc.
    
    return {
        'action': 'immediate_remediation',
        'status': 'success',
        'message': f'Immediate remediation triggered for {asset_name}',
        'remediation_id': f'rem-{asset_name.split("/")[-1]}'
    }

def schedule_remediation(asset_name: str, asset_type: str,
                        action: Dict[str, Any], compliance_data: Dict[str, Any]) -> Dict[str, Any]:
    """Schedule remediation for compliance violations."""
    
    logger.info(f"Scheduling remediation for {asset_name}")
    
    # In a real implementation, this would schedule remediation tasks
    
    return {
        'action': 'scheduled_remediation',
        'status': 'success',
        'message': f'Remediation scheduled for {asset_name}',
        'schedule_id': f'sched-{asset_name.split("/")[-1]}'
    }

def initiate_public_access_review(asset_name: str, asset_type: str,
                                 action: Dict[str, Any], compliance_data: Dict[str, Any]) -> Dict[str, Any]:
    """Initiate review of public access configurations."""
    
    logger.info(f"Initiating public access review for {asset_name}")
    
    # In a real implementation, this would trigger policy simulation
    # and analysis of public access configurations
    
    return {
        'action': 'public_access_review',
        'status': 'success',
        'message': f'Public access review initiated for {asset_name}',
        'review_id': f'pub-{asset_name.split("/")[-1]}'
    }

def initiate_permission_review(asset_name: str, asset_type: str,
                              action: Dict[str, Any], compliance_data: Dict[str, Any]) -> Dict[str, Any]:
    """Initiate review of IAM permissions."""
    
    logger.info(f"Initiating permission review for {asset_name}")
    
    # In a real implementation, this would integrate with Policy Validator
    if POLICY_VALIDATOR_URL:
        try:
            # Call Policy Validator function
            validator_data = {
                'resource_name': asset_name,
                'proposed_policy': compliance_data.get('iam_policy', {}),
                'simulation_type': 'iam_policy'
            }
            
            # This would make an actual HTTP request to the Policy Validator
            logger.info(f"Would call Policy Validator: {POLICY_VALIDATOR_URL}")
            
        except Exception as e:
            logger.error(f"Error calling Policy Validator: {str(e)}")
    
    return {
        'action': 'permission_review',
        'status': 'success',
        'message': f'Permission review initiated for {asset_name}',
        'review_id': f'perm-{asset_name.split("/")[-1]}'
    }

def initiate_network_review(asset_name: str, asset_type: str,
                           action: Dict[str, Any], compliance_data: Dict[str, Any]) -> Dict[str, Any]:
    """Initiate review of network configurations."""
    
    logger.info(f"Initiating network review for {asset_name}")
    
    return {
        'action': 'network_review',
        'status': 'success',
        'message': f'Network review initiated for {asset_name}',
        'review_id': f'net-{asset_name.split("/")[-1]}'
    }

def log_compliance_event(asset_name: str, asset_type: str,
                        action: Dict[str, Any], compliance_data: Dict[str, Any]) -> Dict[str, Any]:
    """Log compliance event for audit trail."""
    
    logger.info(f"Logging compliance event for {asset_name}")
    
    # Structured logging for compliance events
    compliance_log = {
        'event_type': 'compliance_enforcement',
        'asset_name': asset_name,
        'asset_type': asset_type,
        'action': action,
        'compliance_data': compliance_data,
        'timestamp': compliance_data.get('timestamp', ''),
        'project_id': PROJECT_ID
    }
    
    logger.info(f"Compliance log: {json.dumps(compliance_log)}")
    
    return {
        'action': 'log_compliance_event',
        'status': 'success',
        'message': f'Compliance event logged for {asset_name}',
        'log_id': f'log-{asset_name.split("/")[-1]}'
    }

def record_compliance_metrics(asset_name: str, asset_type: str, risk_level: str,
                             violations: List[Dict[str, Any]], 
                             execution_results: List[Dict[str, Any]]) -> None:
    """Record compliance metrics in Cloud Monitoring."""
    
    try:
        client = monitoring_v3.MetricServiceClient()
        project_name = f"projects/{PROJECT_ID}"
        
        # Create time series data
        series = monitoring_v3.TimeSeries()
        series.metric.type = "custom.googleapis.com/governance/compliance_events"
        series.resource.type = "global"
        
        # Add labels
        series.metric.labels["asset_type"] = asset_type
        series.metric.labels["risk_level"] = risk_level
        series.metric.labels["violation_count"] = str(len(violations))
        
        # Add point
        point = monitoring_v3.Point()
        point.value.int64_value = 1
        point.interval.end_time.seconds = int(time.time())
        series.points = [point]
        
        # Write time series
        client.create_time_series(
            name=project_name,
            time_series=[series]
        )
        
        logger.info(f"Compliance metrics recorded for {asset_name}")
        
    except Exception as e:
        logger.error(f"Error recording compliance metrics: {str(e)}")

def generate_compliance_report(asset_name: str, asset_type: str, risk_level: str,
                              violations: List[Dict[str, Any]], 
                              enforcement_actions: List[Dict[str, Any]],
                              execution_results: List[Dict[str, Any]]) -> Dict[str, Any]:
    """Generate comprehensive compliance report."""
    
    return {
        'asset_details': {
            'name': asset_name,
            'type': asset_type,
            'risk_level': risk_level
        },
        'violations_summary': {
            'total_violations': len(violations),
            'high_severity': len([v for v in violations if v['severity'] == 'HIGH']),
            'medium_severity': len([v for v in violations if v['severity'] == 'MEDIUM']),
            'low_severity': len([v for v in violations if v['severity'] == 'LOW'])
        },
        'enforcement_summary': {
            'total_actions': len(enforcement_actions),
            'successful_actions': len([r for r in execution_results if r['status'] == 'success']),
            'failed_actions': len([r for r in execution_results if r['status'] == 'failed']),
            'immediate_actions': len([a for a in enforcement_actions if a['priority'] == 'IMMEDIATE'])
        },
        'violations': violations,
        'enforcement_actions': enforcement_actions,
        'execution_results': execution_results,
        'generated_at': compliance_data.get('timestamp', ''),
        'project_id': PROJECT_ID
    }

# Entry point for Cloud Functions
def main(cloud_event):
    """Main entry point for Cloud Functions."""
    return enforce_compliance(cloud_event)