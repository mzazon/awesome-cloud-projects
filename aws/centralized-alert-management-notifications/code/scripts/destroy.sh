#!/bin/bash

# Destroy script for Centralized Alert Management with User Notifications and CloudWatch
# This script removes all resources created by the deployment script

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

# Function to load environment variables
load_environment() {
    log_info "Loading environment variables..."
    
    # Try to load from saved environment file
    if [[ -f /tmp/aws-centralized-alerts-env.sh ]]; then
        source /tmp/aws-centralized-alerts-env.sh
        log_success "Environment variables loaded from /tmp/aws-centralized-alerts-env.sh"
    else
        log_warning "Environment file not found. Using default values or prompting for input."
        
        # Set default values or prompt for required ones
        export AWS_REGION=$(aws configure get region)
        export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
        
        # Prompt for resource names if not available
        if [[ -z "${BUCKET_NAME:-}" ]]; then
            echo -n "Enter S3 bucket name to delete (or press Enter to skip): "
            read -r BUCKET_NAME
            export BUCKET_NAME
        fi
        
        if [[ -z "${ALARM_NAME:-}" ]]; then
            export ALARM_NAME="s3-bucket-size-alarm"
        fi
        
        if [[ -z "${NOTIFICATION_CONFIG_NAME:-}" ]]; then
            export NOTIFICATION_CONFIG_NAME="s3-monitoring-config"
        fi
    fi
    
    log_info "Environment configuration:"
    log_info "  AWS Region: ${AWS_REGION}"
    log_info "  AWS Account ID: ${AWS_ACCOUNT_ID}"
    log_info "  Bucket Name: ${BUCKET_NAME:-'Not specified'}"
    log_info "  Alarm Name: ${ALARM_NAME}"
    log_info "  Notification Config: ${NOTIFICATION_CONFIG_NAME}"
}

# Function to confirm destructive action
confirm_destruction() {
    echo
    log_warning "⚠️  DESTRUCTIVE ACTION WARNING ⚠️"
    log_warning "This script will permanently delete the following resources:"
    
    if [[ -n "${BUCKET_NAME:-}" ]]; then
        log_warning "  • S3 Bucket: ${BUCKET_NAME} (and ALL its contents)"
    fi
    log_warning "  • CloudWatch Alarm: ${ALARM_NAME}"
    log_warning "  • User Notifications configuration: ${NOTIFICATION_CONFIG_NAME}"
    log_warning "  • Email contacts for notifications"
    log_warning "  • Notification hub registration"
    
    echo
    log_warning "This action cannot be undone!"
    echo
    
    # Require explicit confirmation
    echo -n "Are you sure you want to proceed? Type 'yes' to continue: "
    read -r confirmation
    
    if [[ "$confirmation" != "yes" ]]; then
        log_info "Destruction cancelled by user"
        exit 0
    fi
    
    echo
    log_info "Proceeding with resource destruction..."
}

