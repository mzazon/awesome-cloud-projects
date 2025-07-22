#!/bin/bash

# Enterprise Migration Assessment with AWS Application Discovery Service - Cleanup Script
# This script removes all AWS resources created for the migration assessment

set -euo pipefail

# Color codes for output formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script directory and files
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/cleanup.log"
DEPLOYMENT_STATE_FILE="${SCRIPT_DIR}/.deployment_state"

# Function to log messages with timestamp
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${timestamp} [${level}] ${message}" | tee -a "${LOG_FILE}"
}

# Function to log and display colored messages
log_info() {
    echo -e "${BLUE}[INFO]${NC} $*"
    log "INFO" "$*"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*"
    log "SUCCESS" "$*"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $*"
    log "WARNING" "$*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*"
    log "ERROR" "$*"
}

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to validate AWS CLI and credentials
validate_aws_setup() {
    log_info "Validating AWS CLI setup and credentials..."
    
    if ! command_exists aws; then
        log_error "AWS CLI is not installed. Please install AWS CLI v2."
        exit 1
    fi
    
    # Test AWS credentials
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        log_error "AWS credentials not configured or invalid. Run 'aws configure' first."
        exit 1
    fi
    
    # Get account info
    ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    AWS_REGION=$(aws configure get region)
    
    if [[ -z "${AWS_REGION}" ]]; then
        log_error "AWS region not configured. Please set a default region."
        exit 1
    fi
    
    log_success "AWS setup validated. Account: ${ACCOUNT_ID}, Region: ${AWS_REGION}"
}

# Function to load deployment state
load_deployment_state() {
    log_info "Loading deployment state..."
    
    if [[ ! -f "${DEPLOYMENT_STATE_FILE}" ]]; then
        log_warning "No deployment state file found. Will attempt cleanup with user input."
        return 1
    fi
    
    # Source the deployment state file
    source "${DEPLOYMENT_STATE_FILE}"
    
    log_success "Deployment state loaded successfully"
    log_info "  Migration Project: ${MIGRATION_PROJECT_NAME:-N/A}"
    log_info "  S3 Bucket: ${S3_BUCKET_NAME:-N/A}"
    log_info "  Log Group: ${LOG_GROUP_NAME:-N/A}"
    log_info "  Deployment Date: ${DEPLOYMENT_TIMESTAMP:-N/A}"
    
    return 0
}

# Function to prompt for manual resource identification
prompt_for_resources() {
    log_warning "No deployment state found. Manual resource identification required."
    echo
    
    read -p "Enter Migration Project Name (or press Enter to skip): " MIGRATION_PROJECT_NAME
    read -p "Enter S3 Bucket Name (or press Enter to skip): " S3_BUCKET_NAME
    read -p "Enter CloudWatch Log Group Name (or press Enter to skip): " LOG_GROUP_NAME
    read -p "Enter EventBridge Rule Name (default: weekly-discovery-export): " EVENTBRIDGE_RULE_NAME
    
    # Set defaults
    EVENTBRIDGE_RULE_NAME=${EVENTBRIDGE_RULE_NAME:-"weekly-discovery-export"}
    
    if [[ -z "${MIGRATION_PROJECT_NAME}" && -z "${S3_BUCKET_NAME}" && -z "${LOG_GROUP_NAME}" ]]; then
        log_error "No resources specified for cleanup. Exiting."
        exit 1
    fi
}

# Function to confirm cleanup
confirm_cleanup() {
    echo
    log_warning "=== CLEANUP CONFIRMATION ==="
    log_warning "This will permanently delete the following resources:"
    
    if [[ -n "${S3_BUCKET_NAME:-}" ]]; then
        log_warning "  • S3 Bucket: ${S3_BUCKET_NAME} (including all data)"
    fi
    
    if [[ -n "${MIGRATION_PROJECT_NAME:-}" ]]; then
        log_warning "  • Migration Hub Project: ${MIGRATION_PROJECT_NAME}"
    fi
    
    if [[ -n "${LOG_GROUP_NAME:-}" ]]; then
        log_warning "  • CloudWatch Log Group: ${LOG_GROUP_NAME}"
    fi
    
    if [[ -n "${EVENTBRIDGE_RULE_NAME:-}" ]]; then
        log_warning "  • EventBridge Rule: ${EVENTBRIDGE_RULE_NAME}"
    fi
    
    log_warning "  • Discovery data exports and continuous export tasks"
    log_warning "  • Configuration files created during deployment"
    echo
    log_warning "NOTE: Discovery agents on servers will need to be manually uninstalled."
    log_warning "NOTE: Discovery connectors in VMware environments will need to be manually removed."
    echo
    
    read -p "Are you sure you want to proceed? (yes/no): " confirmation
    
    if [[ "${confirmation}" != "yes" ]]; then
        log_info "Cleanup cancelled by user."
        exit 0
    fi
    
    echo
    log_info "Proceeding with cleanup..."
}

