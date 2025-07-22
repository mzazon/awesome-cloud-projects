#!/bin/bash

# Batch Processing Workflows with Cloud Run Jobs and Cloud Scheduler - Cleanup Script
# This script removes all resources created by the deployment script including:
# - Cloud Scheduler jobs
# - Cloud Run Jobs
# - Artifact Registry repositories
# - Cloud Storage buckets
# - Log-based metrics
# - Optional: Project deletion

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Color codes for output formatting
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
check_command() {
    if ! command -v "$1" &> /dev/null; then
        log_error "Command '$1' not found. Please install it first."
        exit 1
    fi
}

# Function to check if gcloud is authenticated
check_gcloud_auth() {
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q "@"; then
        log_error "gcloud is not authenticated. Please run 'gcloud auth login' first."
        exit 1
    fi
}

# Function to confirm destructive action
confirm_action() {
    local action="$1"
    local resource="$2"
    
    echo -e "${YELLOW}WARNING: This will permanently delete ${resource}${NC}"
    read -p "Are you sure you want to ${action}? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Operation cancelled by user"
        return 1
    fi
    return 0
}

# Function to set resource names from environment or prompt user
set_resource_names() {
    # Try to get from environment first
    if [[ -n "${PROJECT_ID:-}" && -n "${REGION:-}" ]]; then
        log_info "Using environment variables for resource names"
        export REGION="${REGION:-us-central1}"
        export ZONE="${ZONE:-us-central1-a}"
        return 0
    fi
    
    # Prompt user for project ID
    if [[ -z "${PROJECT_ID:-}" ]]; then
        echo -n "Enter Project ID: "
        read -r PROJECT_ID
        if [[ -z "$PROJECT_ID" ]]; then
            log_error "Project ID is required"
            exit 1
        fi
        export PROJECT_ID
    fi
    
    # Set default region if not provided
    export REGION="${REGION:-us-central1}"
    export ZONE="${ZONE:-us-central1-a}"
    
    # Set gcloud project
    gcloud config set project "${PROJECT_ID}"
    gcloud config set compute/region "${REGION}"
    gcloud config set compute/zone "${ZONE}"
    
    log_info "Using Project ID: ${PROJECT_ID}"
    log_info "Using Region: ${REGION}"
}

# Function to list and delete Cloud Scheduler jobs
cleanup_scheduler_jobs() {
    log_info "Cleaning up Cloud Scheduler jobs..."
    
    # List all scheduler jobs in the project
    local jobs
    jobs=$(gcloud scheduler jobs list --location="${REGION}" --format="value(name)" 2>/dev/null || echo "")
    
    if [[ -z "$jobs" ]]; then
        log_info "No Cloud Scheduler jobs found in ${REGION}"
        return 0
    fi
    
    echo "Found Cloud Scheduler jobs:"
    echo "$jobs" | while read -r job; do
        if [[ -n "$job" ]]; then
            echo "  - $job"
        fi
    done
    
    if confirm_action "delete all Cloud Scheduler jobs in ${REGION}" "Cloud Scheduler jobs"; then
        echo "$jobs" | while read -r job; do
            if [[ -n "$job" ]]; then
                local job_name
                job_name=$(basename "$job")
                log_info "Deleting Cloud Scheduler job: $job_name"
                gcloud scheduler jobs delete "$job_name" --location="${REGION}" --quiet || true
            fi
        done
        log_success "Cloud Scheduler jobs cleanup completed"
    else
        log_info "Skipping Cloud Scheduler jobs cleanup"
    fi
}

# Function to list and delete Cloud Run jobs
cleanup_cloud_run_jobs() {
    log_info "Cleaning up Cloud Run jobs..."
    
    # List all Cloud Run jobs in the project
    local jobs
    jobs=$(gcloud run jobs list --region="${REGION}" --format="value(name)" 2>/dev/null || echo "")
    
    if [[ -z "$jobs" ]]; then
        log_info "No Cloud Run jobs found in ${REGION}"
        return 0
    fi
    
    echo "Found Cloud Run jobs:"
    echo "$jobs" | while read -r job; do
        if [[ -n "$job" ]]; then
            echo "  - $job"
        fi
    done
    
    if confirm_action "delete all Cloud Run jobs in ${REGION}" "Cloud Run jobs"; then
        echo "$jobs" | while read -r job; do
            if [[ -n "$job" ]]; then
                log_info "Deleting Cloud Run job: $job"
                gcloud run jobs delete "$job" --region="${REGION}" --quiet || true
            fi
        done
        log_success "Cloud Run jobs cleanup completed"
    else
        log_info "Skipping Cloud Run jobs cleanup"
    fi
}

# Function to list and delete Artifact Registry repositories
cleanup_artifact_registry() {
    log_info "Cleaning up Artifact Registry repositories..."
    
    # List all repositories in the project
    local repos
    repos=$(gcloud artifacts repositories list --location="${REGION}" --format="value(name)" 2>/dev/null || echo "")
    
    if [[ -z "$repos" ]]; then
        log_info "No Artifact Registry repositories found in ${REGION}"
        return 0
    fi
    
    echo "Found Artifact Registry repositories:"
    echo "$repos" | while read -r repo; do
        if [[ -n "$repo" ]]; then
            echo "  - $repo"
        fi
    done
    
    if confirm_action "delete all Artifact Registry repositories in ${REGION}" "Artifact Registry repositories"; then
        echo "$repos" | while read -r repo; do
            if [[ -n "$repo" ]]; then
                local repo_name
                repo_name=$(basename "$repo")
                log_info "Deleting Artifact Registry repository: $repo_name"
                gcloud artifacts repositories delete "$repo_name" --location="${REGION}" --quiet || true
            fi
        done
        log_success "Artifact Registry repositories cleanup completed"
    else
        log_info "Skipping Artifact Registry repositories cleanup"
    fi
}

# Function to list and delete Cloud Storage buckets
cleanup_storage_buckets() {
    log_info "Cleaning up Cloud Storage buckets..."
    
    # List all buckets in the project
    local buckets
    buckets=$(gsutil ls -p "${PROJECT_ID}" 2>/dev/null | grep -E "^gs://.*${PROJECT_ID}.*" || echo "")
    
    if [[ -z "$buckets" ]]; then
        log_info "No Cloud Storage buckets found with project identifier"
        return 0
    fi
    
    echo "Found Cloud Storage buckets:"
    echo "$buckets" | while read -r bucket; do
        if [[ -n "$bucket" ]]; then
            echo "  - $bucket"
        fi
    done
    
    if confirm_action "delete all Cloud Storage buckets" "Cloud Storage buckets and all their contents"; then
        echo "$buckets" | while read -r bucket; do
            if [[ -n "$bucket" ]]; then
                log_info "Deleting Cloud Storage bucket: $bucket"
                gsutil -m rm -r "$bucket" || true
            fi
        done
        log_success "Cloud Storage buckets cleanup completed"
    else
        log_info "Skipping Cloud Storage buckets cleanup"
    fi
}

# Function to delete log-based metrics
cleanup_log_metrics() {
    log_info "Cleaning up log-based metrics..."
    
    # List batch processing related metrics
    local metrics
    metrics=$(gcloud logging metrics list --filter="name:batch" --format="value(name)" 2>/dev/null || echo "")
    
    if [[ -z "$metrics" ]]; then
        log_info "No batch processing log-based metrics found"
        return 0
    fi
    
    echo "Found log-based metrics:"
    echo "$metrics" | while read -r metric; do
        if [[ -n "$metric" ]]; then
            echo "  - $metric"
        fi
    done
    
    if confirm_action "delete batch processing log-based metrics" "log-based metrics"; then
        echo "$metrics" | while read -r metric; do
            if [[ -n "$metric" ]]; then
                local metric_name
                metric_name=$(basename "$metric")
                log_info "Deleting log-based metric: $metric_name"
                gcloud logging metrics delete "$metric_name" --quiet || true
            fi
        done
        log_success "Log-based metrics cleanup completed"
    else
        log_info "Skipping log-based metrics cleanup"
    fi
}

# Function to clean up local files
cleanup_local_files() {
    log_info "Cleaning up local files..."
    
    # Remove any temporary files that might have been created
    local files_to_remove=(
        "batch-app"
        "sample1.txt"
        "sample2.csv"
        "alert-policy.json"
        "*.log"
    )
    
    for file_pattern in "${files_to_remove[@]}"; do
        if ls ${file_pattern} &>/dev/null; then
            log_info "Removing local files: ${file_pattern}"
            rm -rf ${file_pattern}
        fi
    done
    
    log_success "Local files cleanup completed"
}

# Function to optionally delete the entire project
cleanup_project() {
    log_warning "Project deletion is a destructive operation that cannot be undone"
    log_warning "This will delete ALL resources in the project: ${PROJECT_ID}"
    
    if confirm_action "DELETE THE ENTIRE PROJECT" "the entire project ${PROJECT_ID} and all its resources"; then
        log_info "Initiating project deletion..."
        gcloud projects delete "${PROJECT_ID}" --quiet || true
        log_success "Project deletion initiated (this may take several minutes)"
        log_info "You can check the status at: https://console.cloud.google.com/cloud-resource-manager"
    else
        log_info "Skipping project deletion"
    fi
}

