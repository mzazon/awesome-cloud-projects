#!/bin/bash

# Multi-Cloud Resource Discovery with Cloud Location Finder and Pub/Sub - Cleanup Script
# This script safely removes all infrastructure resources created by the deploy.sh script
# including Cloud Functions, Pub/Sub, Cloud Storage, monitoring, and optionally the project.

set -euo pipefail

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

# Error handling function
handle_error() {
    log_error "Cleanup failed at line $1"
    log_error "Command: $BASH_COMMAND"
    log_error "Some resources may remain - please check manually"
    exit 1
}

trap 'handle_error $LINENO' ERR

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/.env"

# Display banner
echo -e "${RED}"
echo "======================================================================="
echo "  Multi-Cloud Resource Discovery Cleanup Script"
echo "  Provider: Google Cloud Platform"
echo "  Recipe: multi-cloud-resource-discovery-location-finder-pub-sub"
echo "======================================================================="
echo -e "${NC}"

# Function to load environment variables
load_environment() {
    log_info "Loading environment variables from deployment..."
    
    if [[ ! -f "$ENV_FILE" ]]; then
        log_error "Environment file not found: $ENV_FILE"
        log_error "Either the deployment was not completed or files were moved"
        log_error "Please provide environment variables manually:"
        
        read -p "Enter PROJECT_ID: " PROJECT_ID
        read -p "Enter REGION (default: us-central1): " REGION
        read -p "Enter TOPIC_NAME: " TOPIC_NAME
        read -p "Enter FUNCTION_NAME: " FUNCTION_NAME
        read -p "Enter BUCKET_NAME: " BUCKET_NAME
        read -p "Enter SCHEDULER_JOB: " SCHEDULER_JOB
        
        REGION="${REGION:-us-central1}"
        
        export PROJECT_ID REGION TOPIC_NAME FUNCTION_NAME BUCKET_NAME SCHEDULER_JOB
        log_info "Manual environment variables set"
    else
        source "$ENV_FILE"
        log_success "Environment variables loaded from $ENV_FILE"
    fi
    
    # Validate required variables
    if [[ -z "${PROJECT_ID:-}" ]]; then
        log_error "PROJECT_ID is not set"
        exit 1
    fi
    
    log_info "Cleanup Configuration:"
    log_info "  • Project: ${PROJECT_ID}"
    log_info "  • Region: ${REGION:-unknown}"
    log_info "  • Topic: ${TOPIC_NAME:-unknown}"
    log_info "  • Function: ${FUNCTION_NAME:-unknown}"
    log_info "  • Bucket: ${BUCKET_NAME:-unknown}"
    log_info "  • Scheduler: ${SCHEDULER_JOB:-unknown}"
}

# Function to confirm destruction
confirm_destruction() {
    echo ""
    log_warning "⚠️  DESTRUCTIVE OPERATION WARNING ⚠️"
    log_warning "This script will permanently delete the following resources:"
    echo ""
    log_info "  • Cloud Scheduler Job: ${SCHEDULER_JOB:-N/A}"
    log_info "  • Cloud Function: ${FUNCTION_NAME:-N/A}"
    log_info "  • Cloud Storage Bucket: ${BUCKET_NAME:-N/A} (and all contents)"
    log_info "  • Pub/Sub Topic and Subscription: ${TOPIC_NAME:-N/A}"
    log_info "  • Monitoring Dashboards and Alert Policies"
    echo ""
    log_warning "This action CANNOT be undone!"
    echo ""
    
    read -p "Are you sure you want to proceed? (type 'yes' to confirm): " confirmation
    
    if [[ "$confirmation" != "yes" ]]; then
        log_info "Cleanup cancelled by user"
        exit 0
    fi
    
    echo ""
    read -p "Do you want to delete the entire project '$PROJECT_ID'? (y/N): " delete_project
    DELETE_PROJECT=false
    if [[ "$delete_project" =~ ^[Yy]$ ]]; then
        DELETE_PROJECT=true
        log_warning "Project deletion selected - this will remove ALL resources in the project"
    fi
}

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites for cleanup..."
    
    # Check if gcloud CLI is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "Google Cloud CLI (gcloud) is not installed or not in PATH"
        exit 1
    fi
    
    # Check if user is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 > /dev/null; then
        log_error "No active gcloud authentication found"
        log_error "Please run: gcloud auth login"
        exit 1
    fi
    
    ACTIVE_ACCOUNT=$(gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1)
    log_info "Active account: $ACTIVE_ACCOUNT"
    
    # Set project context
    gcloud config set project "$PROJECT_ID" 2>/dev/null || {
        log_error "Cannot set project context for $PROJECT_ID"
        log_error "Project may not exist or you may not have access"
        exit 1
    }
    
    log_success "Prerequisites check completed"
}

# Function to remove Cloud Scheduler job
remove_scheduler_job() {
    if [[ -n "${SCHEDULER_JOB:-}" ]]; then
        log_info "Removing Cloud Scheduler job: $SCHEDULER_JOB"
        
        if gcloud scheduler jobs describe "$SCHEDULER_JOB" --location="${REGION}" --project="$PROJECT_ID" &>/dev/null; then
            gcloud scheduler jobs delete "$SCHEDULER_JOB" \
                --location="${REGION}" \
                --project="$PROJECT_ID" \
                --quiet
            log_success "Cloud Scheduler job removed: $SCHEDULER_JOB"
        else
            log_warning "Cloud Scheduler job not found: $SCHEDULER_JOB"
        fi
    else
        log_warning "SCHEDULER_JOB not defined, skipping"
    fi
}

# Function to remove Cloud Function
remove_cloud_function() {
    if [[ -n "${FUNCTION_NAME:-}" ]]; then
        log_info "Removing Cloud Function: $FUNCTION_NAME"
        
        if gcloud functions describe "$FUNCTION_NAME" --region="${REGION}" --project="$PROJECT_ID" &>/dev/null; then
            gcloud functions delete "$FUNCTION_NAME" \
                --region="${REGION}" \
                --project="$PROJECT_ID" \
                --quiet
            log_success "Cloud Function removed: $FUNCTION_NAME"
        else
            log_warning "Cloud Function not found: $FUNCTION_NAME"
        fi
    else
        log_warning "FUNCTION_NAME not defined, skipping"
    fi
}

# Function to remove Cloud Storage bucket
remove_storage_bucket() {
    if [[ -n "${BUCKET_NAME:-}" ]]; then
        log_info "Removing Cloud Storage bucket: $BUCKET_NAME"
        
        if gsutil ls "gs://$BUCKET_NAME" &>/dev/null; then
            # Remove all objects and versions
            log_info "Removing all objects from bucket..."
            gsutil -m rm -r "gs://$BUCKET_NAME/**" 2>/dev/null || log_warning "No objects to remove"
            
            # Remove bucket
            gsutil rb "gs://$BUCKET_NAME"
            log_success "Cloud Storage bucket removed: $BUCKET_NAME"
        else
            log_warning "Cloud Storage bucket not found: $BUCKET_NAME"
        fi
    else
        log_warning "BUCKET_NAME not defined, skipping"
    fi
}

