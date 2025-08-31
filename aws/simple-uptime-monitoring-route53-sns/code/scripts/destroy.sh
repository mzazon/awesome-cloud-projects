#!/bin/bash

# =============================================================================
# AWS Uptime Monitoring Cleanup Script
# Simple Website Uptime Monitoring with Route53 and SNS
# =============================================================================

set -euo pipefail

# Colors for output formatting
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Script configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_FILE="${SCRIPT_DIR}/destroy.log"
readonly STATE_FILE="${SCRIPT_DIR}/.deployment_state"

# =============================================================================
# Utility Functions
# =============================================================================

log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case "$level" in
        "INFO")
            echo -e "${GREEN}[INFO]${NC} $message" | tee -a "$LOG_FILE"
            ;;
        "WARN")
            echo -e "${YELLOW}[WARN]${NC} $message" | tee -a "$LOG_FILE"
            ;;
        "ERROR") 
            echo -e "${RED}[ERROR]${NC} $message" | tee -a "$LOG_FILE"
            ;;
        "DEBUG")
            echo -e "${BLUE}[DEBUG]${NC} $message" | tee -a "$LOG_FILE"
            ;;
        *)
            echo "[$timestamp] $level: $message" >> "$LOG_FILE"
            ;;
    esac
}

print_header() {
    echo -e "${BLUE}"
    echo "================================================================================"
    echo "  AWS Uptime Monitoring Cleanup Script"
    echo "  Simple Website Uptime Monitoring with Route53 and SNS"
    echo "================================================================================"
    echo -e "${NC}"
}

print_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

OPTIONS:
    -f, --force              Skip confirmation prompts
    -h, --help               Show this help message
    -v, --verbose            Enable verbose logging
    --dry-run                Show what would be deleted without making changes
    --keep-state             Keep state file after cleanup
    --partial-cleanup        Clean up only specified resources

EXAMPLES:
    $0                       Interactive cleanup with confirmations
    $0 --force               Non-interactive cleanup
    $0 --dry-run --verbose   Show what would be deleted
    $0 --partial-cleanup     Clean up specific resources only

RESOURCE CLEANUP ORDER:
    1. CloudWatch Alarms
    2. Route53 Health Check
    3. SNS Subscriptions
    4. SNS Topic
    5. State Files (unless --keep-state is used)
EOF
}

prompt_confirmation() {
    local message="$1"
    local default="${2:-n}"
    
    if [[ "${FORCE:-false}" == "true" ]]; then
        log "INFO" "$message (forced: yes)"
        return 0
    fi
    
    local prompt="$message (y/N): "
    if [[ "$default" == "y" ]]; then
        prompt="$message (Y/n): "
    fi
    
    while true; do
        read -p "$prompt" -r response
        response=${response:-$default}
        case $response in
            [Yy]|[Yy][Ee][Ss]) return 0 ;;
            [Nn]|[Nn][Oo]) return 1 ;;
            *) echo "Please answer yes or no." ;;
        esac
    done
}

# =============================================================================
# State Management Functions
# =============================================================================

load_deployment_state() {
    local key="$1"
    
    if [[ -f "$STATE_FILE" ]]; then
        grep "^$key=" "$STATE_FILE" 2>/dev/null | cut -d'=' -f2- || echo ""
    else
        echo ""
    fi
}

remove_from_state() {
    local key="$1"
    
    if [[ -f "$STATE_FILE" ]]; then
        grep -v "^$key=" "$STATE_FILE" > "${STATE_FILE}.tmp" 2>/dev/null || touch "${STATE_FILE}.tmp"
        mv "${STATE_FILE}.tmp" "$STATE_FILE"
    fi
}

# =============================================================================
# Prerequisites Check Functions
# =============================================================================

check_prerequisites() {
    log "INFO" "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        log "ERROR" "AWS CLI is not installed. Please install AWS CLI v2.0 or higher."
        exit 1
    fi
    
    # Check if AWS credentials are configured
    if ! aws sts get-caller-identity &> /dev/null; then
        log "ERROR" "AWS credentials not configured. Please run 'aws configure' first."
        exit 1
    fi
    
    # Get AWS account and region info
    AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    AWS_REGION=${AWS_REGION:-$(aws configure get region)}
    
    if [[ -z "$AWS_REGION" ]]; then
        log "ERROR" "AWS region not configured. Please set AWS_REGION or run 'aws configure'."
        exit 1
    fi
    
    log "INFO" "AWS Account ID: $AWS_ACCOUNT_ID"
    log "INFO" "AWS Region: $AWS_REGION"
    
    log "INFO" "Prerequisites check completed successfully."
}

load_deployment_info() {
    log "INFO" "Loading deployment information..."
    
    if [[ ! -f "$STATE_FILE" ]]; then
        log "WARN" "No deployment state file found at $STATE_FILE"
        log "WARN" "This might indicate no resources were deployed with the deploy script"
        return 1
    fi
    
    # Load deployment state
    TOPIC_ARN=$(load_deployment_state "TOPIC_ARN")
    TOPIC_NAME=$(load_deployment_state "TOPIC_NAME")
    SUBSCRIPTION_ARN=$(load_deployment_state "SUBSCRIPTION_ARN")
    HEALTH_CHECK_ID=$(load_deployment_state "HEALTH_CHECK_ID")
    HEALTH_CHECK_NAME=$(load_deployment_state "HEALTH_CHECK_NAME")
    DOWNTIME_ALARM_NAME=$(load_deployment_state "DOWNTIME_ALARM_NAME")
    RECOVERY_ALARM_NAME=$(load_deployment_state "RECOVERY_ALARM_NAME")
    WEBSITE_URL=$(load_deployment_state "WEBSITE_URL")
    ADMIN_EMAIL=$(load_deployment_state "ADMIN_EMAIL")
    
    log "INFO" "Loaded deployment configuration:"
    [[ -n "$TOPIC_ARN" ]] && log "INFO" "  SNS Topic ARN: $TOPIC_ARN"
    [[ -n "$HEALTH_CHECK_ID" ]] && log "INFO" "  Health Check ID: $HEALTH_CHECK_ID"
    [[ -n "$WEBSITE_URL" ]] && log "INFO" "  Website URL: $WEBSITE_URL"
    [[ -n "$ADMIN_EMAIL" ]] && log "INFO" "  Admin Email: $ADMIN_EMAIL"
    
    return 0
}

# =============================================================================
# Resource Cleanup Functions
# =============================================================================

delete_cloudwatch_alarms() {
    log "INFO" "Removing CloudWatch alarms..."
    
    local alarms_to_delete=()
    
    # Check downtime alarm
    if [[ -n "$DOWNTIME_ALARM_NAME" ]]; then
        if aws cloudwatch describe-alarms --alarm-names "$DOWNTIME_ALARM_NAME" --query 'MetricAlarms[0].AlarmName' --output text 2>/dev/null | grep -q "$DOWNTIME_ALARM_NAME"; then
            alarms_to_delete+=("$DOWNTIME_ALARM_NAME")
        else
            log "WARN" "Downtime alarm '$DOWNTIME_ALARM_NAME' not found"
        fi
    fi
    
    # Check recovery alarm
    if [[ -n "$RECOVERY_ALARM_NAME" ]]; then
        if aws cloudwatch describe-alarms --alarm-names "$RECOVERY_ALARM_NAME" --query 'MetricAlarms[0].AlarmName' --output text 2>/dev/null | grep -q "$RECOVERY_ALARM_NAME"; then
            alarms_to_delete+=("$RECOVERY_ALARM_NAME")
        else
            log "WARN" "Recovery alarm '$RECOVERY_ALARM_NAME' not found"
        fi
    fi
    
    if [[ ${#alarms_to_delete[@]} -eq 0 ]]; then
        log "INFO" "No CloudWatch alarms to delete"
        return 0
    fi
    
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log "INFO" "DRY RUN: Would delete CloudWatch alarms: ${alarms_to_delete[*]}"
        return 0
    fi
    
    # Delete alarms
    if aws cloudwatch delete-alarms --alarm-names "${alarms_to_delete[@]}"; then
        log "INFO" "Successfully deleted CloudWatch alarms: ${alarms_to_delete[*]}"
        remove_from_state "DOWNTIME_ALARM_NAME"
        remove_from_state "RECOVERY_ALARM_NAME"
    else
        log "ERROR" "Failed to delete some CloudWatch alarms"
        return 1
    fi
}

delete_health_check() {
    log "INFO" "Removing Route53 health check..."
    
    if [[ -z "$HEALTH_CHECK_ID" ]]; then
        log "INFO" "No health check ID found in state"
        return 0
    fi
    
    # Check if health check exists
    if ! aws route53 get-health-check --health-check-id "$HEALTH_CHECK_ID" &> /dev/null; then
        log "WARN" "Health check '$HEALTH_CHECK_ID' not found"
        remove_from_state "HEALTH_CHECK_ID"
        remove_from_state "HEALTH_CHECK_NAME"
        return 0
    fi
    
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log "INFO" "DRY RUN: Would delete Route53 health check: $HEALTH_CHECK_ID"
        return 0
    fi
    
    # Delete health check
    if aws route53 delete-health-check --health-check-id "$HEALTH_CHECK_ID"; then
        log "INFO" "Successfully deleted Route53 health check: $HEALTH_CHECK_ID"
        remove_from_state "HEALTH_CHECK_ID"
        remove_from_state "HEALTH_CHECK_NAME"
        remove_from_state "DOMAIN_NAME"
    else
        log "ERROR" "Failed to delete Route53 health check: $HEALTH_CHECK_ID"
        return 1
    fi
}

delete_sns_subscription() {
    log "INFO" "Removing SNS email subscription..."
    
    if [[ -z "$SUBSCRIPTION_ARN" ]]; then
        log "INFO" "No subscription ARN found in state"
        return 0
    fi
    
    # Skip if subscription was never confirmed (PendingConfirmation)
    if [[ "$SUBSCRIPTION_ARN" == "PendingConfirmation" ]]; then
        log "INFO" "Subscription was never confirmed, nothing to delete"
        remove_from_state "SUBSCRIPTION_ARN"
        return 0
    fi
    
    # Check if subscription exists by trying to get its attributes
    if ! aws sns get-subscription-attributes --subscription-arn "$SUBSCRIPTION_ARN" &> /dev/null; then
        log "WARN" "Subscription '$SUBSCRIPTION_ARN' not found"
        remove_from_state "SUBSCRIPTION_ARN"
        return 0
    fi
    
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log "INFO" "DRY RUN: Would delete SNS subscription: $SUBSCRIPTION_ARN"
        return 0
    fi
    
    # Delete subscription
    if aws sns unsubscribe --subscription-arn "$SUBSCRIPTION_ARN"; then
        log "INFO" "Successfully deleted SNS subscription: $SUBSCRIPTION_ARN"
        remove_from_state "SUBSCRIPTION_ARN"
        remove_from_state "ADMIN_EMAIL"
    else
        log "ERROR" "Failed to delete SNS subscription: $SUBSCRIPTION_ARN"
        return 1
    fi
}

delete_sns_topic() {
    log "INFO" "Removing SNS topic..."
    
    if [[ -z "$TOPIC_ARN" ]]; then
        log "INFO" "No topic ARN found in state"
        return 0
    fi
    
    # Check if topic exists
    if ! aws sns get-topic-attributes --topic-arn "$TOPIC_ARN" &> /dev/null; then
        log "WARN" "SNS topic '$TOPIC_ARN' not found"
        remove_from_state "TOPIC_ARN"
        remove_from_state "TOPIC_NAME"
        return 0
    fi
    
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log "INFO" "DRY RUN: Would delete SNS topic: $TOPIC_ARN"
        return 0
    fi
    
    # Delete topic
    if aws sns delete-topic --topic-arn "$TOPIC_ARN"; then
        log "INFO" "Successfully deleted SNS topic: $TOPIC_ARN"
        remove_from_state "TOPIC_ARN"
        remove_from_state "TOPIC_NAME"
    else
        log "ERROR" "Failed to delete SNS topic: $TOPIC_ARN"
        return 1
    fi
}

clean_environment_variables() {
    log "INFO" "Cleaning up environment variables..."
    
    # List of variables to unset
    local vars_to_unset=(
        "WEBSITE_URL"
        "ADMIN_EMAIL"
        "TOPIC_NAME"
        "HEALTH_CHECK_NAME"
        "TOPIC_ARN"
        "SUBSCRIPTION_ARN"
        "HEALTH_CHECK_ID"
        "RANDOM_SUFFIX"
        "DOMAIN_NAME"
        "PORT"
        "PROTOCOL"
        "ENABLE_SNI"
    )
    
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log "INFO" "DRY RUN: Would unset environment variables: ${vars_to_unset[*]}"
        return 0
    fi
    
    for var in "${vars_to_unset[@]}"; do
        if [[ -n "${!var:-}" ]]; then
            unset "$var"
            log "DEBUG" "Unset environment variable: $var"
        fi
    done
    
    log "INFO" "Environment variables cleaned up"
}

cleanup_state_files() {
    log "INFO" "Cleaning up state files..."
    
    if [[ "${KEEP_STATE:-false}" == "true" ]]; then
        log "INFO" "Keeping state file as requested"
        return 0
    fi
    
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log "INFO" "DRY RUN: Would remove state file: $STATE_FILE"
        return 0
    fi
    
    if [[ -f "$STATE_FILE" ]]; then
        rm -f "$STATE_FILE"
        log "INFO" "Removed state file: $STATE_FILE"
    fi
    
    # Clean up any backup files
    rm -f "${STATE_FILE}.bak" "${STATE_FILE}.tmp" 2>/dev/null || true
}

# =============================================================================
# Validation Functions
# =============================================================================

verify_cleanup() {
    log "INFO" "Verifying cleanup completion..."
    
    local cleanup_issues=0
    
    # Check CloudWatch alarms
    if [[ -n "${DOWNTIME_ALARM_NAME:-}" ]] && aws cloudwatch describe-alarms --alarm-names "$DOWNTIME_ALARM_NAME" &> /dev/null; then
        log "WARN" "Downtime alarm still exists: $DOWNTIME_ALARM_NAME"
        ((cleanup_issues++))
    fi
    
    if [[ -n "${RECOVERY_ALARM_NAME:-}" ]] && aws cloudwatch describe-alarms --alarm-names "$RECOVERY_ALARM_NAME" &> /dev/null; then
        log "WARN" "Recovery alarm still exists: $RECOVERY_ALARM_NAME"
        ((cleanup_issues++))
    fi
    
    # Check Route53 health check
    if [[ -n "${HEALTH_CHECK_ID:-}" ]] && aws route53 get-health-check --health-check-id "$HEALTH_CHECK_ID" &> /dev/null; then
        log "WARN" "Health check still exists: $HEALTH_CHECK_ID"
        ((cleanup_issues++))
    fi
    
    # Check SNS topic
    if [[ -n "${TOPIC_ARN:-}" ]] && aws sns get-topic-attributes --topic-arn "$TOPIC_ARN" &> /dev/null; then
        log "WARN" "SNS topic still exists: $TOPIC_ARN"
        ((cleanup_issues++))
    fi
    
    if [[ $cleanup_issues -eq 0 ]]; then
        log "INFO" "Cleanup verification completed successfully"
        return 0
    else
        log "WARN" "Cleanup verification found $cleanup_issues remaining resources"
        return 1
    fi
}

# =============================================================================
# Interactive Cleanup Functions
# =============================================================================

show_resources_summary() {
    echo
    echo -e "${BLUE}=== Resources to be deleted ===${NC}"
    
    local resource_count=0
    
    if [[ -n "${DOWNTIME_ALARM_NAME:-}" ]] || [[ -n "${RECOVERY_ALARM_NAME:-}" ]]; then
        echo "CloudWatch Alarms:"
        [[ -n "${DOWNTIME_ALARM_NAME:-}" ]] && echo "  - $DOWNTIME_ALARM_NAME" && ((resource_count++))
        [[ -n "${RECOVERY_ALARM_NAME:-}" ]] && echo "  - $RECOVERY_ALARM_NAME" && ((resource_count++))
    fi
    
    if [[ -n "${HEALTH_CHECK_ID:-}" ]]; then
        echo "Route53 Health Check:"
        echo "  - $HEALTH_CHECK_ID (${HEALTH_CHECK_NAME:-unknown})"
        ((resource_count++))
    fi
    
    if [[ -n "${SUBSCRIPTION_ARN:-}" ]]; then
        echo "SNS Subscription:"
        echo "  - $SUBSCRIPTION_ARN (${ADMIN_EMAIL:-unknown})"
        ((resource_count++))
    fi
    
    if [[ -n "${TOPIC_ARN:-}" ]]; then
        echo "SNS Topic:"
        echo "  - $TOPIC_ARN (${TOPIC_NAME:-unknown})"
        ((resource_count++))
    fi
    
    if [[ $resource_count -eq 0 ]]; then
        echo "No resources found to delete."
        return 1
    fi
    
    echo
    echo "Total resources to delete: $resource_count"
    echo
    
    return 0
}

partial_cleanup_menu() {
    echo
    echo -e "${BLUE}=== Partial Cleanup Menu ===${NC}"
    echo "Select resources to clean up:"
    echo "1) CloudWatch Alarms only"
    echo "2) Route53 Health Check only"
    echo "3) SNS Subscription only"
    echo "4) SNS Topic only"
    echo "5) All resources (full cleanup)"
    echo "6) Cancel"
    echo
    
    while true; do
        read -p "Enter your choice (1-6): " -r choice
        case $choice in
            1)
                log "INFO" "Selected: CloudWatch Alarms cleanup"
                delete_cloudwatch_alarms
                break
                ;;
            2)
                log "INFO" "Selected: Route53 Health Check cleanup"  
                delete_health_check
                break
                ;;
            3)
                log "INFO" "Selected: SNS Subscription cleanup"
                delete_sns_subscription
                break
                ;;
            4)
                log "INFO" "Selected: SNS Topic cleanup"
                delete_sns_topic
                break
                ;;
            5)
                log "INFO" "Selected: Full cleanup"
                return 1  # Signal to do full cleanup
                ;;
            6)
                log "INFO" "Cleanup cancelled by user"
                exit 0
                ;;
            *)
                echo "Invalid choice. Please enter 1-6."
                ;;
        esac
    done
}

# =============================================================================
# Main Cleanup Logic
# =============================================================================

cleanup_monitoring() {
    log "INFO" "Starting uptime monitoring cleanup..."
    
    # Load deployment information
    if ! load_deployment_info; then
        log "WARN" "No deployment state found. Attempting manual cleanup..."
        
        if [[ "${FORCE:-false}" != "true" ]]; then
            if ! prompt_confirmation "No state file found. Would you like to search for resources manually?"; then
                log "INFO" "Cleanup cancelled by user"
                exit 0
            fi
        fi
        
        # Manual cleanup would require user input for resource IDs
        log "INFO" "Manual cleanup not yet implemented. Exiting."
        exit 1
    fi
    
    # Show resources that will be deleted
    if ! show_resources_summary; then
        log "INFO" "No resources to clean up. Exiting."
        exit 0
    fi
    
    # Handle partial cleanup if requested
    if [[ "${PARTIAL_CLEANUP:-false}" == "true" ]]; then
        if ! partial_cleanup_menu; then
            # User selected full cleanup, continue with normal flow
            true
        else
            # Partial cleanup completed
            log "INFO" "Partial cleanup completed"
            exit 0
        fi
    fi
    
    # Confirm deletion
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log "INFO" "DRY RUN: Would delete all resources shown above"
        exit 0
    fi
    
    if [[ "${FORCE:-false}" != "true" ]]; then
        echo -e "${YELLOW}WARNING: This will permanently delete all uptime monitoring resources.${NC}"
        if ! prompt_confirmation "Are you sure you want to continue?"; then
            log "INFO" "Cleanup cancelled by user"
            exit 0
        fi
    fi
    
    # Perform cleanup in reverse order of creation
    local cleanup_errors=0
    
    log "INFO" "Beginning resource cleanup..."
    
    # 1. Delete CloudWatch alarms
    if ! delete_cloudwatch_alarms; then
        ((cleanup_errors++))
    fi
    
    # 2. Delete Route53 health check
    if ! delete_health_check; then
        ((cleanup_errors++))
    fi
    
    # 3. Delete SNS subscription
    if ! delete_sns_subscription; then
        ((cleanup_errors++))
    fi
    
    # 4. Delete SNS topic
    if ! delete_sns_topic; then
        ((cleanup_errors++))
    fi
    
    # 5. Clean up environment variables
    clean_environment_variables
    
    # 6. Clean up state files
    cleanup_state_files
    
    # Verify cleanup
    if verify_cleanup; then
        if [[ $cleanup_errors -eq 0 ]]; then
            log "INFO" "Uptime monitoring cleanup completed successfully!"
            echo
            echo -e "${GREEN}=== Cleanup Summary ===${NC}"
            echo "All monitoring resources have been successfully removed."
            echo "No further charges will be incurred for this monitoring setup."
            echo
        else
            log "WARN" "Cleanup completed with $cleanup_errors errors. Check logs for details."
        fi
    else
        log "ERROR" "Cleanup verification failed. Some resources may still exist."
        exit 1
    fi
}

cleanup_on_error() {
    local exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        log "ERROR" "Cleanup failed with exit code $exit_code"
        log "INFO" "Check the log file for details: $LOG_FILE"
    fi
    exit $exit_code
}

# =============================================================================
# Main Script Execution
# =============================================================================

main() {
    # Set trap for error handling
    trap cleanup_on_error EXIT
    
    # Initialize logging
    echo "Cleanup started at $(date)" > "$LOG_FILE"
    
    print_header
    
    # Parse command line arguments
    FORCE=false
    VERBOSE=false
    DRY_RUN=false
    KEEP_STATE=false
    PARTIAL_CLEANUP=false
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            -f|--force)
                FORCE=true
                shift
                ;;
            -h|--help)
                print_usage
                exit 0
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --keep-state)
                KEEP_STATE=true
                shift
                ;;
            --partial-cleanup)
                PARTIAL_CLEANUP=true
                shift
                ;;
            *)
                log "ERROR" "Unknown option: $1"
                print_usage
                exit 1
                ;;
        esac
    done
    
    # Set verbose logging if requested
    if [[ "$VERBOSE" == "true" ]]; then
        set -x
    fi
    
    # Run cleanup steps
    check_prerequisites
    cleanup_monitoring
    
    # Remove trap on successful completion
    trap - EXIT
}

# Run main function with all arguments
main "$@"