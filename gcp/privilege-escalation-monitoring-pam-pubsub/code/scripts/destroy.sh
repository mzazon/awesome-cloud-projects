#!/bin/bash

# Destroy Privilege Escalation Monitoring with PAM and Pub/Sub
# This script safely removes all resources created by the deployment script
# including Pub/Sub topics, Cloud Functions, log sinks, and storage buckets

set -euo pipefail

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/destroy_$(date +%Y%m%d_%H%M%S).log"

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1" | tee -a "${LOG_FILE}"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" | tee -a "${LOG_FILE}"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "${LOG_FILE}"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "${LOG_FILE}"
}

# Error handling
handle_error() {
    local exit_code=$?
    log_error "Destruction failed with exit code ${exit_code}"
    log_error "Check the log file for details: ${LOG_FILE}"
    exit ${exit_code}
}

trap handle_error ERR

# Load environment from deployment
load_environment() {
    local env_file="${SCRIPT_DIR}/.deploy_env"
    
    if [[ -f "${env_file}" ]]; then
        log_info "Loading environment from ${env_file}..."
        # shellcheck source=/dev/null
        source "${env_file}"
        log_success "Environment loaded successfully"
    else
        log_warning "Environment file not found: ${env_file}"
        log_warning "You may need to manually specify resource names"
        
        # Try to get basic project info
        PROJECT_ID=$(gcloud config get-value project 2>/dev/null || echo "")
        if [[ -z "${PROJECT_ID}" ]]; then
            log_error "No project ID available. Set manually or run gcloud config set project YOUR_PROJECT_ID"
            exit 1
        fi
        
        REGION="${REGION:-us-central1}"
        log_info "Using fallback values - you may need to manually clean up resources"
        return 1
    fi
    
    return 0
}

# Confirm destruction with user
confirm_destruction() {
    echo
    echo "=== DESTRUCTION CONFIRMATION ==="
    echo "This will permanently delete the following resources:"
    echo "  - Project: ${PROJECT_ID}"
    echo "  - Pub/Sub Topic: ${TOPIC_NAME:-<unknown>}"
    echo "  - Pub/Sub Subscription: ${SUBSCRIPTION_NAME:-<unknown>}"
    echo "  - Cloud Function: ${FUNCTION_NAME:-<unknown>}"
    echo "  - Log Sink: ${SINK_NAME:-<unknown>}"
    echo "  - Storage Bucket: ${BUCKET_NAME:-<unknown>} (and ALL contents)"
    echo "  - Monitoring Alert Policies (manual cleanup required)"
    echo
    echo "=== WARNING ==="
    echo "This action CANNOT be undone!"
    echo "All audit logs and alert data in the storage bucket will be permanently lost."
    echo
    
    read -p "Are you sure you want to proceed? Type 'yes' to continue: " confirmation
    
    if [[ "${confirmation}" != "yes" ]]; then
        log_info "Destruction cancelled by user"
        exit 0
    fi
    
    log_info "User confirmed destruction. Proceeding..."
}

# Remove test IAM roles (if any exist)
cleanup_test_roles() {
    log_info "Cleaning up any test IAM roles..."
    
    # Look for test roles with our suffix pattern
    if [[ -n "${RANDOM_SUFFIX:-}" ]]; then
        local test_role="testPrivilegeRole${RANDOM_SUFFIX}"
        
        if gcloud iam roles describe "${test_role}" --project="${PROJECT_ID}" --quiet >/dev/null 2>&1; then
            log_info "Removing test IAM role: ${test_role}"
            if gcloud iam roles delete "${test_role}" --project="${PROJECT_ID}" --quiet; then
                log_success "Test IAM role removed: ${test_role}"
            else
                log_warning "Failed to remove test IAM role: ${test_role}"
            fi
        fi
    fi
    
    return 0
}

# Delete Cloud Function
delete_cloud_function() {
    if [[ -z "${FUNCTION_NAME:-}" ]]; then
        log_warning "Cloud Function name not specified, skipping"
        return 0
    fi
    
    log_info "Deleting Cloud Function: ${FUNCTION_NAME}"
    
    # Check if function exists
    if gcloud functions describe "${FUNCTION_NAME}" --region="${REGION}" --quiet >/dev/null 2>&1; then
        if gcloud functions delete "${FUNCTION_NAME}" --region="${REGION}" --quiet; then
            log_success "Cloud Function deleted: ${FUNCTION_NAME}"
        else
            log_error "Failed to delete Cloud Function: ${FUNCTION_NAME}"
            return 1
        fi
    else
        log_info "Cloud Function not found: ${FUNCTION_NAME}"
    fi
    
    return 0
}

# Delete log sink
delete_log_sink() {
    if [[ -z "${SINK_NAME:-}" ]]; then
        log_warning "Log sink name not specified, skipping"
        return 0
    fi
    
    log_info "Deleting log sink: ${SINK_NAME}"
    
    # Check if sink exists
    if gcloud logging sinks describe "${SINK_NAME}" --quiet >/dev/null 2>&1; then
        if gcloud logging sinks delete "${SINK_NAME}" --quiet; then
            log_success "Log sink deleted: ${SINK_NAME}"
        else
            log_error "Failed to delete log sink: ${SINK_NAME}"
            return 1
        fi
    else
        log_info "Log sink not found: ${SINK_NAME}"
    fi
    
    return 0
}

# Delete Pub/Sub resources
delete_pubsub_resources() {
    log_info "Deleting Pub/Sub resources..."
    
    # Delete subscription first (if exists)
    if [[ -n "${SUBSCRIPTION_NAME:-}" ]]; then
        log_info "Deleting Pub/Sub subscription: ${SUBSCRIPTION_NAME}"
        if gcloud pubsub subscriptions describe "${SUBSCRIPTION_NAME}" --quiet >/dev/null 2>&1; then
            if gcloud pubsub subscriptions delete "${SUBSCRIPTION_NAME}" --quiet; then
                log_success "Pub/Sub subscription deleted: ${SUBSCRIPTION_NAME}"
            else
                log_error "Failed to delete Pub/Sub subscription: ${SUBSCRIPTION_NAME}"
            fi
        else
            log_info "Pub/Sub subscription not found: ${SUBSCRIPTION_NAME}"
        fi
    fi
    
    # Delete topic
    if [[ -n "${TOPIC_NAME:-}" ]]; then
        log_info "Deleting Pub/Sub topic: ${TOPIC_NAME}"
        if gcloud pubsub topics describe "${TOPIC_NAME}" --quiet >/dev/null 2>&1; then
            if gcloud pubsub topics delete "${TOPIC_NAME}" --quiet; then
                log_success "Pub/Sub topic deleted: ${TOPIC_NAME}"
            else
                log_error "Failed to delete Pub/Sub topic: ${TOPIC_NAME}"
                return 1
            fi
        else
            log_info "Pub/Sub topic not found: ${TOPIC_NAME}"
        fi
    fi
    
    return 0
}

# Delete Cloud Storage bucket
delete_storage_bucket() {
    if [[ -z "${BUCKET_NAME:-}" ]]; then
        log_warning "Storage bucket name not specified, skipping"
        return 0
    fi
    
    log_info "Deleting Cloud Storage bucket: ${BUCKET_NAME}"
    
    # Check if bucket exists
    if gsutil ls "gs://${BUCKET_NAME}" >/dev/null 2>&1; then
        log_warning "Deleting bucket gs://${BUCKET_NAME} and ALL its contents..."
        
        # Additional confirmation for bucket deletion
        echo "WARNING: This will permanently delete all audit logs and alert data!"
        read -p "Confirm bucket deletion by typing the bucket name: " bucket_confirmation
        
        if [[ "${bucket_confirmation}" != "${BUCKET_NAME}" ]]; then
            log_warning "Bucket name confirmation failed. Skipping bucket deletion."
            log_warning "Manual cleanup required for bucket: gs://${BUCKET_NAME}"
            return 0
        fi
        
        # Delete bucket and all contents
        if gsutil -m rm -r "gs://${BUCKET_NAME}"; then
            log_success "Cloud Storage bucket deleted: ${BUCKET_NAME}"
        else
            log_error "Failed to delete Cloud Storage bucket: ${BUCKET_NAME}"
            return 1
        fi
    else
        log_info "Cloud Storage bucket not found: ${BUCKET_NAME}"
    fi
    
    return 0
}

# Clean up monitoring alert policies
cleanup_monitoring_policies() {
    log_info "Cleaning up monitoring alert policies..."
    
    # List policies with our specific name
    log_info "Searching for 'Privilege Escalation Detection' alert policies..."
    local policies
    policies=$(gcloud alpha monitoring policies list \
        --filter="displayName:'Privilege Escalation Detection'" \
        --format="value(name)" 2>/dev/null || echo "")
    
    if [[ -n "${policies}" ]]; then
        log_warning "Found monitoring alert policies that require manual cleanup:"
        echo "${policies}" | while read -r policy; do
            if [[ -n "${policy}" ]]; then
                echo "  Policy: ${policy}"
                log_info "To delete manually: gcloud alpha monitoring policies delete '${policy}'"
            fi
        done
        echo
        log_warning "Alert policies must be deleted manually from the Cloud Console or CLI"
        log_warning "Navigate to: Cloud Console > Monitoring > Alerting > Policies"
    else
        log_info "No matching alert policies found"
    fi
    
    return 0
}

# Verify resource cleanup
verify_cleanup() {
    log_info "Verifying resource cleanup..."
    
    local cleanup_issues=0
    
    # Check Pub/Sub topic
    if [[ -n "${TOPIC_NAME:-}" ]] && gcloud pubsub topics describe "${TOPIC_NAME}" --quiet >/dev/null 2>&1; then
        log_warning "Pub/Sub topic still exists: ${TOPIC_NAME}"
        ((cleanup_issues++))
    fi
    
    # Check Cloud Function
    if [[ -n "${FUNCTION_NAME:-}" ]] && gcloud functions describe "${FUNCTION_NAME}" --region="${REGION}" --quiet >/dev/null 2>&1; then
        log_warning "Cloud Function still exists: ${FUNCTION_NAME}"
        ((cleanup_issues++))
    fi
    
    # Check log sink
    if [[ -n "${SINK_NAME:-}" ]] && gcloud logging sinks describe "${SINK_NAME}" --quiet >/dev/null 2>&1; then
        log_warning "Log sink still exists: ${SINK_NAME}"
        ((cleanup_issues++))
    fi
    
    # Check storage bucket
    if [[ -n "${BUCKET_NAME:-}" ]] && gsutil ls "gs://${BUCKET_NAME}" >/dev/null 2>&1; then
        log_warning "Storage bucket still exists: gs://${BUCKET_NAME}"
        ((cleanup_issues++))
    fi
    
    if [[ ${cleanup_issues} -eq 0 ]]; then
        log_success "All resources cleaned up successfully"
    else
        log_warning "${cleanup_issues} resources may require manual cleanup"
    fi
    
    return 0
}

# Clean up environment file
cleanup_environment_file() {
    local env_file="${SCRIPT_DIR}/.deploy_env"
    
    if [[ -f "${env_file}" ]]; then
        log_info "Removing environment file: ${env_file}"
        if rm "${env_file}"; then
            log_success "Environment file removed"
        else
            log_warning "Failed to remove environment file: ${env_file}"
        fi
    fi
    
    return 0
}

# List remaining resources for manual cleanup
list_manual_cleanup() {
    echo
    echo "=== Manual Cleanup Checklist ==="
    echo "Please verify the following have been removed:"
    echo
    echo "1. Cloud Monitoring Alert Policies:"
    echo "   - Go to Cloud Console > Monitoring > Alerting"
    echo "   - Look for 'Privilege Escalation Detection' policies"
    echo "   - Delete any remaining policies"
    echo
    echo "2. Verify no orphaned IAM bindings:"
    echo "   - Check for any remaining IAM bindings to deleted service accounts"
    echo "   - Review project IAM policies for any test roles"
    echo
    echo "3. Check for any remaining custom metrics:"
    echo "   - Cloud Console > Monitoring > Metrics Explorer"
    echo "   - Look for 'custom.googleapis.com/security/privilege_escalation'"
    echo
    echo "4. Review Cloud Logging for any remaining sinks:"
    echo "   - Cloud Console > Logging > Logs Router"
    echo "   - Verify no privilege escalation sinks remain"
    echo
    
    return 0
}

# Main destruction function
main() {
    log_info "Starting Privilege Escalation Monitoring destruction..."
    log_info "Log file: ${LOG_FILE}"
    
    # Load environment and confirm
    load_environment
    confirm_destruction
    
    # Execute cleanup steps in reverse dependency order
    log_info "Beginning resource cleanup..."
    
    cleanup_test_roles
    delete_cloud_function
    delete_log_sink
    delete_pubsub_resources
    delete_storage_bucket
    cleanup_monitoring_policies
    verify_cleanup
    cleanup_environment_file
    
    # Completion summary
    log_success "Privilege Escalation Monitoring destruction completed!"
    echo
    echo "=== Destruction Summary ==="
    echo "Project ID: ${PROJECT_ID}"
    echo "Region: ${REGION}"
    echo "Destroyed resources:"
    echo "  ✓ Cloud Function: ${FUNCTION_NAME:-<unknown>}"
    echo "  ✓ Log Sink: ${SINK_NAME:-<unknown>}"
    echo "  ✓ Pub/Sub Topic: ${TOPIC_NAME:-<unknown>}"
    echo "  ✓ Pub/Sub Subscription: ${SUBSCRIPTION_NAME:-<unknown>}"
    echo "  ✓ Storage Bucket: ${BUCKET_NAME:-<unknown>}"
    echo
    
    list_manual_cleanup
    
    echo "=== Important Notes ==="
    echo "- All audit log data has been permanently deleted"
    echo "- Monitor your Google Cloud billing to ensure no unexpected charges"
    echo "- Alert policies may require manual cleanup from Cloud Console"
    echo "- This script can be run again safely if needed"
    echo
    log_info "Destruction process completed. Check log file for details: ${LOG_FILE}"
}

# Run main function
main "$@"