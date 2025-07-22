#!/bin/bash

# AWS IoT Device Defender Security Implementation Deployment Script
# This script deploys comprehensive IoT security monitoring using AWS IoT Device Defender
# Recipe: IoT Security Monitoring with Device Defender

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Color codes for output formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

# Error handling function
cleanup_on_error() {
    log_error "Deployment failed. Cleaning up partially created resources..."
    
    # Only cleanup if variables are set
    if [[ -n "${SECURITY_PROFILE_NAME:-}" ]]; then
        aws iot detach-security-profile \
            --security-profile-name "${SECURITY_PROFILE_NAME}" \
            --security-profile-target-arn "arn:aws:iot:${AWS_REGION}:${AWS_ACCOUNT_ID}:all/registered-things" \
            2>/dev/null || true
        
        aws iot delete-security-profile \
            --security-profile-name "${SECURITY_PROFILE_NAME}" \
            2>/dev/null || true
    fi
    
    if [[ -n "${SNS_TOPIC_ARN:-}" ]]; then
        aws sns delete-topic --topic-arn "${SNS_TOPIC_ARN}" 2>/dev/null || true
    fi
    
    if [[ -n "${IAM_ROLE_NAME:-}" ]]; then
        aws iam detach-role-policy \
            --role-name "${IAM_ROLE_NAME}" \
            --policy-arn arn:aws:iam::aws:policy/service-role/AWSIoTDeviceDefenderAudit \
            2>/dev/null || true
        aws iam delete-role --role-name "${IAM_ROLE_NAME}" 2>/dev/null || true
    fi
    
    rm -f /tmp/device-defender-trust-policy.json 2>/dev/null || true
    
    exit 1
}

# Set trap for error handling
trap cleanup_on_error ERR

# Banner
echo "=============================================================================="
echo "  AWS IoT Device Defender Security Implementation Deployment"
echo "  Recipe: IoT Security Monitoring with Device Defender"
echo "=============================================================================="
echo

# Prerequisites check
log_info "Checking prerequisites..."

# Check if AWS CLI is installed
if ! command -v aws &> /dev/null; then
    log_error "AWS CLI is not installed. Please install AWS CLI v2 and configure it."
    exit 1
fi

# Check AWS CLI version
AWS_CLI_VERSION=$(aws --version 2>&1 | awk '{print $1}' | cut -d/ -f2 | cut -d. -f1)
if [[ "${AWS_CLI_VERSION}" -lt 2 ]]; then
    log_error "AWS CLI v2 is required. Current version: $(aws --version)"
    exit 1
fi

# Check AWS credentials
if ! aws sts get-caller-identity &> /dev/null; then
    log_error "AWS credentials not configured. Please run 'aws configure' or set up your credentials."
    exit 1
fi

# Check required permissions
log_info "Validating AWS permissions..."
CALLER_IDENTITY=$(aws sts get-caller-identity)
if [[ $? -ne 0 ]]; then
    log_error "Unable to verify AWS credentials"
    exit 1
fi

log_success "Prerequisites check completed"

# Set environment variables
log_info "Setting up environment variables..."

export AWS_REGION=$(aws configure get region)
if [[ -z "${AWS_REGION}" ]]; then
    log_error "AWS region not configured. Please set your default region with 'aws configure'"
    exit 1
fi

export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# Generate unique identifiers for resources
RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
    --exclude-punctuation --exclude-uppercase \
    --password-length 6 --require-each-included-type \
    --output text --query RandomPassword 2>/dev/null || \
    echo "$(date +%s | tail -c 6)")

export SECURITY_PROFILE_NAME="IoTSecurityProfile-${RANDOM_SUFFIX}"
export SNS_TOPIC_NAME="iot-security-alerts-${RANDOM_SUFFIX}"
export IAM_ROLE_NAME="IoTDeviceDefenderRole-${RANDOM_SUFFIX}"

log_success "Environment variables configured"
log_info "AWS Region: ${AWS_REGION}"
log_info "AWS Account ID: ${AWS_ACCOUNT_ID}"
log_info "Security Profile Name: ${SECURITY_PROFILE_NAME}"

# Get email address for notifications
if [[ -z "${EMAIL_ADDRESS:-}" ]]; then
    echo
    read -p "Enter your email address for security alerts: " EMAIL_ADDRESS
    if [[ -z "${EMAIL_ADDRESS}" ]]; then
        log_error "Email address is required for security notifications"
        exit 1
    fi
fi

# Validate email format
if [[ ! "${EMAIL_ADDRESS}" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; then
    log_error "Invalid email address format"
    exit 1
fi

echo

# Step 1: Create SNS topic for security alerts
log_info "Step 1: Creating SNS topic for security alerts..."

aws sns create-topic --name "${SNS_TOPIC_NAME}" >/dev/null

export SNS_TOPIC_ARN=$(aws sns get-topic-attributes \
    --topic-arn "arn:aws:sns:${AWS_REGION}:${AWS_ACCOUNT_ID}:${SNS_TOPIC_NAME}" \
    --query Attributes.TopicArn --output text)

log_success "Created SNS topic: ${SNS_TOPIC_ARN}"

# Subscribe to SNS topic for email notifications
log_info "Setting up email subscription..."
aws sns subscribe \
    --topic-arn "${SNS_TOPIC_ARN}" \
    --protocol email \
    --notification-endpoint "${EMAIL_ADDRESS}" >/dev/null

log_success "Email subscription created. Please check your email and confirm the subscription."

# Step 2: Create IAM Role for Device Defender
log_info "Step 2: Creating IAM role for Device Defender..."

# Create trust policy for Device Defender
cat > /tmp/device-defender-trust-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "iot.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF

# Create the IAM role
aws iam create-role \
    --role-name "${IAM_ROLE_NAME}" \
    --assume-role-policy-document file:///tmp/device-defender-trust-policy.json >/dev/null

# Attach managed policy for Device Defender
aws iam attach-role-policy \
    --role-name "${IAM_ROLE_NAME}" \
    --policy-arn arn:aws:iam::aws:policy/service-role/AWSIoTDeviceDefenderAudit

export IAM_ROLE_ARN=$(aws iam get-role \
    --role-name "${IAM_ROLE_NAME}" \
    --query Role.Arn --output text)

log_success "Created IAM role: ${IAM_ROLE_ARN}"

# Wait for IAM role propagation
log_info "Waiting for IAM role propagation..."
sleep 10

# Step 3: Configure Device Defender Audit Settings
log_info "Step 3: Configuring Device Defender audit settings..."

aws iot update-account-audit-configuration \
    --role-arn "${IAM_ROLE_ARN}" \
    --audit-notification-target-configurations \
    "SNS={targetArn=\"${SNS_TOPIC_ARN}\",roleArn=\"${IAM_ROLE_ARN}\",enabled=true}" \
    --audit-check-configurations \
    '{
      "AUTHENTICATED_COGNITO_ROLE_OVERLY_PERMISSIVE_CHECK": {"enabled": true},
      "CA_CERTIFICATE_EXPIRING_CHECK": {"enabled": true},
      "CONFLICTING_CLIENT_IDS_CHECK": {"enabled": true},
      "DEVICE_CERTIFICATE_EXPIRING_CHECK": {"enabled": true},
      "DEVICE_CERTIFICATE_SHARED_CHECK": {"enabled": true},
      "IOT_POLICY_OVERLY_PERMISSIVE_CHECK": {"enabled": true},
      "LOGGING_DISABLED_CHECK": {"enabled": true},
      "REVOKED_CA_CERTIFICATE_STILL_ACTIVE_CHECK": {"enabled": true},
      "REVOKED_DEVICE_CERTIFICATE_STILL_ACTIVE_CHECK": {"enabled": true},
      "UNAUTHENTICATED_COGNITO_ROLE_OVERLY_PERMISSIVE_CHECK": {"enabled": true}
    }' >/dev/null

log_success "Configured Device Defender audit settings"

# Step 4: Create Security Profile with Behavioral Rules
log_info "Step 4: Creating security profile with behavioral rules..."

aws iot create-security-profile \
    --security-profile-name "${SECURITY_PROFILE_NAME}" \
    --security-profile-description "Comprehensive IoT security monitoring profile" \
    --behaviors '[
      {
        "name": "ExcessiveMessages",
        "metric": "aws:num-messages-sent",
        "criteria": {
          "comparisonOperator": "greater-than",
          "value": {"count": 100},
          "durationSeconds": 300,
          "consecutiveDatapointsToAlarm": 1,
          "consecutiveDatapointsToClear": 1
        }
      },
      {
        "name": "AuthorizationFailures",
        "metric": "aws:num-authorization-failures",
        "criteria": {
          "comparisonOperator": "greater-than",
          "value": {"count": 5},
          "durationSeconds": 300,
          "consecutiveDatapointsToAlarm": 1,
          "consecutiveDatapointsToClear": 1
        }
      },
      {
        "name": "LargeMessageSize",
        "metric": "aws:message-byte-size",
        "criteria": {
          "comparisonOperator": "greater-than",
          "value": {"count": 1024},
          "consecutiveDatapointsToAlarm": 1,
          "consecutiveDatapointsToClear": 1
        }
      },
      {
        "name": "UnusualConnectionAttempts",
        "metric": "aws:num-connection-attempts",
        "criteria": {
          "comparisonOperator": "greater-than",
          "value": {"count": 20},
          "durationSeconds": 300,
          "consecutiveDatapointsToAlarm": 1,
          "consecutiveDatapointsToClear": 1
        }
      }
    ]' \
    --alert-targets '{
      "SNS": {
        "alertTargetArn": "'"${SNS_TOPIC_ARN}"'",
        "roleArn": "'"${IAM_ROLE_ARN}"'"
      }
    }' >/dev/null

export SECURITY_PROFILE_ARN=$(aws iot describe-security-profile \
    --security-profile-name "${SECURITY_PROFILE_NAME}" \
    --query securityProfileArn --output text)

log_success "Created security profile: ${SECURITY_PROFILE_ARN}"

# Step 5: Attach Security Profile to Target Devices
log_info "Step 5: Attaching security profile to target devices..."

aws iot attach-security-profile \
    --security-profile-name "${SECURITY_PROFILE_NAME}" \
    --security-profile-target-arn \
    "arn:aws:iot:${AWS_REGION}:${AWS_ACCOUNT_ID}:all/registered-things"

log_success "Attached security profile to all registered devices"

# Step 6: Create Scheduled Audit Task
log_info "Step 6: Creating scheduled audit task..."

aws iot create-scheduled-audit \
    --scheduled-audit-name "WeeklySecurityAudit-${RANDOM_SUFFIX}" \
    --frequency WEEKLY \
    --day-of-week MON \
    --target-check-names \
    CA_CERTIFICATE_EXPIRING_CHECK \
    DEVICE_CERTIFICATE_EXPIRING_CHECK \
    DEVICE_CERTIFICATE_SHARED_CHECK \
    IOT_POLICY_OVERLY_PERMISSIVE_CHECK \
    CONFLICTING_CLIENT_IDS_CHECK >/dev/null

log_success "Created scheduled weekly audit task"

# Step 7: Configure CloudWatch Alarms for Security Metrics
log_info "Step 7: Configuring CloudWatch alarms..."

aws cloudwatch put-metric-alarm \
    --alarm-name "IoT-SecurityViolations-${RANDOM_SUFFIX}" \
    --alarm-description "Alert on IoT Device Defender violations" \
    --metric-name "Violations" \
    --namespace "AWS/IoT/DeviceDefender" \
    --statistic Sum \
    --period 300 \
    --threshold 1 \
    --comparison-operator GreaterThanOrEqualToThreshold \
    --evaluation-periods 1 \
    --alarm-actions "${SNS_TOPIC_ARN}" \
    --treat-missing-data notBreaching

log_success "Created CloudWatch alarm for security violations"

# Step 8: Enable ML Detect for Advanced Threat Detection
log_info "Step 8: Creating ML-based security profile..."

aws iot create-security-profile \
    --security-profile-name "${SECURITY_PROFILE_NAME}-ML" \
    --security-profile-description "Machine learning based threat detection" \
    --behaviors '[
      {
        "name": "MLMessagesReceived",
        "metric": "aws:num-messages-received"
      },
      {
        "name": "MLMessagesSent",
        "metric": "aws:num-messages-sent"
      },
      {
        "name": "MLConnectionAttempts",
        "metric": "aws:num-connection-attempts"
      },
      {
        "name": "MLDisconnects",
        "metric": "aws:num-disconnects"
      }
    ]' \
    --alert-targets '{
      "SNS": {
        "alertTargetArn": "'"${SNS_TOPIC_ARN}"'",
        "roleArn": "'"${IAM_ROLE_ARN}"'"
      }
    }' >/dev/null

# Attach ML security profile to devices
aws iot attach-security-profile \
    --security-profile-name "${SECURITY_PROFILE_NAME}-ML" \
    --security-profile-target-arn \
    "arn:aws:iot:${AWS_REGION}:${AWS_ACCOUNT_ID}:all/registered-things"

log_success "Created and attached ML-based security profile"

# Step 9: Run On-Demand Audit
log_info "Step 9: Running on-demand audit..."

AUDIT_TASK_ID=$(aws iot start-on-demand-audit-task \
    --target-check-names \
    CA_CERTIFICATE_EXPIRING_CHECK \
    DEVICE_CERTIFICATE_EXPIRING_CHECK \
    DEVICE_CERTIFICATE_SHARED_CHECK \
    IOT_POLICY_OVERLY_PERMISSIVE_CHECK \
    CONFLICTING_CLIENT_IDS_CHECK \
    --query taskId --output text)

log_info "Started on-demand audit task: ${AUDIT_TASK_ID}"

# Wait for audit to complete
log_info "Waiting for audit to complete..."
aws iot wait audit-task-completed --task-id "${AUDIT_TASK_ID}"

log_success "Audit task completed"

# Save deployment information
log_info "Saving deployment information..."

cat > /tmp/iot-defender-deployment.env << EOF
# AWS IoT Device Defender Deployment Information
# Generated on $(date)

export AWS_REGION="${AWS_REGION}"
export AWS_ACCOUNT_ID="${AWS_ACCOUNT_ID}"
export SECURITY_PROFILE_NAME="${SECURITY_PROFILE_NAME}"
export SNS_TOPIC_NAME="${SNS_TOPIC_NAME}"
export IAM_ROLE_NAME="${IAM_ROLE_NAME}"
export SNS_TOPIC_ARN="${SNS_TOPIC_ARN}"
export IAM_ROLE_ARN="${IAM_ROLE_ARN}"
export SECURITY_PROFILE_ARN="${SECURITY_PROFILE_ARN}"
export AUDIT_TASK_ID="${AUDIT_TASK_ID}"
export EMAIL_ADDRESS="${EMAIL_ADDRESS}"
export RANDOM_SUFFIX="${RANDOM_SUFFIX}"
EOF

log_success "Deployment information saved to /tmp/iot-defender-deployment.env"

# Clean up temporary files
rm -f /tmp/device-defender-trust-policy.json

echo
log_success "AWS IoT Device Defender deployment completed successfully!"
echo
echo "=============================================================================="
echo "  DEPLOYMENT SUMMARY"
echo "=============================================================================="
echo "Security Profile: ${SECURITY_PROFILE_NAME}"
echo "SNS Topic: ${SNS_TOPIC_ARN}"
echo "IAM Role: ${IAM_ROLE_ARN}"
echo "Audit Task ID: ${AUDIT_TASK_ID}"
echo "Email Notifications: ${EMAIL_ADDRESS}"
echo
echo "IMPORTANT: Please confirm your email subscription to receive security alerts."
echo
echo "To verify your deployment:"
echo "  aws iot describe-security-profile --security-profile-name ${SECURITY_PROFILE_NAME}"
echo
echo "To cleanup resources, run: ./destroy.sh"
echo "=============================================================================="