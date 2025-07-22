"""
Asset Analyzer Cloud Function
Analyzes asset changes and triggers governance workflows based on risk assessment.
"""

import json
import base64
import logging
import os
from typing import Dict, Any, List
from google.cloud import asset_v1
from google.cloud import pubsub_v1
from google.cloud import logging as cloud_logging

# Configure logging
cloud_logging.Client().setup_logging()
logger = logging.getLogger(__name__)

# Configuration from environment variables
PROJECT_ID = os.environ.get('PROJECT_ID', '${project_id}')
REGION = os.environ.get('REGION', 'us-central1')
HIGH_RISK_TYPES = json.loads(os.environ.get('HIGH_RISK_TYPES', '${high_risk_types}'))

def analyze_asset_change(cloud_event: Dict[str, Any]) -> Dict[str, Any]:
    """
    Main entry point for analyzing asset changes.
    
    Args:
        cloud_event: Cloud Event from Pub/Sub containing asset change data
        
    Returns:
        Dictionary containing analysis results
    """
    try:
        # Decode Pub/Sub message
        pubsub_message = base64.b64decode(
            cloud_event.data['message']['data']
        ).decode('utf-8')
        asset_data = json.loads(pubsub_message)
        
        # Extract asset information
        asset_name = asset_data.get('name', '')
        asset_type = asset_data.get('assetType', '')
        is_deleted = asset_data.get('deleted', False)
        
        logger.info(f"Processing asset change: {asset_name} ({asset_type})")
        
        # Assess risk level
        risk_assessment = assess_risk_level(asset_type, asset_data)
        
        # Create governance event
        governance_event = create_governance_event(
            asset_name, asset_type, risk_assessment, is_deleted, asset_data
        )
        
        # Process based on risk level
        if risk_assessment['risk_level'] == 'HIGH':
            logger.warning(f"High-risk asset detected: {asset_name}")
            handle_high_risk_asset(governance_event)
        elif risk_assessment['risk_level'] == 'MEDIUM':
            logger.info(f"Medium-risk asset detected: {asset_name}")
            handle_medium_risk_asset(governance_event)
        else:
            logger.info(f"Low-risk asset detected: {asset_name}")
            handle_low_risk_asset(governance_event)
        
        # Log compliance event
        log_compliance_event(governance_event)
        
        return {
            'status': 'success',
            'asset_name': asset_name,
            'asset_type': asset_type,
            'risk_level': risk_assessment['risk_level'],
            'governance_actions': governance_event.get('actions', [])
        }
        
    except Exception as e:
        logger.error(f"Error analyzing asset change: {str(e)}")
        return {
            'status': 'error',
            'message': str(e)
        }

def assess_risk_level(asset_type: str, asset_data: Dict[str, Any]) -> Dict[str, Any]:
    """
    Assess risk level based on asset type and configuration.
    
    Args:
        asset_type: Type of the asset
        asset_data: Complete asset data from Cloud Asset Inventory
        
    Returns:
        Dictionary containing risk assessment details
    """
    risk_factors = []
    
    # Check if asset type is in high-risk list
    if asset_type in HIGH_RISK_TYPES:
        risk_factors.append("high_risk_asset_type")
    
    # Additional risk assessments based on asset properties
    if asset_type == 'storage.googleapis.com/Bucket':
        risk_factors.extend(assess_storage_bucket_risk(asset_data))
    elif asset_type == 'compute.googleapis.com/Instance':
        risk_factors.extend(assess_compute_instance_risk(asset_data))
    elif asset_type == 'iam.googleapis.com/ServiceAccount':
        risk_factors.extend(assess_service_account_risk(asset_data))
    elif asset_type == 'container.googleapis.com/Cluster':
        risk_factors.extend(assess_gke_cluster_risk(asset_data))
    
    # Determine overall risk level
    if any(factor in ['public_access', 'admin_privileges', 'unrestricted_network'] 
           for factor in risk_factors):
        risk_level = 'HIGH'
    elif any(factor in ['high_risk_asset_type', 'privileged_access'] 
             for factor in risk_factors):
        risk_level = 'MEDIUM'
    else:
        risk_level = 'LOW'
    
    return {
        'risk_level': risk_level,
        'risk_factors': risk_factors,
        'assessment_timestamp': asset_data.get('updateTime', '')
    }

def assess_storage_bucket_risk(asset_data: Dict[str, Any]) -> List[str]:
    """Assess risk factors for Cloud Storage buckets."""
    risk_factors = []
    
    resource_data = asset_data.get('resource', {}).get('data', {})
    
    # Check for public access
    iam_config = resource_data.get('iamConfiguration', {})
    if iam_config.get('publicAccessPrevention') == 'inherited':
        risk_factors.append('potential_public_access')
    
    # Check for uniform bucket-level access
    if not iam_config.get('uniformBucketLevelAccess', {}).get('enabled', False):
        risk_factors.append('object_level_permissions')
    
    # Check location for compliance
    location = resource_data.get('location', '')
    if location and not location.startswith('us-'):
        risk_factors.append('non_us_location')
    
    return risk_factors

def assess_compute_instance_risk(asset_data: Dict[str, Any]) -> List[str]:
    """Assess risk factors for Compute Engine instances."""
    risk_factors = []
    
    resource_data = asset_data.get('resource', {}).get('data', {})
    
    # Check network access
    network_interfaces = resource_data.get('networkInterfaces', [])
    for interface in network_interfaces:
        access_configs = interface.get('accessConfigs', [])
        if access_configs:
            risk_factors.append('external_ip_address')
    
    # Check machine type for oversized instances
    machine_type = resource_data.get('machineType', '')
    if any(size in machine_type for size in ['n1-highmem', 'n1-highcpu', 'c2-']):
        risk_factors.append('high_performance_instance')
    
    # Check for preemptible instances
    if resource_data.get('scheduling', {}).get('preemptible', False):
        risk_factors.append('preemptible_instance')
    
    return risk_factors

def assess_service_account_risk(asset_data: Dict[str, Any]) -> List[str]:
    """Assess risk factors for service accounts."""
    risk_factors = []
    
    resource_data = asset_data.get('resource', {}).get('data', {})
    
    # Check for default service accounts
    email = resource_data.get('email', '')
    if 'compute@developer.gserviceaccount.com' in email:
        risk_factors.append('default_service_account')
    
    # Check for user-managed keys
    if 'oauth2ClientId' in resource_data:
        risk_factors.append('user_managed_keys')
    
    return risk_factors

def assess_gke_cluster_risk(asset_data: Dict[str, Any]) -> List[str]:
    """Assess risk factors for GKE clusters."""
    risk_factors = []
    
    resource_data = asset_data.get('resource', {}).get('data', {})
    
    # Check for public endpoint
    if resource_data.get('endpoint'):
        risk_factors.append('public_endpoint')
    
    # Check for legacy RBAC
    if not resource_data.get('rbacEnabled', True):
        risk_factors.append('legacy_rbac')
    
    # Check for network policy
    network_policy = resource_data.get('networkPolicy', {})
    if not network_policy.get('enabled', False):
        risk_factors.append('no_network_policy')
    
    return risk_factors

def create_governance_event(asset_name: str, asset_type: str, 
                          risk_assessment: Dict[str, Any], is_deleted: bool,
                          asset_data: Dict[str, Any]) -> Dict[str, Any]:
    """Create a governance event for further processing."""
    return {
        'asset_name': asset_name,
        'asset_type': asset_type,
        'risk_assessment': risk_assessment,
        'is_deleted': is_deleted,
        'timestamp': asset_data.get('updateTime', ''),
        'project_id': PROJECT_ID,
        'region': REGION,
        'actions': determine_governance_actions(risk_assessment)
    }

def determine_governance_actions(risk_assessment: Dict[str, Any]) -> List[str]:
    """Determine appropriate governance actions based on risk assessment."""
    actions = []
    risk_level = risk_assessment['risk_level']
    risk_factors = risk_assessment['risk_factors']
    
    if risk_level == 'HIGH':
        actions.extend(['alert_security_team', 'create_incident_ticket'])
        
        if 'public_access' in risk_factors:
            actions.append('review_public_access')
        if 'admin_privileges' in risk_factors:
            actions.append('review_permissions')
        if 'unrestricted_network' in risk_factors:
            actions.append('review_network_config')
            
    elif risk_level == 'MEDIUM':
        actions.extend(['alert_team_lead', 'create_review_ticket'])
        
        if 'high_risk_asset_type' in risk_factors:
            actions.append('schedule_security_review')
    else:
        actions.append('log_for_audit')
    
    return actions

