"""
Policy Validator Cloud Function
Validates policy changes using Google Cloud Policy Simulator.
"""

import json
import logging
import os
from typing import Dict, Any, List, Optional
from google.cloud import policy_intelligence_v1
from google.cloud import asset_v1
from google.cloud import logging as cloud_logging
from google.cloud import resourcemanager_v3
import flask

# Configure logging
cloud_logging.Client().setup_logging()
logger = logging.getLogger(__name__)

# Configuration from environment variables
PROJECT_ID = os.environ.get('PROJECT_ID', '${project_id}')
REGION = os.environ.get('REGION', 'us-central1')

def validate_policy_changes(request: flask.Request) -> Dict[str, Any]:
    """
    Main entry point for validating policy changes.
    
    Args:
        request: Flask request object containing policy change data
        
    Returns:
        Dictionary containing validation results
    """
    try:
        # Parse request data
        request_json = request.get_json(silent=True)
        if not request_json:
            return {
                'status': 'error',
                'message': 'No JSON data provided'
            }
        
        # Extract required parameters
        resource_name = request_json.get('resource_name')
        proposed_policy = request_json.get('proposed_policy')
        simulation_type = request_json.get('simulation_type', 'iam_policy')
        
        if not resource_name or not proposed_policy:
            return {
                'status': 'error',
                'message': 'resource_name and proposed_policy are required'
            }
        
        logger.info(f"Validating policy changes for: {resource_name}")
        
        # Initialize Policy Simulator client
        client = policy_intelligence_v1.PolicySimulatorClient()
        
        # Create and run simulation
        simulation_results = run_policy_simulation(
            client, resource_name, proposed_policy, simulation_type
        )
        
        # Analyze simulation results
        validation_results = analyze_simulation_results(simulation_results)
        
        # Assess overall risk
        risk_assessment = assess_policy_risk(validation_results)
        
        # Generate recommendations
        recommendations = generate_policy_recommendations(
            validation_results, risk_assessment
        )
        
        return {
            'status': 'success',
            'resource_name': resource_name,
            'validation_results': validation_results,
            'risk_assessment': risk_assessment,
            'recommendations': recommendations,
            'simulation_timestamp': simulation_results.get('timestamp', '')
        }
        
    except Exception as e:
        logger.error(f"Error validating policy changes: {str(e)}")
        return {
            'status': 'error',
            'message': str(e)
        }

def run_policy_simulation(client: policy_intelligence_v1.PolicySimulatorClient,
                         resource_name: str, proposed_policy: Dict[str, Any],
                         simulation_type: str) -> Dict[str, Any]:
    """
    Execute policy simulation using Policy Simulator.
    
    Args:
        client: Policy Simulator client
        resource_name: Full resource name for simulation
        proposed_policy: Proposed IAM policy
        simulation_type: Type of simulation to run
        
    Returns:
        Dictionary containing simulation results
    """
    try:
        # Create simulation request
        if simulation_type == 'iam_policy':
            simulation_results = simulate_iam_policy_changes(
                client, resource_name, proposed_policy
            )
        else:
            raise ValueError(f"Unsupported simulation type: {simulation_type}")
        
        return simulation_results
        
    except Exception as e:
        logger.error(f"Error running policy simulation: {str(e)}")
        return {
            'status': 'error',
            'message': str(e),
            'timestamp': '',
            'access_changes': []
        }

def simulate_iam_policy_changes(client: policy_intelligence_v1.PolicySimulatorClient,
                               resource_name: str, 
                               proposed_policy: Dict[str, Any]) -> Dict[str, Any]:
    """Simulate IAM policy changes and analyze access impact."""
    
    # For demonstration purposes, we'll simulate the analysis
    # In a real implementation, this would use the actual Policy Simulator API
    
    logger.info(f"Simulating IAM policy changes for {resource_name}")
    
    # Extract current and proposed bindings
    current_bindings = get_current_iam_policy(resource_name)
    proposed_bindings = proposed_policy.get('bindings', [])
    
    # Analyze changes
    access_changes = analyze_policy_differences(current_bindings, proposed_bindings)
    
    # Calculate impact metrics
    impact_metrics = calculate_impact_metrics(access_changes)
    
    return {
        'status': 'success',
        'timestamp': '',
        'access_changes': access_changes,
        'impact_metrics': impact_metrics,
        'resource_name': resource_name
    }

def get_current_iam_policy(resource_name: str) -> List[Dict[str, Any]]:
    """Get current IAM policy for the resource."""
    try:
        # In a real implementation, this would fetch the actual current policy
        # For now, we'll return a sample policy structure
        return [
            {
                'role': 'roles/viewer',
                'members': ['user:example@company.com']
            },
            {
                'role': 'roles/editor',
                'members': ['serviceAccount:service@project.iam.gserviceaccount.com']
            }
        ]
    except Exception as e:
        logger.error(f"Error getting current IAM policy: {str(e)}")
        return []