# Function to remove notification configurations and associations
remove_notification_configurations() {
    log_info "Removing notification configurations and associations..."
    
    # Get notification configuration ARN if not already set
    if [[ -z "${NOTIFICATION_CONFIG_ARN:-}" ]]; then
        NOTIFICATION_CONFIG_ARN=$(aws notifications list-notification-configurations \
            --query "notificationConfigurations[?name=='${NOTIFICATION_CONFIG_NAME}'].arn" \
            --output text 2>/dev/null || echo "")
    fi
    
    # Get email contact ARN if not already set
    if [[ -z "${EMAIL_CONTACT_ARN:-}" ]]; then
        EMAIL_CONTACT_ARN=$(aws notificationscontacts list-email-contacts \
            --query "emailContacts[?name=='monitoring-alerts-contact'].arn" \
            --output text 2>/dev/null || echo "")
    fi
    
    # Disassociate email contact from notification configuration
    if [[ -n "${EMAIL_CONTACT_ARN}" ]] && [[ -n "${NOTIFICATION_CONFIG_ARN}" ]]; then
        if aws notifications disassociate-channel \
            --arn "${EMAIL_CONTACT_ARN}" \
            --notification-configuration-arn "${NOTIFICATION_CONFIG_ARN}" 2>/dev/null; then
            log_success "Email contact disassociated from notification configuration"
        else
            log_warning "Failed to disassociate email contact (may not exist or already disassociated)"
        fi
    else
        log_warning "Skipping disassociation - missing ARNs"
    fi
    
    # Delete event rule
    if aws notifications delete-event-rule \
        --name "${NOTIFICATION_CONFIG_NAME}-event-rule" 2>/dev/null; then
        log_success "Event rule deleted"
    else
        log_warning "Failed to delete event rule (may not exist)"
    fi
    
    # Delete notification configuration
    if [[ -n "${NOTIFICATION_CONFIG_ARN}" ]]; then
        if aws notifications delete-notification-configuration \
            --arn "${NOTIFICATION_CONFIG_ARN}" 2>/dev/null; then
            log_success "Notification configuration deleted"
        else
            log_warning "Failed to delete notification configuration (may not exist)"
        fi
    else
        log_warning "Notification configuration ARN not found, skipping deletion"
    fi
}

# Function to remove email contact and notification hub
remove_email_contact_and_hub() {
    log_info "Removing email contact and notification hub..."
    
    # Delete email contact
    if [[ -n "${EMAIL_CONTACT_ARN:-}" ]]; then
        if aws notificationscontacts delete-email-contact \
            --arn "${EMAIL_CONTACT_ARN}" 2>/dev/null; then
            log_success "Email contact deleted"
        else
            log_warning "Failed to delete email contact (may not exist)"
        fi
    else
        # Try to find and delete by name
        local contact_arn
        contact_arn=$(aws notificationscontacts list-email-contacts \
            --query "emailContacts[?name=='monitoring-alerts-contact'].arn" \
            --output text 2>/dev/null || echo "")
        
        if [[ -n "$contact_arn" ]] && [[ "$contact_arn" != "None" ]]; then
            if aws notificationscontacts delete-email-contact \
                --arn "$contact_arn" 2>/dev/null; then
                log_success "Email contact deleted"
            else
                log_warning "Failed to delete email contact"
            fi
        else
            log_warning "Email contact not found, skipping deletion"
        fi
    fi
    
    # Deregister notification hub
    if aws notifications deregister-notification-hub \
        --notification-hub-region ${AWS_REGION} 2>/dev/null; then
        log_success "Notification hub deregistered"
    else
        log_warning "Failed to deregister notification hub (may not exist or still in use)"
    fi
}

# Function to delete CloudWatch alarm
delete_cloudwatch_alarm() {
    log_info "Deleting CloudWatch alarm..."
    
    # Check if alarm exists before attempting deletion
    if aws cloudwatch describe-alarms --alarm-names ${ALARM_NAME} --query "MetricAlarms[0].AlarmName" --output text 2>/dev/null | grep -q "${ALARM_NAME}"; then
        if aws cloudwatch delete-alarms --alarm-names ${ALARM_NAME}; then
            log_success "CloudWatch alarm '${ALARM_NAME}' deleted"
        else
            log_error "Failed to delete CloudWatch alarm"
        fi
    else
        log_warning "CloudWatch alarm '${ALARM_NAME}' not found, skipping deletion"
    fi
}

# Function to remove S3 bucket and contents
remove_s3_bucket() {
    if [[ -z "${BUCKET_NAME:-}" ]]; then
        log_warning "Bucket name not specified, skipping S3 bucket deletion"
        return 0
    fi
    
    log_info "Removing S3 bucket and contents..."
    
    # Check if bucket exists
    if ! aws s3api head-bucket --bucket "${BUCKET_NAME}" 2>/dev/null; then
        log_warning "S3 bucket '${BUCKET_NAME}' not found, skipping deletion"
        return 0
    fi
    
    # Delete all objects in bucket (including versions)
    log_info "Deleting all objects and versions in bucket..."
    
    # Delete all object versions and delete markers
    aws s3api list-object-versions --bucket "${BUCKET_NAME}" \
        --query 'join(`\n`, [Versions[].{Key: Key, VersionId: VersionId}, DeleteMarkers[].{Key: Key, VersionId: VersionId}][])' \
        --output text | while read -r key version_id; do
        if [[ -n "$key" ]] && [[ -n "$version_id" ]]; then
            aws s3api delete-object --bucket "${BUCKET_NAME}" --key "$key" --version-id "$version_id" >/dev/null 2>&1
        fi
    done
    
    # Use S3 sync delete for any remaining objects
    aws s3 rm s3://${BUCKET_NAME} --recursive 2>/dev/null || true
    
    # Delete the bucket
    if aws s3 rb s3://${BUCKET_NAME} --force; then
        log_success "S3 bucket '${BUCKET_NAME}' and all contents removed"
    else
        log_error "Failed to delete S3 bucket '${BUCKET_NAME}'"
        log_info "You may need to manually remove the bucket from the AWS Console"
    fi
}

# Function to cleanup local files
cleanup_local_files() {
    log_info "Cleaning up local files..."
    
    # Remove environment variables file
    if [[ -f /tmp/aws-centralized-alerts-env.sh ]]; then
        rm -f /tmp/aws-centralized-alerts-env.sh
        log_success "Environment variables file removed"
    fi
    
    # Remove any temporary files that might have been created
    local temp_files=("/tmp/sample1.txt" "/tmp/sample2.txt" "/tmp/largefile.dat")
    for file in "${temp_files[@]}"; do
        if [[ -f "$file" ]]; then
            rm -f "$file"
            log_info "Removed temporary file: $file"
        fi
    done
}

# Function to verify cleanup completion
verify_cleanup() {
    log_info "Verifying cleanup completion..."
    
    local cleanup_issues=0
    
    # Check if S3 bucket still exists
    if [[ -n "${BUCKET_NAME:-}" ]] && aws s3api head-bucket --bucket "${BUCKET_NAME}" 2>/dev/null; then
        log_warning "S3 bucket '${BUCKET_NAME}' still exists"
        ((cleanup_issues++))
    fi
    
    # Check if CloudWatch alarm still exists
    if aws cloudwatch describe-alarms --alarm-names ${ALARM_NAME} --query "MetricAlarms[0].AlarmName" --output text 2>/dev/null | grep -q "${ALARM_NAME}"; then
        log_warning "CloudWatch alarm '${ALARM_NAME}' still exists"
        ((cleanup_issues++))
    fi
    
    # Check if notification configuration still exists
    if aws notifications list-notification-configurations --query "notificationConfigurations[?name=='${NOTIFICATION_CONFIG_NAME}'].name" --output text 2>/dev/null | grep -q "${NOTIFICATION_CONFIG_NAME}"; then
        log_warning "Notification configuration '${NOTIFICATION_CONFIG_NAME}' still exists"
        ((cleanup_issues++))
    fi
    
    # Check if email contact still exists
    if aws notificationscontacts list-email-contacts --query "emailContacts[?name=='monitoring-alerts-contact'].name" --output text 2>/dev/null | grep -q "monitoring-alerts-contact"; then
        log_warning "Email contact 'monitoring-alerts-contact' still exists"
        ((cleanup_issues++))
    fi
    
    if [[ $cleanup_issues -eq 0 ]]; then
        log_success "Cleanup verification completed - all resources successfully removed"
    else
        log_warning "Cleanup verification found $cleanup_issues potential issues"
        log_info "Some resources may still exist and require manual cleanup"
    fi
    
    return $cleanup_issues
}

