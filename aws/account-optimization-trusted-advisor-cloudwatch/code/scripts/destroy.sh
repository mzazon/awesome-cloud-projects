#!/bin/bash

# Destroy Script for Account Optimization Monitoring with Trusted Advisor and CloudWatch
# This script removes all resources created by the deploy.sh script including SNS topics,
# CloudWatch alarms, and email subscriptions.

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Color codes for output formatting
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Logging functions
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

# Function to load deployment configuration
load_config() {
    if [[ ! -f ".deployment_config" ]]; then
        error "Deployment configuration file not found."
        error "Please ensure you're running this script from the same directory where deploy.sh was executed."
        exit 1
    fi
    
    log "Loading deployment configuration..."
    source .deployment_config
    
    # Verify required variables are set
    local required_vars=(
        "SNS_TOPIC_NAME"
        "CLOUDWATCH_ALARM_NAME"
        "SECURITY_ALARM_NAME"
        "LIMITS_ALARM_NAME"
        "AWS_REGION"
        "AWS_ACCOUNT_ID"
        "EMAIL_ADDRESS"
    )
    
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            error "Required variable $var not found in configuration file."
            exit 1
        fi
    done
    
    # Set SNS_TOPIC_ARN if not in config
    if [[ -z "${SNS_TOPIC_ARN:-}" ]]; then
        export SNS_TOPIC_ARN="arn:aws:sns:${AWS_REGION}:${AWS_ACCOUNT_ID}:${SNS_TOPIC_NAME}"
    fi
    
    success "Configuration loaded successfully."
    log "Deployment Date: ${DEPLOYMENT_DATE:-Unknown}"
    log "AWS Region: ${AWS_REGION}"
    log "SNS Topic: ${SNS_TOPIC_NAME}"
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install AWS CLI v2."
        exit 1
    fi
    
    # Check if AWS credentials are configured
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials are not configured. Please run 'aws configure'."
        exit 1
    fi
    
    success "Prerequisites check completed."
}

# Function to confirm destruction
confirm_destruction() {
    echo ""
    warning "This will permanently delete the following resources:"
    echo "  • SNS Topic: ${SNS_TOPIC_NAME}"
    echo "  • Cost Optimization Alarm: ${CLOUDWATCH_ALARM_NAME}"
    echo "  • Security Monitoring Alarm: ${SECURITY_ALARM_NAME}"
    echo "  • Service Limits Alarm: ${LIMITS_ALARM_NAME}"
    echo "  • Email Subscription: ${EMAIL_ADDRESS}"
    echo ""
    warning "This action CANNOT be undone!"
    echo ""
    echo -n "Are you sure you want to proceed? Type 'yes' to continue: "
    read -r confirmation
    
    if [[ "$confirmation" != "yes" ]]; then
        log "Destruction cancelled by user."
        exit 0
    fi
    
    echo ""
    log "Starting resource cleanup..."
}

