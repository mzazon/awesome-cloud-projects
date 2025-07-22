#!/bin/bash

# Deploy script for Centralized SaaS Security Monitoring with AWS AppFabric and EventBridge
# This script automates the deployment of a complete security monitoring pipeline
# for SaaS applications using AWS AppFabric, EventBridge, Lambda, and SNS

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✅ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️  $1${NC}"
}

log_error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ❌ $1${NC}"
}

# Error handling
cleanup_on_error() {
    log_error "Deployment failed. Starting cleanup of partially created resources..."
    ./destroy.sh --auto-confirm || true
    exit 1
}

trap cleanup_on_error ERR

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMP_DIR="${SCRIPT_DIR}/../temp"
DRY_RUN=false
SKIP_CONFIRMATION=false
EMAIL_ADDRESS=""

# Parse command line arguments
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
        --yes|-y)
            SKIP_CONFIRMATION=true
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo "Options:"
            echo "  --dry-run          Show what would be deployed without making changes"
            echo "  --email EMAIL      Email address for security alerts"
            echo "  --yes, -y          Skip confirmation prompts"
            echo "  --help, -h         Show this help message"
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Dry run mode
if [[ "$DRY_RUN" == "true" ]]; then
    log_warning "Running in DRY RUN mode - no resources will be created"
    AWS_CLI="echo aws"
else
    AWS_CLI="aws"
fi

# Prerequisites check
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check AWS CLI version
    AWS_CLI_VERSION=$(aws --version 2>&1 | cut -d/ -f2 | cut -d' ' -f1)
    log "AWS CLI version: $AWS_CLI_VERSION"
    
    # Check if authenticated
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS CLI is not configured or credentials are invalid"
        exit 1
    fi
    
    # Check required permissions (basic check)
    local caller_identity=$(aws sts get-caller-identity)
    local account_id=$(echo "$caller_identity" | jq -r '.Account')
    local user_arn=$(echo "$caller_identity" | jq -r '.Arn')
    
    log "Authenticated as: $user_arn"
    log "Account ID: $account_id"
    
    # Check if region is configured
    if ! aws configure get region &> /dev/null; then
        log_error "AWS region is not configured. Please set your default region."
        exit 1
    fi
    
    # Check if jq is available
    if ! command -v jq &> /dev/null; then
        log_error "jq is required but not installed. Please install jq."
        exit 1
    fi
    
    # Check if zip is available
    if ! command -v zip &> /dev/null; then
        log_error "zip is required but not installed. Please install zip."
        exit 1
    fi
    
    log_success "Prerequisites check passed"
}

# Get email address for notifications
get_email_address() {
    if [[ -z "$EMAIL_ADDRESS" ]]; then
        echo -n "Enter your email address for security alerts: "
        read -r EMAIL_ADDRESS
    fi
    
    # Basic email validation
    if [[ ! "$EMAIL_ADDRESS" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; then
        log_error "Invalid email address format"
        exit 1
    fi
    
    log "Using email address: $EMAIL_ADDRESS"
}

# Set up environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    # Create temp directory
    mkdir -p "$TEMP_DIR"
    
    # Set AWS environment variables
    export AWS_REGION=$(aws configure get region)
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers for resources
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword)
    
    # Set resource names
    export APPFABRIC_APP_BUNDLE="saas-security-bundle-${RANDOM_SUFFIX}"
    export S3_BUCKET="security-logs-${AWS_ACCOUNT_ID}-${RANDOM_SUFFIX}"
    export EVENTBRIDGE_BUS="security-monitoring-bus-${RANDOM_SUFFIX}"
    export LAMBDA_FUNCTION="security-processor-${RANDOM_SUFFIX}"
    export SNS_TOPIC="security-alerts-${RANDOM_SUFFIX}"
    
    # Export for use in destroy script
    cat > "$TEMP_DIR/deployment_vars.sh" << EOF
# Deployment variables for cleanup
export AWS_REGION="$AWS_REGION"
export AWS_ACCOUNT_ID="$AWS_ACCOUNT_ID"
export RANDOM_SUFFIX="$RANDOM_SUFFIX"
export APPFABRIC_APP_BUNDLE="$APPFABRIC_APP_BUNDLE"
export S3_BUCKET="$S3_BUCKET"
export EVENTBRIDGE_BUS="$EVENTBRIDGE_BUS"
export LAMBDA_FUNCTION="$LAMBDA_FUNCTION"
export SNS_TOPIC="$SNS_TOPIC"
EOF
    
    log_success "Environment configured with suffix: $RANDOM_SUFFIX"
    log "AWS Region: $AWS_REGION"
    log "AWS Account ID: $AWS_ACCOUNT_ID"
}

