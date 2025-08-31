#!/bin/bash

# Destroy script for File Upload Notifications with Cloud Storage and Pub/Sub
# This script safely removes all resources created by the deployment script

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

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if gcloud CLI is installed
    if ! command_exists gcloud; then
        log_error "Google Cloud CLI (gcloud) is not installed. Please install it first."
        exit 1
    fi
    
    # Check if user is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q "@"; then
        log_error "Not authenticated with Google Cloud. Please run: gcloud auth login"
        exit 1
    fi
    
    log_success "Prerequisites check passed"
}

# Function to validate environment variables
validate_environment() {
    log_info "Validating environment variables..."
    
    local missing_vars=()
    
    # Check required environment variables
    if [[ -z "${PROJECT_ID:-}" ]]; then
        missing_vars+=("PROJECT_ID")
    fi
    
    if [[ -z "${TOPIC_NAME:-}" ]]; then
        missing_vars+=("TOPIC_NAME")
    fi
    
    if [[ -z "${SUBSCRIPTION_NAME:-}" ]]; then
        missing_vars+=("SUBSCRIPTION_NAME")
    fi
    
    if [[ -z "${BUCKET_NAME:-}" ]]; then
        missing_vars+=("BUCKET_NAME")
    fi
    
    # If any required variables are missing, try to discover them
    if [[ ${#missing_vars[@]} -gt 0 ]]; then
        log_warning "Some environment variables are missing: ${missing_vars[*]}"
        log_info "Attempting to discover resources..."
        
        # Set default PROJECT_ID if not set
        if [[ -z "${PROJECT_ID:-}" ]]; then
            PROJECT_ID=$(gcloud config get project 2>/dev/null || true)
            if [[ -z "${PROJECT_ID}" ]]; then
                log_error "PROJECT_ID could not be determined. Please set it manually."
                log_info "export PROJECT_ID=your-project-id"
                exit 1
            else
                log_info "Using current gcloud project: ${PROJECT_ID}"
            fi
        fi
        
        # Discover resources if variables are not set
        discover_resources
    fi
    
    log_success "Environment variables validated"
}

# Function to discover existing resources
discover_resources() {
    log_info "Discovering existing resources..."
    
    # Try to find resources with common naming patterns
    if [[ -z "${TOPIC_NAME:-}" ]]; then
        TOPIC_NAME=$(gcloud pubsub topics list --filter="name~file-upload-notifications" --format="value(name)" | head -n1 | xargs basename 2>/dev/null || true)
        if [[ -n "${TOPIC_NAME}" ]]; then
            log_info "Discovered topic: ${TOPIC_NAME}"
        fi
    fi
    
    if [[ -z "${SUBSCRIPTION_NAME:-}" ]]; then
        SUBSCRIPTION_NAME=$(gcloud pubsub subscriptions list --filter="name~file-processor" --format="value(name)" | head -n1 | xargs basename 2>/dev/null || true)
        if [[ -n "${SUBSCRIPTION_NAME}" ]]; then
            log_info "Discovered subscription: ${SUBSCRIPTION_NAME}"
        fi
    fi
    
    if [[ -z "${BUCKET_NAME:-}" ]]; then
        BUCKET_NAME=$(gcloud storage buckets list --filter="name~${PROJECT_ID}-uploads" --format="value(name)" | head -n1 2>/dev/null || true)
        if [[ -n "${BUCKET_NAME}" ]]; then
            log_info "Discovered bucket: ${BUCKET_NAME}"
        fi
    fi
}

# Function to confirm destruction
confirm_destruction() {
    log_warning "This will permanently delete the following resources:"
    echo
    log_info "Resources to be deleted:"
    [[ -n "${TOPIC_NAME:-}" ]] && log_info "  - Pub/Sub Topic: ${TOPIC_NAME}"
    [[ -n "${SUBSCRIPTION_NAME:-}" ]] && log_info "  - Pub/Sub Subscription: ${SUBSCRIPTION_NAME}"
    [[ -n "${BUCKET_NAME:-}" ]] && log_info "  - Storage Bucket: ${BUCKET_NAME} (and all contents)"
    echo
    
    # Ask for confirmation unless --force flag is provided
    if [[ "${1:-}" != "--force" ]]; then
        read -p "$(echo -e "${YELLOW}Are you sure you want to proceed? (yes/no): ${NC}")" confirm
        case "$confirm" in
            yes|YES|y|Y)
                log_info "Proceeding with resource deletion..."
                ;;
            *)
                log_info "Destruction cancelled by user"
                exit 0
                ;;
        esac
    else
        log_warning "Force flag detected, skipping confirmation"
    fi
}

# Function to remove bucket notifications
remove_bucket_notifications() {
    if [[ -z "${BUCKET_NAME:-}" ]]; then
        log_warning "BUCKET_NAME not set, skipping notification removal"
        return 0
    fi
    
    log_info "Removing bucket notification configurations..."
    
    # Check if bucket exists
    if ! gcloud storage buckets describe "gs://${BUCKET_NAME}" >/dev/null 2>&1; then
        log_warning "Bucket ${BUCKET_NAME} does not exist, skipping notification removal"
        return 0
    fi
    
    # Get notification IDs and remove them
    local notification_ids
    notification_ids=$(gcloud storage buckets notifications list "gs://${BUCKET_NAME}" --format="value(id)" 2>/dev/null || true)
    
    if [[ -n "${notification_ids}" ]]; then
        while IFS= read -r notification_id; do
            if [[ -n "${notification_id}" ]]; then
                log_info "Removing notification configuration: ${notification_id}"
                if gcloud storage buckets notifications delete "${notification_id}" "gs://${BUCKET_NAME}" --quiet; then
                    log_success "Removed notification: ${notification_id}"
                else
                    log_warning "Failed to remove notification: ${notification_id}"
                fi
            fi
        done <<< "${notification_ids}"
    else
        log_info "No notification configurations found"
    fi
}

# Function to remove Cloud Storage bucket
remove_storage_bucket() {
    if [[ -z "${BUCKET_NAME:-}" ]]; then
        log_warning "BUCKET_NAME not set, skipping bucket removal"
        return 0
    fi
    
    log_info "Removing Cloud Storage bucket: ${BUCKET_NAME}"
    
    # Check if bucket exists
    if ! gcloud storage buckets describe "gs://${BUCKET_NAME}" >/dev/null 2>&1; then
        log_warning "Bucket ${BUCKET_NAME} does not exist, skipping removal"
        return 0
    fi
    
    # Remove all objects and the bucket itself
    if gcloud storage rm --recursive "gs://${BUCKET_NAME}" --quiet; then
        log_success "Removed bucket and all contents: ${BUCKET_NAME}"
    else
        log_error "Failed to remove bucket: ${BUCKET_NAME}"
        log_info "You may need to remove it manually from the GCP Console"
    fi
}

# Function to remove Pub/Sub subscription
remove_pubsub_subscription() {
    if [[ -z "${SUBSCRIPTION_NAME:-}" ]]; then
        log_warning "SUBSCRIPTION_NAME not set, skipping subscription removal"
        return 0
    fi
    
    log_info "Removing Pub/Sub subscription: ${SUBSCRIPTION_NAME}"
    
    # Check if subscription exists
    if ! gcloud pubsub subscriptions describe "${SUBSCRIPTION_NAME}" >/dev/null 2>&1; then
        log_warning "Subscription ${SUBSCRIPTION_NAME} does not exist, skipping removal"
        return 0
    fi
    
    if gcloud pubsub subscriptions delete "${SUBSCRIPTION_NAME}" --quiet; then
        log_success "Removed Pub/Sub subscription: ${SUBSCRIPTION_NAME}"
    else
        log_error "Failed to remove subscription: ${SUBSCRIPTION_NAME}"
        log_info "You may need to remove it manually from the GCP Console"
    fi
}

# Function to remove Pub/Sub topic
remove_pubsub_topic() {
    if [[ -z "${TOPIC_NAME:-}" ]]; then
        log_warning "TOPIC_NAME not set, skipping topic removal"
        return 0
    fi
    
    log_info "Removing Pub/Sub topic: ${TOPIC_NAME}"
    
    # Check if topic exists
    if ! gcloud pubsub topics describe "${TOPIC_NAME}" >/dev/null 2>&1; then
        log_warning "Topic ${TOPIC_NAME} does not exist, skipping removal"
        return 0
    fi
    
    if gcloud pubsub topics delete "${TOPIC_NAME}" --quiet; then
        log_success "Removed Pub/Sub topic: ${TOPIC_NAME}"
    else
        log_error "Failed to remove topic: ${TOPIC_NAME}"
        log_info "You may need to remove it manually from the GCP Console"
    fi
}

# Function to clean up local files
cleanup_local_files() {
    log_info "Cleaning up local test files..."
    
    # Remove any test files that might be left over
    if ls test-upload*.txt >/dev/null 2>&1; then
        rm -f test-upload*.txt
        log_success "Removed local test files"
    else
        log_info "No local test files found"
    fi
}

# Function to verify resource deletion
verify_deletion() {
    log_info "Verifying resource deletion..."
    
    local resources_found=false
    
    # Check if topic still exists
    if [[ -n "${TOPIC_NAME:-}" ]] && gcloud pubsub topics describe "${TOPIC_NAME}" >/dev/null 2>&1; then
        log_warning "Topic ${TOPIC_NAME} still exists"
        resources_found=true
    fi
    
    # Check if subscription still exists
    if [[ -n "${SUBSCRIPTION_NAME:-}" ]] && gcloud pubsub subscriptions describe "${SUBSCRIPTION_NAME}" >/dev/null 2>&1; then
        log_warning "Subscription ${SUBSCRIPTION_NAME} still exists"
        resources_found=true
    fi
    
    # Check if bucket still exists
    if [[ -n "${BUCKET_NAME:-}" ]] && gcloud storage buckets describe "gs://${BUCKET_NAME}" >/dev/null 2>&1; then
        log_warning "Bucket ${BUCKET_NAME} still exists"
        resources_found=true
    fi
    
    if [[ "${resources_found}" == "true" ]]; then
        log_warning "Some resources may not have been deleted completely"
        log_info "Please check the GCP Console and remove any remaining resources manually"
    else
        log_success "All resources have been successfully deleted"
    fi
}

# Function to display destruction summary
display_summary() {
    log_success "Resource destruction completed!"
    echo
    log_info "Summary of actions taken:"
    log_info "  ✅ Removed bucket notifications"
    log_info "  ✅ Deleted Cloud Storage bucket and contents"
    log_info "  ✅ Deleted Pub/Sub subscription"
    log_info "  ✅ Deleted Pub/Sub topic"
    log_info "  ✅ Cleaned up local files"
    echo
    log_info "All resources for the File Upload Notifications system have been removed."
    log_info "Your GCP project should no longer incur charges from these resources."
}

# Function to show usage information
show_usage() {
    echo "Usage: $0 [--force]"
    echo
    echo "Options:"
    echo "  --force    Skip confirmation prompt and proceed with deletion"
    echo
    echo "Environment Variables (optional - will be auto-discovered if not set):"
    echo "  PROJECT_ID        - GCP Project ID"
    echo "  TOPIC_NAME        - Pub/Sub topic name"
    echo "  SUBSCRIPTION_NAME - Pub/Sub subscription name"
    echo "  BUCKET_NAME       - Cloud Storage bucket name"
    echo
    echo "Example:"
    echo "  export PROJECT_ID=my-project"
    echo "  export TOPIC_NAME=file-upload-notifications-abc123"
    echo "  export SUBSCRIPTION_NAME=file-processor-abc123"
    echo "  export BUCKET_NAME=my-project-uploads-abc123"
    echo "  $0"
}

# Main destruction function
main() {
    # Check for help flag
    if [[ "${1:-}" == "--help" ]] || [[ "${1:-}" == "-h" ]]; then
        show_usage
        exit 0
    fi
    
    log_info "Starting destruction of File Upload Notifications system..."
    
    check_prerequisites
    validate_environment
    confirm_destruction "$@"
    
    # Remove resources in reverse order of creation
    remove_bucket_notifications
    remove_storage_bucket
    remove_pubsub_subscription
    remove_pubsub_topic
    cleanup_local_files
    
    verify_deletion
    display_summary
    
    log_success "Destruction process completed successfully!"
}

# Handle script interruption
trap 'log_error "Destruction interrupted. Some resources may not have been deleted."; exit 1' INT TERM

# Run main function with all arguments
main "$@"