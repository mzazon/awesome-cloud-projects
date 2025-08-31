#!/bin/bash

# AWS Cost Monitoring with Cost Explorer and Budgets - Cleanup Script
# This script removes all resources created by the deployment script
# including budgets, notifications, and SNS topics

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Script configuration
readonly SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_FILE="${SCRIPT_DIR}/destroy.log"
readonly CONFIG_DIR="${SCRIPT_DIR}/../config"
readonly DEPLOYMENT_VARS="${CONFIG_DIR}/deployment-vars.env"

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Logging function
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${timestamp} [${level}] ${message}" | tee -a "${LOG_FILE}"
}

info() { log "INFO" "${BLUE}$*${NC}"; }
warn() { log "WARN" "${YELLOW}$*${NC}"; }
error() { log "ERROR" "${RED}$*${NC}"; }
success() { log "SUCCESS" "${GREEN}$*${NC}"; }

# Cleanup function for error handling
cleanup() {
    local exit_code=$?
    if [ $exit_code -ne 0 ]; then
        error "Cleanup failed. Check ${LOG_FILE} for details."
        warn "Some resources may still exist and require manual deletion."
    fi
}

trap cleanup EXIT

# Function to check prerequisites
check_prerequisites() {
    info "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install AWS CLI version 2.x"
        exit 1
    fi
    
    # Check if AWS credentials are configured
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials not configured. Run 'aws configure' first."
        exit 1
    fi
    
    success "Prerequisites check passed"
}

# Function to load deployment variables
load_deployment_vars() {
    info "Loading deployment variables..."
    
    if [ ! -f "${DEPLOYMENT_VARS}" ]; then
        error "Deployment variables file not found: ${DEPLOYMENT_VARS}"
        error "Cannot determine which resources to delete."
        error "Please run cleanup manually or re-deploy first."
        exit 1
    fi
    
    # Source the deployment variables
    source "${DEPLOYMENT_VARS}"
    
    # Validate required variables exist
    local required_vars=(
        "AWS_REGION"
        "AWS_ACCOUNT_ID"
        "MONTHLY_BUDGET_NAME"
        "SNS_TOPIC_NAME"
    )
    
    for var in "${required_vars[@]}"; do
        if [ -z "${!var:-}" ]; then
            error "Required variable ${var} not found in deployment variables"
            exit 1
        fi
    done
    
    # Get SNS Topic ARN if not in variables
    if [ -z "${SNS_TOPIC_ARN:-}" ]; then
        info "Looking up SNS Topic ARN..."
        SNS_TOPIC_ARN=$(aws sns list-topics \
            --query "Topics[?contains(TopicArn, '${SNS_TOPIC_NAME}')].TopicArn" \
            --output text 2>/dev/null || echo "")
    fi
    
    info "Deployment variables loaded:"
    info "  AWS Region: ${AWS_REGION}"
    info "  AWS Account ID: ${AWS_ACCOUNT_ID}"
    info "  Budget Name: ${MONTHLY_BUDGET_NAME}"
    info "  SNS Topic: ${SNS_TOPIC_NAME}"
    if [ -n "${SNS_TOPIC_ARN}" ]; then
        info "  SNS Topic ARN: ${SNS_TOPIC_ARN}"
    fi
}

# Function to confirm destruction
confirm_destruction() {
    if [ "${FORCE_DESTROY:-}" = "true" ]; then
        return 0
    fi
    
    echo
    warn "This will permanently delete the following resources:"
    echo "  • Budget: ${MONTHLY_BUDGET_NAME}"
    echo "  • All budget notifications"
    echo "  • SNS Topic: ${SNS_TOPIC_NAME}"
    echo "  • Email subscriptions"
    echo "  • Configuration files"
    echo
    
    read -p "Are you sure you want to continue? (yes/no): " confirm
    case "$confirm" in
        yes|YES|y|Y)
            info "Proceeding with resource destruction..."
            ;;
        *)
            info "Destruction cancelled by user"
            exit 0
            ;;
    esac
}

# Function to delete budget notifications
delete_budget_notifications() {
    info "Deleting budget notifications..."
    
    # Check if budget exists first
    if ! aws budgets describe-budget \
        --account-id "${AWS_ACCOUNT_ID}" \
        --budget-name "${MONTHLY_BUDGET_NAME}" &> /dev/null; then
        warn "Budget ${MONTHLY_BUDGET_NAME} not found, skipping notification deletion"
        return 0
    fi
    
    # Get all notifications for the budget
    local notifications=$(aws budgets describe-notifications-for-budget \
        --account-id "${AWS_ACCOUNT_ID}" \
        --budget-name "${MONTHLY_BUDGET_NAME}" \
        --query 'Notifications[*].[NotificationType,ComparisonOperator,Threshold,ThresholdType]' \
        --output text 2>/dev/null || echo "")
    
    if [ -z "${notifications}" ]; then
        info "No notifications found for budget"
        return 0
    fi
    
    # Delete each notification
    local deleted_count=0
    while IFS=$'\t' read -r notification_type comparison_operator threshold threshold_type; do
        if [ -n "${notification_type}" ]; then
            info "Deleting notification: ${notification_type} ${threshold}% ${threshold_type}"
            
            if aws budgets delete-notification \
                --account-id "${AWS_ACCOUNT_ID}" \
                --budget-name "${MONTHLY_BUDGET_NAME}" \
                --notification "NotificationType=${notification_type},ComparisonOperator=${comparison_operator},Threshold=${threshold},ThresholdType=${threshold_type}" \
                2>/dev/null; then
                success "Deleted notification: ${notification_type} ${threshold}%"
                ((deleted_count++))
            else
                warn "Failed to delete notification: ${notification_type} ${threshold}%"
            fi
        fi
    done <<< "${notifications}"
    
    if [ ${deleted_count} -gt 0 ]; then
        success "Deleted ${deleted_count} budget notifications"
    else
        warn "No notifications were deleted"
    fi
}

# Function to delete budget
delete_budget() {
    info "Deleting budget: ${MONTHLY_BUDGET_NAME}..."
    
    # Check if budget exists
    if ! aws budgets describe-budget \
        --account-id "${AWS_ACCOUNT_ID}" \
        --budget-name "${MONTHLY_BUDGET_NAME}" &> /dev/null; then
        warn "Budget ${MONTHLY_BUDGET_NAME} not found, may already be deleted"
        return 0
    fi
    
    # Delete the budget
    if aws budgets delete-budget \
        --account-id "${AWS_ACCOUNT_ID}" \
        --budget-name "${MONTHLY_BUDGET_NAME}"; then
        success "Budget deleted: ${MONTHLY_BUDGET_NAME}"
    else
        error "Failed to delete budget: ${MONTHLY_BUDGET_NAME}"
        return 1
    fi
}

# Function to delete SNS resources
delete_sns_resources() {
    info "Deleting SNS resources..."
    
    if [ -z "${SNS_TOPIC_ARN}" ]; then
        warn "SNS Topic ARN not found, cannot delete SNS resources"
        return 0
    fi
    
    # Check if topic exists
    if ! aws sns get-topic-attributes --topic-arn "${SNS_TOPIC_ARN}" &> /dev/null; then
        warn "SNS topic not found, may already be deleted"
        return 0
    fi
    
    # List and delete subscriptions first (optional, as deleting topic removes them)
    info "Checking for SNS subscriptions..."
    local subscriptions=$(aws sns list-subscriptions-by-topic \
        --topic-arn "${SNS_TOPIC_ARN}" \
        --query 'Subscriptions[*].SubscriptionArn' \
        --output text 2>/dev/null || echo "")
    
    if [ -n "${subscriptions}" ] && [ "${subscriptions}" != "None" ]; then
        local sub_count=0
        for subscription_arn in ${subscriptions}; do
            if [ "${subscription_arn}" != "PendingConfirmation" ]; then
                ((sub_count++))
            fi
        done
        info "Found ${sub_count} subscription(s) (will be deleted with topic)"
    fi
    
    # Delete SNS topic (this also removes all subscriptions)
    if aws sns delete-topic --topic-arn "${SNS_TOPIC_ARN}"; then
        success "SNS topic deleted: ${SNS_TOPIC_ARN}"
    else
        error "Failed to delete SNS topic: ${SNS_TOPIC_ARN}"
        return 1
    fi
}

# Function to clean up configuration files
cleanup_config_files() {
    info "Cleaning up configuration files..."
    
    local files_deleted=0
    
    # Delete JSON configuration files
    for config_file in "${CONFIG_DIR}"/*.json; do
        if [ -f "${config_file}" ]; then
            rm -f "${config_file}"
            info "Deleted: $(basename "${config_file}")"
            ((files_deleted++))
        fi
    done
    
    # Delete deployment variables file
    if [ -f "${DEPLOYMENT_VARS}" ]; then
        rm -f "${DEPLOYMENT_VARS}"
        info "Deleted: $(basename "${DEPLOYMENT_VARS}")"
        ((files_deleted++))
    fi
    
    # Remove config directory if empty
    if [ -d "${CONFIG_DIR}" ] && [ -z "$(ls -A "${CONFIG_DIR}")" ]; then
        rmdir "${CONFIG_DIR}"
        info "Removed empty config directory"
        ((files_deleted++))
    fi
    
    if [ ${files_deleted} -gt 0 ]; then
        success "Cleaned up ${files_deleted} configuration file(s)"
    else
        info "No configuration files to clean up"
    fi
}

# Function to validate cleanup
validate_cleanup() {
    info "Validating cleanup..."
    
    local cleanup_issues=0
    
    # Check if budget still exists
    if aws budgets describe-budget \
        --account-id "${AWS_ACCOUNT_ID}" \
        --budget-name "${MONTHLY_BUDGET_NAME}" &> /dev/null; then
        warn "Budget still exists: ${MONTHLY_BUDGET_NAME}"
        ((cleanup_issues++))
    else
        success "Budget cleanup validated"
    fi
    
    # Check if SNS topic still exists
    if [ -n "${SNS_TOPIC_ARN}" ] && aws sns get-topic-attributes \
        --topic-arn "${SNS_TOPIC_ARN}" &> /dev/null; then
        warn "SNS topic still exists: ${SNS_TOPIC_ARN}"
        ((cleanup_issues++))
    else
        success "SNS cleanup validated"
    fi
    
    if [ ${cleanup_issues} -eq 0 ]; then
        success "All resources cleaned up successfully"
    else
        warn "${cleanup_issues} cleanup issue(s) detected"
        return 1
    fi
}

# Function to display cleanup summary
display_summary() {
    info "Cleanup completed!"
    echo
    echo "=== CLEANUP SUMMARY ==="
    echo "✓ Budget notifications deleted"
    echo "✓ Budget deleted: ${MONTHLY_BUDGET_NAME}"
    echo "✓ SNS topic deleted: ${SNS_TOPIC_NAME}"
    echo "✓ Configuration files cleaned up"
    echo
    echo "=== VERIFICATION ==="
    echo "All cost monitoring resources have been removed from your AWS account."
    echo "You can verify this in the AWS Console:"
    echo "• AWS Budgets: https://console.aws.amazon.com/billing/home#/budgets"
    echo "• SNS Topics: https://console.aws.amazon.com/sns/v3/home#/topics"
    echo
}

# Function to list resources for manual cleanup
list_manual_cleanup() {
    warn "If cleanup validation failed, you may need to manually delete:"
    echo
    echo "Budget:"
    echo "  aws budgets delete-budget --account-id ${AWS_ACCOUNT_ID} --budget-name ${MONTHLY_BUDGET_NAME}"
    echo
    if [ -n "${SNS_TOPIC_ARN}" ]; then
        echo "SNS Topic:"
        echo "  aws sns delete-topic --topic-arn ${SNS_TOPIC_ARN}"
        echo
    fi
    echo "Configuration files:"
    echo "  rm -rf ${CONFIG_DIR}"
    echo
}

# Main execution function
main() {
    info "Starting AWS Cost Monitoring cleanup..."
    info "Log file: ${LOG_FILE}"
    
    check_prerequisites
    load_deployment_vars
    confirm_destruction
    
    # Perform cleanup in reverse order of creation
    delete_budget_notifications
    delete_budget
    delete_sns_resources
    cleanup_config_files
    
    if validate_cleanup; then
        display_summary
        success "AWS Cost Monitoring cleanup completed successfully!"
    else
        list_manual_cleanup
        warn "Cleanup completed with issues. See manual cleanup instructions above."
        exit 1
    fi
}

# Help function
show_help() {
    cat << EOF
AWS Cost Monitoring Cleanup Script

USAGE:
    ${SCRIPT_NAME} [OPTIONS]

OPTIONS:
    -h, --help              Show this help message
    -f, --force             Skip confirmation prompt
    --list-resources        List resources that would be deleted
    --dry-run              Show what would be deleted without making changes

ENVIRONMENT VARIABLES:
    FORCE_DESTROY          Skip confirmation if set to 'true'

EXAMPLES:
    ${SCRIPT_NAME}                    # Interactive cleanup
    ${SCRIPT_NAME} --force            # Skip confirmation
    ${SCRIPT_NAME} --list-resources   # Show resources to delete

EOF
}

# Function to list resources that would be deleted
list_resources() {
    info "Loading deployment configuration..."
    
    if [ ! -f "${DEPLOYMENT_VARS}" ]; then
        error "No deployment found. Nothing to delete."
        exit 0
    fi
    
    source "${DEPLOYMENT_VARS}"
    
    echo
    echo "=== RESOURCES TO DELETE ==="
    echo "Budget:"
    echo "  Name: ${MONTHLY_BUDGET_NAME}"
    echo "  Account: ${AWS_ACCOUNT_ID}"
    echo
    echo "SNS Topic:"
    echo "  Name: ${SNS_TOPIC_NAME}"
    echo "  Region: ${AWS_REGION}"
    echo
    echo "Configuration Files:"
    if [ -d "${CONFIG_DIR}" ]; then
        find "${CONFIG_DIR}" -type f -name "*.json" -o -name "*.env" | while read -r file; do
            echo "  $(basename "${file}")"
        done
    else
        echo "  (none found)"
    fi
    echo
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        -f|--force)
            export FORCE_DESTROY="true"
            shift
            ;;
        --list-resources)
            list_resources
            exit 0
            ;;
        --dry-run)
            info "Dry-run mode not implemented yet"
            list_resources
            exit 0
            ;;
        *)
            error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Execute main function
main "$@"