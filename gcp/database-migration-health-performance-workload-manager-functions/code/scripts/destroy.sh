#!/bin/bash

# Database Migration Health and Performance Monitoring - Cleanup Script
# This script removes all resources created by the deployment script
# including Cloud Functions, Cloud SQL instances, Pub/Sub resources, and monitoring dashboards

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
    exit 1
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1${NC}"
}

# Check if running in dry-run mode
DRY_RUN=false
FORCE_DELETE=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            warn "Running in DRY-RUN mode - no resources will be deleted"
            shift
            ;;
        --force)
            FORCE_DELETE=true
            info "Running in FORCE mode - skipping confirmation prompts"
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo "Options:"
            echo "  --dry-run    Show what would be deleted without actually deleting"
            echo "  --force      Skip confirmation prompts"
            echo "  --help, -h   Show this help message"
            exit 0
            ;;
        *)
            error "Unknown option: $1"
            ;;
    esac
done

# Function to run commands with dry-run support
run_command() {
    if [[ "$DRY_RUN" == "true" ]]; then
        info "DRY-RUN: $1"
    else
        eval "$1"
    fi
}

# Function to ask for confirmation
confirm_action() {
    local message="$1"
    if [[ "$FORCE_DELETE" == "true" || "$DRY_RUN" == "true" ]]; then
        return 0
    fi
    
    echo -e "${YELLOW}${message}${NC}"
    read -p "Are you sure? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        info "Operation cancelled by user"
        exit 0
    fi
}

log "Starting Database Migration Health Monitoring cleanup..."

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if gcloud CLI is installed
    if ! command -v gcloud &> /dev/null; then
        error "Google Cloud CLI (gcloud) is not installed. Please install it first."
    fi
    
    # Check if gsutil is available
    if ! command -v gsutil &> /dev/null; then
        error "gsutil is not available. Please ensure Google Cloud SDK is properly installed."
    fi
    
    # Check if user is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        error "No active Google Cloud authentication found. Please run 'gcloud auth login'"
    fi
    
    # Check if project is set
    if [[ -z "${PROJECT_ID:-}" ]]; then
        PROJECT_ID=$(gcloud config get-value project 2>/dev/null || echo "")
        if [[ -z "$PROJECT_ID" ]]; then
            error "PROJECT_ID environment variable not set and no default project configured. Please set PROJECT_ID or run 'gcloud config set project PROJECT_ID'"
        fi
    fi
    
    log "Prerequisites check completed"
}

# Set environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    # Set default values if not provided
    export PROJECT_ID=${PROJECT_ID:-$(gcloud config get-value project)}
    export REGION=${REGION:-"us-central1"}
    export ZONE=${ZONE:-"us-central1-a"}
    
    # Use provided suffix or try to find existing resources
    if [[ -z "${RANDOM_SUFFIX:-}" ]]; then
        # Try to find existing resources to determine suffix
        local instances=$(gcloud sql instances list --filter="name~migration-monitor-" --format="value(name)" 2>/dev/null || echo "")
        if [[ -n "$instances" ]]; then
            local instance_name=$(echo "$instances" | head -1)
            RANDOM_SUFFIX=$(echo "$instance_name" | sed 's/migration-monitor-//')
            info "Found existing resources with suffix: $RANDOM_SUFFIX"
        else
            # Try to list Cloud Functions to find suffix
            local functions=$(gcloud functions list --filter="name~migration-monitor" --format="value(name)" 2>/dev/null || echo "")
            if [[ -n "$functions" ]]; then
                info "Found existing Cloud Functions, will attempt cleanup"
                RANDOM_SUFFIX="unknown"
            else
                warn "No existing resources found with standard naming pattern"
                RANDOM_SUFFIX="unknown"
            fi
        fi
    fi
    
    export MIGRATION_NAME=${MIGRATION_NAME:-"migration-monitor-${RANDOM_SUFFIX}"}
    export WORKLOAD_NAME=${WORKLOAD_NAME:-"workload-monitor-${RANDOM_SUFFIX}"}
    export BUCKET_NAME=${BUCKET_NAME:-"${PROJECT_ID}-migration-monitoring-${RANDOM_SUFFIX}"}
    
    # Set gcloud defaults
    gcloud config set project ${PROJECT_ID} --quiet
    gcloud config set compute/region ${REGION} --quiet
    gcloud config set compute/zone ${ZONE} --quiet
    
    log "Environment configured:"
    info "  PROJECT_ID: ${PROJECT_ID}"
    info "  REGION: ${REGION}"
    info "  ZONE: ${ZONE}"
    info "  MIGRATION_NAME: ${MIGRATION_NAME}"
    info "  WORKLOAD_NAME: ${WORKLOAD_NAME}"
    info "  BUCKET_NAME: ${BUCKET_NAME}"
}

# List resources that will be deleted
list_resources() {
    log "Scanning for resources to delete..."
    
    echo ""
    echo "========================================"
    echo "RESOURCES TO BE DELETED"
    echo "========================================"
    
    # Check Cloud Functions
    local functions=$(gcloud functions list --filter="name~migration-monitor OR name~data-validator OR name~alert-manager" --format="value(name)" 2>/dev/null || echo "")
    if [[ -n "$functions" ]]; then
        echo "Cloud Functions:"
        echo "$functions" | sed 's/^/  - /'
    else
        echo "Cloud Functions: None found"
    fi
    
    # Check Cloud SQL instances
    local sql_instances=$(gcloud sql instances list --filter="name~migration-monitor-" --format="value(name)" 2>/dev/null || echo "")
    if [[ -n "$sql_instances" ]]; then
        echo "Cloud SQL Instances:"
        echo "$sql_instances" | sed 's/^/  - /'
    else
        echo "Cloud SQL Instances: None found"
    fi
    
    # Check Workload Manager evaluations
    local workload_evals=$(gcloud workload-manager evaluations list --location=${REGION} --filter="name~workload-monitor-" --format="value(name)" 2>/dev/null || echo "")
    if [[ -n "$workload_evals" ]]; then
        echo "Workload Manager Evaluations:"
        echo "$workload_evals" | sed 's/^/  - /'
    else
        echo "Workload Manager Evaluations: None found"
    fi
    
    # Check Pub/Sub topics
    local topics=$(gcloud pubsub topics list --filter="name~migration-events OR name~validation-results OR name~alert-notifications" --format="value(name)" 2>/dev/null || echo "")
    if [[ -n "$topics" ]]; then
        echo "Pub/Sub Topics:"
        echo "$topics" | sed 's/^/  - /'
    else
        echo "Pub/Sub Topics: None found"
    fi
    
    # Check Storage buckets
    if gsutil ls -b gs://${BUCKET_NAME} &>/dev/null; then
        echo "Storage Buckets:"
        echo "  - gs://${BUCKET_NAME}"
    else
        echo "Storage Buckets: None found"
    fi
    
    # Check monitoring dashboards
    local dashboards=$(gcloud monitoring dashboards list --filter="displayName~Database Migration" --format="value(name)" 2>/dev/null || echo "")
    if [[ -n "$dashboards" ]]; then
        echo "Monitoring Dashboards:"
        echo "$dashboards" | sed 's/^/  - /'
    else
        echo "Monitoring Dashboards: None found"
    fi
    
    echo "========================================"
    echo ""
}

# Delete Cloud Functions
delete_cloud_functions() {
    log "Deleting Cloud Functions..."
    
    local functions=("migration-monitor" "data-validator" "alert-manager")
    
    for func in "${functions[@]}"; do
        if gcloud functions describe "$func" --quiet &>/dev/null; then
            info "Deleting Cloud Function: $func"
            run_command "gcloud functions delete $func --quiet"
        else
            warn "Cloud Function $func not found, skipping"
        fi
    done
    
    log "Cloud Functions cleanup completed"
}

