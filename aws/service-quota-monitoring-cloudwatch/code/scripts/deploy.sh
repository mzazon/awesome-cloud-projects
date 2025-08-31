#!/bin/bash

# Service Quota Monitoring with CloudWatch Alarms - Deployment Script
# This script deploys AWS service quota monitoring infrastructure with CloudWatch alarms and SNS notifications

set -e  # Exit on any error
set -u  # Exit on undefined variables

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

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_FILE="${SCRIPT_DIR}/.deployment_state"
REQUIRED_CLI_VERSION="2.0.0"

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed. Please install AWS CLI v2.0 or later."
        exit 1
    fi
    
    # Check AWS CLI version
    local cli_version=$(aws --version 2>&1 | cut -d/ -f2 | cut -d' ' -f1)
    if [[ "$(printf '%s\n' "$REQUIRED_CLI_VERSION" "$cli_version" | sort -V | head -n1)" != "$REQUIRED_CLI_VERSION" ]]; then
        log_error "AWS CLI version $cli_version is too old. Please upgrade to v$REQUIRED_CLI_VERSION or later."
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials not configured. Please run 'aws configure' or set AWS credentials."
        exit 1
    fi
    
    # Check required permissions by testing a simple call
    if ! aws service-quotas list-services --max-items 1 &> /dev/null; then
        log_error "Insufficient permissions. Please ensure you have permissions for Service Quotas, CloudWatch, and SNS."
        exit 1
    fi
    
    log_success "Prerequisites check completed"
}

# Function to set environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    # Get AWS region and account ID
    export AWS_REGION=$(aws configure get region)
    if [[ -z "$AWS_REGION" ]]; then
        log_error "AWS region not configured. Please set default region with 'aws configure'."
        exit 1
    fi
    
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique suffix for resources
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || echo "$(date +%s | tail -c 6)")
    
    # Prompt for notification email if not provided
    if [[ -z "${NOTIFICATION_EMAIL:-}" ]]; then
        echo -n "Enter notification email address: "
        read -r NOTIFICATION_EMAIL
        if [[ ! "$NOTIFICATION_EMAIL" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; then
            log_error "Invalid email address format."
            exit 1
        fi
    fi
    
    export NOTIFICATION_EMAIL
    
    log_success "Environment configured - Region: $AWS_REGION, Account: $AWS_ACCOUNT_ID"
    log_success "Notification email: $NOTIFICATION_EMAIL"
}

# Function to create SNS topic
create_sns_topic() {
    log "Creating SNS topic for quota notifications..."
    
    local topic_name="service-quota-alerts-${RANDOM_SUFFIX}"
    
    SNS_TOPIC_ARN=$(aws sns create-topic \
        --name "$topic_name" \
        --query TopicArn --output text)
    
    if [[ -z "$SNS_TOPIC_ARN" ]]; then
        log_error "Failed to create SNS topic"
        exit 1
    fi
    
    # Store topic ARN in state file
    echo "SNS_TOPIC_ARN=$SNS_TOPIC_ARN" >> "$STATE_FILE"
    
    log_success "SNS topic created: $SNS_TOPIC_ARN"
}

# Function to subscribe email to SNS topic
subscribe_email() {
    log "Subscribing email to SNS topic..."
    
    local subscription_arn=$(aws sns subscribe \
        --topic-arn "$SNS_TOPIC_ARN" \
        --protocol email \
        --notification-endpoint "$NOTIFICATION_EMAIL" \
        --query SubscriptionArn --output text)
    
    if [[ "$subscription_arn" == "pending confirmation" ]]; then
        log_warning "Email subscription pending confirmation. Please check $NOTIFICATION_EMAIL and confirm the subscription."
        echo "SUBSCRIPTION_PENDING=true" >> "$STATE_FILE"
    else
        log_success "Email subscription created: $subscription_arn"
        echo "SUBSCRIPTION_ARN=$subscription_arn" >> "$STATE_FILE"
    fi
}

# Function to create CloudWatch alarms
create_cloudwatch_alarms() {
    log "Creating CloudWatch alarms for service quotas..."
    
    local alarms_created=0
    
    # EC2 Running Instances Alarm
    log "Creating EC2 running instances quota alarm..."
    if aws cloudwatch put-metric-alarm \
        --alarm-name "EC2-Running-Instances-Quota-Alert" \
        --alarm-description "Alert when EC2 running instances exceed 80% of quota" \
        --metric-name ServiceQuotaUtilization \
        --namespace AWS/ServiceQuotas \
        --statistic Maximum \
        --period 300 \
        --threshold 80 \
        --comparison-operator GreaterThanThreshold \
        --evaluation-periods 1 \
        --alarm-actions "$SNS_TOPIC_ARN" \
        --dimensions Name=ServiceCode,Value=ec2 Name=QuotaCode,Value=L-1216C47A &> /dev/null; then
        log_success "EC2 instance quota alarm created"
        echo "EC2_ALARM_CREATED=true" >> "$STATE_FILE"
        ((alarms_created++))
    else
        log_error "Failed to create EC2 instance quota alarm"
    fi
    
    # VPC Quota Alarm
    log "Creating VPC quota alarm..."
    if aws cloudwatch put-metric-alarm \
        --alarm-name "VPC-Quota-Alert" \
        --alarm-description "Alert when VPC count exceeds 80% of quota" \
        --metric-name ServiceQuotaUtilization \
        --namespace AWS/ServiceQuotas \
        --statistic Maximum \
        --period 300 \
        --threshold 80 \
        --comparison-operator GreaterThanThreshold \
        --evaluation-periods 1 \
        --alarm-actions "$SNS_TOPIC_ARN" \
        --dimensions Name=ServiceCode,Value=vpc Name=QuotaCode,Value=L-F678F1CE &> /dev/null; then
        log_success "VPC quota alarm created"
        echo "VPC_ALARM_CREATED=true" >> "$STATE_FILE"
        ((alarms_created++))
    else
        log_error "Failed to create VPC quota alarm"
    fi
    
    # Lambda Concurrent Executions Alarm
    log "Creating Lambda concurrent executions quota alarm..."
    if aws cloudwatch put-metric-alarm \
        --alarm-name "Lambda-Concurrent-Executions-Quota-Alert" \
        --alarm-description "Alert when Lambda concurrent executions exceed 80% of quota" \
        --metric-name ServiceQuotaUtilization \
        --namespace AWS/ServiceQuotas \
        --statistic Maximum \
        --period 300 \
        --threshold 80 \
        --comparison-operator GreaterThanThreshold \
        --evaluation-periods 1 \
        --alarm-actions "$SNS_TOPIC_ARN" \
        --dimensions Name=ServiceCode,Value=lambda Name=QuotaCode,Value=L-B99A9384 &> /dev/null; then
        log_success "Lambda concurrent executions quota alarm created"
        echo "LAMBDA_ALARM_CREATED=true" >> "$STATE_FILE"
        ((alarms_created++))
    else
        log_error "Failed to create Lambda concurrent executions quota alarm"
    fi
    
    echo "ALARMS_CREATED=$alarms_created" >> "$STATE_FILE"
    log_success "Created $alarms_created CloudWatch alarms"
}

# Function to test alarm configuration
test_alarms() {
    log "Testing alarm configuration..."
    
    # Test EC2 alarm if it was created
    if grep -q "EC2_ALARM_CREATED=true" "$STATE_FILE"; then
        log "Testing EC2 instance quota alarm..."
        
        if aws cloudwatch set-alarm-state \
            --alarm-name "EC2-Running-Instances-Quota-Alert" \
            --state-value ALARM \
            --state-reason "Testing alarm notification system" &> /dev/null; then
            
            log_success "Test alarm triggered - check email for notification"
            sleep 5  # Wait a moment before resetting
            
            # Reset alarm state
            aws cloudwatch set-alarm-state \
                --alarm-name "EC2-Running-Instances-Quota-Alert" \
                --state-value OK \
                --state-reason "Test complete - resetting to normal state" &> /dev/null
            
            log_success "Alarm state reset to OK"
        else
            log_warning "Failed to test alarm - alarm may still function normally"
        fi
    fi
}

# Function to display deployment summary
display_summary() {
    log "Deployment Summary:"
    echo "===================="
    echo "SNS Topic ARN: $SNS_TOPIC_ARN"
    echo "Notification Email: $NOTIFICATION_EMAIL"
    echo "AWS Region: $AWS_REGION"
    echo "AWS Account: $AWS_ACCOUNT_ID"
    
    local alarms_count=$(grep "ALARMS_CREATED=" "$STATE_FILE" | cut -d= -f2)
    echo "CloudWatch Alarms Created: $alarms_count"
    
    if grep -q "SUBSCRIPTION_PENDING=true" "$STATE_FILE"; then
        echo ""
        log_warning "IMPORTANT: Email subscription is pending confirmation!"
        log_warning "Please check $NOTIFICATION_EMAIL and confirm the subscription to receive alerts."
    fi
    
    echo ""
    log_success "Service quota monitoring deployment completed successfully!"
    echo "State file saved to: $STATE_FILE"
}

# Function to handle cleanup on script failure
cleanup_on_failure() {
    log_error "Deployment failed. Cleaning up partial deployment..."
    
    if [[ -f "$STATE_FILE" ]]; then
        # Source the state file to get created resource ARNs
        source "$STATE_FILE"
        
        # Clean up SNS topic if created
        if [[ -n "${SNS_TOPIC_ARN:-}" ]]; then
            log "Deleting SNS topic..."
            aws sns delete-topic --topic-arn "$SNS_TOPIC_ARN" &> /dev/null || true
        fi
        
        # Clean up alarms if created
        local alarm_names=()
        grep -q "EC2_ALARM_CREATED=true" "$STATE_FILE" && alarm_names+=("EC2-Running-Instances-Quota-Alert")
        grep -q "VPC_ALARM_CREATED=true" "$STATE_FILE" && alarm_names+=("VPC-Quota-Alert")
        grep -q "LAMBDA_ALARM_CREATED=true" "$STATE_FILE" && alarm_names+=("Lambda-Concurrent-Executions-Quota-Alert")
        
        if [[ ${#alarm_names[@]} -gt 0 ]]; then
            log "Deleting CloudWatch alarms..."
            aws cloudwatch delete-alarms --alarm-names "${alarm_names[@]}" &> /dev/null || true
        fi
        
        # Remove state file
        rm -f "$STATE_FILE"
    fi
    
    log_error "Cleanup completed. Please try running the deployment script again."
    exit 1
}

# Main deployment function
main() {
    log "Starting Service Quota Monitoring deployment..."
    
    # Set up error handling
    trap cleanup_on_failure ERR
    
    # Initialize state file
    echo "# Deployment state for Service Quota Monitoring" > "$STATE_FILE"
    echo "DEPLOYMENT_DATE=$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$STATE_FILE"
    
    # Run deployment steps
    check_prerequisites
    setup_environment
    create_sns_topic
    subscribe_email
    create_cloudwatch_alarms
    test_alarms
    display_summary
    
    # Mark deployment as complete
    echo "DEPLOYMENT_COMPLETE=true" >> "$STATE_FILE"
}

# Show usage if help requested
if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    echo "Service Quota Monitoring Deployment Script"
    echo ""
    echo "Usage: $0 [EMAIL]"
    echo ""
    echo "Options:"
    echo "  EMAIL    Optional notification email address"
    echo "  -h, --help   Show this help message"
    echo ""
    echo "Environment Variables:"
    echo "  NOTIFICATION_EMAIL   Email address for notifications (alternative to argument)"
    echo ""
    echo "Examples:"
    echo "  $0 admin@example.com"
    echo "  NOTIFICATION_EMAIL=admin@example.com $0"
    exit 0
fi

# Set notification email from argument if provided
if [[ -n "${1:-}" ]]; then
    export NOTIFICATION_EMAIL="$1"
fi

# Check if already deployed
if [[ -f "$STATE_FILE" ]] && grep -q "DEPLOYMENT_COMPLETE=true" "$STATE_FILE"; then
    log_warning "Service quota monitoring appears to be already deployed."
    echo "State file found at: $STATE_FILE"
    echo ""
    echo "To redeploy, first run the destroy script: ./destroy.sh"
    echo "Or remove the state file manually: rm $STATE_FILE"
    exit 1
fi

# Run main deployment
main