# Function to display cleanup summary
display_cleanup_summary() {
    local cleanup_status=$1
    
    echo
    if [[ $cleanup_status -eq 0 ]]; then
        log_success "🎉 Cleanup completed successfully!"
        echo
        log_info "All resources have been removed:"
        log_info "  ✅ S3 bucket and contents deleted"
        log_info "  ✅ CloudWatch alarm removed"
        log_info "  ✅ User Notifications configuration deleted"
        log_info "  ✅ Email contacts removed"
        log_info "  ✅ Notification hub deregistered"
        log_info "  ✅ Local files cleaned up"
    else
        log_warning "⚠️  Cleanup completed with warnings"
        echo
        log_info "Most resources have been removed, but some may require manual cleanup:"
        log_info "  • Check the AWS Console for any remaining resources"
        log_info "  • Verify no unexpected charges in your AWS billing"
        log_info "  • Some User Notifications resources may have dependencies"
    fi
    
    echo
    log_info "=== Cost Impact ==="
    log_info "With all resources deleted, you should not incur further charges"
    log_info "Check your AWS billing dashboard to confirm"
    
    echo
    log_info "=== Manual Verification ==="
    log_info "You can verify cleanup in the AWS Console:"
    log_info "  • S3: https://console.aws.amazon.com/s3/"
    log_info "  • CloudWatch: https://console.aws.amazon.com/cloudwatch/"
    log_info "  • User Notifications: https://console.aws.amazon.com/notifications/"
}

# Main cleanup function
main() {
    log_info "Starting cleanup of Centralized Alert Management resources"
    echo
    
    # Validate AWS configuration
    validate_aws_config
    
    # Load environment variables
    load_environment
    
    # Confirm destructive action
    confirm_destruction
    
    # Remove resources in reverse order of creation
    remove_notification_configurations
    remove_email_contact_and_hub
    delete_cloudwatch_alarm
    remove_s3_bucket
    cleanup_local_files
    
    # Verify cleanup
    verify_cleanup
    local cleanup_status=$?
    
    # Display summary
    display_cleanup_summary $cleanup_status
    
    return $cleanup_status
}

# Handle script interruption
cleanup_on_exit() {
    log_warning "Script interrupted during cleanup."
    log_info "Some resources may still exist and require manual cleanup."
    exit 1
}

trap cleanup_on_exit INT TERM

# Function to show help
show_help() {
    echo "Usage: $0 [OPTIONS]"
    echo
    echo "Cleanup script for Centralized Alert Management with User Notifications and CloudWatch"
    echo
    echo "Options:"
    echo "  -h, --help              Show this help message"
    echo "  -f, --force             Skip confirmation prompt (dangerous!)"
    echo "  -b, --bucket BUCKET     Specify bucket name to delete"
    echo "  -v, --verbose           Enable verbose logging"
    echo
    echo "Environment Variables:"
    echo "  BUCKET_NAME            S3 bucket name to delete"
    echo "  ALARM_NAME             CloudWatch alarm name (default: s3-bucket-size-alarm)"
    echo "  NOTIFICATION_CONFIG_NAME  Notification config name (default: s3-monitoring-config)"
    echo
    echo "Examples:"
    echo "  $0                      # Interactive cleanup with confirmation"
    echo "  $0 --force              # Cleanup without confirmation (use with caution)"
    echo "  $0 --bucket my-bucket   # Specify bucket name explicitly"
}

# Parse command line arguments
FORCE_MODE=false
VERBOSE_MODE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        -f|--force)
            FORCE_MODE=true
            shift
            ;;
        -b|--bucket)
            BUCKET_NAME="$2"
            shift 2
            ;;
        -v|--verbose)
            VERBOSE_MODE=true
            set -x
            shift
            ;;
        *)
            log_error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Override confirmation if force mode is enabled
if [[ "$FORCE_MODE" == "true" ]]; then
    confirm_destruction() {
        log_warning "Force mode enabled - skipping confirmation"
    }
fi

# Check if script is being sourced or executed
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi