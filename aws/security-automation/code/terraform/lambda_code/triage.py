import json
import boto3
import logging
from datetime import datetime

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    """
    Triage security findings and determine appropriate response
    """
    try:
        # Parse EventBridge event
        detail = event.get('detail', {})
        findings = detail.get('findings', [])
        
        if not findings:
            logger.warning("No findings in event")
            return {'statusCode': 200, 'body': 'No findings to process'}
        
        # Process each finding
        for finding in findings:
            severity = finding.get('Severity', {}).get('Label', 'INFORMATIONAL')
            finding_id = finding.get('Id', 'unknown')
            
            logger.info(f"Processing finding {finding_id} with severity {severity}")
            
            # Determine response based on severity and finding type
            response_action = determine_response_action(finding, severity)
            
            if response_action:
                # Tag finding with automation status
                update_finding_workflow_status(finding_id, 'IN_PROGRESS', 'Automated triage initiated')
                
                # Trigger appropriate response
                trigger_response_action(finding, response_action)
        
        return {
            'statusCode': 200,
            'body': json.dumps(f'Processed {len(findings)} findings')
        }
        
    except Exception as e:
        logger.error(f"Error in triage function: {str(e)}")
        raise

def determine_response_action(finding, severity):
    """
    Determine appropriate automated response based on finding characteristics
    """
    finding_type = finding.get('Types', [])
    
    # High severity findings require immediate response
    if severity in ['HIGH', 'CRITICAL']:
        if any('UnauthorizedAPICall' in t for t in finding_type):
            return 'ISOLATE_INSTANCE'
        elif any('NetworkReachability' in t for t in finding_type):
            return 'BLOCK_NETWORK_ACCESS'
        elif any('Malware' in t for t in finding_type):
            return 'QUARANTINE_INSTANCE'
    
    # Medium severity findings get automated remediation
    elif severity == 'MEDIUM':
        if any('MissingSecurityGroup' in t for t in finding_type):
            return 'FIX_SECURITY_GROUP'
        elif any('UnencryptedStorage' in t for t in finding_type):
            return 'ENABLE_ENCRYPTION'
    
    # Low severity findings get notifications only
    return 'NOTIFY_ONLY'

def update_finding_workflow_status(finding_id, status, note):
    """
    Update Security Hub finding workflow status
    """
    try:
        securityhub = boto3.client('securityhub')
        securityhub.batch_update_findings(
            FindingIdentifiers=[{'Id': finding_id}],
            Workflow={'Status': status},
            Note={'Text': note, 'UpdatedBy': 'SecurityAutomation'}
        )
    except Exception as e:
        logger.error(f"Error updating finding status: {str(e)}")

def trigger_response_action(finding, action):
    """
    Trigger the appropriate response action
    """
    eventbridge = boto3.client('events')
    
    # Create custom event for response automation
    response_event = {
        'Source': 'security.automation',
        'DetailType': 'Security Response Required',
        'Detail': json.dumps({
            'action': action,
            'finding': finding,
            'timestamp': datetime.utcnow().isoformat()
        })
    }
    
    eventbridge.put_events(Entries=[response_event])
    logger.info(f"Triggered response action: {action}")