# Function to display cleanup summary
display_cleanup_summary() {
    log_success "Cleanup process completed!"
    echo
    echo "=== Resources Cleaned Up ==="
    echo "✓ Cloud Scheduler jobs"
    echo "✓ Cloud Run jobs"
    echo "✓ Artifact Registry repositories"
    echo "✓ Cloud Storage buckets"
    echo "✓ Log-based metrics"
    echo "✓ Local files"
    echo
    echo "=== Verification Commands ==="
    echo "Check remaining Cloud Run jobs: gcloud run jobs list --region=${REGION}"
    echo "Check remaining Scheduler jobs: gcloud scheduler jobs list --location=${REGION}"
    echo "Check remaining Artifact Registry: gcloud artifacts repositories list --location=${REGION}"
    echo "Check remaining Storage buckets: gsutil ls -p ${PROJECT_ID}"
    echo
    if gcloud projects describe "${PROJECT_ID}" &>/dev/null; then
        echo "Project ${PROJECT_ID} still exists"
        echo "To delete the project: gcloud projects delete ${PROJECT_ID}"
    else
        echo "Project ${PROJECT_ID} has been deleted or is being deleted"
    fi
    echo
}

# Function to perform safety checks
safety_checks() {
    log_info "Performing safety checks..."
    
    # Check if project exists
    if ! gcloud projects describe "${PROJECT_ID}" &>/dev/null; then
        log_error "Project ${PROJECT_ID} does not exist or is not accessible"
        exit 1
    fi
    
    # Check if we have proper permissions
    if ! gcloud projects get-iam-policy "${PROJECT_ID}" &>/dev/null; then
        log_error "Insufficient permissions to access project ${PROJECT_ID}"
        exit 1
    fi
    
    log_success "Safety checks passed"
}

# Function to show help
show_help() {
    echo "Usage: $0 [OPTIONS]"
    echo
    echo "Options:"
    echo "  -p, --project-id PROJECT_ID    Specify the project ID"
    echo "  -r, --region REGION            Specify the region (default: us-central1)"
    echo "  --include-project              Include project deletion in cleanup"
    echo "  --dry-run                      Show what would be deleted without actually deleting"
    echo "  -h, --help                     Show this help message"
    echo
    echo "Environment Variables:"
    echo "  PROJECT_ID                     Google Cloud project ID"
    echo "  REGION                         Google Cloud region"
    echo
    echo "Examples:"
    echo "  $0 -p my-project-id"
    echo "  $0 --project-id my-project-id --region us-west1"
    echo "  $0 --include-project"
    echo "  $0 --dry-run"
}

# Parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -p|--project-id)
                PROJECT_ID="$2"
                shift 2
                ;;
            -r|--region)
                REGION="$2"
                shift 2
                ;;
            --include-project)
                INCLUDE_PROJECT="true"
                shift
                ;;
            --dry-run)
                DRY_RUN="true"
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

# Main cleanup function
main() {
    log_info "Starting batch processing cleanup..."
    
    # Parse command line arguments
    parse_arguments "$@"
    
    # Check prerequisites
    check_command "gcloud"
    check_command "gsutil"
    check_gcloud_auth
    
    # Set resource names
    set_resource_names
    
    # Perform safety checks
    safety_checks
    
    # Show dry run information
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "DRY RUN MODE - No resources will be deleted"
        log_info "Would clean up resources in project: ${PROJECT_ID}"
        log_info "Would clean up resources in region: ${REGION}"
        return 0
    fi
    
    # Warning about destructive operation
    echo
    log_warning "This script will delete Google Cloud resources"
    log_warning "Project: ${PROJECT_ID}"
    log_warning "Region: ${REGION}"
    echo
    
    if ! confirm_action "proceed with cleanup" "Google Cloud resources"; then
        log_info "Cleanup cancelled by user"
        exit 0
    fi
    
    # Perform cleanup in reverse order of creation
    cleanup_scheduler_jobs
    cleanup_cloud_run_jobs
    cleanup_artifact_registry
    cleanup_storage_buckets
    cleanup_log_metrics
    cleanup_local_files
    
    # Optionally delete the project
    if [[ "${INCLUDE_PROJECT:-false}" == "true" ]]; then
        cleanup_project
    fi
    
    # Display summary
    display_cleanup_summary
    
    log_success "Batch processing cleanup completed successfully!"
}

# Run main function
main "$@"