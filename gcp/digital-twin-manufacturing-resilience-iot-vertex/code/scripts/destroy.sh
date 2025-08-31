#!/bin/bash

# Digital Twin Manufacturing Resilience with IoT and Vertex AI - Cleanup Script
# This script safely removes all infrastructure created by the deploy.sh script
# 
# Usage: ./destroy.sh [PROJECT_ID]
# 
# If PROJECT_ID is not provided, it will attempt to load from environment

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✅ $1${NC}"
}

warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️  $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ❌ $1${NC}"
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        error "gcloud CLI is not installed. Please install it from https://cloud.google.com/sdk/docs/install"
        exit 1
    fi
    
    # Check if gsutil is available
    if ! command -v gsutil &> /dev/null; then
        error "gsutil is not available. Please ensure Google Cloud SDK is properly installed"
        exit 1
    fi
    
    # Check if bq is available
    if ! command -v bq &> /dev/null; then
        error "bq (BigQuery CLI) is not available. Please ensure Google Cloud SDK is properly installed"
        exit 1
    fi
    
    # Check if user is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q "@"; then
        error "Not authenticated with gcloud. Please run 'gcloud auth login'"
        exit 1
    fi
    
    success "Prerequisites check passed"
}

# Function to load environment variables
load_environment() {
    if [[ -f "${HOME}/.digital_twin_env" ]]; then
        log "Loading environment variables from ${HOME}/.digital_twin_env"
        source "${HOME}/.digital_twin_env"
        success "Environment variables loaded"
    else
        warning "Environment file not found at ${HOME}/.digital_twin_env"
        warning "Some cleanup operations may fail if variables are not set"
    fi
}

# Function to confirm destructive actions
confirm_destruction() {
    local project_id="$1"
    
    echo ""
    echo "⚠️  WARNING: DESTRUCTIVE OPERATION ⚠️"
    echo "======================================"
    echo ""
    echo "This script will permanently delete ALL resources for:"
    echo "Project ID: $project_id"
    echo ""
    echo "Resources to be deleted:"
    echo "• Cloud Functions"
    echo "• BigQuery datasets and tables"
    echo "• Pub/Sub topics and subscriptions"
    echo "• Cloud Storage buckets and contents"
    echo "• Vertex AI datasets"
    echo "• Monitoring dashboards"
    echo ""
    echo "This action CANNOT be undone!"
    echo ""
    
    # Safety prompt
    read -p "Are you sure you want to continue? (type 'yes' to confirm): " confirmation
    
    if [[ "$confirmation" != "yes" ]]; then
        echo "Cleanup cancelled."
        exit 0
    fi
    
    # Double confirmation for extra safety
    echo ""
    read -p "This will permanently delete all data. Type '$project_id' to confirm: " project_confirmation
    
    if [[ "$project_confirmation" != "$project_id" ]]; then
        echo "Project ID confirmation failed. Cleanup cancelled."
        exit 0
    fi
    
    success "Destruction confirmed. Beginning cleanup..."
}

# Function to remove Cloud Functions
remove_cloud_functions() {
    log "Removing Cloud Functions..."
    
    # Check if function exists before attempting deletion
    if gcloud functions describe digital-twin-simulator --region="$REGION" &>/dev/null; then
        log "Deleting Cloud Function: digital-twin-simulator"
        gcloud functions delete digital-twin-simulator \
            --region="$REGION" \
            --quiet
        success "Cloud Function deleted"
    else
        log "Cloud Function digital-twin-simulator not found (already deleted or never created)"
    fi
}

# Function to remove BigQuery resources
remove_bigquery_resources() {
    log "Removing BigQuery dataset and tables..."
    
    # Check if dataset exists
    if [[ -n "${DATASET_NAME:-}" ]] && bq ls -d "${PROJECT_ID}:${DATASET_NAME}" &>/dev/null; then
        log "Deleting BigQuery dataset: $DATASET_NAME"
        bq rm -r -f "${PROJECT_ID}:${DATASET_NAME}"
        success "BigQuery dataset deleted"
    else
        log "BigQuery dataset not found (already deleted or never created)"
    fi
}

# Function to remove Pub/Sub resources
remove_pubsub_resources() {
    log "Removing Pub/Sub topics and subscriptions..."
    
    # Define subscriptions and topics
    local subscriptions=(
        "sensor-data-processing"
        "simulation-processing"
    )
    
    local topics=(
        "manufacturing-sensor-data"
        "failure-simulation-events"
        "recovery-commands"
    )
    
    # Delete subscriptions first (to avoid dependency issues)
    for subscription in "${subscriptions[@]}"; do
        if gcloud pubsub subscriptions describe "$subscription" &>/dev/null; then
            log "Deleting subscription: $subscription"
            gcloud pubsub subscriptions delete "$subscription" --quiet
            success "Deleted subscription: $subscription"
        else
            log "Subscription $subscription not found"
        fi
    done
    
    # Delete topics
    for topic in "${topics[@]}"; do
        if gcloud pubsub topics describe "$topic" &>/dev/null; then
            log "Deleting topic: $topic"
            gcloud pubsub topics delete "$topic" --quiet
            success "Deleted topic: $topic"
        else
            log "Topic $topic not found"
        fi
    done
}

