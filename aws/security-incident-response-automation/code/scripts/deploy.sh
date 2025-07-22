#!/bin/bash

# AWS Automated Security Incident Response with Security Hub - Deployment Script
# This script deploys the complete automated security incident response infrastructure
# as described in the recipe: Security Incident Response Automation

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAMBDA_DIR="${SCRIPT_DIR}/../lambda-functions"
LOG_FILE="${SCRIPT_DIR}/deployment.log"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# Error handling function
error_exit() {
    echo -e "${RED}ERROR: $1${NC}" >&2
    log "ERROR: $1"
    exit 1
}

# Success message function
success() {
    echo -e "${GREEN}✅ $1${NC}"
    log "SUCCESS: $1"
}

# Warning message function
warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
    log "WARNING: $1"
}

# Info message function
info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
    log "INFO: $1"
}

# Check prerequisites
check_prerequisites() {
    info "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        error_exit "AWS CLI is not installed. Please install AWS CLI v2."
    fi
    
    # Check if AWS CLI is configured
    if ! aws sts get-caller-identity &> /dev/null; then
        error_exit "AWS CLI is not configured. Please run 'aws configure' first."
    fi
    
    # Check if jq is installed (for JSON parsing)
    if ! command -v jq &> /dev/null; then
        warning "jq is not installed. Some output formatting may be limited."
    fi
    
    # Check if zip is available
    if ! command -v zip &> /dev/null; then
        error_exit "zip command is not available. Please install zip utility."
    fi
    
    success "Prerequisites check completed"
}

# Set environment variables
setup_environment() {
    info "Setting up environment variables..."
    
    # Set AWS region and account ID
    export AWS_REGION=$(aws configure get region)
    if [ -z "$AWS_REGION" ]; then
        export AWS_REGION="us-east-1"
        warning "AWS region not configured, defaulting to us-east-1"
    fi
    
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers for resources
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || echo "$(date +%s | tail -c 6)")
    
    # Set resource names
    export SECURITY_HUB_ROLE_NAME="SecurityHubRole-${RANDOM_SUFFIX}"
    export INCIDENT_RESPONSE_ROLE_NAME="IncidentResponseRole-${RANDOM_SUFFIX}"
    export CLASSIFICATION_FUNCTION_NAME="security-classification-${RANDOM_SUFFIX}"
    export REMEDIATION_FUNCTION_NAME="security-remediation-${RANDOM_SUFFIX}"
    export NOTIFICATION_FUNCTION_NAME="security-notification-${RANDOM_SUFFIX}"
    export SNS_TOPIC_NAME="security-incidents-${RANDOM_SUFFIX}"
    export EVENTBRIDGE_RULE_NAME="security-hub-findings-${RANDOM_SUFFIX}"
    
    # Save environment variables for cleanup
    cat > "${SCRIPT_DIR}/.env" << EOF
export AWS_REGION="$AWS_REGION"
export AWS_ACCOUNT_ID="$AWS_ACCOUNT_ID"
export SECURITY_HUB_ROLE_NAME="$SECURITY_HUB_ROLE_NAME"
export INCIDENT_RESPONSE_ROLE_NAME="$INCIDENT_RESPONSE_ROLE_NAME"
export CLASSIFICATION_FUNCTION_NAME="$CLASSIFICATION_FUNCTION_NAME"
export REMEDIATION_FUNCTION_NAME="$REMEDIATION_FUNCTION_NAME"
export NOTIFICATION_FUNCTION_NAME="$NOTIFICATION_FUNCTION_NAME"
export SNS_TOPIC_NAME="$SNS_TOPIC_NAME"
export EVENTBRIDGE_RULE_NAME="$EVENTBRIDGE_RULE_NAME"
export RANDOM_SUFFIX="$RANDOM_SUFFIX"
EOF
    
    success "Environment setup completed with suffix: ${RANDOM_SUFFIX}"
}

# Enable Security Hub
enable_security_hub() {
    info "Enabling AWS Security Hub..."
    
    # Check if Security Hub is already enabled
    if aws securityhub describe-hub &> /dev/null; then
        warning "Security Hub is already enabled"
    else
        # Enable Security Hub with default standards
        aws securityhub enable-security-hub \
            --enable-default-standards \
            --tags "Project=IncidentResponse,Environment=Production" || \
            error_exit "Failed to enable Security Hub"
        
        # Wait for Security Hub to initialize
        info "Waiting for Security Hub to initialize..."
        sleep 30
    fi
    
    # Verify Security Hub is enabled
    aws securityhub describe-hub > /dev/null || \
        error_exit "Security Hub verification failed"
    
    success "Security Hub enabled and verified"
}

# Create IAM roles
create_iam_roles() {
    info "Creating IAM roles for Lambda functions..."
    
    # Create working directory
    mkdir -p "$LAMBDA_DIR"
    cd "$LAMBDA_DIR"
    
    # Create trust policy for Lambda
    cat > lambda-trust-policy.json << 'EOF'
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Service": "lambda.amazonaws.com"
            },
            "Action": "sts:AssumeRole"
        }
    ]
}
EOF
    
    # Create incident response role
    aws iam create-role \
        --role-name "$INCIDENT_RESPONSE_ROLE_NAME" \
        --assume-role-policy-document file://lambda-trust-policy.json \
        --description "Role for automated incident response functions" || \
        error_exit "Failed to create IAM role"
    
    # Create comprehensive policy for incident response
    cat > incident-response-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "logs:CreateLogGroup",
                "logs:CreateLogStream",
                "logs:PutLogEvents"
            ],
            "Resource": "arn:aws:logs:*:*:*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "securityhub:GetFindings",
                "securityhub:BatchUpdateFindings",
                "securityhub:BatchImportFindings"
            ],
            "Resource": "*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "sns:Publish"
            ],
            "Resource": "arn:aws:sns:${AWS_REGION}:${AWS_ACCOUNT_ID}:${SNS_TOPIC_NAME}"
        },
        {
            "Effect": "Allow",
            "Action": [
                "ec2:DescribeSecurityGroups",
                "ec2:AuthorizeSecurityGroupIngress",
                "ec2:RevokeSecurityGroupIngress",
                "ec2:CreateTags",
                "iam:AttachRolePolicy",
                "iam:DetachRolePolicy",
                "iam:PutRolePolicy",
                "iam:DeleteRolePolicy",
                "s3:PutBucketPolicy",
                "s3:GetBucketPolicy"
            ],
            "Resource": "*"
        }
    ]
}
EOF
    
    # Attach policy to role
    aws iam put-role-policy \
        --role-name "$INCIDENT_RESPONSE_ROLE_NAME" \
        --policy-name "IncidentResponsePolicy" \
        --policy-document file://incident-response-policy.json || \
        error_exit "Failed to attach policy to IAM role"
    
    # Wait for role propagation
    info "Waiting for IAM role propagation..."
    sleep 10
    
    success "IAM roles created successfully"
}

# Create SNS topic
create_sns_topic() {
    info "Creating SNS topic for notifications..."
    
    # Create SNS topic
    SNS_TOPIC_ARN=$(aws sns create-topic \
        --name "$SNS_TOPIC_NAME" \
        --query TopicArn --output text) || \
        error_exit "Failed to create SNS topic"
    
    # Set topic policy for Lambda access
    cat > sns-topic-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "AWS": "arn:aws:iam::${AWS_ACCOUNT_ID}:role/${INCIDENT_RESPONSE_ROLE_NAME}"
            },
            "Action": "SNS:Publish",
            "Resource": "${SNS_TOPIC_ARN}"
        }
    ]
}
EOF
    
    aws sns set-topic-attributes \
        --topic-arn "$SNS_TOPIC_ARN" \
        --attribute-name Policy \
        --attribute-value file://sns-topic-policy.json || \
        error_exit "Failed to set SNS topic policy"
    
    # Save SNS topic ARN for later use
    echo "$SNS_TOPIC_ARN" > sns-topic-arn.txt
    
    success "SNS topic created: $SNS_TOPIC_ARN"
}

# Create Lambda functions
create_lambda_functions() {
    info "Creating Lambda functions..."
    
    # Create classification function
    create_classification_function
    
    # Create remediation function
    create_remediation_function
    
    # Create notification function
    create_notification_function
    
    success "All Lambda functions created successfully"
}

# Create classification Lambda function
create_classification_function() {
    info "Creating classification Lambda function..."
    
    cat > classification_function.py << 'EOF'
import json
import boto3
import logging
from datetime import datetime

logger = logging.getLogger()
logger.setLevel(logging.INFO)

securityhub = boto3.client('securityhub')
sns = boto3.client('sns')

def lambda_handler(event, context):
    try:
        # Extract finding details from EventBridge event
        finding = event['detail']['findings'][0]
        
        finding_id = finding['Id']
        product_arn = finding['ProductArn']
        severity = finding['Severity']['Label']
        title = finding['Title']
        description = finding['Description']
        
        # Classify finding based on severity and type
        classification = classify_finding(finding)
        
        # Update finding with classification
        response = securityhub.batch_update_findings(
            FindingIdentifiers=[
                {
                    'Id': finding_id,
                    'ProductArn': product_arn
                }
            ],
            Note={
                'Text': f'Auto-classified as {classification["category"]} - {classification["action"]}',
                'UpdatedBy': 'SecurityIncidentResponse'
            },
            UserDefinedFields={
                'AutoClassification': classification['category'],
                'RecommendedAction': classification['action'],
                'ProcessedAt': datetime.utcnow().isoformat()
            }
        )
        
        logger.info(f"Successfully classified finding {finding_id} as {classification['category']}")
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'findingId': finding_id,
                'classification': classification,
                'updated': True
            })
        }
        
    except Exception as e:
        logger.error(f"Error processing finding: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }

def classify_finding(finding):
    """Classify finding based on severity, type, and content"""
    severity = finding['Severity']['Label']
    finding_type = finding.get('Types', ['Unknown'])[0]
    title = finding['Title'].lower()
    
    # High-priority security incidents
    if severity == 'CRITICAL':
        if 'root' in title or 'admin' in title:
            return {
                'category': 'CRITICAL_ADMIN_ISSUE',
                'action': 'IMMEDIATE_REVIEW_REQUIRED',
                'escalate': True
            }
        elif 'malware' in title or 'backdoor' in title:
            return {
                'category': 'MALWARE_DETECTED',
                'action': 'QUARANTINE_RESOURCE',
                'escalate': True
            }
        else:
            return {
                'category': 'CRITICAL_SECURITY_ISSUE',
                'action': 'INVESTIGATE_IMMEDIATELY',
                'escalate': True
            }
    
    # Medium-priority issues
    elif severity == 'HIGH':
        if 'mfa' in title:
            return {
                'category': 'MFA_COMPLIANCE_ISSUE',
                'action': 'ENFORCE_MFA_POLICY',
                'escalate': False
            }
        elif 'encryption' in title:
            return {
                'category': 'ENCRYPTION_COMPLIANCE',
                'action': 'ENABLE_ENCRYPTION',
                'escalate': False
            }
        else:
            return {
                'category': 'HIGH_SECURITY_ISSUE',
                'action': 'SCHEDULE_REMEDIATION',
                'escalate': False
            }
    
    # Lower priority issues
    else:
        return {
            'category': 'STANDARD_COMPLIANCE_ISSUE',
            'action': 'TRACK_FOR_REMEDIATION',
            'escalate': False
        }
EOF
    
    # Package and deploy classification function
    zip classification_function.zip classification_function.py
    
    CLASSIFICATION_FUNCTION_ARN=$(aws lambda create-function \
        --function-name "$CLASSIFICATION_FUNCTION_NAME" \
        --runtime python3.9 \
        --role "arn:aws:iam::${AWS_ACCOUNT_ID}:role/${INCIDENT_RESPONSE_ROLE_NAME}" \
        --handler classification_function.lambda_handler \
        --zip-file fileb://classification_function.zip \
        --timeout 300 \
        --memory-size 256 \
        --description "Classifies security findings for automated response" \
        --query FunctionArn --output text) || \
        error_exit "Failed to create classification Lambda function"
    
    echo "$CLASSIFICATION_FUNCTION_ARN" > classification-function-arn.txt
    success "Classification function created: $CLASSIFICATION_FUNCTION_ARN"
}