# Create S3 bucket with security configurations
create_s3_bucket() {
    log "Creating S3 bucket for AppFabric logs..."
    
    # Create S3 bucket
    if [[ "$AWS_REGION" == "us-east-1" ]]; then
        $AWS_CLI s3 mb s3://${S3_BUCKET}
    else
        $AWS_CLI s3api create-bucket \
            --bucket ${S3_BUCKET} \
            --region ${AWS_REGION} \
            --create-bucket-configuration LocationConstraint=${AWS_REGION}
    fi
    
    # Enable versioning
    $AWS_CLI s3api put-bucket-versioning \
        --bucket ${S3_BUCKET} \
        --versioning-configuration Status=Enabled
    
    # Enable encryption
    $AWS_CLI s3api put-bucket-encryption \
        --bucket ${S3_BUCKET} \
        --server-side-encryption-configuration \
        'Rules=[{ApplyServerSideEncryptionByDefault:{SSEAlgorithm:AES256}}]'
    
    # Block public access
    $AWS_CLI s3api put-public-access-block \
        --bucket ${S3_BUCKET} \
        --public-access-block-configuration \
        BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
    
    # Add bucket policy for AppFabric access
    cat > "$TEMP_DIR/bucket-policy.json" << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "AppFabricLogDelivery",
            "Effect": "Allow",
            "Principal": {
                "Service": "appfabric.amazonaws.com"
            },
            "Action": [
                "s3:PutObject",
                "s3:PutObjectAcl",
                "s3:GetBucketLocation"
            ],
            "Resource": [
                "arn:aws:s3:::${S3_BUCKET}",
                "arn:aws:s3:::${S3_BUCKET}/*"
            ],
            "Condition": {
                "StringEquals": {
                    "aws:SourceAccount": "${AWS_ACCOUNT_ID}"
                }
            }
        }
    ]
}
EOF
    
    $AWS_CLI s3api put-bucket-policy \
        --bucket ${S3_BUCKET} \
        --policy file://"$TEMP_DIR/bucket-policy.json"
    
    log_success "S3 bucket created with security configurations: $S3_BUCKET"
}

