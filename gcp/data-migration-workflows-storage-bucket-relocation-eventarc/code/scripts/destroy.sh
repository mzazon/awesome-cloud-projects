#!/bin/bash
# GCP Data Migration Workflows with Storage Bucket Relocation and Eventarc - Cleanup Script
# This script removes all resources created by the deployment script

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING:${NC} $1"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1"
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO:${NC} $1"
}

# Check if running in dry-run mode
DRY_RUN=false
FORCE_DELETE=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            warn "Running in DRY-RUN mode - no resources will be deleted"
            shift
            ;;
        --force)
            FORCE_DELETE=true
            warn "Running in FORCE mode - skipping confirmation prompts"
            shift
            ;;
        *)
            error "Unknown option: $1"
            echo "Usage: $0 [--dry-run] [--force]"
            exit 1
            ;;
    esac
done

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if gcloud CLI is installed
    if ! command -v gcloud &> /dev/null; then
        error "gcloud CLI is not installed"
        exit 1
    fi
    
    # Check if gsutil is available
    if ! command -v gsutil &> /dev/null; then
        error "gsutil is not available"
        exit 1
    fi
    
    # Check if bq is available
    if ! command -v bq &> /dev/null; then
        error "bq (BigQuery CLI) is not available"
        exit 1
    fi
    
    # Check if user is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q "@"; then
        error "Please authenticate with gcloud: gcloud auth login"
        exit 1
    fi
    
    # Check if project is set
    PROJECT_ID=$(gcloud config get-value project 2>/dev/null)
    if [[ -z "${PROJECT_ID}" ]]; then
        error "Please set a GCP project: gcloud config set project PROJECT_ID"
        exit 1
    fi
    
    log "Prerequisites check passed ✅"
}

# Function to set environment variables
set_environment_variables() {
    log "Setting environment variables..."
    
    export PROJECT_ID=$(gcloud config get-value project)
    export REGION="us-central1"
    export SOURCE_REGION="us-west1"
    export DEST_REGION="us-east1"
    
    # Try to detect the bucket name from existing resources
    export SOURCE_BUCKET=$(gcloud storage buckets list --filter="name~migration-source" --format="value(name)" | head -1 | sed 's/gs:\/\///')
    
    if [[ -z "${SOURCE_BUCKET}" ]]; then
        warn "Could not automatically detect source bucket. You may need to specify it manually."
        export SOURCE_BUCKET="migration-source-unknown"
    fi
    
    info "Project ID: ${PROJECT_ID}"
    info "Region: ${REGION}"
    info "Source Bucket: ${SOURCE_BUCKET}"
    
    log "Environment variables configured ✅"
}

# Function to confirm destruction
confirm_destruction() {
    if [[ "$FORCE_DELETE" == "true" ]]; then
        info "Skipping confirmation (--force mode)"
        return 0
    fi
    
    warn "This will permanently delete the following resources:"
    echo "  - Cloud Storage bucket: gs://${SOURCE_BUCKET}"
    echo "  - Cloud Functions: pre-migration-validator, migration-progress-monitor, post-migration-validator"
    echo "  - Eventarc triggers: bucket-admin-trigger, object-event-trigger"
    echo "  - BigQuery dataset: migration_audit"
    echo "  - Audit log sink: migration-audit-sink"
    echo "  - Service account: migration-automation@${PROJECT_ID}.iam.gserviceaccount.com"
    echo "  - Pub/Sub topics: pre-migration-topic"
    echo "  - Cloud Monitoring alert policies"
    echo ""
    
    read -p "Are you sure you want to continue? (yes/no): " -r
    if [[ ! $REPLY =~ ^[Yy]es$ ]]; then
        info "Operation cancelled by user"
        exit 0
    fi
    
    log "Destruction confirmed ✅"
}

# Function to delete Cloud Storage bucket
delete_storage_bucket() {
    log "Deleting Cloud Storage bucket..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "DRY-RUN: Would delete bucket gs://${SOURCE_BUCKET}"
        return 0
    fi
    
    if gsutil ls gs://${SOURCE_BUCKET} &>/dev/null; then
        info "Deleting all objects in bucket..."
        gsutil -m rm -r gs://${SOURCE_BUCKET}/** 2>/dev/null || true
        
        info "Deleting bucket..."
        gsutil rb gs://${SOURCE_BUCKET} || warn "Failed to delete bucket (may not exist)"
        
        info "✅ Storage bucket deleted"
    else
        info "Storage bucket not found, skipping deletion"
    fi
    
    log "Storage bucket cleanup completed ✅"
}

# Function to delete Cloud Functions
delete_cloud_functions() {
    log "Deleting Cloud Functions..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "DRY-RUN: Would delete Cloud Functions"
        return 0
    fi
    
    local functions=("pre-migration-validator" "migration-progress-monitor" "post-migration-validator")
    
    for func in "${functions[@]}"; do
        if gcloud functions describe ${func} --region=${REGION} &>/dev/null; then
            info "Deleting function: ${func}"
            gcloud functions delete ${func} --region=${REGION} --quiet || warn "Failed to delete function ${func}"
        else
            info "Function ${func} not found, skipping deletion"
        fi
    done
    
    log "Cloud Functions cleanup completed ✅"
}

# Function to delete Eventarc triggers
delete_eventarc_triggers() {
    log "Deleting Eventarc triggers..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "DRY-RUN: Would delete Eventarc triggers"
        return 0
    fi
    
    local triggers=("bucket-admin-trigger" "object-event-trigger")
    
    for trigger in "${triggers[@]}"; do
        if gcloud eventarc triggers describe ${trigger} --location=${REGION} &>/dev/null; then
            info "Deleting trigger: ${trigger}"
            gcloud eventarc triggers delete ${trigger} --location=${REGION} --quiet || warn "Failed to delete trigger ${trigger}"
        else
            info "Trigger ${trigger} not found, skipping deletion"
        fi
    done
    
    log "Eventarc triggers cleanup completed ✅"
}

# Function to delete BigQuery dataset
delete_bigquery_dataset() {
    log "Deleting BigQuery dataset..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "DRY-RUN: Would delete BigQuery dataset migration_audit"
        return 0
    fi
    
    if bq ls -d ${PROJECT_ID}:migration_audit &>/dev/null; then
        info "Deleting BigQuery dataset: migration_audit"
        bq rm -r -f ${PROJECT_ID}:migration_audit || warn "Failed to delete BigQuery dataset"
        info "✅ BigQuery dataset deleted"
    else
        info "BigQuery dataset not found, skipping deletion"
    fi
    
    log "BigQuery dataset cleanup completed ✅"
}

# Function to delete audit log sink
delete_audit_log_sink() {
    log "Deleting audit log sink..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "DRY-RUN: Would delete audit log sink migration-audit-sink"
        return 0
    fi
    
    if gcloud logging sinks describe migration-audit-sink &>/dev/null; then
        info "Deleting audit log sink: migration-audit-sink"
        gcloud logging sinks delete migration-audit-sink --quiet || warn "Failed to delete audit log sink"
        info "✅ Audit log sink deleted"
    else
        info "Audit log sink not found, skipping deletion"
    fi
    
    log "Audit log sink cleanup completed ✅"
}

# Function to delete Pub/Sub topics
delete_pubsub_topics() {
    log "Deleting Pub/Sub topics..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "DRY-RUN: Would delete Pub/Sub topics"
        return 0
    fi
    
    local topics=("pre-migration-topic")
    
    for topic in "${topics[@]}"; do
        if gcloud pubsub topics describe ${topic} &>/dev/null; then
            info "Deleting topic: ${topic}"
            gcloud pubsub topics delete ${topic} --quiet || warn "Failed to delete topic ${topic}"
        else
            info "Topic ${topic} not found, skipping deletion"
        fi
    done
    
    log "Pub/Sub topics cleanup completed ✅"
}

# Function to delete monitoring alert policies
delete_monitoring_alerts() {
    log "Deleting Cloud Monitoring alert policies..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "DRY-RUN: Would delete monitoring alert policies"
        return 0
    fi
    
    # List and delete migration-related alert policies
    local policies=$(gcloud alpha monitoring policies list --filter="displayName~'Bucket Migration'" --format="value(name)" 2>/dev/null || true)
    
    if [[ -n "${policies}" ]]; then
        for policy in ${policies}; do
            info "Deleting alert policy: ${policy}"
            gcloud alpha monitoring policies delete ${policy} --quiet || warn "Failed to delete alert policy ${policy}"
        done
        info "✅ Alert policies deleted"
    else
        info "No migration-related alert policies found"
    fi
    
    log "Monitoring alert policies cleanup completed ✅"
}

# Function to delete service account
delete_service_account() {
    log "Deleting service account..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "DRY-RUN: Would delete service account migration-automation@${PROJECT_ID}.iam.gserviceaccount.com"
        return 0
    fi
    
    local service_account="migration-automation@${PROJECT_ID}.iam.gserviceaccount.com"
    
    if gcloud iam service-accounts describe ${service_account} &>/dev/null; then
        info "Removing IAM policy bindings..."
        
        # Remove IAM policy bindings
        local roles=(
            "roles/storage.admin"
            "roles/logging.viewer"
            "roles/monitoring.metricWriter"
            "roles/bigquery.dataEditor"
            "roles/pubsub.publisher"
        )
        
        for role in "${roles[@]}"; do
            gcloud projects remove-iam-policy-binding ${PROJECT_ID} \
                --member="serviceAccount:${service_account}" \
                --role="${role}" \
                --quiet 2>/dev/null || true
        done
        
        info "Deleting service account: ${service_account}"
        gcloud iam service-accounts delete ${service_account} --quiet || warn "Failed to delete service account"
        info "✅ Service account deleted"
    else
        info "Service account not found, skipping deletion"
    fi
    
    log "Service account cleanup completed ✅"
}

# Function to clean up local files
cleanup_local_files() {
    log "Cleaning up local files..."
    
    local script_dir=$(dirname "$0")
    local functions_dir="${script_dir}/../functions"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "DRY-RUN: Would clean up local files"
        return 0
    fi
    
    # Remove function source directories
    if [[ -d "${functions_dir}" ]]; then
        info "Removing function source directories..."
        rm -rf "${functions_dir}"
    fi
    
    # Remove any temporary files
    rm -f alert-policy.json 2>/dev/null || true
    rm -f critical-data.txt archive-data.txt application.log 2>/dev/null || true
    
    log "Local files cleanup completed ✅"
}

# Function to verify cleanup
verify_cleanup() {
    log "Verifying cleanup..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "DRY-RUN: Would verify cleanup"
        return 0
    fi
    
    local cleanup_success=true
    
    # Check if bucket still exists
    if gsutil ls gs://${SOURCE_BUCKET} &>/dev/null; then
        warn "❌ Storage bucket still exists: gs://${SOURCE_BUCKET}"
        cleanup_success=false
    else
        info "✅ Storage bucket successfully removed"
    fi
    
    # Check Cloud Functions
    local functions=("pre-migration-validator" "migration-progress-monitor" "post-migration-validator")
    for func in "${functions[@]}"; do
        if gcloud functions describe ${func} --region=${REGION} &>/dev/null; then
            warn "❌ Cloud Function still exists: ${func}"
            cleanup_success=false
        else
            info "✅ Cloud Function successfully removed: ${func}"
        fi
    done
    
    # Check BigQuery dataset
    if bq ls -d ${PROJECT_ID}:migration_audit &>/dev/null; then
        warn "❌ BigQuery dataset still exists: migration_audit"
        cleanup_success=false
    else
        info "✅ BigQuery dataset successfully removed"
    fi
    
    # Check service account
    if gcloud iam service-accounts describe migration-automation@${PROJECT_ID}.iam.gserviceaccount.com &>/dev/null; then
        warn "❌ Service account still exists: migration-automation@${PROJECT_ID}.iam.gserviceaccount.com"
        cleanup_success=false
    else
        info "✅ Service account successfully removed"
    fi
    
    if [[ "$cleanup_success" == "true" ]]; then
        log "Cleanup verification passed ✅"
    else
        warn "Some resources may not have been fully cleaned up"
        warn "Please review the warnings above and manually clean up any remaining resources"
    fi
}

# Function to display cleanup summary
display_cleanup_summary() {
    log "Cleanup Summary"
    echo "=========================="
    echo "Project ID: ${PROJECT_ID}"
    echo "Region: ${REGION}"
    echo ""
    echo "Removed Resources:"
    echo "  - Cloud Storage bucket: gs://${SOURCE_BUCKET}"
    echo "  - Cloud Functions (3 functions)"
    echo "  - Eventarc triggers (2 triggers)"
    echo "  - BigQuery dataset: migration_audit"
    echo "  - Audit log sink: migration-audit-sink"
    echo "  - Service account: migration-automation@${PROJECT_ID}.iam.gserviceaccount.com"
    echo "  - Pub/Sub topics: pre-migration-topic"
    echo "  - Cloud Monitoring alert policies"
    echo "  - Local function source files"
    echo ""
    echo "Cleanup completed! All resources have been removed."
    echo "=========================="
}

# Function to handle cleanup errors
handle_cleanup_errors() {
    if [[ $? -ne 0 ]]; then
        error "Cleanup encountered errors. Some resources may not have been removed."
        error "Please check the output above and manually clean up any remaining resources."
        exit 1
    fi
}

# Main execution flow
main() {
    log "Starting GCP Data Migration Workflows cleanup..."
    
    # Set trap to handle errors
    trap handle_cleanup_errors ERR
    
    check_prerequisites
    set_environment_variables
    confirm_destruction
    
    # Delete resources in reverse order of creation
    delete_monitoring_alerts
    delete_audit_log_sink
    delete_eventarc_triggers
    delete_cloud_functions
    delete_pubsub_topics
    delete_bigquery_dataset
    delete_storage_bucket
    delete_service_account
    cleanup_local_files
    
    verify_cleanup
    display_cleanup_summary
    
    log "Cleanup completed successfully! 🎉"
}

# Run main function
main "$@"