# Create remediation Lambda function
create_remediation_function() {
    info "Creating remediation Lambda function..."
    
    cat > remediation_function.py << 'EOF'
import json
import boto3
import logging
from datetime import datetime

logger = logging.getLogger()
logger.setLevel(logging.INFO)

ec2 = boto3.client('ec2')
iam = boto3.client('iam')
s3 = boto3.client('s3')
securityhub = boto3.client('securityhub')

def lambda_handler(event, context):
    try:
        # Extract finding details
        finding = event['detail']['findings'][0]
        finding_id = finding['Id']
        product_arn = finding['ProductArn']
        title = finding['Title']
        resources = finding.get('Resources', [])
        
        # Determine remediation action based on finding type
        remediation_result = perform_remediation(finding, resources)
        
        # Update finding with remediation status
        securityhub.batch_update_findings(
            FindingIdentifiers=[
                {
                    'Id': finding_id,
                    'ProductArn': product_arn
                }
            ],
            Note={
                'Text': f'Auto-remediation attempted: {remediation_result["action"]} - {remediation_result["status"]}',
                'UpdatedBy': 'SecurityIncidentResponse'
            },
            UserDefinedFields={
                'RemediationAction': remediation_result['action'],
                'RemediationStatus': remediation_result['status'],
                'RemediationTimestamp': datetime.utcnow().isoformat()
            },
            Workflow={
                'Status': 'RESOLVED' if remediation_result['status'] == 'SUCCESS' else 'NEW'
            }
        )
        
        logger.info(f"Remediation completed for finding {finding_id}: {remediation_result['status']}")
        
        return {
            'statusCode': 200,
            'body': json.dumps(remediation_result)
        }
        
    except Exception as e:
        logger.error(f"Error in remediation: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }

def perform_remediation(finding, resources):
    """Perform automated remediation based on finding type"""
    title = finding['Title'].lower()
    
    try:
        # Security Group remediation
        if 'security group' in title and 'open' in title:
            return remediate_security_group(finding, resources)
        
        # S3 bucket policy remediation
        elif 's3' in title and 'public' in title:
            return remediate_s3_bucket(finding, resources)
        
        # IAM policy remediation
        elif 'iam' in title and 'policy' in title:
            return remediate_iam_policy(finding, resources)
        
        # Default action for other findings
        else:
            return {
                'action': 'MANUAL_REVIEW_REQUIRED',
                'status': 'PENDING',
                'message': 'Finding requires manual investigation'
            }
            
    except Exception as e:
        return {
            'action': 'REMEDIATION_FAILED',
            'status': 'ERROR',
            'message': str(e)
        }

def remediate_security_group(finding, resources):
    """Remediate overly permissive security group rules"""
    for resource in resources:
        if resource['Type'] == 'AwsEc2SecurityGroup':
            sg_id = resource['Id'].split('/')[-1]
            
            try:
                # Get security group details
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
                            
                            # Add more restrictive rule (example: company IP range)
                            restricted_rule = rule.copy()
                            restricted_rule['IpRanges'] = [{'CidrIp': '10.0.0.0/8', 'Description': 'Internal network only'}]
                            
                            ec2.authorize_security_group_ingress(
                                GroupId=sg_id,
                                IpPermissions=[restricted_rule]
                            )
                
                return {
                    'action': 'SECURITY_GROUP_RESTRICTED',
                    'status': 'SUCCESS',
                    'message': f'Restricted security group {sg_id} access'
                }
                
            except Exception as e:
                return {
                    'action': 'SECURITY_GROUP_REMEDIATION_FAILED',
                    'status': 'ERROR',
                    'message': str(e)
                }
    
    return {
        'action': 'NO_SECURITY_GROUP_FOUND',
        'status': 'SKIPPED',
        'message': 'No security group resource found in finding'
    }

def remediate_s3_bucket(finding, resources):
    """Remediate public S3 bucket access"""
    for resource in resources:
        if resource['Type'] == 'AwsS3Bucket':
            bucket_name = resource['Id'].split('/')[-1]
            
            try:
                # Apply restrictive bucket policy
                restrictive_policy = {
                    "Version": "2012-10-17",
                    "Statement": [
                        {
                            "Sid": "DenyPublicRead",
                            "Effect": "Deny",
                            "Principal": "*",
                            "Action": "s3:GetObject",
                            "Resource": f"arn:aws:s3:::{bucket_name}/*",
                            "Condition": {
                                "Bool": {
                                    "aws:SecureTransport": "false"
                                }
                            }
                        }
                    ]
                }
                
                s3.put_bucket_policy(
                    Bucket=bucket_name,
                    Policy=json.dumps(restrictive_policy)
                )
                
                return {
                    'action': 'S3_BUCKET_SECURED',
                    'status': 'SUCCESS',
                    'message': f'Applied restrictive policy to bucket {bucket_name}'
                }
                
            except Exception as e:
                return {
                    'action': 'S3_BUCKET_REMEDIATION_FAILED',
                    'status': 'ERROR',
                    'message': str(e)
                }
    
    return {
        'action': 'NO_S3_BUCKET_FOUND',
        'status': 'SKIPPED',
        'message': 'No S3 bucket resource found in finding'
    }

def remediate_iam_policy(finding, resources):
    """Remediate overly permissive IAM policies"""
    return {
        'action': 'IAM_POLICY_REVIEW_REQUIRED',
        'status': 'PENDING',
        'message': 'IAM policy changes require manual review for security'
    }
EOF
    
    # Package and deploy remediation function
    zip remediation_function.zip remediation_function.py
    
    REMEDIATION_FUNCTION_ARN=$(aws lambda create-function \
        --function-name "$REMEDIATION_FUNCTION_NAME" \
        --runtime python3.9 \
        --role "arn:aws:iam::${AWS_ACCOUNT_ID}:role/${INCIDENT_RESPONSE_ROLE_NAME}" \
        --handler remediation_function.lambda_handler \
        --zip-file fileb://remediation_function.zip \
        --timeout 300 \
        --memory-size 512 \
        --description "Performs automated remediation of security findings" \
        --query FunctionArn --output text) || \
        error_exit "Failed to create remediation Lambda function"
    
    echo "$REMEDIATION_FUNCTION_ARN" > remediation-function-arn.txt
    success "Remediation function created: $REMEDIATION_FUNCTION_ARN"
}

# Create notification Lambda function
create_notification_function() {
    info "Creating notification Lambda function..."
    
    cat > notification_function.py << EOF
import json
import boto3
import logging
from datetime import datetime

logger = logging.getLogger()
logger.setLevel(logging.INFO)

sns = boto3.client('sns')

SNS_TOPIC_ARN = 'arn:aws:sns:${AWS_REGION}:${AWS_ACCOUNT_ID}:${SNS_TOPIC_NAME}'

def lambda_handler(event, context):
    try:
        # Extract finding details
        finding = event['detail']['findings'][0]
        
        finding_id = finding['Id']
        severity = finding['Severity']['Label']
        title = finding['Title']
        description = finding['Description']
        account_id = finding['AwsAccountId']
        region = finding['Resources'][0]['Region'] if finding['Resources'] else 'Unknown'
        
        # Create notification message
        message = create_notification_message(finding, severity, title, description, account_id, region)
        
        # Send notification
        response = sns.publish(
            TopicArn=SNS_TOPIC_ARN,
            Message=message,
            Subject=f'Security Alert: {severity} - {title[:50]}...'
        )
        
        logger.info(f"Notification sent for finding {finding_id}: {response['MessageId']}")
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'messageId': response['MessageId'],
                'finding': finding_id,
                'severity': severity
            })
        }
        
    except Exception as e:
        logger.error(f"Error sending notification: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }

def create_notification_message(finding, severity, title, description, account_id, region):
    """Create formatted notification message"""
    
    # Determine escalation based on severity
    escalation_level = "🔴 CRITICAL" if severity == "CRITICAL" else "🟠 HIGH" if severity == "HIGH" else "🟡 MEDIUM"
    
    # Extract resource information
    resources = []
    for resource in finding.get('Resources', []):
        resources.append(f"- {resource['Type']}: {resource['Id']}")
    
    resource_list = "\\n".join(resources) if resources else "No specific resources identified"
    
    # Create comprehensive message
    message = f"""
{escalation_level} SECURITY INCIDENT ALERT

======================================
INCIDENT DETAILS
======================================

Finding ID: {finding['Id']}
Severity: {severity}
Title: {title}

Account: {account_id}
Region: {region}
Timestamp: {datetime.utcnow().strftime('%Y-%m-%d %H:%M:%S')} UTC

======================================
DESCRIPTION
======================================

{description}

======================================
AFFECTED RESOURCES
======================================

{resource_list}

======================================
RECOMMENDED ACTIONS
======================================

1. Review the finding details in AWS Security Hub
2. Investigate the affected resources
3. Apply necessary remediation steps
4. Update the finding status when resolved

======================================
SECURITY HUB LINK
======================================

https://console.aws.amazon.com/securityhub/home?region={region}#/findings?search=Id%3D{finding['Id'].replace(':', '%3A').replace('/', '%2F')}

This is an automated alert from AWS Security Hub Incident Response System.
"""
    
    return message
EOF
    
    # Package and deploy notification function
    zip notification_function.zip notification_function.py
    
    NOTIFICATION_FUNCTION_ARN=$(aws lambda create-function \
        --function-name "$NOTIFICATION_FUNCTION_NAME" \
        --runtime python3.9 \
        --role "arn:aws:iam::${AWS_ACCOUNT_ID}:role/${INCIDENT_RESPONSE_ROLE_NAME}" \
        --handler notification_function.lambda_handler \
        --zip-file fileb://notification_function.zip \
        --timeout 300 \
        --memory-size 256 \
        --description "Sends notifications for security incidents" \
        --query FunctionArn --output text) || \
        error_exit "Failed to create notification Lambda function"
    
    echo "$NOTIFICATION_FUNCTION_ARN" > notification-function-arn.txt
    success "Notification function created: $NOTIFICATION_FUNCTION_ARN"
}

# Create EventBridge rules
create_eventbridge_rules() {
    info "Creating EventBridge rules for automated response..."
    
    # Load function ARNs
    CLASSIFICATION_FUNCTION_ARN=$(cat classification-function-arn.txt)
    REMEDIATION_FUNCTION_ARN=$(cat remediation-function-arn.txt)
    NOTIFICATION_FUNCTION_ARN=$(cat notification-function-arn.txt)
    
    # Create EventBridge rule for high/critical findings
    aws events put-rule \
        --name "${EVENTBRIDGE_RULE_NAME}-critical" \
        --event-pattern '{
            "source": ["aws.securityhub"],
            "detail-type": ["Security Hub Findings - Imported"],
            "detail": {
                "findings": {
                    "Severity": {
                        "Label": ["HIGH", "CRITICAL"]
                    },
                    "RecordState": ["ACTIVE"],
                    "WorkflowState": ["NEW"]
                }
            }
        }' \
        --state ENABLED \
        --description "Triggers incident response for high/critical security findings" || \
        error_exit "Failed to create critical EventBridge rule"
    
    # Add Lambda targets to the critical rule
    aws events put-targets \
        --rule "${EVENTBRIDGE_RULE_NAME}-critical" \
        --targets "Id"="1","Arn"="$CLASSIFICATION_FUNCTION_ARN" \
                 "Id"="2","Arn"="$REMEDIATION_FUNCTION_ARN" \
                 "Id"="3","Arn"="$NOTIFICATION_FUNCTION_ARN" || \
        error_exit "Failed to add targets to critical EventBridge rule"
    
    # Grant EventBridge permission to invoke Lambda functions
    aws lambda add-permission \
        --function-name "$CLASSIFICATION_FUNCTION_NAME" \
        --statement-id "AllowEventBridgeInvoke" \
        --action "lambda:InvokeFunction" \
        --principal events.amazonaws.com \
        --source-arn "arn:aws:events:${AWS_REGION}:${AWS_ACCOUNT_ID}:rule/${EVENTBRIDGE_RULE_NAME}-critical" || \
        warning "Failed to grant EventBridge permission to classification function"
    
    aws lambda add-permission \
        --function-name "$REMEDIATION_FUNCTION_NAME" \
        --statement-id "AllowEventBridgeInvoke" \
        --action "lambda:InvokeFunction" \
        --principal events.amazonaws.com \
        --source-arn "arn:aws:events:${AWS_REGION}:${AWS_ACCOUNT_ID}:rule/${EVENTBRIDGE_RULE_NAME}-critical" || \
        warning "Failed to grant EventBridge permission to remediation function"
    
    aws lambda add-permission \
        --function-name "$NOTIFICATION_FUNCTION_NAME" \
        --statement-id "AllowEventBridgeInvoke" \
        --action "lambda:InvokeFunction" \
        --principal events.amazonaws.com \
        --source-arn "arn:aws:events:${AWS_REGION}:${AWS_ACCOUNT_ID}:rule/${EVENTBRIDGE_RULE_NAME}-critical" || \
        warning "Failed to grant EventBridge permission to notification function"
    
    # Create separate rule for medium severity findings
    aws events put-rule \
        --name "${EVENTBRIDGE_RULE_NAME}-medium" \
        --event-pattern '{
            "source": ["aws.securityhub"],
            "detail-type": ["Security Hub Findings - Imported"],
            "detail": {
                "findings": {
                    "Severity": {
                        "Label": ["MEDIUM"]
                    },
                    "RecordState": ["ACTIVE"],
                    "WorkflowState": ["NEW"]
                }
            }
        }' \
        --state ENABLED \
        --description "Triggers notifications for medium severity security findings" || \
        error_exit "Failed to create medium EventBridge rule"
    
    aws events put-targets \
        --rule "${EVENTBRIDGE_RULE_NAME}-medium" \
        --targets "Id"="1","Arn"="$CLASSIFICATION_FUNCTION_ARN" \
                 "Id"="2","Arn"="$NOTIFICATION_FUNCTION_ARN" || \
        error_exit "Failed to add targets to medium EventBridge rule"
    
    success "EventBridge rules created for automated incident response"
}

# Create Security Hub custom actions
create_custom_actions() {
    info "Creating Security Hub custom actions..."
    
    # Create custom action for manual escalation
    CUSTOM_ACTION_ARN=$(aws securityhub create-action-target \
        --name "Escalate to Security Team" \
        --description "Manually escalate security finding to security team" \
        --id "escalate-to-security-team" \
        --query ActionTargetArn --output text) || \
        error_exit "Failed to create custom action"
    
    # Create EventBridge rule for custom action
    aws events put-rule \
        --name "${EVENTBRIDGE_RULE_NAME}-manual-escalation" \
        --event-pattern '{
            "source": ["aws.securityhub"],
            "detail-type": ["Security Hub Findings - Custom Action"],
            "detail": {
                "actionName": ["Escalate to Security Team"]
            }
        }' \
        --state ENABLED \
        --description "Handles manual escalation of security findings" || \
        error_exit "Failed to create manual escalation EventBridge rule"
    
    # Add notification target for manual escalation
    NOTIFICATION_FUNCTION_ARN=$(cat notification-function-arn.txt)
    aws events put-targets \
        --rule "${EVENTBRIDGE_RULE_NAME}-manual-escalation" \
        --targets "Id"="1","Arn"="$NOTIFICATION_FUNCTION_ARN" || \
        error_exit "Failed to add target to manual escalation rule"
    
    echo "$CUSTOM_ACTION_ARN" > custom-action-arn.txt
    success "Custom Security Hub actions created: $CUSTOM_ACTION_ARN"
}

# Create Security Hub insights
create_insights() {
    info "Creating Security Hub insights for incident tracking..."
    
    # Create insight for critical findings
    CRITICAL_INSIGHT_ARN=$(aws securityhub create-insight \
        --name "Critical Security Incidents" \
        --filters '{
            "SeverityLabel": [
                {
                    "Value": "CRITICAL",
                    "Comparison": "EQUALS"
                }
            ],
            "RecordState": [
                {
                    "Value": "ACTIVE",
                    "Comparison": "EQUALS"
                }
            ]
        }' \
        --group-by-attribute "ProductName" \
        --query InsightArn --output text) || \
        error_exit "Failed to create critical insight"
    
    # Create insight for unresolved findings
    UNRESOLVED_INSIGHT_ARN=$(aws securityhub create-insight \
        --name "Unresolved Security Findings" \
        --filters '{
            "WorkflowStatus": [
                {
                    "Value": "NEW",
                    "Comparison": "EQUALS"
                }
            ],
            "RecordState": [
                {
                    "Value": "ACTIVE",
                    "Comparison": "EQUALS"
                }
            ]
        }' \
        --group-by-attribute "SeverityLabel" \
        --query InsightArn --output text) || \
        error_exit "Failed to create unresolved insight"
    
    echo "$CRITICAL_INSIGHT_ARN" > critical-insight-arn.txt
    echo "$UNRESOLVED_INSIGHT_ARN" > unresolved-insight-arn.txt
    
    success "Security Hub insights created for incident tracking"
}

# Test the deployment
test_deployment() {
    info "Testing the automated incident response system..."
    
    # Create a test finding to trigger the automated response
    cat > test-finding.json << EOF
[
    {
        "SchemaVersion": "2018-10-08",
        "Id": "test-finding-$(date +%s)",
        "ProductArn": "arn:aws:securityhub:${AWS_REGION}:${AWS_ACCOUNT_ID}:product/${AWS_ACCOUNT_ID}/default",
        "GeneratorId": "TestGenerator",
        "AwsAccountId": "${AWS_ACCOUNT_ID}",
        "Types": ["Software and Configuration Checks/Vulnerabilities"],
        "FirstObservedAt": "$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ)",
        "LastObservedAt": "$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ)",
        "CreatedAt": "$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ)",
        "UpdatedAt": "$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ)",
        "Severity": {
            "Label": "HIGH",
            "Normalized": 70
        },
        "Title": "Test Security Group Open to Internet",
        "Description": "Test finding to validate automated incident response system",
        "Resources": [
            {
                "Type": "AwsEc2SecurityGroup",
                "Id": "arn:aws:ec2:${AWS_REGION}:${AWS_ACCOUNT_ID}:security-group/sg-test123",
                "Partition": "aws",
                "Region": "${AWS_REGION}"
            }
        ],
        "WorkflowState": "NEW",
        "RecordState": "ACTIVE"
    }
]
EOF
    
    # Import test finding
    aws securityhub batch-import-findings \
        --findings file://test-finding.json || \
        warning "Failed to import test finding"
    
    info "Test finding created. Check CloudWatch Logs for Lambda execution within 5 minutes."
    success "Deployment test completed"
}

# Main deployment function
main() {
    info "Starting AWS Automated Security Incident Response deployment..."
    
    # Create log file
    touch "$LOG_FILE"
    
    # Run deployment steps
    check_prerequisites
    setup_environment
    enable_security_hub
    create_iam_roles
    create_sns_topic
    create_lambda_functions
    create_eventbridge_rules
    create_custom_actions
    create_insights
    test_deployment
    
    success "🎉 AWS Automated Security Incident Response deployment completed successfully!"
    
    echo ""
    echo "=== DEPLOYMENT SUMMARY ==="
    echo "AWS Region: $AWS_REGION"
    echo "AWS Account ID: $AWS_ACCOUNT_ID"
    echo "Resource Suffix: $RANDOM_SUFFIX"
    echo ""
    echo "=== NEXT STEPS ==="
    echo "1. Subscribe to the SNS topic for notifications:"
    echo "   aws sns subscribe --topic-arn $(cat sns-topic-arn.txt) --protocol email --notification-endpoint your-email@company.com"
    echo ""
    echo "2. Review Security Hub findings in the AWS Console:"
    echo "   https://console.aws.amazon.com/securityhub/home?region=${AWS_REGION}#/findings"
    echo ""
    echo "3. Monitor CloudWatch Logs for Lambda function execution"
    echo ""
    echo "4. To clean up resources, run: ./destroy.sh"
    echo ""
    echo "=== ENVIRONMENT FILE ==="
    echo "Resource identifiers saved to: ${SCRIPT_DIR}/.env"
    echo "Use this file for cleanup and future operations."
    
    log "Deployment completed successfully"
}

# Run main function
main "$@"