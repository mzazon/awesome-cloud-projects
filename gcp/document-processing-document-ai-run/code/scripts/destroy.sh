#!/bin/bash

# Document Processing Workflows with Document AI and Cloud Run - Cleanup Script
# This script removes all infrastructure created for the document processing pipeline
# including Google Cloud Document AI, Cloud Run, Pub/Sub, and Cloud Storage resources

set -e  # Exit on any error
set -u  # Exit on undefined variables

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

# Script metadata
SCRIPT_NAME="GCP Document Processing Cleanup"
SCRIPT_VERSION="1.0"
CLEANUP_START_TIME=$(date)

log_info "Starting ${SCRIPT_NAME} v${SCRIPT_VERSION}"
log_info "Cleanup started at: ${CLEANUP_START_TIME}"

# Configuration - try to load from environment or config file
if [[ -n "${PROJECT_ID:-}" ]]; then
    log_info "Using PROJECT_ID from environment: ${PROJECT_ID}"
else
    # Try to load from saved config file
    CONFIG_FILE="/tmp/gcp-docai-config-*.env"
    if ls ${CONFIG_FILE} 1> /dev/null 2>&1; then
        LATEST_CONFIG=$(ls -t ${CONFIG_FILE} | head -n1)
        log_info "Loading configuration from: ${LATEST_CONFIG}"
        source "${LATEST_CONFIG}"
    else
        log_error "PROJECT_ID not found in environment and no config file found."
        log_error "Please set PROJECT_ID or provide it as an argument:"
        log_error "  export PROJECT_ID=your-project-id"
        log_error "  $0"
        log_error "Or:"
        log_error "  $0 --project your-project-id"
        exit 1
    fi
fi

# Set defaults for other variables if not already set
REGION="${REGION:-us-central1}"
BUCKET_NAME="${BUCKET_NAME:-document-uploads-${PROJECT_ID}}"
PUBSUB_TOPIC="${PUBSUB_TOPIC:-document-processing}"
PUBSUB_SUBSCRIPTION="${PUBSUB_SUBSCRIPTION:-document-worker}"
CLOUDRUN_SERVICE="${CLOUDRUN_SERVICE:-document-processor}"
SERVICE_ACCOUNT_NAME="${SERVICE_ACCOUNT_NAME:-document-processor-sa}"

# Cleanup tracking
CLEANUP_LOG="/tmp/gcp-docai-cleanup-${PROJECT_ID}-$(date +%s).log"
DELETED_RESOURCES=""
FAILED_DELETIONS=""

# Function to log cleanup actions
log_cleanup() {
    local action="$1"
    local resource="$2"
    local status="$3"
    echo "$(date): ${action} ${resource} - ${status}" >> "${CLEANUP_LOG}"
    
    if [[ "${status}" == "SUCCESS" ]]; then
        DELETED_RESOURCES="${DELETED_RESOURCES}\n- ${resource}"
    else
        FAILED_DELETIONS="${FAILED_DELETIONS}\n- ${resource}: ${status}"
    fi
}

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "gcloud CLI is not installed. Please install Google Cloud SDK."
        exit 1
    fi
    
    # Check if gsutil is installed
    if ! command -v gsutil &> /dev/null; then
        log_error "gsutil is not installed. Please install Google Cloud SDK."
        exit 1
    fi
    
    # Check gcloud authentication
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        log_error "No active gcloud authentication found. Please run 'gcloud auth login'."
        exit 1
    fi
    
    # Verify project exists and is accessible
    if ! gcloud projects describe "${PROJECT_ID}" &>/dev/null; then
        log_error "Project ${PROJECT_ID} not found or not accessible."
        exit 1
    fi
    
    # Set gcloud project
    gcloud config set project "${PROJECT_ID}"
    gcloud config set compute/region "${REGION}"
    
    log_success "Prerequisites check completed"
}

# Function to get processor ID if not already set
get_processor_id() {
    if [[ -z "${PROCESSOR_ID:-}" ]]; then
        log_info "Searching for Document AI processors..."
        
        # Try to find processors with common naming patterns
        local search_patterns=("form-parser-" "document-processor")
        
        for pattern in "${search_patterns[@]}"; do
            PROCESSOR_ID=$(gcloud documentai processors list \
                --location="${REGION}" \
                --filter="displayName:${pattern}" \
                --format="value(name)" \
                --project="${PROJECT_ID}" 2>/dev/null | head -n1 | cut -d'/' -f6)
            
            if [[ -n "${PROCESSOR_ID}" ]]; then
                log_info "Found processor ID: ${PROCESSOR_ID}"
                break
            fi
        done
        
        if [[ -z "${PROCESSOR_ID}" ]]; then
            log_warning "No Document AI processor found with expected naming patterns"
            log_warning "You may need to manually delete any remaining processors"
        fi
    fi
}

# Function to list resources before deletion
list_resources() {
    log_info "Scanning for resources to delete..."
    
    echo ""
    echo "============================================="
    echo "         RESOURCES TO BE DELETED"
    echo "============================================="
    echo "Project: ${PROJECT_ID}"
    echo "Region: ${REGION}"
    echo ""
    
    # Check Cloud Run services
    local cloudrun_services
    cloudrun_services=$(gcloud run services list \
        --region="${REGION}" \
        --filter="metadata.name:${CLOUDRUN_SERVICE}" \
        --format="value(metadata.name)" \
        --project="${PROJECT_ID}" 2>/dev/null || echo "")
    
    if [[ -n "${cloudrun_services}" ]]; then
        echo "Cloud Run Services:"
        echo "${cloudrun_services}" | while read -r service; do
            echo "  - ${service}"
        done
    else
        echo "Cloud Run Services: None found"
    fi
    
    # Check Pub/Sub resources
    local pubsub_topics
    pubsub_topics=$(gcloud pubsub topics list \
        --filter="name:projects/${PROJECT_ID}/topics/${PUBSUB_TOPIC}" \
        --format="value(name)" \
        --project="${PROJECT_ID}" 2>/dev/null || echo "")
    
    local pubsub_subscriptions
    pubsub_subscriptions=$(gcloud pubsub subscriptions list \
        --filter="name:projects/${PROJECT_ID}/subscriptions/${PUBSUB_SUBSCRIPTION}" \
        --format="value(name)" \
        --project="${PROJECT_ID}" 2>/dev/null || echo "")
    
    echo ""
    echo "Pub/Sub Resources:"
    if [[ -n "${pubsub_topics}" ]]; then
        echo "  Topics: ${PUBSUB_TOPIC}"
    fi
    if [[ -n "${pubsub_subscriptions}" ]]; then
        echo "  Subscriptions: ${PUBSUB_SUBSCRIPTION}"
    fi
    if [[ -z "${pubsub_topics}" && -z "${pubsub_subscriptions}" ]]; then
        echo "  None found"
    fi
    
    # Check Cloud Storage buckets
    echo ""
    echo "Cloud Storage:"
    if gsutil ls -b "gs://${BUCKET_NAME}" &>/dev/null; then
        echo "  - Bucket: gs://${BUCKET_NAME}"
        local object_count
        object_count=$(gsutil ls -r "gs://${BUCKET_NAME}/**" 2>/dev/null | wc -l || echo "0")
        echo "    Objects: ~${object_count}"
    else
        echo "  - Bucket: None found"
    fi
    
    # Check Document AI processors
    echo ""
    echo "Document AI:"
    if [[ -n "${PROCESSOR_ID:-}" ]]; then
        local processor_info
        processor_info=$(gcloud documentai processors describe "${PROCESSOR_ID}" \
            --location="${REGION}" \
            --format="value(displayName,type)" \
            --project="${PROJECT_ID}" 2>/dev/null || echo "Not found")
        echo "  - Processor: ${PROCESSOR_ID} (${processor_info})"
    else
        local all_processors
        all_processors=$(gcloud documentai processors list \
            --location="${REGION}" \
            --format="value(name,displayName)" \
            --project="${PROJECT_ID}" 2>/dev/null || echo "")
        if [[ -n "${all_processors}" ]]; then
            echo "  - Found processors (may need manual deletion):"
            echo "${all_processors}" | while read -r line; do
                echo "    ${line}"
            done
        else
            echo "  - None found"
        fi
    fi
    
    # Check Service Accounts
    echo ""
    echo "Service Accounts:"
    if gcloud iam service-accounts describe "${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com" \
        --project="${PROJECT_ID}" &>/dev/null; then
        echo "  - ${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
    else
        echo "  - None found"
    fi
    
    echo ""
    echo "============================================="
}

# Function to delete Cloud Run service
delete_cloudrun_service() {
    log_info "Deleting Cloud Run service..."
    
    if gcloud run services describe "${CLOUDRUN_SERVICE}" \
        --region="${REGION}" \
        --project="${PROJECT_ID}" &>/dev/null; then
        
        if gcloud run services delete "${CLOUDRUN_SERVICE}" \
            --region="${REGION}" \
            --project="${PROJECT_ID}" \
            --quiet; then
            log_cleanup "DELETE" "Cloud Run Service: ${CLOUDRUN_SERVICE}" "SUCCESS"
            log_success "Deleted Cloud Run service: ${CLOUDRUN_SERVICE}"
        else
            log_cleanup "DELETE" "Cloud Run Service: ${CLOUDRUN_SERVICE}" "FAILED"
            log_error "Failed to delete Cloud Run service: ${CLOUDRUN_SERVICE}"
        fi
    else
        log_info "Cloud Run service ${CLOUDRUN_SERVICE} not found or already deleted"
    fi
}

# Function to delete Pub/Sub resources
delete_pubsub_resources() {
    log_info "Deleting Pub/Sub resources..."
    
    # Delete subscription first
    if gcloud pubsub subscriptions describe "${PUBSUB_SUBSCRIPTION}" \
        --project="${PROJECT_ID}" &>/dev/null; then
        
        if gcloud pubsub subscriptions delete "${PUBSUB_SUBSCRIPTION}" \
            --project="${PROJECT_ID}" \
            --quiet; then
            log_cleanup "DELETE" "Pub/Sub Subscription: ${PUBSUB_SUBSCRIPTION}" "SUCCESS"
            log_success "Deleted Pub/Sub subscription: ${PUBSUB_SUBSCRIPTION}"
        else
            log_cleanup "DELETE" "Pub/Sub Subscription: ${PUBSUB_SUBSCRIPTION}" "FAILED"
            log_error "Failed to delete Pub/Sub subscription: ${PUBSUB_SUBSCRIPTION}"
        fi
    else
        log_info "Pub/Sub subscription ${PUBSUB_SUBSCRIPTION} not found or already deleted"
    fi
    
    # Delete topic
    if gcloud pubsub topics describe "${PUBSUB_TOPIC}" \
        --project="${PROJECT_ID}" &>/dev/null; then
        
        if gcloud pubsub topics delete "${PUBSUB_TOPIC}" \
            --project="${PROJECT_ID}" \
            --quiet; then
            log_cleanup "DELETE" "Pub/Sub Topic: ${PUBSUB_TOPIC}" "SUCCESS"
            log_success "Deleted Pub/Sub topic: ${PUBSUB_TOPIC}"
        else
            log_cleanup "DELETE" "Pub/Sub Topic: ${PUBSUB_TOPIC}" "FAILED"
            log_error "Failed to delete Pub/Sub topic: ${PUBSUB_TOPIC}"
        fi
    else
        log_info "Pub/Sub topic ${PUBSUB_TOPIC} not found or already deleted"
    fi
}

# Function to delete storage bucket
delete_storage_bucket() {
    log_info "Deleting Cloud Storage bucket and contents..."
    
    if gsutil ls -b "gs://${BUCKET_NAME}" &>/dev/null; then
        # Check if bucket has objects
        local object_count
        object_count=$(gsutil ls "gs://${BUCKET_NAME}/**" 2>/dev/null | wc -l || echo "0")
        
        if [[ "${object_count}" -gt 0 ]]; then
            log_info "Bucket contains ${object_count} objects. Deleting all contents..."
            
            # Delete all objects in parallel
            if gsutil -m rm -r "gs://${BUCKET_NAME}/**" 2>/dev/null; then
                log_info "Deleted all objects from bucket"
            else
                log_warning "Some objects may not have been deleted"
            fi
        fi
        
        # Delete the bucket itself
        if gsutil rb "gs://${BUCKET_NAME}"; then
            log_cleanup "DELETE" "Storage Bucket: gs://${BUCKET_NAME}" "SUCCESS"
            log_success "Deleted storage bucket: gs://${BUCKET_NAME}"
        else
            log_cleanup "DELETE" "Storage Bucket: gs://${BUCKET_NAME}" "FAILED"
            log_error "Failed to delete storage bucket: gs://${BUCKET_NAME}"
        fi
    else
        log_info "Storage bucket gs://${BUCKET_NAME} not found or already deleted"
    fi
}

# Function to delete Document AI processor
delete_documentai_processor() {
    log_info "Deleting Document AI processor..."
    
    if [[ -n "${PROCESSOR_ID:-}" ]]; then
        if gcloud documentai processors describe "${PROCESSOR_ID}" \
            --location="${REGION}" \
            --project="${PROJECT_ID}" &>/dev/null; then
            
            if gcloud documentai processors delete "${PROCESSOR_ID}" \
                --location="${REGION}" \
                --project="${PROJECT_ID}" \
                --quiet; then
                log_cleanup "DELETE" "Document AI Processor: ${PROCESSOR_ID}" "SUCCESS"
                log_success "Deleted Document AI processor: ${PROCESSOR_ID}"
            else
                log_cleanup "DELETE" "Document AI Processor: ${PROCESSOR_ID}" "FAILED"
                log_error "Failed to delete Document AI processor: ${PROCESSOR_ID}"
            fi
        else
            log_info "Document AI processor ${PROCESSOR_ID} not found or already deleted"
        fi
    else
        log_warning "No processor ID specified. Skipping Document AI processor deletion."
        log_warning "You may need to manually delete any remaining processors."
    fi
}

# Function to delete service account
delete_service_account() {
    log_info "Deleting service account..."
    
    local service_account_email="${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
    
    if gcloud iam service-accounts describe "${service_account_email}" \
        --project="${PROJECT_ID}" &>/dev/null; then
        
        # Remove IAM policy bindings first
        log_info "Removing IAM policy bindings..."
        local permissions=(
            "roles/documentai.apiUser"
            "roles/storage.objectAdmin"
            "roles/pubsub.subscriber"
            "roles/logging.logWriter"
            "roles/monitoring.metricWriter"
        )
        
        for permission in "${permissions[@]}"; do
            gcloud projects remove-iam-policy-binding "${PROJECT_ID}" \
                --member="serviceAccount:${service_account_email}" \
                --role="${permission}" \
                --quiet 2>/dev/null || true
        done
        
        # Delete the service account
        if gcloud iam service-accounts delete "${service_account_email}" \
            --project="${PROJECT_ID}" \
            --quiet; then
            log_cleanup "DELETE" "Service Account: ${service_account_email}" "SUCCESS"
            log_success "Deleted service account: ${service_account_email}"
        else
            log_cleanup "DELETE" "Service Account: ${service_account_email}" "FAILED"
            log_error "Failed to delete service account: ${service_account_email}"
        fi
    else
        log_info "Service account ${service_account_email} not found or already deleted"
    fi
}

# Function to clean up temporary files
cleanup_temp_files() {
    log_info "Cleaning up temporary files..."
    
    # Remove config files
    rm -f "/tmp/gcp-docai-config-${PROJECT_ID}.env"
    
    # Remove any leftover deployment state files
    rm -f "/tmp/gcp-docai-deployment-${PROJECT_ID}.state"
    
    log_success "Temporary files cleaned up"
}

# Function to verify cleanup completion
verify_cleanup() {
    log_info "Verifying cleanup completion..."
    
    local cleanup_issues=""
    
    # Check Cloud Run services
    if gcloud run services describe "${CLOUDRUN_SERVICE}" \
        --region="${REGION}" \
        --project="${PROJECT_ID}" &>/dev/null; then
        cleanup_issues="${cleanup_issues}\n- Cloud Run service still exists: ${CLOUDRUN_SERVICE}"
    fi
    
    # Check Pub/Sub resources
    if gcloud pubsub topics describe "${PUBSUB_TOPIC}" \
        --project="${PROJECT_ID}" &>/dev/null; then
        cleanup_issues="${cleanup_issues}\n- Pub/Sub topic still exists: ${PUBSUB_TOPIC}"
    fi
    
    if gcloud pubsub subscriptions describe "${PUBSUB_SUBSCRIPTION}" \
        --project="${PROJECT_ID}" &>/dev/null; then
        cleanup_issues="${cleanup_issues}\n- Pub/Sub subscription still exists: ${PUBSUB_SUBSCRIPTION}"
    fi
    
    # Check storage bucket
    if gsutil ls -b "gs://${BUCKET_NAME}" &>/dev/null; then
        cleanup_issues="${cleanup_issues}\n- Storage bucket still exists: gs://${BUCKET_NAME}"
    fi
    
    # Check Document AI processor
    if [[ -n "${PROCESSOR_ID:-}" ]] && gcloud documentai processors describe "${PROCESSOR_ID}" \
        --location="${REGION}" \
        --project="${PROJECT_ID}" &>/dev/null; then
        cleanup_issues="${cleanup_issues}\n- Document AI processor still exists: ${PROCESSOR_ID}"
    fi
    
    # Check service account
    if gcloud iam service-accounts describe "${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com" \
        --project="${PROJECT_ID}" &>/dev/null; then
        cleanup_issues="${cleanup_issues}\n- Service account still exists: ${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
    fi
    
    if [[ -n "${cleanup_issues}" ]]; then
        log_warning "Some resources may not have been completely deleted:"
        echo -e "${cleanup_issues}"
        log_warning "You may need to manually delete these resources"
        return 1
    else
        log_success "All resources have been successfully deleted"
        return 0
    fi
}

# Function to display cleanup summary
display_summary() {
    local cleanup_end_time=$(date)
    local duration=$(($(date +%s) - $(date -d "${CLEANUP_START_TIME}" +%s)))
    
    echo ""
    echo "============================================="
    echo "         CLEANUP SUMMARY"
    echo "============================================="
    echo "Project: ${PROJECT_ID}"
    echo "Region: ${REGION}"
    echo "Start Time: ${CLEANUP_START_TIME}"
    echo "End Time: ${cleanup_end_time}"
    echo "Duration: ${duration} seconds"
    echo ""
    echo "Cleanup Log: ${CLEANUP_LOG}"
    echo ""
    
    if [[ -n "${DELETED_RESOURCES}" ]]; then
        echo "Successfully Deleted:"
        echo -e "${DELETED_RESOURCES}"
        echo ""
    fi
    
    if [[ -n "${FAILED_DELETIONS}" ]]; then
        echo "Failed Deletions:"
        echo -e "${FAILED_DELETIONS}"
        echo ""
        log_warning "Some resources could not be deleted. Check the cleanup log for details."
    else
        log_success "All cleanup operations completed successfully!"
    fi
    
    echo "============================================="
}

# Main cleanup function
main() {
    log_info "Configuration:"
    echo "  Project ID: ${PROJECT_ID}"
    echo "  Region: ${REGION}"
    echo "  Bucket Name: ${BUCKET_NAME}"
    echo "  Cloud Run Service: ${CLOUDRUN_SERVICE}"
    echo "  Service Account: ${SERVICE_ACCOUNT_NAME}"
    echo "  Processor ID: ${PROCESSOR_ID:-'Not specified - will search'}"
    echo ""
    
    # Initialize cleanup log
    echo "# GCP Document Processing Cleanup Log" > "${CLEANUP_LOG}"
    echo "# Started at: $(date)" >> "${CLEANUP_LOG}"
    echo "# Project: ${PROJECT_ID}" >> "${CLEANUP_LOG}"
    echo "" >> "${CLEANUP_LOG}"
    
    # Execute cleanup steps
    check_prerequisites
    get_processor_id
    list_resources
    
    # Confirm deletion
    if [[ "${FORCE_DELETE:-false}" != "true" ]]; then
        echo ""
        log_warning "This will permanently delete all resources listed above."
        log_warning "This action cannot be undone!"
        echo ""
        read -p "Are you sure you want to continue? (type 'DELETE' to confirm): " -r
        echo
        if [[ $REPLY != "DELETE" ]]; then
            log_info "Cleanup cancelled by user"
            exit 0
        fi
    fi
    
    # Perform cleanup in order (dependencies first)
    delete_cloudrun_service
    delete_pubsub_resources
    delete_storage_bucket
    delete_documentai_processor
    delete_service_account
    cleanup_temp_files
    
    # Verify and summarize
    verify_cleanup
    display_summary
    
    log_success "Cleanup completed!"
}

# Handle script arguments
case "${1:-}" in
    --help|-h)
        echo "Usage: $0 [OPTIONS]"
        echo ""
        echo "Options:"
        echo "  --project PROJECT_ID    Specify the GCP project ID"
        echo "  --region REGION         Specify the GCP region (default: us-central1)"
        echo "  --force                 Skip confirmation prompts"
        echo "  --list-only             Only list resources without deleting"
        echo "  --help, -h              Show this help message"
        echo ""
        echo "Environment Variables:"
        echo "  PROJECT_ID              GCP Project ID"
        echo "  REGION                  GCP Region"
        echo "  BUCKET_NAME             Storage bucket name"
        echo "  CLOUDRUN_SERVICE        Cloud Run service name"
        echo "  SERVICE_ACCOUNT_NAME    Service account name"
        echo "  PROCESSOR_ID            Document AI processor ID"
        echo ""
        echo "The script will attempt to load configuration from saved deployment files"
        echo "if environment variables are not set."
        exit 0
        ;;
    --project)
        if [[ -z "${2:-}" ]]; then
            log_error "Project ID required after --project"
            exit 1
        fi
        PROJECT_ID="$2"
        shift 2
        ;;
    --region)
        if [[ -z "${2:-}" ]]; then
            log_error "Region required after --region"
            exit 1
        fi
        REGION="$2"
        shift 2
        ;;
    --force)
        FORCE_DELETE="true"
        shift
        ;;
    --list-only)
        check_prerequisites
        get_processor_id
        list_resources
        exit 0
        ;;
    "")
        # No arguments, proceed with main execution
        ;;
    *)
        log_error "Unknown option: $1"
        echo "Use --help for usage information"
        exit 1
        ;;
esac

# Run main cleanup
main