def analyze_policy_differences(current_bindings: List[Dict[str, Any]],
                             proposed_bindings: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    """Analyze differences between current and proposed policy bindings."""
    
    access_changes = []
    
    # Create maps for easier comparison
    current_map = {binding['role']: set(binding.get('members', [])) 
                   for binding in current_bindings}
    proposed_map = {binding['role']: set(binding.get('members', [])) 
                    for binding in proposed_bindings}
    
    # Find all roles (current and proposed)
    all_roles = set(current_map.keys()) | set(proposed_map.keys())
    
    for role in all_roles:
        current_members = current_map.get(role, set())
        proposed_members = proposed_map.get(role, set())
        
        # Find added members
        added_members = proposed_members - current_members
        for member in added_members:
            access_changes.append({
                'change_type': 'ADDED',
                'role': role,
                'member': member,
                'impact': assess_role_impact(role, 'ADDED')
            })
        
        # Find removed members
        removed_members = current_members - proposed_members
        for member in removed_members:
            access_changes.append({
                'change_type': 'REMOVED',
                'role': role,
                'member': member,
                'impact': assess_role_impact(role, 'REMOVED')
            })
    
    return access_changes

def assess_role_impact(role: str, change_type: str) -> str:
    """Assess the impact level of a role change."""
    
    # High-impact roles
    high_impact_roles = [
        'roles/owner',
        'roles/editor',
        'roles/iam.securityAdmin',
        'roles/resourcemanager.organizationAdmin',
        'roles/billing.admin'
    ]
    
    # Medium-impact roles
    medium_impact_roles = [
        'roles/compute.admin',
        'roles/storage.admin',
        'roles/cloudsql.admin',
        'roles/container.admin'
    ]
    
    if role in high_impact_roles:
        return 'HIGH'
    elif role in medium_impact_roles:
        return 'MEDIUM'
    else:
        return 'LOW'

def calculate_impact_metrics(access_changes: List[Dict[str, Any]]) -> Dict[str, Any]:
    """Calculate metrics about the impact of policy changes."""
    
    total_changes = len(access_changes)
    high_impact_changes = sum(1 for change in access_changes 
                             if change['impact'] == 'HIGH')
    medium_impact_changes = sum(1 for change in access_changes 
                               if change['impact'] == 'MEDIUM')
    low_impact_changes = sum(1 for change in access_changes 
                            if change['impact'] == 'LOW')
    
    added_permissions = sum(1 for change in access_changes 
                           if change['change_type'] == 'ADDED')
    removed_permissions = sum(1 for change in access_changes 
                             if change['change_type'] == 'REMOVED')
    
    return {
        'total_changes': total_changes,
        'high_impact_changes': high_impact_changes,
        'medium_impact_changes': medium_impact_changes,
        'low_impact_changes': low_impact_changes,
        'added_permissions': added_permissions,
        'removed_permissions': removed_permissions
    }

def analyze_simulation_results(simulation_results: Dict[str, Any]) -> Dict[str, Any]:
    """Analyze simulation results for governance compliance."""
    
    if simulation_results.get('status') == 'error':
        return {
            'status': 'error',
            'message': simulation_results.get('message', 'Unknown error')
        }
    
    access_changes = simulation_results.get('access_changes', [])
    impact_metrics = simulation_results.get('impact_metrics', {})
    
    # Categorize changes
    permission_additions = [change for change in access_changes 
                           if change['change_type'] == 'ADDED']
    permission_removals = [change for change in access_changes 
                          if change['change_type'] == 'REMOVED']
    
    # Identify concerning patterns
    concerning_patterns = identify_concerning_patterns(access_changes)
    
    # Calculate compliance score
    compliance_score = calculate_compliance_score(access_changes, concerning_patterns)
    
    return {
        'status': 'success',
        'access_changes': access_changes,
        'impact_metrics': impact_metrics,
        'permission_additions': permission_additions,
        'permission_removals': permission_removals,
        'concerning_patterns': concerning_patterns,
        'compliance_score': compliance_score
    }

def identify_concerning_patterns(access_changes: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    """Identify concerning patterns in policy changes."""
    
    patterns = []
    
    # Check for privilege escalation
    admin_roles_added = [change for change in access_changes 
                        if change['change_type'] == 'ADDED' 
                        and ('admin' in change['role'].lower() or 'owner' in change['role'].lower())]
    
    if admin_roles_added:
        patterns.append({
            'pattern': 'privilege_escalation',
            'severity': 'HIGH',
            'description': 'Administrative roles being added',
            'affected_changes': admin_roles_added
        })
    
    # Check for broad permissions
    broad_permissions = [change for change in access_changes 
                        if change['change_type'] == 'ADDED' 
                        and change['role'] in ['roles/editor', 'roles/owner']]
    
    if broad_permissions:
        patterns.append({
            'pattern': 'broad_permissions',
            'severity': 'MEDIUM',
            'description': 'Broad permissions being granted',
            'affected_changes': broad_permissions
        })
    
    # Check for external user access
    external_access = [change for change in access_changes 
                      if change['change_type'] == 'ADDED' 
                      and not change['member'].endswith('@' + PROJECT_ID + '.iam.gserviceaccount.com')]
    
    if external_access:
        patterns.append({
            'pattern': 'external_access',
            'severity': 'MEDIUM',
            'description': 'Access being granted to external users',
            'affected_changes': external_access
        })
    
    return patterns

def calculate_compliance_score(access_changes: List[Dict[str, Any]], 
                             concerning_patterns: List[Dict[str, Any]]) -> Dict[str, Any]:
    """Calculate a compliance score based on policy changes."""
    
    base_score = 100
    
    # Deduct points for concerning patterns
    for pattern in concerning_patterns:
        if pattern['severity'] == 'HIGH':
            base_score -= 30
        elif pattern['severity'] == 'MEDIUM':
            base_score -= 15
        else:
            base_score -= 5
    
    # Deduct points for high-impact changes
    high_impact_changes = sum(1 for change in access_changes 
                             if change['impact'] == 'HIGH')
    base_score -= high_impact_changes * 10
    
    # Ensure score doesn't go below 0
    final_score = max(0, base_score)
    
    # Determine compliance level
    if final_score >= 80:
        compliance_level = 'GOOD'
    elif final_score >= 60:
        compliance_level = 'MODERATE'
    else:
        compliance_level = 'POOR'
    
    return {
        'score': final_score,
        'level': compliance_level,
        'max_score': 100,
        'deductions': 100 - final_score
    }

def assess_policy_risk(validation_results: Dict[str, Any]) -> Dict[str, Any]:
    """Assess overall risk level of proposed policy changes."""
    
    if validation_results.get('status') == 'error':
        return {
            'risk_level': 'UNKNOWN',
            'message': 'Cannot assess risk due to validation errors'
        }
    
    concerning_patterns = validation_results.get('concerning_patterns', [])
    compliance_score = validation_results.get('compliance_score', {})
    impact_metrics = validation_results.get('impact_metrics', {})
    
    # Determine risk level
    high_severity_patterns = [p for p in concerning_patterns if p['severity'] == 'HIGH']
    medium_severity_patterns = [p for p in concerning_patterns if p['severity'] == 'MEDIUM']
    
    if high_severity_patterns or compliance_score.get('score', 100) < 60:
        risk_level = 'HIGH'
    elif medium_severity_patterns or compliance_score.get('score', 100) < 80:
        risk_level = 'MEDIUM'
    else:
        risk_level = 'LOW'
    
    return {
        'risk_level': risk_level,
        'compliance_score': compliance_score.get('score', 100),
        'concerning_patterns_count': len(concerning_patterns),
        'high_impact_changes': impact_metrics.get('high_impact_changes', 0),
        'total_changes': impact_metrics.get('total_changes', 0)
    }

def generate_policy_recommendations(validation_results: Dict[str, Any],
                                  risk_assessment: Dict[str, Any]) -> List[Dict[str, Any]]:
    """Generate recommendations based on validation results."""
    
    recommendations = []
    
    if validation_results.get('status') == 'error':
        return [{
            'type': 'ERROR',
            'priority': 'HIGH',
            'message': 'Policy validation failed - manual review required'
        }]
    
    risk_level = risk_assessment.get('risk_level', 'LOW')
    concerning_patterns = validation_results.get('concerning_patterns', [])
    
    # High-risk recommendations
    if risk_level == 'HIGH':
        recommendations.append({
            'type': 'SECURITY_REVIEW',
            'priority': 'HIGH',
            'message': 'High-risk policy changes require security team review before implementation'
        })
    
    # Pattern-specific recommendations
    for pattern in concerning_patterns:
        if pattern['pattern'] == 'privilege_escalation':
            recommendations.append({
                'type': 'PRIVILEGE_REVIEW',
                'priority': 'HIGH',
                'message': 'Administrative privileges being granted - verify business justification'
            })
        elif pattern['pattern'] == 'broad_permissions':
            recommendations.append({
                'type': 'LEAST_PRIVILEGE',
                'priority': 'MEDIUM',
                'message': 'Consider granting more specific roles instead of broad permissions'
            })
        elif pattern['pattern'] == 'external_access':
            recommendations.append({
                'type': 'EXTERNAL_ACCESS_REVIEW',
                'priority': 'MEDIUM',
                'message': 'External user access detected - verify identity and necessity'
            })
    
    # General recommendations
    if risk_level in ['HIGH', 'MEDIUM']:
        recommendations.append({
            'type': 'TESTING',
            'priority': 'MEDIUM',
            'message': 'Test policy changes in a development environment first'
        })
    
    if not recommendations:
        recommendations.append({
            'type': 'APPROVAL',
            'priority': 'LOW',
            'message': 'Policy changes appear safe for implementation'
        })
    
    return recommendations

# Entry point for Cloud Functions
def main(request):
    """Main entry point for Cloud Functions."""
    return validate_policy_changes(request)