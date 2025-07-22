#!/bin/bash

# Destroy script for Application Performance Monitoring with Cloud Monitoring and Cloud Trace
# Recipe: f4a8e3d2
# Last Updated: 2025-07-12

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

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DESTROY_LOG="${SCRIPT_DIR}/destroy.log"
RESOURCE_STATE="${SCRIPT_DIR}/.deploy_state"

# Default configuration
DEFAULT_PROJECT_ID=""
DEFAULT_REGION="us-central1"
DEFAULT_ZONE="us-central1-a"

# Function to load resource state
load_resource_state() {
    if [[ -f "${RESOURCE_STATE}" ]]; then
        log_info "Loading resource state from previous deployment..."
        source "${RESOURCE_STATE}"
        
        # Verify required variables are set
        if [[ -z "${PROJECT_ID:-}" ]]; then
            log_error "PROJECT_ID not found in resource state file"
            return 1
        fi
        
        log_info "Found project: ${PROJECT_ID}"
        return 0
    else
        log_warning "No resource state file found. You may need to specify resources manually."
        return 1
    fi
}

# Function to prompt for manual resource specification
prompt_manual_input() {
    log_warning "No deployment state found. Please provide resource information manually."
    
    # Prompt for project ID
    read -p "Enter Project ID to clean up: " PROJECT_ID
    if [[ -z "${PROJECT_ID}" ]]; then
        log_error "Project ID is required"
        exit 1
    fi
    
    # Set defaults for other variables
    REGION="${DEFAULT_REGION}"
    ZONE="${DEFAULT_ZONE}"
    
    # Prompt for optional resource names (with fallback to listing)
    read -p "Enter Instance Name (leave blank to auto-detect): " INSTANCE_NAME
    read -p "Enter Pub/Sub Topic Name (leave blank to auto-detect): " PUBSUB_TOPIC
    read -p "Enter Function Name (leave blank to auto-detect): " FUNCTION_NAME
    
    log_info "Manual input completed"
}

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if gcloud CLI is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "gcloud CLI is not installed. Please install it from https://cloud.google.com/sdk/docs/install"
        exit 1
    fi
    
    # Check if user is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        log_error "No active gcloud authentication found. Please run 'gcloud auth login'"
        exit 1
    fi
    
    # Verify project exists
    if ! gcloud projects describe "${PROJECT_ID}" &>/dev/null; then
        log_error "Project ${PROJECT_ID} does not exist or is not accessible"
        exit 1
    fi
    
    # Set project context
    gcloud config set project "${PROJECT_ID}" 2>>"${DESTROY_LOG}"
    gcloud config set compute/region "${REGION}" 2>>"${DESTROY_LOG}"
    gcloud config set compute/zone "${ZONE}" 2>>"${DESTROY_LOG}"
    
    log_success "Prerequisites check completed"
}

# Function to confirm destruction
confirm_destruction() {
    log_warning "This will DELETE ALL resources created by the monitoring demo in project: ${PROJECT_ID}"
    echo
    echo "Resources that will be deleted:"
    echo "• Compute Engine instances"
    echo "• Cloud Functions"
    echo "• Pub/Sub topics and subscriptions"
    echo "• Firewall rules"
    echo "• Monitoring alert policies"
    echo "• Notification channels"
    echo "• Monitoring dashboards"
    echo "• Project (if specified)"
    echo
    
    read -p "Are you sure you want to continue? (y/N): " confirm
    if [[ ! "${confirm}" =~ ^[Yy]$ ]]; then
        log_info "Destruction cancelled by user"
        exit 0
    fi
    
    # Double confirmation for project deletion
    read -p "Do you also want to DELETE the entire project ${PROJECT_ID}? (y/N): " delete_project
    export DELETE_PROJECT="${delete_project}"
}

