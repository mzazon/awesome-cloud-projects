#!/bin/bash

# Deploy script for Centralized Alert Management with User Notifications and CloudWatch
# This script implements the complete solution described in the recipe

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to validate AWS CLI configuration
validate_aws_config() {
    log_info "Validating AWS CLI configuration..."
    
    if ! command_exists aws; then
        log_error "AWS CLI is not installed or not in PATH"
        exit 1
    fi
    
    # Check if AWS CLI is configured
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        log_error "AWS CLI is not configured or credentials are invalid"
        log_info "Please run 'aws configure' to set up your credentials"
        exit 1
    fi
    
    log_success "AWS CLI is properly configured"
}

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check AWS CLI version
    AWS_CLI_VERSION=$(aws --version 2>&1 | cut -d/ -f2 | cut -d' ' -f1)
    log_info "AWS CLI version: $AWS_CLI_VERSION"
    
    # Check if User Notifications is available in the region
    local region
    region=$(aws configure get region)
    if [[ -z "$region" ]]; then
        log_error "AWS region is not configured"
        exit 1
    fi
    
    log_info "Target AWS region: $region"
    
    # Verify permissions by attempting to list notification hubs
    if ! aws notifications list-notification-hubs >/dev/null 2>&1; then
        log_warning "Unable to access User Notifications service. This may be due to:"
        log_warning "1. Service not available in your region"
        log_warning "2. Insufficient permissions"
        log_warning "3. Service not yet activated"
        log_info "Continuing with deployment..."
    fi
    
    log_success "Prerequisites check completed"
}

# Function to set up environment variables
setup_environment() {
    log_info "Setting up environment variables..."
    
    # Set AWS environment variables
    export AWS_REGION=$(aws configure get region)
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers for resources
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || \
        echo "$(date +%s | tail -c 6)")
    
    # Set resource names
    export BUCKET_NAME="monitoring-demo-${RANDOM_SUFFIX}"
    export ALARM_NAME="s3-bucket-size-alarm"
    export NOTIFICATION_CONFIG_NAME="s3-monitoring-config"
    
    log_success "Environment configured:"
    log_info "  AWS Region: ${AWS_REGION}"
    log_info "  AWS Account ID: ${AWS_ACCOUNT_ID}"
    log_info "  Bucket Name: ${BUCKET_NAME}"
    log_info "  Alarm Name: ${ALARM_NAME}"
    log_info "  Notification Config: ${NOTIFICATION_CONFIG_NAME}"
    
    # Save environment variables to file for cleanup script
    cat > /tmp/aws-centralized-alerts-env.sh << EOF
export AWS_REGION="${AWS_REGION}"
export AWS_ACCOUNT_ID="${AWS_ACCOUNT_ID}"
export BUCKET_NAME="${BUCKET_NAME}"
export ALARM_NAME="${ALARM_NAME}"
export NOTIFICATION_CONFIG_NAME="${NOTIFICATION_CONFIG_NAME}"
EOF
    
    log_info "Environment variables saved to /tmp/aws-centralized-alerts-env.sh"
}

# Function to create S3 bucket with CloudWatch metrics
create_s3_bucket() {
    log_info "Creating S3 bucket with CloudWatch metrics..."
    
    # Check if bucket already exists
    if aws s3api head-bucket --bucket "${BUCKET_NAME}" 2>/dev/null; then
        log_warning "Bucket ${BUCKET_NAME} already exists, skipping creation"
        return 0
    fi
    
    # Create S3 bucket with versioning
    aws s3 mb s3://${BUCKET_NAME} --region ${AWS_REGION}
    
    # Enable versioning for better tracking
    aws s3api put-bucket-versioning \
        --bucket ${BUCKET_NAME} \
        --versioning-configuration Status=Enabled
    
    # Enable CloudWatch request metrics
    aws s3api put-bucket-metrics-configuration \
        --bucket ${BUCKET_NAME} \
        --id EntireBucket \
        --metrics-configuration Id=EntireBucket
    
    log_success "S3 bucket ${BUCKET_NAME} created with CloudWatch metrics enabled"
}

# Function to upload sample files
upload_sample_files() {
    log_info "Uploading sample files to generate metrics..."
    
    # Create temporary directory for sample files
    local temp_dir
    temp_dir=$(mktemp -d)
    cd "$temp_dir"
    
    # Create sample files with different sizes
    echo "Sample monitoring data - $(date)" > sample1.txt
    echo "Additional test content for metrics generation - $(date)" > sample2.txt
    
    # Create a larger file for size-based monitoring
    dd if=/dev/zero of=largefile.dat bs=1024 count=1024 2>/dev/null
    
    # Upload files to S3 bucket
    aws s3 cp sample1.txt s3://${BUCKET_NAME}/data/
    aws s3 cp sample2.txt s3://${BUCKET_NAME}/logs/
    aws s3 cp largefile.dat s3://${BUCKET_NAME}/archive/
    
    # Clean up local files
    cd - >/dev/null
    rm -rf "$temp_dir"
    
    log_success "Sample files uploaded to generate CloudWatch metrics"
}

# Function to create CloudWatch alarm
create_cloudwatch_alarm() {
    log_info "Creating CloudWatch alarm for bucket size monitoring..."
    
    # Check if alarm already exists
    if aws cloudwatch describe-alarms --alarm-names ${ALARM_NAME} --query "MetricAlarms[0].AlarmName" --output text 2>/dev/null | grep -q "${ALARM_NAME}"; then
        log_warning "CloudWatch alarm ${ALARM_NAME} already exists, skipping creation"
        return 0
    fi
    
    # Create CloudWatch alarm for bucket size monitoring
    aws cloudwatch put-metric-alarm \
        --alarm-name ${ALARM_NAME} \
        --alarm-description "Monitor S3 bucket size growth for centralized alerting demo" \
        --metric-name BucketSizeBytes \
        --namespace AWS/S3 \
        --statistic Average \
        --period 86400 \
        --threshold 5000000 \
        --comparison-operator GreaterThanThreshold \
        --evaluation-periods 1 \
        --treat-missing-data notBreaching \
        --dimensions Name=BucketName,Value=${BUCKET_NAME} \
                     Name=StorageType,Value=StandardStorage
    
    # Verify alarm creation
    local alarm_state
    alarm_state=$(aws cloudwatch describe-alarms \
        --alarm-names ${ALARM_NAME} \
        --query "MetricAlarms[0].StateValue" --output text)
    
    log_success "CloudWatch alarm ${ALARM_NAME} created with state: ${alarm_state}"
}

# Function to register notification hub
register_notification_hub() {
    log_info "Registering User Notifications hub..."
    
    # Check if notification hub is already registered
    if aws notifications list-notification-hubs --query "notificationHubs[0].notificationHubRegion" --output text 2>/dev/null | grep -q "${AWS_REGION}"; then
        log_warning "Notification hub already registered in region ${AWS_REGION}"
        return 0
    fi
    
    # Register notification hub for centralized management
    if aws notifications register-notification-hub \
        --notification-hub-region ${AWS_REGION} 2>/dev/null; then
        
        # Verify notification hub registration
        local hub_status
        hub_status=$(aws notifications list-notification-hubs \
            --query "notificationHubs[0].status" --output text 2>/dev/null)
        
        log_success "Notification hub registered in region: ${AWS_REGION} with status: ${hub_status}"
    else
        log_warning "Failed to register notification hub. This may be due to:"
        log_warning "1. Service not available in your region"
        log_warning "2. Hub already exists"
        log_warning "3. Insufficient permissions"
        log_info "Continuing with deployment..."
    fi
}

# Function to create email contact
create_email_contact() {
    log_info "Creating email contact for notifications..."
    
    # Check if we already have an email contact
    if aws notificationscontacts list-email-contacts --query "emailContacts[?name=='monitoring-alerts-contact'].name" --output text 2>/dev/null | grep -q "monitoring-alerts-contact"; then
        log_warning "Email contact 'monitoring-alerts-contact' already exists"
        return 0
    fi
    
    # Prompt for email address if not provided
    if [[ -z "${USER_EMAIL:-}" ]]; then
        echo -n "Enter your email address for notifications: "
        read -r USER_EMAIL
        export USER_EMAIL
        echo "export USER_EMAIL=\"${USER_EMAIL}\"" >> /tmp/aws-centralized-alerts-env.sh
    fi
    
    # Validate email format
    if [[ ! "$USER_EMAIL" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; then
        log_error "Invalid email format: $USER_EMAIL"
        exit 1
    fi
    
    # Create email contact using User Notifications Contacts service
    if aws notificationscontacts create-email-contact \
        --name "monitoring-alerts-contact" \
        --email-address "${USER_EMAIL}" 2>/dev/null; then
        
        # Get the email contact ARN
        EMAIL_CONTACT_ARN=$(aws notificationscontacts list-email-contacts \
            --query "emailContacts[?name=='monitoring-alerts-contact'].arn" \
            --output text)
        
        echo "export EMAIL_CONTACT_ARN=\"${EMAIL_CONTACT_ARN}\"" >> /tmp/aws-centralized-alerts-env.sh
        
        log_success "Email contact created: ${EMAIL_CONTACT_ARN}"
        log_warning "📧 Check your email for activation instructions before proceeding"
        
        # Wait for user confirmation of email activation
        echo -n "Press Enter after you have activated the email contact (check your email)..."
        read -r
    else
        log_warning "Failed to create email contact. This may be due to:"
        log_warning "1. Service not available in your region"
        log_warning "2. Contact already exists"
        log_warning "3. Insufficient permissions"
        log_info "Continuing with deployment..."
    fi
}

# Function to create notification configuration
create_notification_configuration() {
    log_info "Creating notification configuration..."
    
    # Source environment variables to get EMAIL_CONTACT_ARN
    if [[ -f /tmp/aws-centralized-alerts-env.sh ]]; then
        source /tmp/aws-centralized-alerts-env.sh
    fi
    
    # Check if event rule already exists
    if aws notifications list-event-rules --query "eventRules[?name=='${NOTIFICATION_CONFIG_NAME}-event-rule'].name" --output text 2>/dev/null | grep -q "${NOTIFICATION_CONFIG_NAME}-event-rule"; then
        log_warning "Event rule already exists, skipping creation"
    else
        # Create event rule for CloudWatch alarm state changes
        aws notifications create-event-rule \
            --name "${NOTIFICATION_CONFIG_NAME}-event-rule" \
            --description "Filter CloudWatch alarm state changes for S3 monitoring" \
            --event-pattern "{
              \"source\": [\"aws.cloudwatch\"],
              \"detail-type\": [\"CloudWatch Alarm State Change\"],
              \"detail\": {
                \"alarmName\": [\"${ALARM_NAME}\"],
                \"state\": {
                  \"value\": [\"ALARM\", \"OK\"]
                }
              }
            }" 2>/dev/null || log_warning "Failed to create event rule"
    fi
    
    # Check if notification configuration already exists
    if aws notifications list-notification-configurations --query "notificationConfigurations[?name=='${NOTIFICATION_CONFIG_NAME}'].name" --output text 2>/dev/null | grep -q "${NOTIFICATION_CONFIG_NAME}"; then
        log_warning "Notification configuration already exists, skipping creation"
        
        # Get existing notification configuration ARN
        NOTIFICATION_CONFIG_ARN=$(aws notifications list-notification-configurations \
            --query "notificationConfigurations[?name=='${NOTIFICATION_CONFIG_NAME}'].arn" \
            --output text)
    else
        # Create notification configuration
        aws notifications create-notification-configuration \
            --name "${NOTIFICATION_CONFIG_NAME}" \
            --description "S3 monitoring notification configuration" \
            --aggregation-duration "PT5M" 2>/dev/null || log_warning "Failed to create notification configuration"
        
        # Get notification configuration ARN
        NOTIFICATION_CONFIG_ARN=$(aws notifications list-notification-configurations \
            --query "notificationConfigurations[?name=='${NOTIFICATION_CONFIG_NAME}'].arn" \
            --output text 2>/dev/null)
    fi
    
    # Associate email contact with notification configuration if we have both ARNs
    if [[ -n "${EMAIL_CONTACT_ARN:-}" ]] && [[ -n "${NOTIFICATION_CONFIG_ARN:-}" ]]; then
        aws notifications associate-channel \
            --arn "${EMAIL_CONTACT_ARN}" \
            --notification-configuration-arn "${NOTIFICATION_CONFIG_ARN}" 2>/dev/null || \
            log_warning "Failed to associate email contact with notification configuration"
        
        log_success "Notification configuration created and associated with email contact"
    else
        log_warning "Unable to associate email contact - missing ARNs"
    fi
    
    # Save notification config ARN to environment file
    if [[ -n "${NOTIFICATION_CONFIG_ARN:-}" ]]; then
        echo "export NOTIFICATION_CONFIG_ARN=\"${NOTIFICATION_CONFIG_ARN}\"" >> /tmp/aws-centralized-alerts-env.sh
    fi
}

