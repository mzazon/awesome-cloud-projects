#!/bin/bash

# Destroy script for Sustainable Infrastructure Intelligence with Smart Analytics Hub and Cloud Carbon Footprint
# This script removes all resources created by the deployment script

set -euo pipefail

# Colors for output
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
DRY_RUN="${DRY_RUN:-false}"
FORCE="${FORCE:-false}"
KEEP_PROJECT="${KEEP_PROJECT:-false}"

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --force)
            FORCE=true
            shift
            ;;
        --keep-project)
            KEEP_PROJECT=true
            shift
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo "Options:"
            echo "  --dry-run       Show what would be deleted without actually deleting"
            echo "  --force         Skip confirmation prompts"
            echo "  --keep-project  Keep the Google Cloud project (only delete resources)"
            echo "  --help          Show this help message"
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "Google Cloud CLI (gcloud) is not installed"
        exit 1
    fi
    
    # Check if bq is installed
    if ! command -v bq &> /dev/null; then
        log_error "BigQuery CLI (bq) is not installed"
        exit 1
    fi
    
    # Check if gsutil is installed
    if ! command -v gsutil &> /dev/null; then
        log_error "Cloud Storage CLI (gsutil) is not installed"
        exit 1
    fi
    
    # Check authentication
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        log_error "No active Google Cloud authentication found"
        log_info "Run: gcloud auth login"
        exit 1
    fi
    
    log_success "Prerequisites check completed"
}

# Load environment variables
load_environment() {
    log_info "Loading environment variables..."
    
    # Try to get current project
    CURRENT_PROJECT=$(gcloud config get-value project 2>/dev/null || echo "")
    
    # Set environment variables (use current project if available, or ask user)
    if [ -n "$CURRENT_PROJECT" ]; then
        export PROJECT_ID="${PROJECT_ID:-$CURRENT_PROJECT}"
    else
        if [ -z "${PROJECT_ID:-}" ]; then
            log_error "PROJECT_ID environment variable not set and no current project configured"
            log_info "Set PROJECT_ID environment variable or run: gcloud config set project YOUR_PROJECT_ID"
            exit 1
        fi
    fi
    
    export REGION="${REGION:-us-central1}"
    export ZONE="${ZONE:-us-central1-a}"
    
    # Resource names (should match deploy script)
    export DATASET_NAME="${DATASET_NAME:-carbon_intelligence}"
    export TOPIC_NAME="${TOPIC_NAME:-carbon-alerts}"
    export FUNCTION_NAME="${FUNCTION_NAME:-carbon-processor}"
    
    # Try to find bucket with carbon-reports prefix
    if [ -z "${BUCKET_NAME:-}" ]; then
        BUCKET_CANDIDATES=$(gsutil ls -p "$PROJECT_ID" 2>/dev/null | grep "gs://carbon-reports-" || echo "")
        if [ -n "$BUCKET_CANDIDATES" ]; then
            export BUCKET_NAME=$(echo "$BUCKET_CANDIDATES" | head -1 | sed 's/gs:\/\///' | sed 's/\///')
            log_info "Found bucket: $BUCKET_NAME"
        fi
    fi
    
    log_info "Project ID: $PROJECT_ID"
    log_info "Region: $REGION"
    log_info "Dataset: $DATASET_NAME"
    log_info "Topic: $TOPIC_NAME"
    log_info "Function: $FUNCTION_NAME"
    if [ -n "${BUCKET_NAME:-}" ]; then
        log_info "Bucket: $BUCKET_NAME"
    fi
    
    # Set default project
    gcloud config set project "$PROJECT_ID" --quiet
    
    log_success "Environment variables loaded"
}

# Confirmation prompt
confirm_destruction() {
    if [ "$FORCE" = "true" ]; then
        return 0
    fi
    
    echo
    log_warning "This will delete the following resources in project '$PROJECT_ID':"
    echo "  • Cloud Functions (carbon-processor, recommendations-engine)"
    echo "  • Cloud Scheduler jobs (recommendations-weekly, data-processing-monthly)"
    echo "  • BigQuery dataset and Smart Analytics Hub resources ($DATASET_NAME)"
    echo "  • Cloud Storage bucket and contents ($BUCKET_NAME)"
    echo "  • Pub/Sub topic and subscription ($TOPIC_NAME)"
    echo "  • Service accounts (looker-studio-sa)"
    if [ "$KEEP_PROJECT" = "false" ]; then
        echo "  • Google Cloud Project ($PROJECT_ID)"
    fi
    echo
    
    if [ "$DRY_RUN" = "true" ]; then
        log_info "DRY RUN MODE: No resources will actually be deleted"
        return 0
    fi
    
    read -p "Are you sure you want to continue? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Destruction cancelled"
        exit 0
    fi
}

# Execute command with dry-run support
execute_command() {
    local cmd="$1"
    local description="$2"
    
    if [ "$DRY_RUN" = "true" ]; then
        log_info "[DRY RUN] Would execute: $cmd"
        log_info "[DRY RUN] $description"
    else
        log_info "$description"
        eval "$cmd" || {
            log_warning "Command failed (continuing): $cmd"
        }
    fi
}

# Delete Cloud Functions
delete_functions() {
    log_info "Deleting Cloud Functions..."
    
    # List and delete all functions in the region
    local functions=$(gcloud functions list --regions="$REGION" --format="value(name)" 2>/dev/null || echo "")
    
    if [ -n "$functions" ]; then
        for func in $functions; do
            if [[ "$func" == *"$FUNCTION_NAME"* ]] || [[ "$func" == *"recommendations-engine"* ]]; then
                execute_command \
                    "gcloud functions delete '$func' --region='$REGION' --quiet" \
                    "Deleting function: $func"
            fi
        done
    else
        log_info "No Cloud Functions found to delete"
    fi
    
    log_success "Cloud Functions deletion completed"
}

# Delete Cloud Scheduler jobs
delete_scheduler_jobs() {
    log_info "Deleting Cloud Scheduler jobs..."
    
    # List and delete scheduler jobs
    local jobs=$(gcloud scheduler jobs list --location="$REGION" --format="value(name)" 2>/dev/null || echo "")
    
    if [ -n "$jobs" ]; then
        for job in $jobs; do
            if [[ "$job" == *"recommendations-weekly"* ]] || [[ "$job" == *"data-processing-monthly"* ]]; then
                execute_command \
                    "gcloud scheduler jobs delete '$job' --location='$REGION' --quiet" \
                    "Deleting scheduler job: $job"
            fi
        done
    else
        log_info "No Cloud Scheduler jobs found to delete"
    fi
    
    log_success "Cloud Scheduler jobs deletion completed"
}

# Delete BigQuery resources
delete_bigquery_resources() {
    log_info "Deleting BigQuery and Smart Analytics Hub resources..."
    
    # Delete Smart Analytics Hub listings and exchanges
    local exchanges=$(bq ls --data_exchanges --location="$REGION" --format="value(name)" 2>/dev/null || echo "")
    
    if [ -n "$exchanges" ]; then
        for exchange in $exchanges; do
            if [[ "$exchange" == *"sustainability_exchange"* ]]; then
                # Delete listings first
                local listings=$(bq ls --listings --data_exchange="$exchange" --location="$REGION" --format="value(name)" 2>/dev/null || echo "")
                for listing in $listings; do
                    execute_command \
                        "bq rm --listing --location='$REGION' '$exchange.$listing'" \
                        "Deleting Analytics Hub listing: $listing"
                done
                
                # Delete exchange
                execute_command \
                    "bq rm --data_exchange --location='$REGION' '$exchange'" \
                    "Deleting Analytics Hub exchange: $exchange"
            fi
        done
    fi
    
    # Delete BigQuery dataset
    execute_command \
        "bq rm -r -f '${PROJECT_ID}:${DATASET_NAME}'" \
        "Deleting BigQuery dataset: $DATASET_NAME"
    
    # Delete data transfer configurations
    local transfers=$(gcloud transfer configs list --location="$REGION" --format="value(name)" 2>/dev/null || echo "")
    for transfer in $transfers; do
        if [[ "$transfer" == *"Carbon Footprint"* ]]; then
            execute_command \
                "gcloud transfer configs delete '$transfer' --location='$REGION' --quiet" \
                "Deleting data transfer: $transfer"
        fi
    done
    
    log_success "BigQuery resources deletion completed"
}

# Delete Cloud Storage bucket
delete_storage_resources() {
    log_info "Deleting Cloud Storage resources..."
    
    if [ -n "${BUCKET_NAME:-}" ]; then
        # Check if bucket exists
        if gsutil ls -b "gs://$BUCKET_NAME" &>/dev/null; then
            execute_command \
                "gsutil -m rm -r 'gs://$BUCKET_NAME'" \
                "Deleting storage bucket: $BUCKET_NAME"
        else
            log_info "Storage bucket $BUCKET_NAME not found or already deleted"
        fi
    else
        # Try to find and delete any carbon-reports buckets
        local buckets=$(gsutil ls -p "$PROJECT_ID" 2>/dev/null | grep "gs://carbon-reports-" || echo "")
        if [ -n "$buckets" ]; then
            for bucket in $buckets; do
                bucket_name=$(echo "$bucket" | sed 's/gs:\/\///' | sed 's/\///')
                execute_command \
                    "gsutil -m rm -r '$bucket'" \
                    "Deleting storage bucket: $bucket_name"
            done
        else
            log_info "No carbon-reports storage buckets found"
        fi
    fi
    
    log_success "Storage resources deletion completed"
}

# Delete Pub/Sub resources
delete_pubsub_resources() {
    log_info "Deleting Pub/Sub resources..."
    
    # Delete subscription first
    execute_command \
        "gcloud pubsub subscriptions delete 'carbon-alerts-sub' --quiet" \
        "Deleting Pub/Sub subscription: carbon-alerts-sub"
    
    # Delete topic
    execute_command \
        "gcloud pubsub topics delete '$TOPIC_NAME' --quiet" \
        "Deleting Pub/Sub topic: $TOPIC_NAME"
    
    log_success "Pub/Sub resources deletion completed"
}

# Delete service accounts
delete_service_accounts() {
    log_info "Deleting service accounts..."
    
    # Delete Looker Studio service account
    execute_command \
        "gcloud iam service-accounts delete 'looker-studio-sa@${PROJECT_ID}.iam.gserviceaccount.com' --quiet" \
        "Deleting service account: looker-studio-sa"
    
    log_success "Service accounts deletion completed"
}

# Delete project
delete_project() {
    if [ "$KEEP_PROJECT" = "true" ]; then
        log_info "Keeping Google Cloud project as requested"
        return 0
    fi
    
    log_info "Deleting Google Cloud project..."
    
    execute_command \
        "gcloud projects delete '$PROJECT_ID' --quiet" \
        "Deleting project: $PROJECT_ID"
    
    if [ "$DRY_RUN" = "false" ]; then
        log_warning "Project deletion may take several minutes to complete"
        log_info "You can check status with: gcloud projects describe $PROJECT_ID"
    fi
    
    log_success "Project deletion initiated"
}

# Verify deletion
verify_deletion() {
    if [ "$DRY_RUN" = "true" ]; then
        log_info "DRY RUN completed - no resources were actually deleted"
        return 0
    fi
    
    log_info "Verifying resource deletion..."
    
    # Check Cloud Functions
    local remaining_functions=$(gcloud functions list --regions="$REGION" --filter="name:($FUNCTION_NAME OR recommendations-engine)" --format="value(name)" 2>/dev/null || echo "")
    if [ -n "$remaining_functions" ]; then
        log_warning "Some Cloud Functions may still exist: $remaining_functions"
    fi
    
    # Check BigQuery dataset
    if bq show "${PROJECT_ID}:${DATASET_NAME}" &>/dev/null; then
        log_warning "BigQuery dataset $DATASET_NAME may still exist"
    fi
    
    # Check storage bucket
    if [ -n "${BUCKET_NAME:-}" ] && gsutil ls -b "gs://$BUCKET_NAME" &>/dev/null; then
        log_warning "Storage bucket $BUCKET_NAME may still exist"
    fi
    
    # Check Pub/Sub topic
    if gcloud pubsub topics describe "$TOPIC_NAME" &>/dev/null; then
        log_warning "Pub/Sub topic $TOPIC_NAME may still exist"
    fi
    
    log_info "Verification completed"
}

# Print summary
print_summary() {
    echo
    if [ "$DRY_RUN" = "true" ]; then
        log_info "=== DRY RUN SUMMARY ==="
        log_info "No resources were actually deleted"
        log_info "Run without --dry-run to perform actual deletion"
    else
        log_success "=== DESTRUCTION SUMMARY ==="
        log_success "Resource cleanup completed for project: $PROJECT_ID"
        
        if [ "$KEEP_PROJECT" = "false" ]; then
            log_info "Project deletion initiated - may take several minutes"
        else
            log_info "Project preserved as requested"
        fi
        
        echo
        log_info "=== CLEANUP NOTES ==="
        echo "• Some resources may take time to fully delete"
        echo "• Check billing to ensure no unexpected charges"
        echo "• Data transfer configurations may need manual cleanup"
        echo "• Organization-level Analytics Hub permissions may persist"
    fi
    echo
}

# Main destruction function
main() {
    log_info "Starting destruction of Sustainable Infrastructure Intelligence solution..."
    
    if [ "$DRY_RUN" = "true" ]; then
        log_info "DRY RUN MODE: No resources will be deleted"
    fi
    
    echo
    
    check_prerequisites
    load_environment
    confirm_destruction
    
    echo
    log_info "Beginning resource deletion..."
    
    delete_functions
    delete_scheduler_jobs
    delete_bigquery_resources
    delete_storage_resources
    delete_pubsub_resources
    delete_service_accounts
    
    if [ "$KEEP_PROJECT" = "false" ]; then
        delete_project
    fi
    
    verify_deletion
    print_summary
}

# Run main function
main "$@"