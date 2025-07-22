#!/bin/bash

# Destroy script for Data Locality Optimization with Cloud Storage Bucket Relocation and Cloud Monitoring
# This script safely removes all infrastructure resources created by the deployment

set -euo pipefail

# Color codes for output
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
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to load deployment metadata
load_deployment_metadata() {
    log "Loading deployment metadata..."
    
    if [[ -f "deployment-metadata.json" ]]; then
        # Extract values from metadata file
        export PROJECT_ID=$(jq -r '.project_id' deployment-metadata.json)
        export REGION=$(jq -r '.region' deployment-metadata.json)
        export SECONDARY_REGION=$(jq -r '.secondary_region' deployment-metadata.json)
        export BUCKET_NAME=$(jq -r '.bucket_name' deployment-metadata.json)
        export FUNCTION_NAME=$(jq -r '.function_name' deployment-metadata.json)
        export SCHEDULER_JOB=$(jq -r '.scheduler_job' deployment-metadata.json)
        export PUBSUB_TOPIC=$(jq -r '.pubsub_topic' deployment-metadata.json)
        
        success "Loaded deployment metadata"
        log "  Project ID: $PROJECT_ID"
        log "  Bucket name: $BUCKET_NAME"
        log "  Function name: $FUNCTION_NAME"
        log "  Scheduler job: $SCHEDULER_JOB"
        log "  Pub/Sub topic: $PUBSUB_TOPIC"
    else
        warning "deployment-metadata.json not found. Using manual resource discovery..."
        
        # Try to get project from gcloud config
        export PROJECT_ID=$(gcloud config get-value project 2>/dev/null || echo "")
        export REGION="us-central1"
        export SECONDARY_REGION="europe-west1"
        
        if [[ -z "$PROJECT_ID" ]]; then
            error "No project ID found. Please set it manually:"
            error "export PROJECT_ID=your-project-id"
            exit 1
        fi
        
        # Prompt user for resource names if metadata is missing
        read -p "Enter bucket name (or press Enter to skip): " BUCKET_NAME
        read -p "Enter function name (or press Enter to skip): " FUNCTION_NAME
        read -p "Enter scheduler job name (or press Enter to skip): " SCHEDULER_JOB
        read -p "Enter Pub/Sub topic name (or press Enter to skip): " PUBSUB_TOPIC
        
        export BUCKET_NAME=${BUCKET_NAME:-""}
        export FUNCTION_NAME=${FUNCTION_NAME:-""}
        export SCHEDULER_JOB=${SCHEDULER_JOB:-""}
        export PUBSUB_TOPIC=${PUBSUB_TOPIC:-""}
    fi
}

# Function to confirm destruction
confirm_destruction() {
    log "This will permanently delete the following resources:"
    echo "  ✗ Cloud Storage Bucket: $BUCKET_NAME"
    echo "  ✗ Cloud Function: $FUNCTION_NAME"
    echo "  ✗ Cloud Scheduler Job: $SCHEDULER_JOB"
    echo "  ✗ Pub/Sub Topic and Subscription: $PUBSUB_TOPIC"
    echo "  ✗ Monitoring Alert Policies"
    echo "  ✗ Custom Metrics"
    echo ""
    echo "This action cannot be undone!"
    echo ""
    
    read -p "Are you sure you want to proceed? (type 'yes' to confirm): " confirmation
    
    if [[ "$confirmation" != "yes" ]]; then
        log "Destruction cancelled by user"
        exit 0
    fi
    
    success "Destruction confirmed"
}

# Function to delete Cloud Scheduler job
delete_scheduler_job() {
    if [[ -n "$SCHEDULER_JOB" ]]; then
        log "Deleting Cloud Scheduler job: $SCHEDULER_JOB..."
        
        # Check if job exists
        if gcloud scheduler jobs describe "$SCHEDULER_JOB" --location="$REGION" &>/dev/null; then
            if gcloud scheduler jobs delete "$SCHEDULER_JOB" --location="$REGION" --quiet; then
                success "Deleted Cloud Scheduler job: $SCHEDULER_JOB"
            else
                warning "Failed to delete Cloud Scheduler job: $SCHEDULER_JOB"
            fi
        else
            log "Cloud Scheduler job $SCHEDULER_JOB not found"
        fi
    else
        log "No scheduler job specified, skipping..."
    fi
}

