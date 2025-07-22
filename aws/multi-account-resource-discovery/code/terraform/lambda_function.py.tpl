"""
Multi-Account Resource Discovery and Compliance Processing Lambda Function

This function processes AWS Config compliance events and Resource Explorer updates
to automate governance actions, generate insights, and maintain compliance across
a multi-account environment.

Environment Variables:
- PROJECT_NAME: Name of the project for logging and identification
- CONFIG_AGGREGATOR_NAME: Name of the Config aggregator
- ORGANIZATION_ID: AWS Organizations ID
- NOTIFICATION_TOPIC_ARN: SNS topic for notifications (optional)
- LOG_LEVEL: Logging level (INFO, DEBUG, WARNING, ERROR)
"""

import json
import boto3
import logging
import os
from datetime import datetime, timezone
from typing import Dict, Any, List, Optional

# Configure logging
log_level = os.environ.get('LOG_LEVEL', 'INFO').upper()
logging.basicConfig(
    level=getattr(logging, log_level),
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# Initialize AWS clients
config_client = boto3.client('config')
resource_explorer_client = boto3.client('resource-explorer-2')
organizations_client = boto3.client('organizations')
sns_client = boto3.client('sns') if os.environ.get('NOTIFICATION_TOPIC_ARN') else None

# Environment variables
PROJECT_NAME = os.environ.get('PROJECT_NAME', 'multi-account-discovery')
CONFIG_AGGREGATOR_NAME = os.environ.get('CONFIG_AGGREGATOR_NAME', 'organization-aggregator')
ORGANIZATION_ID = os.environ.get('ORGANIZATION_ID', '')
NOTIFICATION_TOPIC_ARN = os.environ.get('NOTIFICATION_TOPIC_ARN', '${notification_topic_arn}')

def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Main handler for multi-account resource discovery events
    
    Processes:
    - AWS Config compliance change events
    - Scheduled resource discovery tasks
    - Resource Explorer events
    """
    logger.info(f"Processing event from source: %{event.get('source', 'unknown')}")
    logger.debug(f"Full event: %{json.dumps(event, default=str, indent=2)}")
    
    try:
        # Route event based on source
        if event.get('source') == 'aws.config':
            return process_config_event(event, context)
        
        elif event.get('source') == 'aws.resource-explorer-2':
            return process_resource_explorer_event(event, context)
        
        elif (event.get('source') == 'aws.events' and 
              'Scheduled Event' in event.get('detail-type', '')):
            return process_scheduled_discovery(event, context)
        
        else:
            logger.warning(f"Unknown event source: %{event.get('source')}")
            return create_response(200, 'Unknown event source processed')
            
    except Exception as e:
        logger.error(f"Error processing event: %{str(e)}", exc_info=True)
        
        # Send error notification if configured
        if sns_client and NOTIFICATION_TOPIC_ARN:
            try:
                send_notification(
                    "Lambda Processing Error",
                    f"Error in %{PROJECT_NAME} Lambda function: %{str(e)}"
                )
            except Exception as notify_error:
                logger.error(f"Failed to send error notification: %{notify_error}")
        
        raise

def process_config_event(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Process AWS Config compliance change events
    
    Handles compliance violations and triggers appropriate responses
    """
    detail = event.get('detail', {})
    
    # Extract compliance information
    compliance_info = extract_compliance_info(detail)
    
    logger.info(f"Config compliance event processed:")
    logger.info(f"  Resource: %{compliance_info['resource_type']} (%{compliance_info['resource_id']})")
    logger.info(f"  Account: %{compliance_info['account_id']}")
    logger.info(f"  Region: %{compliance_info['region']}")
    logger.info(f"  Rule: %{compliance_info['rule_name']}")
    logger.info(f"  Compliance: %{compliance_info['compliance_type']}")
    
    # Handle non-compliant resources
    if compliance_info['compliance_type'] == 'NON_COMPLIANT':
        handle_compliance_violation(compliance_info, detail)
        
        # Get aggregated compliance summary for organization
        try:
            compliance_summary = get_organizational_compliance_summary()
            log_compliance_summary(compliance_summary)
        except Exception as e:
            logger.warning(f"Failed to get compliance summary: %{e}")
    
    return create_response(200, 'Config compliance event processed', {
        'compliance_processed': True,
        'resource_info': compliance_info
    })

def process_resource_explorer_event(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Process Resource Explorer events for cross-account resource discovery
    """
    logger.info("Processing Resource Explorer event for cross-account discovery")
    
    try:
        # Perform sample resource discovery queries
        discovery_results = perform_resource_discovery()
        
        logger.info(f"Resource discovery completed:")
        for result in discovery_results:
            logger.info(f"  %{result['query']}: %{result['count']} resources found")
        
        return create_response(200, 'Resource Explorer event processed', {
            'discovery_processed': True,
            'discovery_results': discovery_results
        })
        
    except Exception as e:
        logger.error(f"Error in Resource Explorer processing: %{e}")
        return create_response(500, f'Resource Explorer processing failed: %{e}')

def process_scheduled_discovery(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Process scheduled resource discovery tasks
    
    Performs comprehensive organizational resource discovery and compliance checks
    """
    logger.info("Starting scheduled resource discovery scan")
    
    try:
        # Get organization account information
        org_accounts = get_organization_accounts()
        logger.info(f"Organization has %{len(org_accounts)} active accounts")
        
        # Perform comprehensive resource discovery
        discovery_results = perform_comprehensive_discovery()
        
        # Get compliance summary across the organization
        compliance_summary = get_organizational_compliance_summary()
        
        # Generate and log summary report
        summary_report = generate_discovery_summary(
            org_accounts, discovery_results, compliance_summary
        )
        
        logger.info("Scheduled discovery summary:")
        logger.info(f"  Total Accounts: %{summary_report['total_accounts']}")
        logger.info(f"  Total Resources Discovered: %{summary_report['total_resources']}")
        logger.info(f"  Compliant Rules: %{summary_report['compliant_rules']}")
        logger.info(f"  Non-Compliant Rules: %{summary_report['non_compliant_rules']}")
        
        # Send notification if significant issues found
        if (summary_report['non_compliant_rules'] > 0 and 
            sns_client and NOTIFICATION_TOPIC_ARN):
            send_discovery_notification(summary_report)
        
        return create_response(200, 'Scheduled discovery completed', {
            'scheduled_discovery_complete': True,
            'summary_report': summary_report
        })
        
    except Exception as e:
        logger.error(f"Error in scheduled discovery: %{e}")
        return create_response(500, f'Scheduled discovery failed: %{e}')

def extract_compliance_info(detail: Dict[str, Any]) -> Dict[str, Any]:
    """Extract compliance information from Config event detail"""
    new_evaluation = detail.get('newEvaluationResult', {})
    
    return {
        'resource_type': detail.get('resourceType', 'Unknown'),
        'resource_id': detail.get('resourceId', 'Unknown'),
        'account_id': detail.get('awsAccountId', 'Unknown'),
        'region': detail.get('awsRegion', 'Unknown'),
        'rule_name': detail.get('configRuleName', 'Unknown'),
        'compliance_type': new_evaluation.get('complianceType', 'Unknown'),
        'evaluation_result_identifier': new_evaluation.get('evaluationResultIdentifier', {}),
        'result_recorded_time': new_evaluation.get('resultRecordedTime', 'Unknown')
    }

def handle_compliance_violation(compliance_info: Dict[str, Any], detail: Dict[str, Any]) -> None:
    """
    Handle compliance violations with detailed logging and potential remediation
    """
    logger.warning(f"COMPLIANCE VIOLATION DETECTED:")
    logger.warning(f"  Rule: %{compliance_info['rule_name']}")
    logger.warning(f"  Resource: %{compliance_info['resource_type']}")
    logger.warning(f"  Resource ID: %{compliance_info['resource_id']}")
    logger.warning(f"  Account: %{compliance_info['account_id']}")
    logger.warning(f"  Region: %{compliance_info['region']}")
    logger.warning(f"  Recorded Time: %{compliance_info['result_recorded_time']}")
    
    # Add compliance violation metadata for structured logging
    violation_metadata = {
        'event_type': 'compliance_violation',
        'severity': get_rule_severity(compliance_info['rule_name']),
        'rule_name': compliance_info['rule_name'],
        'resource_type': compliance_info['resource_type'],
        'account_id': compliance_info['account_id'],
        'region': compliance_info['region'],
        'timestamp': datetime.now(timezone.utc).isoformat()
    }
    
    logger.info(f"Violation metadata: %{json.dumps(violation_metadata)}")
    
    # Send notification for high-severity violations
    if (violation_metadata['severity'] in ['HIGH', 'CRITICAL'] and 
        sns_client and NOTIFICATION_TOPIC_ARN):
        try:
            send_compliance_notification(compliance_info, violation_metadata)
        except Exception as e:
            logger.error(f"Failed to send compliance notification: %{e}")

def get_rule_severity(rule_name: str) -> str:
    """Determine rule severity based on rule name patterns"""
    rule_name_lower = rule_name.lower()
    
    if any(keyword in rule_name_lower for keyword in ['root', 'admin', 'privileged']):
        return 'CRITICAL'
    elif any(keyword in rule_name_lower for keyword in ['public', 'encryption', 'security']):
        return 'HIGH'
    elif any(keyword in rule_name_lower for keyword in ['password', 'access', 'policy']):
        return 'MEDIUM'
    else:
        return 'LOW'

def perform_resource_discovery() -> List[Dict[str, Any]]:
    """
    Perform targeted resource discovery across the organization
    """
    discovery_queries = [
        {
            'name': 'EC2 Instances',
            'query': 'resourcetype:AWS::EC2::Instance',
            'description': 'All EC2 instances across accounts'
        },
        {
            'name': 'S3 Buckets',
            'query': 'service:s3',
            'description': 'All S3 buckets across accounts'
        },
        {
            'name': 'RDS Databases',
            'query': 'service:rds',
            'description': 'All RDS resources across accounts'
        },
        {
            'name': 'Lambda Functions',
            'query': 'service:lambda',
            'description': 'All Lambda functions across accounts'
        }
    ]
    
    results = []
    
    for query_info in discovery_queries:
        try:
            response = resource_explorer_client.search(
                QueryString=query_info['query'],
                MaxResults=100
            )
            
            resource_count = len(response.get('Resources', []))
            
            results.append({
                'query': query_info['name'],
                'query_string': query_info['query'],
                'count': resource_count,
                'description': query_info['description']
            })
            
            logger.debug(f"Query '%{query_info['name']}' found %{resource_count} resources")
            
        except Exception as e:
            logger.warning(f"Failed to execute query '%{query_info['name']}': %{e}")
            results.append({
                'query': query_info['name'],
                'query_string': query_info['query'],
                'count': 0,
                'error': str(e),
                'description': query_info['description']
            })
    
    return results

def perform_comprehensive_discovery() -> Dict[str, Any]:
    """
    Perform comprehensive resource discovery with detailed analysis
    """
    logger.info("Performing comprehensive organizational resource discovery")
    
    try:
        # Search for all resources
        all_resources_response = resource_explorer_client.search(
            QueryString="*",
            MaxResults=1000  # Increase for larger organizations
        )
        
        resources = all_resources_response.get('Resources', [])
        total_resources = len(resources)
        
        # Analyze resources by type and account
        resource_analysis = analyze_resources_by_type_and_account(resources)
        
        logger.info(f"Comprehensive discovery found %{total_resources} total resources")
        
        return {
            'total_resources': total_resources,
            'resource_analysis': resource_analysis,
            'timestamp': datetime.now(timezone.utc).isoformat()
        }
        
    except Exception as e:
        logger.error(f"Error in comprehensive discovery: %{e}")
        return {
            'total_resources': 0,
            'error': str(e),
            'timestamp': datetime.now(timezone.utc).isoformat()
        }

def analyze_resources_by_type_and_account(resources: List[Dict[str, Any]]) -> Dict[str, Any]:
    """
    Analyze discovered resources by type and account
    """
    analysis = {
        'by_type': {},
        'by_account': {},
        'by_region': {}
    }
    
    for resource in resources:
        # Analyze by resource type
        resource_type = resource.get('ResourceType', 'Unknown')
        analysis['by_type'][resource_type] = analysis['by_type'].get(resource_type, 0) + 1
        
        # Analyze by account
        account_id = resource.get('OwningAccountId', 'Unknown')
        analysis['by_account'][account_id] = analysis['by_account'].get(account_id, 0) + 1
        
        # Analyze by region
        region = resource.get('Region', 'Unknown')
        analysis['by_region'][region] = analysis['by_region'].get(region, 0) + 1
    
    return analysis

def get_organization_accounts() -> List[Dict[str, Any]]:
    """
    Get list of active organization accounts
    """
    try:
        response = organizations_client.list_accounts()
        accounts = [
            account for account in response.get('Accounts', [])
            if account.get('Status') == 'ACTIVE'
        ]
        
        logger.debug(f"Found %{len(accounts)} active accounts in organization")
        return accounts
        
    except Exception as e:
        logger.warning(f"Failed to get organization accounts: %{e}")
        return []

def get_organizational_compliance_summary() -> Dict[str, Any]:
    """
    Get compliance summary across the organization using Config aggregator
    """
    try:
        response = config_client.get_aggregate_compliance_summary(
            ConfigurationAggregatorName=CONFIG_AGGREGATOR_NAME
        )
        
        summary = response.get('AggregateComplianceSummary', {})
        
        return {
            'compliant_rule_count': summary.get('CompliantRuleCount', 0),
            'non_compliant_rule_count': summary.get('NonCompliantRuleCount', 0),
            'compliance_summary_timestamp': summary.get('ComplianceSummaryTimestamp', ''),
            'raw_summary': summary
        }
        
    except Exception as e:
        logger.warning(f"Failed to get organizational compliance summary: %{e}")
        return {
            'compliant_rule_count': 0,
            'non_compliant_rule_count': 0,
            'error': str(e)
        }

def log_compliance_summary(compliance_summary: Dict[str, Any]) -> None:
    """
    Log compliance summary in structured format
    """
    logger.info("Organizational Compliance Summary:")
    logger.info(f"  Compliant Rules: %{compliance_summary.get('compliant_rule_count', 0)}")
    logger.info(f"  Non-Compliant Rules: %{compliance_summary.get('non_compliant_rule_count', 0)}")
    
    if compliance_summary.get('compliance_summary_timestamp'):
        logger.info(f"  Last Updated: %{compliance_summary['compliance_summary_timestamp']}")

def generate_discovery_summary(
    org_accounts: List[Dict[str, Any]], 
    discovery_results: Dict[str, Any], 
    compliance_summary: Dict[str, Any]
) -> Dict[str, Any]:
    """
    Generate comprehensive discovery summary report
    """
    return {
        'total_accounts': len(org_accounts),
        'total_resources': discovery_results.get('total_resources', 0),
        'compliant_rules': compliance_summary.get('compliant_rule_count', 0),
        'non_compliant_rules': compliance_summary.get('non_compliant_rule_count', 0),
        'discovery_timestamp': discovery_results.get('timestamp', ''),
        'organization_id': ORGANIZATION_ID,
        'project_name': PROJECT_NAME
    }

def send_notification(subject: str, message: str) -> None:
    """
    Send SNS notification if topic is configured
    """
    if not (sns_client and NOTIFICATION_TOPIC_ARN):
        logger.debug("SNS notifications not configured")
        return
    
    try:
        sns_client.publish(
            TopicArn=NOTIFICATION_TOPIC_ARN,
            Subject=f"[%{PROJECT_NAME}] %{subject}",
            Message=message
        )
        logger.info(f"Notification sent: %{subject}")
        
    except Exception as e:
        logger.error(f"Failed to send notification: %{e}")

def send_compliance_notification(
    compliance_info: Dict[str, Any], 
    violation_metadata: Dict[str, Any]
) -> None:
    """
    Send detailed compliance violation notification
    """
    subject = f"%{violation_metadata['severity']} Compliance Violation"
    
    message = f"""
Compliance Violation Detected in %{PROJECT_NAME}

Severity: %{violation_metadata['severity']}
Rule: %{compliance_info['rule_name']}
Resource Type: %{compliance_info['resource_type']}
Resource ID: %{compliance_info['resource_id']}
Account: %{compliance_info['account_id']}
Region: %{compliance_info['region']}
Detected At: %{violation_metadata['timestamp']}

Please review and take appropriate remediation action.
    """.strip()
    
    send_notification(subject, message)

def send_discovery_notification(summary_report: Dict[str, Any]) -> None:
    """
    Send scheduled discovery summary notification
    """
    subject = "Scheduled Resource Discovery Summary"
    
    message = f"""
Multi-Account Resource Discovery Summary for %{PROJECT_NAME}

Organization Overview:
- Total Accounts: %{summary_report['total_accounts']}
- Total Resources Discovered: %{summary_report['total_resources']}

Compliance Status:
- Compliant Rules: %{summary_report['compliant_rules']}
- Non-Compliant Rules: %{summary_report['non_compliant_rules']}

Discovery completed at: %{summary_report['discovery_timestamp']}

%{"Review AWS Config dashboard for detailed compliance information." if summary_report['non_compliant_rules'] > 0 else "All compliance rules are currently passing."}
    """.strip()
    
    send_notification(subject, message)

def create_response(status_code: int, message: str, data: Optional[Dict[str, Any]] = None) -> Dict[str, Any]:
    """
    Create standardized Lambda response
    """
    response = {
        'statusCode': status_code,
        'message': message,
        'timestamp': datetime.now(timezone.utc).isoformat(),
        'project': PROJECT_NAME
    }
    
    if data:
        response.update(data)
    
    return response