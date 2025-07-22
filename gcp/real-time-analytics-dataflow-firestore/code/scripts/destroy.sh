#!/bin/bash

# Real-Time Analytics with Cloud Dataflow and Firestore - Cleanup Script
# This script safely removes all resources created by the deployment script including:
# - Dataflow streaming pipeline
# - Pub/Sub topic and subscription
# - Cloud Storage bucket and contents
# - Firestore collections and data
# - Service account and IAM bindings

set -euo pipefail

# Color codes for output
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
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1${NC}"
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites for cleanup..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        error "gcloud CLI is not installed. Please install the Google Cloud SDK."
        exit 1
    fi
    
    # Check if gsutil is available
    if ! command -v gsutil &> /dev/null; then
        error "gsutil is not available. Please ensure Google Cloud SDK is properly installed."
        exit 1
    fi
    
    # Check if user is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 > /dev/null; then
        error "Not authenticated with gcloud. Please run 'gcloud auth login'"
        exit 1
    fi
    
    log "Prerequisites check completed successfully"
}

# Function to load environment variables from deployment state
load_deployment_state() {
    log "Loading deployment state..."
    
    # Check if deployment state file exists
    if [[ ! -f "deployment_state.env" ]]; then
        warn "deployment_state.env file not found. You may need to provide resource names manually."
        
        # Try to get project ID from gcloud config
        PROJECT_ID=$(gcloud config get-value project 2>/dev/null || echo "")
        if [[ -z "$PROJECT_ID" ]]; then
            read -p "Enter your Google Cloud Project ID: " PROJECT_ID
            if [[ -z "$PROJECT_ID" ]]; then
                error "Project ID is required"
                exit 1
            fi
        fi
        
        # Set default region
        REGION="us-central1"
        
        warn "Using default values. Some resources may not be found if they use different naming."
        warn "If you have the original deployment_state.env file, place it in this directory and run the script again."
        
        return
    fi
    
    # Source the deployment state file
    source deployment_state.env
    
    info "Loaded deployment state:"
    info "  Project ID: ${PROJECT_ID}"
    info "  Region: ${REGION}"
    info "  Deployment Timestamp: ${DEPLOYMENT_TIMESTAMP:-'Unknown'}"
    
    # Set gcloud project
    gcloud config set project "${PROJECT_ID}" --quiet
}

# Function to confirm destruction
confirm_destruction() {
    warn "This script will permanently delete the following resources:"
    echo "  - Project: ${PROJECT_ID}"
    echo "  - Dataflow job: ${DATAFLOW_JOB:-'streaming-analytics-*'}"
    echo "  - Pub/Sub topic: ${PUBSUB_TOPIC:-'events-topic-*'}"
    echo "  - Pub/Sub subscription: ${SUBSCRIPTION:-'events-subscription-*'}"
    echo "  - Storage bucket: ${STORAGE_BUCKET:-'*-analytics-archive-*'}"
    echo "  - Service account: ${SERVICE_ACCOUNT_EMAIL:-'dataflow-analytics@*.iam.gserviceaccount.com'}"
    echo "  - Firestore collections: analytics_metrics, user_sessions"
    echo ""
    
    # Skip confirmation if --force flag is provided
    if [[ "${1:-}" == "--force" ]]; then
        warn "Force flag detected, skipping confirmation"
        return
    fi
    
    read -p "Are you sure you want to delete these resources? This action cannot be undone. (yes/no): " confirmation
    if [[ "$confirmation" != "yes" ]]; then
        info "Cleanup cancelled by user"
        exit 0
    fi
    
    warn "Starting cleanup in 5 seconds... Press Ctrl+C to cancel"
    sleep 5
}

# Function to stop and cancel Dataflow pipeline
stop_dataflow_pipeline() {
    log "Stopping Dataflow pipeline..."
    
    if [[ -n "${DATAFLOW_JOB:-}" ]]; then
        # Try to cancel specific job
        if gcloud dataflow jobs cancel "${DATAFLOW_JOB}" --region="${REGION}" --quiet 2>/dev/null; then
            log "Dataflow job '${DATAFLOW_JOB}' cancelled successfully"
        else
            info "Could not cancel specific job '${DATAFLOW_JOB}', it may not exist or already be stopped"
        fi
    else
        # Find and cancel any running streaming analytics jobs
        info "Searching for running streaming analytics jobs..."
        local jobs=$(gcloud dataflow jobs list \
            --filter="name~streaming-analytics AND state=JOB_STATE_RUNNING" \
            --format="value(name)" \
            --region="${REGION}" 2>/dev/null || echo "")
        
        if [[ -n "$jobs" ]]; then
            while IFS= read -r job; do
                if [[ -n "$job" ]]; then
                    info "Cancelling job: $job"
                    if gcloud dataflow jobs cancel "$job" --region="${REGION}" --quiet; then
                        log "Job '$job' cancelled successfully"
                    else
                        warn "Failed to cancel job '$job'"
                    fi
                fi
            done <<< "$jobs"
        else
            info "No running Dataflow jobs found matching pattern"
        fi
    fi
    
    # Wait for jobs to stop
    info "Waiting 30 seconds for jobs to finish cancelling..."
    sleep 30
}

# Function to delete Pub/Sub resources
delete_pubsub_resources() {
    log "Deleting Pub/Sub resources..."
    
    # Delete subscription first
    if [[ -n "${SUBSCRIPTION:-}" ]]; then
        if gcloud pubsub subscriptions delete "${SUBSCRIPTION}" --quiet 2>/dev/null; then
            log "Pub/Sub subscription '${SUBSCRIPTION}' deleted successfully"
        else
            info "Subscription '${SUBSCRIPTION}' not found or already deleted"
        fi
    else
        # Find and delete subscriptions matching pattern
        info "Searching for subscriptions to delete..."
        local subscriptions=$(gcloud pubsub subscriptions list \
            --filter="name~events-subscription" \
            --format="value(name)" 2>/dev/null || echo "")
        
        if [[ -n "$subscriptions" ]]; then
            while IFS= read -r subscription; do
                if [[ -n "$subscription" ]]; then
                    local sub_name=$(basename "$subscription")
                    info "Deleting subscription: $sub_name"
                    if gcloud pubsub subscriptions delete "$sub_name" --quiet; then
                        log "Subscription '$sub_name' deleted successfully"
                    else
                        warn "Failed to delete subscription '$sub_name'"
                    fi
                fi
            done <<< "$subscriptions"
        fi
    fi
    
    # Delete topic
    if [[ -n "${PUBSUB_TOPIC:-}" ]]; then
        if gcloud pubsub topics delete "${PUBSUB_TOPIC}" --quiet 2>/dev/null; then
            log "Pub/Sub topic '${PUBSUB_TOPIC}' deleted successfully"
        else
            info "Topic '${PUBSUB_TOPIC}' not found or already deleted"
        fi
    else
        # Find and delete topics matching pattern
        info "Searching for topics to delete..."
        local topics=$(gcloud pubsub topics list \
            --filter="name~events-topic" \
            --format="value(name)" 2>/dev/null || echo "")
        
        if [[ -n "$topics" ]]; then
            while IFS= read -r topic; do
                if [[ -n "$topic" ]]; then
                    local topic_name=$(basename "$topic")
                    info "Deleting topic: $topic_name"
                    if gcloud pubsub topics delete "$topic_name" --quiet; then
                        log "Topic '$topic_name' deleted successfully"
                    else
                        warn "Failed to delete topic '$topic_name'"
                    fi
                fi
            done <<< "$topics"
        fi
    fi
}

# Function to delete Cloud Storage bucket
delete_storage_bucket() {
    log "Deleting Cloud Storage bucket..."
    
    if [[ -n "${STORAGE_BUCKET:-}" ]]; then
        # Check if bucket exists
        if gsutil ls -b "gs://${STORAGE_BUCKET}" &>/dev/null; then
            info "Deleting all objects in bucket gs://${STORAGE_BUCKET}..."
            # Delete all objects and versions
            if gsutil -m rm -r "gs://${STORAGE_BUCKET}/**" 2>/dev/null || true; then
                info "Objects deleted from bucket"
            fi
            
            # Delete the bucket itself
            if gsutil rb "gs://${STORAGE_BUCKET}"; then
                log "Storage bucket 'gs://${STORAGE_BUCKET}' deleted successfully"
            else
                warn "Failed to delete storage bucket 'gs://${STORAGE_BUCKET}'"
            fi
        else
            info "Storage bucket 'gs://${STORAGE_BUCKET}' not found or already deleted"
        fi
    else
        # Find and delete buckets matching pattern
        info "Searching for storage buckets to delete..."
        local buckets=$(gsutil ls -p "${PROJECT_ID}" 2>/dev/null | grep "analytics-archive" || echo "")
        
        if [[ -n "$buckets" ]]; then
            while IFS= read -r bucket; do
                if [[ -n "$bucket" && "$bucket" =~ analytics-archive ]]; then
                    info "Deleting bucket: $bucket"
                    # Delete all objects first
                    if gsutil -m rm -r "${bucket}**" 2>/dev/null || true; then
                        info "Objects deleted from $bucket"
                    fi
                    # Delete bucket
                    if gsutil rb "$bucket"; then
                        log "Bucket '$bucket' deleted successfully"
                    else
                        warn "Failed to delete bucket '$bucket'"
                    fi
                fi
            done <<< "$buckets"
        fi
    fi
}

