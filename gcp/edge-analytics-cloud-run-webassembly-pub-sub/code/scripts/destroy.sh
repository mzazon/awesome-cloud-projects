#!/bin/bash

# Edge Analytics with Cloud Run WebAssembly and Pub/Sub - Cleanup Script
# This script safely removes all resources created by the deployment

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Color codes for output formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Function to check if required tools are installed
check_prerequisites() {
    log "Checking prerequisites for cleanup..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        error "gcloud CLI is not installed. Please install Google Cloud SDK."
        exit 1
    fi
    
    # Check if gsutil is installed
    if ! command -v gsutil &> /dev/null; then
        error "gsutil is not installed. Please install Google Cloud SDK."
        exit 1
    fi
    
    success "Prerequisites check completed"
}

# Function to check gcloud authentication and project setup
check_gcloud_auth() {
    log "Checking gcloud authentication and project setup..."
    
    # Check if user is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        error "Not authenticated with gcloud. Please run 'gcloud auth login'"
        exit 1
    fi
    
    # Check if project is set
    if ! gcloud config get-value project &> /dev/null; then
        error "No default project set. Please run 'gcloud config set project PROJECT_ID'"
        exit 1
    fi
    
    success "gcloud authentication and project setup verified"
}

# Function to load environment variables
load_environment() {
    log "Loading environment configuration..."
    
    # Use provided environment variables or try to detect from gcloud config
    export PROJECT_ID="${PROJECT_ID:-$(gcloud config get-value project)}"
    export REGION="${REGION:-$(gcloud config get-value compute/region)}"
    export ZONE="${ZONE:-$(gcloud config get-value compute/zone)}"
    
    # Set defaults if not configured
    export REGION="${REGION:-us-central1}"
    export ZONE="${ZONE:-us-central1-a}"
    
    # Get project number
    export PROJECT_NUMBER=$(gcloud projects describe "${PROJECT_ID}" --format="value(projectNumber)" 2>/dev/null || echo "")
    
    success "Environment configuration loaded"
    log "Project ID: ${PROJECT_ID}"
    log "Region: ${REGION}"
    log "Zone: ${ZONE}"
}

# Function to get user confirmation for destructive actions
confirm_destruction() {
    log "This script will permanently delete all Edge Analytics resources in project: ${PROJECT_ID}"
    warning "This action cannot be undone!"
    echo ""
    echo "Resources that will be deleted:"
    echo "- All Cloud Run services matching 'edge-analytics-*'"
    echo "- All Pub/Sub topics matching 'iot-sensor-data-*'"
    echo "- All Pub/Sub subscriptions matching 'analytics-subscription-*'"
    echo "- All Cloud Storage buckets matching 'edge-analytics-data-*'"
    echo "- All container images in Container Registry matching 'edge-analytics-*'"
    echo "- All Cloud Monitoring alert policies containing 'IoT Anomaly'"
    echo "- All Cloud Monitoring dashboards containing 'Edge Analytics'"
    echo "- All local temporary files and directories"
    echo ""
    
    # Skip confirmation if FORCE_DESTROY is set
    if [[ "${FORCE_DESTROY:-}" == "true" ]]; then
        warning "FORCE_DESTROY is set, proceeding without confirmation"
        return 0
    fi
    
    read -p "Do you want to continue? (type 'yes' to confirm): " confirmation
    if [[ "$confirmation" != "yes" ]]; then
        log "Cleanup cancelled by user"
        exit 0
    fi
    
    success "User confirmed destruction, proceeding with cleanup"
}

# Function to find and delete Cloud Run services
cleanup_cloud_run_services() {
    log "Cleaning up Cloud Run services..."
    
    # Find all Cloud Run services matching our pattern
    local services=$(gcloud run services list \
        --platform managed \
        --region "${REGION}" \
        --filter="metadata.name:edge-analytics-*" \
        --format="value(metadata.name)" 2>/dev/null || echo "")
    
    if [[ -z "$services" ]]; then
        warning "No Edge Analytics Cloud Run services found"
        return 0
    fi
    
    for service in $services; do
        log "Deleting Cloud Run service: ${service}"
        if gcloud run services delete "${service}" \
            --platform managed \
            --region "${REGION}" \
            --quiet; then
            success "Deleted Cloud Run service: ${service}"
        else
            error "Failed to delete Cloud Run service: ${service}"
        fi
    done
}

# Function to find and delete container images
cleanup_container_images() {
    log "Cleaning up container images..."
    
    # Find all container images matching our pattern
    local images=$(gcloud container images list \
        --repository="gcr.io/${PROJECT_ID}" \
        --filter="name:edge-analytics-*" \
        --format="value(name)" 2>/dev/null || echo "")
    
    if [[ -z "$images" ]]; then
        warning "No Edge Analytics container images found"
        return 0
    fi
    
    for image in $images; do
        log "Deleting container image: ${image}"
        if gcloud container images delete "${image}" --quiet --force-delete-tags; then
            success "Deleted container image: ${image}"
        else
            error "Failed to delete container image: ${image}"
        fi
    done
}