# Function to stop data collection
stop_data_collection() {
    log_info "Stopping data collection..."
    
    # Get list of active agents
    local agents
    agents=$(aws discovery describe-agents --query 'agentsInfo[?health==`HEALTHY`].agentId' --output text 2>/dev/null || echo "")
    
    if [[ -n "${agents}" ]]; then
        log_info "Stopping data collection for agents: ${agents}"
        if aws discovery stop-data-collection-by-agent-ids --agent-ids ${agents} >/dev/null 2>&1; then
            log_success "Data collection stopped for active agents"
        else
            log_warning "Could not stop data collection for some agents"
        fi
    else
        log_info "No active agents found or agents already stopped"
    fi
    
    # Stop continuous export if it exists
    if [[ -n "${CONTINUOUS_EXPORT_ID:-}" ]]; then
        log_info "Stopping continuous export: ${CONTINUOUS_EXPORT_ID}"
        if aws discovery stop-continuous-export --export-id "${CONTINUOUS_EXPORT_ID}" >/dev/null 2>&1; then
            log_success "Continuous export stopped"
        else
            log_warning "Could not stop continuous export (may already be stopped)"
        fi
    fi
}

# Function to delete EventBridge rule
delete_eventbridge_rule() {
    if [[ -z "${EVENTBRIDGE_RULE_NAME:-}" ]]; then
        log_info "No EventBridge rule specified, skipping..."
        return 0
    fi
    
    log_info "Deleting EventBridge rule: ${EVENTBRIDGE_RULE_NAME}"
    
    # Remove targets first (if any)
    local targets
    targets=$(aws events list-targets-by-rule --rule "${EVENTBRIDGE_RULE_NAME}" --query 'Targets[].Id' --output text 2>/dev/null || echo "")
    
    if [[ -n "${targets}" ]]; then
        log_info "Removing targets from EventBridge rule"
        aws events remove-targets --rule "${EVENTBRIDGE_RULE_NAME}" --ids ${targets} >/dev/null 2>&1 || true
    fi
    
    # Delete the rule
    if aws events delete-rule --name "${EVENTBRIDGE_RULE_NAME}" >/dev/null 2>&1; then
        log_success "EventBridge rule deleted: ${EVENTBRIDGE_RULE_NAME}"
    else
        log_warning "Could not delete EventBridge rule (may not exist): ${EVENTBRIDGE_RULE_NAME}"
    fi
}

# Function to delete CloudWatch Log Group
delete_log_group() {
    if [[ -z "${LOG_GROUP_NAME:-}" ]]; then
        log_info "No CloudWatch Log Group specified, skipping..."
        return 0
    fi
    
    log_info "Deleting CloudWatch Log Group: ${LOG_GROUP_NAME}"
    
    if aws logs delete-log-group --log-group-name "${LOG_GROUP_NAME}" >/dev/null 2>&1; then
        log_success "CloudWatch Log Group deleted: ${LOG_GROUP_NAME}"
    else
        log_warning "Could not delete CloudWatch Log Group (may not exist): ${LOG_GROUP_NAME}"
    fi
}

# Function to delete Migration Hub resources
delete_migration_hub_resources() {
    if [[ -z "${MIGRATION_PROJECT_NAME:-}" ]]; then
        log_info "No Migration Hub project specified, skipping..."
        return 0
    fi
    
    log_info "Cleaning up Migration Hub resources..."
    
    # Migration Hub home region
    local hub_region="us-west-2"
    
    # Delete progress update stream
    if aws migrationhub delete-progress-update-stream \
        --progress-update-stream-name "${MIGRATION_PROJECT_NAME}" \
        --region "${hub_region}" >/dev/null 2>&1; then
        log_success "Migration Hub progress stream deleted: ${MIGRATION_PROJECT_NAME}"
    else
        log_warning "Could not delete Migration Hub progress stream (may not exist): ${MIGRATION_PROJECT_NAME}"
    fi
}

# Function to empty and delete S3 bucket
delete_s3_bucket() {
    if [[ -z "${S3_BUCKET_NAME:-}" ]]; then
        log_info "No S3 bucket specified, skipping..."
        return 0
    fi
    
    log_info "Deleting S3 bucket: ${S3_BUCKET_NAME}"
    
    # Check if bucket exists
    if ! aws s3 ls "s3://${S3_BUCKET_NAME}" >/dev/null 2>&1; then
        log_warning "S3 bucket does not exist: ${S3_BUCKET_NAME}"
        return 0
    fi
    
    # Get object count for progress indication
    local object_count
    object_count=$(aws s3api list-objects-v2 --bucket "${S3_BUCKET_NAME}" --query 'KeyCount' --output text 2>/dev/null || echo "0")
    
    if [[ "${object_count}" -gt 0 ]]; then
        log_info "Deleting ${object_count} objects from S3 bucket..."
        
        # Delete all objects (including versions if versioning is enabled)
        aws s3api list-object-versions --bucket "${S3_BUCKET_NAME}" \
            --query 'Versions[].{Key:Key,VersionId:VersionId}' \
            --output text 2>/dev/null | while read -r key version_id; do
            if [[ -n "${key}" && -n "${version_id}" ]]; then
                aws s3api delete-object --bucket "${S3_BUCKET_NAME}" --key "${key}" --version-id "${version_id}" >/dev/null 2>&1
            fi
        done
        
        # Delete delete markers
        aws s3api list-object-versions --bucket "${S3_BUCKET_NAME}" \
            --query 'DeleteMarkers[].{Key:Key,VersionId:VersionId}' \
            --output text 2>/dev/null | while read -r key version_id; do
            if [[ -n "${key}" && -n "${version_id}" ]]; then
                aws s3api delete-object --bucket "${S3_BUCKET_NAME}" --key "${key}" --version-id "${version_id}" >/dev/null 2>&1
            fi
        done
        
        # Fallback: use aws s3 rm for any remaining objects
        aws s3 rm "s3://${S3_BUCKET_NAME}" --recursive >/dev/null 2>&1 || true
    fi
    
    # Delete the bucket
    if aws s3 rb "s3://${S3_BUCKET_NAME}" >/dev/null 2>&1; then
        log_success "S3 bucket deleted: ${S3_BUCKET_NAME}"
    else
        log_error "Could not delete S3 bucket: ${S3_BUCKET_NAME}"
        log_error "You may need to manually delete remaining objects and the bucket"
    fi
}

# Function to clean up local files
cleanup_local_files() {
    log_info "Cleaning up local configuration files..."
    
    local files_to_remove=(
        "${SCRIPT_DIR}/agent-config.json"
        "${SCRIPT_DIR}/connector-config.json"
        "${SCRIPT_DIR}/migration-waves.json"
        "${DEPLOYMENT_STATE_FILE}"
    )
    
    for file in "${files_to_remove[@]}"; do
        if [[ -f "${file}" ]]; then
            rm -f "${file}"
            log_info "Removed: $(basename "${file}")"
        fi
    done
    
    log_success "Local configuration files cleaned up"
}

# Function to display manual cleanup instructions
display_manual_cleanup_instructions() {
    echo
    log_warning "=== MANUAL CLEANUP REQUIRED ==="
    echo
    log_warning "The following items require manual cleanup:"
    echo
    log_warning "1. Discovery Agents on Servers:"
    log_warning "   • Windows: Run 'msiexec /x {APPLICATION-DISCOVERY-AGENT-GUID} /quiet'"
    log_warning "   • Linux: Run 'sudo /opt/aws/discovery/uninstall'"
    echo
    log_warning "2. Discovery Connectors in VMware:"
    log_warning "   • Remove the Discovery Connector VM from vCenter"
    log_warning "   • Delete the connector configuration from vCenter"
    echo
    log_warning "3. Migration Hub Data:"
    log_warning "   • Some historical data may remain in Migration Hub"
    log_warning "   • This data does not incur charges but can be viewed in the console"
    echo
    log_info "4. Verify Cleanup:"
    log_info "   • Check AWS console for any remaining resources"
    log_info "   • Verify no unexpected charges in AWS billing"
}

# Function to display cleanup summary
display_cleanup_summary() {
    echo
    log_success "=== CLEANUP COMPLETED ==="
    echo
    log_info "AWS resources removed:"
    if [[ -n "${S3_BUCKET_NAME:-}" ]]; then
        log_info "  ✓ S3 Bucket: ${S3_BUCKET_NAME}"
    fi
    if [[ -n "${MIGRATION_PROJECT_NAME:-}" ]]; then
        log_info "  ✓ Migration Hub Project: ${MIGRATION_PROJECT_NAME}"
    fi
    if [[ -n "${LOG_GROUP_NAME:-}" ]]; then
        log_info "  ✓ CloudWatch Log Group: ${LOG_GROUP_NAME}"
    fi
    if [[ -n "${EVENTBRIDGE_RULE_NAME:-}" ]]; then
        log_info "  ✓ EventBridge Rule: ${EVENTBRIDGE_RULE_NAME}"
    fi
    log_info "  ✓ Discovery data collection stopped"
    log_info "  ✓ Local configuration files removed"
    echo
    log_info "Cleanup log saved to: ${LOG_FILE}"
}

# Function to handle cleanup on script exit
cleanup_on_exit() {
    local exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        log_error "Cleanup failed with exit code: ${exit_code}"
        log_info "Check the log file for details: ${LOG_FILE}"
        log_warning "Some resources may still exist and require manual cleanup"
    fi
}

# Main cleanup function
main() {
    echo "=============================================================="
    echo "  AWS Application Discovery Service Cleanup Script"
    echo "  Enterprise Migration Assessment"
    echo "=============================================================="
    echo
    
    # Setup trap for cleanup
    trap cleanup_on_exit EXIT
    
    # Initialize log file
    echo "$(date '+%Y-%m-%d %H:%M:%S') [INFO] Starting cleanup..." > "${LOG_FILE}"
    
    # Run cleanup steps
    validate_aws_setup
    
    if ! load_deployment_state; then
        prompt_for_resources
    fi
    
    confirm_cleanup
    stop_data_collection
    delete_eventbridge_rule
    delete_log_group
    delete_migration_hub_resources
    delete_s3_bucket
    cleanup_local_files
    display_cleanup_summary
    display_manual_cleanup_instructions
    
    log_success "Cleanup completed successfully!"
}

# Check if script is being sourced or executed
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi