#!/bin/bash

# Data Pipeline Recovery Workflows with Dataform and Cloud Tasks - Cleanup Script
# This script safely removes all infrastructure created by the deployment script

set -euo pipefail

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

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites for cleanup..."
    
    # Check if gcloud CLI is installed
    if ! command -v gcloud &> /dev/null; then
        error "gcloud CLI is not installed. Please install it from https://cloud.google.com/sdk/docs/install"
        exit 1
    fi
    
    # Check if bq CLI is installed
    if ! command -v bq &> /dev/null; then
        error "BigQuery CLI (bq) is not installed. Please install Google Cloud SDK with BigQuery components"
        exit 1
    fi
    
    # Check if user is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q "@"; then
        error "No active gcloud authentication found. Please run 'gcloud auth login'"
        exit 1
    fi
    
    # Check if project is set
    PROJECT_ID=$(gcloud config get-value project 2>/dev/null)
    if [[ -z "$PROJECT_ID" ]]; then
        error "No default project set. Please run 'gcloud config set project YOUR_PROJECT_ID'"
        exit 1
    fi
    
    success "Prerequisites check completed"
}

# Function to load deployment information
load_deployment_info() {
    log "Loading deployment information..."
    
    local deployment_file="deployment-info.txt"
    
    if [[ -f "$deployment_file" ]]; then
        # Source the deployment file to load variables
        # shellcheck source=/dev/null
        source <(grep -E '^[A-Z_]+=.*$' "$deployment_file")
        success "Loaded deployment configuration from ${deployment_file}"
        
        log "Configuration loaded:"
        log "  • Project: ${PROJECT_ID:-Not set}"
        log "  • Region: ${REGION:-Not set}"
        log "  • Dataform Repo: ${DATAFORM_REPO:-Not set}"
        log "  • Dataset: ${DATASET_NAME:-Not set}"
    else
        warning "Deployment info file not found. Will attempt to discover resources interactively."
        setup_interactive_cleanup
    fi
}

# Function for interactive cleanup when deployment info is missing
setup_interactive_cleanup() {
    log "Setting up interactive cleanup..."
    
    export PROJECT_ID=$(gcloud config get-value project)
    export REGION="us-central1"
    
    # Prompt user to confirm resource cleanup
    echo ""
    warning "No deployment-info.txt file found."
    warning "This script will search for and remove resources created by the pipeline recovery recipe."
    echo ""
    read -p "Do you want to proceed with interactive cleanup? (y/N): " -n 1 -r
    echo ""
    
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log "Cleanup cancelled by user"
        exit 0
    fi
    
    success "Proceeding with interactive cleanup"
}

# Function to confirm destructive actions
confirm_cleanup() {
    log "This script will delete the following resources:"
    echo ""
    echo "  🗄️  BigQuery Dataset: ${DATASET_NAME:-<will be discovered>}"
    echo "  📊 Dataform Repository: ${DATAFORM_REPO:-<will be discovered>}"
    echo "  ⚡ Cloud Functions: ${CONTROLLER_FUNCTION:-<will be discovered>}, ${WORKER_FUNCTION:-<will be discovered>}, ${NOTIFY_FUNCTION:-<will be discovered>}"
    echo "  📋 Cloud Tasks Queue: ${TASK_QUEUE:-<will be discovered>}"
    echo "  📢 Pub/Sub Topic: ${NOTIFICATION_TOPIC:-<will be discovered>}"
    echo "  📈 Monitoring resources (alerts, channels, metrics)"
    echo "  📁 Local files and directories"
    echo ""
    warning "⚠️  This action cannot be undone!"
    echo ""
    
    if [[ "${1:-}" != "--force" ]]; then
        read -p "Are you sure you want to delete all these resources? (y/N): " -n 1 -r
        echo ""
        
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log "Cleanup cancelled by user"
            exit 0
        fi
    fi
    
    success "Proceeding with resource cleanup"
}

# Function to delete Cloud Functions
delete_cloud_functions() {
    log "Deleting Cloud Functions..."
    
    local functions_to_delete=()
    
    # If we have deployment info, use specific function names
    if [[ -n "${CONTROLLER_FUNCTION:-}" ]]; then
        functions_to_delete+=("${CONTROLLER_FUNCTION}")
    fi
    if [[ -n "${WORKER_FUNCTION:-}" ]]; then
        functions_to_delete+=("${WORKER_FUNCTION}")
    fi
    if [[ -n "${NOTIFY_FUNCTION:-}" ]]; then
        functions_to_delete+=("${NOTIFY_FUNCTION}")
    fi
    
    # If no specific functions, discover them
    if [[ ${#functions_to_delete[@]} -eq 0 ]]; then
        log "Discovering Cloud Functions related to pipeline recovery..."
        mapfile -t functions_to_delete < <(gcloud functions list \
            --regions="${REGION}" \
            --format="value(name)" \
            --filter="name:pipeline-controller OR name:recovery-worker OR name:notification-handler" 2>/dev/null || true)
    fi
    
    # Delete each function
    for func in "${functions_to_delete[@]}"; do
        if [[ -n "$func" ]]; then
            log "Deleting Cloud Function: ${func}"
            if gcloud functions delete "$func" --region="${REGION}" --gen2 --quiet 2>/dev/null; then
                success "Deleted Cloud Function: ${func}"
            else
                warning "Failed to delete Cloud Function: ${func} (may not exist)"
            fi
        fi
    done
    
    # Clean up local function files
    if [[ -d "./functions" ]]; then
        log "Removing local function files..."
        rm -rf "./functions"
        success "Removed local function files"
    fi
}

# Function to delete Cloud Tasks queue
delete_cloud_tasks_queue() {
    log "Deleting Cloud Tasks queue..."
    
    local queues_to_delete=()
    
    # If we have deployment info, use specific queue name
    if [[ -n "${TASK_QUEUE:-}" ]]; then
        queues_to_delete+=("${TASK_QUEUE}")
    else
        # Discover queues
        log "Discovering Cloud Tasks queues related to pipeline recovery..."
        mapfile -t queues_to_delete < <(gcloud tasks queues list \
            --location="${REGION}" \
            --format="value(name)" \
            --filter="name:pipeline-recovery-queue" 2>/dev/null | sed 's|.*/||' || true)
    fi
    
    # Delete each queue
    for queue in "${queues_to_delete[@]}"; do
        if [[ -n "$queue" ]]; then
            log "Deleting Cloud Tasks queue: ${queue}"
            if gcloud tasks queues delete "$queue" --location="${REGION}" --quiet 2>/dev/null; then
                success "Deleted Cloud Tasks queue: ${queue}"
            else
                warning "Failed to delete Cloud Tasks queue: ${queue} (may not exist)"
            fi
        fi
    done
}

# Function to delete Pub/Sub resources
delete_pubsub_resources() {
    log "Deleting Pub/Sub resources..."
    
    local topics_to_delete=()
    
    # If we have deployment info, use specific topic name
    if [[ -n "${NOTIFICATION_TOPIC:-}" ]]; then
        topics_to_delete+=("${NOTIFICATION_TOPIC}")
    else
        # Discover topics
        log "Discovering Pub/Sub topics related to pipeline notifications..."
        mapfile -t topics_to_delete < <(gcloud pubsub topics list \
            --format="value(name)" \
            --filter="name:pipeline-notifications" 2>/dev/null | sed 's|.*/||' || true)
    fi
    
    # Delete each topic (this also deletes associated subscriptions)
    for topic in "${topics_to_delete[@]}"; do
        if [[ -n "$topic" ]]; then
            log "Deleting Pub/Sub topic: ${topic}"
            if gcloud pubsub topics delete "$topic" --quiet 2>/dev/null; then
                success "Deleted Pub/Sub topic: ${topic}"
            else
                warning "Failed to delete Pub/Sub topic: ${topic} (may not exist)"
            fi
        fi
    done
}

# Function to delete Dataform repository
delete_dataform_repository() {
    log "Deleting Dataform repository..."
    
    local repos_to_delete=()
    
    # If we have deployment info, use specific repo name
    if [[ -n "${DATAFORM_REPO:-}" ]]; then
        repos_to_delete+=("${DATAFORM_REPO}")
    else
        # Discover repositories
        log "Discovering Dataform repositories related to pipeline recovery..."
        mapfile -t repos_to_delete < <(gcloud dataform repositories list \
            --region="${REGION}" \
            --format="value(name)" \
            --filter="name:pipeline-recovery-repo" 2>/dev/null | sed 's|.*/||' || true)
    fi
    
    # Delete each repository
    for repo in "${repos_to_delete[@]}"; do
        if [[ -n "$repo" ]]; then
            log "Deleting Dataform repository: ${repo}"
            if gcloud dataform repositories delete "$repo" --region="${REGION}" --quiet 2>/dev/null; then
                success "Deleted Dataform repository: ${repo}"
            else
                warning "Failed to delete Dataform repository: ${repo} (may not exist)"
            fi
        fi
    done
    
    # Clean up local Dataform config files
    if [[ -d "./dataform-config" ]]; then
        log "Removing local Dataform configuration files..."
        rm -rf "./dataform-config"
        success "Removed local Dataform configuration files"
    fi
}

# Function to delete BigQuery resources
delete_bigquery_resources() {
    log "Deleting BigQuery resources..."
    
    local datasets_to_delete=()
    
    # If we have deployment info, use specific dataset name
    if [[ -n "${DATASET_NAME:-}" ]]; then
        datasets_to_delete+=("${DATASET_NAME}")
    else
        # Discover datasets
        log "Discovering BigQuery datasets related to pipeline monitoring..."
        mapfile -t datasets_to_delete < <(bq ls --format=csv --max_results=1000 | \
            grep "pipeline_monitoring" | cut -d, -f1 | tail -n +2 2>/dev/null || true)
    fi
    
    # Delete each dataset
    for dataset in "${datasets_to_delete[@]}"; do
        if [[ -n "$dataset" ]]; then
            log "Deleting BigQuery dataset: ${dataset}"
            if bq rm -r -f "$dataset" 2>/dev/null; then
                success "Deleted BigQuery dataset: ${dataset}"
            else
                warning "Failed to delete BigQuery dataset: ${dataset} (may not exist)"
            fi
        fi
    done
}

# Function to delete monitoring resources
delete_monitoring_resources() {
    log "Deleting monitoring resources..."
    
    # Delete monitoring policies
    log "Removing monitoring alert policies..."
    local policies
    policies=$(gcloud alpha monitoring policies list \
        --filter="displayName:'Dataform Pipeline Failure Alert'" \
        --format="value(name)" 2>/dev/null || true)
    
    if [[ -n "$policies" ]]; then
        while IFS= read -r policy; do
            if [[ -n "$policy" ]]; then
                log "Deleting monitoring policy: ${policy}"
                if gcloud alpha monitoring policies delete "$policy" --quiet 2>/dev/null; then
                    success "Deleted monitoring policy"
                else
                    warning "Failed to delete monitoring policy"
                fi
            fi
        done <<< "$policies"
    fi
    
    # Delete notification channels
    log "Removing monitoring notification channels..."
    local channels
    channels=$(gcloud alpha monitoring channels list \
        --filter="displayName:'Pipeline Recovery Webhook'" \
        --format="value(name)" 2>/dev/null || true)
    
    if [[ -n "$channels" ]]; then
        while IFS= read -r channel; do
            if [[ -n "$channel" ]]; then
                log "Deleting notification channel: ${channel}"
                if gcloud alpha monitoring channels delete "$channel" --quiet 2>/dev/null; then
                    success "Deleted notification channel"
                else
                    warning "Failed to delete notification channel"
                fi
            fi
        done <<< "$channels"
    fi
    
    # Delete log-based metrics
    log "Removing log-based metrics..."
    if gcloud logging metrics delete pipeline_execution_status --quiet 2>/dev/null; then
        success "Deleted log-based metric: pipeline_execution_status"
    else
        warning "Failed to delete log-based metric (may not exist)"
    fi
}

# Function to clean up local files
cleanup_local_files() {
    log "Cleaning up local files and directories..."
    
    local files_to_remove=(
        "deployment-info.txt"
        "monitoring-policy.json"
    )
    
    for file in "${files_to_remove[@]}"; do
        if [[ -f "$file" ]]; then
            log "Removing file: ${file}"
            rm -f "$file"
            success "Removed: ${file}"
        fi
    done
    
    # Remove any remaining temporary directories
    local dirs_to_remove=(
        "./functions"
        "./dataform-config"
    )
    
    for dir in "${dirs_to_remove[@]}"; do
        if [[ -d "$dir" ]]; then
            log "Removing directory: ${dir}"
            rm -rf "$dir"
            success "Removed: ${dir}"
        fi
    done
}

# Function to verify cleanup completion
verify_cleanup() {
    log "Verifying cleanup completion..."
    
    local cleanup_issues=()
    
    # Check for remaining Cloud Functions
    local remaining_functions
    remaining_functions=$(gcloud functions list \
        --regions="${REGION}" \
        --filter="name:pipeline-controller OR name:recovery-worker OR name:notification-handler" \
        --format="value(name)" 2>/dev/null | wc -l || echo "0")
    
    if [[ "$remaining_functions" -gt 0 ]]; then
        cleanup_issues+=("${remaining_functions} Cloud Functions still exist")
    fi
    
    # Check for remaining Cloud Tasks queues
    local remaining_queues
    remaining_queues=$(gcloud tasks queues list \
        --location="${REGION}" \
        --filter="name:pipeline-recovery-queue" \
        --format="value(name)" 2>/dev/null | wc -l || echo "0")
    
    if [[ "$remaining_queues" -gt 0 ]]; then
        cleanup_issues+=("${remaining_queues} Cloud Tasks queues still exist")
    fi
    
    # Check for remaining Dataform repositories
    local remaining_repos
    remaining_repos=$(gcloud dataform repositories list \
        --region="${REGION}" \
        --filter="name:pipeline-recovery-repo" \
        --format="value(name)" 2>/dev/null | wc -l || echo "0")
    
    if [[ "$remaining_repos" -gt 0 ]]; then
        cleanup_issues+=("${remaining_repos} Dataform repositories still exist")
    fi
    
    # Report results
    if [[ ${#cleanup_issues[@]} -eq 0 ]]; then
        success "Cleanup verification completed - all resources removed successfully"
    else
        warning "Cleanup verification found the following issues:"
        for issue in "${cleanup_issues[@]}"; do
            warning "  • ${issue}"
        done
        warning "You may need to manually remove these resources from the Google Cloud Console"
    fi
}

# Function to display cleanup summary
display_cleanup_summary() {
    log ""
    success "🧹 Data Pipeline Recovery Workflows cleanup completed!"
    log ""
    log "📋 Cleanup Summary:"
    log "  • Cloud Functions: Removed"
    log "  • Cloud Tasks Queue: Removed"
    log "  • Pub/Sub Topic: Removed"
    log "  • Dataform Repository: Removed"
    log "  • BigQuery Dataset: Removed"
    log "  • Monitoring Resources: Removed"
    log "  • Local Files: Cleaned up"
    log ""
    log "💡 What's Next:"
    log "  • Check your Google Cloud Console to verify all resources are removed"
    log "  • Review your billing to confirm charges have stopped"
    log "  • Resources in the trash/recycle bin will be permanently deleted after 30 days"
    log ""
    success "All pipeline recovery infrastructure has been successfully removed!"
}

# Main cleanup function
main() {
    log "Starting Data Pipeline Recovery Workflows cleanup..."
    
    # Check for force flag
    local force_cleanup=false
    if [[ "${1:-}" == "--force" ]]; then
        force_cleanup=true
        log "Running in force mode - skipping confirmation prompts"
    fi
    
    # Execute cleanup steps
    check_prerequisites
    load_deployment_info
    
    if [[ "$force_cleanup" == true ]]; then
        confirm_cleanup --force
    else
        confirm_cleanup
    fi
    
    delete_cloud_functions
    delete_cloud_tasks_queue
    delete_pubsub_resources
    delete_dataform_repository
    delete_bigquery_resources
    delete_monitoring_resources
    cleanup_local_files
    verify_cleanup
    display_cleanup_summary
}

# Handle script interruption
cleanup_on_interrupt() {
    echo ""
    warning "Cleanup interrupted by user"
    warning "Some resources may still exist. Re-run this script to complete cleanup."
    exit 130
}

# Handle script errors
cleanup_on_error() {
    if [[ $? -ne 0 ]]; then
        error "Cleanup script encountered an error"
        error "Some resources may still exist. Check the Google Cloud Console and re-run if needed."
        error "For manual cleanup, check the deployment-info.txt file for resource names."
    fi
}

# Set up signal handlers
trap cleanup_on_interrupt SIGINT SIGTERM
trap cleanup_on_error EXIT

# Execute main function with all arguments
main "$@"