# Function to find and delete Pub/Sub subscriptions
cleanup_pubsub_subscriptions() {
    log "Cleaning up Pub/Sub subscriptions..."
    
    # Find all subscriptions matching our pattern
    local subscriptions=$(gcloud pubsub subscriptions list \
        --filter="name:analytics-subscription-*" \
        --format="value(name.basename())" 2>/dev/null || echo "")
    
    if [[ -z "$subscriptions" ]]; then
        warning "No Edge Analytics Pub/Sub subscriptions found"
        return 0
    fi
    
    for subscription in $subscriptions; do
        log "Deleting Pub/Sub subscription: ${subscription}"
        if gcloud pubsub subscriptions delete "${subscription}" --quiet; then
            success "Deleted Pub/Sub subscription: ${subscription}"
        else
            error "Failed to delete Pub/Sub subscription: ${subscription}"
        fi
    done
}

# Function to find and delete Pub/Sub topics
cleanup_pubsub_topics() {
    log "Cleaning up Pub/Sub topics..."
    
    # Find all topics matching our pattern
    local topics=$(gcloud pubsub topics list \
        --filter="name:iot-sensor-data-*" \
        --format="value(name.basename())" 2>/dev/null || echo "")
    
    if [[ -z "$topics" ]]; then
        warning "No Edge Analytics Pub/Sub topics found"
        return 0
    fi
    
    for topic in $topics; do
        log "Deleting Pub/Sub topic: ${topic}"
        if gcloud pubsub topics delete "${topic}" --quiet; then
            success "Deleted Pub/Sub topic: ${topic}"
        else
            error "Failed to delete Pub/Sub topic: ${topic}"
        fi
    done
}

# Function to find and delete Cloud Storage buckets
cleanup_storage_buckets() {
    log "Cleaning up Cloud Storage buckets..."
    
    # Find all buckets matching our pattern
    local buckets=$(gsutil ls -p "${PROJECT_ID}" 2>/dev/null | grep "gs://edge-analytics-data-" | sed 's|gs://||' | sed 's|/||' || echo "")
    
    if [[ -z "$buckets" ]]; then
        warning "No Edge Analytics Cloud Storage buckets found"
        return 0
    fi
    
    for bucket in $buckets; do
        log "Deleting Cloud Storage bucket and all contents: gs://${bucket}"
        
        # Check if bucket exists
        if gsutil ls -b "gs://${bucket}" &> /dev/null; then
            # Remove all objects and versions
            if gsutil -m rm -r "gs://${bucket}/**" 2>/dev/null || true; then
                log "Removed all objects from bucket: ${bucket}"
            fi
            
            # Remove the bucket itself
            if gsutil rb "gs://${bucket}"; then
                success "Deleted Cloud Storage bucket: ${bucket}"
            else
                error "Failed to delete Cloud Storage bucket: ${bucket}"
            fi
        else
            warning "Bucket gs://${bucket} does not exist, skipping"
        fi
    done
}

# Function to cleanup Firestore data (optional)
cleanup_firestore_data() {
    log "Cleaning up Firestore data..."
    
    # Note: This is optional as Firestore deletion is more complex
    # and might contain other application data
    
    warning "Firestore cleanup is manual. To clean up sensor_analytics collection:"
    echo "1. Go to Firebase Console: https://console.firebase.google.com/"
    echo "2. Select your project: ${PROJECT_ID}"
    echo "3. Go to Firestore Database"
    echo "4. Delete the 'sensor_analytics' collection if it exists"
    echo ""
    
    # For safety, we won't auto-delete Firestore data
    # Users can do this manually if needed
}

# Function to cleanup monitoring resources
cleanup_monitoring_resources() {
    log "Cleaning up Cloud Monitoring resources..."
    
    # Find and delete alert policies
    local alert_policies=$(gcloud alpha monitoring policies list \
        --filter="displayName:'IoT Anomaly Detection Alert'" \
        --format="value(name)" 2>/dev/null || echo "")
    
    if [[ -n "$alert_policies" ]]; then
        for policy in $alert_policies; do
            log "Deleting alert policy: ${policy}"
            if gcloud alpha monitoring policies delete "${policy}" --quiet; then
                success "Deleted alert policy"
            else
                error "Failed to delete alert policy: ${policy}"
            fi
        done
    else
        warning "No Edge Analytics alert policies found"
    fi
    
    # Find and delete dashboards
    local dashboards=$(gcloud monitoring dashboards list \
        --filter="displayName:'Edge Analytics Dashboard'" \
        --format="value(name)" 2>/dev/null || echo "")
    
    if [[ -n "$dashboards" ]]; then
        for dashboard in $dashboards; do
            log "Deleting dashboard: ${dashboard}"
            if gcloud monitoring dashboards delete "${dashboard}" --quiet; then
                success "Deleted dashboard"
            else
                error "Failed to delete dashboard: ${dashboard}"
            fi
        done
    else
        warning "No Edge Analytics dashboards found"
    fi
}

