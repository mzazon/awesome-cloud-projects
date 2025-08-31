#!/bin/bash

# Deploy Script for Account Optimization Monitoring with Trusted Advisor and CloudWatch
# This script creates SNS topics, CloudWatch alarms, and email subscriptions for monitoring
# AWS Trusted Advisor recommendations in real-time.

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Color codes for output formatting
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install AWS CLI v2."
        exit 1
    fi
    
    # Check AWS CLI version
    AWS_CLI_VERSION=$(aws --version 2>&1 | cut -d/ -f2 | cut -d' ' -f1)
    log "AWS CLI version: ${AWS_CLI_VERSION}"
    
    # Check if AWS credentials are configured
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials are not configured. Please run 'aws configure'."
        exit 1
    fi
    
    # Check if we're in the US East (N. Virginia) region (required for Trusted Advisor)
    if [[ "${AWS_REGION:-$(aws configure get region)}" != "us-east-1" ]]; then
        warning "Trusted Advisor metrics are only available in us-east-1 region."
        log "Setting AWS_REGION to us-east-1..."
        export AWS_REGION=us-east-1
    fi
    
    # Check AWS Support plan
    log "Checking AWS Support plan (Business/Enterprise required for full Trusted Advisor access)..."
    SUPPORT_PLAN=$(aws support describe-severity-levels --region us-east-1 2>/dev/null | jq -r '.severityLevels | length' || echo "0")
    if [[ "${SUPPORT_PLAN}" -lt "4" ]]; then
        warning "Basic or Developer Support plan detected. Some Trusted Advisor checks may not be available."
        warning "Business, Enterprise On-Ramp, or Enterprise Support plan recommended for full functionality."
    else
        success "Enterprise Support plan detected - full Trusted Advisor access available."
    fi
    
    success "Prerequisites check completed."
}

# Function to validate email address format
validate_email() {
    local email=$1
    if [[ ! "$email" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Z|a-z]{2,}$ ]]; then
        error "Invalid email address format: $email"
        return 1
    fi
    return 0
}

# Function to prompt for email address
get_email_address() {
    while true; do
        echo -n "Enter your email address for notifications: "
        read -r EMAIL_ADDRESS
        
        if validate_email "$EMAIL_ADDRESS"; then
            break
        else
            error "Please enter a valid email address."
        fi
    done
    
    echo -n "Confirm email address ($EMAIL_ADDRESS) [y/N]: "
    read -r confirmation
    if [[ ! "$confirmation" =~ ^[Yy]$ ]]; then
        error "Email confirmation cancelled. Exiting."
        exit 1
    fi
}

# Function to set environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    # Set required AWS region for Trusted Advisor
    export AWS_REGION=us-east-1
    
    # Get AWS Account ID
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    log "AWS Account ID: ${AWS_ACCOUNT_ID}"
    
    # Generate unique identifier for resources
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || \
        echo "$(date +%s | tail -c 6)")
    
    # Set resource names
    export SNS_TOPIC_NAME="trusted-advisor-alerts-${RANDOM_SUFFIX}"
    export CLOUDWATCH_ALARM_NAME="trusted-advisor-cost-optimization-${RANDOM_SUFFIX}"
    export SECURITY_ALARM_NAME="trusted-advisor-security-${RANDOM_SUFFIX}"
    export LIMITS_ALARM_NAME="trusted-advisor-limits-${RANDOM_SUFFIX}"
    
    # Store configuration for cleanup script
    cat > .deployment_config << EOF
SNS_TOPIC_NAME=${SNS_TOPIC_NAME}
CLOUDWATCH_ALARM_NAME=${CLOUDWATCH_ALARM_NAME}
SECURITY_ALARM_NAME=${SECURITY_ALARM_NAME}
LIMITS_ALARM_NAME=${LIMITS_ALARM_NAME}
AWS_REGION=${AWS_REGION}
AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID}
EMAIL_ADDRESS=${EMAIL_ADDRESS}
DEPLOYMENT_DATE=$(date -u +"%Y-%m-%d %H:%M:%S UTC")
EOF
    
    success "Environment configured for region: ${AWS_REGION}"
    log "Topic Name: ${SNS_TOPIC_NAME}"
    log "Cost Alarm Name: ${CLOUDWATCH_ALARM_NAME}"
    log "Security Alarm Name: ${SECURITY_ALARM_NAME}"
    log "Limits Alarm Name: ${LIMITS_ALARM_NAME}"
}

