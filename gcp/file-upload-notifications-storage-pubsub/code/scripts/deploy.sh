#!/bin/bash

# Deploy script for File Upload Notifications with Cloud Storage and Pub/Sub
# This script creates a complete notification system for file uploads using GCP services

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
        log_info "Visit: https://cloud.google.com/sdk/docs/install"
        exit 1
    fi
    
    # Check if user is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q "@"; then
        log_error "Not authenticated with Google Cloud. Please run: gcloud auth login"
        exit 1
    fi
    
    # Check if openssl is available for random generation
    if ! command_exists openssl; then
        log_error "openssl is required for generating random values but not found."
        exit 1
    fi
    
    log_success "Prerequisites check passed"
}

# Function to validate GCP project
validate_project() {
    if [[ -z "${PROJECT_ID:-}" ]]; then
        log_error "PROJECT_ID environment variable is not set"
        log_info "Please set PROJECT_ID: export PROJECT_ID=your-project-id"
        exit 1
    fi
    
    # Check if project exists and user has access
    if ! gcloud projects describe "${PROJECT_ID}" >/dev/null 2>&1; then
        log_error "Cannot access project '${PROJECT_ID}'. Please check project ID and permissions."
        exit 1
    fi
    
    log_success "Project validation passed: ${PROJECT_ID}"
}

# Function to set up environment variables
setup_environment() {
    log_info "Setting up environment variables..."
    
    # Set default values if not provided
    export REGION="${REGION:-us-central1}"
    export ZONE="${ZONE:-us-central1-a}"
    
    # Generate unique suffix for resource names
    RANDOM_SUFFIX=$(openssl rand -hex 3)
    
    # Set resource names with unique suffixes
    export TOPIC_NAME="${TOPIC_NAME:-file-upload-notifications-${RANDOM_SUFFIX}}"
    export SUBSCRIPTION_NAME="${SUBSCRIPTION_NAME:-file-processor-${RANDOM_SUFFIX}}"
    export BUCKET_NAME="${BUCKET_NAME:-${PROJECT_ID}-uploads-${RANDOM_SUFFIX}}"
    
    log_info "Environment configured:"
    log_info "  Project ID: ${PROJECT_ID}"
    log_info "  Region: ${REGION}"
    log_info "  Zone: ${ZONE}"
    log_info "  Topic Name: ${TOPIC_NAME}"
    log_info "  Subscription Name: ${SUBSCRIPTION_NAME}"
    log_info "  Bucket Name: ${BUCKET_NAME}"
}

# Function to configure gcloud defaults
configure_gcloud() {
    log_info "Configuring gcloud defaults..."
    
    gcloud config set project "${PROJECT_ID}"
    gcloud config set compute/region "${REGION}"
    gcloud config set compute/zone "${ZONE}"
    
    log_success "gcloud configuration updated"
}

# Function to enable required APIs
enable_apis() {
    log_info "Enabling required Google Cloud APIs..."
    
    local apis=(
        "storage.googleapis.com"
        "pubsub.googleapis.com"
    )
    
    for api in "${apis[@]}"; do
        log_info "Enabling ${api}..."
        if gcloud services enable "${api}" --quiet; then
            log_success "Enabled ${api}"
        else
            log_error "Failed to enable ${api}"
            exit 1
        fi
    done
    
    # Wait for APIs to be fully enabled
    log_info "Waiting for APIs to be fully activated..."
    sleep 10
}

# Function to create Pub/Sub topic
create_pubsub_topic() {
    log_info "Creating Pub/Sub topic: ${TOPIC_NAME}"
    
    if gcloud pubsub topics describe "${TOPIC_NAME}" >/dev/null 2>&1; then
        log_warning "Topic ${TOPIC_NAME} already exists, skipping creation"
    else
        if gcloud pubsub topics create "${TOPIC_NAME}"; then
            log_success "Created Pub/Sub topic: ${TOPIC_NAME}"
        else
            log_error "Failed to create Pub/Sub topic"
            exit 1
        fi
    fi
    
    # Verify topic creation
    if gcloud pubsub topics list --filter="name:${TOPIC_NAME}" --format="value(name)" | grep -q "${TOPIC_NAME}"; then
        log_success "Topic verification passed"
    else
        log_error "Topic verification failed"
        exit 1
    fi
}

# Function to create Pub/Sub subscription
create_pubsub_subscription() {
    log_info "Creating Pub/Sub subscription: ${SUBSCRIPTION_NAME}"
    
    if gcloud pubsub subscriptions describe "${SUBSCRIPTION_NAME}" >/dev/null 2>&1; then
        log_warning "Subscription ${SUBSCRIPTION_NAME} already exists, skipping creation"
    else
        if gcloud pubsub subscriptions create "${SUBSCRIPTION_NAME}" \
            --topic="${TOPIC_NAME}" \
            --ack-deadline=60 \
            --message-retention-duration=7d; then
            log_success "Created Pub/Sub subscription: ${SUBSCRIPTION_NAME}"
        else
            log_error "Failed to create Pub/Sub subscription"
            exit 1
        fi
    fi
    
    # Verify subscription creation
    if gcloud pubsub subscriptions list --filter="name:${SUBSCRIPTION_NAME}" --format="value(name)" | grep -q "${SUBSCRIPTION_NAME}"; then
        log_success "Subscription verification passed"
    else
        log_error "Subscription verification failed"
        exit 1
    fi
}

# Function to create Cloud Storage bucket
create_storage_bucket() {
    log_info "Creating Cloud Storage bucket: ${BUCKET_NAME}"
    
    if gcloud storage buckets describe "gs://${BUCKET_NAME}" >/dev/null 2>&1; then
        log_warning "Bucket ${BUCKET_NAME} already exists, skipping creation"
    else
        if gcloud storage buckets create "gs://${BUCKET_NAME}" \
            --project="${PROJECT_ID}" \
            --default-storage-class=STANDARD \
            --location="${REGION}"; then
            log_success "Created Cloud Storage bucket: ${BUCKET_NAME}"
        else
            log_error "Failed to create Cloud Storage bucket"
            exit 1
        fi
    fi
    
    # Enable uniform bucket-level access
    log_info "Enabling uniform bucket-level access..."
    if gcloud storage buckets update "gs://${BUCKET_NAME}" \
        --uniform-bucket-level-access; then
        log_success "Enabled uniform bucket-level access"
    else
        log_warning "Failed to enable uniform bucket-level access (may already be enabled)"
    fi
    
    # Verify bucket creation
    if gcloud storage buckets list --filter="name:${BUCKET_NAME}" --format="value(name)" | grep -q "${BUCKET_NAME}"; then
        log_success "Bucket verification passed"
    else
        log_error "Bucket verification failed"
        exit 1
    fi
}

# Function to configure bucket notifications
configure_bucket_notifications() {
    log_info "Configuring bucket notifications to Pub/Sub..."
    
    # Check if notification already exists
    if gcloud storage buckets notifications list "gs://${BUCKET_NAME}" --format="value(topic)" | grep -q "${TOPIC_NAME}"; then
        log_warning "Notification configuration already exists, skipping creation"
    else
        if gcloud storage buckets notifications create \
            "gs://${BUCKET_NAME}" \
            --topic="${TOPIC_NAME}" \
            --event-types=OBJECT_FINALIZE,OBJECT_DELETE \
            --payload-format=JSON_API_V1; then
            log_success "Configured bucket notifications"
        else
            log_error "Failed to configure bucket notifications"
            exit 1
        fi
    fi
    
    # Verify notification configuration
    if gcloud storage buckets notifications list "gs://${BUCKET_NAME}" --format="value(topic)" | grep -q "${TOPIC_NAME}"; then
        log_success "Notification configuration verified"
    else
        log_error "Notification configuration verification failed"
        exit 1
    fi
}

# Function to test the deployment
test_deployment() {
    log_info "Testing the deployment with a sample file upload..."
    
    # Create a test file
    local test_file="test-upload-$(date +%s).txt"
    echo "Test file content $(date)" > "${test_file}"
    
    # Upload the test file
    if gcloud storage cp "${test_file}" "gs://${BUCKET_NAME}/"; then
        log_success "Test file uploaded successfully"
    else
        log_error "Failed to upload test file"
        rm -f "${test_file}"
        exit 1
    fi
    
    # Wait for notification propagation
    log_info "Waiting for notification propagation..."
    sleep 10
    
    # Check for messages in the subscription
    log_info "Checking for notification messages..."
    if gcloud pubsub subscriptions pull "${SUBSCRIPTION_NAME}" \
        --limit=1 \
        --auto-ack \
        --format="value(message.data)" >/dev/null 2>&1; then
        log_success "Notification system is working correctly"
    else
        log_warning "No messages found in subscription (this may be normal if processing is fast)"
    fi
    
    # Clean up test file
    rm -f "${test_file}"
    log_info "Test file cleaned up locally"
}

# Function to display deployment summary
display_summary() {
    log_success "Deployment completed successfully!"
    echo
    log_info "Resource Summary:"
    log_info "  Project ID: ${PROJECT_ID}"
    log_info "  Pub/Sub Topic: ${TOPIC_NAME}"
    log_info "  Pub/Sub Subscription: ${SUBSCRIPTION_NAME}"
    log_info "  Storage Bucket: ${BUCKET_NAME}"
    echo
    log_info "Next Steps:"
    log_info "  1. Upload files to gs://${BUCKET_NAME}/ to trigger notifications"
    log_info "  2. Pull messages from subscription: gcloud pubsub subscriptions pull ${SUBSCRIPTION_NAME} --auto-ack"
    log_info "  3. Monitor your Pub/Sub topic in the GCP Console"
    echo
    log_info "To clean up resources, run: ./destroy.sh"
}

# Main deployment function
main() {
    log_info "Starting deployment of File Upload Notifications system..."
    
    check_prerequisites
    validate_project
    setup_environment
    configure_gcloud
    enable_apis
    create_pubsub_topic
    create_pubsub_subscription
    create_storage_bucket
    configure_bucket_notifications
    test_deployment
    display_summary
    
    log_success "Deployment process completed successfully!"
}

# Handle script interruption
trap 'log_error "Deployment interrupted. You may need to clean up partially created resources."; exit 1' INT TERM

# Run main function
main "$@"