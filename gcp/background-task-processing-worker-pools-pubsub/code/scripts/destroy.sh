#!/bin/bash

# Destroy script for Background Task Processing with Cloud Run Worker Pools
# This script safely removes all resources created by the deployment script
# with confirmation prompts and proper error handling

set -euo pipefail

# Color codes for output
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

# Configuration variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/.env"
FORCE_DELETE=false
KEEP_PROJECT=false

# Function to display usage
show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -f, --force           Skip confirmation prompts"
    echo "  -k, --keep-project    Keep the Google Cloud project after cleanup"
    echo "  -h, --help           Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                   # Interactive cleanup with confirmations"
    echo "  $0 --force           # Automated cleanup without prompts"
    echo "  $0 --keep-project    # Clean resources but keep the project"
}

# Parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -f|--force)
                FORCE_DELETE=true
                shift
                ;;
            -k|--keep-project)
                KEEP_PROJECT=true
                shift
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
}

# Function to check if environment file exists
check_environment() {
    if [[ ! -f "${ENV_FILE}" ]]; then
        log_error "Environment file not found: ${ENV_FILE}"
        log_info "This script requires the .env file created during deployment"
        log_info "If you need to clean up manually, use these commands:"
        echo ""
        echo "# List projects with 'background-tasks' prefix:"
        echo "gcloud projects list --filter='name:background-tasks*'"
        echo ""
        echo "# Delete a specific project:"
        echo "gcloud projects delete PROJECT_ID"
        exit 1
    fi
    
    # Source environment variables
    source "${ENV_FILE}"
    
    # Validate required variables
    local required_vars=(
        "PROJECT_ID"
        "REGION"
        "TOPIC_NAME"
        "SUBSCRIPTION_NAME"
        "BUCKET_NAME"
        "JOB_NAME"
        "API_SERVICE_NAME"
    )
    
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            log_error "Required environment variable ${var} is not set"
            exit 1
        fi
    done
    
    log_success "Environment variables loaded successfully"
}

# Function to confirm deletion
confirm_deletion() {
    if [[ "${FORCE_DELETE}" == "true" ]]; then
        return 0
    fi
    
    echo ""
    log_warning "This will permanently delete the following resources:"
    echo "  • Project: ${PROJECT_ID}"
    echo "  • Cloud Run Services: ${API_SERVICE_NAME}"
    echo "  • Cloud Run Jobs: ${JOB_NAME}"
    echo "  • Pub/Sub Topic: ${TOPIC_NAME}"
    echo "  • Pub/Sub Subscription: ${SUBSCRIPTION_NAME}"
    echo "  • Cloud Storage Bucket: ${BUCKET_NAME} (including all files)"
    echo "  • Container images in Artifact Registry"
    echo ""
    
    read -p "Are you sure you want to continue? (yes/no): " -r
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        log_info "Cleanup cancelled by user"
        exit 0
    fi
}

# Function to set project context
setup_project_context() {
    log_info "Setting up project context..."
    
    # Check if project exists
    if ! gcloud projects describe "${PROJECT_ID}" &> /dev/null; then
        log_warning "Project ${PROJECT_ID} does not exist or is not accessible"
        return 1
    fi
    
    # Set active project
    gcloud config set project "${PROJECT_ID}" --quiet
    
    log_success "Project context established"
}

# Function to delete Cloud Run services
delete_cloud_run_services() {
    log_info "Deleting Cloud Run services..."
    
    # Delete API service
    if gcloud run services describe "${API_SERVICE_NAME}" \
       --region="${REGION}" &> /dev/null; then
        log_info "Deleting Cloud Run service: ${API_SERVICE_NAME}"
        gcloud run services delete "${API_SERVICE_NAME}" \
            --region="${REGION}" \
            --quiet
        log_success "Cloud Run service deleted"
    else
        log_info "Cloud Run service ${API_SERVICE_NAME} not found"
    fi
    
    # Delete Cloud Run Job
    if gcloud run jobs describe "${JOB_NAME}" \
       --region="${REGION}" &> /dev/null; then
        log_info "Deleting Cloud Run job: ${JOB_NAME}"
        gcloud run jobs delete "${JOB_NAME}" \
            --region="${REGION}" \
            --quiet
        log_success "Cloud Run job deleted"
    else
        log_info "Cloud Run job ${JOB_NAME} not found"
    fi
}