def handle_high_risk_asset(governance_event: Dict[str, Any]) -> None:
    """Handle high-risk assets with immediate actions."""
    logger.warning(f"HIGH RISK ASSET: {governance_event['asset_name']}")
    
    # Trigger immediate security review
    trigger_security_alert(governance_event)
    
    # Create incident ticket
    create_incident_ticket(governance_event)
    
    # Log for audit trail
    log_security_event(governance_event)

def handle_medium_risk_asset(governance_event: Dict[str, Any]) -> None:
    """Handle medium-risk assets with scheduled reviews."""
    logger.info(f"MEDIUM RISK ASSET: {governance_event['asset_name']}")
    
    # Schedule review
    schedule_security_review(governance_event)
    
    # Create review ticket
    create_review_ticket(governance_event)

def handle_low_risk_asset(governance_event: Dict[str, Any]) -> None:
    """Handle low-risk assets with standard logging."""
    logger.info(f"LOW RISK ASSET: {governance_event['asset_name']}")
    
    # Standard audit logging
    log_compliance_event(governance_event)

def trigger_security_alert(governance_event: Dict[str, Any]) -> None:
    """Trigger security team alert for high-risk assets."""
    logger.warning(f"SECURITY ALERT: {governance_event['asset_name']} - "
                  f"Risk Level: {governance_event['risk_assessment']['risk_level']}")
    
    # In a real implementation, this would integrate with alerting systems
    # such as PagerDuty, Slack, or email notifications

def create_incident_ticket(governance_event: Dict[str, Any]) -> None:
    """Create incident ticket for high-risk assets."""
    logger.info(f"Creating incident ticket for {governance_event['asset_name']}")
    
    # In a real implementation, this would integrate with ITSM systems
    # such as ServiceNow, Jira, or similar ticketing systems

def create_review_ticket(governance_event: Dict[str, Any]) -> None:
    """Create review ticket for medium-risk assets."""
    logger.info(f"Creating review ticket for {governance_event['asset_name']}")
    
    # In a real implementation, this would integrate with task management systems

def schedule_security_review(governance_event: Dict[str, Any]) -> None:
    """Schedule security review for medium-risk assets."""
    logger.info(f"Scheduling security review for {governance_event['asset_name']}")
    
    # In a real implementation, this would integrate with scheduling systems

def log_compliance_event(governance_event: Dict[str, Any]) -> None:
    """Log compliance event for audit trail."""
    logger.info(f"COMPLIANCE EVENT: {governance_event['asset_name']} - "
               f"Risk: {governance_event['risk_assessment']['risk_level']}")
    
    # Structured logging for compliance audit
    compliance_log = {
        'event_type': 'asset_governance_analysis',
        'asset_name': governance_event['asset_name'],
        'asset_type': governance_event['asset_type'],
        'risk_level': governance_event['risk_assessment']['risk_level'],
        'risk_factors': governance_event['risk_assessment']['risk_factors'],
        'actions_taken': governance_event['actions'],
        'timestamp': governance_event['timestamp'],
        'project_id': governance_event['project_id']
    }
    
    logger.info(f"Compliance log: {json.dumps(compliance_log)}")

def log_security_event(governance_event: Dict[str, Any]) -> None:
    """Log security event for high-risk assets."""
    logger.warning(f"SECURITY EVENT: {governance_event['asset_name']} - "
                  f"Immediate attention required")
    
    # Structured logging for security events
    security_log = {
        'event_type': 'high_risk_asset_detected',
        'asset_name': governance_event['asset_name'],
        'asset_type': governance_event['asset_type'],
        'risk_factors': governance_event['risk_assessment']['risk_factors'],
        'severity': 'HIGH',
        'timestamp': governance_event['timestamp'],
        'project_id': governance_event['project_id']
    }
    
    logger.warning(f"Security log: {json.dumps(security_log)}")

# Entry point for Cloud Functions
def main(cloud_event):
    """Main entry point for Cloud Functions."""
    return analyze_asset_change(cloud_event)