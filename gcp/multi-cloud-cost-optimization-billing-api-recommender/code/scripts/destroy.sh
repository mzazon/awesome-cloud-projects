#!/bin/bash

# Multi-Cloud Cost Optimization with Cloud Billing API and Cloud Recommender - Cleanup Script
# This script removes all deployed infrastructure to avoid ongoing costs

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/.deployment_config"

# Load deployment configuration
load_config() {
    log "Loading deployment configuration..."
    
    if [[ ! -f "$CONFIG_FILE" ]]; then
        error "Deployment configuration file not found: $CONFIG_FILE"
        error "This script requires the configuration file created during deployment."
        exit 1
    fi
    
    # Source the configuration file
    source "$CONFIG_FILE"
    
    # Verify required variables are loaded
    local required_vars=("PROJECT_ID" "DATASET_NAME" "BUCKET_NAME" "TOPIC_NAME" "REGION" "BILLING_ACCOUNT_ID")
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            error "Required configuration variable $var is not set"
            exit 1
        fi
    done
    
    log "Configuration loaded successfully"
    log "Project ID: ${PROJECT_ID}"
    log "Dataset: ${DATASET_NAME}"
    log "Bucket: ${BUCKET_NAME}"
}

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        error "gcloud CLI is not installed. Please install Google Cloud SDK."
        exit 1
    fi
    
    # Check if authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        error "Not authenticated with gcloud. Please run 'gcloud auth login'."
        exit 1
    fi
    
    # Check if project exists
    if ! gcloud projects describe "${PROJECT_ID}" &>/dev/null; then
        warn "Project ${PROJECT_ID} not found or not accessible. Some resources may already be deleted."
    fi
    
    log "Prerequisites check completed"
}

# Confirmation prompt with safety checks
confirm_destruction() {
    echo -e "${RED}⚠️  DESTRUCTIVE OPERATION WARNING ⚠️${NC}"
    echo ""
    echo "This script will permanently delete the following resources:"
    echo "  🗑️  Google Cloud Project: ${PROJECT_ID}"
    echo "  🗑️  BigQuery Dataset: ${DATASET_NAME} (with all tables and data)"
    echo "  🗑️  Cloud Storage Bucket: gs://${BUCKET_NAME} (with all files)"
    echo "  🗑️  All Cloud Functions (analyze-costs, generate-recommendations, optimize-resources)"
    echo "  🗑️  All Pub/Sub topics and subscriptions"
    echo "  🗑️  All Cloud Scheduler jobs"
    echo "  🗑️  Cloud Monitoring dashboards and alerts"
    echo ""
    echo -e "${RED}THIS ACTION CANNOT BE UNDONE!${NC}"
    echo ""
    echo "Expected time to complete: 5-10 minutes"
    echo ""
    
    # Double confirmation
    read -p "Are you absolutely sure you want to delete ALL resources? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log "Cleanup cancelled by user"
        exit 0
    fi
    
    echo ""
    echo -e "${YELLOW}Final confirmation required.${NC}"
    echo "Type the project ID '${PROJECT_ID}' to confirm deletion:"
    read -p "> " user_input
    
    if [[ "$user_input" != "$PROJECT_ID" ]]; then
        error "Project ID confirmation failed. Cleanup cancelled."
        exit 1
    fi
    
    log "Destruction confirmed. Starting cleanup in 5 seconds..."
    sleep 5
}

# Set project context
set_project_context() {
    log "Setting project context..."
    
    # Set the current project
    gcloud config set project "${PROJECT_ID}" 2>/dev/null || {
        warn "Could not set project context. Project may already be deleted."
        return 1
    }
    
    log "Project context set successfully"
}

# Delete Cloud Scheduler jobs
cleanup_scheduler() {
    log "Deleting Cloud Scheduler jobs..."
    
    local jobs=("daily-cost-analysis" "weekly-cost-report" "monthly-optimization-review")
    
    for job in "${jobs[@]}"; do
        if gcloud scheduler jobs describe "$job" --location="${REGION}" &>/dev/null; then
            log "Deleting scheduler job: $job"
            gcloud scheduler jobs delete "$job" --location="${REGION}" --quiet || warn "Failed to delete job: $job"
        else
            warn "Scheduler job not found: $job"
        fi
    done
    
    log "Cloud Scheduler cleanup completed"
}

# Delete Cloud Functions
cleanup_functions() {
    log "Deleting Cloud Functions..."
    
    local functions=("analyze-costs" "generate-recommendations" "optimize-resources")
    
    for func in "${functions[@]}"; do
        if gcloud functions describe "$func" --region="${REGION}" &>/dev/null; then
            log "Deleting function: $func"
            gcloud functions delete "$func" --region="${REGION}" --quiet || warn "Failed to delete function: $func"
        else
            warn "Function not found: $func"
        fi
    done
    
    # Wait a moment for functions to be fully deleted
    log "Waiting for functions to be fully deleted..."
    sleep 30
    
    log "Cloud Functions cleanup completed"
}

# Delete Pub/Sub resources
cleanup_pubsub() {
    log "Deleting Pub/Sub topics and subscriptions..."
    
    # Delete subscriptions first
    local subscriptions=("cost-analysis-sub" "recommendations-sub" "alerts-sub")
    for sub in "${subscriptions[@]}"; do
        if gcloud pubsub subscriptions describe "$sub" &>/dev/null; then
            log "Deleting subscription: $sub"
            gcloud pubsub subscriptions delete "$sub" --quiet || warn "Failed to delete subscription: $sub"
        else
            warn "Subscription not found: $sub"
        fi
    done
    
    # Delete topics
    local topics=("${TOPIC_NAME}" "cost-analysis-results" "recommendations-generated" "optimization-alerts")
    for topic in "${topics[@]}"; do
        if gcloud pubsub topics describe "$topic" &>/dev/null; then
            log "Deleting topic: $topic"
            gcloud pubsub topics delete "$topic" --quiet || warn "Failed to delete topic: $topic"
        else
            warn "Topic not found: $topic"
        fi
    done
    
    log "Pub/Sub cleanup completed"
}

# Delete BigQuery dataset
cleanup_bigquery() {
    log "Deleting BigQuery dataset..."
    
    if bq show "${PROJECT_ID}:${DATASET_NAME}" &>/dev/null; then
        log "Deleting BigQuery dataset: ${DATASET_NAME}"
        bq rm -r -f "${PROJECT_ID}:${DATASET_NAME}" || warn "Failed to delete BigQuery dataset"
    else
        warn "BigQuery dataset not found: ${DATASET_NAME}"
    fi
    
    log "BigQuery cleanup completed"
}

# Delete Cloud Storage bucket
cleanup_storage() {
    log "Deleting Cloud Storage bucket..."
    
    if gsutil ls "gs://${BUCKET_NAME}" &>/dev/null; then
        log "Deleting all objects in bucket: gs://${BUCKET_NAME}"
        gsutil -m rm -r "gs://${BUCKET_NAME}" || warn "Failed to delete storage bucket"
    else
        warn "Storage bucket not found: gs://${BUCKET_NAME}"
    fi
    
    log "Cloud Storage cleanup completed"
}

# Delete monitoring resources
cleanup_monitoring() {
    log "Deleting monitoring resources..."
    
    # List and delete dashboards (they contain "Cost Optimization" in the name)
    local dashboards=$(gcloud monitoring dashboards list --filter="displayName:Cost\ Optimization" --format="value(name)" 2>/dev/null || echo "")
    
    if [[ -n "$dashboards" ]]; then
        while IFS= read -r dashboard; do
            if [[ -n "$dashboard" ]]; then
                log "Deleting monitoring dashboard: $dashboard"
                gcloud monitoring dashboards delete "$dashboard" --quiet || warn "Failed to delete dashboard: $dashboard"
            fi
        done <<< "$dashboards"
    else
        warn "No monitoring dashboards found"
    fi
    
    log "Monitoring cleanup completed"
}

# Delete the entire project
delete_project() {
    log "Deleting Google Cloud project..."
    
    if gcloud projects describe "${PROJECT_ID}" &>/dev/null; then
        log "Deleting project: ${PROJECT_ID}"
        
        # Disable billing first to prevent any charges
        log "Unlinking billing account..."
        gcloud billing projects unlink "${PROJECT_ID}" 2>/dev/null || warn "Could not unlink billing account"
        
        # Delete the project
        log "Initiating project deletion..."
        gcloud projects delete "${PROJECT_ID}" --quiet || {
            error "Failed to delete project. You may need to delete it manually from the console."
            return 1
        }
        
        log "Project deletion initiated. The project will be fully deleted within a few minutes."
    else
        warn "Project ${PROJECT_ID} not found or already deleted"
    fi
}

