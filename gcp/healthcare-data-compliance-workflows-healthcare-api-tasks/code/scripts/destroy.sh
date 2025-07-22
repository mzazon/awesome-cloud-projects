#!/bin/bash

# Healthcare Data Compliance Workflows - Cleanup Script
# This script removes all resources created by the deployment script
# Use with caution - this will permanently delete all healthcare compliance infrastructure

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✅${NC} $1"
}

warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️${NC} $1"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ❌${NC} $1"
}

# Check if script is run with --dry-run flag
DRY_RUN=false
FORCE=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            log "Running in dry-run mode - no resources will be deleted"
            shift
            ;;
        --force)
            FORCE=true
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [OPTIONS]"
            echo "Options:"
            echo "  --dry-run    Show what would be deleted without actually deleting"
            echo "  --force      Skip confirmation prompts"
            echo "  -h, --help   Show this help message"
            exit 0
            ;;
        *)
            error "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Function to execute commands with dry-run support
execute() {
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "[DRY-RUN] $*"
    else
        "$@"
    fi
}

# Function to load environment variables from deployment
load_environment() {
    log "Loading environment variables from deployment..."
    
    if [[ -f ".env.deploy" ]]; then
        # Source the environment file
        set -a  # automatically export all variables
        source .env.deploy
        set +a
        
        log "Environment loaded from .env.deploy:"
        log "  Project ID: ${PROJECT_ID}"
        log "  Region: ${REGION}"
        log "  Dataset ID: ${DATASET_ID}"
        log "  FHIR Store ID: ${FHIR_STORE_ID}"
        log "  Bucket Name: ${BUCKET_NAME}"
        
        success "Environment variables loaded successfully"
    else
        warning ".env.deploy file not found - attempting to use current environment"
        
        # Check if required variables are set
        if [[ -z "${PROJECT_ID:-}" ]]; then
            PROJECT_ID=$(gcloud config get-value project 2>/dev/null || echo "")
            if [[ -z "$PROJECT_ID" ]]; then
                error "PROJECT_ID not set and no .env.deploy file found"
                error "Please set PROJECT_ID environment variable or run from deployment directory"
                exit 1
            fi
        fi
        
        # Set default values for missing variables
        REGION="${REGION:-us-central1}"
        LOCATION="${LOCATION:-us-central1}"
        
        warning "Some environment variables may be missing - cleanup may be incomplete"
    fi
}

# Function to confirm deletion
confirm_deletion() {
    if [[ "$FORCE" == "true" || "$DRY_RUN" == "true" ]]; then
        return 0
    fi
    
    echo ""
    warning "⚠️  DESTRUCTIVE OPERATION WARNING ⚠️"
    echo "This will permanently delete all healthcare compliance infrastructure including:"
    echo "• Healthcare datasets and FHIR stores (including all medical data)"
    echo "• Cloud Functions and their source code"
    echo "• Cloud Storage buckets and all compliance artifacts"
    echo "• BigQuery datasets and audit trail data"
    echo "• Pub/Sub topics and subscriptions"
    echo "• Cloud Tasks queues and pending tasks"
    echo "• All associated logs and monitoring data"
    echo ""
    echo "Project: ${PROJECT_ID}"
    echo "Region: ${REGION}"
    echo ""
    warning "This action cannot be undone!"
    echo ""
    
    read -p "Are you sure you want to proceed? (type 'DELETE' to confirm): " confirmation
    
    if [[ "$confirmation" != "DELETE" ]]; then
        log "Deletion cancelled by user"
        exit 0
    fi
    
    log "Deletion confirmed. Proceeding with resource cleanup..."
}

# Function to delete Cloud Functions
delete_cloud_functions() {
    log "Deleting Cloud Functions..."
    
    # Delete main compliance function
    if [[ -n "${FUNCTION_NAME:-}" ]]; then
        log "Deleting compliance processing function: ${FUNCTION_NAME}"
        if gcloud functions describe "${FUNCTION_NAME}" --region="${REGION}" &>/dev/null; then
            execute gcloud functions delete "${FUNCTION_NAME}" \
                --region="${REGION}" \
                --quiet
            success "Deleted function: ${FUNCTION_NAME}"
        else
            warning "Function ${FUNCTION_NAME} not found or already deleted"
        fi
    fi
    
    # Delete audit function
    if [[ -n "${RANDOM_SUFFIX:-}" ]]; then
        AUDIT_FUNCTION_NAME="compliance-audit-${RANDOM_SUFFIX}"
        log "Deleting compliance audit function: ${AUDIT_FUNCTION_NAME}"
        if gcloud functions describe "${AUDIT_FUNCTION_NAME}" --region="${REGION}" &>/dev/null; then
            execute gcloud functions delete "${AUDIT_FUNCTION_NAME}" \
                --region="${REGION}" \
                --quiet
            success "Deleted function: ${AUDIT_FUNCTION_NAME}"
        else
            warning "Function ${AUDIT_FUNCTION_NAME} not found or already deleted"
        fi
    fi
    
    # Clean up function source directories
    if [[ -d "compliance-function" ]]; then
        execute rm -rf compliance-function
        success "Removed compliance-function directory"
    fi
    
    if [[ -d "audit-function" ]]; then
        execute rm -rf audit-function
        success "Removed audit-function directory"
    fi
    
    success "Cloud Functions cleanup completed"
}

# Function to delete Cloud Tasks queue
delete_task_queue() {
    log "Deleting Cloud Tasks queue..."
    
    if [[ -n "${TASK_QUEUE_NAME:-}" ]]; then
        log "Deleting task queue: ${TASK_QUEUE_NAME}"
        if gcloud tasks queues describe "${TASK_QUEUE_NAME}" --location="${LOCATION}" &>/dev/null; then
            execute gcloud tasks queues delete "${TASK_QUEUE_NAME}" \
                --location="${LOCATION}" \
                --quiet
            success "Deleted task queue: ${TASK_QUEUE_NAME}"
        else
            warning "Task queue ${TASK_QUEUE_NAME} not found or already deleted"
        fi
    else
        warning "TASK_QUEUE_NAME not set - skipping task queue deletion"
    fi
    
    success "Cloud Tasks cleanup completed"
}

# Function to delete Pub/Sub resources
delete_pubsub_resources() {
    log "Deleting Pub/Sub resources..."
    
    # Delete subscription first
    log "Deleting Pub/Sub subscription: fhir-events-sub"
    if gcloud pubsub subscriptions describe "fhir-events-sub" &>/dev/null; then
        execute gcloud pubsub subscriptions delete "fhir-events-sub" --quiet
        success "Deleted subscription: fhir-events-sub"
    else
        warning "Subscription fhir-events-sub not found or already deleted"
    fi
    
    # Delete topic
    if [[ -n "${TOPIC_NAME:-}" ]]; then
        log "Deleting Pub/Sub topic: ${TOPIC_NAME}"
        if gcloud pubsub topics describe "${TOPIC_NAME}" &>/dev/null; then
            execute gcloud pubsub topics delete "${TOPIC_NAME}" --quiet
            success "Deleted topic: ${TOPIC_NAME}"
        else
            warning "Topic ${TOPIC_NAME} not found or already deleted"
        fi
    else
        warning "TOPIC_NAME not set - skipping topic deletion"
    fi
    
    success "Pub/Sub resources cleanup completed"
}

# Function to delete Cloud Storage bucket
delete_storage_bucket() {
    log "Deleting Cloud Storage bucket..."
    
    if [[ -n "${BUCKET_NAME:-}" ]]; then
        log "Deleting storage bucket: gs://${BUCKET_NAME}"
        if gsutil ls "gs://${BUCKET_NAME}" &>/dev/null; then
            # First, remove all objects in the bucket
            log "Removing all objects from bucket..."
            execute gsutil -m rm -r "gs://${BUCKET_NAME}/*" || true
            
            # Then remove the bucket itself
            execute gsutil rb "gs://${BUCKET_NAME}"
            success "Deleted storage bucket: gs://${BUCKET_NAME}"
        else
            warning "Storage bucket gs://${BUCKET_NAME} not found or already deleted"
        fi
    else
        warning "BUCKET_NAME not set - skipping storage bucket deletion"
    fi
    
    success "Cloud Storage cleanup completed"
}

