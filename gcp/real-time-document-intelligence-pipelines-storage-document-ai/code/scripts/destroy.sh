#!/bin/bash

# Real-Time Document Intelligence Pipelines Cleanup Script
# This script removes all infrastructure created for the document processing pipeline
# including Cloud Functions, Pub/Sub resources, Cloud Storage, and Document AI processors

set -euo pipefail

# Color codes for output formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
    exit 1
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1${NC}"
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if gcloud is installed and authenticated
    if ! command -v gcloud &> /dev/null; then
        error "gcloud CLI is not installed. Please install it from https://cloud.google.com/sdk/docs/install"
    fi
    
    # Check if user is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        error "No active gcloud authentication found. Run 'gcloud auth login' to authenticate"
    fi
    
    # Check if project is set
    if ! gcloud config get-value project &> /dev/null; then
        error "No default project set. Run 'gcloud config set project YOUR_PROJECT_ID'"
    fi
    
    log "Prerequisites check passed ✅"
}

# Function to load environment variables
load_environment() {
    log "Loading environment variables..."
    
    # Core environment variables with defaults
    export PROJECT_ID="${PROJECT_ID:-$(gcloud config get-value project)}"
    export REGION="${REGION:-us-central1}"
    export LOCATION="${LOCATION:-us}"
    
    # Check for resource names in environment variables or prompt user
    if [[ -z "${BUCKET_NAME:-}" ]] || [[ -z "${TOPIC_NAME:-}" ]] || [[ -z "${RESULTS_TOPIC:-}" ]]; then
        info "Resource names not found in environment variables."
        info "Attempting to discover resources automatically..."
        
        # Try to discover resources by common patterns
        discover_resources
    fi
    
    info "Environment loaded for project: ${PROJECT_ID}"
}

# Function to discover existing resources
discover_resources() {
    log "Discovering document intelligence pipeline resources..."
    
    # Discover Document AI processors
    local processors
    processors=$(gcloud documentai processors list --location="${LOCATION}" --format="value(name,displayName)" 2>/dev/null || echo "")
    
    if [[ -n "${processors}" ]]; then
        info "Found Document AI processors:"
        echo "${processors}" | while IFS=$'\t' read -r name display_name; do
            echo "  - ${display_name} ($(echo "${name}" | cut -d'/' -f6))"
        done
    fi
    
    # Discover Cloud Functions
    local functions
    functions=$(gcloud functions list --regions="${REGION}" --format="value(name)" 2>/dev/null | grep -E "(process-document|consume-results)" || echo "")
    
    if [[ -n "${functions}" ]]; then
        info "Found related Cloud Functions:"
        echo "${functions}" | while read -r func; do
            echo "  - ${func}"
        done
    fi
    
    # Discover Pub/Sub topics
    local topics
    topics=$(gcloud pubsub topics list --format="value(name)" 2>/dev/null | grep -E "(document-events|document-results)" || echo "")
    
    if [[ -n "${topics}" ]]; then
        info "Found related Pub/Sub topics:"
        echo "${topics}" | while read -r topic; do
            echo "  - $(basename "${topic}")"
        done
    fi
    
    # Discover Storage buckets
    local buckets
    buckets=$(gsutil ls -p "${PROJECT_ID}" 2>/dev/null | grep -E "documents-" || echo "")
    
    if [[ -n "${buckets}" ]]; then
        info "Found related Storage buckets:"
        echo "${buckets}" | while read -r bucket; do
            echo "  - ${bucket}"
        done
    fi
}

# Function to confirm destruction
confirm_destruction() {
    warn "⚠️  DESTRUCTIVE OPERATION WARNING ⚠️"
    echo ""
    echo "This script will permanently delete the following resources:"
    echo "- Cloud Functions (process-document, consume-results)"
    echo "- Pub/Sub topics and subscriptions"
    echo "- Cloud Storage buckets and all contents"
    echo "- Document AI processors"
    echo "- Firestore collections (processed_documents)"
    echo ""
    echo "Project: ${PROJECT_ID}"
    echo "Region: ${REGION}"
    echo ""
    
    # Interactive confirmation
    if [[ "${FORCE_DESTROY:-}" != "true" ]]; then
        read -p "Are you sure you want to proceed? (yes/no): " confirmation
        case "${confirmation}" in
            yes|YES|y|Y)
                log "Proceeding with resource destruction..."
                ;;
            *)
                info "Operation cancelled by user"
                exit 0
                ;;
        esac
        
        echo ""
        warn "This action cannot be undone!"
        read -p "Type 'DELETE' to confirm: " final_confirmation
        if [[ "${final_confirmation}" != "DELETE" ]]; then
            info "Operation cancelled by user"
            exit 0
        fi
    else
        warn "FORCE_DESTROY=true detected, skipping confirmation prompts"
    fi
}

# Function to delete Cloud Functions
delete_cloud_functions() {
    log "Deleting Cloud Functions..."
    
    local functions=("process-document" "consume-results")
    
    for func in "${functions[@]}"; do
        if gcloud functions describe "${func}" --region="${REGION}" &> /dev/null; then
            info "Deleting Cloud Function: ${func}"
            if gcloud functions delete "${func}" --region="${REGION}" --quiet; then
                log "✅ Deleted Cloud Function: ${func}"
            else
                warn "Failed to delete Cloud Function: ${func}"
            fi
        else
            info "Cloud Function ${func} not found, skipping"
        fi
    done
}

# Function to delete Pub/Sub resources
delete_pubsub_resources() {
    log "Deleting Pub/Sub resources..."
    
    # Delete subscriptions first
    local subscriptions
    subscriptions=$(gcloud pubsub subscriptions list --format="value(name)" 2>/dev/null | grep -E "(process-docs|consume-results)" || echo "")
    
    if [[ -n "${subscriptions}" ]]; then
        echo "${subscriptions}" | while read -r sub; do
            if [[ -n "${sub}" ]]; then
                local sub_name
                sub_name=$(basename "${sub}")
                info "Deleting subscription: ${sub_name}"
                if gcloud pubsub subscriptions delete "${sub_name}" --quiet; then
                    log "✅ Deleted subscription: ${sub_name}"
                else
                    warn "Failed to delete subscription: ${sub_name}"
                fi
            fi
        done
    fi
    
    # Delete topics
    local topics
    topics=$(gcloud pubsub topics list --format="value(name)" 2>/dev/null | grep -E "(document-events|document-results)" || echo "")
    
    if [[ -n "${topics}" ]]; then
        echo "${topics}" | while read -r topic; do
            if [[ -n "${topic}" ]]; then
                local topic_name
                topic_name=$(basename "${topic}")
                info "Deleting topic: ${topic_name}"
                if gcloud pubsub topics delete "${topic_name}" --quiet; then
                    log "✅ Deleted topic: ${topic_name}"
                else
                    warn "Failed to delete topic: ${topic_name}"
                fi
            fi
        done
    fi
}

# Function to delete Cloud Storage buckets
delete_storage_buckets() {
    log "Deleting Cloud Storage buckets..."
    
    # Find document-related buckets
    local buckets
    buckets=$(gsutil ls -p "${PROJECT_ID}" 2>/dev/null | grep -E "documents-" || echo "")
    
    if [[ -n "${buckets}" ]]; then
        echo "${buckets}" | while read -r bucket; do
            if [[ -n "${bucket}" ]]; then
                info "Deleting bucket and all contents: ${bucket}"
                if gsutil -m rm -r "${bucket}" 2>/dev/null; then
                    log "✅ Deleted bucket: ${bucket}"
                else
                    warn "Failed to delete bucket: ${bucket}"
                fi
            fi
        done
    else
        info "No document-related storage buckets found"
    fi
    
    # Also try environment variable if set
    if [[ -n "${BUCKET_NAME:-}" ]]; then
        if gsutil ls "gs://${BUCKET_NAME}" &> /dev/null; then
            info "Deleting bucket from environment: gs://${BUCKET_NAME}"
            if gsutil -m rm -r "gs://${BUCKET_NAME}" 2>/dev/null; then
                log "✅ Deleted bucket: gs://${BUCKET_NAME}"
            else
                warn "Failed to delete bucket: gs://${BUCKET_NAME}"
            fi
        fi
    fi
}

# Function to delete Document AI processors
delete_document_ai_processors() {
    log "Deleting Document AI processors..."
    
    # List all processors in the location
    local processors
    processors=$(gcloud documentai processors list --location="${LOCATION}" --format="value(name,displayName)" 2>/dev/null || echo "")
    
    if [[ -n "${processors}" ]]; then
        echo "${processors}" | while IFS=$'\t' read -r name display_name; do
            if [[ -n "${name}" ]] && [[ "${display_name}" == *"processor"* || "${display_name}" == *"doc-intelligence"* ]]; then
                local processor_id
                processor_id=$(echo "${name}" | cut -d'/' -f6)
                info "Deleting Document AI processor: ${display_name} (${processor_id})"
                if gcloud documentai processors delete "${processor_id}" --location="${LOCATION}" --quiet; then
                    log "✅ Deleted processor: ${display_name}"
                else
                    warn "Failed to delete processor: ${display_name}"
                fi
            fi
        done
    else
        info "No Document AI processors found"
    fi
    
    # Also try environment variable if set
    if [[ -n "${PROCESSOR_ID:-}" ]]; then
        if gcloud documentai processors describe "${PROCESSOR_ID}" --location="${LOCATION}" &> /dev/null; then
            info "Deleting processor from environment: ${PROCESSOR_ID}"
            if gcloud documentai processors delete "${PROCESSOR_ID}" --location="${LOCATION}" --quiet; then
                log "✅ Deleted processor: ${PROCESSOR_ID}"
            else
                warn "Failed to delete processor: ${PROCESSOR_ID}"
            fi
        fi
    fi
}

# Function to clean up Firestore collections
cleanup_firestore() {
    log "Cleaning up Firestore collections..."
    
    # Check if Firestore is enabled
    if gcloud firestore databases list --format="value(name)" 2>/dev/null | grep -q "default"; then
        info "Firestore database found"
        warn "Note: Firestore collection 'processed_documents' may contain data"
        warn "Manual cleanup may be required via the Firebase Console:"
        warn "https://console.firebase.google.com/project/${PROJECT_ID}/firestore"
    else
        info "No Firestore database found"
    fi
}

# Function to clean up temporary files and environment
cleanup_environment() {
    log "Cleaning up environment..."
    
    # Remove any temporary directories that might exist
    rm -rf /tmp/doc-processor-* /tmp/results-consumer-* 2>/dev/null || true
    
    # Unset environment variables
    unset PROJECT_ID REGION LOCATION PROCESSOR_ID BUCKET_NAME 2>/dev/null || true
    unset TOPIC_NAME RESULTS_TOPIC SUBSCRIPTION_NAME RESULTS_SUBSCRIPTION 2>/dev/null || true
    
    log "Environment cleanup completed ✅"
}

# Function to verify cleanup
verify_cleanup() {
    log "Verifying resource cleanup..."
    
    local cleanup_issues=0
    
    # Check Cloud Functions
    local remaining_functions
    remaining_functions=$(gcloud functions list --regions="${REGION}" --format="value(name)" 2>/dev/null | grep -E "(process-document|consume-results)" || echo "")
    if [[ -n "${remaining_functions}" ]]; then
        warn "Remaining Cloud Functions found:"
        echo "${remaining_functions}"
        ((cleanup_issues++))
    fi
    
    # Check Pub/Sub topics
    local remaining_topics
    remaining_topics=$(gcloud pubsub topics list --format="value(name)" 2>/dev/null | grep -E "(document-events|document-results)" || echo "")
    if [[ -n "${remaining_topics}" ]]; then
        warn "Remaining Pub/Sub topics found:"
        echo "${remaining_topics}"
        ((cleanup_issues++))
    fi
    
    # Check Storage buckets
    local remaining_buckets
    remaining_buckets=$(gsutil ls -p "${PROJECT_ID}" 2>/dev/null | grep -E "documents-" || echo "")
    if [[ -n "${remaining_buckets}" ]]; then
        warn "Remaining Storage buckets found:"
        echo "${remaining_buckets}"
        ((cleanup_issues++))
    fi
    
    if [[ ${cleanup_issues} -eq 0 ]]; then
        log "✅ All resources successfully cleaned up!"
    else
        warn "⚠️  Some resources may require manual cleanup"
        info "Please check the Google Cloud Console for any remaining resources"
    fi
}

# Function to display cleanup summary
display_summary() {
    log "Cleanup Summary"
    echo "==============="
    echo "Project: ${PROJECT_ID}"
    echo "Region: ${REGION}"
    echo ""
    echo "Resources Deleted:"
    echo "- Cloud Functions (process-document, consume-results)"
    echo "- Pub/Sub topics and subscriptions"
    echo "- Cloud Storage buckets and contents"
    echo "- Document AI processors"
    echo ""
    echo "Manual Cleanup May Be Required:"
    echo "- Firestore collections: processed_documents"
    echo "- Any custom IAM roles or policies"
    echo "- Cloud Build triggers (if any)"
    echo ""
    info "Check the Google Cloud Console to verify all resources are removed:"
    echo "  https://console.cloud.google.com/home/dashboard?project=${PROJECT_ID}"
}

# Main cleanup function
main() {
    log "Starting Real-Time Document Intelligence Pipeline Cleanup"
    
    check_prerequisites
    load_environment
    discover_resources
    confirm_destruction
    
    delete_cloud_functions
    delete_pubsub_resources
    delete_storage_buckets
    delete_document_ai_processors
    cleanup_firestore
    cleanup_environment
    verify_cleanup
    display_summary
    
    log "🧹 Document Intelligence Pipeline cleanup completed!"
}

# Handle script interruption
trap 'error "Cleanup interrupted - some resources may remain"' INT TERM

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --force)
            export FORCE_DESTROY=true
            shift
            ;;
        --project)
            export PROJECT_ID="$2"
            shift 2
            ;;
        --region)
            export REGION="$2"
            shift 2
            ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --force          Skip confirmation prompts"
            echo "  --project ID     Specify project ID"
            echo "  --region REGION  Specify region (default: us-central1)"
            echo "  --help, -h       Show this help message"
            exit 0
            ;;
        *)
            warn "Unknown option: $1"
            shift
            ;;
    esac
done

# Run main function
main "$@"