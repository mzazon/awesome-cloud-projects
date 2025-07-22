#!/bin/bash

# Real-Time Supply Chain Visibility with Cloud Dataflow and Cloud Spanner - Cleanup Script
# This script removes all resources created by the deployment script

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

# Check if running in dry-run mode
DRY_RUN=false
if [[ "${1:-}" == "--dry-run" ]]; then
    DRY_RUN=true
    log_info "Running in dry-run mode - no resources will be deleted"
fi

# Check if force mode is enabled (skip confirmation prompts)
FORCE_MODE=false
if [[ "${1:-}" == "--force" ]] || [[ "${2:-}" == "--force" ]]; then
    FORCE_MODE=true
    log_info "Running in force mode - skipping confirmation prompts"
fi

# Function to execute commands with dry-run support
execute_cmd() {
    local cmd="$1"
    local description="$2"
    local ignore_errors="${3:-false}"
    
    log_info "$description"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        echo -e "${YELLOW}[DRY-RUN]${NC} Would execute: $cmd"
        return 0
    fi
    
    if eval "$cmd"; then
        log_success "$description completed"
        return 0
    else
        if [[ "$ignore_errors" == "true" ]]; then
            log_warning "$description failed (ignored)"
            return 0
        else
            log_error "$description failed"
            return 1
        fi
    fi
}

# Function to confirm destructive actions
confirm_action() {
    local action="$1"
    
    if [[ "$FORCE_MODE" == "true" ]]; then
        return 0
    fi
    
    echo -e "${YELLOW}[CONFIRM]${NC} Are you sure you want to $action? (y/N)"
    read -r response
    case "$response" in
        [yY][eE][sS]|[yY])
            return 0
            ;;
        *)
            log_info "Action cancelled by user"
            return 1
            ;;
    esac
}

# Function to load environment variables
load_environment() {
    log_info "Loading environment variables..."
    
    # Try to load from deployment script environment
    if [[ -f ".env" ]]; then
        source .env
        log_info "Loaded environment from .env file"
    fi
    
    # Set defaults if not provided
    if [[ -z "${PROJECT_ID:-}" ]]; then
        log_warning "PROJECT_ID not set. Please provide it as an environment variable."
        read -p "Enter PROJECT_ID: " PROJECT_ID
        export PROJECT_ID
    fi
    
    if [[ -z "${REGION:-}" ]]; then
        export REGION="us-central1"
    fi
    
    if [[ -z "${ZONE:-}" ]]; then
        export ZONE="us-central1-a"
    fi
    
    # Try to detect resource names from existing resources
    if [[ -z "${SPANNER_INSTANCE:-}" ]]; then
        log_info "Detecting Spanner instance..."
        SPANNER_INSTANCE=$(gcloud spanner instances list --format="value(name)" --filter="name:supply-chain-instance*" | head -1 2>/dev/null || echo "")
        if [[ -n "$SPANNER_INSTANCE" ]]; then
            export SPANNER_INSTANCE
            log_info "Found Spanner instance: $SPANNER_INSTANCE"
        fi
    fi
    
    if [[ -z "${STORAGE_BUCKET:-}" ]]; then
        log_info "Detecting storage bucket..."
        STORAGE_BUCKET=$(gsutil ls -p "$PROJECT_ID" 2>/dev/null | grep "supply-chain-dataflow" | head -1 | sed 's|gs://||' | sed 's|/||' || echo "")
        if [[ -n "$STORAGE_BUCKET" ]]; then
            export STORAGE_BUCKET
            log_info "Found storage bucket: $STORAGE_BUCKET"
        fi
    fi
    
    if [[ -z "${DATAFLOW_JOB:-}" ]]; then
        log_info "Detecting Dataflow job..."
        DATAFLOW_JOB=$(gcloud dataflow jobs list --region="$REGION" --format="value(name)" --filter="name:supply-chain-streaming*" | head -1 2>/dev/null || echo "")
        if [[ -n "$DATAFLOW_JOB" ]]; then
            export DATAFLOW_JOB
            log_info "Found Dataflow job: $DATAFLOW_JOB"
        fi
    fi
    
    # Set other resource names
    export SPANNER_DATABASE="${SPANNER_DATABASE:-supply-chain-db}"
    export PUBSUB_TOPIC="${PUBSUB_TOPIC:-logistics-events}"
    export PUBSUB_SUBSCRIPTION="${PUBSUB_SUBSCRIPTION:-logistics-events-sub}"
    export BIGQUERY_DATASET="${BIGQUERY_DATASET:-supply_chain_analytics}"
    
    log_success "Environment variables loaded"
    log_info "PROJECT_ID: $PROJECT_ID"
    log_info "REGION: $REGION"
    log_info "SPANNER_INSTANCE: ${SPANNER_INSTANCE:-not found}"
    log_info "STORAGE_BUCKET: ${STORAGE_BUCKET:-not found}"
    log_info "DATAFLOW_JOB: ${DATAFLOW_JOB:-not found}"
}

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if gcloud CLI is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "gcloud CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if authenticated with gcloud
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" &> /dev/null; then
        log_error "Not authenticated with gcloud. Please run 'gcloud auth login' first."
        exit 1
    fi
    
    # Check if project exists
    if ! gcloud projects describe "$PROJECT_ID" &> /dev/null; then
        log_error "Project $PROJECT_ID does not exist or is not accessible."
        exit 1
    fi
    
    # Set project context
    gcloud config set project "$PROJECT_ID"
    
    log_success "Prerequisites check passed"
}

# Function to stop Dataflow pipeline
stop_dataflow_pipeline() {
    log_info "Stopping Dataflow pipeline..."
    
    if [[ -n "${DATAFLOW_JOB:-}" ]]; then
        if confirm_action "stop Dataflow pipeline '$DATAFLOW_JOB'"; then
            # Get job ID
            JOB_ID=$(gcloud dataflow jobs list --region="$REGION" --filter="name:$DATAFLOW_JOB" --format="value(id)" --limit=1 2>/dev/null || echo "")
            
            if [[ -n "$JOB_ID" ]]; then
                execute_cmd "gcloud dataflow jobs cancel $JOB_ID --region=$REGION" \
                    "Stopping Dataflow job $DATAFLOW_JOB" "true"
                
                # Wait for job to stop
                if [[ "$DRY_RUN" == "false" ]]; then
                    log_info "Waiting for job to stop..."
                    sleep 30
                fi
            else
                log_warning "Dataflow job not found or already stopped"
            fi
        fi
    else
        log_warning "No Dataflow job found to stop"
    fi
    
    log_success "Dataflow pipeline cleanup completed"
}

# Function to remove BigQuery resources
remove_bigquery_resources() {
    log_info "Removing BigQuery resources..."
    
    if confirm_action "delete BigQuery dataset '$BIGQUERY_DATASET' and all its tables"; then
        execute_cmd "bq rm -r -f ${PROJECT_ID}:${BIGQUERY_DATASET}" \
            "Removing BigQuery dataset" "true"
    fi
    
    log_success "BigQuery resources cleanup completed"
}

# Function to remove Spanner resources
remove_spanner_resources() {
    log_info "Removing Spanner resources..."
    
    if [[ -n "${SPANNER_INSTANCE:-}" ]]; then
        if confirm_action "delete Spanner instance '$SPANNER_INSTANCE' and database '$SPANNER_DATABASE'"; then
            # Delete database first
            execute_cmd "gcloud spanner databases delete $SPANNER_DATABASE \
                --instance=$SPANNER_INSTANCE \
                --quiet" \
                "Removing Spanner database" "true"
            
            # Delete instance
            execute_cmd "gcloud spanner instances delete $SPANNER_INSTANCE --quiet" \
                "Removing Spanner instance" "true"
        fi
    else
        log_warning "No Spanner instance found to remove"
    fi
    
    log_success "Spanner resources cleanup completed"
}

# Function to remove Pub/Sub resources
remove_pubsub_resources() {
    log_info "Removing Pub/Sub resources..."
    
    if confirm_action "delete Pub/Sub topic '$PUBSUB_TOPIC' and subscription '$PUBSUB_SUBSCRIPTION'"; then
        # Delete subscription first
        execute_cmd "gcloud pubsub subscriptions delete $PUBSUB_SUBSCRIPTION" \
            "Removing Pub/Sub subscription" "true"
        
        # Delete topic
        execute_cmd "gcloud pubsub topics delete $PUBSUB_TOPIC" \
            "Removing Pub/Sub topic" "true"
    fi
    
    log_success "Pub/Sub resources cleanup completed"
}

# Function to remove Cloud Storage resources
remove_storage_resources() {
    log_info "Removing Cloud Storage resources..."
    
    if [[ -n "${STORAGE_BUCKET:-}" ]]; then
        if confirm_action "delete Cloud Storage bucket 'gs://$STORAGE_BUCKET' and all its contents"; then
            # Check if bucket exists
            if gsutil ls -b "gs://$STORAGE_BUCKET" &> /dev/null; then
                execute_cmd "gsutil -m rm -r gs://$STORAGE_BUCKET" \
                    "Removing storage bucket" "true"
            else
                log_warning "Storage bucket not found or already deleted"
            fi
        fi
    else
        log_warning "No storage bucket found to remove"
    fi
    
    log_success "Storage resources cleanup completed"
}

# Function to clean up local files
cleanup_local_files() {
    log_info "Cleaning up local files..."
    
    if confirm_action "delete local pipeline files and event generator"; then
        # Remove pipeline directory
        if [[ -d "dataflow-pipeline" ]]; then
            execute_cmd "rm -rf dataflow-pipeline" \
                "Removing pipeline directory" "true"
        fi
        
        # Remove event generator
        if [[ -f "generate_sample_events.py" ]]; then
            execute_cmd "rm generate_sample_events.py" \
                "Removing event generator" "true"
        fi
        
        # Remove environment file if exists
        if [[ -f ".env" ]]; then
            execute_cmd "rm .env" \
                "Removing environment file" "true"
        fi
    fi
    
    log_success "Local files cleanup completed"
}

# Function to disable APIs (optional)
disable_apis() {
    log_info "Disabling APIs (optional)..."
    
    if confirm_action "disable Google Cloud APIs (this may affect other resources in the project)"; then
        local apis=(
            "dataflow.googleapis.com"
            "spanner.googleapis.com"
            "pubsub.googleapis.com"
            "bigquery.googleapis.com"
        )
        
        for api in "${apis[@]}"; do
            execute_cmd "gcloud services disable $api --force" \
                "Disabling $api" "true"
        done
    else
        log_info "Skipping API disable - APIs remain enabled"
    fi
    
    log_success "API cleanup completed"
}

# Function to delete project (optional)
delete_project() {
    log_info "Project deletion (optional)..."
    
    if confirm_action "DELETE THE ENTIRE PROJECT '$PROJECT_ID' (this will remove ALL resources in the project)"; then
        log_warning "This action will DELETE ALL RESOURCES in project $PROJECT_ID"
        log_warning "This includes any resources not created by this recipe!"
        
        if confirm_action "PERMANENTLY DELETE project '$PROJECT_ID'"; then
            execute_cmd "gcloud projects delete $PROJECT_ID --quiet" \
                "Deleting project" "true"
            
            log_info "Project deletion initiated. It may take several minutes to complete."
        fi
    else
        log_info "Skipping project deletion - project preserved"
    fi
    
    log_success "Project deletion process completed"
}

# Function to verify cleanup
verify_cleanup() {
    log_info "Verifying resource cleanup..."
    
    if [[ "$DRY_RUN" == "false" ]]; then
        # Check Spanner instances
        log_info "Checking for remaining Spanner instances..."
        REMAINING_SPANNER=$(gcloud spanner instances list --format="value(name)" --filter="name:supply-chain-instance*" 2>/dev/null || echo "")
        if [[ -n "$REMAINING_SPANNER" ]]; then
            log_warning "Found remaining Spanner instances: $REMAINING_SPANNER"
        else
            log_success "No Spanner instances found"
        fi
        
        # Check storage buckets
        log_info "Checking for remaining storage buckets..."
        REMAINING_BUCKETS=$(gsutil ls -p "$PROJECT_ID" 2>/dev/null | grep "supply-chain-dataflow" || echo "")
        if [[ -n "$REMAINING_BUCKETS" ]]; then
            log_warning "Found remaining storage buckets: $REMAINING_BUCKETS"
        else
            log_success "No storage buckets found"
        fi
        
        # Check Dataflow jobs
        log_info "Checking for remaining Dataflow jobs..."
        REMAINING_JOBS=$(gcloud dataflow jobs list --region="$REGION" --format="value(name)" --filter="name:supply-chain-streaming*" 2>/dev/null || echo "")
        if [[ -n "$REMAINING_JOBS" ]]; then
            log_warning "Found remaining Dataflow jobs: $REMAINING_JOBS"
        else
            log_success "No Dataflow jobs found"
        fi
        
        # Check BigQuery datasets
        log_info "Checking for remaining BigQuery datasets..."
        REMAINING_BQ=$(bq ls -d --format="value(datasetId)" "$PROJECT_ID" 2>/dev/null | grep "supply_chain_analytics" || echo "")
        if [[ -n "$REMAINING_BQ" ]]; then
            log_warning "Found remaining BigQuery datasets: $REMAINING_BQ"
        else
            log_success "No BigQuery datasets found"
        fi
        
        # Check Pub/Sub topics
        log_info "Checking for remaining Pub/Sub resources..."
        REMAINING_TOPICS=$(gcloud pubsub topics list --format="value(name)" --filter="name:logistics-events" 2>/dev/null || echo "")
        if [[ -n "$REMAINING_TOPICS" ]]; then
            log_warning "Found remaining Pub/Sub topics: $REMAINING_TOPICS"
        else
            log_success "No Pub/Sub topics found"
        fi
    else
        log_info "Skipping verification in dry-run mode"
    fi
    
    log_success "Cleanup verification completed"
}

# Function to display cleanup summary
display_summary() {
    log_success "Cleanup completed!"
    echo
    echo "=== CLEANUP SUMMARY ==="
    echo "Project ID: $PROJECT_ID"
    echo "Region: $REGION"
    echo
    echo "=== RESOURCES CLEANED UP ==="
    echo "✓ Dataflow pipeline stopped"
    echo "✓ BigQuery dataset and tables removed"
    echo "✓ Spanner instance and database removed"
    echo "✓ Pub/Sub topic and subscription removed"
    echo "✓ Cloud Storage bucket removed"
    echo "✓ Local files cleaned up"
    echo
    echo "=== IMPORTANT NOTES ==="
    echo "• Check the GCP Console to verify all resources are removed"
    echo "• Some resources may take a few minutes to be fully deleted"
    echo "• If you deleted the project, it may take up to 30 minutes to complete"
    echo "• Monitor your billing to ensure no unexpected charges"
    echo
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "=== DRY RUN MODE ==="
        echo "No actual resources were deleted. Run without --dry-run to perform cleanup."
    fi
}

# Main cleanup function
main() {
    echo "=== Real-Time Supply Chain Visibility - Cleanup Script ==="
    echo
    
    load_environment
    check_prerequisites
    
    log_warning "This script will DELETE resources and may incur final charges"
    log_warning "Make sure you have backed up any important data"
    echo
    
    if [[ "$FORCE_MODE" == "false" ]] && [[ "$DRY_RUN" == "false" ]]; then
        echo -e "${YELLOW}[CONFIRM]${NC} Do you want to proceed with cleanup? (y/N)"
        read -r response
        case "$response" in
            [yY][eE][sS]|[yY])
                log_info "Proceeding with cleanup..."
                ;;
            *)
                log_info "Cleanup cancelled by user"
                exit 0
                ;;
        esac
    fi
    
    echo
    stop_dataflow_pipeline
    remove_bigquery_resources
    remove_spanner_resources
    remove_pubsub_resources
    remove_storage_resources
    cleanup_local_files
    
    # Optional steps
    echo
    log_info "Optional cleanup steps:"
    disable_apis
    delete_project
    
    echo
    verify_cleanup
    display_summary
}

# Run main function
main "$@"