# Function to create SNS topic
create_sns_topic() {
    log "Creating SNS topic for Trusted Advisor notifications..."
    
    # Create SNS topic
    aws sns create-topic \
        --name "${SNS_TOPIC_NAME}" \
        --attributes DisplayName="AWS Account Optimization Alerts" \
        --region "${AWS_REGION}"
    
    # Get the topic ARN
    export SNS_TOPIC_ARN=$(aws sns get-topic-attributes \
        --topic-arn "arn:aws:sns:${AWS_REGION}:${AWS_ACCOUNT_ID}:${SNS_TOPIC_NAME}" \
        --query Attributes.TopicArn --output text \
        --region "${AWS_REGION}")
    
    # Add topic ARN to config file
    echo "SNS_TOPIC_ARN=${SNS_TOPIC_ARN}" >> .deployment_config
    
    success "SNS topic created: ${SNS_TOPIC_ARN}"
}

# Function to subscribe email to SNS topic
subscribe_email() {
    log "Subscribing email address to SNS topic..."
    
    # Subscribe email to SNS topic
    SUBSCRIPTION_ARN=$(aws sns subscribe \
        --topic-arn "${SNS_TOPIC_ARN}" \
        --protocol email \
        --notification-endpoint "${EMAIL_ADDRESS}" \
        --region "${AWS_REGION}" \
        --query SubscriptionArn --output text)
    
    echo "SUBSCRIPTION_ARN=${SUBSCRIPTION_ARN}" >> .deployment_config
    
    success "Email subscription created for: ${EMAIL_ADDRESS}"
    warning "Please check your email inbox and confirm the subscription before notifications will be delivered."
}

# Function to create CloudWatch alarms
create_cloudwatch_alarms() {
    log "Creating CloudWatch alarms for Trusted Advisor monitoring..."
    
    # Create cost optimization alarm
    log "Creating cost optimization alarm..."
    aws cloudwatch put-metric-alarm \
        --alarm-name "${CLOUDWATCH_ALARM_NAME}" \
        --alarm-description "Alert when Trusted Advisor identifies cost optimization opportunities" \
        --metric-name YellowResources \
        --namespace AWS/TrustedAdvisor \
        --statistic Average \
        --period 300 \
        --threshold 1 \
        --comparison-operator GreaterThanOrEqualToThreshold \
        --evaluation-periods 1 \
        --alarm-actions "${SNS_TOPIC_ARN}" \
        --dimensions Name=CheckName,Value="Low Utilization Amazon EC2 Instances" \
        --region "${AWS_REGION}"
    
    success "Cost optimization alarm created: ${CLOUDWATCH_ALARM_NAME}"
    
    # Create security monitoring alarm
    log "Creating security monitoring alarm..."
    aws cloudwatch put-metric-alarm \
        --alarm-name "${SECURITY_ALARM_NAME}" \
        --alarm-description "Alert when Trusted Advisor identifies security recommendations" \
        --metric-name RedResources \
        --namespace AWS/TrustedAdvisor \
        --statistic Average \
        --period 300 \
        --threshold 1 \
        --comparison-operator GreaterThanOrEqualToThreshold \
        --evaluation-periods 1 \
        --alarm-actions "${SNS_TOPIC_ARN}" \
        --dimensions Name=CheckName,Value="Security Groups - Specific Ports Unrestricted" \
        --region "${AWS_REGION}"
    
    success "Security monitoring alarm created: ${SECURITY_ALARM_NAME}"
    
    # Create service limits monitoring alarm
    log "Creating service limits monitoring alarm..."
    aws cloudwatch put-metric-alarm \
        --alarm-name "${LIMITS_ALARM_NAME}" \
        --alarm-description "Alert when service usage approaches limits" \
        --metric-name ServiceLimitUsage \
        --namespace AWS/TrustedAdvisor \
        --statistic Average \
        --period 300 \
        --threshold 80 \
        --comparison-operator GreaterThanThreshold \
        --evaluation-periods 1 \
        --alarm-actions "${SNS_TOPIC_ARN}" \
        --dimensions Name=ServiceName,Value=EC2 Name=ServiceLimit,Value="Running On-Demand EC2 Instances" Name=Region,Value="${AWS_REGION}" \
        --region "${AWS_REGION}"
    
    success "Service limits monitoring alarm created: ${LIMITS_ALARM_NAME}"
}