# Function to delete BigQuery dataset
delete_bigquery_dataset() {
    log "Deleting BigQuery dataset..."
    
    log "Deleting BigQuery dataset: healthcare_compliance"
    if bq ls -d "${PROJECT_ID}:healthcare_compliance" &>/dev/null; then
        execute bq rm -r -f "${PROJECT_ID}:healthcare_compliance"
        success "Deleted BigQuery dataset: healthcare_compliance"
    else
        warning "BigQuery dataset healthcare_compliance not found or already deleted"
    fi
    
    success "BigQuery cleanup completed"
}

# Function to delete Healthcare API resources
delete_healthcare_resources() {
    log "Deleting Healthcare API resources..."
    
    # Delete FHIR store first
    if [[ -n "${FHIR_STORE_ID:-}" && -n "${DATASET_ID:-}" ]]; then
        log "Deleting FHIR store: ${FHIR_STORE_ID}"
        if gcloud healthcare fhir-stores describe "${FHIR_STORE_ID}" \
            --dataset="${DATASET_ID}" \
            --location="${LOCATION}" &>/dev/null; then
            execute gcloud healthcare fhir-stores delete "${FHIR_STORE_ID}" \
                --dataset="${DATASET_ID}" \
                --location="${LOCATION}" \
                --quiet
            success "Deleted FHIR store: ${FHIR_STORE_ID}"
        else
            warning "FHIR store ${FHIR_STORE_ID} not found or already deleted"
        fi
    else
        warning "FHIR_STORE_ID or DATASET_ID not set - skipping FHIR store deletion"
    fi
    
    # Delete healthcare dataset
    if [[ -n "${DATASET_ID:-}" ]]; then
        log "Deleting healthcare dataset: ${DATASET_ID}"
        if gcloud healthcare datasets describe "${DATASET_ID}" \
            --location="${LOCATION}" &>/dev/null; then
            execute gcloud healthcare datasets delete "${DATASET_ID}" \
                --location="${LOCATION}" \
                --quiet
            success "Deleted healthcare dataset: ${DATASET_ID}"
        else
            warning "Healthcare dataset ${DATASET_ID} not found or already deleted"
        fi
    else
        warning "DATASET_ID not set - skipping healthcare dataset deletion"
    fi
    
    success "Healthcare API resources cleanup completed"
}

# Function to delete monitoring resources
delete_monitoring_resources() {
    log "Deleting monitoring resources..."
    
    # Delete monitoring policies
    log "Deleting monitoring policies..."
    if [[ "$DRY_RUN" == "false" ]]; then
        # Find and delete any monitoring policies created for this deployment
        POLICY_IDS=$(gcloud alpha monitoring policies list \
            --filter="displayName:'High-Risk Healthcare Data Access'" \
            --format="value(name)" 2>/dev/null || echo "")
        
        if [[ -n "$POLICY_IDS" ]]; then
            while IFS= read -r policy_id; do
                if [[ -n "$policy_id" ]]; then
                    log "Deleting monitoring policy: ${policy_id}"
                    execute gcloud alpha monitoring policies delete "$policy_id" --quiet
                    success "Deleted monitoring policy: ${policy_id}"
                fi
            done <<< "$POLICY_IDS"
        else
            warning "No monitoring policies found for this deployment"
        fi
    fi
    
    success "Monitoring resources cleanup completed"
}

# Function to clean up local files
cleanup_local_files() {
    log "Cleaning up local files..."
    
    # Remove environment file
    if [[ -f ".env.deploy" ]]; then
        execute rm -f .env.deploy
        success "Removed .env.deploy file"
    fi
    
    # Remove any temporary files
    if [[ -f "lifecycle.json" ]]; then
        execute rm -f lifecycle.json
        success "Removed lifecycle.json file"
    fi
    
    # Remove any log files
    if [[ -f "deployment.log" ]]; then
        execute rm -f deployment.log
        success "Removed deployment.log file"
    fi
    
    success "Local files cleanup completed"
}

# Function to verify cleanup
verify_cleanup() {
    log "Verifying resource cleanup..."
    
    local cleanup_errors=0
    
    if [[ "$DRY_RUN" == "false" ]]; then
        # Check Healthcare API resources
        if [[ -n "${DATASET_ID:-}" ]]; then
            if gcloud healthcare datasets describe "${DATASET_ID}" \
                --location="${LOCATION}" &>/dev/null; then
                error "Healthcare dataset ${DATASET_ID} still exists"
                cleanup_errors=$((cleanup_errors + 1))
            fi
        fi
        
        # Check Cloud Functions
        if [[ -n "${FUNCTION_NAME:-}" ]]; then
            if gcloud functions describe "${FUNCTION_NAME}" \
                --region="${REGION}" &>/dev/null; then
                error "Function ${FUNCTION_NAME} still exists"
                cleanup_errors=$((cleanup_errors + 1))
            fi
        fi
        
        # Check Cloud Storage
        if [[ -n "${BUCKET_NAME:-}" ]]; then
            if gsutil ls "gs://${BUCKET_NAME}" &>/dev/null; then
                error "Storage bucket gs://${BUCKET_NAME} still exists"
                cleanup_errors=$((cleanup_errors + 1))
            fi
        fi
        
        # Check BigQuery
        if bq ls -d "${PROJECT_ID}:healthcare_compliance" &>/dev/null; then
            error "BigQuery dataset healthcare_compliance still exists"
            cleanup_errors=$((cleanup_errors + 1))
        fi
        
        # Check Pub/Sub
        if [[ -n "${TOPIC_NAME:-}" ]]; then
            if gcloud pubsub topics describe "${TOPIC_NAME}" &>/dev/null; then
                error "Pub/Sub topic ${TOPIC_NAME} still exists"
                cleanup_errors=$((cleanup_errors + 1))
            fi
        fi
        
        if [[ $cleanup_errors -eq 0 ]]; then
            success "All resources have been successfully cleaned up"
        else
            error "Cleanup verification failed - ${cleanup_errors} resources still exist"
            error "You may need to manually delete remaining resources"
            return 1
        fi
    else
        success "Cleanup verification skipped in dry-run mode"
    fi
}

# Function to display cleanup summary
display_cleanup_summary() {
    log "Cleanup Summary:"
    echo "================"
    echo "Project ID: ${PROJECT_ID}"
    echo "Region: ${REGION}"
    echo ""
    echo "Resources cleaned up:"
    echo "• Healthcare Dataset: ${DATASET_ID:-'N/A'}"
    echo "• FHIR Store: ${FHIR_STORE_ID:-'N/A'}"
    echo "• Cloud Functions: ${FUNCTION_NAME:-'N/A'}, compliance-audit-${RANDOM_SUFFIX:-'N/A'}"
    echo "• Cloud Storage: gs://${BUCKET_NAME:-'N/A'}"
    echo "• Pub/Sub Topic: ${TOPIC_NAME:-'N/A'}"
    echo "• Task Queue: ${TASK_QUEUE_NAME:-'N/A'}"
    echo "• BigQuery Dataset: healthcare_compliance"
    echo "• Monitoring policies and notification channels"
    echo ""
    
    if [[ "$DRY_RUN" == "false" ]]; then
        success "Healthcare Data Compliance Workflows cleanup completed successfully!"
        echo ""
        warning "Note: Some logs and audit trails may remain in Cloud Logging"
        warning "Review and clean up any remaining logs if needed for complete cleanup"
    else
        log "Dry-run completed - no resources were actually deleted"
    fi
}

# Main cleanup function
main() {
    log "Starting Healthcare Data Compliance Workflows cleanup..."
    
    # Load environment variables
    load_environment
    
    # Confirm deletion (unless in dry-run mode)
    confirm_deletion
    
    # Delete resources in reverse order of creation
    delete_monitoring_resources
    delete_cloud_functions
    delete_task_queue
    delete_bigquery_dataset
    delete_storage_bucket
    delete_pubsub_resources
    delete_healthcare_resources
    
    # Clean up local files
    cleanup_local_files
    
    # Verify cleanup
    verify_cleanup
    
    # Display summary
    display_cleanup_summary
    
    if [[ "$DRY_RUN" == "false" ]]; then
        log "Cleanup completed successfully!"
        log "All healthcare compliance infrastructure has been removed."
    fi
}

# Error handling
trap 'error "Cleanup failed on line $LINENO"; exit 1' ERR

# Run main function
main "$@"