# Delete Workload Manager resources
delete_workload_manager() {
    log "Deleting Workload Manager resources..."
    
    # Delete workload evaluation
    if gcloud workload-manager evaluations describe ${WORKLOAD_NAME} --location=${REGION} --quiet &>/dev/null; then
        info "Deleting Workload Manager evaluation: ${WORKLOAD_NAME}"
        run_command "gcloud workload-manager evaluations delete ${WORKLOAD_NAME} --location=${REGION} --quiet"
    else
        warn "Workload Manager evaluation ${WORKLOAD_NAME} not found, skipping"
    fi
    
    # Also try to delete any evaluations that might have different naming
    local evaluations=$(gcloud workload-manager evaluations list --location=${REGION} --filter="name~workload-monitor-" --format="value(name)" 2>/dev/null || echo "")
    if [[ -n "$evaluations" ]]; then
        info "Found additional workload evaluations to delete"
        while IFS= read -r eval_name; do
            if [[ -n "$eval_name" ]]; then
                eval_id=$(basename "$eval_name")
                info "Deleting workload evaluation: $eval_id"
                run_command "gcloud workload-manager evaluations delete $eval_id --location=${REGION} --quiet"
            fi
        done <<< "$evaluations"
    fi
    
    log "Workload Manager cleanup completed"
}

# Delete Cloud SQL instances
delete_cloudsql_instances() {
    log "Deleting Cloud SQL instances..."
    
    # Delete primary instance
    if gcloud sql instances describe ${MIGRATION_NAME}-target --quiet &>/dev/null; then
        info "Deleting Cloud SQL instance: ${MIGRATION_NAME}-target"
        run_command "gcloud sql instances delete ${MIGRATION_NAME}-target --quiet"
    else
        warn "Cloud SQL instance ${MIGRATION_NAME}-target not found, skipping"
    fi
    
    # Also try to delete any instances that might have different naming
    local instances=$(gcloud sql instances list --filter="name~migration-monitor-" --format="value(name)" 2>/dev/null || echo "")
    if [[ -n "$instances" ]]; then
        info "Found additional Cloud SQL instances to delete"
        while IFS= read -r instance_name; do
            if [[ -n "$instance_name" && "$instance_name" != "${MIGRATION_NAME}-target" ]]; then
                info "Deleting Cloud SQL instance: $instance_name"
                run_command "gcloud sql instances delete $instance_name --quiet"
            fi
        done <<< "$instances"
    fi
    
    log "Cloud SQL instances cleanup completed"
}

# Delete Pub/Sub resources
delete_pubsub_resources() {
    log "Deleting Pub/Sub resources..."
    
    local subscriptions=("migration-monitor-sub" "validation-processor-sub" "alert-manager-sub")
    local topics=("migration-events" "validation-results" "alert-notifications")
    
    # Delete subscriptions first
    for sub in "${subscriptions[@]}"; do
        if gcloud pubsub subscriptions describe "$sub" --quiet &>/dev/null; then
            info "Deleting Pub/Sub subscription: $sub"
            run_command "gcloud pubsub subscriptions delete $sub --quiet"
        else
            warn "Pub/Sub subscription $sub not found, skipping"
        fi
    done
    
    # Delete topics
    for topic in "${topics[@]}"; do
        if gcloud pubsub topics describe "$topic" --quiet &>/dev/null; then
            info "Deleting Pub/Sub topic: $topic"
            run_command "gcloud pubsub topics delete $topic --quiet"
        else
            warn "Pub/Sub topic $topic not found, skipping"
        fi
    done
    
    log "Pub/Sub resources cleanup completed"
}

# Delete Storage resources
delete_storage_resources() {
    log "Deleting Storage resources..."
    
    # Delete storage bucket and contents
    if gsutil ls -b gs://${BUCKET_NAME} &>/dev/null; then
        info "Deleting storage bucket: gs://${BUCKET_NAME}"
        run_command "gsutil -m rm -r gs://${BUCKET_NAME}"
    else
        warn "Storage bucket gs://${BUCKET_NAME} not found, skipping"
    fi
    
    # Clean up local files
    if [[ -d "migration-functions" ]]; then
        info "Removing local migration-functions directory"
        run_command "rm -rf migration-functions/"
    fi
    
    if [[ -f "dashboard-config.json" ]]; then
        info "Removing local dashboard configuration file"
        run_command "rm -f dashboard-config.json"
    fi
    
    log "Storage resources cleanup completed"
}

