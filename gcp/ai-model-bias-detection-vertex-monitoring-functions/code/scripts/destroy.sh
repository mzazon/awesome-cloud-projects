#!/bin/bash

# AI Model Bias Detection with Vertex AI Monitoring and Functions - Cleanup Script
# This script safely removes all infrastructure created by the bias detection deployment

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

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"
FUNCTIONS_DIR="$PROJECT_ROOT/bias-functions"

# Configuration (can be overridden via environment variables)
export PROJECT_ID="${PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}"
export REGION="${REGION:-$(gcloud config get-value compute/region 2>/dev/null || echo 'us-central1')}"

# Resource names (must match deployment script)
export BUCKET_NAME="${BUCKET_NAME:-}"
export FUNCTION_NAME="${FUNCTION_NAME:-bias-detection-processor}"
export ALERT_FUNCTION_NAME="${ALERT_FUNCTION_NAME:-bias-alert-handler}"
export REPORT_FUNCTION_NAME="${REPORT_FUNCTION_NAME:-bias-report-generator}"
export TOPIC_NAME="${TOPIC_NAME:-model-monitoring-alerts}"
export SCHEDULER_JOB_NAME="${SCHEDULER_JOB_NAME:-bias-audit-scheduler}"

# Cleanup configuration
FORCE_DELETE="${FORCE_DELETE:-false}"
SKIP_CONFIRMATION="${SKIP_CONFIRMATION:-false}"
DELETE_PROJECT="${DELETE_PROJECT:-false}"

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites for cleanup..."
    
    # Check if gcloud CLI is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "Google Cloud CLI (gcloud) is not installed or not in PATH"
        exit 1
    fi
    
    # Check if authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 | grep -q "."; then
        log_error "Not authenticated with Google Cloud"
        log_error "Please run: gcloud auth login"
        exit 1
    fi
    
    # Check if project is set
    if [[ -z "$PROJECT_ID" ]]; then
        log_error "PROJECT_ID is not set"
        log_error "Please set PROJECT_ID environment variable or use gcloud config set project"
        exit 1
    fi
    
    # Verify project exists and user has access
    if ! gcloud projects describe "$PROJECT_ID" &> /dev/null; then
        log_error "Project $PROJECT_ID does not exist or you don't have access"
        exit 1
    fi
    
    # Set project context
    gcloud config set project "$PROJECT_ID" &> /dev/null
    
    log_success "Prerequisites met for cleanup"
}

# Function to discover resources automatically
discover_resources() {
    log_info "Discovering resources to clean up..."
    
    # Discover buckets with bias-detection prefix
    if [[ -z "$BUCKET_NAME" ]]; then
        local buckets
        buckets=$(gsutil ls -p "$PROJECT_ID" 2>/dev/null | grep -E "gs://bias-detection-reports-[a-f0-9]{6}/" | head -1 || true)
        if [[ -n "$buckets" ]]; then
            BUCKET_NAME=$(echo "$buckets" | sed 's|gs://||' | sed 's|/||')
            log_info "Discovered bucket: $BUCKET_NAME"
        fi
    fi
    
    # Verify functions exist
    local functions_found=0
    for func in "$FUNCTION_NAME" "$ALERT_FUNCTION_NAME" "$REPORT_FUNCTION_NAME"; do
        if gcloud functions describe "$func" --gen2 --region="$REGION" &> /dev/null; then
            log_info "Found function: $func"
            ((functions_found++))
        fi
    done
    
    # Verify scheduler job exists
    if gcloud scheduler jobs describe "$SCHEDULER_JOB_NAME" --location="$REGION" &> /dev/null; then
        log_info "Found scheduler job: $SCHEDULER_JOB_NAME"
    fi
    
    # Verify Pub/Sub resources exist
    if gcloud pubsub topics describe "$TOPIC_NAME" &> /dev/null; then
        log_info "Found Pub/Sub topic: $TOPIC_NAME"
    fi
    
    if gcloud pubsub subscriptions describe bias-detection-sub &> /dev/null; then
        log_info "Found Pub/Sub subscription: bias-detection-sub"
    fi
    
    log_success "Resource discovery completed"
}

# Function to confirm cleanup
confirm_cleanup() {
    if [[ "$SKIP_CONFIRMATION" == "true" ]]; then
        return 0
    fi
    
    echo ""
    log_warning "⚠️  DESTRUCTIVE ACTION WARNING ⚠️"
    echo ""
    echo "This will permanently delete the following resources:"
    echo "- Cloud Scheduler job: $SCHEDULER_JOB_NAME"
    echo "- Cloud Functions: $FUNCTION_NAME, $ALERT_FUNCTION_NAME, $REPORT_FUNCTION_NAME"
    echo "- Pub/Sub topic and subscription: $TOPIC_NAME, bias-detection-sub"
    
    if [[ -n "$BUCKET_NAME" ]]; then
        echo "- Cloud Storage bucket and ALL data: $BUCKET_NAME"
    fi
    
    if [[ "$DELETE_PROJECT" == "true" ]]; then
        echo "- ENTIRE PROJECT: $PROJECT_ID (ALL RESOURCES WILL BE DELETED)"
    fi
    
    echo ""
    echo "Local cleanup:"
    echo "- Function source code directory: $FUNCTIONS_DIR"
    echo "- Monitoring configuration file"
    echo ""
    
    if [[ "$DELETE_PROJECT" == "true" ]]; then
        log_warning "PROJECT DELETION WILL REMOVE ALL RESOURCES AND CANNOT BE UNDONE!"
        echo ""
        echo "Type 'DELETE PROJECT' to confirm project deletion:"
        read -r confirmation
        if [[ "$confirmation" != "DELETE PROJECT" ]]; then
            log_info "Cleanup cancelled by user"
            exit 0
        fi
    else
        echo "Type 'DELETE' to confirm resource deletion:"
        read -r confirmation
        if [[ "$confirmation" != "DELETE" ]]; then
            log_info "Cleanup cancelled by user"
            exit 0
        fi
    fi
}

# Function to delete Cloud Scheduler job
delete_scheduler_job() {
    log_info "Deleting Cloud Scheduler job..."
    
    if gcloud scheduler jobs describe "$SCHEDULER_JOB_NAME" --location="$REGION" &> /dev/null; then
        if gcloud scheduler jobs delete "$SCHEDULER_JOB_NAME" \
            --location="$REGION" \
            --quiet; then
            log_success "Cloud Scheduler job deleted: $SCHEDULER_JOB_NAME"
        else
            log_warning "Failed to delete scheduler job (may not exist)"
        fi
    else
        log_info "Scheduler job $SCHEDULER_JOB_NAME not found, skipping"
    fi
}

# Function to delete Cloud Functions
delete_cloud_functions() {
    log_info "Deleting Cloud Functions..."
    
    local functions=("$FUNCTION_NAME" "$ALERT_FUNCTION_NAME" "$REPORT_FUNCTION_NAME")
    
    for func in "${functions[@]}"; do
        if gcloud functions describe "$func" --gen2 --region="$REGION" &> /dev/null; then
            log_info "Deleting function: $func"
            if gcloud functions delete "$func" \
                --gen2 \
                --region="$REGION" \
                --quiet; then
                log_success "Function deleted: $func"
            else
                log_error "Failed to delete function: $func"
                if [[ "$FORCE_DELETE" != "true" ]]; then
                    exit 1
                fi
            fi
        else
            log_info "Function $func not found, skipping"
        fi
    done
    
    log_success "Cloud Functions cleanup completed"
}

# Function to delete Pub/Sub resources
delete_pubsub_resources() {
    log_info "Deleting Pub/Sub resources..."
    
    # Delete subscription first
    if gcloud pubsub subscriptions describe bias-detection-sub &> /dev/null; then
        if gcloud pubsub subscriptions delete bias-detection-sub --quiet; then
            log_success "Pub/Sub subscription deleted: bias-detection-sub"
        else
            log_warning "Failed to delete Pub/Sub subscription"
        fi
    else
        log_info "Pub/Sub subscription bias-detection-sub not found, skipping"
    fi
    
    # Delete topic
    if gcloud pubsub topics describe "$TOPIC_NAME" &> /dev/null; then
        if gcloud pubsub topics delete "$TOPIC_NAME" --quiet; then
            log_success "Pub/Sub topic deleted: $TOPIC_NAME"
        else
            log_warning "Failed to delete Pub/Sub topic"
        fi
    else
        log_info "Pub/Sub topic $TOPIC_NAME not found, skipping"
    fi
}

# Function to delete Cloud Storage bucket
delete_storage_bucket() {
    if [[ -z "$BUCKET_NAME" ]]; then
        log_info "No bucket name specified, skipping bucket deletion"
        return 0
    fi
    
    log_info "Deleting Cloud Storage bucket: $BUCKET_NAME"
    
    # Check if bucket exists
    if gsutil ls -b "gs://$BUCKET_NAME" &> /dev/null; then
        # Get object count for user information
        local object_count
        object_count=$(gsutil ls -l "gs://$BUCKET_NAME/**" 2>/dev/null | grep -v "TOTAL:" | wc -l || echo "0")
        
        if [[ "$object_count" -gt 0 ]]; then
            log_warning "Bucket contains $object_count objects"
        fi
        
        # Remove all objects and bucket
        if gsutil -m rm -r "gs://$BUCKET_NAME"; then
            log_success "Cloud Storage bucket deleted: $BUCKET_NAME"
        else
            log_error "Failed to delete Cloud Storage bucket"
            if [[ "$FORCE_DELETE" != "true" ]]; then
                exit 1
            fi
        fi
    else
        log_info "Bucket $BUCKET_NAME not found, skipping"
    fi
}

# Function to clean up local files
cleanup_local_files() {
    log_info "Cleaning up local files..."
    
    # Remove function source code
    if [[ -d "$FUNCTIONS_DIR" ]]; then
        if rm -rf "$FUNCTIONS_DIR"; then
            log_success "Function source code directory removed"
        else
            log_warning "Failed to remove function source code directory"
        fi
    else
        log_info "Function source code directory not found, skipping"
    fi
    
    # Remove monitoring configuration
    local monitoring_config="$PROJECT_ROOT/monitoring-config.json"
    if [[ -f "$monitoring_config" ]]; then
        if rm -f "$monitoring_config"; then
            log_success "Monitoring configuration file removed"
        else
            log_warning "Failed to remove monitoring configuration file"
        fi
    else
        log_info "Monitoring configuration file not found, skipping"
    fi
    
    # Clear environment variables
    unset PROJECT_ID REGION ZONE BUCKET_NAME FUNCTION_NAME
    unset ALERT_FUNCTION_NAME REPORT_FUNCTION_NAME TOPIC_NAME
    unset SCHEDULER_JOB_NAME MODEL_NAME
    
    log_success "Local cleanup completed"
}

# Function to delete entire project (optional)
delete_project() {
    if [[ "$DELETE_PROJECT" != "true" ]]; then
        return 0
    fi
    
    log_warning "Deleting entire project: $PROJECT_ID"
    
    # Double confirmation for project deletion
    echo ""
    log_warning "FINAL WARNING: This will delete the ENTIRE project and ALL resources!"
    echo "Project to delete: $PROJECT_ID"
    echo ""
    echo "Type the project ID to confirm deletion:"
    read -r project_confirmation
    
    if [[ "$project_confirmation" != "$PROJECT_ID" ]]; then
        log_error "Project ID confirmation failed. Aborting project deletion."
        exit 1
    fi
    
    if gcloud projects delete "$PROJECT_ID" --quiet; then
        log_success "Project deleted: $PROJECT_ID"
        log_info "All resources have been permanently removed"
    else
        log_error "Failed to delete project"
        exit 1
    fi
}

# Function to verify cleanup completion
verify_cleanup() {
    log_info "Verifying cleanup completion..."
    
    local issues=0
    
    # Check if functions still exist
    for func in "$FUNCTION_NAME" "$ALERT_FUNCTION_NAME" "$REPORT_FUNCTION_NAME"; do
        if gcloud functions describe "$func" --gen2 --region="$REGION" &> /dev/null; then
            log_warning "Function still exists: $func"
            ((issues++))
        fi
    done
    
    # Check if scheduler job still exists
    if gcloud scheduler jobs describe "$SCHEDULER_JOB_NAME" --location="$REGION" &> /dev/null; then
        log_warning "Scheduler job still exists: $SCHEDULER_JOB_NAME"
        ((issues++))
    fi
    
    # Check if Pub/Sub resources still exist
    if gcloud pubsub topics describe "$TOPIC_NAME" &> /dev/null; then
        log_warning "Pub/Sub topic still exists: $TOPIC_NAME"
        ((issues++))
    fi
    
    # Check if bucket still exists
    if [[ -n "$BUCKET_NAME" ]] && gsutil ls -b "gs://$BUCKET_NAME" &> /dev/null; then
        log_warning "Storage bucket still exists: $BUCKET_NAME"
        ((issues++))
    fi
    
    if [[ "$issues" -eq 0 ]]; then
        log_success "Cleanup verification passed - all resources removed"
    else
        log_warning "Cleanup verification found $issues remaining resources"
        if [[ "$FORCE_DELETE" != "true" ]]; then
            log_error "Some resources may require manual cleanup"
        fi
    fi
}

# Function to display cleanup summary
display_cleanup_summary() {
    log_success "=== Cleanup Summary ==="
    echo "✅ Cloud Scheduler job: $SCHEDULER_JOB_NAME"
    echo "✅ Cloud Functions: $FUNCTION_NAME, $ALERT_FUNCTION_NAME, $REPORT_FUNCTION_NAME"
    echo "✅ Pub/Sub resources: $TOPIC_NAME, bias-detection-sub"
    
    if [[ -n "$BUCKET_NAME" ]]; then
        echo "✅ Cloud Storage bucket: $BUCKET_NAME"
    fi
    
    echo "✅ Local files and configurations"
    
    if [[ "$DELETE_PROJECT" == "true" ]]; then
        echo "✅ Project: $PROJECT_ID (COMPLETELY DELETED)"
    fi
    
    echo ""
    echo "All AI Model Bias Detection resources have been cleaned up."
    
    if [[ "$DELETE_PROJECT" != "true" ]]; then
        echo ""
        echo "Note: The Google Cloud project '$PROJECT_ID' still exists."
        echo "If you no longer need it, you can delete it manually:"
        echo "  gcloud projects delete $PROJECT_ID"
    fi
}

# Main cleanup function
main() {
    log_info "Starting AI Model Bias Detection cleanup..."
    
    check_prerequisites
    discover_resources
    confirm_cleanup
    
    if [[ "$DELETE_PROJECT" == "true" ]]; then
        delete_project
        display_cleanup_summary
        return 0
    fi
    
    delete_scheduler_job
    delete_cloud_functions
    delete_pubsub_resources
    delete_storage_bucket
    cleanup_local_files
    verify_cleanup
    display_cleanup_summary
    
    log_success "AI Model Bias Detection cleanup completed successfully!"
}

# Handle script arguments
case "${1:-}" in
    --help|-h)
        echo "Usage: $0 [OPTIONS]"
        echo ""
        echo "Clean up AI Model Bias Detection infrastructure from Google Cloud"
        echo ""
        echo "Options:"
        echo "  --help, -h            Show this help message"
        echo "  --force               Continue cleanup even if some operations fail"
        echo "  --skip-confirmation   Skip cleanup confirmation prompt"
        echo "  --delete-project      Delete the entire Google Cloud project"
        echo ""
        echo "Environment Variables:"
        echo "  PROJECT_ID           Google Cloud project ID"
        echo "  REGION              Deployment region (default: us-central1)"
        echo "  BUCKET_NAME         Storage bucket name to delete"
        echo "  FORCE_DELETE        Continue on errors (default: false)"
        echo "  DELETE_PROJECT      Delete entire project (default: false)"
        echo ""
        echo "Examples:"
        echo "  $0                           # Interactive cleanup"
        echo "  $0 --skip-confirmation       # Automatic cleanup"
        echo "  $0 --delete-project          # Delete entire project"
        echo "  BUCKET_NAME=my-bucket $0     # Specify bucket name"
        echo ""
        exit 0
        ;;
    --force)
        FORCE_DELETE="true"
        ;;
    --skip-confirmation)
        SKIP_CONFIRMATION="true"
        ;;
    --delete-project)
        DELETE_PROJECT="true"
        ;;
esac

# Run main function
main "$@"