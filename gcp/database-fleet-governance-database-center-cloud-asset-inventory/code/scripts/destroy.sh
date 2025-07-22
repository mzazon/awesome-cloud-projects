#!/bin/bash

# Database Fleet Governance - Cleanup Script
# This script safely removes all resources created by the deploy.sh script
# including database instances, governance infrastructure, and monitoring components

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

# Error handling
error_exit() {
    log_error "$1"
    exit 1
}

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Resource tracking
RESOURCES_DELETED=()
FAILED_DELETIONS=()

# Track resource deletion
track_deletion() {
    local resource="$1"
    local status="$2"
    
    if [ "$status" = "success" ]; then
        RESOURCES_DELETED+=("$resource")
    else
        FAILED_DELETIONS+=("$resource")
    fi
}

# Confirmation prompt for destructive operations
confirm_deletion() {
    local resource_type="$1"
    
    echo -e "${YELLOW}[WARNING]${NC} This will permanently delete $resource_type"
    echo "This action cannot be undone."
    
    # Check for --force flag
    for arg in "$@"; do
        if [ "$arg" = "--force" ] || [ "$arg" = "-f" ]; then
            log_info "Force flag detected, skipping confirmation"
            return 0
        fi
    done
    
    read -p "Do you want to continue? (yes/no): " response
    case "$response" in
        [yY]|[yY][eE][sS])
            return 0
            ;;
        *)
            log_info "Operation cancelled by user"
            exit 0
            ;;
    esac
}

# Validate prerequisites
validate_prerequisites() {
    log_info "Validating prerequisites for cleanup..."
    
    # Check for required commands
    local required_commands=("gcloud" "bq" "gsutil")
    for cmd in "${required_commands[@]}"; do
        if ! command_exists "$cmd"; then
            error_exit "Required command '$cmd' not found. Please install it first."
        fi
    done
    
    # Check gcloud authentication
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        error_exit "No active gcloud authentication found. Run 'gcloud auth login' first."
    fi
    
    log_success "Prerequisites validated successfully"
}

# Set environment variables
setup_environment() {
    log_info "Setting up environment variables..."
    
    # Try to detect project from current gcloud config
    local current_project
    current_project=$(gcloud config get-value project 2>/dev/null || echo "")
    
    # Set environment variables
    export PROJECT_ID="${PROJECT_ID:-$current_project}"
    export REGION="${REGION:-us-central1}"
    export ZONE="${ZONE:-us-central1-a}"
    
    # Try to detect RANDOM_SUFFIX from existing resources
    if [ -z "${RANDOM_SUFFIX:-}" ]; then
        # Look for existing resources to extract suffix
        local sql_instances
        sql_instances=$(gcloud sql instances list --format="value(name)" --filter="name:fleet-sql-*" 2>/dev/null || echo "")
        
        if [ -n "$sql_instances" ]; then
            # Extract suffix from first matching instance
            export RANDOM_SUFFIX=$(echo "$sql_instances" | head -1 | sed 's/fleet-sql-//')
            log_info "Detected RANDOM_SUFFIX from existing resources: $RANDOM_SUFFIX"
        else
            log_warning "Could not detect RANDOM_SUFFIX. You may need to set it manually."
            log_warning "Example: export RANDOM_SUFFIX=abc123"
            read -p "Enter RANDOM_SUFFIX (or press Enter to continue without): " user_suffix
            export RANDOM_SUFFIX="${user_suffix:-unknown}"
        fi
    fi
    
    if [ -z "$PROJECT_ID" ]; then
        error_exit "PROJECT_ID not set. Please set it manually: export PROJECT_ID=your-project-id"
    fi
    
    export SERVICE_ACCOUNT="db-governance-sa@${PROJECT_ID}.iam.gserviceaccount.com"
    
    log_info "Project ID: $PROJECT_ID"
    log_info "Region: $REGION"
    log_info "Zone: $ZONE"
    log_info "Random Suffix: $RANDOM_SUFFIX"
    
    # Set default project
    gcloud config set project "$PROJECT_ID" || error_exit "Failed to set project"
    
    log_success "Environment configured successfully"
}

