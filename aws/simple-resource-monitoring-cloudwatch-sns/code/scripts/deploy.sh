#!/bin/bash

# Deploy script for Simple Resource Monitoring with CloudWatch and SNS
# This script creates EC2 instances, SNS topics, and CloudWatch alarms for basic monitoring

set -euo pipefail

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/deploy.log"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "[${TIMESTAMP}] $1" | tee -a "${LOG_FILE}"
}

# Error handling function
error_exit() {
    log "${RED}ERROR: $1${NC}"
    exit 1
}

# Success message function
success() {
    log "${GREEN}✅ $1${NC}"
}

# Warning message function
warning() {
    log "${YELLOW}⚠️  $1${NC}"
}

# Info message function
info() {
    log "${BLUE}ℹ️  $1${NC}"
}

# Check prerequisites
check_prerequisites() {
    info "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        error_exit "AWS CLI is not installed. Please install it first."
    fi
    
    # Check if AWS CLI is configured
    if ! aws sts get-caller-identity &> /dev/null; then
        error_exit "AWS CLI is not configured. Please run 'aws configure' first."
    fi
    
    # Check if jq is installed (helpful for JSON parsing)
    if ! command -v jq &> /dev/null; then
        warning "jq is not installed. Some operations may be less efficient."
    fi
    
    success "Prerequisites check completed"
}

# Get user input for email address
get_user_email() {
    if [[ -z "${USER_EMAIL:-}" ]]; then
        read -p "Enter your email address for alerts: " USER_EMAIL
        if [[ ! "$USER_EMAIL" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; then
            error_exit "Invalid email address format"
        fi
    fi
    export USER_EMAIL
    info "Using email address: ${USER_EMAIL}"
}

# Set environment variables
setup_environment() {
    info "Setting up environment variables..."
    
    # Get AWS region and account ID
    export AWS_REGION=$(aws configure get region)
    if [[ -z "${AWS_REGION}" ]]; then
        export AWS_REGION="us-east-1"
        warning "No default region configured, using us-east-1"
    fi
    
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers for resources
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || \
        echo $(date +%s | tail -c 7))
    
    export INSTANCE_NAME="monitoring-demo-${RANDOM_SUFFIX}"
    export TOPIC_NAME="cpu-alerts-${RANDOM_SUFFIX}"
    export ALARM_NAME="high-cpu-${RANDOM_SUFFIX}"
    
    # Create state file to track resources
    STATE_FILE="${SCRIPT_DIR}/deploy-state.env"
    cat > "${STATE_FILE}" << EOF
AWS_REGION=${AWS_REGION}
AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID}
INSTANCE_NAME=${INSTANCE_NAME}
TOPIC_NAME=${TOPIC_NAME}
ALARM_NAME=${ALARM_NAME}
USER_EMAIL=${USER_EMAIL}
RANDOM_SUFFIX=${RANDOM_SUFFIX}
EOF
    
    success "Environment configured for monitoring setup"
    info "Region: ${AWS_REGION}"
    info "Account ID: ${AWS_ACCOUNT_ID}"
    info "Instance Name: ${INSTANCE_NAME}"
    info "Topic Name: ${TOPIC_NAME}"
    info "Alarm Name: ${ALARM_NAME}"
}

# Launch EC2 instance
launch_ec2_instance() {
    info "Launching EC2 instance for monitoring..."
    
    # Get the latest Amazon Linux 2023 AMI ID
    AMI_ID=$(aws ec2 describe-images \
        --owners amazon \
        --filters \
        "Name=name,Values=al2023-ami-kernel-*-x86_64" \
        "Name=state,Values=available" \
        --query 'Images | sort_by(@, &CreationDate) | [-1].ImageId' \
        --output text)
    
    if [[ -z "${AMI_ID}" || "${AMI_ID}" == "None" ]]; then
        # Fallback to SSM parameter
        AMI_ID=$(aws ssm get-parameter \
            --name "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64" \
            --query 'Parameter.Value' --output text 2>/dev/null || echo "")
    fi
    
    if [[ -z "${AMI_ID}" ]]; then
        error_exit "Could not determine Amazon Linux 2023 AMI ID"
    fi
    
    # Launch instance
    INSTANCE_ID=$(aws ec2 run-instances \
        --image-id "${AMI_ID}" \
        --instance-type t2.micro \
        --security-groups default \
        --tag-specifications \
        "ResourceType=instance,Tags=[{Key=Name,Value=${INSTANCE_NAME}},{Key=Purpose,Value=Monitoring-Demo}]" \
        --user-data "#!/bin/bash
yum update -y
yum install -y stress-ng" \
        --query 'Instances[0].InstanceId' --output text)
    
    if [[ -z "${INSTANCE_ID}" ]]; then
        error_exit "Failed to launch EC2 instance"
    fi
    
    export INSTANCE_ID
    echo "INSTANCE_ID=${INSTANCE_ID}" >> "${STATE_FILE}"
    
    success "EC2 instance launched: ${INSTANCE_ID}"
    info "AMI ID used: ${AMI_ID}"
}

# Create SNS topic
create_sns_topic() {
    info "Creating SNS topic for notifications..."
    
    TOPIC_ARN=$(aws sns create-topic \
        --name "${TOPIC_NAME}" \
        --attributes DisplayName="CPU Alerts for ${INSTANCE_NAME}" \
        --tags "Key=Purpose,Value=Monitoring-Demo" \
        --query 'TopicArn' --output text)
    
    if [[ -z "${TOPIC_ARN}" ]]; then
        error_exit "Failed to create SNS topic"
    fi
    
    export TOPIC_ARN
    echo "TOPIC_ARN=${TOPIC_ARN}" >> "${STATE_FILE}"
    
    success "SNS topic created: ${TOPIC_ARN}"
}

# Subscribe email to SNS topic
subscribe_email_to_topic() {
    info "Subscribing email address to SNS topic..."
    
    SUBSCRIPTION_ARN=$(aws sns subscribe \
        --topic-arn "${TOPIC_ARN}" \
        --protocol email \
        --notification-endpoint "${USER_EMAIL}" \
        --query 'SubscriptionArn' --output text)
    
    if [[ -z "${SUBSCRIPTION_ARN}" ]]; then
        error_exit "Failed to create email subscription"
    fi
    
    echo "SUBSCRIPTION_ARN=${SUBSCRIPTION_ARN}" >> "${STATE_FILE}"
    
    success "Email subscription created (pending confirmation)"
    warning "Check your email and confirm the subscription before proceeding"
    
    # Wait for user confirmation
    echo ""
    echo "Please check your email inbox for a subscription confirmation message from AWS."
    echo "Click the confirmation link in the email to complete the subscription."
    echo ""
    read -p "Press Enter after confirming the subscription in your email..."
    
    # Verify subscription was confirmed
    CONFIRMED_SUB=$(aws sns list-subscriptions-by-topic \
        --topic-arn "${TOPIC_ARN}" \
        --query 'Subscriptions[?Protocol==`email` && Endpoint==`'"${USER_EMAIL}"'`].SubscriptionArn' \
        --output text)
    
    if [[ "${CONFIRMED_SUB}" == "PendingConfirmation" ]]; then
        warning "Subscription is still pending. Alarms may not send emails until confirmed."
    else
        success "Email subscription confirmed"
    fi
}

# Wait for instance to be ready
wait_for_instance() {
    info "Waiting for EC2 instance to be ready..."
    
    # Wait for instance to reach running state
    info "Waiting for instance to start..."
    aws ec2 wait instance-running --instance-ids "${INSTANCE_ID}"
    
    # Wait for status checks to pass
    info "Waiting for system status checks..."
    aws ec2 wait instance-status-ok --instance-ids "${INSTANCE_ID}" --max-attempts 20 || {
        warning "Status checks didn't pass within expected time, but instance is running"
    }
    
    # Allow additional time for CloudWatch metrics to initialize
    info "Waiting for CloudWatch metrics to initialize (3 minutes)..."
    sleep 180
    
    success "Instance ready for monitoring"
}

# Create CloudWatch alarm
create_cloudwatch_alarm() {
    info "Creating CloudWatch CPU alarm..."
    
    aws cloudwatch put-metric-alarm \
        --alarm-name "${ALARM_NAME}" \
        --alarm-description "Alert when CPU exceeds 70% for ${INSTANCE_NAME}" \
        --metric-name CPUUtilization \
        --namespace AWS/EC2 \
        --statistic Average \
        --period 300 \
        --threshold 70 \
        --comparison-operator GreaterThanThreshold \
        --dimensions "Name=InstanceId,Value=${INSTANCE_ID}" \
        --evaluation-periods 2 \
        --alarm-actions "${TOPIC_ARN}" \
        --ok-actions "${TOPIC_ARN}" \
        --unit Percent \
        --tags "Key=Purpose,Value=Monitoring-Demo"
    
    if [[ $? -ne 0 ]]; then
        error_exit "Failed to create CloudWatch alarm"
    fi
    
    success "CloudWatch alarm created: ${ALARM_NAME}"
}

# Test the alarm (optional)
test_alarm() {
    info "Testing alarm with simulated CPU load..."
    
    # Try to use Systems Manager Run Command first
    if aws ssm describe-instance-information --instance-information-filter-list "key=InstanceIds,valueSet=${INSTANCE_ID}" --query 'InstanceInformationList[0].InstanceId' --output text 2>/dev/null | grep -q "${INSTANCE_ID}"; then
        info "Using Systems Manager to generate CPU load..."
        
        COMMAND_ID=$(aws ssm send-command \
            --document-name "AWS-RunShellScript" \
            --instance-ids "${INSTANCE_ID}" \
            --parameters 'commands=["stress-ng --cpu 4 --timeout 600s"]' \
            --comment "CPU stress test for monitoring demo" \
            --query 'Command.CommandId' --output text)
        
        if [[ $? -eq 0 && -n "${COMMAND_ID}" ]]; then
            echo "COMMAND_ID=${COMMAND_ID}" >> "${STATE_FILE}"
            success "CPU stress test initiated via SSM"
            info "Command ID: ${COMMAND_ID}"
            info "Monitor your email for alarm notifications in the next 10-15 minutes"
        else
            warning "SSM command failed, skipping automated test"
        fi
    else
        warning "Instance not available via SSM, skipping automated test"
        info "To manually test the alarm:"
        info "1. Connect to EC2 instance via SSH or Session Manager"
        info "2. Run: sudo stress-ng --cpu 4 --timeout 600s"
    fi
}

# Display deployment summary
display_summary() {
    echo ""
    echo "=========================================="
    echo "DEPLOYMENT SUMMARY"
    echo "=========================================="
    echo "EC2 Instance ID: ${INSTANCE_ID}"
    echo "SNS Topic ARN: ${TOPIC_ARN}"
    echo "CloudWatch Alarm: ${ALARM_NAME}"
    echo "Email Address: ${USER_EMAIL}"
    echo "AWS Region: ${AWS_REGION}"
    echo ""
    echo "Next Steps:"
    echo "1. Monitor your email for alarm notifications"
    echo "2. Check CloudWatch console for alarm status"
    echo "3. Use the destroy.sh script to clean up resources"
    echo ""
    echo "State file saved to: ${STATE_FILE}"
    echo "=========================================="
}

# Main execution flow
main() {
    log "${BLUE}Starting deployment of Simple Resource Monitoring with CloudWatch and SNS${NC}"
    log "Timestamp: ${TIMESTAMP}"
    log "Log file: ${LOG_FILE}"
    
    # Trap to handle interruptions
    trap 'echo ""; warning "Deployment interrupted. Check state file for created resources."; exit 1' INT TERM
    
    check_prerequisites
    get_user_email
    setup_environment
    launch_ec2_instance
    create_sns_topic
    subscribe_email_to_topic
    wait_for_instance
    create_cloudwatch_alarm
    
    # Ask if user wants to test the alarm
    echo ""
    read -p "Would you like to test the alarm by generating CPU load? (y/N): " -n 1 -r
    echo ""
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        test_alarm
    fi
    
    display_summary
    success "Deployment completed successfully!"
}

# Run main function
main "$@"