# Function to delete CloudWatch alarms
delete_cloudwatch_alarms() {
    log "Deleting CloudWatch alarms..."
    
    local alarms_to_delete=(
        "${CLOUDWATCH_ALARM_NAME}"
        "${SECURITY_ALARM_NAME}"
        "${LIMITS_ALARM_NAME}"
    )
    
    # Check which alarms exist before attempting deletion
    local existing_alarms=()
    for alarm in "${alarms_to_delete[@]}"; do
        if aws cloudwatch describe-alarms \
            --alarm-names "$alarm" \
            --region "${AWS_REGION}" \
            --query 'MetricAlarms[0].AlarmName' \
            --output text 2>/dev/null | grep -q "$alarm"; then
            existing_alarms+=("$alarm")
        else
            warning "Alarm $alarm not found (may have been already deleted)."
        fi
    done
    
    if [[ ${#existing_alarms[@]} -gt 0 ]]; then
        # Delete existing alarms in batch
        aws cloudwatch delete-alarms \
            --alarm-names "${existing_alarms[@]}" \
            --region "${AWS_REGION}"
        
        success "Deleted ${#existing_alarms[@]} CloudWatch alarm(s):"
        for alarm in "${existing_alarms[@]}"; do
            echo "  ✅ $alarm"
        done
    else
        warning "No CloudWatch alarms found to delete."
    fi
}

# Function to delete SNS subscriptions and topic
delete_sns_resources() {
    log "Deleting SNS subscriptions and topic..."
    
    # Check if topic exists
    if ! aws sns get-topic-attributes \
        --topic-arn "${SNS_TOPIC_ARN}" \
        --region "${AWS_REGION}" \
        --query 'Attributes.TopicArn' \
        --output text &>/dev/null; then
        warning "SNS topic ${SNS_TOPIC_NAME} not found (may have been already deleted)."
        return
    fi
    
    # Get all subscriptions for the topic
    log "Retrieving topic subscriptions..."
    local subscription_arns
    subscription_arns=$(aws sns list-subscriptions-by-topic \
        --topic-arn "${SNS_TOPIC_ARN}" \
        --region "${AWS_REGION}" \
        --query 'Subscriptions[*].SubscriptionArn' \
        --output text 2>/dev/null || echo "")
    
    # Delete subscriptions
    if [[ -n "$subscription_arns" ]]; then
        log "Unsubscribing email addresses..."
        for arn in $subscription_arns; do
            if [[ "$arn" != "PendingConfirmation" && "$arn" != "None" ]]; then
                aws sns unsubscribe \
                    --subscription-arn "$arn" \
                    --region "${AWS_REGION}" 2>/dev/null || \
                    warning "Failed to unsubscribe $arn (may have been already removed)."
                success "Unsubscribed: $arn"
            fi
        done
    else
        warning "No active subscriptions found for topic."
    fi
    
    # Delete SNS topic
    log "Deleting SNS topic..."
    aws sns delete-topic \
        --topic-arn "${SNS_TOPIC_ARN}" \
        --region "${AWS_REGION}"
    
    success "SNS topic deleted: ${SNS_TOPIC_NAME}"
}

# Function to verify cleanup
verify_cleanup() {
    log "Verifying resource cleanup..."
    
    # Check if CloudWatch alarms were deleted
    local remaining_alarms
    remaining_alarms=$(aws cloudwatch describe-alarms \
        --alarm-names "${CLOUDWATCH_ALARM_NAME}" "${SECURITY_ALARM_NAME}" "${LIMITS_ALARM_NAME}" \
        --region "${AWS_REGION}" \
        --query 'length(MetricAlarms)' \
        --output text 2>/dev/null || echo "0")
    
    if [[ "$remaining_alarms" -eq "0" ]]; then
        success "All CloudWatch alarms successfully deleted."
    else
        warning "$remaining_alarms alarm(s) may still exist. Please check AWS Console."
    fi
    
    # Check if SNS topic was deleted
    if aws sns get-topic-attributes \
        --topic-arn "${SNS_TOPIC_ARN}" \
        --region "${AWS_REGION}" \
        --query 'Attributes.TopicArn' \
        --output text &>/dev/null; then
        warning "SNS topic may still exist. Please check AWS Console."
    else
        success "SNS topic successfully deleted."
    fi
    
    success "Resource cleanup verification completed."
}

# Function to clean up local files
cleanup_local_files() {
    log "Cleaning up local configuration files..."
    
    if [[ -f ".deployment_config" ]]; then
        # Create backup before deletion
        local backup_file=".deployment_config.backup.$(date +%Y%m%d_%H%M%S)"
        cp .deployment_config "$backup_file"
        log "Configuration backed up to: $backup_file"
        
        # Remove original config file
        rm .deployment_config
        success "Deployment configuration file removed."
    fi
    
    # Clean up any temporary files that might have been created
    if [[ -f "trusted-advisor-deployment.log" ]]; then
        rm trusted-advisor-deployment.log
        log "Removed deployment log file."
    fi
}

# Function to display cleanup summary
display_cleanup_summary() {
    echo ""
    echo "==============================="
    success "CLEANUP COMPLETED SUCCESSFULLY"
    echo "==============================="
    echo ""
    echo "Resources Removed:"
    echo "  ✅ SNS Topic: ${SNS_TOPIC_NAME}"
    echo "  ✅ Cost Optimization Alarm: ${CLOUDWATCH_ALARM_NAME}"
    echo "  ✅ Security Monitoring Alarm: ${SECURITY_ALARM_NAME}"
    echo "  ✅ Service Limits Alarm: ${LIMITS_ALARM_NAME}"
    echo "  ✅ Email Subscription: ${EMAIL_ADDRESS}"
    echo "  ✅ Local configuration files"
    echo ""
    success "All AWS Account Optimization Monitoring resources have been removed."
    echo ""
    warning "Note: You may continue to receive emails for a few minutes after cleanup."
    echo "This is normal as SNS processes the subscription deletions."
    echo ""
    echo "To redeploy the monitoring system, run './deploy.sh' again."
    echo ""
}

# Function to handle errors during cleanup
handle_cleanup_error() {
    local exit_code=$?
    echo ""
    error "Cleanup encountered an error (exit code: $exit_code)"
    echo ""
    warning "Some resources may not have been deleted. Please check the AWS Console:"
    echo "  • CloudWatch Alarms: https://console.aws.amazon.com/cloudwatch/home?region=${AWS_REGION}#alarmsV2:"
    echo "  • SNS Topics: https://console.aws.amazon.com/sns/v3/home?region=${AWS_REGION}#/topics"
    echo ""
    echo "You can manually delete any remaining resources if needed."
    exit $exit_code
}

# Main execution
main() {
    echo "============================================"
    echo "AWS Account Optimization Monitoring Cleanup"
    echo "============================================"
    echo ""
    
    load_config
    check_prerequisites
    confirm_destruction
    delete_cloudwatch_alarms
    delete_sns_resources
    verify_cleanup
    cleanup_local_files
    display_cleanup_summary
}

# Trap to handle script interruption and errors
trap 'handle_cleanup_error' ERR
trap 'error "Script interrupted. Some resources may not have been deleted. Please check AWS Console."; exit 1' INT TERM

# Run main function
main "$@"