# Remove continuous governance automation
cleanup_automation() {
    log_info "Removing continuous governance automation..."
    
    # Delete Cloud Scheduler job
    if gcloud scheduler jobs describe governance-scheduler >/dev/null 2>&1; then
        log_info "Deleting Cloud Scheduler job..."
        if gcloud scheduler jobs delete governance-scheduler --quiet; then
            track_deletion "Cloud Scheduler job" "success"
        else
            track_deletion "Cloud Scheduler job" "failed"
            log_warning "Failed to delete Cloud Scheduler job"
        fi
    else
        log_info "Cloud Scheduler job not found or already deleted"
    fi
    
    # Delete Pub/Sub subscription
    if gcloud pubsub subscriptions describe governance-automation >/dev/null 2>&1; then
        log_info "Deleting Pub/Sub subscription..."
        if gcloud pubsub subscriptions delete governance-automation --quiet; then
            track_deletion "Pub/Sub subscription" "success"
        else
            track_deletion "Pub/Sub subscription" "failed"
            log_warning "Failed to delete Pub/Sub subscription"
        fi
    else
        log_info "Pub/Sub subscription not found or already deleted"
    fi
    
    # Delete Pub/Sub topic
    if gcloud pubsub topics describe database-asset-changes >/dev/null 2>&1; then
        log_info "Deleting Pub/Sub topic..."
        if gcloud pubsub topics delete database-asset-changes --quiet; then
            track_deletion "Pub/Sub topic" "success"
        else
            track_deletion "Pub/Sub topic" "failed"
            log_warning "Failed to delete Pub/Sub topic"
        fi
    else
        log_info "Pub/Sub topic not found or already deleted"
    fi
    
    log_success "Automation components cleanup completed"
}

# Remove Cloud Functions and Workflows
cleanup_functions_workflows() {
    log_info "Removing Cloud Functions and Workflows..."
    
    # Delete compliance reporting function
    if gcloud functions describe compliance-reporter >/dev/null 2>&1; then
        log_info "Deleting compliance reporting function..."
        if gcloud functions delete compliance-reporter --quiet; then
            track_deletion "Cloud Function" "success"
        else
            track_deletion "Cloud Function" "failed"
            log_warning "Failed to delete compliance reporting function"
        fi
    else
        log_info "Compliance reporting function not found or already deleted"
    fi
    
    # Delete governance workflow
    if gcloud workflows describe database-governance-workflow >/dev/null 2>&1; then
        log_info "Deleting governance workflow..."
        if gcloud workflows delete database-governance-workflow --quiet; then
            track_deletion "Cloud Workflow" "success"
        else
            track_deletion "Cloud Workflow" "failed"
            log_warning "Failed to delete governance workflow"
        fi
    else
        log_info "Governance workflow not found or already deleted"
    fi
    
    log_success "Functions and workflows cleanup completed"
}

# Remove monitoring and alerting
cleanup_monitoring() {
    log_info "Removing monitoring and alerting resources..."
    
    # Delete alert policies
    local alert_policies
    alert_policies=$(gcloud alpha monitoring policies list \
        --filter="displayName:'Database Governance Violations'" \
        --format="value(name)" 2>/dev/null || echo "")
    
    for policy in $alert_policies; do
        if [ -n "$policy" ]; then
            log_info "Deleting alert policy: $policy"
            if gcloud alpha monitoring policies delete "$policy" --quiet; then
                track_deletion "Alert policy" "success"
            else
                track_deletion "Alert policy" "failed"
                log_warning "Failed to delete alert policy: $policy"
            fi
        fi
    done
    
    # Delete notification channels
    local notification_channels
    notification_channels=$(gcloud alpha monitoring channels list \
        --filter="displayName:'Database Governance Alerts'" \
        --format="value(name)" 2>/dev/null || echo "")
    
    for channel in $notification_channels; do
        if [ -n "$channel" ]; then
            log_info "Deleting notification channel: $channel"
            if gcloud alpha monitoring channels delete "$channel" --quiet; then
                track_deletion "Notification channel" "success"
            else
                track_deletion "Notification channel" "failed"
                log_warning "Failed to delete notification channel: $channel"
            fi
        fi
    done
    
    # Delete log-based metrics
    local metrics=("database_compliance_score" "governance_events")
    for metric in "${metrics[@]}"; do
        if gcloud logging metrics describe "$metric" >/dev/null 2>&1; then
            log_info "Deleting log-based metric: $metric"
            if gcloud logging metrics delete "$metric" --quiet; then
                track_deletion "Log metric: $metric" "success"
            else
                track_deletion "Log metric: $metric" "failed"
                log_warning "Failed to delete log-based metric: $metric"
            fi
        else
            log_info "Log-based metric $metric not found or already deleted"
        fi
    done
    
    log_success "Monitoring and alerting cleanup completed"
}

# Remove storage resources
cleanup_storage() {
    log_info "Removing storage resources..."
    
    # Delete BigQuery dataset (with force flag to delete all tables)
    if bq ls -d "${PROJECT_ID}:database_governance" >/dev/null 2>&1; then
        log_info "Deleting BigQuery dataset with all tables..."
        if bq rm -r -f "${PROJECT_ID}:database_governance"; then
            track_deletion "BigQuery dataset" "success"
        else
            track_deletion "BigQuery dataset" "failed"
            log_warning "Failed to delete BigQuery dataset"
        fi
    else
        log_info "BigQuery dataset not found or already deleted"
    fi
    
    # Delete Cloud Storage bucket
    local bucket_name="db-governance-assets-${RANDOM_SUFFIX}"
    if gsutil ls "gs://${bucket_name}" >/dev/null 2>&1; then
        log_info "Deleting Cloud Storage bucket and all contents..."
        # First remove object versioning retention policy if any
        gsutil versioning set off "gs://${bucket_name}" 2>/dev/null || true
        
        # Remove all objects (including versioned objects)
        if gsutil -m rm -r "gs://${bucket_name}/**" 2>/dev/null || true; then
            # Now remove the bucket itself
            if gsutil rb "gs://${bucket_name}"; then
                track_deletion "Cloud Storage bucket" "success"
            else
                track_deletion "Cloud Storage bucket" "failed"
                log_warning "Failed to delete Cloud Storage bucket"
            fi
        else
            log_warning "Failed to delete bucket contents, attempting to delete bucket anyway"
            if gsutil rb "gs://${bucket_name}"; then
                track_deletion "Cloud Storage bucket" "success"
            else
                track_deletion "Cloud Storage bucket" "failed"
                log_warning "Failed to delete Cloud Storage bucket"
            fi
        fi
    else
        log_info "Cloud Storage bucket not found or already deleted"
    fi
    
    log_success "Storage resources cleanup completed"
}

# Remove database fleet
cleanup_database_fleet() {
    log_info "Removing database fleet..."
    
    # Remove Cloud SQL instance (need to disable deletion protection first)
    local sql_instance="fleet-sql-${RANDOM_SUFFIX}"
    if gcloud sql instances describe "$sql_instance" >/dev/null 2>&1; then
        log_info "Removing deletion protection from Cloud SQL instance..."
        gcloud sql instances patch "$sql_instance" \
            --no-deletion-protection --quiet 2>/dev/null || true
        
        log_info "Deleting Cloud SQL instance: $sql_instance"
        if gcloud sql instances delete "$sql_instance" --quiet; then
            track_deletion "Cloud SQL instance" "success"
        else
            track_deletion "Cloud SQL instance" "failed"
            log_warning "Failed to delete Cloud SQL instance"
        fi
    else
        log_info "Cloud SQL instance not found or already deleted"
    fi
    
    # Remove Spanner instance
    local spanner_instance="fleet-spanner-${RANDOM_SUFFIX}"
    if gcloud spanner instances describe "$spanner_instance" >/dev/null 2>&1; then
        log_info "Deleting Spanner instance: $spanner_instance"
        if gcloud spanner instances delete "$spanner_instance" --quiet; then
            track_deletion "Spanner instance" "success"
        else
            track_deletion "Spanner instance" "failed"
            log_warning "Failed to delete Spanner instance"
        fi
    else
        log_info "Spanner instance not found or already deleted"
    fi
    
    # Remove Bigtable instance
    local bigtable_instance="fleet-bigtable-${RANDOM_SUFFIX}"
    if gcloud bigtable instances describe "$bigtable_instance" >/dev/null 2>&1; then
        log_info "Deleting Bigtable instance: $bigtable_instance"
        if gcloud bigtable instances delete "$bigtable_instance" --quiet; then
            track_deletion "Bigtable instance" "success"
        else
            track_deletion "Bigtable instance" "failed"
            log_warning "Failed to delete Bigtable instance"
        fi
    else
        log_info "Bigtable instance not found or already deleted"
    fi
    
    log_success "Database fleet cleanup completed"
}