# Clean up local configuration files
cleanup_local_files() {
    log "Cleaning up local configuration files..."
    
    # Remove deployment configuration
    if [[ -f "$CONFIG_FILE" ]]; then
        rm -f "$CONFIG_FILE"
        log "Removed deployment configuration file"
    fi
    
    # Remove any temporary files created during deployment
    local temp_files=(
        "${SCRIPT_DIR}/.dashboard_config.json"
        "${SCRIPT_DIR}/.temp_*"
    )
    
    for pattern in "${temp_files[@]}"; do
        rm -f $pattern 2>/dev/null || true
    done
    
    log "Local cleanup completed"
}

# Verification and final status
verify_cleanup() {
    log "Verifying cleanup completion..."
    
    # Check if project still exists
    if gcloud projects describe "${PROJECT_ID}" &>/dev/null; then
        warn "Project ${PROJECT_ID} still exists. It may take several minutes to be fully deleted."
        warn "You can check the deletion status in the Google Cloud Console."
    else
        log "Project ${PROJECT_ID} has been successfully deleted"
    fi
    
    # Check for any remaining billable resources
    log "Checking for any remaining billable resources..."
    
    local remaining_resources=()
    
    # Check functions (unlikely to exist if project is deleted, but good practice)
    if gcloud functions list --filter="name:analyze-costs OR name:generate-recommendations OR name:optimize-resources" --format="value(name)" 2>/dev/null | grep -q .; then
        remaining_resources+=("Cloud Functions")
    fi
    
    # Check scheduler jobs
    if gcloud scheduler jobs list --filter="name:daily-cost-analysis OR name:weekly-cost-report OR name:monthly-optimization-review" --format="value(name)" 2>/dev/null | grep -q .; then
        remaining_resources+=("Cloud Scheduler jobs")
    fi
    
    if [[ ${#remaining_resources[@]} -gt 0 ]]; then
        warn "The following resources may still exist:"
        for resource in "${remaining_resources[@]}"; do
            warn "  - $resource"
        done
        warn "These should be automatically deleted with the project, but please verify in the console."
    else
        log "No remaining billable resources detected"
    fi
    
    log "Cleanup verification completed"
}

# Display cleanup summary
show_cleanup_summary() {
    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}     CLEANUP COMPLETED SUCCESSFULLY    ${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    echo "Deleted Resources:"
    echo "  🗑️  Google Cloud Project: ${PROJECT_ID}"
    echo "  🗑️  BigQuery Dataset: ${DATASET_NAME}"
    echo "  🗑️  Cloud Storage Bucket: gs://${BUCKET_NAME}"
    echo "  🗑️  3 Cloud Functions"
    echo "  🗑️  4 Pub/Sub topics and 3 subscriptions"
    echo "  🗑️  3 Cloud Scheduler jobs"
    echo "  🗑️  Cloud Monitoring dashboards"
    echo "  🗑️  Local configuration files"
    echo ""
    echo "Important Notes:"
    echo "  ⏳ Project deletion may take 5-10 minutes to complete fully"
    echo "  💰 Billing should stop immediately after project deletion"
    echo "  📊 You can verify deletion in the Google Cloud Console"
    echo "  📧 You may receive an email confirmation when deletion is complete"
    echo ""
    echo "If you encounter any issues:"
    echo "  1. Check the Google Cloud Console for remaining resources"
    echo "  2. Verify billing has stopped in the Billing section"
    echo "  3. Contact Google Cloud Support if needed"
    echo ""
}

# Main cleanup flow
main() {
    log "Starting Multi-Cloud Cost Optimization cleanup..."
    
    load_config
    check_prerequisites
    confirm_destruction
    
    # Set project context (may fail if project already deleted)
    if set_project_context; then
        # Clean up individual resources first
        cleanup_scheduler
        cleanup_functions
        cleanup_pubsub
        cleanup_bigquery
        cleanup_storage
        cleanup_monitoring
        
        # Finally delete the entire project
        delete_project
    else
        log "Skipping individual resource cleanup - project context unavailable"
        log "Attempting project deletion directly..."
        delete_project
    fi
    
    cleanup_local_files
    verify_cleanup
    show_cleanup_summary
    
    log "Cleanup completed successfully!"
}

# Handle script interruption
trap 'error "Cleanup interrupted. Some resources may still exist. Please check the Google Cloud Console."; exit 1' INT TERM

# Run main function
main "$@"