# Function to remove Cloud Storage bucket
remove_storage_bucket() {
    log "Removing Cloud Storage bucket..."
    
    if [[ -n "${BUCKET_NAME:-}" ]]; then
        # Check if bucket exists
        if gsutil ls "gs://${BUCKET_NAME}" &>/dev/null; then
            log "Deleting storage bucket: $BUCKET_NAME"
            # Remove all objects first, then the bucket
            gsutil -m rm -r "gs://${BUCKET_NAME}" 2>/dev/null || true
            success "Cloud Storage bucket deleted"
        else
            log "Storage bucket $BUCKET_NAME not found"
        fi
    else
        warning "BUCKET_NAME not set, cannot delete storage bucket"
        
        # Try to find buckets with manufacturing-twin prefix
        log "Searching for manufacturing-twin storage buckets..."
        local buckets=$(gsutil ls -p "$PROJECT_ID" | grep "manufacturing-twin-storage" || true)
        
        if [[ -n "$buckets" ]]; then
            warning "Found potential buckets to delete:"
            echo "$buckets"
            
            for bucket in $buckets; do
                read -p "Delete $bucket? (y/n): " delete_bucket
                if [[ "$delete_bucket" == "y" ]]; then
                    gsutil -m rm -r "$bucket" 2>/dev/null || true
                    success "Deleted bucket: $bucket"
                fi
            done
        fi
    fi
}

# Function to remove Vertex AI dataset
remove_vertex_ai_dataset() {
    log "Removing Vertex AI dataset..."
    
    # Try to get dataset ID from environment
    if [[ -n "${DATASET_ID:-}" ]]; then
        if gcloud ai datasets describe "$DATASET_ID" --region="$REGION" &>/dev/null; then
            log "Deleting Vertex AI dataset: $DATASET_ID"
            gcloud ai datasets delete "$DATASET_ID" \
                --region="$REGION" \
                --quiet
            success "Vertex AI dataset deleted"
        else
            log "Vertex AI dataset $DATASET_ID not found"
        fi
    else
        warning "DATASET_ID not set, searching for manufacturing datasets..."
        
        # Search for datasets with manufacturing in the name
        local datasets=$(gcloud ai datasets list --region="$REGION" \
            --filter="displayName:manufacturing" \
            --format="value(name)" 2>/dev/null || true)
        
        if [[ -n "$datasets" ]]; then
            warning "Found potential Vertex AI datasets to delete:"
            
            for dataset in $datasets; do
                local dataset_id=$(echo "$dataset" | cut -d'/' -f6)
                local dataset_name=$(gcloud ai datasets describe "$dataset_id" --region="$REGION" --format="value(displayName)" 2>/dev/null || echo "Unknown")
                
                echo "Dataset ID: $dataset_id, Name: $dataset_name"
                read -p "Delete this dataset? (y/n): " delete_dataset
                
                if [[ "$delete_dataset" == "y" ]]; then
                    gcloud ai datasets delete "$dataset_id" \
                        --region="$REGION" \
                        --quiet
                    success "Deleted dataset: $dataset_id"
                fi
            done
        else
            log "No Vertex AI datasets found with 'manufacturing' in the name"
        fi
    fi
}

# Function to remove monitoring dashboards
remove_monitoring_dashboards() {
    log "Removing monitoring dashboards..."
    
    # Search for dashboards with the specific name
    local dashboards=$(gcloud monitoring dashboards list \
        --filter="displayName:Manufacturing Digital Twin Dashboard" \
        --format="value(name)" 2>/dev/null || true)
    
    if [[ -n "$dashboards" ]]; then
        for dashboard in $dashboards; do
            log "Deleting monitoring dashboard: $dashboard"
            gcloud monitoring dashboards delete "$dashboard" --quiet
            success "Monitoring dashboard deleted"
        done
    else
        log "No monitoring dashboards found with expected name"
    fi
}

# Function to disable APIs (optional)
disable_apis() {
    warning "API disabling is optional and not recommended if other projects use these APIs"
    read -p "Do you want to disable the APIs that were enabled? (y/n): " disable_choice
    
    if [[ "$disable_choice" == "y" ]]; then
        log "Disabling APIs..."
        
        local apis=(
            "cloudfunctions.googleapis.com"
            "aiplatform.googleapis.com"
            "dataflow.googleapis.com"
            "monitoring.googleapis.com"
        )
        
        for api in "${apis[@]}"; do
            log "Disabling $api..."
            gcloud services disable "$api" --quiet 2>/dev/null || warning "Failed to disable $api"
        done
        
        success "APIs disabled"
    else
        log "Skipping API disabling"
    fi
}

# Function to clean up local environment files
cleanup_local_files() {
    log "Cleaning up local environment files..."
    
    if [[ -f "${HOME}/.digital_twin_env" ]]; then
        read -p "Remove local environment file ${HOME}/.digital_twin_env? (y/n): " remove_env
        
        if [[ "$remove_env" == "y" ]]; then
            rm "${HOME}/.digital_twin_env"
            success "Local environment file removed"
        else
            log "Keeping local environment file"
        fi
    else
        log "No local environment file found"
    fi
}

# Function to verify cleanup completion
verify_cleanup() {
    log "Verifying cleanup completion..."
    
    local cleanup_issues=0
    
    # Check Cloud Functions
    if gcloud functions list --regions="$REGION" --filter="name:digital-twin-simulator" --format="value(name)" | grep -q "digital-twin-simulator"; then
        warning "Cloud Function still exists"
        ((cleanup_issues++))
    fi
    
    # Check BigQuery datasets
    if [[ -n "${DATASET_NAME:-}" ]] && bq ls -d "${PROJECT_ID}:${DATASET_NAME}" &>/dev/null; then
        warning "BigQuery dataset still exists"
        ((cleanup_issues++))
    fi
    
    # Check Pub/Sub topics
    local remaining_topics=$(gcloud pubsub topics list --filter="name:manufacturing OR name:failure OR name:recovery" --format="value(name)" 2>/dev/null || true)
    if [[ -n "$remaining_topics" ]]; then
        warning "Some Pub/Sub topics still exist: $remaining_topics"
        ((cleanup_issues++))
    fi
    
    # Check Storage buckets
    if [[ -n "${BUCKET_NAME:-}" ]] && gsutil ls "gs://${BUCKET_NAME}" &>/dev/null; then
        warning "Storage bucket still exists"
        ((cleanup_issues++))
    fi
    
    if [[ $cleanup_issues -eq 0 ]]; then
        success "Cleanup verification passed - all resources removed"
    else
        warning "$cleanup_issues issue(s) found during verification"
        warning "Some resources may still exist and incur charges"
    fi
}

# Function to display cleanup summary
display_cleanup_summary() {
    echo ""
    echo "=================================="
    echo "🧹 CLEANUP COMPLETED"
    echo "=================================="
    echo ""
    echo "Project ID: $PROJECT_ID"
    echo "Region: $REGION"
    echo ""
    echo "Resources Removed:"
    echo "✅ Cloud Functions"
    echo "✅ BigQuery Dataset and Tables"
    echo "✅ Pub/Sub Topics and Subscriptions"
    echo "✅ Cloud Storage Bucket"
    echo "✅ Vertex AI Dataset"
    echo "✅ Monitoring Dashboards"
    echo ""
    echo "Note: Project '$PROJECT_ID' still exists."
    echo "If this was a temporary project, you may want to delete it entirely:"
    echo "gcloud projects delete $PROJECT_ID"
    echo ""
    echo "Please verify in the Google Cloud Console that all expected resources"
    echo "have been removed to avoid unexpected charges."
    echo "=================================="
}

# Main cleanup function
main() {
    echo "🧹 Starting Digital Twin Manufacturing Resilience Cleanup"
    echo "=========================================================="
    
    # Parse command line arguments or load from environment
    if [[ $# -gt 0 ]]; then
        PROJECT_ID="$1"
    else
        # Try to load from environment
        load_environment
        
        # If still not set, try to get from gcloud config
        if [[ -z "${PROJECT_ID:-}" ]]; then
            PROJECT_ID=$(gcloud config get-value project 2>/dev/null || echo "")
        fi
        
        if [[ -z "$PROJECT_ID" ]]; then
            error "PROJECT_ID not provided and cannot be determined from environment"
            error "Usage: ./destroy.sh [PROJECT_ID]"
            exit 1
        fi
    fi
    
    # Set defaults for other variables if not loaded from environment
    REGION=${REGION:-"us-central1"}
    DATASET_NAME=${DATASET_NAME:-"manufacturing_data"}
    
    log "Project ID: $PROJECT_ID"
    log "Region: $REGION"
    echo ""
    
    # Check prerequisites
    check_prerequisites
    
    # Set project context
    gcloud config set project "$PROJECT_ID"
    
    # Confirm destructive operation
    confirm_destruction "$PROJECT_ID"
    
    echo ""
    log "Beginning resource cleanup..."
    
    # Remove resources in reverse order of creation
    # (to handle dependencies properly)
    remove_monitoring_dashboards
    remove_cloud_functions
    remove_vertex_ai_dataset
    remove_storage_bucket
    remove_bigquery_resources
    remove_pubsub_resources
    
    # Optional cleanup steps
    disable_apis
    cleanup_local_files
    
    # Verify cleanup
    verify_cleanup
    
    # Display summary
    display_cleanup_summary
}

# Error handling
trap 'error "Cleanup failed at line $LINENO"' ERR

# Run main function
main "$@"