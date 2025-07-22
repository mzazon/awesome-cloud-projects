"""
Security Finding Classification Lambda Function

This function automatically classifies Security Hub findings based on severity,
type, and content analysis to enable appropriate automated response actions.

Environment Variables:
- ENVIRONMENT: Deployment environment (dev, staging, prod)
- PROJECT: Project name for tagging and identification
"""

import json
import boto3
import logging
import os
from datetime import datetime
from typing import Dict, Any, List

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize AWS clients
securityhub = boto3.client('securityhub')
sns = boto3.client('sns')

# Environment configuration
ENVIRONMENT = os.environ.get('ENVIRONMENT', '${environment}')
PROJECT = os.environ.get('PROJECT', '${project}')


def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Main Lambda handler for security finding classification.
    
    Args:
        event: EventBridge event containing Security Hub finding
        context: Lambda context object
        
    Returns:
        Dict containing classification results and status
    """
    try:
        logger.info(f"Processing finding classification event in {ENVIRONMENT} environment")
        
        # Extract finding details from EventBridge event
        finding = event['detail']['findings'][0]
        
        finding_id = finding['Id']
        product_arn = finding['ProductArn']
        severity = finding['Severity']['Label']
        title = finding['Title']
        description = finding['Description']
        aws_account_id = finding['AwsAccountId']
        
        logger.info(f"Classifying finding: {finding_id}, Severity: {severity}, Title: {title}")
        
        # Classify finding based on severity and type
        classification = classify_finding(finding)
        
        # Update finding with classification metadata
        response = securityhub.batch_update_findings(
            FindingIdentifiers=[
                {
                    'Id': finding_id,
                    'ProductArn': product_arn
                }
            ],
            Note={
                'Text': f'Auto-classified as {classification["category"]} - {classification["action"]} (Environment: {ENVIRONMENT})',
                'UpdatedBy': f'SecurityIncidentResponse-{PROJECT}'
            },
            UserDefinedFields={
                'AutoClassification': classification['category'],
                'RecommendedAction': classification['action'],
                'ProcessedAt': datetime.utcnow().isoformat(),
                'ProcessedBy': f'{PROJECT}-classification-function',
                'Environment': ENVIRONMENT,
                'EscalationRequired': str(classification.get('escalate', False)).lower(),
                'RiskLevel': classification.get('risk_level', 'MEDIUM'),
                'BusinessImpact': classification.get('business_impact', 'UNKNOWN')
            }
        )
        
        logger.info(f"Successfully classified finding {finding_id} as {classification['category']}")
        
        # Return classification for downstream processing
        return {
            'statusCode': 200,
            'body': json.dumps({
                'findingId': finding_id,
                'classification': classification,
                'updated': True,
                'environment': ENVIRONMENT,
                'timestamp': datetime.utcnow().isoformat()
            })
        }
        
    except Exception as e:
        logger.error(f"Error processing finding classification: {str(e)}")
        logger.error(f"Event details: {json.dumps(event, default=str)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': str(e),
                'environment': ENVIRONMENT,
                'timestamp': datetime.utcnow().isoformat()
            })
        }


def classify_finding(finding: Dict[str, Any]) -> Dict[str, Any]:
    """
    Classify security finding based on severity, type, and content analysis.
    
    Args:
        finding: Security Hub finding object
        
    Returns:
        Dict containing classification metadata
    """
    severity = finding['Severity']['Label']
    finding_types = finding.get('Types', ['Unknown'])
    title = finding['Title'].lower()
    description = finding.get('Description', '').lower()
    resources = finding.get('Resources', [])
    
    # Extract additional context
    compliance_status = finding.get('Compliance', {}).get('Status', 'UNKNOWN')
    workflow_state = finding.get('WorkflowState', 'NEW')
    
    logger.info(f"Analyzing finding: Severity={severity}, Types={finding_types}, Compliance={compliance_status}")
    
    # High-priority critical security incidents
    if severity == 'CRITICAL':
        return classify_critical_finding(title, description, resources, finding_types)
    
    # High severity findings
    elif severity == 'HIGH':
        return classify_high_finding(title, description, resources, finding_types)
    
    # Medium severity findings
    elif severity == 'MEDIUM':
        return classify_medium_finding(title, description, resources, finding_types)
    
    # Low severity and informational findings
    else:
        return classify_low_finding(title, description, resources, finding_types)


def classify_critical_finding(title: str, description: str, resources: List[Dict], finding_types: List[str]) -> Dict[str, Any]:
    """Classify critical severity findings with detailed risk assessment."""
    
    # Root/admin access issues
    if any(keyword in title for keyword in ['root', 'admin', 'administrator', 'privileged']):
        return {
            'category': 'CRITICAL_ADMIN_ISSUE',
            'action': 'IMMEDIATE_REVIEW_REQUIRED',
            'escalate': True,
            'risk_level': 'CRITICAL',
            'business_impact': 'HIGH',
            'response_time': 'IMMEDIATE',
            'remediation_priority': 1
        }
    
    # Malware and security breaches
    elif any(keyword in title for keyword in ['malware', 'backdoor', 'trojan', 'virus', 'breach']):
        return {
            'category': 'MALWARE_DETECTED',
            'action': 'QUARANTINE_RESOURCE',
            'escalate': True,
            'risk_level': 'CRITICAL',
            'business_impact': 'HIGH',
            'response_time': 'IMMEDIATE',
            'remediation_priority': 1
        }
    
    # Data exfiltration or unauthorized access
    elif any(keyword in title for keyword in ['exfiltration', 'unauthorized', 'suspicious access', 'data leak']):
        return {
            'category': 'DATA_SECURITY_BREACH',
            'action': 'INVESTIGATE_IMMEDIATELY',
            'escalate': True,
            'risk_level': 'CRITICAL',
            'business_impact': 'HIGH',
            'response_time': 'IMMEDIATE',
            'remediation_priority': 1
        }
    
    # Cryptocurrency mining or resource abuse
    elif any(keyword in title for keyword in ['mining', 'cryptocurrency', 'bitcoin', 'resource abuse']):
        return {
            'category': 'RESOURCE_ABUSE_DETECTED',
            'action': 'TERMINATE_RESOURCE',
            'escalate': True,
            'risk_level': 'HIGH',
            'business_impact': 'MEDIUM',
            'response_time': 'IMMEDIATE',
            'remediation_priority': 2
        }
    
    # Default critical classification
    else:
        return {
            'category': 'CRITICAL_SECURITY_ISSUE',
            'action': 'INVESTIGATE_IMMEDIATELY',
            'escalate': True,
            'risk_level': 'CRITICAL',
            'business_impact': 'HIGH',
            'response_time': 'IMMEDIATE',
            'remediation_priority': 1
        }


def classify_high_finding(title: str, description: str, resources: List[Dict], finding_types: List[str]) -> Dict[str, Any]:
    """Classify high severity findings with appropriate response actions."""
    
    # Multi-Factor Authentication issues
    if any(keyword in title for keyword in ['mfa', 'multi-factor', '2fa', 'two-factor']):
        return {
            'category': 'MFA_COMPLIANCE_ISSUE',
            'action': 'ENFORCE_MFA_POLICY',
            'escalate': False,
            'risk_level': 'HIGH',
            'business_impact': 'MEDIUM',
            'response_time': '1_HOUR',
            'remediation_priority': 3
        }
    
    # Encryption compliance issues
    elif any(keyword in title for keyword in ['encryption', 'encrypted', 'ssl', 'tls', 'https']):
        return {
            'category': 'ENCRYPTION_COMPLIANCE',
            'action': 'ENABLE_ENCRYPTION',
            'escalate': False,
            'risk_level': 'HIGH',
            'business_impact': 'MEDIUM',
            'response_time': '2_HOURS',
            'remediation_priority': 3
        }
    
    # Network security issues
    elif any(keyword in title for keyword in ['security group', 'open', 'exposed', 'internet']):
        return {
            'category': 'NETWORK_SECURITY_ISSUE',
            'action': 'RESTRICT_NETWORK_ACCESS',
            'escalate': False,
            'risk_level': 'HIGH',
            'business_impact': 'MEDIUM',
            'response_time': '1_HOUR',
            'remediation_priority': 2
        }
    
    # IAM permission issues
    elif any(keyword in title for keyword in ['iam', 'permission', 'policy', 'access']):
        return {
            'category': 'IAM_SECURITY_ISSUE',
            'action': 'REVIEW_PERMISSIONS',
            'escalate': False,
            'risk_level': 'HIGH',
            'business_impact': 'MEDIUM',
            'response_time': '2_HOURS',
            'remediation_priority': 3
        }
    
    # Default high severity classification
    else:
        return {
            'category': 'HIGH_SECURITY_ISSUE',
            'action': 'SCHEDULE_REMEDIATION',
            'escalate': False,
            'risk_level': 'HIGH',
            'business_impact': 'MEDIUM',
            'response_time': '4_HOURS',
            'remediation_priority': 4
        }


def classify_medium_finding(title: str, description: str, resources: List[Dict], finding_types: List[str]) -> Dict[str, Any]:
    """Classify medium severity findings for standard remediation workflow."""
    
    # Configuration compliance issues
    if any(keyword in title for keyword in ['configuration', 'config', 'compliance', 'standard']):
        return {
            'category': 'COMPLIANCE_ISSUE',
            'action': 'UPDATE_CONFIGURATION',
            'escalate': False,
            'risk_level': 'MEDIUM',
            'business_impact': 'LOW',
            'response_time': '24_HOURS',
            'remediation_priority': 5
        }
    
    # Logging and monitoring issues
    elif any(keyword in title for keyword in ['logging', 'cloudtrail', 'monitoring', 'audit']):
        return {
            'category': 'MONITORING_COMPLIANCE',
            'action': 'ENABLE_LOGGING',
            'escalate': False,
            'risk_level': 'MEDIUM',
            'business_impact': 'LOW',
            'response_time': '8_HOURS',
            'remediation_priority': 6
        }
    
    # Backup and recovery issues
    elif any(keyword in title for keyword in ['backup', 'snapshot', 'recovery']):
        return {
            'category': 'BACKUP_COMPLIANCE',
            'action': 'CONFIGURE_BACKUP',
            'escalate': False,
            'risk_level': 'MEDIUM',
            'business_impact': 'LOW',
            'response_time': '24_HOURS',
            'remediation_priority': 7
        }
    
    # Default medium severity classification
    else:
        return {
            'category': 'STANDARD_COMPLIANCE_ISSUE',
            'action': 'TRACK_FOR_REMEDIATION',
            'escalate': False,
            'risk_level': 'MEDIUM',
            'business_impact': 'LOW',
            'response_time': '72_HOURS',
            'remediation_priority': 8
        }


def classify_low_finding(title: str, description: str, resources: List[Dict], finding_types: List[str]) -> Dict[str, Any]:
    """Classify low severity and informational findings."""
    
    # Informational findings
    if any(keyword in title for keyword in ['informational', 'info', 'notice']):
        return {
            'category': 'INFORMATIONAL',
            'action': 'ACKNOWLEDGE',
            'escalate': False,
            'risk_level': 'LOW',
            'business_impact': 'NONE',
            'response_time': '7_DAYS',
            'remediation_priority': 10
        }
    
    # Best practice recommendations
    elif any(keyword in title for keyword in ['recommendation', 'best practice', 'optimization']):
        return {
            'category': 'BEST_PRACTICE_RECOMMENDATION',
            'action': 'SCHEDULE_IMPROVEMENT',
            'escalate': False,
            'risk_level': 'LOW',
            'business_impact': 'NONE',
            'response_time': '30_DAYS',
            'remediation_priority': 9
        }
    
    # Default low severity classification
    else:
        return {
            'category': 'LOW_PRIORITY_ISSUE',
            'action': 'TRACK_FOR_REVIEW',
            'escalate': False,
            'risk_level': 'LOW',
            'business_impact': 'NONE',
            'response_time': '7_DAYS',
            'remediation_priority': 10
        }


def get_resource_context(resources: List[Dict]) -> Dict[str, Any]:
    """Extract context information from finding resources."""
    context = {
        'resource_types': [],
        'regions': set(),
        'is_public_facing': False,
        'is_production': False
    }
    
    for resource in resources:
        resource_type = resource.get('Type', 'Unknown')
        region = resource.get('Region', 'Unknown')
        
        context['resource_types'].append(resource_type)
        context['regions'].add(region)
        
        # Check for public-facing resources
        if any(keyword in resource_type.lower() for keyword in ['elb', 'cloudfront', 'api', 'public']):
            context['is_public_facing'] = True
        
        # Check for production indicators
        resource_id = resource.get('Id', '').lower()
        if any(keyword in resource_id for keyword in ['prod', 'production', 'live']):
            context['is_production'] = True
    
    context['regions'] = list(context['regions'])
    return context