#!/bin/bash

# Error Monitoring and Debugging with Cloud Error Reporting and Cloud Functions
# Cleanup Script for GCP Recipe
#
# This script safely removes all resources created by the error monitoring system
# deployment, including Cloud Functions, Pub/Sub topics, storage buckets, and
# monitoring dashboards.

set -e  # Exit on any error
set -u  # Exit on undefined variables

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

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Default values
DEFAULT_REGION="us-central1"
DEFAULT_ZONE="us-central1-a"

# Function to display usage
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Clean up all resources created by the error monitoring system deployment.

OPTIONS:
    -p, --project-id PROJECT_ID     GCP Project ID (required)
    -r, --region REGION             GCP region (default: ${DEFAULT_REGION})
    -z, --zone ZONE                 GCP zone (default: ${DEFAULT_ZONE})
    -s, --suffix SUFFIX             Resource suffix used during deployment
    --force                         Skip confirmation prompts
    --keep-firestore                Keep Firestore database (recommended for production)
    --keep-logs                     Keep Cloud Logging data
    --dry-run                       Show what would be deleted without making changes
    -h, --help                      Display this help message

EXAMPLES:
    $0 --project-id my-project-123
    $0 --project-id my-project-123 --suffix abc123 --force
    $0 --project-id my-project-123 --keep-firestore --keep-logs

SAFETY FEATURES:
    - Confirmation prompts for destructive operations
    - Option to preserve Firestore data
    - Dry-run mode to preview changes
    - Detailed logging of all operations

EOF
}

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "Google Cloud CLI (gcloud) is not installed or not in PATH"
        exit 1
    fi
    
    # Check if gsutil is installed
    if ! command -v gsutil &> /dev/null; then
        log_error "gsutil is not installed or not in PATH"
        exit 1
    fi
    
    # Check gcloud authentication
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 > /dev/null; then
        log_error "No active gcloud authentication found"
        log_info "Run: gcloud auth login"
        exit 1
    fi
    
    log_success "Prerequisites check completed"
}

# Function to validate project
validate_project() {
    log_info "Validating project access..."
    
    # Check if project exists and is accessible
    if ! gcloud projects describe "$PROJECT_ID" &> /dev/null; then
        log_error "Project '$PROJECT_ID' not found or not accessible"
        exit 1
    fi
    
    # Set the project
    gcloud config set project "$PROJECT_ID" --quiet
    log_success "Project validated: $PROJECT_ID"
}

# Function to discover resources
discover_resources() {
    log_info "Discovering deployed resources..."
    
    # Discover Cloud Functions with the pattern
    log_info "Scanning for Cloud Functions..."
    DISCOVERED_FUNCTIONS=($(gcloud functions list \
        --regions="$REGION" \
        --format="value(name)" \
        --filter="name:error-processor OR name:sample-error-app" 2>/dev/null || true))
    
    # If suffix is provided, look for functions with that suffix
    if [[ -n "${RESOURCE_SUFFIX:-}" ]]; then
        FUNCTION_NAME="error-processor-${RESOURCE_SUFFIX}"
        PUBSUB_TOPIC="error-notifications-${RESOURCE_SUFFIX}"
        STORAGE_BUCKET="${PROJECT_ID}-error-debug-data-${RESOURCE_SUFFIX}"
    else
        # Try to discover suffix from existing resources
        if [[ ${#DISCOVERED_FUNCTIONS[@]} -gt 0 ]]; then
            # Extract suffix from first function name
            first_function="${DISCOVERED_FUNCTIONS[0]}"
            if [[ "$first_function" =~ error-processor-(.+) ]]; then
                RESOURCE_SUFFIX="${BASH_REMATCH[1]}"
                FUNCTION_NAME="error-processor-${RESOURCE_SUFFIX}"
                PUBSUB_TOPIC="error-notifications-${RESOURCE_SUFFIX}"
                STORAGE_BUCKET="${PROJECT_ID}-error-debug-data-${RESOURCE_SUFFIX}"
                log_info "Discovered resource suffix: $RESOURCE_SUFFIX"
            fi
        fi
    fi
    
    # Discover Pub/Sub topics
    log_info "Scanning for Pub/Sub topics..."
    DISCOVERED_TOPICS=($(gcloud pubsub topics list \
        --format="value(name.basename())" \
        --filter="name:error-notifications" 2>/dev/null || true))
    
    # Discover Storage buckets
    log_info "Scanning for Cloud Storage buckets..."
    DISCOVERED_BUCKETS=($(gsutil ls -p "$PROJECT_ID" 2>/dev/null | \
        grep "error-debug-data" | \
        sed 's|gs://||g' | \
        sed 's|/||g' || true))
    
    # Discover monitoring dashboards
    log_info "Scanning for monitoring dashboards..."
    DISCOVERED_DASHBOARDS=($(gcloud monitoring dashboards list \
        --format="value(name)" \
        --filter="displayName:'Error Monitoring Dashboard'" 2>/dev/null || true))
    
    # Discover log sinks
    log_info "Scanning for log sinks..."
    DISCOVERED_LOG_SINKS=($(gcloud logging sinks list \
        --format="value(name)" \
        --filter="name:error-notification-sink" 2>/dev/null || true))
    
    # Display discovered resources
    log_info "Resource discovery summary:"
    echo "  Functions: ${#DISCOVERED_FUNCTIONS[@]} found"
    echo "  Pub/Sub Topics: ${#DISCOVERED_TOPICS[@]} found"
    echo "  Storage Buckets: ${#DISCOVERED_BUCKETS[@]} found"
    echo "  Dashboards: ${#DISCOVERED_DASHBOARDS[@]} found"
    echo "  Log Sinks: ${#DISCOVERED_LOG_SINKS[@]} found"
    
    if [[ -n "${RESOURCE_SUFFIX:-}" ]]; then
        echo "  Resource Suffix: $RESOURCE_SUFFIX"
    fi
}

# Function to confirm destructive operations
confirm_deletion() {
    if [[ "${FORCE_DELETE}" == "true" ]]; then
        return 0
    fi
    
    echo
    log_warning "This will permanently delete the following resources:"
    echo
    
    if [[ ${#DISCOVERED_FUNCTIONS[@]} -gt 0 ]]; then
        echo "Cloud Functions:"
        for func in "${DISCOVERED_FUNCTIONS[@]}"; do
            echo "  - $func"
        done
        echo
    fi
    
    if [[ ${#DISCOVERED_TOPICS[@]} -gt 0 ]]; then
        echo "Pub/Sub Topics:"
        for topic in "${DISCOVERED_TOPICS[@]}"; do
            echo "  - $topic"
        done
        echo
    fi
    
    if [[ ${#DISCOVERED_BUCKETS[@]} -gt 0 ]]; then
        echo "Storage Buckets (and all contents):"
        for bucket in "${DISCOVERED_BUCKETS[@]}"; do
            echo "  - gs://$bucket"
        done
        echo
    fi
    
    if [[ ${#DISCOVERED_DASHBOARDS[@]} -gt 0 ]]; then
        echo "Monitoring Dashboards:"
        for dashboard in "${DISCOVERED_DASHBOARDS[@]}"; do
            echo "  - $dashboard"
        done
        echo
    fi
    
    if [[ "${KEEP_FIRESTORE}" == "false" ]]; then
        echo "Firestore Collections:"
        echo "  - errors"
        echo "  - error_aggregates"
        echo "  - incidents"
        echo "  - alert_routing_log"
        echo
    fi
    
    echo -n "Are you sure you want to proceed? (yes/no): "
    read -r confirmation
    
    if [[ "$confirmation" != "yes" ]]; then
        log_info "Cleanup cancelled by user"
        exit 0
    fi
}

# Function to delete Cloud Functions
delete_cloud_functions() {
    if [[ ${#DISCOVERED_FUNCTIONS[@]} -eq 0 ]]; then
        log_info "No Cloud Functions found to delete"
        return 0
    fi
    
    log_info "Deleting Cloud Functions..."
    
    for function in "${DISCOVERED_FUNCTIONS[@]}"; do
        if [[ "$DRY_RUN" == "true" ]]; then
            log_info "[DRY RUN] Would delete function: $function"
        else
            log_info "Deleting function: $function"
            if gcloud functions delete "$function" \
                --region="$REGION" \
                --quiet; then
                log_success "Deleted function: $function"
            else
                log_warning "Failed to delete function: $function (may not exist)"
            fi
        fi
    done
    
    # Also try to delete functions with known naming pattern if suffix is available
    if [[ -n "${FUNCTION_NAME:-}" ]]; then
        local functions_to_delete=(
            "$FUNCTION_NAME"
            "${FUNCTION_NAME}-router"
            "${FUNCTION_NAME}-debug"
            "sample-error-app"
        )
        
        for function in "${functions_to_delete[@]}"; do
            if gcloud functions describe "$function" --region="$REGION" &> /dev/null; then
                if [[ "$DRY_RUN" == "true" ]]; then
                    log_info "[DRY RUN] Would delete function: $function"
                else
                    log_info "Deleting function: $function"
                    gcloud functions delete "$function" \
                        --region="$REGION" \
                        --quiet
                    log_success "Deleted function: $function"
                fi
            fi
        done
    fi
}

# Function to delete Pub/Sub topics
delete_pubsub_topics() {
    if [[ ${#DISCOVERED_TOPICS[@]} -eq 0 ]] && [[ -z "${PUBSUB_TOPIC:-}" ]]; then
        log_info "No Pub/Sub topics found to delete"
        return 0
    fi
    
    log_info "Deleting Pub/Sub topics..."
    
    # Delete discovered topics
    for topic in "${DISCOVERED_TOPICS[@]}"; do
        if [[ "$DRY_RUN" == "true" ]]; then
            log_info "[DRY RUN] Would delete topic: $topic"
        else
            log_info "Deleting topic: $topic"
            if gcloud pubsub topics delete "$topic" --quiet; then
                log_success "Deleted topic: $topic"
            else
                log_warning "Failed to delete topic: $topic (may not exist)"
            fi
        fi
    done
    
    # Also try to delete topics with known naming pattern if suffix is available
    if [[ -n "${PUBSUB_TOPIC:-}" ]]; then
        local topics_to_delete=(
            "$PUBSUB_TOPIC"
            "${PUBSUB_TOPIC}-alerts"
            "${PUBSUB_TOPIC}-debug"
        )
        
        for topic in "${topics_to_delete[@]}"; do
            if gcloud pubsub topics describe "$topic" &> /dev/null; then
                if [[ "$DRY_RUN" == "true" ]]; then
                    log_info "[DRY RUN] Would delete topic: $topic"
                else
                    log_info "Deleting topic: $topic"
                    gcloud pubsub topics delete "$topic" --quiet
                    log_success "Deleted topic: $topic"
                fi
            fi
        done
    fi
}

# Function to delete Cloud Storage buckets
delete_storage_buckets() {
    if [[ ${#DISCOVERED_BUCKETS[@]} -eq 0 ]] && [[ -z "${STORAGE_BUCKET:-}" ]]; then
        log_info "No Cloud Storage buckets found to delete"
        return 0
    fi
    
    log_info "Deleting Cloud Storage buckets..."
    
    # Delete discovered buckets
    for bucket in "${DISCOVERED_BUCKETS[@]}"; do
        if [[ "$DRY_RUN" == "true" ]]; then
            log_info "[DRY RUN] Would delete bucket: gs://$bucket"
        else
            log_info "Deleting bucket: gs://$bucket"
            if gsutil -m rm -r "gs://$bucket" 2>/dev/null; then
                log_success "Deleted bucket: gs://$bucket"
            else
                log_warning "Failed to delete bucket: gs://$bucket (may not exist or be empty)"
            fi
        fi
    done
    
    # Also try to delete bucket with known naming pattern if suffix is available
    if [[ -n "${STORAGE_BUCKET:-}" ]]; then
        if gsutil ls "gs://${STORAGE_BUCKET}" &> /dev/null; then
            if [[ "$DRY_RUN" == "true" ]]; then
                log_info "[DRY RUN] Would delete bucket: gs://$STORAGE_BUCKET"
            else
                log_info "Deleting bucket: gs://$STORAGE_BUCKET"
                gsutil -m rm -r "gs://${STORAGE_BUCKET}"
                log_success "Deleted bucket: gs://$STORAGE_BUCKET"
            fi
        fi
    fi
}

# Function to delete monitoring dashboards
delete_monitoring_dashboards() {
    if [[ ${#DISCOVERED_DASHBOARDS[@]} -eq 0 ]]; then
        log_info "No monitoring dashboards found to delete"
        return 0
    fi
    
    log_info "Deleting monitoring dashboards..."
    
    for dashboard in "${DISCOVERED_DASHBOARDS[@]}"; do
        if [[ "$DRY_RUN" == "true" ]]; then
            log_info "[DRY RUN] Would delete dashboard: $dashboard"
        else
            log_info "Deleting dashboard: $dashboard"
            if gcloud monitoring dashboards delete "$dashboard" --quiet; then
                log_success "Deleted dashboard: $dashboard"
            else
                log_warning "Failed to delete dashboard: $dashboard (may not exist)"
            fi
        fi
    done
}

# Function to delete log sinks
delete_log_sinks() {
    if [[ ${#DISCOVERED_LOG_SINKS[@]} -eq 0 ]]; then
        log_info "No log sinks found to delete"
        return 0
    fi
    
    log_info "Deleting log sinks..."
    
    for sink in "${DISCOVERED_LOG_SINKS[@]}"; do
        if [[ "$DRY_RUN" == "true" ]]; then
            log_info "[DRY RUN] Would delete log sink: $sink"
        else
            log_info "Deleting log sink: $sink"
            if gcloud logging sinks delete "$sink" --quiet; then
                log_success "Deleted log sink: $sink"
            else
                log_warning "Failed to delete log sink: $sink (may not exist)"
            fi
        fi
    done
}

# Function to delete alert policies
delete_alert_policies() {
    log_info "Deleting monitoring alert policies..."
    
    # Find alert policies created by the error monitoring system
    local alert_policies
    alert_policies=($(gcloud alpha monitoring policies list \
        --filter="displayName:Error Alert" \
        --format="value(name)" 2>/dev/null || true))
    
    if [[ ${#alert_policies[@]} -eq 0 ]]; then
        log_info "No alert policies found to delete"
        return 0
    fi
    
    for policy in "${alert_policies[@]}"; do
        if [[ "$DRY_RUN" == "true" ]]; then
            log_info "[DRY RUN] Would delete alert policy: $policy"
        else
            log_info "Deleting alert policy: $policy"
            if gcloud alpha monitoring policies delete "$policy" --quiet; then
                log_success "Deleted alert policy: $policy"
            else
                log_warning "Failed to delete alert policy: $policy (may not exist)"
            fi
        fi
    done
}

# Function to clean Firestore data
clean_firestore_data() {
    if [[ "$KEEP_FIRESTORE" == "true" ]]; then
        log_info "Keeping Firestore data as requested"
        return 0
    fi
    
    log_info "Cleaning Firestore collections..."
    
    local collections=("errors" "error_aggregates" "incidents" "alert_routing_log")
    
    for collection in "${collections[@]}"; do
        if [[ "$DRY_RUN" == "true" ]]; then
            log_info "[DRY RUN] Would delete Firestore collection: $collection"
        else
            log_info "Deleting Firestore collection: $collection"
            # Note: This is a simple deletion. In production, you might want to backup data first
            if gcloud firestore export gs://${STORAGE_BUCKET:-$PROJECT_ID-backup}/firestore-backup \
                --collection-ids="$collection" &> /dev/null; then
                log_info "Backed up collection $collection before deletion"
            fi
            
            # Delete the collection (be very careful with this in production)
            log_warning "Firestore collection deletion requires manual intervention for safety"
            log_info "To delete collection '$collection', run:"
            log_info "  gcloud firestore collections delete $collection --recursive"
        fi
    done
}

# Function to remove temporary files
cleanup_temp_files() {
    log_info "Cleaning up temporary files..."
    
    local temp_files=(
        "${PROJECT_ROOT}/dashboard_config.json"
        "${PROJECT_ROOT}/functions"
    )
    
    for item in "${temp_files[@]}"; do
        if [[ -f "$item" ]] || [[ -d "$item" ]]; then
            if [[ "$DRY_RUN" == "true" ]]; then
                log_info "[DRY RUN] Would remove: $item"
            else
                log_info "Removing: $item"
                rm -rf "$item"
                log_success "Removed: $item"
            fi
        fi
    done
}

# Function to display cleanup summary
display_cleanup_summary() {
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "DRY RUN SUMMARY - No resources were actually deleted"
    else
        log_success "Cleanup completed successfully!"
    fi
    
    echo
    echo "=== CLEANUP SUMMARY ==="
    echo "Project ID: $PROJECT_ID"
    echo "Region: $REGION"
    if [[ -n "${RESOURCE_SUFFIX:-}" ]]; then
        echo "Resource Suffix: $RESOURCE_SUFFIX"
    fi
    echo
    echo "=== RESOURCES PROCESSED ==="
    echo "Cloud Functions: ${#DISCOVERED_FUNCTIONS[@]} deleted"
    echo "Pub/Sub Topics: ${#DISCOVERED_TOPICS[@]} deleted"
    echo "Storage Buckets: ${#DISCOVERED_BUCKETS[@]} deleted"
    echo "Monitoring Dashboards: ${#DISCOVERED_DASHBOARDS[@]} deleted"
    echo "Log Sinks: ${#DISCOVERED_LOG_SINKS[@]} deleted"
    echo
    
    if [[ "$KEEP_FIRESTORE" == "true" ]]; then
        echo "Firestore: Data preserved as requested"
    else
        echo "Firestore: Collections marked for deletion (manual intervention required)"
    fi
    
    if [[ "$KEEP_LOGS" == "true" ]]; then
        echo "Cloud Logging: Data preserved as requested"
    else
        echo "Cloud Logging: Data retention follows project settings"
    fi
    
    echo
    if [[ "$DRY_RUN" == "false" ]]; then
        echo "=== VERIFICATION ==="
        echo "To verify cleanup, check the following:"
        echo "1. Cloud Functions: https://console.cloud.google.com/functions?project=$PROJECT_ID"
        echo "2. Pub/Sub Topics: https://console.cloud.google.com/cloudpubsub/topic?project=$PROJECT_ID"
        echo "3. Storage Buckets: https://console.cloud.google.com/storage/browser?project=$PROJECT_ID"
        echo "4. Monitoring: https://console.cloud.google.com/monitoring/dashboards?project=$PROJECT_ID"
        echo
        echo "=== COST IMPACT ==="
        echo "Resource deletion should reduce ongoing costs for:"
        echo "- Cloud Functions compute time"
        echo "- Pub/Sub message processing"
        echo "- Cloud Storage usage"
        echo "- Cloud Monitoring queries"
    fi
}

# Main cleanup function
main() {
    local project_id=""
    local region="$DEFAULT_REGION"
    local zone="$DEFAULT_ZONE"
    local resource_suffix=""
    local force_delete=false
    local keep_firestore=false
    local keep_logs=false
    local dry_run=false
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -p|--project-id)
                project_id="$2"
                shift 2
                ;;
            -r|--region)
                region="$2"
                shift 2
                ;;
            -z|--zone)
                zone="$2"
                shift 2
                ;;
            -s|--suffix)
                resource_suffix="$2"
                shift 2
                ;;
            --force)
                force_delete=true
                shift
                ;;
            --keep-firestore)
                keep_firestore=true
                shift
                ;;
            --keep-logs)
                keep_logs=true
                shift
                ;;
            --dry-run)
                dry_run=true
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
    if [[ -z "$project_id" ]]; then
        log_error "Project ID is required. Use --project-id or -p option."
        usage
        exit 1
    fi
    
    # Set global variables
    PROJECT_ID="$project_id"
    REGION="$region"
    ZONE="$zone"
    RESOURCE_SUFFIX="$resource_suffix"
    FORCE_DELETE="$force_delete"
    KEEP_FIRESTORE="$keep_firestore"
    KEEP_LOGS="$keep_logs"
    DRY_RUN="$dry_run"
    
    if [[ "$dry_run" == "true" ]]; then
        log_info "DRY RUN MODE - No resources will be deleted"
    fi
    
    log_info "Starting cleanup of Error Monitoring System..."
    log_info "Project: $PROJECT_ID"
    log_info "Region: $REGION"
    
    # Execute cleanup steps
    check_prerequisites
    validate_project
    discover_resources
    
    if [[ "$dry_run" == "false" ]]; then
        confirm_deletion
    fi
    
    delete_cloud_functions
    delete_pubsub_topics
    delete_storage_buckets
    delete_monitoring_dashboards
    delete_log_sinks
    delete_alert_policies
    clean_firestore_data
    cleanup_temp_files
    display_cleanup_summary
    
    if [[ "$dry_run" == "false" ]]; then
        log_success "Cleanup completed successfully!"
    else
        log_info "Dry run completed. Use --force to execute actual cleanup."
    fi
}

# Run main function with all arguments
main "$@"