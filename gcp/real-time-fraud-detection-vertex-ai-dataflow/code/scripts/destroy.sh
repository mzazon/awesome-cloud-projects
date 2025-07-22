#!/bin/bash

# Cleanup Real-Time Fraud Detection with Vertex AI and Cloud Dataflow
# This script safely removes all resources created by the deployment script

set -euo pipefail

# Color codes for output formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Global variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/destroy.log"
DEPLOYMENT_STATE_FILE="${SCRIPT_DIR}/.deployment_state"

# Initialize logging
exec 1> >(tee -a "${LOG_FILE}")
exec 2> >(tee -a "${LOG_FILE}" >&2)

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

# Error handling
cleanup_on_error() {
    log_error "Cleanup failed. Check ${LOG_FILE} for details."
    exit 1
}

trap cleanup_on_error ERR

# Help function
show_help() {
    cat << EOF
Cleanup Real-Time Fraud Detection with Vertex AI and Cloud Dataflow

USAGE:
    $0 [OPTIONS]

OPTIONS:
    -p, --project-id PROJECT_ID     Google Cloud project ID (optional if state file exists)
    -r, --region REGION            Deployment region (optional if state file exists)
    -f, --force                    Skip confirmation prompts
    -h, --help                     Show this help message
    --dry-run                      Show what would be deleted without deleting
    --keep-project                 Do not offer to delete the entire project
    --partial-cleanup              Clean up only specific resource types

EXAMPLES:
    $0                             # Use configuration from deployment state file
    $0 --project-id my-project     # Specify project explicitly
    $0 --force --dry-run           # Show what would be deleted without prompts
    $0 --partial-cleanup           # Interactive cleanup of specific resources

PREREQUISITES:
    - Google Cloud CLI (gcloud) installed and authenticated
    - Access to the project where resources were deployed
    - Appropriate permissions to delete resources

EOF
}

# Parse command line arguments
parse_arguments() {
    PROJECT_ID=""
    REGION=""
    FORCE=false
    DRY_RUN=false
    KEEP_PROJECT=false
    PARTIAL_CLEANUP=false

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
                FORCE=true
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --keep-project)
                KEEP_PROJECT=true
                shift
                ;;
            --partial-cleanup)
                PARTIAL_CLEANUP=true
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

# Load configuration from deployment state
load_deployment_state() {
    if [[ -f "$DEPLOYMENT_STATE_FILE" ]]; then
        log_info "Loading deployment configuration from state file..."
        source "$DEPLOYMENT_STATE_FILE"
        
        # Use loaded values if not provided via command line
        if [[ -z "$PROJECT_ID" ]]; then
            PROJECT_ID="${PROJECT_ID:-}"
        fi
        
        if [[ -z "$REGION" ]]; then
            REGION="${REGION:-us-central1}"
        fi
        
        log_success "Configuration loaded from deployment state"
    else
        log_warning "No deployment state file found at: $DEPLOYMENT_STATE_FILE"
        
        if [[ -z "$PROJECT_ID" ]]; then
            log_error "Project ID is required when no state file exists. Use --project-id option."
            exit 1
        fi
        
        if [[ -z "$REGION" ]]; then
            REGION="us-central1"
            log_info "Using default region: $REGION"
        fi
    fi
}

# Prerequisites validation
check_prerequisites() {
    log_info "Validating prerequisites..."

    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "Google Cloud CLI (gcloud) is not installed. Please install it first."
        exit 1
    fi

    # Check authentication
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        log_error "No active gcloud authentication found. Run 'gcloud auth login' first."
        exit 1
    fi

    # Validate project exists and is accessible
    if ! gcloud projects describe "$PROJECT_ID" &>/dev/null; then
        log_error "Cannot access project '$PROJECT_ID'. Check project ID and permissions."
        exit 1
    fi

    # Set project context
    gcloud config set project "$PROJECT_ID"
    gcloud config set compute/region "$REGION"

    log_success "Prerequisites validation completed"
}

# Confirmation prompt
confirm_destruction() {
    if [[ "$FORCE" == "true" ]] || [[ "$DRY_RUN" == "true" ]]; then
        return 0
    fi

    echo
    echo "======================================"
    echo "        DESTRUCTION WARNING"
    echo "======================================"
    echo "This will DELETE the following resources:"
    echo "• All Dataflow jobs in project: $PROJECT_ID"
    echo "• BigQuery dataset and tables: $DATASET_ID"
    echo "• Pub/Sub topic and subscription: $TOPIC_NAME"
    echo "• Vertex AI endpoints and datasets"
    echo "• Cloud Storage bucket: $BUCKET_NAME"
    echo "• Custom monitoring metrics"
    echo "• Generated code and data files"
    echo
    echo -e "${RED}THIS ACTION CANNOT BE UNDONE!${NC}"
    echo "======================================"
    echo

    read -p "Are you sure you want to proceed? (type 'yes' to confirm): " confirmation
    if [[ "$confirmation" != "yes" ]]; then
        log_info "Cleanup cancelled by user"
        exit 0
    fi

    echo
    read -p "Last chance! Type 'DELETE' to confirm destruction: " final_confirmation
    if [[ "$final_confirmation" != "DELETE" ]]; then
        log_info "Cleanup cancelled by user"
        exit 0
    fi
}

# Stop and delete Dataflow jobs
cleanup_dataflow_jobs() {
    log_info "Cleaning up Dataflow jobs..."

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would list and cancel active Dataflow jobs"
        return 0
    fi

    # Get all Dataflow jobs (active and recent)
    local jobs
    jobs=$(gcloud dataflow jobs list --region="$REGION" \
        --status=active --format="value(id)" 2>/dev/null || echo "")

    if [[ -n "$jobs" ]]; then
        for job_id in $jobs; do
            log_info "Cancelling Dataflow job: $job_id"
            gcloud dataflow jobs cancel "$job_id" --region="$REGION" --quiet || true
            
            # Wait for job to stop
            log_info "Waiting for job $job_id to stop..."
            local timeout=0
            while [[ $timeout -lt 300 ]]; do  # 5 minute timeout
                local state
                state=$(gcloud dataflow jobs describe "$job_id" --region="$REGION" \
                    --format="value(currentState)" 2>/dev/null || echo "UNKNOWN")
                
                if [[ "$state" != "JOB_STATE_RUNNING" ]]; then
                    log_success "Job $job_id stopped (state: $state)"
                    break
                fi
                
                sleep 10
                timeout=$((timeout + 10))
            done
            
            if [[ $timeout -ge 300 ]]; then
                log_warning "Timeout waiting for job $job_id to stop"
            fi
        done
    else
        log_info "No active Dataflow jobs found"
    fi

    log_success "Dataflow jobs cleanup completed"
}

# Delete Vertex AI resources
cleanup_vertex_ai() {
    log_info "Cleaning up Vertex AI resources..."

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would delete Vertex AI endpoints and datasets"
        return 0
    fi

    # Delete endpoints
    local endpoints
    endpoints=$(gcloud ai endpoints list --region="$REGION" \
        --filter="displayName~fraud-detection-endpoint" \
        --format="value(name.split('/').slice(-1:))" 2>/dev/null || echo "")

    if [[ -n "$endpoints" ]]; then
        for endpoint in $endpoints; do
            log_info "Deleting Vertex AI endpoint: $endpoint"
            gcloud ai endpoints delete "$endpoint" --region="$REGION" --quiet || true
        done
    else
        log_info "No Vertex AI endpoints found to delete"
    fi

    # Delete datasets
    local datasets
    datasets=$(gcloud ai datasets list --region="$REGION" \
        --filter="displayName~fraud-detection-dataset" \
        --format="value(name.split('/').slice(-1:))" 2>/dev/null || echo "")

    if [[ -n "$datasets" ]]; then
        for dataset in $datasets; do
            log_info "Deleting Vertex AI dataset: $dataset"
            gcloud ai datasets delete "$dataset" --region="$REGION" --quiet || true
        done
    else
        log_info "No Vertex AI datasets found to delete"
    fi

    # Delete any training jobs or models (if they exist)
    local models
    models=$(gcloud ai models list --region="$REGION" \
        --filter="displayName~fraud-detection-model" \
        --format="value(name.split('/').slice(-1:))" 2>/dev/null || echo "")

    if [[ -n "$models" ]]; then
        for model in $models; do
            log_info "Deleting Vertex AI model: $model"
            gcloud ai models delete "$model" --region="$REGION" --quiet || true
        done
    else
        log_info "No Vertex AI models found to delete"
    fi

    log_success "Vertex AI resources cleanup completed"
}

# Delete BigQuery resources
cleanup_bigquery() {
    log_info "Cleaning up BigQuery resources..."

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would delete BigQuery dataset: $DATASET_ID"
        return 0
    fi

    # Check if dataset exists
    if bq ls "$PROJECT_ID:$DATASET_ID" &>/dev/null; then
        log_info "Deleting BigQuery dataset: $DATASET_ID"
        bq rm -r -f "$PROJECT_ID:$DATASET_ID" || true
        
        # Verify deletion
        if ! bq ls "$PROJECT_ID:$DATASET_ID" &>/dev/null; then
            log_success "BigQuery dataset $DATASET_ID deleted successfully"
        else
            log_warning "BigQuery dataset $DATASET_ID may not have been fully deleted"
        fi
    else
        log_info "BigQuery dataset $DATASET_ID not found or already deleted"
    fi

    log_success "BigQuery resources cleanup completed"
}

# Delete Pub/Sub resources
cleanup_pubsub() {
    log_info "Cleaning up Pub/Sub resources..."

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would delete Pub/Sub topic: $TOPIC_NAME and subscription: $SUBSCRIPTION_NAME"
        return 0
    fi

    # Delete subscription first
    if gcloud pubsub subscriptions describe "$SUBSCRIPTION_NAME" &>/dev/null; then
        log_info "Deleting Pub/Sub subscription: $SUBSCRIPTION_NAME"
        gcloud pubsub subscriptions delete "$SUBSCRIPTION_NAME" --quiet || true
    else
        log_info "Pub/Sub subscription $SUBSCRIPTION_NAME not found"
    fi

    # Delete topic
    if gcloud pubsub topics describe "$TOPIC_NAME" &>/dev/null; then
        log_info "Deleting Pub/Sub topic: $TOPIC_NAME"
        gcloud pubsub topics delete "$TOPIC_NAME" --quiet || true
    else
        log_info "Pub/Sub topic $TOPIC_NAME not found"
    fi

    log_success "Pub/Sub resources cleanup completed"
}

# Delete Cloud Storage bucket
cleanup_storage() {
    log_info "Cleaning up Cloud Storage resources..."

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would delete Cloud Storage bucket: gs://$BUCKET_NAME"
        return 0
    fi

    # Check if bucket exists
    if gsutil ls -b "gs://$BUCKET_NAME" &>/dev/null; then
        log_info "Deleting Cloud Storage bucket: gs://$BUCKET_NAME"
        
        # Delete all objects first (including versions)
        log_info "Removing all objects from bucket..."
        gsutil -m rm -r "gs://$BUCKET_NAME/**" 2>/dev/null || true
        
        # Delete bucket
        gsutil rb "gs://$BUCKET_NAME" || true
        
        # Verify deletion
        if ! gsutil ls -b "gs://$BUCKET_NAME" &>/dev/null; then
            log_success "Cloud Storage bucket $BUCKET_NAME deleted successfully"
        else
            log_warning "Cloud Storage bucket $BUCKET_NAME may not have been fully deleted"
        fi
    else
        log_info "Cloud Storage bucket gs://$BUCKET_NAME not found"
    fi

    log_success "Cloud Storage resources cleanup completed"
}

# Delete monitoring resources
cleanup_monitoring() {
    log_info "Cleaning up monitoring resources..."

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would delete custom log-based metrics"
        return 0
    fi

    # Delete custom log-based metrics
    local metrics=("fraud_detection_rate" "transaction_processing_rate")
    
    for metric in "${metrics[@]}"; do
        if gcloud logging metrics describe "$metric" &>/dev/null; then
            log_info "Deleting log-based metric: $metric"
            gcloud logging metrics delete "$metric" --quiet || true
        else
            log_info "Log-based metric $metric not found"
        fi
    done

    # Note: We don't delete alert policies as they might be shared
    log_info "Note: Alert policies are not deleted to avoid affecting other resources"

    log_success "Monitoring resources cleanup completed"
}

# Clean up local files
cleanup_local_files() {
    log_info "Cleaning up local generated files..."

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would delete local training data and pipeline code"
        return 0
    fi

    local files_to_delete=(
        "${SCRIPT_DIR}/../training_data/"
        "${SCRIPT_DIR}/../dataflow_pipeline/"
        "${SCRIPT_DIR}/../transaction_simulator.py"
        "${SCRIPT_DIR}/deploy.log"
        "${SCRIPT_DIR}/destroy.log"
    )

    for file_path in "${files_to_delete[@]}"; do
        if [[ -e "$file_path" ]]; then
            log_info "Removing: $file_path"
            rm -rf "$file_path" || true
        fi
    done

    log_success "Local files cleanup completed"
}

# Partial cleanup with user selection
perform_partial_cleanup() {
    log_info "Starting partial cleanup - you can choose which resources to delete"
    
    local options=(
        "Dataflow jobs"
        "Vertex AI resources" 
        "BigQuery dataset"
        "Pub/Sub resources"
        "Cloud Storage bucket"
        "Monitoring resources"
        "Local files"
        "All resources"
        "Cancel"
    )
    
    echo "Select resources to delete:"
    select opt in "${options[@]}"; do
        case $opt in
            "Dataflow jobs")
                cleanup_dataflow_jobs
                ;;
            "Vertex AI resources")
                cleanup_vertex_ai
                ;;
            "BigQuery dataset")
                cleanup_bigquery
                ;;
            "Pub/Sub resources")
                cleanup_pubsub
                ;;
            "Cloud Storage bucket")
                cleanup_storage
                ;;
            "Monitoring resources")
                cleanup_monitoring
                ;;
            "Local files")
                cleanup_local_files
                ;;
            "All resources")
                perform_full_cleanup
                return
                ;;
            "Cancel")
                log_info "Cleanup cancelled by user"
                exit 0
                ;;
            *)
                echo "Invalid option. Please try again."
                ;;
        esac
        echo "Select another resource to delete (or Cancel to finish):"
    done
}

# Full cleanup
perform_full_cleanup() {
    log_info "Performing full cleanup of all fraud detection resources..."
    
    cleanup_dataflow_jobs
    cleanup_vertex_ai
    cleanup_bigquery
    cleanup_pubsub
    cleanup_storage
    cleanup_monitoring
    cleanup_local_files
}

# Offer to delete project
offer_project_deletion() {
    if [[ "$KEEP_PROJECT" == "true" ]] || [[ "$DRY_RUN" == "true" ]]; then
        return 0
    fi

    echo
    echo "======================================"
    echo "       PROJECT DELETION OPTION"
    echo "======================================"
    echo "Would you like to delete the entire project?"
    echo "Project: $PROJECT_ID"
    echo
    echo -e "${RED}WARNING: This will delete ALL resources in the project!${NC}"
    echo "======================================"
    echo

    read -p "Delete entire project? (y/N): " delete_project
    if [[ "$delete_project" =~ ^[Yy]$ ]]; then
        echo
        read -p "Type the project ID to confirm deletion: " confirm_project
        
        if [[ "$confirm_project" == "$PROJECT_ID" ]]; then
            log_info "Deleting project: $PROJECT_ID"
            gcloud projects delete "$PROJECT_ID" --quiet || true
            log_success "Project deletion initiated"
        else
            log_info "Project ID mismatch. Project deletion cancelled."
        fi
    else
        log_info "Project deletion declined"
    fi
}

# Update deployment state
update_cleanup_state() {
    if [[ "$DRY_RUN" == "false" ]] && [[ -f "$DEPLOYMENT_STATE_FILE" ]]; then
        echo "CLEANUP_COMPLETED=$(date '+%Y-%m-%d %H:%M:%S')" >> "${DEPLOYMENT_STATE_FILE}"
        echo "CLEANUP_STATUS=COMPLETED" >> "${DEPLOYMENT_STATE_FILE}"
    fi
}

# Print cleanup summary
print_cleanup_summary() {
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "DRY-RUN completed - no resources were actually deleted"
    else
        log_success "Fraud Detection System Cleanup Completed!"
    fi
    
    echo
    echo "======================================"
    echo "        CLEANUP SUMMARY"
    echo "======================================"
    echo "Project ID: $PROJECT_ID"
    echo "Region: $REGION"
    echo
    
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "Resources that would be deleted:"
    else
        echo "Resources cleaned up:"
    fi
    
    echo "• Dataflow jobs (fraud detection pipeline)"
    echo "• Vertex AI endpoints and datasets"
    echo "• BigQuery dataset: $DATASET_ID"
    echo "• Pub/Sub topic: $TOPIC_NAME"
    echo "• Pub/Sub subscription: $SUBSCRIPTION_NAME"
    echo "• Cloud Storage bucket: gs://$BUCKET_NAME"
    echo "• Custom monitoring metrics"
    echo "• Local generated files"
    echo
    
    if [[ "$DRY_RUN" == "false" ]]; then
        echo "💰 All billable resources have been removed"
        echo "📊 Check Cloud Billing console to verify cost savings"
    fi
    
    echo "Cleanup logs: $LOG_FILE"
    echo "======================================"
}

# Main cleanup function
main() {
    log_info "Starting fraud detection system cleanup..."
    log_info "Logs are being written to: $LOG_FILE"

    parse_arguments "$@"
    load_deployment_state
    check_prerequisites

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "Running in DRY-RUN mode - no resources will be deleted"
    fi

    if [[ "$PARTIAL_CLEANUP" == "true" ]]; then
        perform_partial_cleanup
    else
        confirm_destruction
        perform_full_cleanup
        offer_project_deletion
    fi

    if [[ "$DRY_RUN" == "false" ]]; then
        update_cleanup_state
    fi

    print_cleanup_summary
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "Dry-run completed successfully!"
    else
        log_success "Cleanup completed successfully!"
    fi
}

# Execute main function with all arguments
main "$@"