# Remove IAM service account and permissions
cleanup_iam() {
    log_info "Removing IAM service account and permissions..."
    
    # Delete service account
    if gcloud iam service-accounts describe "$SERVICE_ACCOUNT" >/dev/null 2>&1; then
        log_info "Deleting service account: $SERVICE_ACCOUNT"
        if gcloud iam service-accounts delete "$SERVICE_ACCOUNT" --quiet; then
            track_deletion "Service account" "success"
        else
            track_deletion "Service account" "failed"
            log_warning "Failed to delete service account"
        fi
    else
        log_info "Service account not found or already deleted"
    fi
    
    # Note: IAM policy bindings are automatically removed when the service account is deleted
    
    log_success "IAM cleanup completed"
}

# Clean up local files
cleanup_local_files() {
    log_info "Cleaning up local files..."
    
    local files_to_remove=(
        "governance-workflow.yaml"
        "governance-alert-policy.json"
        "gemini-queries.json"
        "governance-reporting"
    )
    
    for file in "${files_to_remove[@]}"; do
        if [ -e "$file" ]; then
            log_info "Removing local file/directory: $file"
            rm -rf "$file"
            track_deletion "Local file: $file" "success"
        fi
    done
    
    log_success "Local files cleanup completed"
}

# Optional: Disable APIs (only if user confirms)
cleanup_apis() {
    local disable_apis="$1"
    
    if [ "$disable_apis" = "true" ]; then
        log_info "Disabling Google Cloud APIs..."
        
        local apis=(
            "cloudasset.googleapis.com"
            "workflows.googleapis.com"
            "sqladmin.googleapis.com"
            "spanner.googleapis.com"
            "bigtableadmin.googleapis.com"
            "firestore.googleapis.com"
            "pubsub.googleapis.com"
            "cloudfunctions.googleapis.com"
            "cloudscheduler.googleapis.com"
            "aiplatform.googleapis.com"
        )
        
        for api in "${apis[@]}"; do
            log_info "Disabling API: $api"
            if gcloud services disable "$api" --quiet 2>/dev/null; then
                track_deletion "API: $api" "success"
            else
                track_deletion "API: $api" "failed"
                log_warning "Failed to disable API: $api (this is usually safe to ignore)"
            fi
        done
    else
        log_info "Skipping API disabling (APIs left enabled for other projects/services)"
    fi
}