# Function to remove Pub/Sub resources
remove_pubsub_resources() {
    if [[ -n "${TOPIC_NAME:-}" ]]; then
        log_info "Removing Pub/Sub resources for topic: $TOPIC_NAME"
        
        # Remove subscription first
        local subscription_name="${TOPIC_NAME}-sub"
        if gcloud pubsub subscriptions describe "$subscription_name" --project="$PROJECT_ID" &>/dev/null; then
            gcloud pubsub subscriptions delete "$subscription_name" \
                --project="$PROJECT_ID" \
                --quiet
            log_success "Pub/Sub subscription removed: $subscription_name"
        else
            log_warning "Pub/Sub subscription not found: $subscription_name"
        fi
        
        # Remove topic
        if gcloud pubsub topics describe "$TOPIC_NAME" --project="$PROJECT_ID" &>/dev/null; then
            gcloud pubsub topics delete "$TOPIC_NAME" \
                --project="$PROJECT_ID" \
                --quiet
            log_success "Pub/Sub topic removed: $TOPIC_NAME"
        else
            log_warning "Pub/Sub topic not found: $TOPIC_NAME"
        fi
    else
        log_warning "TOPIC_NAME not defined, skipping"
    fi
}

# Function to remove monitoring resources
remove_monitoring_resources() {
    log_info "Removing monitoring dashboards and alert policies..."
    
    # Remove custom dashboards
    local dashboard_filter="displayName:'Multi-Cloud Location Discovery Dashboard'"
    local dashboard_ids=$(gcloud monitoring dashboards list \
        --filter="$dashboard_filter" \
        --format="value(name)" \
        --project="$PROJECT_ID" 2>/dev/null || echo "")
    
    if [[ -n "$dashboard_ids" ]]; then
        while IFS= read -r dashboard_id; do
            if [[ -n "$dashboard_id" ]]; then
                gcloud monitoring dashboards delete "$dashboard_id" \
                    --project="$PROJECT_ID" \
                    --quiet
                log_success "Monitoring dashboard removed: $dashboard_id"
            fi
        done <<< "$dashboard_ids"
    else
        log_warning "No custom monitoring dashboards found"
    fi
    
    # Remove alert policies
    local policy_filter="displayName:'Location Discovery Function Failures'"
    local policy_ids=$(gcloud alpha monitoring policies list \
        --filter="$policy_filter" \
        --format="value(name)" \
        --project="$PROJECT_ID" 2>/dev/null || echo "")
    
    if [[ -n "$policy_ids" ]]; then
        while IFS= read -r policy_id; do
            if [[ -n "$policy_id" ]]; then
                gcloud alpha monitoring policies delete "$policy_id" \
                    --project="$PROJECT_ID" \
                    --quiet
                log_success "Alert policy removed: $policy_id"
            fi
        done <<< "$policy_ids"
    else
        log_warning "No custom alert policies found"
    fi
}

# Function to clean up temporary files
cleanup_local_files() {
    log_info "Cleaning up local temporary files..."
    
    # Remove environment file
    if [[ -f "$ENV_FILE" ]]; then
        rm -f "$ENV_FILE"
        log_success "Environment file removed: $ENV_FILE"
    fi
    
    # Remove any temporary files that might exist
    local temp_files=(
        "/tmp/dashboard-config.json"
        "/tmp/alert-policy.json"
    )
    
    for file in "${temp_files[@]}"; do
        if [[ -f "$file" ]]; then
            rm -f "$file"
            log_success "Temporary file removed: $file"
        fi
    done
    
    log_success "Local cleanup completed"
}

# Function to delete entire project
delete_project() {
    if [[ "$DELETE_PROJECT" == true ]]; then
        log_warning "Deleting entire project: $PROJECT_ID"
        echo ""
        log_warning "⚠️  FINAL WARNING ⚠️"
        log_warning "You are about to delete the ENTIRE project: $PROJECT_ID"
        log_warning "This will remove ALL resources in the project, not just the ones created by this recipe"
        log_warning "This action is IRREVERSIBLE!"
        echo ""
        
        read -p "Type the project ID '$PROJECT_ID' to confirm deletion: " project_confirmation
        
        if [[ "$project_confirmation" == "$PROJECT_ID" ]]; then
            gcloud projects delete "$PROJECT_ID" --quiet
            log_success "Project deletion initiated: $PROJECT_ID"
            log_info "Project deletion is asynchronous and may take several minutes"
            log_info "All billing for this project will stop once deletion is complete"
        else
            log_warning "Project ID mismatch - project deletion cancelled"
            log_info "Individual resources have been cleaned up"
        fi
    fi
}

# Function to verify cleanup completion
verify_cleanup() {
    if [[ "$DELETE_PROJECT" == true ]]; then
        log_info "Project deletion in progress - verification skipped"
        return
    fi
    
    log_info "Verifying cleanup completion..."
    
    local issues_found=false
    
    # Check for remaining Cloud Functions
    if [[ -n "${FUNCTION_NAME:-}" ]]; then
        if gcloud functions describe "$FUNCTION_NAME" --region="${REGION}" --project="$PROJECT_ID" &>/dev/null; then
            log_warning "Cloud Function still exists: $FUNCTION_NAME"
            issues_found=true
        fi
    fi
    
    # Check for remaining Storage buckets
    if [[ -n "${BUCKET_NAME:-}" ]]; then
        if gsutil ls "gs://$BUCKET_NAME" &>/dev/null; then
            log_warning "Storage bucket still exists: $BUCKET_NAME"
            issues_found=true
        fi
    fi
    
    # Check for remaining Pub/Sub topics
    if [[ -n "${TOPIC_NAME:-}" ]]; then
        if gcloud pubsub topics describe "$TOPIC_NAME" --project="$PROJECT_ID" &>/dev/null; then
            log_warning "Pub/Sub topic still exists: $TOPIC_NAME"
            issues_found=true
        fi
    fi
    
    if [[ "$issues_found" == false ]]; then
        log_success "Cleanup verification completed - no remaining resources detected"
    else
        log_warning "Some resources may still exist - please check manually"
    fi
}

# Function to display cleanup summary
display_summary() {
    echo ""
    if [[ "$DELETE_PROJECT" == true ]]; then
        log_success "=== PROJECT DELETION INITIATED ==="
        echo ""
        log_info "Project '$PROJECT_ID' deletion has been started"
        log_info "This process is asynchronous and may take several minutes"
        log_info "All resources will be removed automatically"
        log_info "Billing will stop once deletion is complete"
    else
        log_success "=== CLEANUP COMPLETED SUCCESSFULLY ==="
        echo ""
        log_info "Removed Resources:"
        log_info "  • Cloud Scheduler Job: ${SCHEDULER_JOB:-N/A}"
        log_info "  • Cloud Function: ${FUNCTION_NAME:-N/A}"
        log_info "  • Cloud Storage Bucket: ${BUCKET_NAME:-N/A}"
        log_info "  • Pub/Sub Topic: ${TOPIC_NAME:-N/A}"
        log_info "  • Monitoring Resources: Dashboards and Alert Policies"
        log_info "  • Local Environment Files"
        echo ""
        log_info "Project '$PROJECT_ID' has been preserved"
        log_info "You may want to disable billing or delete the project manually if no longer needed"
    fi
    echo ""
    log_success "Multi-cloud resource discovery infrastructure cleanup completed"
    echo ""
}

# Main cleanup function
main() {
    local start_time=$(date +%s)
    
    load_environment
    confirm_destruction
    check_prerequisites
    
    if [[ "$DELETE_PROJECT" != true ]]; then
        remove_scheduler_job
        remove_cloud_function
        remove_storage_bucket
        remove_pubsub_resources
        remove_monitoring_resources
        verify_cleanup
    fi
    
    cleanup_local_files
    delete_project
    
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    display_summary
    log_success "Total cleanup time: ${duration} seconds"
}

# Cleanup on script exit
cleanup() {
    # Remove any temporary files created during cleanup
    local temp_files=(
        "/tmp/dashboard-config.json"
        "/tmp/alert-policy.json"
    )
    
    for file in "${temp_files[@]}"; do
        if [[ -f "$file" ]]; then
            rm -f "$file" 2>/dev/null || true
        fi
    done
}

trap cleanup EXIT

# Run main function
main "$@"