# Function to auto-detect resources if not specified
auto_detect_resources() {
    log_info "Auto-detecting resources in project ${PROJECT_ID}..."
    
    # Auto-detect instance names if not specified
    if [[ -z "${INSTANCE_NAME:-}" ]]; then
        log_info "Detecting Compute Engine instances..."
        local instances
        instances=$(gcloud compute instances list --format="value(name)" --filter="tags.items:web-server" 2>>"${DESTROY_LOG}" || true)
        if [[ -n "${instances}" ]]; then
            INSTANCE_NAME=$(echo "${instances}" | head -n1)
            log_info "Found instance: ${INSTANCE_NAME}"
        fi
    fi
    
    # Auto-detect Pub/Sub topics if not specified
    if [[ -z "${PUBSUB_TOPIC:-}" ]]; then
        log_info "Detecting Pub/Sub topics..."
        local topics
        topics=$(gcloud pubsub topics list --format="value(name)" --filter="name~performance-alerts" 2>>"${DESTROY_LOG}" || true)
        if [[ -n "${topics}" ]]; then
            PUBSUB_TOPIC=$(basename "${topics}" | head -n1)
            log_info "Found topic: ${PUBSUB_TOPIC}"
        fi
    fi
    
    # Auto-detect Cloud Functions if not specified
    if [[ -z "${FUNCTION_NAME:-}" ]]; then
        log_info "Detecting Cloud Functions..."
        local functions
        functions=$(gcloud functions list --format="value(name)" --filter="name~performance-optimizer" 2>>"${DESTROY_LOG}" || true)
        if [[ -n "${functions}" ]]; then
            FUNCTION_NAME=$(basename "${functions}" | head -n1)
            log_info "Found function: ${FUNCTION_NAME}"
        fi
    fi
    
    log_success "Resource detection completed"
}

# Function to delete Cloud Functions
delete_cloud_functions() {
    log_info "Deleting Cloud Functions..."
    
    if [[ -n "${FUNCTION_NAME:-}" ]]; then
        log_info "Deleting function: ${FUNCTION_NAME}"
        if gcloud functions delete "${FUNCTION_NAME}" --quiet 2>>"${DESTROY_LOG}"; then
            log_success "Deleted Cloud Function: ${FUNCTION_NAME}"
        else
            log_warning "Failed to delete Cloud Function: ${FUNCTION_NAME} (may not exist)"
        fi
    else
        # Try to find and delete any performance-optimizer functions
        local functions
        functions=$(gcloud functions list --format="value(name)" --filter="name~performance-optimizer" 2>>"${DESTROY_LOG}" || true)
        for func in ${functions}; do
            local func_name=$(basename "${func}")
            log_info "Deleting function: ${func_name}"
            if gcloud functions delete "${func_name}" --quiet 2>>"${DESTROY_LOG}"; then
                log_success "Deleted Cloud Function: ${func_name}"
            else
                log_warning "Failed to delete Cloud Function: ${func_name}"
            fi
        done
    fi
}

# Function to delete Pub/Sub resources
delete_pubsub() {
    log_info "Deleting Pub/Sub resources..."
    
    if [[ -n "${PUBSUB_TOPIC:-}" ]]; then
        # Delete subscription first
        local subscription="${PUBSUB_TOPIC}-subscription"
        log_info "Deleting subscription: ${subscription}"
        if gcloud pubsub subscriptions delete "${subscription}" --quiet 2>>"${DESTROY_LOG}"; then
            log_success "Deleted Pub/Sub subscription: ${subscription}"
        else
            log_warning "Failed to delete subscription: ${subscription} (may not exist)"
        fi
        
        # Delete topic
        log_info "Deleting topic: ${PUBSUB_TOPIC}"
        if gcloud pubsub topics delete "${PUBSUB_TOPIC}" --quiet 2>>"${DESTROY_LOG}"; then
            log_success "Deleted Pub/Sub topic: ${PUBSUB_TOPIC}"
        else
            log_warning "Failed to delete topic: ${PUBSUB_TOPIC} (may not exist)"
        fi
    else
        # Try to find and delete performance-alert topics
        local topics
        topics=$(gcloud pubsub topics list --format="value(name)" --filter="name~performance-alerts" 2>>"${DESTROY_LOG}" || true)
        for topic_path in ${topics}; do
            local topic_name=$(basename "${topic_path}")
            local subscription="${topic_name}-subscription"
            
            # Delete subscription
            log_info "Deleting subscription: ${subscription}"
            if gcloud pubsub subscriptions delete "${subscription}" --quiet 2>>"${DESTROY_LOG}"; then
                log_success "Deleted subscription: ${subscription}"
            else
                log_warning "Failed to delete subscription: ${subscription}"
            fi
            
            # Delete topic
            log_info "Deleting topic: ${topic_name}"
            if gcloud pubsub topics delete "${topic_name}" --quiet 2>>"${DESTROY_LOG}"; then
                log_success "Deleted topic: ${topic_name}"
            else
                log_warning "Failed to delete topic: ${topic_name}"
            fi
        done
    fi
}

# Function to delete monitoring configuration
delete_monitoring() {
    log_info "Deleting monitoring configuration..."
    
    # Delete alert policies
    log_info "Deleting alert policies..."
    local policies
    policies=$(gcloud alpha monitoring policies list \
        --format="value(name)" \
        --filter="displayName:'High API Response Time Alert'" 2>>"${DESTROY_LOG}" || true)
    
    for policy in ${policies}; do
        log_info "Deleting alert policy: $(basename "${policy}")"
        if gcloud alpha monitoring policies delete "${policy}" --quiet 2>>"${DESTROY_LOG}"; then
            log_success "Deleted alert policy"
        else
            log_warning "Failed to delete alert policy: ${policy}"
        fi
    done
    
    # Delete notification channels
    log_info "Deleting notification channels..."
    local channels
    channels=$(gcloud alpha monitoring channels list \
        --format="value(name)" \
        --filter="displayName:'Performance Alert Channel'" 2>>"${DESTROY_LOG}" || true)
    
    for channel in ${channels}; do
        log_info "Deleting notification channel: $(basename "${channel}")"
        if gcloud alpha monitoring channels delete "${channel}" --quiet 2>>"${DESTROY_LOG}"; then
            log_success "Deleted notification channel"
        else
            log_warning "Failed to delete notification channel: ${channel}"
        fi
    done
    
    # Delete dashboards
    log_info "Deleting monitoring dashboards..."
    local dashboards
    dashboards=$(gcloud monitoring dashboards list \
        --format="value(name)" \
        --filter="displayName:'Intelligent Performance Monitoring Dashboard'" 2>>"${DESTROY_LOG}" || true)
    
    for dashboard in ${dashboards}; do
        log_info "Deleting dashboard: $(basename "${dashboard}")"
        if gcloud monitoring dashboards delete "${dashboard}" --quiet 2>>"${DESTROY_LOG}"; then
            log_success "Deleted dashboard"
        else
            log_warning "Failed to delete dashboard: ${dashboard}"
        fi
    done
}

# Function to delete compute resources
delete_compute_resources() {
    log_info "Deleting compute resources..."
    
    # Delete Compute Engine instances
    if [[ -n "${INSTANCE_NAME:-}" ]]; then
        log_info "Deleting instance: ${INSTANCE_NAME}"
        if gcloud compute instances delete "${INSTANCE_NAME}" \
            --zone="${ZONE}" --quiet 2>>"${DESTROY_LOG}"; then
            log_success "Deleted Compute Engine instance: ${INSTANCE_NAME}"
        else
            log_warning "Failed to delete instance: ${INSTANCE_NAME} (may not exist)"
        fi
    else
        # Try to find and delete web-server instances
        local instances
        instances=$(gcloud compute instances list --format="value(name)" --filter="tags.items:web-server" 2>>"${DESTROY_LOG}" || true)
        for instance in ${instances}; do
            log_info "Deleting instance: ${instance}"
            if gcloud compute instances delete "${instance}" \
                --zone="${ZONE}" --quiet 2>>"${DESTROY_LOG}"; then
                log_success "Deleted instance: ${instance}"
            else
                log_warning "Failed to delete instance: ${instance}"
            fi
        done
    fi
    
    # Delete firewall rules
    log_info "Deleting firewall rules..."
    if gcloud compute firewall-rules delete allow-web-app --quiet 2>>"${DESTROY_LOG}"; then
        log_success "Deleted firewall rule: allow-web-app"
    else
        log_warning "Failed to delete firewall rule: allow-web-app (may not exist)"
    fi
}

# Function to delete project (if requested)
delete_project() {
    if [[ "${DELETE_PROJECT:-}" =~ ^[Yy]$ ]]; then
        log_warning "Deleting entire project: ${PROJECT_ID}"
        log_warning "This action is IRREVERSIBLE and will delete ALL resources in the project!"
        
        read -p "Type 'DELETE' to confirm project deletion: " final_confirm
        if [[ "${final_confirm}" == "DELETE" ]]; then
            log_info "Initiating project deletion..."
            if gcloud projects delete "${PROJECT_ID}" --quiet 2>>"${DESTROY_LOG}"; then
                log_success "Project deletion initiated. This may take several minutes to complete."
                log_info "You can monitor the deletion status in the Cloud Console."
            else
                log_error "Failed to delete project: ${PROJECT_ID}"
            fi
        else
            log_info "Project deletion cancelled"
        fi
    fi
}

