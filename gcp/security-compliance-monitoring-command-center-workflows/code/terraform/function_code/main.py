"""
Security findings processing Cloud Function.

This function processes security findings from Security Command Center
and triggers appropriate workflows based on severity levels.
"""

import functions_framework
import json
import base64
import logging
import os
from typing import Dict, Any, Optional
from google.cloud import workflows_v1
from google.cloud import logging as cloud_logging

# Configure logging
cloud_logging.Client().setup_logging()
logger = logging.getLogger(__name__)

# Environment variables
PROJECT_ID = os.environ.get('PROJECT_ID', '${project_id}')
REGION = os.environ.get('REGION', '${region}')

# Workflow mappings based on severity
SEVERITY_WORKFLOWS = {
    'CRITICAL': 'high-severity-workflow',
    'HIGH': 'high-severity-workflow',
    'MEDIUM': 'medium-severity-workflow',
    'LOW': 'low-severity-workflow',
    'INFO': 'low-severity-workflow'
}

@functions_framework.cloud_event
def process_security_finding(cloud_event):
    """
    Process security findings from Pub/Sub and trigger appropriate workflows.
    
    Args:
        cloud_event: CloudEvent containing the Pub/Sub message
        
    Returns:
        str: Processing status
    """
    try:
        # Extract and decode the Pub/Sub message
        message_data = base64.b64decode(cloud_event.data["message"]["data"])
        finding_data = json.loads(message_data.decode('utf-8'))
        
        # Extract finding details
        finding_id = finding_data.get('name', 'unknown-finding')
        severity = finding_data.get('severity', 'LOW')
        category = finding_data.get('category', 'unknown')
        resource_name = finding_data.get('resourceName', 'unknown-resource')
        state = finding_data.get('state', 'UNKNOWN')
        
        logger.info(
            f"Processing finding: {finding_id} with severity: {severity}, "
            f"category: {category}, resource: {resource_name}, state: {state}"
        )
        
        # Only process ACTIVE findings
        if state != 'ACTIVE':
            logger.info(f"Skipping non-active finding: {finding_id} (state: {state})")
            return 'SKIPPED'
        
        # Determine appropriate workflow based on severity
        workflow_name = determine_workflow(severity, category)
        
        if workflow_name:
            # Trigger the appropriate workflow
            execution_result = trigger_workflow(workflow_name, finding_data)
            
            if execution_result:
                logger.info(f"Successfully triggered workflow {workflow_name} for finding {finding_id}")
                return 'SUCCESS'
            else:
                logger.error(f"Failed to trigger workflow {workflow_name} for finding {finding_id}")
                return 'FAILED'
        else:
            logger.warning(f"No workflow mapping found for severity: {severity}")
            return 'NO_WORKFLOW'
            
    except json.JSONDecodeError as e:
        logger.error(f"Error decoding JSON message: {str(e)}")
        raise
    except Exception as e:
        logger.error(f"Error processing security finding: {str(e)}")
        raise

def determine_workflow(severity: str, category: str) -> Optional[str]:
    """
    Determine which workflow to trigger based on finding severity and category.
    
    Args:
        severity: Security finding severity level
        category: Security finding category
        
    Returns:
        str: Workflow name to trigger, or None if no mapping found
    """
    # Get base workflow from severity
    workflow_name = SEVERITY_WORKFLOWS.get(severity.upper())
    
    # Special handling for specific categories
    if category in ['MALWARE', 'VULNERABILITY', 'SUSPICIOUS_ACTIVITY']:
        # Always treat these as high priority regardless of severity
        if severity.upper() in ['LOW', 'INFO']:
            workflow_name = 'medium-severity-workflow'
    
    logger.debug(f"Mapped severity {severity} and category {category} to workflow: {workflow_name}")
    return workflow_name

def trigger_workflow(workflow_name: str, finding: Dict[str, Any]) -> bool:
    """
    Trigger a Cloud Workflow with the security finding data.
    
    Args:
        workflow_name: Name of the workflow to trigger
        finding: Security finding data
        
    Returns:
        bool: True if workflow was triggered successfully, False otherwise
    """
    try:
        # Initialize Workflows client
        client = workflows_v1.WorkflowsClient()
        
        # Prepare workflow input with enhanced data
        workflow_input = {
            'finding': finding,
            'metadata': {
                'timestamp': finding.get('eventTime', ''),
                'severity': finding.get('severity', 'LOW'),
                'category': finding.get('category', 'unknown'),
                'processor': 'security-compliance-function',
                'project_id': PROJECT_ID,
                'region': REGION
            }
        }
        
        # Construct workflow parent path
        workflow_parent = f"projects/{PROJECT_ID}/locations/{REGION}/workflows/{workflow_name}"
        
        # Create workflow execution
        execution = workflows_v1.Execution(
            argument=json.dumps(workflow_input)
        )
        
        # Execute the workflow
        operation = client.create_execution(
            parent=workflow_parent,
            execution=execution
        )
        
        logger.info(f"Triggered workflow: {workflow_name} with execution: {operation.name}")
        return True
        
    except Exception as e:
        logger.error(f"Error triggering workflow {workflow_name}: {str(e)}")
        return False

def validate_finding_data(finding: Dict[str, Any]) -> bool:
    """
    Validate that the security finding contains required fields.
    
    Args:
        finding: Security finding data dictionary
        
    Returns:
        bool: True if finding is valid, False otherwise
    """
    required_fields = ['name', 'severity', 'category', 'state']
    
    for field in required_fields:
        if field not in finding:
            logger.warning(f"Missing required field in finding: {field}")
            return False
    
    # Validate severity is a known value
    valid_severities = ['CRITICAL', 'HIGH', 'MEDIUM', 'LOW', 'INFO']
    if finding.get('severity', '').upper() not in valid_severities:
        logger.warning(f"Invalid severity level: {finding.get('severity')}")
        return False
    
    return True

def enrich_finding_data(finding: Dict[str, Any]) -> Dict[str, Any]:
    """
    Enrich security finding data with additional context.
    
    Args:
        finding: Original security finding data
        
    Returns:
        dict: Enriched finding data
    """
    enriched = finding.copy()
    
    # Add processing metadata
    enriched['processing'] = {
        'processor_function': 'security-compliance-processor',
        'project_id': PROJECT_ID,
        'region': REGION,
        'enriched_at': finding.get('eventTime', '')
    }
    
    # Add risk assessment
    severity = finding.get('severity', 'LOW').upper()
    category = finding.get('category', '').upper()
    
    risk_score = calculate_risk_score(severity, category)
    enriched['risk_assessment'] = {
        'risk_score': risk_score,
        'risk_level': get_risk_level(risk_score),
        'automated_response_eligible': risk_score >= 7
    }
    
    return enriched

def calculate_risk_score(severity: str, category: str) -> int:
    """
    Calculate a risk score based on severity and category.
    
    Args:
        severity: Security finding severity
        category: Security finding category
        
    Returns:
        int: Risk score from 1-10
    """
    # Base score from severity
    severity_scores = {
        'CRITICAL': 10,
        'HIGH': 8,
        'MEDIUM': 5,
        'LOW': 3,
        'INFO': 1
    }
    
    base_score = severity_scores.get(severity, 1)
    
    # Adjustment based on category
    high_risk_categories = ['MALWARE', 'VULNERABILITY', 'SUSPICIOUS_ACTIVITY']
    if category in high_risk_categories:
        base_score = min(10, base_score + 2)
    
    return base_score

def get_risk_level(risk_score: int) -> str:
    """
    Convert numeric risk score to risk level string.
    
    Args:
        risk_score: Numeric risk score
        
    Returns:
        str: Risk level description
    """
    if risk_score >= 9:
        return 'CRITICAL'
    elif risk_score >= 7:
        return 'HIGH'
    elif risk_score >= 4:
        return 'MEDIUM'
    else:
        return 'LOW'