# Function to verify deployment
verify_deployment() {
    log "Verifying deployment..."
    
    # Check SNS topic attributes
    log "Checking SNS topic configuration..."
    aws sns get-topic-attributes \
        --topic-arn "${SNS_TOPIC_ARN}" \
        --region "${AWS_REGION}" \
        --query 'Attributes.[DisplayName,SubscriptionsConfirmed,SubscriptionsPending]' \
        --output table
    
    # Check alarm states
    log "Checking CloudWatch alarm states..."
    aws cloudwatch describe-alarms \
        --alarm-names "${CLOUDWATCH_ALARM_NAME}" "${SECURITY_ALARM_NAME}" "${LIMITS_ALARM_NAME}" \
        --region "${AWS_REGION}" \
        --query 'MetricAlarms[*].[AlarmName,StateValue,StateReason]' \
        --output table
    
    # Send test notification
    log "Sending test notification..."
    aws sns publish \
        --topic-arn "${SNS_TOPIC_ARN}" \
        --message "Test notification: AWS Account Optimization Monitoring is now active and monitoring your account for optimization opportunities." \
        --subject "AWS Trusted Advisor - Monitoring Active" \
        --region "${AWS_REGION}" \
        --query MessageId --output text > /dev/null
    
    success "Test notification sent. Check your email inbox."
    
    # Check for Trusted Advisor metrics
    log "Checking Trusted Advisor metrics availability..."
    METRICS_AVAILABLE=$(aws cloudwatch list-metrics \
        --namespace AWS/TrustedAdvisor \
        --metric-name YellowResources \
        --region "${AWS_REGION}" \
        --query 'length(Metrics)' --output text)
    
    if [[ "${METRICS_AVAILABLE}" -gt "0" ]]; then
        success "Trusted Advisor metrics are available in CloudWatch."
    else
        warning "Trusted Advisor metrics may take a few hours to appear in CloudWatch."
    fi
}

# Function to display summary
display_summary() {
    echo ""
    echo "=================================="
    success "DEPLOYMENT COMPLETED SUCCESSFULLY"
    echo "=================================="
    echo ""
    echo "Resources Created:"
    echo "  • SNS Topic: ${SNS_TOPIC_NAME}"
    echo "  • Cost Optimization Alarm: ${CLOUDWATCH_ALARM_NAME}"
    echo "  • Security Monitoring Alarm: ${SECURITY_ALARM_NAME}"
    echo "  • Service Limits Alarm: ${LIMITS_ALARM_NAME}"
    echo "  • Email Subscription: ${EMAIL_ADDRESS}"
    echo ""
    echo "Configuration saved to: .deployment_config"
    echo ""
    warning "IMPORTANT: Please confirm your email subscription to receive notifications!"
    echo ""
    echo "What's Next:"
    echo "  1. Check your email and confirm the SNS subscription"
    echo "  2. Monitor CloudWatch alarms in the AWS Console"
    echo "  3. Review Trusted Advisor recommendations when alerts are received"
    echo "  4. Use './destroy.sh' to clean up resources when no longer needed"
    echo ""
    echo "Estimated monthly cost: \$0.50-\$2.00 (based on alert frequency)"
    echo ""
}

# Main execution
main() {
    echo "=========================================="
    echo "AWS Account Optimization Monitoring Setup"
    echo "=========================================="
    echo ""
    
    check_prerequisites
    get_email_address
    setup_environment
    create_sns_topic
    subscribe_email
    create_cloudwatch_alarms
    verify_deployment
    display_summary
}

# Trap to handle script interruption
trap 'error "Script interrupted. Partial deployment may have occurred. Check AWS Console for created resources."; exit 1' INT TERM

# Run main function
main "$@"