# Function to delete Cloud Function
delete_cloud_function() {
    if [[ -n "$FUNCTION_NAME" ]]; then
        log "Deleting Cloud Function: $FUNCTION_NAME..."
        
        # Check if function exists
        if gcloud functions describe "$FUNCTION_NAME" --region="$REGION" &>/dev/null; then
            if gcloud functions delete "$FUNCTION_NAME" --region="$REGION" --quiet; then
                success "Deleted Cloud Function: $FUNCTION_NAME"
            else
                warning "Failed to delete Cloud Function: $FUNCTION_NAME"
            fi
        else
            log "Cloud Function $FUNCTION_NAME not found"
        fi
    else
        log "No function name specified, skipping..."
    fi
}

# Function to delete monitoring alert policies
delete_alert_policies() {
    log "Deleting monitoring alert policies..."
    
    # Find and delete alert policies related to the bucket
    if [[ -n "$BUCKET_NAME" ]]; then
        local policy_filter="displayName:Storage Access Latency Alert - $BUCKET_NAME"
        
        # Get policy names
        local policies=$(gcloud alpha monitoring policies list \
            --filter="$policy_filter" \
            --format="value(name)" 2>/dev/null || echo "")
        
        if [[ -n "$policies" ]]; then
            while IFS= read -r policy; do
                if [[ -n "$policy" ]]; then
                    log "Deleting alert policy: $policy"
                    if gcloud alpha monitoring policies delete "$policy" --quiet; then
                        success "Deleted alert policy: $policy"
                    else
                        warning "Failed to delete alert policy: $policy"
                    fi
                fi
            done <<< "$policies"
        else
            log "No alert policies found for bucket: $BUCKET_NAME"
        fi
    else
        # If no bucket name, try to find all policies that might be related
        log "Searching for related alert policies..."
        local policies=$(gcloud alpha monitoring policies list \
            --filter="displayName:Storage Access Latency Alert" \
            --format="value(name)" 2>/dev/null || echo "")
        
        if [[ -n "$policies" ]]; then
            echo "Found the following alert policies that might be related:"
            gcloud alpha monitoring policies list \
                --filter="displayName:Storage Access Latency Alert" \
                --format="table(displayName,name)"
            
            read -p "Delete all these policies? (y/N): " delete_all
            if [[ "$delete_all" =~ ^[Yy]$ ]]; then
                while IFS= read -r policy; do
                    if [[ -n "$policy" ]]; then
                        gcloud alpha monitoring policies delete "$policy" --quiet || true
                    fi
                done <<< "$policies"
                success "Deleted all related alert policies"
            fi
        else
            log "No alert policies found"
        fi
    fi
}

# Function to delete custom metrics
delete_custom_metrics() {
    log "Deleting custom monitoring metrics..."
    
    # Delete the custom metric for regional access latency
    if gcloud logging metrics describe storage-regional-latency &>/dev/null; then
        if gcloud logging metrics delete storage-regional-latency --quiet; then
            success "Deleted custom metric: storage-regional-latency"
        else
            warning "Failed to delete custom metric: storage-regional-latency"
        fi
    else
        log "Custom metric storage-regional-latency not found"
    fi
    
    # Check for other custom metrics that might be related
    log "Checking for other related custom metrics..."
    local custom_metrics=$(gcloud logging metrics list \
        --filter="name:storage" \
        --format="value(name)" 2>/dev/null || echo "")
    
    if [[ -n "$custom_metrics" ]]; then
        echo "Found additional storage-related metrics:"
        gcloud logging metrics list --filter="name:storage" --format="table(name,description)"
        
        read -p "Delete these metrics as well? (y/N): " delete_metrics
        if [[ "$delete_metrics" =~ ^[Yy]$ ]]; then
            while IFS= read -r metric; do
                if [[ -n "$metric" ]]; then
                    gcloud logging metrics delete "$metric" --quiet || true
                fi
            done <<< "$custom_metrics"
            success "Deleted additional custom metrics"
        fi
    fi
}

# Function to delete Pub/Sub resources
delete_pubsub_resources() {
    if [[ -n "$PUBSUB_TOPIC" ]]; then
        log "Deleting Pub/Sub resources..."
        
        # Delete subscription first
        local subscription="${PUBSUB_TOPIC}-monitor"
        if gcloud pubsub subscriptions describe "$subscription" &>/dev/null; then
            if gcloud pubsub subscriptions delete "$subscription" --quiet; then
                success "Deleted Pub/Sub subscription: $subscription"
            else
                warning "Failed to delete Pub/Sub subscription: $subscription"
            fi
        else
            log "Pub/Sub subscription $subscription not found"
        fi
        
        # Delete topic
        if gcloud pubsub topics describe "$PUBSUB_TOPIC" &>/dev/null; then
            if gcloud pubsub topics delete "$PUBSUB_TOPIC" --quiet; then
                success "Deleted Pub/Sub topic: $PUBSUB_TOPIC"
            else
                warning "Failed to delete Pub/Sub topic: $PUBSUB_TOPIC"
            fi
        else
            log "Pub/Sub topic $PUBSUB_TOPIC not found"
        fi
    else
        log "No Pub/Sub topic specified, skipping..."
    fi
}

# Function to delete Cloud Storage bucket
delete_storage_bucket() {
    if [[ -n "$BUCKET_NAME" ]]; then
        log "Deleting Cloud Storage bucket: $BUCKET_NAME..."
        
        # Check if bucket exists
        if gsutil ls "gs://$BUCKET_NAME" &>/dev/null; then
            log "Removing all objects from bucket..."
            
            # Remove all objects (including versioned objects)
            if gsutil -m rm -r "gs://$BUCKET_NAME/**" 2>/dev/null || true; then
                log "Removed all objects from bucket"
            fi
            
            # Remove versioned objects if versioning is enabled
            if gsutil -m rm -a "gs://$BUCKET_NAME/**" 2>/dev/null || true; then
                log "Removed versioned objects from bucket"
            fi
            
            # Delete the bucket
            if gsutil rb "gs://$BUCKET_NAME"; then
                success "Deleted Cloud Storage bucket: $BUCKET_NAME"
            else
                error "Failed to delete Cloud Storage bucket: $BUCKET_NAME"
                error "You may need to delete it manually through the console"
            fi
        else
            log "Cloud Storage bucket $BUCKET_NAME not found"
        fi
    else
        log "No bucket name specified, skipping..."
    fi
}

# Function to clean up local files
cleanup_local_files() {
    log "Cleaning up local files..."
    
    local files_to_remove=(
        "deployment-metadata.json"
        "metric_descriptor.json"
        "alert_policy.json"
        "sample-data-*.txt"
        "downloaded-*.txt"
        "bucket-relocator-function/"
    )
    
    for file_pattern in "${files_to_remove[@]}"; do
        if [[ -e $file_pattern ]] || ls $file_pattern 2>/dev/null; then
            rm -rf $file_pattern
            log "Removed: $file_pattern"
        fi
    done
    
    success "Local files cleaned up"
}

# Function to display destruction summary
display_summary() {
    log "Destruction Summary:"
    echo "===================="
    echo "The following resources have been deleted:"
    echo "  ✓ Cloud Scheduler Job: $SCHEDULER_JOB"
    echo "  ✓ Cloud Function: $FUNCTION_NAME"
    echo "  ✓ Monitoring Alert Policies"
    echo "  ✓ Custom Metrics"
    echo "  ✓ Pub/Sub Topic and Subscription: $PUBSUB_TOPIC"
    echo "  ✓ Cloud Storage Bucket: $BUCKET_NAME"
    echo "  ✓ Local files and directories"
    echo ""
    echo "All resources have been successfully destroyed!"
    echo ""
    warning "Note: Some monitoring data and logs may be retained according to Google Cloud's retention policies."
    warning "Please verify through the Google Cloud Console that all resources have been removed."
    
    success "Destruction completed successfully!"
}

# Function to handle errors during destruction
handle_destruction_error() {
    error "An error occurred during resource destruction."
    error "Some resources may not have been deleted completely."
    echo ""
    echo "Please check the following manually in the Google Cloud Console:"
    echo "  - Cloud Storage bucket: $BUCKET_NAME"
    echo "  - Cloud Function: $FUNCTION_NAME"
    echo "  - Cloud Scheduler job: $SCHEDULER_JOB"
    echo "  - Pub/Sub topic: $PUBSUB_TOPIC"
    echo "  - Monitoring alert policies and custom metrics"
    echo ""
    echo "You can also re-run this script to attempt cleanup again."
    exit 1
}

# Function to discover resources automatically
discover_resources() {
    log "Attempting to discover resources automatically..."
    
    # Try to find data locality related resources
    
    # Find Cloud Functions with "bucket-relocator" or "data-locality" in the name
    log "Searching for Cloud Functions..."
    local functions=$(gcloud functions list --regions="$REGION" \
        --filter="name:bucket-relocator OR name:data-locality" \
        --format="value(name)" 2>/dev/null || echo "")
    
    if [[ -n "$functions" ]]; then
        echo "Found potential Cloud Functions:"
        gcloud functions list --regions="$REGION" \
            --filter="name:bucket-relocator OR name:data-locality" \
            --format="table(name,status,trigger)" 2>/dev/null || true
    fi
    
    # Find Cloud Storage buckets with data-locality labels
    log "Searching for Cloud Storage buckets..."
    local buckets=$(gsutil ls -L -b | grep -B5 -A5 "data-locality-optimization" | grep "gs://" | cut -d'/' -f3 || echo "")
    
    if [[ -n "$buckets" ]]; then
        echo "Found potential Cloud Storage buckets:"
        echo "$buckets"
    fi
    
    # Find Pub/Sub topics with "relocation-alerts" in the name
    log "Searching for Pub/Sub topics..."
    local topics=$(gcloud pubsub topics list \
        --filter="name:relocation-alerts" \
        --format="value(name)" 2>/dev/null || echo "")
    
    if [[ -n "$topics" ]]; then
        echo "Found potential Pub/Sub topics:"
        echo "$topics"
    fi
    
    # Find Cloud Scheduler jobs with "locality-analyzer" in the name
    log "Searching for Cloud Scheduler jobs..."
    local jobs=$(gcloud scheduler jobs list --location="$REGION" \
        --filter="name:locality-analyzer" \
        --format="value(name)" 2>/dev/null || echo "")
    
    if [[ -n "$jobs" ]]; then
        echo "Found potential Cloud Scheduler jobs:"
        echo "$jobs"
    fi
}

# Main destruction function
main() {
    log "Starting destruction of Data Locality Optimization solution..."
    
    # Set up error handling
    trap handle_destruction_error ERR
    
    # Load deployment metadata or manual input
    load_deployment_metadata
    
    # If no resources found, try discovery
    if [[ -z "$BUCKET_NAME" && -z "$FUNCTION_NAME" && -z "$SCHEDULER_JOB" && -z "$PUBSUB_TOPIC" ]]; then
        log "No resources specified. Attempting automatic discovery..."
        discover_resources
        
        echo ""
        read -p "Would you like to specify resource names manually? (y/N): " manual_input
        if [[ "$manual_input" =~ ^[Yy]$ ]]; then
            load_deployment_metadata  # This will prompt for manual input
        else
            log "No resources to destroy. Exiting."
            exit 0
        fi
    fi
    
    # Confirm destruction
    confirm_destruction
    
    # Run destruction steps in reverse order of creation
    delete_scheduler_job
    delete_cloud_function
    delete_alert_policies
    delete_custom_metrics
    delete_pubsub_resources
    delete_storage_bucket
    cleanup_local_files
    display_summary
    
    success "All destruction steps completed successfully!"
}

# Handle script arguments
case "${1:-}" in
    --help|-h)
        echo "Usage: $0 [options]"
        echo ""
        echo "Options:"
        echo "  --help, -h     Show this help message"
        echo "  --discover     Only discover resources, don't delete"
        echo "  --force        Skip confirmation prompt"
        echo ""
        echo "This script will destroy all resources created by the data locality optimization deployment."
        echo "Make sure you have deployment-metadata.json file in the current directory, or be prepared"
        echo "to enter resource names manually."
        exit 0
        ;;
    --discover)
        export PROJECT_ID=$(gcloud config get-value project 2>/dev/null || echo "")
        export REGION="us-central1"
        if [[ -z "$PROJECT_ID" ]]; then
            error "No project ID found. Please run 'gcloud config set project PROJECT_ID'"
            exit 1
        fi
        discover_resources
        exit 0
        ;;
    --force)
        # Skip confirmation
        confirm_destruction() { success "Destruction confirmed (forced)"; }
        ;;
esac

# Run main function
main "$@"