# Function to test notification system
test_notification_system() {
    log_info "Testing notification system..."
    
    # Manually trigger alarm state change for testing
    aws cloudwatch set-alarm-state \
        --alarm-name ${ALARM_NAME} \
        --state-value ALARM \
        --state-reason "Automated deployment test of notification system"
    
    log_success "Alarm state set to ALARM for testing purposes"
    log_info "Check your email and AWS Console Notifications Center for alerts"
    
    # Wait and reset alarm state
    log_info "Waiting 30 seconds before resetting alarm state..."
    sleep 30
    
    aws cloudwatch set-alarm-state \
        --alarm-name ${ALARM_NAME} \
        --state-value OK \
        --state-reason "Automated test completed - resetting to OK state"
    
    log_success "Alarm state reset to OK - test completed"
}

# Function to display deployment summary
display_summary() {
    log_success "Deployment completed successfully!"
    echo
    log_info "=== Deployment Summary ==="
    log_info "S3 Bucket: ${BUCKET_NAME}"
    log_info "CloudWatch Alarm: ${ALARM_NAME}"
    log_info "AWS Region: ${AWS_REGION}"
    log_info "Notification Config: ${NOTIFICATION_CONFIG_NAME}"
    
    if [[ -n "${USER_EMAIL:-}" ]]; then
        log_info "Email Contact: ${USER_EMAIL}"
    fi
    
    echo
    log_info "=== Next Steps ==="
    log_info "1. Check the AWS User Notifications console for centralized alert management"
    log_info "2. Monitor your email for test notifications"
    log_info "3. Verify CloudWatch alarms in the CloudWatch console"
    log_info "4. Upload additional files to S3 to test real metrics-based alerting"
    
    echo
    log_info "=== Cleanup ==="
    log_info "To remove all resources, run: ./destroy.sh"
    log_info "Environment variables saved to: /tmp/aws-centralized-alerts-env.sh"
    
    echo
    log_info "=== Costs ==="
    log_info "Estimated monthly cost: $0.10-$0.50 (CloudWatch alarms and S3 storage)"
    log_info "Most services used are within AWS Free Tier limits"
}

# Main deployment function
main() {
    log_info "Starting deployment of Centralized Alert Management with User Notifications and CloudWatch"
    echo
    
    # Check prerequisites
    validate_aws_config
    check_prerequisites
    
    # Setup environment
    setup_environment
    
    # Deploy resources
    create_s3_bucket
    upload_sample_files
    create_cloudwatch_alarm
    register_notification_hub
    create_email_contact
    create_notification_configuration
    test_notification_system
    
    # Display summary
    display_summary
}

# Handle script interruption
cleanup_on_exit() {
    log_warning "Script interrupted. Some resources may have been created."
    log_info "Use ./destroy.sh to clean up any created resources."
    exit 1
}

trap cleanup_on_exit INT TERM

# Check if script is being sourced or executed
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi