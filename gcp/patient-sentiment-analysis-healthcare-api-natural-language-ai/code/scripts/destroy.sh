#!/bin/bash

# Destroy script for Patient Sentiment Analysis with Cloud Healthcare API and Natural Language AI
# This script safely removes all resources created by the deployment

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

# Configuration options
DRY_RUN=${1:-false}
FORCE_DELETE=${2:-false}

# Function to display help
show_help() {
    cat << EOF
Healthcare Sentiment Analysis Cleanup Script

Usage: $0 [dry-run] [force]

Options:
  dry-run    Show what would be deleted without actually deleting
  force      Skip confirmation prompts and delete everything

Examples:
  $0                  # Interactive cleanup with confirmations
  $0 dry-run          # Show what would be deleted
  $0 force            # Delete everything without prompts
  $0 dry-run force    # Show what would be deleted (ignores force in dry-run)

EOF
}

# Check for help request
if [[ "${1:-}" == "help" ]] || [[ "${1:-}" == "--help" ]] || [[ "${1:-}" == "-h" ]]; then
    show_help
    exit 0
fi

# Validate parameters
if [[ -n "${1:-}" ]] && [[ "$1" != "dry-run" ]] && [[ "$1" != "force" ]]; then
    log_error "Invalid parameter: $1"
    show_help
    exit 1
fi

if [[ -n "${2:-}" ]] && [[ "$2" != "force" ]]; then
    log_error "Invalid second parameter: $2"
    show_help
    exit 1
fi

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "gcloud CLI is not installed. Please install Google Cloud SDK."
        exit 1
    fi
    
    # Check if authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        log_error "Not authenticated with gcloud. Please run 'gcloud auth login'."
        exit 1
    fi
    
    # Check if bq command is available
    if ! command -v bq &> /dev/null; then
        log_error "BigQuery CLI (bq) is not available. Please ensure it's installed with gcloud."
        exit 1
    fi
    
    log_success "Prerequisites check passed"
}

# Load deployment information
load_deployment_info() {
    log_info "Loading deployment information..."
    
    # Check if deployment-info.txt exists
    if [[ ! -f "deployment-info.txt" ]]; then
        log_warning "deployment-info.txt not found. You'll need to provide resource details manually."
        get_manual_input
        return
    fi
    
    # Parse deployment info
    export PROJECT_ID=$(grep "Project ID:" deployment-info.txt | cut -d' ' -f3)
    export REGION=$(grep "Region:" deployment-info.txt | cut -d' ' -f2)
    export HEALTHCARE_DATASET=$(grep "Healthcare Dataset:" deployment-info.txt | cut -d' ' -f3)
    export FHIR_STORE=$(grep "FHIR Store:" deployment-info.txt | cut -d' ' -f3)
    export FUNCTION_NAME=$(grep "Cloud Function:" deployment-info.txt | cut -d' ' -f3)
    export PUBSUB_TOPIC=$(grep "Pub/Sub Topic:" deployment-info.txt | cut -d' ' -f3)
    export BQ_DATASET=$(grep "BigQuery Dataset:" deployment-info.txt | cut -d' ' -f3)
    
    if [[ -z "${PROJECT_ID}" ]]; then
        log_error "Failed to parse deployment information. Please check deployment-info.txt"
        exit 1
    fi
    
    log_info "Loaded deployment information for project: ${PROJECT_ID}"
    log_success "Deployment information loaded successfully"
}

# Get manual input if deployment-info.txt is not available
get_manual_input() {
    log_info "Please provide the resource details to clean up:"
    
    read -p "Project ID: " PROJECT_ID
    read -p "Region [us-central1]: " REGION
    REGION=${REGION:-us-central1}
    read -p "Healthcare Dataset name: " HEALTHCARE_DATASET
    read -p "FHIR Store name: " FHIR_STORE
    read -p "Cloud Function name: " FUNCTION_NAME
    read -p "Pub/Sub Topic name: " PUBSUB_TOPIC
    read -p "BigQuery Dataset name: " BQ_DATASET
    
    export PROJECT_ID REGION HEALTHCARE_DATASET FHIR_STORE FUNCTION_NAME PUBSUB_TOPIC BQ_DATASET
    
    if [[ -z "${PROJECT_ID}" ]]; then
        log_error "Project ID is required"
        exit 1
    fi
}

# Display resources to be deleted
show_resources() {
    log_info "Resources to be deleted:"
    echo "=================================="
    echo "Project ID: ${PROJECT_ID}"
    echo "Region: ${REGION}"
    echo "Healthcare Dataset: ${HEALTHCARE_DATASET}"
    echo "FHIR Store: ${FHIR_STORE}"
    echo "Cloud Function: ${FUNCTION_NAME}"
    echo "Pub/Sub Topic: ${PUBSUB_TOPIC}"
    echo "BigQuery Dataset: ${BQ_DATASET}"
    echo "=================================="
}

# Confirm deletion
confirm_deletion() {
    if [[ "${FORCE_DELETE}" == "true" ]]; then
        log_warning "Force mode enabled - skipping confirmation"
        return 0
    fi
    
    show_resources
    echo
    log_warning "This will permanently delete all healthcare sentiment analysis resources!"
    log_warning "This action cannot be undone."
    echo
    read -p "Are you sure you want to continue? (type 'yes' to confirm): " confirmation
    
    if [[ "${confirmation}" != "yes" ]]; then
        log_info "Cleanup cancelled by user"
        exit 0
    fi
    
    log_info "Deletion confirmed. Proceeding with cleanup..."
}

# Set active project
set_active_project() {
    log_info "Setting active project to ${PROJECT_ID}..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would set project: ${PROJECT_ID}"
        return 0
    fi
    
    if gcloud config set project "${PROJECT_ID}" --quiet; then
        log_success "Active project set to ${PROJECT_ID}"
    else
        log_error "Failed to set active project. Project may not exist."
        exit 1
    fi
}

# Delete BigQuery resources
delete_bigquery_resources() {
    log_info "Deleting BigQuery resources..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would delete BigQuery dataset: ${PROJECT_ID}:${BQ_DATASET}"
        return 0
    fi
    
    # Check if dataset exists
    if bq ls "${PROJECT_ID}:${BQ_DATASET}" > /dev/null 2>&1; then
        log_info "Deleting BigQuery dataset: ${BQ_DATASET}"
        if bq rm -r -f "${PROJECT_ID}:${BQ_DATASET}" > /dev/null 2>&1; then
            log_success "BigQuery dataset deleted"
        else
            log_warning "Failed to delete BigQuery dataset (may not exist)"
        fi
    else
        log_info "BigQuery dataset does not exist, skipping"
    fi
}

# Delete Cloud Function
delete_cloud_function() {
    log_info "Deleting Cloud Function..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would delete Cloud Function: ${FUNCTION_NAME}"
        return 0
    fi
    
    # Check if function exists
    if gcloud functions describe "${FUNCTION_NAME}" --region="${REGION}" > /dev/null 2>&1; then
        log_info "Deleting Cloud Function: ${FUNCTION_NAME}"
        if gcloud functions delete "${FUNCTION_NAME}" \
            --region="${REGION}" \
            --quiet; then
            log_success "Cloud Function deleted"
        else
            log_warning "Failed to delete Cloud Function"
        fi
    else
        log_info "Cloud Function does not exist, skipping"
    fi
}