# Delete monitoring dashboards
delete_monitoring_dashboards() {
    log "Deleting monitoring dashboards..."
    
    # List and delete dashboards related to database migration
    local dashboards=$(gcloud monitoring dashboards list --filter="displayName~Database Migration" --format="value(name)" 2>/dev/null || echo "")
    
    if [[ -n "$dashboards" ]]; then
        while IFS= read -r dashboard_name; do
            if [[ -n "$dashboard_name" ]]; then
                dashboard_id=$(basename "$dashboard_name")
                info "Deleting monitoring dashboard: $dashboard_id"
                run_command "gcloud monitoring dashboards delete $dashboard_id --quiet"
            fi
        done <<< "$dashboards"
    else
        warn "No monitoring dashboards found with 'Database Migration' in name"
    fi
    
    log "Monitoring dashboards cleanup completed"
}

# Verify cleanup completion
verify_cleanup() {
    log "Verifying cleanup completion..."
    
    local cleanup_issues=()
    
    # Check Cloud Functions
    if gcloud functions list --filter="name~migration-monitor OR name~data-validator OR name~alert-manager" --format="value(name)" 2>/dev/null | grep -q .; then
        cleanup_issues+=("Some Cloud Functions still exist")
    fi
    
    # Check Cloud SQL instances
    if gcloud sql instances list --filter="name~migration-monitor-" --format="value(name)" 2>/dev/null | grep -q .; then
        cleanup_issues+=("Some Cloud SQL instances still exist")
    fi
    
    # Check Workload Manager evaluations
    if gcloud workload-manager evaluations list --location=${REGION} --filter="name~workload-monitor-" --format="value(name)" 2>/dev/null | grep -q .; then
        cleanup_issues+=("Some Workload Manager evaluations still exist")
    fi
    
    # Check Pub/Sub topics
    if gcloud pubsub topics list --filter="name~migration-events OR name~validation-results OR name~alert-notifications" --format="value(name)" 2>/dev/null | grep -q .; then
        cleanup_issues+=("Some Pub/Sub topics still exist")
    fi
    
    # Check Storage buckets
    if gsutil ls -b gs://${BUCKET_NAME} &>/dev/null; then
        cleanup_issues+=("Storage bucket still exists")
    fi
    
    if [[ ${#cleanup_issues[@]} -eq 0 ]]; then
        log "All resources have been successfully cleaned up"
    else
        warn "Some resources may still exist:"
        for issue in "${cleanup_issues[@]}"; do
            warn "  - $issue"
        done
        warn "You may need to manually delete these resources or re-run the cleanup script"
    fi
}

# Main cleanup function
main() {
    log "Starting Database Migration Health Monitoring cleanup..."
    
    check_prerequisites
    setup_environment
    list_resources
    
    # Confirm deletion
    confirm_action "This will delete all resources listed above. This action cannot be undone."
    
    # Perform cleanup in reverse order of creation
    delete_cloud_functions
    delete_workload_manager
    delete_cloudsql_instances
    delete_pubsub_resources
    delete_storage_resources
    delete_monitoring_dashboards
    
    # Verify cleanup
    if [[ "$DRY_RUN" == "false" ]]; then
        verify_cleanup
    fi
    
    log "Cleanup completed successfully!"
    
    # Display final summary
    echo ""
    echo "========================================"
    echo "CLEANUP SUMMARY"
    echo "========================================"
    echo "Project ID: ${PROJECT_ID}"
    echo "Region: ${REGION}"
    echo ""
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "DRY-RUN MODE: No resources were actually deleted"
        echo "Run without --dry-run to perform actual cleanup"
    else
        echo "Resources deleted:"
        echo "  ✓ Cloud Functions (migration-monitor, data-validator, alert-manager)"
        echo "  ✓ Cloud SQL instances"
        echo "  ✓ Workload Manager evaluations"
        echo "  ✓ Pub/Sub topics and subscriptions"
        echo "  ✓ Storage buckets and local files"
        echo "  ✓ Monitoring dashboards"
        echo ""
        echo "All monitoring infrastructure has been removed"
    fi
    echo "========================================"
}

# Handle script interruption
cleanup_on_exit() {
    if [[ $? -ne 0 ]]; then
        warn "Cleanup script interrupted. Some resources may not have been deleted."
        info "You can re-run this script to continue cleanup, or manually delete remaining resources."
    fi
}

trap cleanup_on_exit EXIT

# Run main function
main "$@"