# Create IAM roles with least privilege access
create_iam_roles() {
    log "Creating IAM roles for service integration..."
    
    # AppFabric service role trust policy
    cat > "$TEMP_DIR/appfabric-trust-policy.json" << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Service": "appfabric.amazonaws.com"
            },
            "Action": "sts:AssumeRole"
        }
    ]
}
EOF
    
    # Create AppFabric service role
    $AWS_CLI iam create-role \
        --role-name AppFabricServiceRole-${RANDOM_SUFFIX} \
        --assume-role-policy-document file://"$TEMP_DIR/appfabric-trust-policy.json" \
        --description "Service role for AppFabric to write security logs to S3"
    
    # AppFabric S3 access policy
    cat > "$TEMP_DIR/appfabric-s3-policy.json" << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "s3:PutObject",
                "s3:PutObjectAcl",
                "s3:GetBucketLocation"
            ],
            "Resource": [
                "arn:aws:s3:::${S3_BUCKET}",
                "arn:aws:s3:::${S3_BUCKET}/*"
            ]
        }
    ]
}
EOF
    
    $AWS_CLI iam put-role-policy \
        --role-name AppFabricServiceRole-${RANDOM_SUFFIX} \
        --policy-name S3AccessPolicy \
        --policy-document file://"$TEMP_DIR/appfabric-s3-policy.json"
    
    # Lambda execution role trust policy
    cat > "$TEMP_DIR/lambda-trust-policy.json" << EOF
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
    
    # Create Lambda execution role
    $AWS_CLI iam create-role \
        --role-name LambdaSecurityProcessorRole-${RANDOM_SUFFIX} \
        --assume-role-policy-document file://"$TEMP_DIR/lambda-trust-policy.json" \
        --description "Execution role for security processing Lambda function"
    
    # Attach Lambda basic execution policy
    $AWS_CLI iam attach-role-policy \
        --role-name LambdaSecurityProcessorRole-${RANDOM_SUFFIX} \
        --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
    
    # Get role ARNs
    export APPFABRIC_ROLE_ARN=$($AWS_CLI iam get-role \
        --role-name AppFabricServiceRole-${RANDOM_SUFFIX} \
        --query 'Role.Arn' --output text)
    
    export LAMBDA_ROLE_ARN=$($AWS_CLI iam get-role \
        --role-name LambdaSecurityProcessorRole-${RANDOM_SUFFIX} \
        --query 'Role.Arn' --output text)
    
    # Save role ARNs to deployment vars
    echo "export APPFABRIC_ROLE_ARN=\"$APPFABRIC_ROLE_ARN\"" >> "$TEMP_DIR/deployment_vars.sh"
    echo "export LAMBDA_ROLE_ARN=\"$LAMBDA_ROLE_ARN\"" >> "$TEMP_DIR/deployment_vars.sh"
    
    log_success "IAM roles created successfully"
    log "AppFabric Role ARN: $APPFABRIC_ROLE_ARN"
    log "Lambda Role ARN: $LAMBDA_ROLE_ARN"
}

# Create EventBridge custom bus and rules
create_eventbridge_resources() {
    log "Creating EventBridge resources..."
    
    # Create custom event bus
    $AWS_CLI events create-event-bus \
        --name ${EVENTBRIDGE_BUS} \
        --tags Key=Purpose,Value=SecurityMonitoring \
               Key=Environment,Value=Production \
               Key=ManagedBy,Value=SecurityMonitoringPipeline
    
    log_success "EventBridge custom bus created: $EVENTBRIDGE_BUS"
}

# Create SNS topic for security alerts
create_sns_topic() {
    log "Creating SNS topic for security alerts..."
    
    # Create SNS topic
    $AWS_CLI sns create-topic \
        --name ${SNS_TOPIC} \
        --attributes DisplayName="Security Alerts - SaaS Monitoring"
    
    export SNS_TOPIC_ARN=$($AWS_CLI sns get-topic-attributes \
        --topic-arn arn:aws:sns:${AWS_REGION}:${AWS_ACCOUNT_ID}:${SNS_TOPIC} \
        --query 'Attributes.TopicArn' --output text)
    
    # Subscribe email to SNS topic
    $AWS_CLI sns subscribe \
        --topic-arn ${SNS_TOPIC_ARN} \
        --protocol email \
        --notification-endpoint ${EMAIL_ADDRESS}
    
    # Save SNS topic ARN to deployment vars
    echo "export SNS_TOPIC_ARN=\"$SNS_TOPIC_ARN\"" >> "$TEMP_DIR/deployment_vars.sh"
    
    log_success "SNS topic created: $SNS_TOPIC"
    log_warning "Please check your email ($EMAIL_ADDRESS) and confirm the SNS subscription"
}