# Function to cleanup local files and directories
cleanup_local_files() {
    log "Cleaning up local files and directories..."
    
    local cleanup_dirs=(
        "wasm-analytics"
        "cloud-run-service"
    )
    
    local cleanup_files=(
        "iot-simulator.py"
        "lifecycle.json"
        "anomaly-alert-policy.json"
        "dashboard-config.json"
    )
    
    # Remove directories
    for dir in "${cleanup_dirs[@]}"; do
        if [[ -d "$dir" ]]; then
            log "Removing directory: ${dir}"
            rm -rf "$dir"
            success "Removed directory: ${dir}"
        fi
    done
    
    # Remove files
    for file in "${cleanup_files[@]}"; do
        if [[ -f "$file" ]]; then
            log "Removing file: ${file}"
            rm -f "$file"
            success "Removed file: ${file}"
        fi
    done
}

# Function to verify cleanup completion
verify_cleanup() {
    log "Verifying cleanup completion..."
    
    local issues=0
    
    # Check Cloud Run services
    local remaining_services=$(gcloud run services list \
        --platform managed \
        --region "${REGION}" \
        --filter="metadata.name:edge-analytics-*" \
        --format="value(metadata.name)" 2>/dev/null || echo "")
    
    if [[ -n "$remaining_services" ]]; then
        warning "Remaining Cloud Run services found: $remaining_services"
        ((issues++))
    fi
    
    # Check Pub/Sub topics
    local remaining_topics=$(gcloud pubsub topics list \
        --filter="name:iot-sensor-data-*" \
        --format="value(name.basename())" 2>/dev/null || echo "")
    
    if [[ -n "$remaining_topics" ]]; then
        warning "Remaining Pub/Sub topics found: $remaining_topics"
        ((issues++))
    fi
    
    # Check Pub/Sub subscriptions
    local remaining_subscriptions=$(gcloud pubsub subscriptions list \
        --filter="name:analytics-subscription-*" \
        --format="value(name.basename())" 2>/dev/null || echo "")
    
    if [[ -n "$remaining_subscriptions" ]]; then
        warning "Remaining Pub/Sub subscriptions found: $remaining_subscriptions"
        ((issues++))
    fi
    
    # Check Cloud Storage buckets
    local remaining_buckets=$(gsutil ls -p "${PROJECT_ID}" 2>/dev/null | grep "gs://edge-analytics-data-" || echo "")
    
    if [[ -n "$remaining_buckets" ]]; then
        warning "Remaining Cloud Storage buckets found: $remaining_buckets"
        ((issues++))
    fi
    
    if [[ $issues -eq 0 ]]; then
        success "All resources cleaned up successfully"
    else
        warning "Cleanup completed with $issues remaining resources"
        echo "You may need to manually clean up the remaining resources"
    fi
}

# Function to display cleanup summary
display_cleanup_summary() {
    log "Cleanup Summary"
    echo "===================="
    echo "Project ID: ${PROJECT_ID}"
    echo "Region: ${REGION}"
    echo ""
    echo "Cleanup Actions Performed:"
    echo "✓ Removed Cloud Run services"
    echo "✓ Removed container images"
    echo "✓ Removed Pub/Sub topics and subscriptions"
    echo "✓ Removed Cloud Storage buckets and data"
    echo "✓ Removed monitoring resources"
    echo "✓ Removed local files and directories"
    echo ""
    echo "Manual Actions Required:"
    echo "- Review and clean up Firestore data if needed"
    echo "- Review IAM roles and permissions if needed"
    echo "- Review billing to ensure no unexpected charges"
    echo ""
    
    success "Edge Analytics platform cleanup completed!"
}

# Function to handle script interruption
cleanup_on_exit() {
    local exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        error "Cleanup script interrupted or failed"
        warning "Some resources may not have been cleaned up"
        echo "Please run the script again or clean up remaining resources manually"
    fi
    exit $exit_code
}

# Main cleanup function
main() {
    # Set up signal handlers
    trap cleanup_on_exit EXIT INT TERM
    
    log "Starting Edge Analytics platform cleanup..."
    
    # Run all cleanup steps
    check_prerequisites
    check_gcloud_auth
    load_environment
    confirm_destruction
    
    # Cleanup in reverse order of creation
    cleanup_cloud_run_services
    cleanup_container_images
    cleanup_pubsub_subscriptions
    cleanup_pubsub_topics
    cleanup_storage_buckets
    cleanup_firestore_data
    cleanup_monitoring_resources
    cleanup_local_files
    
    verify_cleanup
    display_cleanup_summary
    
    success "Cleanup completed successfully!"
}

# Script entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi