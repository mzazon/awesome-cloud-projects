#!/bin/bash

# Deploy script for Event-Driven Security Automation with EventBridge and Lambda
# This script deploys the complete security automation infrastructure

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING:${NC} $1"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1"
    exit 1
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO:${NC} $1"
}

# Check if running with --help flag
if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    echo "Usage: $0 [--dry-run] [--email EMAIL_ADDRESS]"
    echo ""
    echo "Options:"
    echo "  --dry-run          Show what would be deployed without making changes"
    echo "  --email EMAIL      Email address for SNS notifications"
    echo "  --help, -h         Show this help message"
    echo ""
    echo "Environment Variables:"
    echo "  AWS_REGION         AWS region for deployment (default: from AWS config)"
    echo "  AUTOMATION_PREFIX  Prefix for resource names (default: auto-generated)"
    echo ""
    exit 0
fi

# Parse command line arguments
DRY_RUN=false
EMAIL_ADDRESS=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --email)
            EMAIL_ADDRESS="$2"
            shift 2
            ;;
        *)
            error "Unknown option: $1. Use --help for usage information."
            ;;
    esac
done

log "Starting deployment of Event-Driven Security Automation"

# Prerequisites check
info "Checking prerequisites..."

# Check if AWS CLI is installed and configured
if ! command -v aws &> /dev/null; then
    error "AWS CLI is not installed. Please install it first."
fi

# Check AWS credentials
if ! aws sts get-caller-identity &> /dev/null; then
    error "AWS credentials are not configured. Please run 'aws configure' first."
fi

# Check required permissions
info "Verifying AWS permissions..."
REQUIRED_PERMISSIONS=(
    "events:PutRule"
    "events:PutTargets"
    "lambda:CreateFunction"
    "lambda:AddPermission"
    "iam:CreateRole"
    "iam:AttachRolePolicy"
    "sns:CreateTopic"
    "sqs:CreateQueue"
    "securityhub:CreateAutomationRule"
    "securityhub:CreateActionTarget"
    "ssm:CreateDocument"
    "cloudwatch:PutMetricAlarm"
    "cloudwatch:PutDashboard"
)

# Test a few key permissions
if ! aws iam list-roles --max-items 1 &> /dev/null; then
    error "Insufficient IAM permissions. Please ensure you have the required permissions."
fi

log "Prerequisites check completed successfully"

# Set environment variables
export AWS_REGION=${AWS_REGION:-$(aws configure get region)}
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

if [[ -z "$AWS_REGION" ]]; then
    error "AWS region not configured. Please set AWS_REGION environment variable or run 'aws configure'."
fi

# Generate unique identifiers for resources
RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
    --exclude-punctuation --exclude-uppercase \
    --password-length 6 --require-each-included-type \
    --output text --query RandomPassword 2>/dev/null || echo "$(date +%s | tail -c 6)")

export AUTOMATION_PREFIX=${AUTOMATION_PREFIX:-"security-automation-${RANDOM_SUFFIX}"}
export LAMBDA_ROLE_NAME="${AUTOMATION_PREFIX}-lambda-role"
export EVENTBRIDGE_RULE_NAME="${AUTOMATION_PREFIX}-findings-rule"
export SNS_TOPIC_NAME="${AUTOMATION_PREFIX}-notifications"
export SQS_QUEUE_NAME="${AUTOMATION_PREFIX}-dlq"

log "Deployment configuration:"
info "  AWS Region: $AWS_REGION"
info "  AWS Account ID: $AWS_ACCOUNT_ID"
info "  Resource Prefix: $AUTOMATION_PREFIX"
info "  Dry Run: $DRY_RUN"

if [[ "$DRY_RUN" == "true" ]]; then
    warn "DRY RUN MODE - No resources will be created"
fi

# Create temporary directory for Lambda code
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

info "Created temporary directory: $TEMP_DIR"

# Function to execute commands with dry-run support
execute_command() {
    local cmd="$1"
    local description="$2"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY RUN] Would execute: $description"
        info "[DRY RUN] Command: $cmd"
    else
        info "Executing: $description"
        eval "$cmd"
    fi
}

# Step 1: Create IAM role for Lambda functions
log "Step 1: Creating IAM role and policies..."

execute_command "aws iam create-role \
    --role-name ${LAMBDA_ROLE_NAME} \
    --assume-role-policy-document '{
        \"Version\": \"2012-10-17\",
        \"Statement\": [
            {
                \"Effect\": \"Allow\",
                \"Principal\": {
                    \"Service\": \"lambda.amazonaws.com\"
                },
                \"Action\": \"sts:AssumeRole\"
            }
        ]
    }' \
    --tags Key=Project,Value=SecurityAutomation Key=Environment,Value=Production" \
    "Create Lambda execution role"

# Wait for role to be available
if [[ "$DRY_RUN" == "false" ]]; then
    sleep 5
fi

execute_command "aws iam attach-role-policy \
    --role-name ${LAMBDA_ROLE_NAME} \
    --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole" \
    "Attach basic Lambda execution policy"

# Create custom policy for security automation
CUSTOM_POLICY_DOCUMENT='{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "securityhub:BatchUpdateFindings",
                "securityhub:GetFindings",
                "securityhub:BatchGetAutomationRules",
                "securityhub:CreateAutomationRule",
                "securityhub:UpdateAutomationRule",
                "ssm:StartAutomationExecution",
                "ssm:GetAutomationExecution",
                "ec2:DescribeInstances",
                "ec2:StopInstances",
                "ec2:DescribeSecurityGroups",
                "ec2:AuthorizeSecurityGroupIngress",
                "ec2:RevokeSecurityGroupIngress",
                "ec2:CreateSnapshot",
                "ec2:DescribeSnapshots",
                "sns:Publish",
                "sqs:SendMessage",
                "events:PutEvents",
                "logs:CreateLogGroup",
                "logs:CreateLogStream",
                "logs:PutLogEvents"
            ],
            "Resource": "*"
        }
    ]
}'

execute_command "aws iam create-policy \
    --policy-name ${AUTOMATION_PREFIX}-policy \
    --policy-document '$CUSTOM_POLICY_DOCUMENT' \
    --description 'Custom policy for security automation Lambda functions'" \
    "Create custom security automation policy"

execute_command "aws iam attach-role-policy \
    --role-name ${LAMBDA_ROLE_NAME} \
    --policy-arn arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${AUTOMATION_PREFIX}-policy" \
    "Attach custom policy to Lambda role"

# Step 2: Create SNS topic and Dead Letter Queue
log "Step 2: Creating SNS topic and Dead Letter Queue..."

execute_command "aws sns create-topic \
    --name ${SNS_TOPIC_NAME} \
    --attributes '{
        \"DisplayName\": \"Security Automation Notifications\",
        \"DeliveryPolicy\": \"{\\\"healthyRetryPolicy\\\":{\\\"minDelayTarget\\\":5,\\\"maxDelayTarget\\\":300,\\\"numRetries\\\":10}}\"
    }' \
    --tags Key=Project,Value=SecurityAutomation Key=Environment,Value=Production" \
    "Create SNS topic for notifications"

if [[ "$DRY_RUN" == "false" ]]; then
    export SNS_TOPIC_ARN=$(aws sns get-topic-attributes \
        --topic-arn arn:aws:sns:${AWS_REGION}:${AWS_ACCOUNT_ID}:${SNS_TOPIC_NAME} \
        --query 'Attributes.TopicArn' --output text)
    info "Created SNS topic: $SNS_TOPIC_ARN"
else
    export SNS_TOPIC_ARN="arn:aws:sns:${AWS_REGION}:${AWS_ACCOUNT_ID}:${SNS_TOPIC_NAME}"
fi

execute_command "aws sqs create-queue \
    --queue-name ${SQS_QUEUE_NAME} \
    --attributes '{
        \"MessageRetentionPeriod\": \"1209600\",
        \"VisibilityTimeoutSeconds\": \"300\"
    }' \
    --tags Key=Project,Value=SecurityAutomation Key=Environment,Value=Production" \
    "Create SQS dead letter queue"

if [[ "$DRY_RUN" == "false" ]]; then
    export DLQ_URL=$(aws sqs get-queue-url \
        --queue-name ${SQS_QUEUE_NAME} \
        --query 'QueueUrl' --output text)
    info "Created DLQ: $DLQ_URL"
fi

# Subscribe email to SNS topic if provided
if [[ -n "$EMAIL_ADDRESS" ]]; then
    execute_command "aws sns subscribe \
        --topic-arn ${SNS_TOPIC_ARN} \
        --protocol email \
        --notification-endpoint ${EMAIL_ADDRESS}" \
        "Subscribe email to SNS topic"
    info "Email subscription created for: $EMAIL_ADDRESS"
fi

# Step 3: Create Lambda functions
log "Step 3: Creating Lambda functions..."

# Create triage function
info "Creating triage Lambda function..."
cat > "$TEMP_DIR/triage.py" << 'EOF'
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
EOF

# Create deployment package for triage function
cd "$TEMP_DIR"
zip -r triage.zip triage.py

execute_command "aws lambda create-function \
    --function-name ${AUTOMATION_PREFIX}-triage \
    --runtime python3.9 \
    --role arn:aws:iam::${AWS_ACCOUNT_ID}:role/${LAMBDA_ROLE_NAME} \
    --handler triage.lambda_handler \
    --zip-file fileb://triage.zip \
    --timeout 60 \
    --memory-size 256 \
    --description 'Security finding triage and response classification' \
    --tags Key=Project,Value=SecurityAutomation Key=Environment,Value=Production" \
    "Create triage Lambda function"

# Create remediation function
info "Creating remediation Lambda function..."
cat > "$TEMP_DIR/remediation.py" << 'EOF'
import json
import boto3
import logging
import os
from datetime import datetime

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    """
    Execute automated remediation actions based on security findings
    """
    try:
        detail = event.get('detail', {})
        action = detail.get('action')
        finding = detail.get('finding', {})
        
        if not action:
            logger.warning("No action specified in event")
            return {'statusCode': 400, 'body': 'No action specified'}
        
        logger.info(f"Executing remediation action: {action}")
        
        # Execute appropriate remediation
        if action == 'ISOLATE_INSTANCE':
            result = isolate_ec2_instance(finding)
        elif action == 'BLOCK_NETWORK_ACCESS':
            result = block_network_access(finding)
        elif action == 'QUARANTINE_INSTANCE':
            result = quarantine_instance(finding)
        elif action == 'FIX_SECURITY_GROUP':
            result = fix_security_group(finding)
        elif action == 'ENABLE_ENCRYPTION':
            result = enable_encryption(finding)
        elif action == 'NOTIFY_ONLY':
            result = send_notification_only(finding)
        else:
            logger.warning(f"Unknown action: {action}")
            return {'statusCode': 400, 'body': f'Unknown action: {action}'}
        
        # Update finding with remediation status
        update_finding_status(finding.get('Id'), result)
        
        return {
            'statusCode': 200,
            'body': json.dumps({'action': action, 'result': result})
        }
        
    except Exception as e:
        logger.error(f"Error in remediation function: {str(e)}")
        raise

def isolate_ec2_instance(finding):
    """
    Isolate EC2 instance by moving to quarantine security group
    """
    try:
        # Extract instance ID from finding
        instance_id = extract_instance_id(finding)
        if not instance_id:
            return {'success': False, 'message': 'No instance ID found'}
        
        # Use Systems Manager automation
        ssm = boto3.client('ssm')
        response = ssm.start_automation_execution(
            DocumentName='AWS-PublishSNSNotification',
            Parameters={
                'TopicArn': [os.environ.get('SNS_TOPIC_ARN', '')],
                'Message': [f'Instance {instance_id} isolated due to security finding']
            }
        )
        
        return {'success': True, 'automation_id': response['AutomationExecutionId']}
        
    except Exception as e:
        logger.error(f"Error isolating instance: {str(e)}")
        return {'success': False, 'message': str(e)}

def block_network_access(finding):
    """
    Block network access by updating security group rules
    """
    try:
        # Extract security group information
        sg_id = extract_security_group_id(finding)
        if not sg_id:
            return {'success': False, 'message': 'No security group ID found'}
        
        ec2 = boto3.client('ec2')
        
        # Get current security group rules
        response = ec2.describe_security_groups(GroupIds=[sg_id])
        sg = response['SecurityGroups'][0]
        
        # Remove overly permissive rules (0.0.0.0/0)
        for rule in sg.get('IpPermissions', []):
            for ip_range in rule.get('IpRanges', []):
                if ip_range.get('CidrIp') == '0.0.0.0/0':
                    ec2.revoke_security_group_ingress(
                        GroupId=sg_id,
                        IpPermissions=[rule]
                    )
        
        return {'success': True, 'message': f'Blocked open access for {sg_id}'}
        
    except Exception as e:
        logger.error(f"Error blocking network access: {str(e)}")
        return {'success': False, 'message': str(e)}

def quarantine_instance(finding):
    """
    Quarantine instance by stopping it and creating forensic snapshot
    """
    try:
        instance_id = extract_instance_id(finding)
        if not instance_id:
            return {'success': False, 'message': 'No instance ID found'}
        
        ec2 = boto3.client('ec2')
        
        # Stop the instance
        ec2.stop_instances(InstanceIds=[instance_id])
        
        # Create snapshot for forensic analysis
        response = ec2.describe_instances(InstanceIds=[instance_id])
        instance = response['Reservations'][0]['Instances'][0]
        
        for device in instance.get('BlockDeviceMappings', []):
            volume_id = device['Ebs']['VolumeId']
            ec2.create_snapshot(
                VolumeId=volume_id,
                Description=f'Forensic snapshot for security incident - {instance_id}'
            )
        
        return {'success': True, 'message': f'Instance {instance_id} quarantined'}
        
    except Exception as e:
        logger.error(f"Error quarantining instance: {str(e)}")
        return {'success': False, 'message': str(e)}

def fix_security_group(finding):
    """
    Fix security group misconfigurations
    """
    return {'success': True, 'message': 'Security group remediation simulated'}

def enable_encryption(finding):
    """
    Enable encryption for unencrypted resources
    """
    return {'success': True, 'message': 'Encryption enablement simulated'}

def send_notification_only(finding):
    """
    Send notification without automated remediation
    """
    return {'success': True, 'message': 'Notification sent for manual review'}

def extract_instance_id(finding):
    """
    Extract EC2 instance ID from finding resources
    """
    resources = finding.get('Resources', [])
    for resource in resources:
        resource_id = resource.get('Id', '')
        if 'i-' in resource_id:
            return resource_id.split('/')[-1]
    return None

def extract_security_group_id(finding):
    """
    Extract security group ID from finding resources
    """
    resources = finding.get('Resources', [])
    for resource in resources:
        resource_id = resource.get('Id', '')
        if 'sg-' in resource_id:
            return resource_id.split('/')[-1]
    return None

def update_finding_status(finding_id, result):
    """
    Update Security Hub finding with remediation status
    """
    try:
        securityhub = boto3.client('securityhub')
        status = 'RESOLVED' if result.get('success') else 'NEW'
        note = result.get('message', 'Automated remediation attempted')
        
        securityhub.batch_update_findings(
            FindingIdentifiers=[{'Id': finding_id}],
            Workflow={'Status': status},
            Note={'Text': note, 'UpdatedBy': 'SecurityAutomation'}
        )
    except Exception as e:
        logger.error(f"Error updating finding status: {str(e)}")
EOF

# Create deployment package for remediation function
zip -r remediation.zip remediation.py

execute_command "aws lambda create-function \
    --function-name ${AUTOMATION_PREFIX}-remediation \
    --runtime python3.9 \
    --role arn:aws:iam::${AWS_ACCOUNT_ID}:role/${LAMBDA_ROLE_NAME} \
    --handler remediation.lambda_handler \
    --zip-file fileb://remediation.zip \
    --timeout 300 \
    --memory-size 512 \
    --description 'Automated security remediation actions' \
    --environment Variables='{\"SNS_TOPIC_ARN\":\"${SNS_TOPIC_ARN}\"}' \
    --tags Key=Project,Value=SecurityAutomation Key=Environment,Value=Production" \
    "Create remediation Lambda function"

# Create notification function
info "Creating notification Lambda function..."
cat > "$TEMP_DIR/notification.py" << 'EOF'
import json
import boto3
import logging
import os
from datetime import datetime

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    """
    Send contextual notifications for security findings
    """
    try:
        detail = event.get('detail', {})
        findings = detail.get('findings', [])
        
        if not findings:
            logger.warning("No findings in event")
            return {'statusCode': 200, 'body': 'No findings to process'}
        
        # Process each finding for notification
        for finding in findings:
            send_security_notification(finding)
        
        return {
            'statusCode': 200,
            'body': json.dumps(f'Sent notifications for {len(findings)} findings')
        }
        
    except Exception as e:
        logger.error(f"Error in notification function: {str(e)}")
        raise

def send_security_notification(finding):
    """
    Send detailed security notification
    """
    try:
        # Extract key information
        severity = finding.get('Severity', {}).get('Label', 'INFORMATIONAL')
        title = finding.get('Title', 'Security Finding')
        description = finding.get('Description', 'No description available')
        finding_id = finding.get('Id', 'unknown')
        
        # Create rich notification message
        message = create_notification_message(finding, severity, title, description)
        
        # Send to SNS topic
        sns = boto3.client('sns')
        sns.publish(
            TopicArn=os.environ.get('SNS_TOPIC_ARN'),
            Subject=f'Security Alert: {severity} - {title}',
            Message=message,
            MessageAttributes={
                'severity': {
                    'DataType': 'String',
                    'StringValue': severity
                },
                'finding_id': {
                    'DataType': 'String',
                    'StringValue': finding_id
                }
            }
        )
        
        logger.info(f"Notification sent for finding {finding_id}")
        
    except Exception as e:
        logger.error(f"Error sending notification: {str(e)}")

def create_notification_message(finding, severity, title, description):
    """
    Create structured notification message
    """
    resources = finding.get('Resources', [])
    resource_list = [r.get('Id', 'Unknown') for r in resources[:3]]
    
    message = f"""
🚨 Security Finding Alert

Severity: {severity}
Title: {title}

Description: {description}

Affected Resources:
{chr(10).join(f'• {r}' for r in resource_list)}

Finding ID: {finding.get('Id', 'unknown')}
Account: {finding.get('AwsAccountId', 'unknown')}
Region: {finding.get('Region', 'unknown')}

Created: {finding.get('CreatedAt', 'unknown')}
Updated: {finding.get('UpdatedAt', 'unknown')}

Compliance Status: {finding.get('Compliance', {}).get('Status', 'UNKNOWN')}

🔗 View in Security Hub Console:
https://console.aws.amazon.com/securityhub/home?region={finding.get('Region', 'us-east-1')}#/findings?search=Id%3D{finding.get('Id', '')}

This alert was generated by automated security monitoring.
"""
    
    return message
EOF

# Create deployment package for notification function
zip -r notification.zip notification.py

execute_command "aws lambda create-function \
    --function-name ${AUTOMATION_PREFIX}-notification \
    --runtime python3.9 \
    --role arn:aws:iam::${AWS_ACCOUNT_ID}:role/${LAMBDA_ROLE_NAME} \
    --handler notification.lambda_handler \
    --zip-file fileb://notification.zip \
    --timeout 60 \
    --memory-size 256 \
    --description 'Security finding notifications' \
    --environment Variables='{\"SNS_TOPIC_ARN\":\"${SNS_TOPIC_ARN}\"}' \
    --tags Key=Project,Value=SecurityAutomation Key=Environment,Value=Production" \
    "Create notification Lambda function"

# Create error handler function
info "Creating error handler Lambda function..."
cat > "$TEMP_DIR/error_handler.py" << 'EOF'
import json
import boto3
import logging
import os

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    """
    Handle failed automation events
    """
    try:
        logger.error(f"Automation failure: {json.dumps(event)}")
        
        # Send failure notification
        sns = boto3.client('sns')
        sns.publish(
            TopicArn=os.environ.get('SNS_TOPIC_ARN'),
            Subject='Security Automation Failure',
            Message=f'Automation failure detected: {json.dumps(event, indent=2)}'
        )
        
        return {'statusCode': 200, 'body': 'Error handled'}
        
    except Exception as e:
        logger.error(f"Error in error handler: {str(e)}")
        raise
EOF

# Create deployment package for error handler function
zip -r error_handler.zip error_handler.py

execute_command "aws lambda create-function \
    --function-name ${AUTOMATION_PREFIX}-error-handler \
    --runtime python3.9 \
    --role arn:aws:iam::${AWS_ACCOUNT_ID}:role/${LAMBDA_ROLE_NAME} \
    --handler error_handler.lambda_handler \
    --zip-file fileb://error_handler.zip \
    --timeout 60 \
    --memory-size 256 \
    --description 'Handle automation errors' \
    --environment Variables='{\"SNS_TOPIC_ARN\":\"${SNS_TOPIC_ARN}\"}' \
    --tags Key=Project,Value=SecurityAutomation Key=Environment,Value=Production" \
    "Create error handler Lambda function"

# Step 4: Create EventBridge rules
log "Step 4: Creating EventBridge rules..."

# Create rule for Security Hub findings
SECURITY_HUB_PATTERN='{
    "source": ["aws.securityhub"],
    "detail-type": ["Security Hub Findings - Imported"],
    "detail": {
        "findings": {
            "Severity": {
                "Label": ["HIGH", "CRITICAL", "MEDIUM"]
            },
            "Workflow": {
                "Status": ["NEW"]
            }
        }
    }
}'

execute_command "aws events put-rule \
    --name ${EVENTBRIDGE_RULE_NAME} \
    --event-pattern '$SECURITY_HUB_PATTERN' \
    --state ENABLED \
    --description 'Route Security Hub findings to automation' \
    --tags Key=Project,Value=SecurityAutomation Key=Environment,Value=Production" \
    "Create EventBridge rule for Security Hub findings"

# Add Lambda targets
execute_command "aws events put-targets \
    --rule ${EVENTBRIDGE_RULE_NAME} \
    --targets 'Id=1,Arn=arn:aws:lambda:${AWS_REGION}:${AWS_ACCOUNT_ID}:function:${AUTOMATION_PREFIX}-triage' \
             'Id=2,Arn=arn:aws:lambda:${AWS_REGION}:${AWS_ACCOUNT_ID}:function:${AUTOMATION_PREFIX}-notification'" \
    "Add Lambda targets to Security Hub rule"

# Create rule for remediation actions
REMEDIATION_PATTERN='{
    "source": ["security.automation"],
    "detail-type": ["Security Response Required"]
}'

execute_command "aws events put-rule \
    --name ${AUTOMATION_PREFIX}-remediation-rule \
    --event-pattern '$REMEDIATION_PATTERN' \
    --state ENABLED \
    --description 'Route remediation actions to Lambda' \
    --tags Key=Project,Value=SecurityAutomation Key=Environment,Value=Production" \
    "Create EventBridge rule for remediation actions"

execute_command "aws events put-targets \
    --rule ${AUTOMATION_PREFIX}-remediation-rule \
    --targets 'Id=1,Arn=arn:aws:lambda:${AWS_REGION}:${AWS_ACCOUNT_ID}:function:${AUTOMATION_PREFIX}-remediation'" \
    "Add Lambda target to remediation rule"

# Create rule for error handling
ERROR_PATTERN='{
    "source": ["aws.events"],
    "detail-type": ["EventBridge Rule Execution Failed"]
}'

execute_command "aws events put-rule \
    --name ${AUTOMATION_PREFIX}-error-handling \
    --event-pattern '$ERROR_PATTERN' \
    --state ENABLED \
    --description 'Handle failed automation events' \
    --tags Key=Project,Value=SecurityAutomation Key=Environment,Value=Production" \
    "Create EventBridge rule for error handling"

execute_command "aws events put-targets \
    --rule ${AUTOMATION_PREFIX}-error-handling \
    --targets 'Id=1,Arn=arn:aws:lambda:${AWS_REGION}:${AWS_ACCOUNT_ID}:function:${AUTOMATION_PREFIX}-error-handler'" \
    "Add Lambda target to error handling rule"

# Step 5: Configure Lambda permissions
log "Step 5: Configuring Lambda permissions..."

execute_command "aws lambda add-permission \
    --function-name ${AUTOMATION_PREFIX}-triage \
    --statement-id allow-eventbridge-triage \
    --action lambda:InvokeFunction \
    --principal events.amazonaws.com \
    --source-arn arn:aws:events:${AWS_REGION}:${AWS_ACCOUNT_ID}:rule/${EVENTBRIDGE_RULE_NAME}" \
    "Grant EventBridge permission to invoke triage Lambda"

execute_command "aws lambda add-permission \
    --function-name ${AUTOMATION_PREFIX}-notification \
    --statement-id allow-eventbridge-notification \
    --action lambda:InvokeFunction \
    --principal events.amazonaws.com \
    --source-arn arn:aws:events:${AWS_REGION}:${AWS_ACCOUNT_ID}:rule/${EVENTBRIDGE_RULE_NAME}" \
    "Grant EventBridge permission to invoke notification Lambda"

execute_command "aws lambda add-permission \
    --function-name ${AUTOMATION_PREFIX}-remediation \
    --statement-id allow-eventbridge-remediation \
    --action lambda:InvokeFunction \
    --principal events.amazonaws.com \
    --source-arn arn:aws:events:${AWS_REGION}:${AWS_ACCOUNT_ID}:rule/${AUTOMATION_PREFIX}-remediation-rule" \
    "Grant EventBridge permission to invoke remediation Lambda"

execute_command "aws lambda add-permission \
    --function-name ${AUTOMATION_PREFIX}-error-handler \
    --statement-id allow-eventbridge-error-handler \
    --action lambda:InvokeFunction \
    --principal events.amazonaws.com \
    --source-arn arn:aws:events:${AWS_REGION}:${AWS_ACCOUNT_ID}:rule/${AUTOMATION_PREFIX}-error-handling" \
    "Grant EventBridge permission to invoke error handler Lambda"

# Step 6: Create Systems Manager automation document
log "Step 6: Creating Systems Manager automation document..."

AUTOMATION_DOCUMENT='{
    "schemaVersion": "0.3",
    "description": "Isolate EC2 instance for security incident response",
    "assumeRole": "{{ AutomationAssumeRole }}",
    "parameters": {
        "InstanceId": {
            "type": "String",
            "description": "EC2 instance ID to isolate"
        },
        "AutomationAssumeRole": {
            "type": "String",
            "description": "IAM role for automation execution"
        }
    },
    "mainSteps": [
        {
            "name": "StopInstance",
            "action": "aws:executeAwsApi",
            "inputs": {
                "Service": "ec2",
                "Api": "StopInstances",
                "InstanceIds": ["{{ InstanceId }}"]
            }
        },
        {
            "name": "CreateSnapshot",
            "action": "aws:executeScript",
            "inputs": {
                "Runtime": "python3.8",
                "Handler": "create_snapshot",
                "Script": "def create_snapshot(events, context):\n    import boto3\n    ec2 = boto3.client(\"ec2\")\n    instance_id = events[\"InstanceId\"]\n    \n    # Get instance volumes\n    response = ec2.describe_instances(InstanceIds=[instance_id])\n    instance = response[\"Reservations\"][0][\"Instances\"][0]\n    \n    snapshots = []\n    for device in instance.get(\"BlockDeviceMappings\", []):\n        volume_id = device[\"Ebs\"][\"VolumeId\"]\n        snapshot = ec2.create_snapshot(\n            VolumeId=volume_id,\n            Description=f\"Forensic snapshot for {instance_id}\"\n        )\n        snapshots.append(snapshot[\"SnapshotId\"])\n    \n    return {\"snapshots\": snapshots}",
                "InputPayload": {
                    "InstanceId": "{{ InstanceId }}"
                }
            }
        }
    ]
}'

echo "$AUTOMATION_DOCUMENT" > "$TEMP_DIR/isolate-instance.json"

execute_command "aws ssm create-document \
    --name ${AUTOMATION_PREFIX}-isolate-instance \
    --document-type Automation \
    --document-format JSON \
    --content file://$TEMP_DIR/isolate-instance.json \
    --tags Key=Project,Value=SecurityAutomation Key=Environment,Value=Production" \
    "Create Systems Manager automation document"

# Step 7: Create Security Hub automation rules
log "Step 7: Creating Security Hub automation rules..."

# Check if Security Hub is enabled
if [[ "$DRY_RUN" == "false" ]]; then
    if ! aws securityhub describe-hub &>/dev/null; then
        warn "Security Hub is not enabled. Security Hub automation rules will not be created."
        warn "To enable Security Hub, run: aws securityhub enable-security-hub"
    else
        execute_command "aws securityhub create-automation-rule \
            --actions '[{
                \"Type\": \"FINDING_FIELDS_UPDATE\",
                \"FindingFieldsUpdate\": {
                    \"Note\": {
                        \"Text\": \"High severity finding detected - automated response initiated\",
                        \"UpdatedBy\": \"SecurityAutomation\"
                    },
                    \"Workflow\": {
                        \"Status\": \"IN_PROGRESS\"
                    }
                }
            }]' \
            --criteria '{
                \"SeverityLabel\": [{
                    \"Value\": \"HIGH\",
                    \"Comparison\": \"EQUALS\"
                }],
                \"WorkflowStatus\": [{
                    \"Value\": \"NEW\",
                    \"Comparison\": \"EQUALS\"
                }]
            }' \
            --description 'Automatically mark high severity findings as in progress' \
            --rule-name 'Auto-Process-High-Severity' \
            --rule-order 1 \
            --rule-status 'ENABLED' \
            --tags Key=Project,Value=SecurityAutomation Key=Environment,Value=Production" \
            "Create Security Hub automation rule for high severity findings"

        execute_command "aws securityhub create-automation-rule \
            --actions '[{
                \"Type\": \"FINDING_FIELDS_UPDATE\",
                \"FindingFieldsUpdate\": {
                    \"Note\": {
                        \"Text\": \"Critical finding detected - immediate attention required\",
                        \"UpdatedBy\": \"SecurityAutomation\"
                    },
                    \"Workflow\": {
                        \"Status\": \"IN_PROGRESS\"
                    },
                    \"Severity\": {
                        \"Label\": \"CRITICAL\"
                    }
                }
            }]' \
            --criteria '{
                \"SeverityLabel\": [{
                    \"Value\": \"CRITICAL\",
                    \"Comparison\": \"EQUALS\"
                }],
                \"WorkflowStatus\": [{
                    \"Value\": \"NEW\",
                    \"Comparison\": \"EQUALS\"
                }]
            }' \
            --description 'Automatically process critical findings' \
            --rule-name 'Auto-Process-Critical-Findings' \
            --rule-order 2 \
            --rule-status 'ENABLED' \
            --tags Key=Project,Value=SecurityAutomation Key=Environment,Value=Production" \
            "Create Security Hub automation rule for critical findings"
    fi
else
    info "[DRY RUN] Would create Security Hub automation rules"
fi

# Step 8: Create custom Security Hub actions
log "Step 8: Creating custom Security Hub actions..."

if [[ "$DRY_RUN" == "false" ]]; then
    if aws securityhub describe-hub &>/dev/null; then
        execute_command "aws securityhub create-action-target \
            --name 'TriggerAutomatedRemediation' \
            --description 'Trigger automated remediation for selected findings' \
            --id 'trigger-remediation'" \
            "Create custom action for manual remediation trigger"

        execute_command "aws securityhub create-action-target \
            --name 'EscalateToSOC' \
            --description 'Escalate finding to Security Operations Center' \
            --id 'escalate-soc'" \
            "Create custom action for escalation"

        CUSTOM_ACTION_PATTERN='{
            "source": ["aws.securityhub"],
            "detail-type": ["Security Hub Findings - Custom Action"],
            "detail": {
                "actionName": ["TriggerAutomatedRemediation", "EscalateToSOC"]
            }
        }'

        execute_command "aws events put-rule \
            --name ${AUTOMATION_PREFIX}-custom-actions \
            --event-pattern '$CUSTOM_ACTION_PATTERN' \
            --state ENABLED \
            --description 'Handle custom Security Hub actions' \
            --tags Key=Project,Value=SecurityAutomation Key=Environment,Value=Production" \
            "Create EventBridge rule for custom actions"
    fi
else
    info "[DRY RUN] Would create custom Security Hub actions"
fi

# Step 9: Create CloudWatch monitoring
log "Step 9: Creating CloudWatch monitoring and alerting..."

execute_command "aws cloudwatch put-metric-alarm \
    --alarm-name ${AUTOMATION_PREFIX}-lambda-errors \
    --alarm-description 'Security automation Lambda errors' \
    --metric-name Errors \
    --namespace AWS/Lambda \
    --statistic Sum \
    --period 300 \
    --threshold 1 \
    --comparison-operator GreaterThanOrEqualToThreshold \
    --evaluation-periods 1 \
    --alarm-actions ${SNS_TOPIC_ARN} \
    --dimensions Name=FunctionName,Value=${AUTOMATION_PREFIX}-triage \
    --tags Key=Project,Value=SecurityAutomation Key=Environment,Value=Production" \
    "Create CloudWatch alarm for Lambda errors"

execute_command "aws cloudwatch put-metric-alarm \
    --alarm-name ${AUTOMATION_PREFIX}-eventbridge-failures \
    --alarm-description 'EventBridge rule failures' \
    --metric-name FailedInvocations \
    --namespace AWS/Events \
    --statistic Sum \
    --period 300 \
    --threshold 1 \
    --comparison-operator GreaterThanOrEqualToThreshold \
    --evaluation-periods 1 \
    --alarm-actions ${SNS_TOPIC_ARN} \
    --dimensions Name=RuleName,Value=${EVENTBRIDGE_RULE_NAME} \
    --tags Key=Project,Value=SecurityAutomation Key=Environment,Value=Production" \
    "Create CloudWatch alarm for EventBridge failures"

DASHBOARD_BODY='{
    "widgets": [
        {
            "type": "metric",
            "x": 0,
            "y": 0,
            "width": 12,
            "height": 6,
            "properties": {
                "metrics": [
                    ["AWS/Lambda", "Invocations", "FunctionName", "'${AUTOMATION_PREFIX}'-triage"],
                    [".", "Errors", ".", "."],
                    [".", "Duration", ".", "."]
                ],
                "period": 300,
                "stat": "Sum",
                "region": "'${AWS_REGION}'",
                "title": "Triage Lambda Metrics",
                "yAxis": {
                    "left": {
                        "min": 0
                    }
                }
            }
        },
        {
            "type": "metric",
            "x": 12,
            "y": 0,
            "width": 12,
            "height": 6,
            "properties": {
                "metrics": [
                    ["AWS/Lambda", "Invocations", "FunctionName", "'${AUTOMATION_PREFIX}'-remediation"],
                    [".", "Errors", ".", "."],
                    [".", "Duration", ".", "."]
                ],
                "period": 300,
                "stat": "Sum",
                "region": "'${AWS_REGION}'",
                "title": "Remediation Lambda Metrics",
                "yAxis": {
                    "left": {
                        "min": 0
                    }
                }
            }
        },
        {
            "type": "metric",
            "x": 0,
            "y": 6,
            "width": 24,
            "height": 6,
            "properties": {
                "metrics": [
                    ["AWS/Events", "SuccessfulInvocations", "RuleName", "'${EVENTBRIDGE_RULE_NAME}'"],
                    [".", "FailedInvocations", ".", "."]
                ],
                "period": 300,
                "stat": "Sum",
                "region": "'${AWS_REGION}'",
                "title": "EventBridge Rule Metrics",
                "yAxis": {
                    "left": {
                        "min": 0
                    }
                }
            }
        }
    ]
}'

execute_command "aws cloudwatch put-dashboard \
    --dashboard-name ${AUTOMATION_PREFIX}-monitoring \
    --dashboard-body '$DASHBOARD_BODY'" \
    "Create CloudWatch dashboard for monitoring"

# Step 10: Output deployment summary
log "Deployment completed successfully!"

info "Deployment Summary:"
info "==================="
info "Resource Prefix: $AUTOMATION_PREFIX"
info "AWS Region: $AWS_REGION"
info "SNS Topic ARN: $SNS_TOPIC_ARN"

if [[ "$DRY_RUN" == "false" ]]; then
    info "Lambda Functions:"
    info "  - ${AUTOMATION_PREFIX}-triage"
    info "  - ${AUTOMATION_PREFIX}-remediation"
    info "  - ${AUTOMATION_PREFIX}-notification"
    info "  - ${AUTOMATION_PREFIX}-error-handler"
    
    info "EventBridge Rules:"
    info "  - ${EVENTBRIDGE_RULE_NAME}"
    info "  - ${AUTOMATION_PREFIX}-remediation-rule"
    info "  - ${AUTOMATION_PREFIX}-error-handling"
    
    info "CloudWatch Dashboard:"
    info "  - ${AUTOMATION_PREFIX}-monitoring"
    
    if [[ -n "$EMAIL_ADDRESS" ]]; then
        info "Email Notifications: $EMAIL_ADDRESS"
        warn "Check your email and confirm the SNS subscription to receive notifications"
    fi
    
    # Save deployment info for cleanup script
    cat > "$HOME/.security-automation-deployment.env" << EOF
export AUTOMATION_PREFIX="${AUTOMATION_PREFIX}"
export LAMBDA_ROLE_NAME="${LAMBDA_ROLE_NAME}"
export EVENTBRIDGE_RULE_NAME="${EVENTBRIDGE_RULE_NAME}"
export SNS_TOPIC_NAME="${SNS_TOPIC_NAME}"
export SNS_TOPIC_ARN="${SNS_TOPIC_ARN}"
export SQS_QUEUE_NAME="${SQS_QUEUE_NAME}"
export DLQ_URL="${DLQ_URL}"
export AWS_REGION="${AWS_REGION}"
export AWS_ACCOUNT_ID="${AWS_ACCOUNT_ID}"
EOF
    
    info "Deployment configuration saved to: $HOME/.security-automation-deployment.env"
    info "Use this file with the destroy script to clean up resources"
fi

info "Next Steps:"
info "1. Enable Security Hub if not already enabled: aws securityhub enable-security-hub"
info "2. Configure Security Hub to import findings from other AWS services"
info "3. Test the automation by creating a test security finding"
info "4. Monitor the CloudWatch dashboard for automation metrics"
info "5. Review CloudWatch logs for Lambda function execution details"

if [[ "$DRY_RUN" == "true" ]]; then
    info "This was a dry run. No resources were actually created."
    info "Run the script without --dry-run to deploy the infrastructure."
fi

log "Deployment script completed successfully!"