#!/bin/bash

# Destroy script for Simple Application Health Monitoring with Cloud Monitoring
# This script safely removes all resources created by the deploy.sh script

set -euo pipefail

# Colors for output
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

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command_exists gcloud; then
        log_error "gcloud CLI is not installed. Please install it first."
        log_info "Visit: https://cloud.google.com/sdk/docs/install"
        exit 1
    fi
    
    # Check if user is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 >/dev/null 2>&1; then
        log_error "No authenticated gcloud account found. Please run 'gcloud auth login' first."
        exit 1
    fi
    
    log_success "Prerequisites check completed"
}

# Function to display confirmation prompt
confirm_destruction() {
    log_warning "⚠️  This script will DELETE all monitoring resources created by the deploy script."
    log_warning "This action is IRREVERSIBLE and will remove:"
    echo "  • Alert policies"
    echo "  • Uptime checks" 
    echo "  • Notification channels"
    echo "  • Cloud Functions"
    echo "  • Pub/Sub topics"
    echo "  • All associated configurations"
    echo
    
    # Interactive confirmation
    read -p "Are you sure you want to proceed? Type 'yes' to continue: " -r
    echo
    if [[ ! $REPLY == "yes" ]]; then
        log_info "Destruction cancelled by user."
        exit 0
    fi
    
    log_warning "Starting resource destruction in 5 seconds... Press Ctrl+C to cancel."
    sleep 5
}

# Function to set up environment from deployment info or user input
setup_environment() {
    log_info "Setting up environment variables..."
    
    # Try to find deployment info file
    local info_files
    mapfile -t info_files < <(find /tmp -name "monitoring-deployment-*.txt" 2>/dev/null || true)
    
    if [[ ${#info_files[@]} -gt 0 ]]; then
        log_info "Found deployment info file: ${info_files[0]}"
        # Source the deployment info to get variables
        while IFS='=' read -r key value; do
            # Skip comments and empty lines
            [[ $key =~ ^#.*$ ]] && continue
            [[ -z $key ]] && continue
            # Export variables
            export "$key"="$value"
        done < "${info_files[0]}"
        
        log_info "Using deployment info from file"
    else
        log_warning "No deployment info file found. Please provide environment variables manually."
        
        # Prompt for required variables
        read -p "Enter PROJECT_ID (or press Enter for current project): " input_project
        export PROJECT_ID="${input_project:-$(gcloud config get-value project 2>/dev/null)}"
        
        read -p "Enter REGION [us-central1]: " input_region
        export REGION="${input_region:-us-central1}"
        
        read -p "Enter RANDOM_SUFFIX (from deployment): " input_suffix
        export RANDOM_SUFFIX="${input_suffix}"
        
        if [[ -z "${RANDOM_SUFFIX}" ]]; then
            log_error "RANDOM_SUFFIX is required to identify resources to delete"
            exit 1
        fi
        
        # Construct resource names
        export TOPIC_NAME="monitoring-alerts-${RANDOM_SUFFIX}"
        export FUNCTION_NAME="alert-notifier-${RANDOM_SUFFIX}"
        export FUNCTION_SOURCE_DIR="/tmp/alert-function-${RANDOM_SUFFIX}"
    fi
    
    # Set project configuration
    gcloud config set project "${PROJECT_ID}" --quiet
    gcloud config set compute/region "${REGION}" --quiet
    
    log_info "Project ID: ${PROJECT_ID}"
    log_info "Region: ${REGION}"
    log_info "Random suffix: ${RANDOM_SUFFIX}"
    
    log_success "Environment variables configured"
}

# Function to list resources to be deleted
list_resources() {
    log_info "Scanning for resources to delete..."
    
    local resources_found=false
    
    # Check for alert policies
    local alert_policies
    alert_policies=$(gcloud alpha monitoring policies list \
        --filter="displayName:Website Uptime Alert ${RANDOM_SUFFIX}" \
        --format="value(name)" 2>/dev/null || true)
    
    if [[ -n "${alert_policies}" ]]; then
        log_info "Found alert policy: Website Uptime Alert ${RANDOM_SUFFIX}"
        resources_found=true
    fi
    
    # Check for uptime checks
    local uptime_checks
    uptime_checks=$(gcloud alpha monitoring uptime list \
        --filter="displayName:Sample Website Health Check ${RANDOM_SUFFIX}" \
        --format="value(name)" 2>/dev/null || true)
    
    if [[ -n "${uptime_checks}" ]]; then
        log_info "Found uptime check: Sample Website Health Check ${RANDOM_SUFFIX}"
        resources_found=true
    fi
    
    # Check for notification channels
    local notification_channels
    notification_channels=$(gcloud alpha monitoring channels list \
        --filter="displayName:Custom Alert Notifications ${RANDOM_SUFFIX}" \
        --format="value(name)" 2>/dev/null || true)
    
    if [[ -n "${notification_channels}" ]]; then
        log_info "Found notification channel: Custom Alert Notifications ${RANDOM_SUFFIX}"
        resources_found=true
    fi
    
    # Check for Cloud Functions
    if gcloud functions describe "${FUNCTION_NAME}" --region="${REGION}" >/dev/null 2>&1; then
        log_info "Found Cloud Function: ${FUNCTION_NAME}"
        resources_found=true
    fi
    
    # Check for Pub/Sub topics
    if gcloud pubsub topics describe "${TOPIC_NAME}" >/dev/null 2>&1; then
        log_info "Found Pub/Sub topic: ${TOPIC_NAME}"
        resources_found=true
    fi
    
    if [[ "${resources_found}" == false ]]; then
        log_warning "No resources found matching the provided suffix: ${RANDOM_SUFFIX}"
        log_info "Either the resources were already deleted or the suffix is incorrect."
        exit 0
    fi
}

# Function to delete alert policies
delete_alert_policies() {
    log_info "Deleting alert policies..."
    
    local policy_ids
    policy_ids=$(gcloud alpha monitoring policies list \
        --filter="displayName:Website Uptime Alert ${RANDOM_SUFFIX}" \
        --format="value(name)" 2>/dev/null || true)
    
    if [[ -n "${policy_ids}" ]]; then
        while IFS= read -r policy_id; do
            log_info "Deleting alert policy: ${policy_id}"
            if gcloud alpha monitoring policies delete "${policy_id}" --quiet; then
                log_success "✅ Alert policy deleted successfully"
            else
                log_error "❌ Failed to delete alert policy: ${policy_id}"
            fi
        done <<< "${policy_ids}"
    else
        log_info "No alert policies found to delete"
    fi
}

# Function to delete uptime checks
delete_uptime_checks() {
    log_info "Deleting uptime checks..."
    
    local uptime_check_ids
    uptime_check_ids=$(gcloud alpha monitoring uptime list \
        --filter="displayName:Sample Website Health Check ${RANDOM_SUFFIX}" \
        --format="value(name)" 2>/dev/null || true)
    
    if [[ -n "${uptime_check_ids}" ]]; then
        while IFS= read -r uptime_check_id; do
            log_info "Deleting uptime check: ${uptime_check_id}"
            if gcloud alpha monitoring uptime delete "${uptime_check_id}" --quiet; then
                log_success "✅ Uptime check deleted successfully"
            else
                log_error "❌ Failed to delete uptime check: ${uptime_check_id}"
            fi
        done <<< "${uptime_check_ids}"
    else
        log_info "No uptime checks found to delete"
    fi
}

# Function to delete notification channels
delete_notification_channels() {
    log_info "Deleting notification channels..."
    
    local channel_ids
    channel_ids=$(gcloud alpha monitoring channels list \
        --filter="displayName:Custom Alert Notifications ${RANDOM_SUFFIX}" \
        --format="value(name)" 2>/dev/null || true)
    
    if [[ -n "${channel_ids}" ]]; then
        while IFS= read -r channel_id; do
            log_info "Deleting notification channel: ${channel_id}"
            if gcloud alpha monitoring channels delete "${channel_id}" --quiet; then
                log_success "✅ Notification channel deleted successfully"
            else
                log_error "❌ Failed to delete notification channel: ${channel_id}"
            fi
        done <<< "${channel_ids}"
    else
        log_info "No notification channels found to delete"
    fi
}

# Function to delete Cloud Functions
delete_cloud_functions() {
    log_info "Deleting Cloud Functions..."
    
    if gcloud functions describe "${FUNCTION_NAME}" --region="${REGION}" >/dev/null 2>&1; then
        log_info "Deleting Cloud Function: ${FUNCTION_NAME}"
        if gcloud functions delete "${FUNCTION_NAME}" --region="${REGION}" --quiet; then
            log_success "✅ Cloud Function deleted successfully"
        else
            log_error "❌ Failed to delete Cloud Function: ${FUNCTION_NAME}"
        fi
    else
        log_info "No Cloud Function found to delete: ${FUNCTION_NAME}"
    fi
}

# Function to delete Pub/Sub topics
delete_pubsub_topics() {
    log_info "Deleting Pub/Sub topics..."
    
    if gcloud pubsub topics describe "${TOPIC_NAME}" >/dev/null 2>&1; then
        log_info "Deleting Pub/Sub topic: ${TOPIC_NAME}"
        if gcloud pubsub topics delete "${TOPIC_NAME}" --quiet; then
            log_success "✅ Pub/Sub topic deleted successfully"
        else
            log_error "❌ Failed to delete Pub/Sub topic: ${TOPIC_NAME}"
        fi
    else
        log_info "No Pub/Sub topic found to delete: ${TOPIC_NAME}"
    fi
}

# Function to clean up local files
cleanup_local_files() {
    log_info "Cleaning up local files..."
    
    # Clean up function source directory
    if [[ -d "${FUNCTION_SOURCE_DIR}" ]]; then
        log_info "Removing function source directory: ${FUNCTION_SOURCE_DIR}"
        rm -rf "${FUNCTION_SOURCE_DIR}"
        log_success "✅ Function source directory removed"
    fi
    
    # Clean up temporary JSON files
    local temp_files=(
        "/tmp/notification-channel-${RANDOM_SUFFIX}.json"
        "/tmp/uptime-check-${RANDOM_SUFFIX}.json"
        "/tmp/alert-policy-${RANDOM_SUFFIX}.json"
        "/tmp/monitoring-deployment-${RANDOM_SUFFIX}.txt"
    )
    
    for file in "${temp_files[@]}"; do
        if [[ -f "${file}" ]]; then
            log_info "Removing temporary file: ${file}"
            rm -f "${file}"
        fi
    done
    
    log_success "✅ Local files cleaned up"
}

# Function to validate resource deletion
validate_deletion() {
    log_info "Validating resource deletion..."
    
    local validation_passed=true
    
    # Check if alert policies still exist
    local remaining_policies
    remaining_policies=$(gcloud alpha monitoring policies list \
        --filter="displayName:Website Uptime Alert ${RANDOM_SUFFIX}" \
        --format="value(name)" 2>/dev/null || true)
    
    if [[ -n "${remaining_policies}" ]]; then
        log_error "❌ Alert policies still exist"
        validation_passed=false
    else
        log_success "✅ Alert policies successfully removed"
    fi
    
    # Check if uptime checks still exist
    local remaining_uptime
    remaining_uptime=$(gcloud alpha monitoring uptime list \
        --filter="displayName:Sample Website Health Check ${RANDOM_SUFFIX}" \
        --format="value(name)" 2>/dev/null || true)
    
    if [[ -n "${remaining_uptime}" ]]; then
        log_error "❌ Uptime checks still exist"
        validation_passed=false
    else
        log_success "✅ Uptime checks successfully removed"
    fi
    
    # Check if notification channels still exist
    local remaining_channels
    remaining_channels=$(gcloud alpha monitoring channels list \
        --filter="displayName:Custom Alert Notifications ${RANDOM_SUFFIX}" \
        --format="value(name)" 2>/dev/null || true)
    
    if [[ -n "${remaining_channels}" ]]; then
        log_error "❌ Notification channels still exist"
        validation_passed=false
    else
        log_success "✅ Notification channels successfully removed"
    fi
    
    # Check if Cloud Function still exists
    if gcloud functions describe "${FUNCTION_NAME}" --region="${REGION}" >/dev/null 2>&1; then
        log_error "❌ Cloud Function still exists"
        validation_passed=false
    else
        log_success "✅ Cloud Function successfully removed"
    fi
    
    # Check if Pub/Sub topic still exists
    if gcloud pubsub topics describe "${TOPIC_NAME}" >/dev/null 2>&1; then
        log_error "❌ Pub/Sub topic still exists"
        validation_passed=false
    else
        log_success "✅ Pub/Sub topic successfully removed"
    fi
    
    if [[ "${validation_passed}" == true ]]; then
        log_success "✅ All resources successfully deleted"
    else
        log_warning "⚠️  Some resources may still exist. Please check manually."
    fi
}

# Function to display final cleanup status
display_cleanup_status() {
    log_success "🧹 Cleanup completed!"
    echo
    log_info "The following resources have been removed:"
    echo "  • Alert policies with suffix: ${RANDOM_SUFFIX}"
    echo "  • Uptime checks with suffix: ${RANDOM_SUFFIX}"
    echo "  • Notification channels with suffix: ${RANDOM_SUFFIX}"
    echo "  • Cloud Function: ${FUNCTION_NAME}"
    echo "  • Pub/Sub topic: ${TOPIC_NAME}"
    echo "  • Local temporary files and directories"
    echo
    log_info "Additional cleanup notes:"
    echo "  • Project ${PROJECT_ID} remains active (not deleted)"
    echo "  • Enabled APIs remain active for future use"
    echo "  • Cloud Build logs may persist (minimal cost impact)"
    echo
    log_success "Monitoring solution has been completely removed! 🗑️"
}

# Function to handle partial cleanup on error
handle_cleanup_error() {
    log_error "An error occurred during cleanup. Some resources may still exist."
    log_info "You can:"
    echo "  1. Run this script again to retry cleanup"
    echo "  2. Manually delete remaining resources via Google Cloud Console"
    echo "  3. Check the Cloud Console for any resources with suffix: ${RANDOM_SUFFIX}"
    exit 1
}

# Trap to handle errors during cleanup
trap handle_cleanup_error ERR

# Main execution
main() {
    log_info "Starting destruction of Simple Application Health Monitoring resources..."
    echo
    
    check_prerequisites
    setup_environment
    confirm_destruction
    list_resources
    
    # Delete resources in reverse order of creation (dependencies first)
    delete_alert_policies
    delete_uptime_checks
    delete_notification_channels
    delete_cloud_functions
    delete_pubsub_topics
    cleanup_local_files
    
    # Validate deletion
    validate_deletion
    display_cleanup_status
    
    log_success "Destruction completed successfully! 🎯"
}

# Check if script is being sourced or executed
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi