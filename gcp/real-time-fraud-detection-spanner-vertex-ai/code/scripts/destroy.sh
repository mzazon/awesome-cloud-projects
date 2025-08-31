#!/bin/bash

# Real-time Fraud Detection with Spanner and Vertex AI - Cleanup Script
# This script safely removes all resources created by the deployment script

set -euo pipefail  # Exit on any error, undefined variables, or pipe failures

# Color codes for output formatting
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Script configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly CONFIG_FILE="${SCRIPT_DIR}/.deployment_config"
readonly LOG_FILE="${SCRIPT_DIR}/destroy.log"

# Logging functions
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "${LOG_FILE}"
}

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

# Error handling function
handle_error() {
    log_error "An error occurred during cleanup. Check ${LOG_FILE} for details."
    log_warning "Some resources may need manual cleanup."
    exit 1
}

trap handle_error ERR

# Confirmation prompt
confirm_destruction() {
    echo ""
    echo "=========================================="
    echo "⚠️  RESOURCE DESTRUCTION WARNING ⚠️"
    echo "=========================================="
    echo "This script will permanently delete the following resources:"
    
    if [[ -f "${CONFIG_FILE}" ]]; then
        source "${CONFIG_FILE}"
        echo "  • Cloud Spanner Instance: ${SPANNER_INSTANCE:-N/A}"
        echo "  • Cloud Spanner Database: ${DATABASE_NAME:-N/A}"
        echo "  • Cloud Function: ${FUNCTION_NAME:-N/A}"
        echo "  • Pub/Sub Topic: ${TOPIC_NAME:-N/A}"
        echo "  • Pub/Sub Subscription: ${SUBSCRIPTION_NAME:-N/A}"
        echo "  • Cloud Storage Bucket: ${PROJECT_ID:-N/A}-fraud-detection-data"
        echo "  • Project: ${PROJECT_ID:-N/A}"
    else
        log_warning "Configuration file not found. Manual resource specification required."
        echo "  • All fraud detection resources in current project"
    fi
    
    echo ""
    echo "⚠️  THIS ACTION CANNOT BE UNDONE ⚠️"
    echo ""
    read -p "Are you sure you want to proceed? (yes/no): " -r
    
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        log_info "Cleanup cancelled by user"
        exit 0
    fi
    
    echo ""
    read -p "Type 'DELETE' to confirm resource destruction: " -r
    
    if [[ $REPLY != "DELETE" ]]; then
        log_info "Cleanup cancelled - confirmation not provided"
        exit 0
    fi
    
    log_info "User confirmed resource destruction"
}

# Load configuration
load_configuration() {
    log_info "Loading deployment configuration..."
    
    if [[ -f "${CONFIG_FILE}" ]]; then
        source "${CONFIG_FILE}"
        log_success "Configuration loaded from ${CONFIG_FILE}"
        
        # Validate required variables
        local required_vars=(
            "PROJECT_ID"
            "REGION"
            "SPANNER_INSTANCE"
            "DATABASE_NAME"
            "FUNCTION_NAME"
            "TOPIC_NAME"
            "SUBSCRIPTION_NAME"
        )
        
        for var in "${required_vars[@]}"; do
            if [[ -z "${!var:-}" ]]; then
                log_error "Required variable ${var} not found in configuration"
                exit 1
            fi
        done
        
        # Set gcloud configuration
        gcloud config set project "${PROJECT_ID}" --quiet
        gcloud config set compute/region "${REGION}" --quiet
        
    else
        log_warning "Configuration file not found. Attempting manual resource detection..."
        
        # Try to detect current project
        PROJECT_ID=$(gcloud config get-value project 2>/dev/null || echo "")
        if [[ -z "${PROJECT_ID}" ]]; then
            log_error "No project configured. Please run gcloud config set project PROJECT_ID"
            exit 1
        fi
        
        REGION=$(gcloud config get-value compute/region 2>/dev/null || echo "us-central1")
        
        log_warning "Manual cleanup mode - will attempt to find and delete fraud detection resources"
    fi
    
    log_info "Project: ${PROJECT_ID}"
    log_info "Region: ${REGION}"
}

# Delete Cloud Function
delete_cloud_function() {
    log_info "Deleting Cloud Function..."
    
    if [[ -n "${FUNCTION_NAME:-}" ]]; then
        # Delete specific function
        if gcloud functions describe "${FUNCTION_NAME}" --gen2 --region="${REGION}" --quiet &>/dev/null; then
            log_info "Deleting function: ${FUNCTION_NAME}"
            if gcloud functions delete "${FUNCTION_NAME}" --gen2 --region="${REGION}" --quiet; then
                log_success "✅ Cloud Function deleted: ${FUNCTION_NAME}"
            else
                log_warning "Failed to delete Cloud Function: ${FUNCTION_NAME}"
            fi
        else
            log_info "Cloud Function not found: ${FUNCTION_NAME}"
        fi
    else
        # Try to find and delete fraud detection functions
        log_info "Searching for fraud detection functions..."
        local functions
        functions=$(gcloud functions list --gen2 --region="${REGION}" --filter="name~fraud" --format="value(name)" 2>/dev/null || echo "")
        
        if [[ -n "${functions}" ]]; then
            echo "${functions}" | while read -r function_name; do
                if [[ -n "${function_name}" ]]; then
                    log_info "Deleting function: ${function_name}"
                    gcloud functions delete "${function_name}" --gen2 --region="${REGION}" --quiet || log_warning "Failed to delete ${function_name}"
                fi
            done
        else
            log_info "No fraud detection functions found"
        fi
    fi
    
    log_success "Cloud Function cleanup completed"
}

# Delete Pub/Sub resources
delete_pubsub_resources() {
    log_info "Deleting Pub/Sub resources..."
    
    # Delete subscription first (if configured)
    if [[ -n "${SUBSCRIPTION_NAME:-}" ]]; then
        if gcloud pubsub subscriptions describe "${SUBSCRIPTION_NAME}" --quiet &>/dev/null; then
            log_info "Deleting subscription: ${SUBSCRIPTION_NAME}"
            if gcloud pubsub subscriptions delete "${SUBSCRIPTION_NAME}" --quiet; then
                log_success "✅ Pub/Sub subscription deleted: ${SUBSCRIPTION_NAME}"
            else
                log_warning "Failed to delete subscription: ${SUBSCRIPTION_NAME}"
            fi
        else
            log_info "Subscription not found: ${SUBSCRIPTION_NAME}"
        fi
    else
        # Try to find and delete fraud detection subscriptions
        log_info "Searching for fraud detection subscriptions..."
        local subscriptions
        subscriptions=$(gcloud pubsub subscriptions list --filter="name~fraud" --format="value(name)" 2>/dev/null || echo "")
        
        if [[ -n "${subscriptions}" ]]; then
            echo "${subscriptions}" | while read -r sub_name; do
                if [[ -n "${sub_name}" ]]; then
                    log_info "Deleting subscription: ${sub_name}"
                    gcloud pubsub subscriptions delete "${sub_name}" --quiet || log_warning "Failed to delete ${sub_name}"
                fi
            done
        fi
    fi
    
    # Delete topic (if configured)
    if [[ -n "${TOPIC_NAME:-}" ]]; then
        if gcloud pubsub topics describe "${TOPIC_NAME}" --quiet &>/dev/null; then
            log_info "Deleting topic: ${TOPIC_NAME}"
            if gcloud pubsub topics delete "${TOPIC_NAME}" --quiet; then
                log_success "✅ Pub/Sub topic deleted: ${TOPIC_NAME}"
            else
                log_warning "Failed to delete topic: ${TOPIC_NAME}"
            fi
        else
            log_info "Topic not found: ${TOPIC_NAME}"
        fi
    else
        # Try to find and delete fraud detection topics
        log_info "Searching for fraud detection topics..."
        local topics
        topics=$(gcloud pubsub topics list --filter="name~fraud OR name~transaction" --format="value(name)" 2>/dev/null || echo "")
        
        if [[ -n "${topics}" ]]; then
            echo "${topics}" | while read -r topic_name; do
                if [[ -n "${topic_name}" ]]; then
                    log_info "Deleting topic: ${topic_name}"
                    gcloud pubsub topics delete "${topic_name}" --quiet || log_warning "Failed to delete ${topic_name}"
                fi
            done
        fi
    fi
    
    log_success "Pub/Sub resources cleanup completed"
}

# Delete Spanner resources
delete_spanner_resources() {
    log_info "Deleting Cloud Spanner resources..."
    
    if [[ -n "${SPANNER_INSTANCE:-}" && -n "${DATABASE_NAME:-}" ]]; then
        # Delete database first
        if gcloud spanner databases describe "${DATABASE_NAME}" --instance="${SPANNER_INSTANCE}" --quiet &>/dev/null; then
            log_info "Deleting database: ${DATABASE_NAME}"
            if gcloud spanner databases delete "${DATABASE_NAME}" --instance="${SPANNER_INSTANCE}" --quiet; then
                log_success "✅ Spanner database deleted: ${DATABASE_NAME}"
            else
                log_warning "Failed to delete database: ${DATABASE_NAME}"
            fi
        else
            log_info "Database not found: ${DATABASE_NAME}"
        fi
        
        # Delete instance
        if gcloud spanner instances describe "${SPANNER_INSTANCE}" --quiet &>/dev/null; then
            log_info "Deleting Spanner instance: ${SPANNER_INSTANCE}"
            if gcloud spanner instances delete "${SPANNER_INSTANCE}" --quiet; then
                log_success "✅ Spanner instance deleted: ${SPANNER_INSTANCE}"
            else
                log_warning "Failed to delete Spanner instance: ${SPANNER_INSTANCE}"
            fi
        else
            log_info "Spanner instance not found: ${SPANNER_INSTANCE}"
        fi
    else
        # Try to find and delete fraud detection Spanner resources
        log_info "Searching for fraud detection Spanner instances..."
        local instances
        instances=$(gcloud spanner instances list --filter="name~fraud" --format="value(name)" 2>/dev/null || echo "")
        
        if [[ -n "${instances}" ]]; then
            echo "${instances}" | while read -r instance_name; do
                if [[ -n "${instance_name}" ]]; then
                    log_info "Deleting Spanner instance: ${instance_name}"
                    gcloud spanner instances delete "${instance_name}" --quiet || log_warning "Failed to delete ${instance_name}"
                fi
            done
        else
            log_info "No fraud detection Spanner instances found"
        fi
    fi
    
    log_success "Spanner resources cleanup completed"
}

# Delete Cloud Storage resources
delete_storage_resources() {
    log_info "Deleting Cloud Storage resources..."
    
    local bucket_name="${PROJECT_ID}-fraud-detection-data"
    
    # Check if bucket exists and delete it
    if gsutil ls "gs://${bucket_name}" &>/dev/null; then
        log_info "Deleting storage bucket: gs://${bucket_name}"
        if gsutil -m rm -r "gs://${bucket_name}"; then
            log_success "✅ Storage bucket deleted: gs://${bucket_name}"
        else
            log_warning "Failed to delete storage bucket: gs://${bucket_name}"
        fi
    else
        log_info "Storage bucket not found: gs://${bucket_name}"
    fi
    
    # Also try to find and delete any other fraud detection buckets
    log_info "Searching for other fraud detection storage buckets..."
    local buckets
    buckets=$(gsutil ls -p "${PROJECT_ID}" 2>/dev/null | grep fraud || echo "")
    
    if [[ -n "${buckets}" ]]; then
        echo "${buckets}" | while read -r bucket_uri; do
            if [[ -n "${bucket_uri}" ]]; then
                log_info "Deleting bucket: ${bucket_uri}"
                gsutil -m rm -r "${bucket_uri}" || log_warning "Failed to delete ${bucket_uri}"
            fi
        done
    fi
    
    log_success "Storage resources cleanup completed"
}

# Delete Vertex AI resources
delete_vertex_ai_resources() {
    log_info "Deleting Vertex AI resources..."
    
    # Try to find and delete fraud detection datasets
    log_info "Searching for fraud detection datasets..."
    local access_token
    access_token=$(gcloud auth print-access-token)
    
    local datasets_response
    datasets_response=$(curl -s -H "Authorization: Bearer ${access_token}" \
        "https://${REGION}-aiplatform.googleapis.com/v1/projects/${PROJECT_ID}/locations/${REGION}/datasets" || echo "")
    
    if [[ -n "${datasets_response}" ]] && echo "${datasets_response}" | grep -q "fraud"; then
        log_info "Found fraud detection datasets, attempting cleanup..."
        # Extract dataset names and delete them
        local dataset_names
        dataset_names=$(echo "${datasets_response}" | grep -o '"name":"[^"]*fraud[^"]*"' | cut -d'"' -f4 || echo "")
        
        if [[ -n "${dataset_names}" ]]; then
            echo "${dataset_names}" | while read -r dataset_name; do
                if [[ -n "${dataset_name}" ]]; then
                    log_info "Deleting dataset: ${dataset_name}"
                    curl -s -X DELETE -H "Authorization: Bearer ${access_token}" \
                        "https://${REGION}-aiplatform.googleapis.com/v1/${dataset_name}" || log_warning "Failed to delete ${dataset_name}"
                fi
            done
        fi
    else
        log_info "No fraud detection datasets found"
    fi
    
    log_success "Vertex AI resources cleanup completed"
}

# Clean up local files
cleanup_local_files() {
    log_info "Cleaning up local files..."
    
    local files_to_remove=(
        "${SCRIPT_DIR}/schema.sql"
        "${SCRIPT_DIR}/insert_users.sql"
        "${SCRIPT_DIR}/training_data.csv"
        "${SCRIPT_DIR}/fraud-detection-function"
    )
    
    for file_path in "${files_to_remove[@]}"; do
        if [[ -e "${file_path}" ]]; then
            log_info "Removing: ${file_path}"
            rm -rf "${file_path}"
            log_success "✅ Removed: ${file_path}"
        fi
    done
    
    # Remove configuration file last
    if [[ -f "${CONFIG_FILE}" ]]; then
        log_info "Removing configuration file: ${CONFIG_FILE}"
        rm -f "${CONFIG_FILE}"
        log_success "✅ Configuration file removed"
    fi
    
    log_success "Local files cleanup completed"
}

# Verify cleanup completion
verify_cleanup() {
    log_info "Verifying resource cleanup..."
    
    local cleanup_issues=()
    
    # Check Spanner instances
    if [[ -n "${SPANNER_INSTANCE:-}" ]]; then
        if gcloud spanner instances describe "${SPANNER_INSTANCE}" --quiet &>/dev/null; then
            cleanup_issues+=("Spanner instance still exists: ${SPANNER_INSTANCE}")
        fi
    fi
    
    # Check Cloud Functions
    if [[ -n "${FUNCTION_NAME:-}" ]]; then
        if gcloud functions describe "${FUNCTION_NAME}" --gen2 --region="${REGION}" --quiet &>/dev/null; then
            cleanup_issues+=("Cloud Function still exists: ${FUNCTION_NAME}")
        fi
    fi
    
    # Check Pub/Sub topics
    if [[ -n "${TOPIC_NAME:-}" ]]; then
        if gcloud pubsub topics describe "${TOPIC_NAME}" --quiet &>/dev/null; then
            cleanup_issues+=("Pub/Sub topic still exists: ${TOPIC_NAME}")
        fi
    fi
    
    # Check storage buckets
    if gsutil ls "gs://${PROJECT_ID}-fraud-detection-data" &>/dev/null; then
        cleanup_issues+=("Storage bucket still exists: gs://${PROJECT_ID}-fraud-detection-data")
    fi
    
    if [[ ${#cleanup_issues[@]} -gt 0 ]]; then
        log_warning "Some resources may not have been fully cleaned up:"
        for issue in "${cleanup_issues[@]}"; do
            log_warning "  - ${issue}"
        done
        log_warning "Please check these resources manually in the Google Cloud Console"
    else
        log_success "✅ All resources appear to have been cleaned up successfully"
    fi
}

# Display cleanup summary
display_cleanup_summary() {
    echo ""
    echo "=========================================="
    echo "🧹 CLEANUP SUMMARY"
    echo "=========================================="
    
    if [[ -f "${CONFIG_FILE}" ]]; then
        source "${CONFIG_FILE}" 2>/dev/null || true
    fi
    
    echo "Project: ${PROJECT_ID:-Unknown}"
    echo "Region: ${REGION:-Unknown}"
    echo ""
    echo "Resources processed for deletion:"
    echo "  ✅ Cloud Functions"
    echo "  ✅ Pub/Sub Topics and Subscriptions"
    echo "  ✅ Cloud Spanner Instances and Databases"
    echo "  ✅ Cloud Storage Buckets"
    echo "  ✅ Vertex AI Datasets"
    echo "  ✅ Local Files and Configuration"
    echo ""
    echo "Cleanup log: ${LOG_FILE}"
    echo ""
    echo "If you encounter any billing charges after cleanup,"
    echo "please check the Google Cloud Console for any"
    echo "remaining resources that may need manual deletion."
    echo "=========================================="
}

# Main cleanup function
main() {
    log_info "Starting fraud detection system cleanup..."
    log_info "Cleanup log: ${LOG_FILE}"
    
    confirm_destruction
    load_configuration
    delete_cloud_function
    delete_pubsub_resources
    delete_spanner_resources
    delete_storage_resources
    delete_vertex_ai_resources
    cleanup_local_files
    verify_cleanup
    display_cleanup_summary
    
    log_success "Cleanup completed successfully at $(date)"
}

# Execute main function with error handling
if ! main "$@"; then
    log_error "Cleanup failed. Some resources may require manual deletion."
    exit 1
fi