# Create and deploy Lambda function
create_lambda_function() {
    log "Creating Lambda function for security event processing..."
    
    # Create Lambda function code directory
    mkdir -p "$TEMP_DIR/lambda-security-processor"
    
    # Create Lambda function code
    cat > "$TEMP_DIR/lambda-security-processor/index.py" << 'EOF'
import json
import boto3
import logging
import os
import re
from datetime import datetime
from typing import Dict, Any, List

logger = logging.getLogger()
logger.setLevel(logging.INFO)

sns = boto3.client('sns')
s3 = boto3.client('s3')

def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """Process security events from AppFabric and generate alerts"""
    
    try:
        logger.info(f"Processing event: {json.dumps(event, default=str)}")
        
        # Process S3 events from EventBridge
        if 'Records' in event:
            for record in event['Records']:
                if record.get('eventSource') == 'aws:s3':
                    process_s3_security_log(record)
        
        # Process direct EventBridge events
        elif 'source' in event:
            process_eventbridge_event(event)
        
        # Process S3 notifications through EventBridge
        elif event.get('source') == 'aws.s3':
            process_s3_event_from_eventbridge(event)
            
        return {
            'statusCode': 200,
            'body': json.dumps('Security events processed successfully')
        }
        
    except Exception as e:
        logger.error(f"Error processing security event: {str(e)}")
        send_error_alert(str(e), event)
        raise

def process_s3_security_log(s3_record: Dict[str, Any]) -> None:
    """Process security logs uploaded to S3 by AppFabric"""
    
    bucket = s3_record['s3']['bucket']['name']
    key = s3_record['s3']['object']['key']
    
    logger.info(f"Processing security log: s3://{bucket}/{key}")
    
    try:
        # Download and analyze the log file
        response = s3.get_object(Bucket=bucket, Key=key)
        log_content = response['Body'].read().decode('utf-8')
        
        # Parse OCSF formatted logs
        log_entries = parse_ocsf_logs(log_content)
        
        # Analyze each log entry for threats
        for entry in log_entries:
            analyze_security_event(entry, key)
            
    except Exception as e:
        logger.error(f"Error processing S3 log {key}: {str(e)}")

def process_s3_event_from_eventbridge(event: Dict[str, Any]) -> None:
    """Process S3 events received through EventBridge"""
    
    detail = event.get('detail', {})
    bucket = detail.get('bucket', {}).get('name')
    key = detail.get('object', {}).get('key')
    
    if bucket and key:
        logger.info(f"Processing EventBridge S3 event: s3://{bucket}/{key}")
        
        # Extract application name from S3 key path
        app_name = extract_app_name(key)
        
        # Generate alert for new security log
        alert_message = {
            'alert_type': 'NEW_SECURITY_LOG',
            'application': app_name,
            'timestamp': datetime.utcnow().isoformat(),
            's3_location': f"s3://{bucket}/{key}",
            'severity': 'INFO'
        }
        
        send_security_alert(alert_message)

def process_eventbridge_event(event: Dict[str, Any]) -> None:
    """Process custom security events from EventBridge"""
    
    event_type = event.get('detail-type', 'Unknown')
    source = event.get('source', 'Unknown')
    
    logger.info(f"Processing EventBridge event: {event_type} from {source}")
    
    # Apply threat detection logic based on event patterns
    if is_suspicious_activity(event):
        alert_message = {
            'alert_type': 'SUSPICIOUS_ACTIVITY',
            'event_type': event_type,
            'source': source,
            'timestamp': datetime.utcnow().isoformat(),
            'severity': 'HIGH',
            'details': event.get('detail', {})
        }
        
        send_security_alert(alert_message)

def parse_ocsf_logs(log_content: str) -> List[Dict[str, Any]]:
    """Parse OCSF formatted log content"""
    
    log_entries = []
    
    # Handle both single JSON objects and NDJSON format
    for line in log_content.strip().split('\n'):
        if line.strip():
            try:
                entry = json.loads(line)
                log_entries.append(entry)
            except json.JSONDecodeError:
                logger.warning(f"Failed to parse log line: {line[:100]}...")
    
    return log_entries

def analyze_security_event(log_entry: Dict[str, Any], s3_key: str) -> None:
    """Analyze individual security log entry for threats"""
    
    # Extract key fields from OCSF format
    severity = log_entry.get('severity_id', 1)
    activity_id = log_entry.get('activity_id', 0)
    class_uid = log_entry.get('class_uid', 0)
    
    # High severity events (4 = High, 5 = Critical)
    if severity >= 4:
        alert_message = {
            'alert_type': 'HIGH_SEVERITY_EVENT',
            'severity': map_severity_id(severity),
            'timestamp': datetime.utcnow().isoformat(),
            'ocsf_class': class_uid,
            'activity_id': activity_id,
            's3_location': s3_key,
            'event_details': log_entry
        }
        
        send_security_alert(alert_message)
    
    # Authentication failures
    if class_uid == 3002 and activity_id in [2, 3]:  # Authentication class, logon failure
        alert_message = {
            'alert_type': 'AUTHENTICATION_FAILURE',
            'severity': 'MEDIUM',
            'timestamp': datetime.utcnow().isoformat(),
            'user': log_entry.get('user', {}).get('name', 'Unknown'),
            'src_endpoint': log_entry.get('src_endpoint', {}),
            's3_location': s3_key,
            'event_details': log_entry
        }
        
        send_security_alert(alert_message)

def is_suspicious_activity(event: Dict[str, Any]) -> bool:
    """Apply threat detection logic to identify suspicious activities"""
    
    detail = event.get('detail', {})
    
    # Threat detection patterns
    suspicious_indicators = [
        'failed_login_attempt',
        'privilege_escalation',
        'unusual_access_pattern',
        'data_exfiltration',
        'brute_force',
        'account_lockout',
        'unauthorized_access'
    ]
    
    event_text = json.dumps(detail).lower()
    return any(indicator in event_text for indicator in suspicious_indicators)

def extract_app_name(s3_key: str) -> str:
    """Extract application name from S3 key path"""
    
    # AppFabric S3 key format: app-bundle-id/app-name/yyyy/mm/dd/file
    path_parts = s3_key.split('/')
    return path_parts[1] if len(path_parts) > 1 else 'unknown'

def map_severity_id(severity_id: int) -> str:
    """Map OCSF severity ID to string"""
    
    severity_map = {
        1: 'INFO',
        2: 'LOW',
        3: 'MEDIUM',
        4: 'HIGH',
        5: 'CRITICAL'
    }
    
    return severity_map.get(severity_id, 'UNKNOWN')

def send_security_alert(alert_message: Dict[str, Any]) -> None:
    """Send security alert via SNS"""
    
    topic_arn = os.environ['SNS_TOPIC_ARN']
    
    message = {
        'default': json.dumps(alert_message, indent=2, default=str),
        'email': format_email_alert(alert_message),
        'sms': format_sms_alert(alert_message)
    }
    
    try:
        sns.publish(
            TopicArn=topic_arn,
            Message=json.dumps(message),
            MessageStructure='json',
            Subject=f"Security Alert: {alert_message['alert_type']}"
        )
        
        logger.info(f"Security alert sent: {alert_message['alert_type']}")
        
    except Exception as e:
        logger.error(f"Failed to send security alert: {str(e)}")

def format_email_alert(alert: Dict[str, Any]) -> str:
    """Format security alert for email delivery"""
    
    return f"""
Security Alert: {alert['alert_type']}

Severity: {alert['severity']}
Timestamp: {alert['timestamp']}
Application: {alert.get('application', 'N/A')}
Source: {alert.get('source', 'N/A')}

Details:
{json.dumps(alert.get('details', alert.get('event_details', {})), indent=2, default=str)}

S3 Location: {alert.get('s3_location', 'N/A')}

This is an automated security alert from your SaaS monitoring system.
Please review and take appropriate action if necessary.

---
AWS Centralized SaaS Security Monitoring
"""

def format_sms_alert(alert: Dict[str, Any]) -> str:
    """Format security alert for SMS delivery"""
    
    return f"SECURITY ALERT: {alert['alert_type']} - {alert['severity']} severity detected at {alert['timestamp'][:19]}"

def send_error_alert(error_message: str, original_event: Dict[str, Any]) -> None:
    """Send alert when Lambda function encounters an error"""
    
    alert_message = {
        'alert_type': 'PROCESSING_ERROR',
        'severity': 'HIGH',
        'timestamp': datetime.utcnow().isoformat(),
        'error_message': error_message,
        'original_event': original_event
    }
    
    try:
        send_security_alert(alert_message)
    except Exception as e:
        logger.error(f"Failed to send error alert: {str(e)}")
EOF
    
    # Create Lambda deployment package
    cd "$TEMP_DIR/lambda-security-processor"
    zip -r ../security-processor.zip .
    cd "$SCRIPT_DIR"
    
    # Add SNS permissions to Lambda role
    cat > "$TEMP_DIR/lambda-sns-policy.json" << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "sns:Publish"
            ],
            "Resource": "${SNS_TOPIC_ARN}"
        },
        {
            "Effect": "Allow",
            "Action": [
                "s3:GetObject"
            ],
            "Resource": "arn:aws:s3:::${S3_BUCKET}/*"
        }
    ]
}
EOF
    
    $AWS_CLI iam put-role-policy \
        --role-name LambdaSecurityProcessorRole-${RANDOM_SUFFIX} \
        --policy-name SNSAndS3AccessPolicy \
        --policy-document file://"$TEMP_DIR/lambda-sns-policy.json"
    
    # Wait for IAM role propagation
    log "Waiting for IAM role propagation..."
    sleep 10
    
    # Create Lambda function
    $AWS_CLI lambda create-function \
        --function-name ${LAMBDA_FUNCTION} \
        --runtime python3.9 \
        --role ${LAMBDA_ROLE_ARN} \
        --handler index.lambda_handler \
        --zip-file fileb://"$TEMP_DIR/security-processor.zip" \
        --timeout 300 \
        --memory-size 512 \
        --environment Variables="{SNS_TOPIC_ARN=${SNS_TOPIC_ARN}}" \
        --description "Security event processor for SaaS monitoring pipeline" \
        --tags Purpose=SecurityMonitoring,Environment=Production,ManagedBy=SecurityMonitoringPipeline
    
    export LAMBDA_FUNCTION_ARN=$($AWS_CLI lambda get-function \
        --function-name ${LAMBDA_FUNCTION} \
        --query 'Configuration.FunctionArn' --output text)
    
    # Save Lambda function ARN to deployment vars
    echo "export LAMBDA_FUNCTION_ARN=\"$LAMBDA_FUNCTION_ARN\"" >> "$TEMP_DIR/deployment_vars.sh"
    
    log_success "Lambda function deployed successfully"
    log "Lambda Function ARN: $LAMBDA_FUNCTION_ARN"
}