# Display cleanup summary
display_cleanup_summary() {
    echo
    log_success "Database Fleet Governance cleanup completed!"
    echo
    echo "=== CLEANUP SUMMARY ==="
    echo "Project ID: $PROJECT_ID"
    echo "Random Suffix: $RANDOM_SUFFIX"
    echo
    
    if [ ${#RESOURCES_DELETED[@]} -gt 0 ]; then
        echo "=== SUCCESSFULLY DELETED RESOURCES ==="
        for resource in "${RESOURCES_DELETED[@]}"; do
            echo "  ✅ $resource"
        done
        echo
    fi
    
    if [ ${#FAILED_DELETIONS[@]} -gt 0 ]; then
        echo "=== FAILED DELETIONS ==="
        for resource in "${FAILED_DELETIONS[@]}"; do
            echo "  ❌ $resource"
        done
        echo
        log_warning "Some resources failed to delete. You may need to remove them manually."
        log_info "Check the Google Cloud Console for any remaining resources."
    fi
    
    echo "=== VERIFICATION COMMANDS ==="
    echo "Run these commands to verify cleanup:"
    echo "  gcloud sql instances list --filter=\"name:fleet-sql-${RANDOM_SUFFIX}\""
    echo "  gcloud spanner instances list --filter=\"name:fleet-spanner-${RANDOM_SUFFIX}\""
    echo "  gcloud bigtable instances list --filter=\"name:fleet-bigtable-${RANDOM_SUFFIX}\""
    echo "  gcloud functions list --filter=\"name:compliance-reporter\""
    echo "  gcloud workflows list --filter=\"name:database-governance-workflow\""
    echo "  gsutil ls gs://db-governance-assets-${RANDOM_SUFFIX}"
    echo
    
    if [ ${#FAILED_DELETIONS[@]} -eq 0 ]; then
        log_success "All resources were successfully cleaned up!"
    else
        log_warning "Cleanup completed with some errors. Please review failed deletions above."
    fi
}

# Usage information
show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo
    echo "Options:"
    echo "  -f, --force           Skip confirmation prompts"
    echo "  --disable-apis        Disable Google Cloud APIs after cleanup"
    echo "  --keep-project        Keep the project (don't delete it)"
    echo "  -h, --help           Show this help message"
    echo
    echo "Environment Variables:"
    echo "  PROJECT_ID           Google Cloud project ID (required)"
    echo "  RANDOM_SUFFIX        Suffix used for resource names (auto-detected if not set)"
    echo "  REGION               Google Cloud region (default: us-central1)"
    echo "  ZONE                 Google Cloud zone (default: us-central1-a)"
    echo
    echo "Examples:"
    echo "  $0                          # Interactive cleanup"
    echo "  $0 --force                  # Non-interactive cleanup"
    echo "  $0 --force --disable-apis   # Cleanup and disable APIs"
}

# Parse command line arguments
parse_arguments() {
    FORCE_MODE=false
    DISABLE_APIS=false
    KEEP_PROJECT=false
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            -f|--force)
                FORCE_MODE=true
                shift
                ;;
            --disable-apis)
                DISABLE_APIS=true
                shift
                ;;
            --keep-project)
                KEEP_PROJECT=true
                shift
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
    
    # Add force flag to arguments for confirm_deletion function
    if [ "$FORCE_MODE" = true ]; then
        set -- "$@" "--force"
    fi
}

# Main cleanup function
main() {
    log_info "Starting Database Fleet Governance cleanup..."
    echo "This script will remove all resources created by the deployment script."
    echo
    
    # Parse command line arguments
    parse_arguments "$@"
    
    # Validate prerequisites
    validate_prerequisites
    setup_environment
    
    # Show what will be deleted
    echo "=== RESOURCES TO BE DELETED ==="
    echo "• Database Fleet:"
    echo "  - Cloud SQL Instance: fleet-sql-${RANDOM_SUFFIX}"
    echo "  - Spanner Instance: fleet-spanner-${RANDOM_SUFFIX}"
    echo "  - Bigtable Instance: fleet-bigtable-${RANDOM_SUFFIX}"
    echo
    echo "• Governance Infrastructure:"
    echo "  - BigQuery Dataset: database_governance"
    echo "  - Storage Bucket: db-governance-assets-${RANDOM_SUFFIX}"
    echo "  - Pub/Sub Topic: database-asset-changes"
    echo "  - Cloud Workflow: database-governance-workflow"
    echo "  - Cloud Function: compliance-reporter"
    echo "  - Scheduler Job: governance-scheduler"
    echo "  - Monitoring alerts and metrics"
    echo
    echo "• Service Account: $SERVICE_ACCOUNT"
    echo
    
    # Confirm deletion unless force mode
    if [ "$FORCE_MODE" = false ]; then
        confirm_deletion "all database governance resources"
    fi
    
    # Execute cleanup steps in reverse order of creation
    cleanup_automation
    cleanup_functions_workflows
    cleanup_monitoring
    cleanup_storage
    cleanup_database_fleet
    cleanup_iam
    cleanup_local_files
    
    # Optionally disable APIs
    cleanup_apis "$DISABLE_APIS"
    
    display_cleanup_summary
}

# Run main function with all arguments
main "$@"