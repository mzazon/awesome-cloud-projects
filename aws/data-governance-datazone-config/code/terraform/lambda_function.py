"""
Lambda function for processing data governance events from AWS Config
and updating Amazon DataZone metadata for compliance tracking.
"""

import json
import boto3
import logging
import os
from datetime import datetime
from botocore.exceptions import ClientError

# Configure logging
logger = logging.getLogger()
logger.setLevel(os.environ.get('LOG_LEVEL', 'INFO'))

def lambda_handler(event, context):
    """
    Process governance events and update DataZone metadata
    
    Args:
        event: EventBridge event from AWS Config
        context: Lambda context object
        
    Returns:
        dict: Response with status and processing details
    """
    
    try:
        logger.info(f"Received governance event: {json.dumps(event, default=str)}")
        
        # Parse EventBridge event structure
        detail = event.get('detail', {})
        config_item = detail.get('configurationItem', {})
        compliance_result = detail.get('newEvaluationResult', {})
        compliance_type = compliance_result.get('complianceType', 'UNKNOWN')
        
        resource_type = config_item.get('resourceType', '')
        resource_id = config_item.get('resourceId', '')
        resource_arn = config_item.get('arn', '')
        config_rule_name = compliance_result.get('configRuleName', '')
        
        logger.info(f"Processing governance event for {resource_type}: {resource_id}")
        logger.info(f"Compliance status: {compliance_type}")
        logger.info(f"Config rule: {config_rule_name}")
        
        # Initialize AWS clients with error handling
        try:
            config_client = boto3.client('config')
            sns_client = boto3.client('sns')
            # DataZone client initialization (commented out for regions where not available)
            # datazone_client = boto3.client('datazone')
        except Exception as e:
            logger.error(f"Failed to initialize AWS clients: {str(e)}")
            raise
        
        # Create comprehensive governance metadata
        governance_metadata = {
            'eventType': 'CONFIG_COMPLIANCE_CHANGE',
            'resourceId': resource_id,
            'resourceType': resource_type,
            'resourceArn': resource_arn,
            'complianceStatus': compliance_type,
            'evaluationTimestamp': compliance_result.get('resultRecordedTime', ''),
            'configRuleName': config_rule_name,
            'awsAccountId': detail.get('awsAccountId', os.environ.get('AWS_ACCOUNT_ID', '')),
            'awsRegion': detail.get('awsRegion', os.environ.get('AWS_REGION', '')),
            'processedAt': datetime.utcnow().isoformat(),
            'severity': determine_violation_severity(config_rule_name, compliance_type),
            'category': categorize_governance_rule(config_rule_name)
        }
        
        # Log governance event for comprehensive audit trail
        logger.info(f"Governance metadata: {json.dumps(governance_metadata, default=str)}")
        
        # Process compliance violations with detailed handling
        response_metadata = process_compliance_event(
            governance_metadata, 
            config_client, 
            sns_client
        )
        
        # Prepare comprehensive response
        response_body = {
            'statusCode': 200,
            'message': 'Governance event processed successfully',
            'metadata': governance_metadata,
            'processing': response_metadata,
            'processedResources': 1,
            'timestamp': datetime.utcnow().isoformat()
        }
        
        logger.info(f"Processing completed successfully: {json.dumps(response_body, default=str)}")
        
        return {
            'statusCode': 200,
            'body': json.dumps(response_body, default=str)
        }
        
    except ClientError as e:
        error_code = e.response['Error']['Code']
        error_message = e.response['Error']['Message']
        logger.error(f"AWS service error ({error_code}): {error_message}")
        
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': f'AWS service error: {error_code}',
                'message': error_message,
                'timestamp': datetime.utcnow().isoformat()
            })
        }
        
    except Exception as e:
        logger.error(f"Unexpected error processing governance event: {str(e)}", exc_info=True)
        
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': 'Internal processing error',
                'message': str(e),
                'timestamp': datetime.utcnow().isoformat()
            })
        }

def process_compliance_event(metadata, config_client, sns_client):
    """
    Process compliance events and trigger appropriate actions
    
    Args:
        metadata: Governance metadata dictionary
        config_client: AWS Config boto3 client
        sns_client: AWS SNS boto3 client
        
    Returns:
        dict: Processing results and actions taken
    """
    
    compliance_status = metadata['complianceStatus']
    resource_id = metadata['resourceId']
    resource_type = metadata['resourceType']
    config_rule_name = metadata['configRuleName']
    severity = metadata['severity']
    
    processing_results = {
        'actionsPerformed': [],
        'notifications': [],
        'errors': []
    }
    
    try:
        # Handle compliance violations
        if compliance_status == 'NON_COMPLIANT':
            logger.warning(f"Compliance violation detected for {resource_type}: {resource_id}")
            
            # Get detailed compliance information
            try:
                compliance_details = get_compliance_details(
                    config_client, 
                    config_rule_name, 
                    resource_id, 
                    resource_type
                )
                processing_results['complianceDetails'] = compliance_details
                processing_results['actionsPerformed'].append('retrieved_compliance_details')
                
            except Exception as e:
                logger.error(f"Failed to get compliance details: {str(e)}")
                processing_results['errors'].append(f"compliance_details_error: {str(e)}")
            
            # Create violation summary
            violation_summary = {
                'violationType': 'COMPLIANCE_VIOLATION',
                'severity': severity,
                'resource': resource_id,
                'resourceType': resource_type,
                'rule': config_rule_name,
                'requiresAttention': True,
                'detectedAt': metadata['evaluationTimestamp'],
                'category': metadata['category'],
                'recommendedActions': get_remediation_recommendations(config_rule_name)
            }
            
            logger.info(f"Violation summary: {json.dumps(violation_summary)}")
            processing_results['violationSummary'] = violation_summary
            processing_results['actionsPerformed'].append('created_violation_summary')
            
            # Send notification for high-severity violations
            if severity in ['HIGH', 'CRITICAL']:
                try:
                    notification_result = send_governance_notification(
                        sns_client, 
                        violation_summary, 
                        metadata
                    )
                    processing_results['notifications'].append(notification_result)
                    processing_results['actionsPerformed'].append('sent_notification')
                    
                except Exception as e:
                    logger.error(f"Failed to send notification: {str(e)}")
                    processing_results['errors'].append(f"notification_error: {str(e)}")
            
            # In production environments, implement specific remediation logic:
            # 1. Update DataZone asset metadata with compliance status
            # 2. Create governance incidents in tracking systems
            # 3. Trigger automated remediation workflows based on rule type
            # 4. Update compliance dashboards and reports
            # 5. Integrate with security information and event management (SIEM) systems
            
            processing_results['actionsPerformed'].append('logged_violation')
            
        elif compliance_status == 'COMPLIANT':
            logger.info(f"Resource {resource_id} is compliant with rule {config_rule_name}")
            processing_results['actionsPerformed'].append('logged_compliance')
            
            # Update governance metadata to reflect compliant status
            compliance_update = {
                'status': 'COMPLIANT',
                'verifiedAt': metadata['evaluationTimestamp'],
                'rule': config_rule_name
            }
            processing_results['complianceUpdate'] = compliance_update
            
        else:
            logger.warning(f"Unknown compliance status: {compliance_status}")
            processing_results['warnings'] = [f"Unknown compliance status: {compliance_status}"]
        
        return processing_results
        
    except Exception as e:
        logger.error(f"Error in compliance event processing: {str(e)}")
        processing_results['errors'].append(f"processing_error: {str(e)}")
        return processing_results

def get_compliance_details(config_client, rule_name, resource_id, resource_type):
    """
    Retrieve detailed compliance information from AWS Config
    
    Args:
        config_client: AWS Config boto3 client
        rule_name: Name of the Config rule
        resource_id: ID of the resource
        resource_type: Type of the AWS resource
        
    Returns:
        dict: Detailed compliance information
    """
    
    try:
        # Get compliance details by Config rule
        response = config_client.get_compliance_details_by_config_rule(
            ConfigRuleName=rule_name,
            ComplianceTypes=['NON_COMPLIANT', 'COMPLIANT'],
            Limit=10
        )
        
        compliance_details = {
            'ruleName': rule_name,
            'evaluationResults': response.get('EvaluationResults', []),
            'retrievedAt': datetime.utcnow().isoformat()
        }
        
        # Filter results for the specific resource if found
        for result in compliance_details['evaluationResults']:
            if (result.get('EvaluationResultIdentifier', {}).get('EvaluationResultQualifier', {}).get('ResourceId') == resource_id):
                compliance_details['specificResourceResult'] = result
                break
        
        return compliance_details
        
    except ClientError as e:
        logger.error(f"AWS Config API error: {e}")
        raise
    except Exception as e:
        logger.error(f"Unexpected error getting compliance details: {e}")
        raise

def send_governance_notification(sns_client, violation_summary, metadata):
    """
    Send governance violation notification via SNS
    
    Args:
        sns_client: AWS SNS boto3 client
        violation_summary: Dictionary containing violation details
        metadata: Governance metadata
        
    Returns:
        dict: Notification sending results
    """
    
    sns_topic_arn = os.environ.get('SNS_TOPIC_ARN')
    if not sns_topic_arn:
        logger.warning("SNS_TOPIC_ARN not configured, skipping notification")
        return {'status': 'skipped', 'reason': 'no_topic_configured'}
    
    try:
        # Create detailed notification message
        notification_message = {
            'alert': 'Data Governance Compliance Violation',
            'severity': violation_summary['severity'],
            'resource': {
                'id': violation_summary['resource'],
                'type': violation_summary['resourceType'],
                'arn': metadata.get('resourceArn', 'N/A')
            },
            'violation': {
                'rule': violation_summary['rule'],
                'category': violation_summary['category'],
                'detectedAt': violation_summary['detectedAt']
            },
            'recommendations': violation_summary['recommendedActions'],
            'account': metadata['awsAccountId'],
            'region': metadata['awsRegion'],
            'timestamp': datetime.utcnow().isoformat()
        }
        
        # Create human-readable subject
        subject = f"🚨 Data Governance Alert: {violation_summary['severity']} violation in {metadata['awsRegion']}"
        
        # Send notification
        response = sns_client.publish(
            TopicArn=sns_topic_arn,
            Subject=subject,
            Message=json.dumps(notification_message, indent=2, default=str)
        )
        
        logger.info(f"Notification sent successfully: MessageId {response['MessageId']}")
        
        return {
            'status': 'sent',
            'messageId': response['MessageId'],
            'topicArn': sns_topic_arn,
            'subject': subject
        }
        
    except ClientError as e:
        logger.error(f"SNS publish error: {e}")
        raise
    except Exception as e:
        logger.error(f"Unexpected error sending notification: {e}")
        raise

def determine_violation_severity(config_rule_name, compliance_type):
    """
    Determine severity level based on Config rule name and compliance status
    
    Args:
        config_rule_name: Name of the AWS Config rule
        compliance_type: Compliance status (COMPLIANT/NON_COMPLIANT)
        
    Returns:
        str: Severity level (LOW/MEDIUM/HIGH/CRITICAL)
    """
    
    if compliance_type == 'COMPLIANT':
        return 'NONE'
    
    # Define severity mapping based on rule types
    high_severity_rules = [
        's3-bucket-server-side-encryption-enabled',
        'rds-storage-encrypted',
        's3-bucket-ssl-requests-only'
    ]
    
    critical_severity_rules = [
        's3-bucket-public-read-prohibited',
        's3-bucket-public-write-prohibited',
        'rds-instance-public-access-check'
    ]
    
    if config_rule_name in critical_severity_rules:
        return 'CRITICAL'
    elif config_rule_name in high_severity_rules:
        return 'HIGH'
    elif 'encryption' in config_rule_name.lower():
        return 'HIGH'
    elif 'public' in config_rule_name.lower():
        return 'CRITICAL'
    else:
        return 'MEDIUM'

def categorize_governance_rule(config_rule_name):
    """
    Categorize the governance rule for better organization
    
    Args:
        config_rule_name: Name of the AWS Config rule
        
    Returns:
        str: Category of the governance rule
    """
    
    if 'encryption' in config_rule_name.lower():
        return 'DATA_PROTECTION'
    elif 'public' in config_rule_name.lower():
        return 'ACCESS_CONTROL'
    elif 'backup' in config_rule_name.lower():
        return 'DATA_RESILIENCE'
    elif 'logging' in config_rule_name.lower():
        return 'AUDIT_TRAIL'
    elif 's3' in config_rule_name.lower():
        return 'STORAGE_GOVERNANCE'
    elif 'rds' in config_rule_name.lower() or 'database' in config_rule_name.lower():
        return 'DATABASE_GOVERNANCE'
    else:
        return 'GENERAL_COMPLIANCE'

def get_remediation_recommendations(config_rule_name):
    """
    Provide remediation recommendations based on the Config rule
    
    Args:
        config_rule_name: Name of the AWS Config rule
        
    Returns:
        list: List of recommended remediation actions
    """
    
    recommendations = {
        's3-bucket-server-side-encryption-enabled': [
            'Enable default server-side encryption on the S3 bucket',
            'Use AES-256 or AWS KMS encryption',
            'Review bucket policy to enforce encryption in transit'
        ],
        'rds-storage-encrypted': [
            'Enable encryption at rest for RDS instances',
            'Use AWS KMS keys for encryption',
            'Consider automated snapshots encryption'
        ],
        's3-bucket-public-read-prohibited': [
            'Remove public read permissions from S3 bucket',
            'Review bucket ACLs and bucket policies',
            'Enable S3 Block Public Access settings',
            'Implement least privilege access principles'
        ]
    }
    
    return recommendations.get(config_rule_name, [
        'Review AWS Config rule documentation for remediation guidance',
        'Implement least privilege access principles',
        'Enable appropriate logging and monitoring',
        'Follow AWS security best practices'
    ])