# Delete Pub/Sub resources
delete_pubsub_resources() {
    log_info "Deleting Pub/Sub resources..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would delete Pub/Sub subscription: ${PUBSUB_TOPIC}-sub"
        log_info "[DRY RUN] Would delete Pub/Sub topic: ${PUBSUB_TOPIC}"
        return 0
    fi
    
    # Delete subscription
    if gcloud pubsub subscriptions describe "${PUBSUB_TOPIC}-sub" > /dev/null 2>&1; then
        log_info "Deleting Pub/Sub subscription: ${PUBSUB_TOPIC}-sub"
        if gcloud pubsub subscriptions delete "${PUBSUB_TOPIC}-sub" --quiet; then
            log_success "Pub/Sub subscription deleted"
        else
            log_warning "Failed to delete Pub/Sub subscription"
        fi
    else
        log_info "Pub/Sub subscription does not exist, skipping"
    fi
    
    # Delete topic
    if gcloud pubsub topics describe "${PUBSUB_TOPIC}" > /dev/null 2>&1; then
        log_info "Deleting Pub/Sub topic: ${PUBSUB_TOPIC}"
        if gcloud pubsub topics delete "${PUBSUB_TOPIC}" --quiet; then
            log_success "Pub/Sub topic deleted"
        else
            log_warning "Failed to delete Pub/Sub topic"
        fi
    else
        log_info "Pub/Sub topic does not exist, skipping"
    fi
}

# Delete Healthcare API resources
delete_healthcare_resources() {
    log_info "Deleting Healthcare API resources..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would delete FHIR store: ${FHIR_STORE}"
        log_info "[DRY RUN] Would delete Healthcare dataset: ${HEALTHCARE_DATASET}"
        return 0
    fi
    
    # Delete FHIR store
    if gcloud healthcare fhir-stores describe "${FHIR_STORE}" \
        --dataset="${HEALTHCARE_DATASET}" \
        --location="${REGION}" > /dev/null 2>&1; then
        log_info "Deleting FHIR store: ${FHIR_STORE}"
        if gcloud healthcare fhir-stores delete "${FHIR_STORE}" \
            --dataset="${HEALTHCARE_DATASET}" \
            --location="${REGION}" \
            --quiet; then
            log_success "FHIR store deleted"
        else
            log_warning "Failed to delete FHIR store"
        fi
    else
        log_info "FHIR store does not exist, skipping"
    fi
    
    # Wait a moment for FHIR store deletion to complete
    sleep 5
    
    # Delete healthcare dataset
    if gcloud healthcare datasets describe "${HEALTHCARE_DATASET}" \
        --location="${REGION}" > /dev/null 2>&1; then
        log_info "Deleting Healthcare dataset: ${HEALTHCARE_DATASET}"
        if gcloud healthcare datasets delete "${HEALTHCARE_DATASET}" \
            --location="${REGION}" \
            --quiet; then
            log_success "Healthcare dataset deleted"
        else
            log_warning "Failed to delete Healthcare dataset"
        fi
    else
        log_info "Healthcare dataset does not exist, skipping"
    fi
}

# Delete IAM bindings (optional cleanup)
cleanup_iam_bindings() {
    log_info "Cleaning up IAM bindings..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would clean up IAM bindings for deleted function service account"
        return 0
    fi
    
    # Note: When the Cloud Function is deleted, its service account may remain
    # but the IAM bindings are typically cleaned up automatically
    log_info "IAM bindings are automatically cleaned when resources are deleted"
}

# Delete project (optional - most destructive action)
delete_project() {
    log_warning "Project deletion is available but disabled by default"
    log_info "To delete the entire project, run: gcloud projects delete ${PROJECT_ID}"
    
    if [[ "${FORCE_DELETE}" == "true" ]]; then
        log_warning "Even in force mode, project deletion requires manual confirmation"
        echo
        read -p "Do you want to delete the entire project ${PROJECT_ID}? (type 'DELETE' to confirm): " project_confirmation
        
        if [[ "${project_confirmation}" == "DELETE" ]]; then
            if [[ "${DRY_RUN}" == "true" ]]; then
                log_info "[DRY RUN] Would delete project: ${PROJECT_ID}"
                return 0
            fi
            
            log_warning "Deleting project: ${PROJECT_ID}"
            if gcloud projects delete "${PROJECT_ID}" --quiet; then
                log_success "Project deleted successfully"
            else
                log_error "Failed to delete project"
            fi
        else
            log_info "Project deletion cancelled"
        fi
    fi
}

# Clean up local files
cleanup_local_files() {
    log_info "Cleaning up local files..."
    
    local files_to_remove=(
        "deployment-info.txt"
        "sample-patient.json"
        "positive-observation.json"
        "negative-observation.json"
        "neutral-observation.json"
    )
    
    local dirs_to_remove=(
        "sentiment-function"
    )
    
    for file in "${files_to_remove[@]}"; do
        if [[ -f "${file}" ]]; then
            if [[ "${DRY_RUN}" == "true" ]]; then
                log_info "[DRY RUN] Would remove file: ${file}"
            else
                rm -f "${file}"
                log_success "Removed file: ${file}"
            fi
        fi
    done
    
    for dir in "${dirs_to_remove[@]}"; do
        if [[ -d "${dir}" ]]; then
            if [[ "${DRY_RUN}" == "true" ]]; then
                log_info "[DRY RUN] Would remove directory: ${dir}"
            else
                rm -rf "${dir}"
                log_success "Removed directory: ${dir}"
            fi
        fi
    done
}

# Verify cleanup completion
verify_cleanup() {
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Cleanup verification skipped in dry-run mode"
        return 0
    fi
    
    log_info "Verifying cleanup completion..."
    
    local cleanup_successful=true
    
    # Check if BigQuery dataset still exists
    if bq ls "${PROJECT_ID}:${BQ_DATASET}" > /dev/null 2>&1; then
        log_warning "BigQuery dataset still exists"
        cleanup_successful=false
    fi
    
    # Check if Cloud Function still exists
    if gcloud functions describe "${FUNCTION_NAME}" --region="${REGION}" > /dev/null 2>&1; then
        log_warning "Cloud Function still exists"
        cleanup_successful=false
    fi
    
    # Check if Healthcare dataset still exists
    if gcloud healthcare datasets describe "${HEALTHCARE_DATASET}" --location="${REGION}" > /dev/null 2>&1; then
        log_warning "Healthcare dataset still exists"
        cleanup_successful=false
    fi
    
    if [[ "${cleanup_successful}" == "true" ]]; then
        log_success "Cleanup completed successfully"
    else
        log_warning "Some resources may still exist. Manual cleanup may be required."
    fi
}

# Display summary
show_summary() {
    log_info "Cleanup Summary"
    echo "==============="
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        echo "Mode: DRY RUN (no actual changes made)"
    else
        echo "Mode: ACTUAL DELETION"
    fi
    
    echo "Project: ${PROJECT_ID}"
    echo "Region: ${REGION}"
    echo "Timestamp: $(date)"
    echo
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "To perform actual cleanup, run: $0"
        if [[ "${FORCE_DELETE}" != "true" ]]; then
            log_info "To skip confirmations, run: $0 force"
        fi
    else
        log_success "Healthcare Sentiment Analysis resources have been cleaned up"
        log_info "If you created a project specifically for this recipe, consider deleting it:"
        log_info "gcloud projects delete ${PROJECT_ID}"
    fi
}

# Main cleanup function
main() {
    log_info "Starting Healthcare Sentiment Analysis cleanup..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_warning "DRY RUN MODE - No actual changes will be made"
    fi
    
    check_prerequisites
    load_deployment_info
    
    if [[ "${DRY_RUN}" != "true" ]]; then
        confirm_deletion
    fi
    
    set_active_project
    
    # Delete resources in reverse order of creation
    delete_bigquery_resources
    delete_cloud_function
    delete_pubsub_resources
    delete_healthcare_resources
    cleanup_iam_bindings
    cleanup_local_files
    
    if [[ "${DRY_RUN}" != "true" ]]; then
        verify_cleanup
    fi
    
    show_summary
    
    # Optionally delete the entire project
    if [[ "${DRY_RUN}" != "true" ]]; then
        echo
        delete_project
    fi
}

# Run main function
main "$@"