# Function to clean up Firestore collections
cleanup_firestore_data() {
    log "Cleaning up Firestore collections..."
    
    # Install required library if not already installed
    if ! python3 -c "import google.cloud.firestore" 2>/dev/null; then
        info "Installing google-cloud-firestore..."
        python3 -m pip install google-cloud-firestore --quiet
    fi
    
    # Create cleanup script
    cat > cleanup_firestore.py << 'EOF'
import sys
from google.cloud import firestore
import logging

def cleanup_collection(db, collection_name, batch_size=500):
    """Delete all documents in a collection"""
    try:
        collection_ref = db.collection(collection_name)
        docs = collection_ref.limit(batch_size).stream()
        
        deleted = 0
        batch = db.batch()
        
        for doc in docs:
            batch.delete(doc.reference)
            deleted += 1
            
            if deleted % 100 == 0:
                batch.commit()
                print(f"Deleted {deleted} documents from {collection_name}")
                batch = db.batch()
        
        # Commit any remaining deletes
        if deleted % 100 != 0:
            batch.commit()
        
        print(f"Total documents deleted from {collection_name}: {deleted}")
        return deleted
        
    except Exception as e:
        print(f"Error cleaning up collection {collection_name}: {e}")
        return 0

def main():
    if len(sys.argv) != 2:
        print("Usage: python cleanup_firestore.py PROJECT_ID")
        sys.exit(1)
    
    project_id = sys.argv[1]
    
    try:
        db = firestore.Client(project=project_id)
        
        # Clean up analytics_metrics collection
        print("Cleaning up analytics_metrics collection...")
        deleted_metrics = cleanup_collection(db, 'analytics_metrics')
        
        # Clean up user_sessions collection
        print("Cleaning up user_sessions collection...")
        deleted_sessions = cleanup_collection(db, 'user_sessions')
        
        print(f"Firestore cleanup completed:")
        print(f"  analytics_metrics: {deleted_metrics} documents deleted")
        print(f"  user_sessions: {deleted_sessions} documents deleted")
        
    except Exception as e:
        print(f"Error during Firestore cleanup: {e}")
        sys.exit(1)

if __name__ == '__main__':
    main()
EOF
    
    # Run Firestore cleanup
    if python3 cleanup_firestore.py "${PROJECT_ID}"; then
        log "Firestore collections cleaned up successfully"
    else
        warn "Firestore cleanup encountered some issues"
    fi
    
    # Clean up temporary script
    rm -f cleanup_firestore.py
}

# Function to remove service account and IAM bindings
remove_service_account() {
    log "Removing service account and IAM bindings..."
    
    local service_account_email="${SERVICE_ACCOUNT_EMAIL:-dataflow-analytics@${PROJECT_ID}.iam.gserviceaccount.com}"
    
    # Check if service account exists
    if gcloud iam service-accounts describe "${service_account_email}" --quiet &>/dev/null; then
        # Remove IAM policy bindings
        local roles=(
            "roles/dataflow.worker"
            "roles/pubsub.subscriber"
            "roles/datastore.user"
            "roles/storage.admin"
            "roles/compute.instanceAdmin.v1"
        )
        
        for role in "${roles[@]}"; do
            info "Removing IAM binding for role ${role}..."
            if gcloud projects remove-iam-policy-binding "${PROJECT_ID}" \
                --member="serviceAccount:${service_account_email}" \
                --role="${role}" \
                --quiet 2>/dev/null; then
                log "IAM binding for role ${role} removed successfully"
            else
                info "IAM binding for role ${role} not found or already removed"
            fi
        done
        
        # Delete service account
        if gcloud iam service-accounts delete "${service_account_email}" --quiet; then
            log "Service account '${service_account_email}' deleted successfully"
        else
            warn "Failed to delete service account '${service_account_email}'"
        fi
    else
        info "Service account '${service_account_email}' not found or already deleted"
    fi
}

# Function to clean up local files
cleanup_local_files() {
    log "Cleaning up local files..."
    
    local files_to_remove=(
        "deployment_state.env"
        "generate_events.py"
        "dashboard_queries.py"
        "index.yaml"
        "lifecycle.json"
        "cleanup_firestore.py"
    )
    
    for file in "${files_to_remove[@]}"; do
        if [[ -f "$file" ]]; then
            rm -f "$file"
            info "Removed file: $file"
        fi
    done
    
    # Remove dataflow-pipeline directory
    if [[ -d "dataflow-pipeline" ]]; then
        rm -rf "dataflow-pipeline"
        info "Removed directory: dataflow-pipeline"
    fi
}

# Function to verify cleanup
verify_cleanup() {
    log "Verifying cleanup..."
    
    local cleanup_issues=0
    
    # Check for remaining Dataflow jobs
    info "Checking for remaining Dataflow jobs..."
    local remaining_jobs=$(gcloud dataflow jobs list \
        --filter="name~streaming-analytics AND state=JOB_STATE_RUNNING" \
        --format="value(name)" \
        --region="${REGION}" 2>/dev/null | wc -l)
    
    if [[ "$remaining_jobs" -gt 0 ]]; then
        warn "Found $remaining_jobs remaining Dataflow job(s)"
        cleanup_issues=$((cleanup_issues + 1))
    else
        log "No remaining Dataflow jobs found"
    fi
    
    # Check for remaining Pub/Sub resources
    info "Checking for remaining Pub/Sub resources..."
    local remaining_topics=$(gcloud pubsub topics list \
        --filter="name~events-topic" \
        --format="value(name)" 2>/dev/null | wc -l)
    local remaining_subscriptions=$(gcloud pubsub subscriptions list \
        --filter="name~events-subscription" \
        --format="value(name)" 2>/dev/null | wc -l)
    
    if [[ "$remaining_topics" -gt 0 ]] || [[ "$remaining_subscriptions" -gt 0 ]]; then
        warn "Found remaining Pub/Sub resources: $remaining_topics topics, $remaining_subscriptions subscriptions"
        cleanup_issues=$((cleanup_issues + 1))
    else
        log "No remaining Pub/Sub resources found"
    fi
    
    # Check for remaining storage buckets
    info "Checking for remaining storage buckets..."
    local remaining_buckets=$(gsutil ls -p "${PROJECT_ID}" 2>/dev/null | grep -c "analytics-archive" || echo "0")
    
    if [[ "$remaining_buckets" -gt 0 ]]; then
        warn "Found $remaining_buckets remaining storage bucket(s)"
        cleanup_issues=$((cleanup_issues + 1))
    else
        log "No remaining storage buckets found"
    fi
    
    # Check for service account
    info "Checking for remaining service account..."
    local service_account_email="${SERVICE_ACCOUNT_EMAIL:-dataflow-analytics@${PROJECT_ID}.iam.gserviceaccount.com}"
    if gcloud iam service-accounts describe "${service_account_email}" --quiet &>/dev/null; then
        warn "Service account still exists: ${service_account_email}"
        cleanup_issues=$((cleanup_issues + 1))
    else
        log "Service account successfully removed"
    fi
    
    if [[ "$cleanup_issues" -eq 0 ]]; then
        log "Cleanup verification completed successfully - no issues found"
    else
        warn "Cleanup verification found $cleanup_issues issue(s) - some resources may need manual cleanup"
    fi
}

# Function to display cleanup summary
display_cleanup_summary() {
    log "Cleanup Summary"
    echo "==============="
    echo "The following resources have been cleaned up:"
    echo "✓ Dataflow streaming pipeline"
    echo "✓ Pub/Sub topic and subscription"
    echo "✓ Cloud Storage bucket and contents"
    echo "✓ Firestore collections and data"
    echo "✓ Service account and IAM bindings"
    echo "✓ Local files and directories"
    echo ""
    echo "Project: ${PROJECT_ID}"
    echo "Region: ${REGION}"
    echo ""
    info "If you encounter any remaining resources, you can manually delete them through the Google Cloud Console."
    info "Check for costs in the Cloud Billing console to ensure all billable resources are removed."
}

# Main cleanup function
main() {
    local force_flag="${1:-}"
    
    log "Starting cleanup of Real-Time Analytics with Cloud Dataflow and Firestore"
    
    check_prerequisites
    load_deployment_state
    confirm_destruction "$force_flag"
    stop_dataflow_pipeline
    delete_pubsub_resources
    delete_storage_bucket
    cleanup_firestore_data
    remove_service_account
    cleanup_local_files
    verify_cleanup
    display_cleanup_summary
    
    log "Cleanup completed successfully!"
    log "All resources from the streaming analytics deployment have been removed."
}

# Error handling
trap 'error "Cleanup failed. Check the logs above for details. Some resources may need manual cleanup."; exit 1' ERR

# Check for help flag
if [[ "${1:-}" == "--help" ]] || [[ "${1:-}" == "-h" ]]; then
    echo "Real-Time Analytics Cleanup Script"
    echo ""
    echo "Usage: $0 [--force]"
    echo ""
    echo "Options:"
    echo "  --force    Skip confirmation prompt and proceed with cleanup"
    echo "  --help     Show this help message"
    echo ""
    echo "This script will remove all resources created by the deployment script."
    echo "Make sure you have the deployment_state.env file in the current directory."
    exit 0
fi

# Run main function
main "$@"