# Function to delete Pub/Sub resources
delete_pubsub_resources() {
    log_info "Deleting Pub/Sub resources..."
    
    # Delete subscription first (must be done before topic)
    if gcloud pubsub subscriptions describe "${SUBSCRIPTION_NAME}" &> /dev/null; then
        log_info "Deleting Pub/Sub subscription: ${SUBSCRIPTION_NAME}"
        gcloud pubsub subscriptions delete "${SUBSCRIPTION_NAME}" --quiet
        log_success "Pub/Sub subscription deleted"
    else
        log_info "Pub/Sub subscription ${SUBSCRIPTION_NAME} not found"
    fi
    
    # Delete topic
    if gcloud pubsub topics describe "${TOPIC_NAME}" &> /dev/null; then
        log_info "Deleting Pub/Sub topic: ${TOPIC_NAME}"
        gcloud pubsub topics delete "${TOPIC_NAME}" --quiet
        log_success "Pub/Sub topic deleted"
    else
        log_info "Pub/Sub topic ${TOPIC_NAME} not found"
    fi
}

# Function to delete Cloud Storage bucket
delete_storage_bucket() {
    log_info "Deleting Cloud Storage bucket..."
    
    if gsutil ls -b "gs://${BUCKET_NAME}" &> /dev/null; then
        log_info "Deleting bucket contents and bucket: ${BUCKET_NAME}"
        
        # Delete all objects first
        gsutil -m rm -r "gs://${BUCKET_NAME}/**" 2>/dev/null || true
        
        # Delete the bucket itself
        gsutil rb "gs://${BUCKET_NAME}"
        
        log_success "Cloud Storage bucket deleted"
    else
        log_info "Cloud Storage bucket ${BUCKET_NAME} not found"
    fi
}

# Function to delete Artifact Registry repositories
delete_artifact_registry() {
    log_info "Deleting Artifact Registry repositories..."
    
    if gcloud artifacts repositories describe cloud-run-source-deploy \
       --location="${REGION}" &> /dev/null; then
        log_info "Deleting Artifact Registry repository: cloud-run-source-deploy"
        gcloud artifacts repositories delete cloud-run-source-deploy \
            --location="${REGION}" \
            --quiet
        log_success "Artifact Registry repository deleted"
    else
        log_info "Artifact Registry repository cloud-run-source-deploy not found"
    fi
}

# Function to delete application code directories
cleanup_local_files() {
    log_info "Cleaning up local application files..."
    
    local worker_dir="${SCRIPT_DIR}/../worker"
    local api_dir="${SCRIPT_DIR}/../api"
    
    # Remove worker directory
    if [[ -d "${worker_dir}" ]]; then
        log_info "Removing worker application directory"
        rm -rf "${worker_dir}"
    fi
    
    # Remove API directory
    if [[ -d "${api_dir}" ]]; then
        log_info "Removing API application directory"
        rm -rf "${api_dir}"
    fi
    
    # Remove environment file
    if [[ -f "${ENV_FILE}" ]]; then
        log_info "Removing environment file"
        rm -f "${ENV_FILE}"
    fi
    
    log_success "Local files cleaned up"
}

# Function to delete the entire project
delete_project() {
    if [[ "${KEEP_PROJECT}" == "true" ]]; then
        log_info "Keeping project as requested: ${PROJECT_ID}"
        return 0
    fi
    
    log_info "Deleting Google Cloud project: ${PROJECT_ID}"
    
    if [[ "${FORCE_DELETE}" == "false" ]]; then
        echo ""
        log_warning "This will permanently delete the entire project: ${PROJECT_ID}"
        log_warning "This action cannot be undone!"
        echo ""
        read -p "Type 'DELETE' to confirm project deletion: " -r
        if [[ ! $REPLY == "DELETE" ]]; then
            log_info "Project deletion cancelled"
            return 0
        fi
    fi
    
    # Delete the project
    gcloud projects delete "${PROJECT_ID}" --quiet
    
    log_success "Project deletion initiated (may take a few minutes to complete)"
}

# Function to verify cleanup
verify_cleanup() {
    log_info "Verifying resource cleanup..."
    
    local cleanup_errors=()
    
    # Only verify if project still exists
    if gcloud projects describe "${PROJECT_ID}" &> /dev/null; then
        # Check Cloud Run services
        if gcloud run services list --region="${REGION}" \
           --filter="metadata.name:${API_SERVICE_NAME}" \
           --format="value(metadata.name)" | grep -q "${API_SERVICE_NAME}"; then
            cleanup_errors+=("Cloud Run service ${API_SERVICE_NAME} still exists")
        fi
        
        # Check Cloud Run jobs
        if gcloud run jobs list --region="${REGION}" \
           --filter="metadata.name:${JOB_NAME}" \
           --format="value(metadata.name)" | grep -q "${JOB_NAME}"; then
            cleanup_errors+=("Cloud Run job ${JOB_NAME} still exists")
        fi
        
        # Check Pub/Sub topic
        if gcloud pubsub topics describe "${TOPIC_NAME}" &> /dev/null; then
            cleanup_errors+=("Pub/Sub topic ${TOPIC_NAME} still exists")
        fi
        
        # Check Cloud Storage bucket
        if gsutil ls -b "gs://${BUCKET_NAME}" &> /dev/null; then
            cleanup_errors+=("Cloud Storage bucket ${BUCKET_NAME} still exists")
        fi
    fi
    
    # Report results
    if [[ ${#cleanup_errors[@]} -eq 0 ]]; then
        log_success "All resources cleaned up successfully"
    else
        log_warning "Some resources may still exist:"
        for error in "${cleanup_errors[@]}"; do
            echo "  • ${error}"
        done
    fi
}

# Function to display cleanup summary
show_cleanup_summary() {
    echo ""
    echo "==============================================="
    echo "         CLEANUP SUMMARY"
    echo "==============================================="
    
    if [[ "${KEEP_PROJECT}" == "true" ]]; then
        echo "Project Status:       Preserved"
        echo "Project ID:          ${PROJECT_ID}"
        echo "Resources Deleted:   All application resources"
        echo ""
        log_info "Project ${PROJECT_ID} has been preserved as requested"
        log_info "You may want to disable billing or delete manually later"
    else
        echo "Project Status:       Deleted"
        echo "Project ID:          ${PROJECT_ID}"
        echo "Resources Deleted:   All resources (project deletion)"
        echo ""
        log_info "Project ${PROJECT_ID} has been deleted"
        log_info "Billing for this project will stop once deletion is complete"
    fi
    
    echo "Local Files:         Cleaned up"
    echo "Environment File:    Removed"
    echo "==============================================="
    
    if [[ -f "${ENV_FILE}" ]]; then
        log_warning "Note: Environment file still exists at ${ENV_FILE}"
    fi
}

# Main cleanup function
main() {
    log_info "Starting cleanup of Background Task Processing system"
    
    parse_arguments "$@"
    check_environment
    confirm_deletion
    
    # Only proceed with resource cleanup if project exists
    if setup_project_context; then
        delete_cloud_run_services
        delete_pubsub_resources
        delete_storage_bucket
        delete_artifact_registry
        
        # Wait a moment for deletions to propagate
        sleep 10
        
        verify_cleanup
        
        # Delete project unless keeping it
        delete_project
    else
        log_info "Skipping cloud resource cleanup (project not accessible)"
    fi
    
    # Always clean up local files
    cleanup_local_files
    
    show_cleanup_summary
    
    log_success "Cleanup completed!"
}

# Error handling
handle_error() {
    log_error "Cleanup failed at line $1. Exit code: $2"
    log_info "Some resources may not have been deleted"
    log_info "You may need to clean up manually using the Google Cloud Console"
    exit $2
}

# Set error trap
trap 'handle_error $LINENO $?' ERR

# Run main function
main "$@"