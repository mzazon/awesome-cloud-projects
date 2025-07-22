#!/bin/bash

# Smart Calendar Intelligence with Cloud Calendar API and Cloud Run Worker Pools - Cleanup Script
# This script safely removes all calendar intelligence infrastructure from Google Cloud Platform
# 
# Prerequisites:
# - Google Cloud CLI installed and authenticated
# - Access to the project where resources were deployed
# - Appropriate IAM permissions for resource deletion

set -euo pipefail

# Color codes for output
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

# Configuration variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_REGION="us-central1"

# Check if running in dry-run mode
DRY_RUN=${DRY_RUN:-false}
FORCE_DELETE=${FORCE_DELETE:-false}

# Function to display usage
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Safely remove Smart Calendar Intelligence infrastructure from Google Cloud Platform.

OPTIONS:
    -p, --project-id PROJECT_ID    Specify GCP project ID (required)
    -r, --region REGION           Specify GCP region (default: us-central1)
    -f, --force                   Skip confirmation prompts (use with caution)
    -d, --dry-run                 Run in dry-run mode (show what would be deleted)
    -h, --help                    Display this help message

EXAMPLES:
    $0 -p my-calendar-project                    # Interactive cleanup
    $0 -p my-calendar-project --force            # Automated cleanup (dangerous)
    $0 -p my-calendar-project --dry-run          # Show what would be deleted

WARNING:
    This script will permanently delete resources and data. Use with caution!
    Always backup important data before running cleanup operations.

EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -p|--project-id)
            PROJECT_ID="$2"
            shift 2
            ;;
        -r|--region)
            REGION="$2"
            shift 2
            ;;
        -f|--force)
            FORCE_DELETE=true
            shift
            ;;
        -d|--dry-run)
            DRY_RUN=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# Validate required parameters
if [[ -z "${PROJECT_ID:-}" ]]; then
    log_error "Project ID is required. Use -p or --project-id to specify."
    usage
    exit 1
fi

# Set default values
REGION=${REGION:-$DEFAULT_REGION}

# Function to execute commands (respects dry-run mode)
execute_command() {
    local cmd="$1"
    local description="$2"
    local ignore_errors="${3:-false}"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] $description"
        echo "  Command: $cmd"
    else
        log_info "$description"
        if eval "$cmd"; then
            log_success "Completed: $description"
        else
            if [[ "$ignore_errors" == "true" ]]; then
                log_warning "Failed (ignoring): $description"
            else
                log_error "Failed: $description"
                return 1
            fi
        fi
    fi
}

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "Google Cloud CLI (gcloud) is not installed or not in PATH"
        exit 1
    fi
    
    # Check if gcloud is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 > /dev/null; then
        log_error "Not authenticated with Google Cloud"
        log_error "Please run: gcloud auth login"
        exit 1
    fi
    
    # Check if project exists and is accessible
    if ! gcloud projects describe "$PROJECT_ID" &> /dev/null; then
        log_error "Project ${PROJECT_ID} does not exist or is not accessible"
        log_error "Please verify the project ID and your permissions"
        exit 1
    fi
    
    log_success "Prerequisites satisfied"
}

# Function to discover resources
discover_resources() {
    log_info "Discovering calendar intelligence resources in project ${PROJECT_ID}..."
    
    # Set project context
    execute_command "gcloud config set project ${PROJECT_ID}" "Setting project context"
    
    # Discover resources with calendar-intelligence or calendar-tasks pattern
    local discovered_resources=()
    
    if [[ "$DRY_RUN" == "false" ]]; then
        # Discover worker pools
        WORKER_POOLS=($(gcloud beta run worker-pools list --region=${REGION} --filter="name~calendar-intelligence" --format="value(name)" 2>/dev/null || true))
        
        # Discover Cloud Run services
        API_SERVICES=($(gcloud run services list --region=${REGION} --filter="name~calendar-intelligence" --format="value(name)" 2>/dev/null || true))
        
        # Discover Cloud Tasks queues
        TASK_QUEUES=($(gcloud tasks queues list --location=${REGION} --filter="name~calendar-tasks" --format="value(name)" 2>/dev/null || true))
        
        # Discover Cloud Scheduler jobs
        SCHEDULER_JOBS=($(gcloud scheduler jobs list --location=${REGION} --filter="name~calendar" --format="value(name)" 2>/dev/null || true))
        
        # Discover BigQuery datasets
        DATASETS=($(bq ls --format=csv --max_results=1000 | grep "calendar_analytics" | cut -d',' -f1 2>/dev/null || true))
        
        # Discover Cloud Storage buckets
        BUCKETS=($(gsutil ls -p ${PROJECT_ID} | grep "calendar-intelligence" | sed 's|gs://||' | sed 's|/||' 2>/dev/null || true))
        
        # Discover Artifact Registry repositories
        REPOSITORIES=($(gcloud artifacts repositories list --location=${REGION} --filter="name~calendar-intelligence" --format="value(name)" 2>/dev/null || true))
        
        # Discover service accounts
        SERVICE_ACCOUNTS=($(gcloud iam service-accounts list --filter="name~calendar-intelligence" --format="value(email)" 2>/dev/null || true))
    else
        # In dry-run mode, simulate discovery
        WORKER_POOLS=("calendar-intelligence-sample")
        API_SERVICES=("calendar-intelligence-api")
        TASK_QUEUES=("calendar-tasks-sample")
        SCHEDULER_JOBS=("calendar-daily-analysis")
        DATASETS=("calendar_analytics_sample")
        BUCKETS=("calendar-intelligence-${PROJECT_ID}")
        REPOSITORIES=("calendar-intelligence")
        SERVICE_ACCOUNTS=("calendar-intelligence-worker@${PROJECT_ID}.iam.gserviceaccount.com")
    fi
    
    # Display discovered resources
    log_info "Discovered resources for cleanup:"
    echo "  Worker Pools: ${#WORKER_POOLS[@]} found"
    echo "  API Services: ${#API_SERVICES[@]} found"
    echo "  Task Queues: ${#TASK_QUEUES[@]} found"
    echo "  Scheduler Jobs: ${#SCHEDULER_JOBS[@]} found"
    echo "  BigQuery Datasets: ${#DATASETS[@]} found"
    echo "  Storage Buckets: ${#BUCKETS[@]} found"
    echo "  Artifact Repositories: ${#REPOSITORIES[@]} found"
    echo "  Service Accounts: ${#SERVICE_ACCOUNTS[@]} found"
}

# Function to confirm deletion
confirm_deletion() {
    if [[ "$FORCE_DELETE" == "true" ]]; then
        log_warning "Force mode enabled - skipping confirmation prompts"
        return 0
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        return 0
    fi
    
    echo
    log_warning "╔════════════════════════════════════════════════════════════════════════════════════════╗"
    log_warning "║                                    DANGER ZONE                                            ║"
    log_warning "║                                                                                            ║"
    log_warning "║  This operation will PERMANENTLY DELETE all calendar intelligence resources including:    ║"
    log_warning "║                                                                                            ║"
    log_warning "║  • All BigQuery datasets and analytics data                                               ║"
    log_warning "║  • All Cloud Storage buckets and stored files                                             ║"
    log_warning "║  • All Cloud Run services and worker pools                                                ║"
    log_warning "║  • All Cloud Tasks queues and pending tasks                                               ║"
    log_warning "║  • All scheduled jobs and automation                                                      ║"
    log_warning "║  • All container images and artifacts                                                     ║"
    log_warning "║  • All service accounts and IAM configurations                                            ║"
    log_warning "║                                                                                            ║"
    log_warning "║  This action CANNOT BE UNDONE. Ensure you have backups of any important data.            ║"
    log_warning "╚════════════════════════════════════════════════════════════════════════════════════════╝"
    echo
    
    read -p "Are you absolutely sure you want to proceed? Type 'DELETE' to confirm: " -r
    if [[ "$REPLY" != "DELETE" ]]; then
        log_info "Cleanup cancelled by user"
        exit 0
    fi
    
    read -p "Final confirmation - type the project ID '${PROJECT_ID}' to proceed: " -r
    if [[ "$REPLY" != "$PROJECT_ID" ]]; then
        log_error "Project ID mismatch. Cleanup cancelled for safety."
        exit 1
    fi
    
    log_info "Deletion confirmed. Proceeding with cleanup..."
}

# Function to delete Cloud Scheduler jobs
delete_scheduler_jobs() {
    if [[ ${#SCHEDULER_JOBS[@]} -gt 0 ]]; then
        log_info "Deleting Cloud Scheduler jobs..."
        for job in "${SCHEDULER_JOBS[@]}"; do
            execute_command "gcloud scheduler jobs delete ${job} --location=${REGION} --quiet" \
                "Deleting scheduler job: ${job}" true
        done
        log_success "Cloud Scheduler jobs deleted"
    else
        log_info "No Cloud Scheduler jobs found to delete"
    fi
}

# Function to delete Cloud Run services and worker pools
delete_cloud_run_resources() {
    # Delete API services first
    if [[ ${#API_SERVICES[@]} -gt 0 ]]; then
        log_info "Deleting Cloud Run API services..."
        for service in "${API_SERVICES[@]}"; do
            execute_command "gcloud run services delete ${service} --region=${REGION} --quiet" \
                "Deleting API service: ${service}" true
        done
        log_success "Cloud Run API services deleted"
    else
        log_info "No Cloud Run API services found to delete"
    fi
    
    # Delete worker pools
    if [[ ${#WORKER_POOLS[@]} -gt 0 ]]; then
        log_info "Deleting Cloud Run worker pools..."
        for pool in "${WORKER_POOLS[@]}"; do
            execute_command "gcloud beta run worker-pools delete ${pool} --region=${REGION} --quiet" \
                "Deleting worker pool: ${pool}" true
        done
        log_success "Cloud Run worker pools deleted"
    else
        log_info "No Cloud Run worker pools found to delete"
    fi
}

# Function to delete Cloud Tasks queues
delete_task_queues() {
    if [[ ${#TASK_QUEUES[@]} -gt 0 ]]; then
        log_info "Deleting Cloud Tasks queues..."
        for queue in "${TASK_QUEUES[@]}"; do
            # Purge queue first to remove pending tasks
            execute_command "gcloud tasks queues purge ${queue} --location=${REGION} --quiet" \
                "Purging task queue: ${queue}" true
            
            # Delete the queue
            execute_command "gcloud tasks queues delete ${queue} --location=${REGION} --quiet" \
                "Deleting task queue: ${queue}" true
        done
        log_success "Cloud Tasks queues deleted"
    else
        log_info "No Cloud Tasks queues found to delete"
    fi
}

# Function to delete BigQuery resources
delete_bigquery_resources() {
    if [[ ${#DATASETS[@]} -gt 0 ]]; then
        log_info "Deleting BigQuery datasets..."
        for dataset in "${DATASETS[@]}"; do
            execute_command "bq rm -r -f ${PROJECT_ID}:${dataset}" \
                "Deleting BigQuery dataset: ${dataset}" true
        done
        log_success "BigQuery datasets deleted"
    else
        log_info "No BigQuery datasets found to delete"
    fi
}

# Function to delete Cloud Storage buckets
delete_storage_buckets() {
    if [[ ${#BUCKETS[@]} -gt 0 ]]; then
        log_info "Deleting Cloud Storage buckets..."
        for bucket in "${BUCKETS[@]}"; do
            # Remove all objects first (including versioned objects)
            execute_command "gsutil -m rm -r gs://${bucket}/**" \
                "Removing all objects from bucket: ${bucket}" true
            
            # Delete the bucket
            execute_command "gsutil rb gs://${bucket}" \
                "Deleting storage bucket: ${bucket}" true
        done
        log_success "Cloud Storage buckets deleted"
    else
        log_info "No Cloud Storage buckets found to delete"
    fi
}

# Function to delete Artifact Registry repositories
delete_artifact_repositories() {
    if [[ ${#REPOSITORIES[@]} -gt 0 ]]; then
        log_info "Deleting Artifact Registry repositories..."
        for repo in "${REPOSITORIES[@]}"; do
            execute_command "gcloud artifacts repositories delete ${repo} --location=${REGION} --quiet" \
                "Deleting artifact repository: ${repo}" true
        done
        log_success "Artifact Registry repositories deleted"
    else
        log_info "No Artifact Registry repositories found to delete"
    fi
}

# Function to delete service accounts
delete_service_accounts() {
    if [[ ${#SERVICE_ACCOUNTS[@]} -gt 0 ]]; then
        log_info "Deleting IAM service accounts..."
        for sa in "${SERVICE_ACCOUNTS[@]}"; do
            execute_command "gcloud iam service-accounts delete ${sa} --quiet" \
                "Deleting service account: ${sa}" true
        done
        log_success "Service accounts deleted"
    else
        log_info "No service accounts found to delete"
    fi
}

# Function to cleanup local files
cleanup_local_files() {
    log_info "Cleaning up local temporary files..."
    
    local cleanup_paths=(
        "/tmp/calendar_insights_schema.json"
        "${SCRIPT_DIR}/../worker"
        "${SCRIPT_DIR}/../api"
    )
    
    for path in "${cleanup_paths[@]}"; do
        if [[ -e "$path" ]]; then
            execute_command "rm -rf ${path}" \
                "Removing local path: ${path}" true
        fi
    done
    
    log_success "Local cleanup completed"
}

# Function to verify cleanup completion
verify_cleanup() {
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "Dry run completed - no actual resources were deleted"
        return 0
    fi
    
    log_info "Verifying cleanup completion..."
    
    local cleanup_issues=0
    
    # Check for remaining resources
    local remaining_services=$(gcloud run services list --region=${REGION} --filter="name~calendar-intelligence" --format="value(name)" 2>/dev/null | wc -l || echo "0")
    local remaining_pools=$(gcloud beta run worker-pools list --region=${REGION} --filter="name~calendar-intelligence" --format="value(name)" 2>/dev/null | wc -l || echo "0")
    local remaining_queues=$(gcloud tasks queues list --location=${REGION} --filter="name~calendar-tasks" --format="value(name)" 2>/dev/null | wc -l || echo "0")
    
    if [[ "$remaining_services" -gt 0 ]]; then
        log_warning "Found ${remaining_services} remaining Cloud Run services"
        cleanup_issues=$((cleanup_issues + 1))
    fi
    
    if [[ "$remaining_pools" -gt 0 ]]; then
        log_warning "Found ${remaining_pools} remaining worker pools"
        cleanup_issues=$((cleanup_issues + 1))
    fi
    
    if [[ "$remaining_queues" -gt 0 ]]; then
        log_warning "Found ${remaining_queues} remaining task queues"
        cleanup_issues=$((cleanup_issues + 1))
    fi
    
    if [[ "$cleanup_issues" -gt 0 ]]; then
        log_warning "Cleanup completed with ${cleanup_issues} potential issues"
        log_warning "Some resources may require manual cleanup"
    else
        log_success "Cleanup verification completed successfully"
    fi
}

# Function to display cleanup summary
display_summary() {
    log_success "Cleanup completed!"
    
    cat << EOF

================================================================================
                    SMART CALENDAR INTELLIGENCE CLEANUP SUMMARY
================================================================================

Project:              ${PROJECT_ID}
Region:               ${REGION}
Cleanup Mode:         $([ "$DRY_RUN" == "true" ] && echo "DRY RUN" || echo "LIVE")

Resources Processed:
  🗑️  Cloud Run Services:       ${#API_SERVICES[@]} processed
  🗑️  Worker Pools:             ${#WORKER_POOLS[@]} processed
  🗑️  Task Queues:              ${#TASK_QUEUES[@]} processed
  🗑️  Scheduler Jobs:           ${#SCHEDULER_JOBS[@]} processed
  🗑️  BigQuery Datasets:        ${#DATASETS[@]} processed
  🗑️  Storage Buckets:          ${#BUCKETS[@]} processed
  🗑️  Artifact Repositories:    ${#REPOSITORIES[@]} processed
  🗑️  Service Accounts:         ${#SERVICE_ACCOUNTS[@]} processed

$([ "$DRY_RUN" == "true" ] && echo "NOTE: This was a dry run. No actual resources were deleted." || echo "All calendar intelligence resources have been permanently deleted.")

Next Steps:
  1. Verify no unexpected charges continue to accrue
  2. Review Cloud Billing console for any remaining resources
  3. Consider deleting the entire project if it was created solely for this recipe

Verification Commands:
  # Check for any remaining Cloud Run resources
  gcloud run services list --region=${REGION}
  
  # Check for any remaining BigQuery datasets
  bq ls
  
  # Check for any remaining storage buckets
  gsutil ls -p ${PROJECT_ID}

If you need to redeploy, run: ./deploy.sh

================================================================================
EOF
}

# Main cleanup function
main() {
    log_info "Starting Smart Calendar Intelligence cleanup..."
    log_info "Target project: ${PROJECT_ID}"
    log_info "Target region: ${REGION}"
    log_info "Dry run mode: ${DRY_RUN}"
    log_info "Force mode: ${FORCE_DELETE}"
    
    check_prerequisites
    discover_resources
    confirm_deletion
    
    # Delete resources in proper order (reverse of creation)
    delete_scheduler_jobs
    delete_cloud_run_resources
    delete_task_queues
    delete_bigquery_resources
    delete_storage_buckets
    delete_artifact_repositories
    delete_service_accounts
    cleanup_local_files
    
    verify_cleanup
    display_summary
}

# Trap errors
trap 'log_error "Cleanup failed at line $LINENO"' ERR

# Run main function
main "$@"