# Configure EventBridge rules
configure_eventbridge_rules() {
    log "Configuring EventBridge rules for security event processing..."
    
    # Create EventBridge rule for S3 security log events
    cat > "$TEMP_DIR/eventbridge-rule-pattern.json" << EOF
{
    "source": ["aws.s3"],
    "detail-type": ["Object Created"],
    "detail": {
        "bucket": {
            "name": ["${S3_BUCKET}"]
        }
    }
}
EOF
    
    $AWS_CLI events put-rule \
        --name SecurityLogProcessingRule-${RANDOM_SUFFIX} \
        --event-pattern file://"$TEMP_DIR/eventbridge-rule-pattern.json" \
        --event-bus-name ${EVENTBRIDGE_BUS} \
        --description "Route S3 security logs to Lambda processor" \
        --state ENABLED
    
    # Add Lambda as target for the rule
    $AWS_CLI events put-targets \
        --rule SecurityLogProcessingRule-${RANDOM_SUFFIX} \
        --event-bus-name ${EVENTBRIDGE_BUS} \
        --targets "Id"="1","Arn"="${LAMBDA_FUNCTION_ARN}"
    
    # Grant EventBridge permission to invoke Lambda
    $AWS_CLI lambda add-permission \
        --function-name ${LAMBDA_FUNCTION} \
        --statement-id eventbridge-invoke-${RANDOM_SUFFIX} \
        --action lambda:InvokeFunction \
        --principal events.amazonaws.com \
        --source-arn arn:aws:events:${AWS_REGION}:${AWS_ACCOUNT_ID}:rule/${EVENTBRIDGE_BUS}/SecurityLogProcessingRule-${RANDOM_SUFFIX}
    
    log_success "EventBridge rules configured successfully"
}

# Create AppFabric app bundle
create_appfabric_resources() {
    log "Creating AppFabric app bundle..."
    
    # Check if AppFabric is available in the region
    local supported_regions=("us-east-1" "eu-west-1" "ap-northeast-1")
    if [[ ! " ${supported_regions[@]} " =~ " ${AWS_REGION} " ]]; then
        log_warning "AppFabric may not be available in region ${AWS_REGION}"
        log_warning "Supported regions: us-east-1, eu-west-1, ap-northeast-1"
    fi
    
    # Create AppFabric app bundle
    $AWS_CLI appfabric create-app-bundle \
        --tags Purpose=SecurityMonitoring,Environment=Production,ManagedBy=SecurityMonitoringPipeline \
        --customer-managed-key-identifier alias/aws/s3
    
    export APP_BUNDLE_ARN=$($AWS_CLI appfabric list-app-bundles \
        --query 'appBundles[0].arn' --output text)
    
    # Save app bundle ARN to deployment vars
    echo "export APP_BUNDLE_ARN=\"$APP_BUNDLE_ARN\"" >> "$TEMP_DIR/deployment_vars.sh"
    
    log_success "AppFabric app bundle created successfully"
    log "App Bundle ARN: $APP_BUNDLE_ARN"
    
    log_warning "Manual steps required:"
    log "1. Go to AWS Console > AppFabric"
    log "2. Create ingestions for your SaaS applications"
    log "3. Authorize AppFabric to access SaaS APIs"
    log "4. Configure S3 destination: s3://${S3_BUCKET}/security-logs/"
}

# Configure S3 EventBridge notifications
configure_s3_eventbridge() {
    log "Configuring S3 EventBridge notifications..."
    
    # Enable EventBridge notifications on S3 bucket
    cat > "$TEMP_DIR/s3-event-config.json" << EOF
{
    "EventBridgeConfiguration": {
        "EventBridgeEnabled": true
    }
}
EOF
    
    $AWS_CLI s3api put-bucket-notification-configuration \
        --bucket ${S3_BUCKET} \
        --notification-configuration file://"$TEMP_DIR/s3-event-config.json"
    
    log_success "S3 EventBridge notifications configured"
}

# Run deployment tests
run_deployment_tests() {
    log "Running deployment validation tests..."
    
    # Test 1: Verify S3 bucket exists and is accessible
    if $AWS_CLI s3 ls s3://${S3_BUCKET} > /dev/null 2>&1; then
        log_success "S3 bucket test passed"
    else
        log_error "S3 bucket test failed"
        return 1
    fi
    
    # Test 2: Verify Lambda function exists
    if $AWS_CLI lambda get-function --function-name ${LAMBDA_FUNCTION} > /dev/null 2>&1; then
        log_success "Lambda function test passed"
    else
        log_error "Lambda function test failed"
        return 1
    fi
    
    # Test 3: Verify SNS topic exists
    if $AWS_CLI sns get-topic-attributes --topic-arn ${SNS_TOPIC_ARN} > /dev/null 2>&1; then
        log_success "SNS topic test passed"
    else
        log_error "SNS topic test failed"
        return 1
    fi
    
    # Test 4: Verify EventBridge bus exists
    if $AWS_CLI events describe-event-bus --name ${EVENTBRIDGE_BUS} > /dev/null 2>&1; then
        log_success "EventBridge bus test passed"
    else
        log_error "EventBridge bus test failed"
        return 1
    fi
    
    # Test 5: Create and upload test security event
    log "Testing security event processing pipeline..."
    
    cat > "$TEMP_DIR/test-security-event.json" << EOF
{
    "metadata": {
        "version": "1.0.0",
        "product": {
            "name": "Test SaaS Application",
            "vendor_name": "Test Vendor"
        }
    },
    "time": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "class_uid": 3002,
    "category_uid": 3,
    "severity_id": 2,
    "activity_id": 1,
    "type_name": "Authentication: Logon",
    "user": {
        "name": "test.user@example.com",
        "type": "User"
    },
    "src_endpoint": {
        "ip": "192.168.1.100"
    },
    "status": "Success"
}
EOF
    
    # Upload test event to S3 to trigger processing
    $AWS_CLI s3 cp "$TEMP_DIR/test-security-event.json" \
        s3://${S3_BUCKET}/security-logs/test-app/$(date +%Y/%m/%d)/test-event-$(date +%s).json
    
    log "Test event uploaded. Waiting for processing..."
    sleep 10
    
    log_success "Deployment validation tests completed"
}

# Display deployment summary
display_summary() {
    log_success "Deployment completed successfully!"
    echo
    echo "=== DEPLOYMENT SUMMARY ==="
    echo "AWS Region: $AWS_REGION"
    echo "AWS Account ID: $AWS_ACCOUNT_ID"
    echo "Deployment ID: $RANDOM_SUFFIX"
    echo
    echo "=== RESOURCES CREATED ==="
    echo "• S3 Bucket: $S3_BUCKET"
    echo "• EventBridge Bus: $EVENTBRIDGE_BUS"
    echo "• Lambda Function: $LAMBDA_FUNCTION"
    echo "• SNS Topic: $SNS_TOPIC"
    echo "• AppFabric App Bundle: $APP_BUNDLE_ARN"
    echo
    echo "=== NEXT STEPS ==="
    echo "1. Confirm your email subscription for SNS alerts"
    echo "2. Configure SaaS application connections in AppFabric Console:"
    echo "   - Go to AWS Console > AppFabric"
    echo "   - Select your app bundle: $APPFABRIC_APP_BUNDLE"
    echo "   - Create ingestions for your SaaS applications"
    echo "   - Set S3 destination: s3://${S3_BUCKET}/security-logs/"
    echo
    echo "3. Monitor CloudWatch logs for Lambda function:"
    echo "   - Log group: /aws/lambda/$LAMBDA_FUNCTION"
    echo
    echo "4. To clean up resources, run: ./destroy.sh"
    echo
    echo "=== ESTIMATED MONTHLY COST ==="
    echo "• S3 Storage: ~$1-5 (depending on log volume)"
    echo "• Lambda: ~$1-10 (depending on invocations)"
    echo "• SNS: ~$1-2"
    echo "• EventBridge: ~$1"
    echo "• AppFabric: ~$15-30 (per application connection)"
    echo "Total: ~$20-50/month"
    echo
}

# Main deployment function
main() {
    log "Starting deployment of Centralized SaaS Security Monitoring..."
    
    if [[ "$SKIP_CONFIRMATION" != "true" ]]; then
        echo "This will deploy AWS resources for SaaS security monitoring."
        echo "Estimated cost: $20-50/month"
        echo -n "Do you want to continue? (y/N): "
        read -r confirmation
        if [[ ! "$confirmation" =~ ^[Yy]$ ]]; then
            log "Deployment cancelled by user"
            exit 0
        fi
    fi
    
    # Run deployment steps
    check_prerequisites
    get_email_address
    setup_environment
    create_s3_bucket
    create_iam_roles
    create_eventbridge_resources
    create_sns_topic
    create_lambda_function
    configure_eventbridge_rules
    configure_s3_eventbridge
    create_appfabric_resources
    run_deployment_tests
    display_summary
    
    log_success "Deployment completed successfully!"
}

# Run main function
main "$@"