# Function to clean up local files
cleanup_local_files() {
    log_info "Cleaning up local files..."
    
    # Remove state file
    if [[ -f "${RESOURCE_STATE}" ]]; then
        rm -f "${RESOURCE_STATE}"
        log_success "Removed resource state file"
    fi
    
    # Remove temporary scripts and configs
    local temp_files=(
        "${SCRIPT_DIR}/generate_traffic.sh"
        "${SCRIPT_DIR}/alert-policy.json"
        "${SCRIPT_DIR}/notification-channel.json"
        "${SCRIPT_DIR}/updated-alert-policy.json"
        "${SCRIPT_DIR}/dashboard.json"
    )
    
    for file in "${temp_files[@]}"; do
        if [[ -f "${file}" ]]; then
            rm -f "${file}"
            log_success "Removed temporary file: $(basename "${file}")"
        fi
    done
    
    # Remove temporary function directory if it exists
    if [[ -d "${SCRIPT_DIR}/temp_function" ]]; then
        rm -rf "${SCRIPT_DIR}/temp_function"
        log_success "Removed temporary function directory"
    fi
}

# Function to verify resource deletion
verify_deletion() {
    log_info "Verifying resource deletion..."
    
    local verification_failed=false
    
    # Check for remaining instances
    local remaining_instances
    remaining_instances=$(gcloud compute instances list --format="value(name)" --filter="tags.items:web-server" 2>>"${DESTROY_LOG}" || true)
    if [[ -n "${remaining_instances}" ]]; then
        log_warning "Some instances may still exist: ${remaining_instances}"
        verification_failed=true
    fi
    
    # Check for remaining functions
    local remaining_functions
    remaining_functions=$(gcloud functions list --format="value(name)" --filter="name~performance-optimizer" 2>>"${DESTROY_LOG}" || true)
    if [[ -n "${remaining_functions}" ]]; then
        log_warning "Some functions may still exist: ${remaining_functions}"
        verification_failed=true
    fi
    
    # Check for remaining topics
    local remaining_topics
    remaining_topics=$(gcloud pubsub topics list --format="value(name)" --filter="name~performance-alerts" 2>>"${DESTROY_LOG}" || true)
    if [[ -n "${remaining_topics}" ]]; then
        log_warning "Some Pub/Sub topics may still exist: ${remaining_topics}"
        verification_failed=true
    fi
    
    if [[ "${verification_failed}" == "true" ]]; then
        log_warning "Some resources may not have been deleted completely"
        log_warning "You may need to check the Cloud Console and delete them manually"
    else
        log_success "Resource deletion verification completed successfully"
    fi
}

# Function to display destruction summary
display_summary() {
    echo
    echo "=== Destruction Summary ==="
    echo "Project ID: ${PROJECT_ID}"
    
    if [[ "${DELETE_PROJECT:-}" =~ ^[Yy]$ ]]; then
        echo "Status: Project deletion initiated"
        echo "Note: Project deletion may take several minutes to complete"
    else
        echo "Status: Resources deleted (project preserved)"
    fi
    
    echo
    echo "=== Deleted Resources ==="
    echo "• Compute Engine instances"
    echo "• Cloud Functions"
    echo "• Pub/Sub topics and subscriptions"
    echo "• Firewall rules"
    echo "• Monitoring alert policies"
    echo "• Notification channels"
    echo "• Monitoring dashboards"
    echo "• Local state and temporary files"
    echo
    
    log_info "Destruction log saved to: ${DESTROY_LOG}"
    log_success "Cleanup completed!"
}

# Function to handle errors during destruction
handle_destruction_error() {
    log_error "An error occurred during resource destruction"
    log_error "Check ${DESTROY_LOG} for details"
    log_info "Some resources may still exist and require manual deletion"
    exit 1
}

# Main destruction function
main() {
    log_info "Starting destruction of Application Performance Monitoring resources..."
    log_info "Destruction log: ${DESTROY_LOG}"
    
    # Clear previous log
    > "${DESTROY_LOG}"
    
    # Try to load resource state, otherwise prompt for manual input
    if ! load_resource_state; then
        prompt_manual_input
    fi
    
    # Execute destruction steps
    check_prerequisites
    auto_detect_resources
    confirm_destruction
    
    # Set up error handling
    trap handle_destruction_error ERR
    
    # Delete resources in reverse order of creation
    delete_cloud_functions
    delete_monitoring
    delete_pubsub
    delete_compute_resources
    delete_project
    cleanup_local_files
    verify_deletion
    
    display_summary
}

# Script entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi