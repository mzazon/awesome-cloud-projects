#!/bin/bash

# Large-Scale ML Training Pipeline Cleanup Script
# Destroys Cloud TPU v6e and Dataproc Serverless infrastructure
# Recipe: large-scale-ml-training-pipelines-tpu-v6e-dataproc-serverless

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

# Function to load environment variables
load_environment() {
    log_info "Loading environment variables..."
    
    if [[ -f .env ]]; then
        # Source the environment file
        source .env
        log_info "Environment loaded from .env file"
    else
        log_warning ".env file not found. Attempting to detect resources..."
        
        # Try to get project from gcloud config
        if ! PROJECT_ID=$(gcloud config get-value project 2>/dev/null); then
            log_error "Could not determine project ID. Please set PROJECT_ID manually."
            exit 1
        fi
        
        # Set default values
        REGION="us-central2"
        ZONE="us-central2-b"
        
        log_warning "Using default region/zone. Some resources may not be found."
    fi
    
    # Validate required variables
    if [[ -z "${PROJECT_ID:-}" ]]; then
        log_error "PROJECT_ID is not set"
        exit 1
    fi
    
    log_info "Project ID: ${PROJECT_ID}"
    log_info "Region: ${REGION:-unknown}"
    log_info "Zone: ${ZONE:-unknown}"
}

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking cleanup prerequisites..."
    
    # Check if gcloud CLI is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "gcloud CLI is not installed"
        exit 1
    fi
    
    # Check if authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 &> /dev/null; then
        log_error "Not authenticated with Google Cloud. Run 'gcloud auth login'"
        exit 1
    fi
    
    # Check gsutil availability
    if ! command -v gsutil &> /dev/null; then
        log_error "gsutil is not available"
        exit 1
    fi
    
    log_success "Prerequisites check passed"
}

# Function to confirm destruction
confirm_destruction() {
    echo ""
    log_warning "This will permanently delete the following resources:"
    echo "  - TPU v6e instances (${TPU_NAME:-'detected TPUs'})"
    echo "  - Dataproc Serverless batches (${DATAPROC_BATCH_ID:-'all batches'})"
    echo "  - Cloud Storage bucket and all data (${BUCKET_NAME:-'detected buckets'})"
    echo "  - Monitoring dashboards"
    echo ""
    
    # Option to skip confirmation in automated environments
    if [[ "${SKIP_CONFIRMATION:-false}" == "true" ]]; then
        log_warning "Skipping confirmation due to SKIP_CONFIRMATION=true"
        return 0
    fi
    
    read -p "Are you sure you want to proceed? (type 'yes' to confirm): " confirmation
    
    if [[ "${confirmation}" != "yes" ]]; then
        log_info "Cleanup cancelled by user"
        exit 0
    fi
    
    log_info "Proceeding with cleanup..."
}

# Function to terminate TPU training processes
terminate_training() {
    log_info "Terminating any running training processes..."
    
    if [[ -n "${TPU_NAME:-}" && -n "${ZONE:-}" ]]; then
        # Try to terminate training processes on TPU
        gcloud compute tpus tpu-vm ssh "${TPU_NAME}" \
            --zone="${ZONE}" \
            --command="pkill -f python || true; pkill -f training || true" \
            --quiet 2>/dev/null || log_warning "Could not connect to TPU ${TPU_NAME}"
    else
        # Find and terminate training on all TPUs in the project
        log_info "Searching for TPU instances in project..."
        local tpu_instances=$(gcloud compute tpus tpu-vm list \
            --format="value(name,zone)" \
            --filter="labels.recipe=tpu-v6e-pipeline OR name~'training-tpu'" 2>/dev/null || true)
        
        if [[ -n "${tpu_instances}" ]]; then
            while IFS=$'\t' read -r tpu_name tpu_zone; do
                if [[ -n "${tpu_name}" && -n "${tpu_zone}" ]]; then
                    log_info "Terminating processes on TPU ${tpu_name} in ${tpu_zone}"
                    gcloud compute tpus tpu-vm ssh "${tpu_name}" \
                        --zone="${tpu_zone}" \
                        --command="pkill -f python || true; pkill -f training || true" \
                        --quiet 2>/dev/null || true
                fi
            done <<< "${tpu_instances}"
        fi
    fi
    
    log_success "Training processes terminated"
}

# Function to cancel Dataproc batches
cancel_dataproc_batches() {
    log_info "Cancelling Dataproc Serverless batches..."
    
    local region="${REGION:-us-central2}"
    
    if [[ -n "${DATAPROC_BATCH_ID:-}" ]]; then
        # Cancel specific batch
        log_info "Cancelling batch: ${DATAPROC_BATCH_ID}"
        if gcloud dataproc batches cancel "${DATAPROC_BATCH_ID}" \
            --region="${region}" --quiet 2>/dev/null; then
            log_success "Cancelled batch: ${DATAPROC_BATCH_ID}"
        else
            log_warning "Could not cancel batch ${DATAPROC_BATCH_ID} (may not exist or already completed)"
        fi
    else
        # Find and cancel all preprocessing batches
        log_info "Searching for preprocessing batches..."
        local batch_ids=$(gcloud dataproc batches list \
            --region="${region}" \
            --format="value(batchId)" \
            --filter="labels.recipe=tpu-v6e-pipeline OR batchId~'preprocessing'" 2>/dev/null || true)
        
        if [[ -n "${batch_ids}" ]]; then
            while read -r batch_id; do
                if [[ -n "${batch_id}" ]]; then
                    log_info "Cancelling batch: ${batch_id}"
                    gcloud dataproc batches cancel "${batch_id}" \
                        --region="${region}" --quiet 2>/dev/null || true
                fi
            done <<< "${batch_ids}"
        fi
    fi
    
    # Wait a moment for cancellation to take effect
    sleep 10
    
    log_success "Dataproc batch cancellation completed"
}

# Function to delete TPU instances
delete_tpu_instances() {
    log_info "Deleting TPU v6e instances..."
    
    if [[ -n "${TPU_NAME:-}" && -n "${ZONE:-}" ]]; then
        # Delete specific TPU instance
        log_info "Deleting TPU: ${TPU_NAME}"
        if gcloud compute tpus tpu-vm delete "${TPU_NAME}" \
            --zone="${ZONE}" --quiet 2>/dev/null; then
            log_success "Deleted TPU: ${TPU_NAME}"
        else
            log_warning "Could not delete TPU ${TPU_NAME} (may not exist)"
        fi
    else
        # Find and delete all training TPUs
        log_info "Searching for TPU instances to delete..."
        local tpu_list=$(gcloud compute tpus tpu-vm list \
            --format="value(name,zone)" \
            --filter="labels.recipe=tpu-v6e-pipeline OR name~'training-tpu'" 2>/dev/null || true)
        
        if [[ -n "${tpu_list}" ]]; then
            while IFS=$'\t' read -r tpu_name tpu_zone; do
                if [[ -n "${tpu_name}" && -n "${tpu_zone}" ]]; then
                    log_info "Deleting TPU: ${tpu_name} in zone ${tpu_zone}"
                    gcloud compute tpus tpu-vm delete "${tpu_name}" \
                        --zone="${tpu_zone}" --quiet 2>/dev/null || true
                fi
            done <<< "${tpu_list}"
            log_success "All TPU instances deleted"
        else
            log_info "No TPU instances found to delete"
        fi
    fi
}

# Function to delete storage buckets
delete_storage() {
    log_info "Deleting Cloud Storage resources..."
    
    if [[ -n "${BUCKET_NAME:-}" ]]; then
        # Delete specific bucket
        log_info "Deleting bucket: gs://${BUCKET_NAME}"
        if gsutil ls "gs://${BUCKET_NAME}" &> /dev/null; then
            # Delete all objects first, then the bucket
            gsutil -m rm -r "gs://${BUCKET_NAME}" 2>/dev/null || {
                log_warning "Standard deletion failed, attempting force deletion..."
                gsutil -m rm -r -f "gs://${BUCKET_NAME}" 2>/dev/null || true
            }
            log_success "Deleted bucket: gs://${BUCKET_NAME}"
        else
            log_warning "Bucket gs://${BUCKET_NAME} does not exist"
        fi
    else
        # Find and delete training pipeline buckets
        log_info "Searching for training pipeline storage buckets..."
        local bucket_list=$(gsutil ls | grep -E "(ml-training-pipeline|training-tpu)" || true)
        
        if [[ -n "${bucket_list}" ]]; then
            while read -r bucket_url; do
                if [[ -n "${bucket_url}" ]]; then
                    log_info "Deleting bucket: ${bucket_url}"
                    gsutil -m rm -r "${bucket_url}" 2>/dev/null || {
                        log_warning "Standard deletion failed for ${bucket_url}, attempting force deletion..."
                        gsutil -m rm -r -f "${bucket_url}" 2>/dev/null || true
                    }
                fi
            done <<< "${bucket_list}"
            log_success "All training pipeline buckets deleted"
        else
            log_info "No training pipeline buckets found"
        fi
    fi
}

# Function to delete monitoring resources
delete_monitoring() {
    log_info "Deleting monitoring resources..."
    
    # Delete TPU training dashboards
    local dashboard_list=$(gcloud monitoring dashboards list \
        --format="value(name)" \
        --filter="displayName:'TPU v6e Training Dashboard'" 2>/dev/null || true)
    
    if [[ -n "${dashboard_list}" ]]; then
        while read -r dashboard_id; do
            if [[ -n "${dashboard_id}" ]]; then
                log_info "Deleting dashboard: ${dashboard_id}"
                gcloud monitoring dashboards delete "${dashboard_id}" --quiet 2>/dev/null || true
            fi
        done <<< "${dashboard_list}"
        log_success "Monitoring dashboards deleted"
    else
        log_info "No monitoring dashboards found to delete"
    fi
    
    # Clean up any custom log sinks (optional)
    local log_sinks=$(gcloud logging sinks list \
        --format="value(name)" \
        --filter="name~'tpu-training'" 2>/dev/null || true)
    
    if [[ -n "${log_sinks}" ]]; then
        while read -r sink_name; do
            if [[ -n "${sink_name}" ]]; then
                log_info "Deleting log sink: ${sink_name}"
                gcloud logging sinks delete "${sink_name}" --quiet 2>/dev/null || true
            fi
        done <<< "${log_sinks}"
    fi
}

# Function to clean up local files
cleanup_local_files() {
    log_info "Cleaning up local files..."
    
    # Remove environment file
    if [[ -f .env ]]; then
        rm .env
        log_info "Removed .env file"
    fi
    
    # Remove any temporary files
    find /tmp -name "*tpu*" -type f -mtime -1 2>/dev/null | while read -r temp_file; do
        rm -f "${temp_file}" 2>/dev/null || true
    done
    
    # Remove any local training logs
    rm -f training.log preprocessing.log 2>/dev/null || true
    
    log_success "Local cleanup completed"
}

# Function to verify cleanup completion
verify_cleanup() {
    log_info "Verifying cleanup completion..."
    
    local cleanup_issues=()
    
    # Check for remaining TPU instances
    local remaining_tpus=$(gcloud compute tpus tpu-vm list \
        --format="value(name)" \
        --filter="labels.recipe=tpu-v6e-pipeline OR name~'training-tpu'" 2>/dev/null || true)
    
    if [[ -n "${remaining_tpus}" ]]; then
        cleanup_issues+=("TPU instances still exist: ${remaining_tpus}")
    fi
    
    # Check for remaining Dataproc batches
    local remaining_batches=$(gcloud dataproc batches list \
        --region="${REGION:-us-central2}" \
        --format="value(batchId)" \
        --filter="labels.recipe=tpu-v6e-pipeline OR batchId~'preprocessing'" 2>/dev/null || true)
    
    if [[ -n "${remaining_batches}" ]]; then
        cleanup_issues+=("Dataproc batches still exist: ${remaining_batches}")
    fi
    
    # Check for remaining buckets
    if [[ -n "${BUCKET_NAME:-}" ]]; then
        if gsutil ls "gs://${BUCKET_NAME}" &> /dev/null; then
            cleanup_issues+=("Storage bucket still exists: gs://${BUCKET_NAME}")
        fi
    fi
    
    # Report results
    if [[ ${#cleanup_issues[@]} -eq 0 ]]; then
        log_success "Cleanup verification passed - all resources removed"
    else
        log_warning "Some resources may still exist:"
        for issue in "${cleanup_issues[@]}"; do
            echo "  - ${issue}"
        done
        echo ""
        log_info "You may need to manually verify and clean up these resources"
    fi
}

# Function to display cleanup summary
display_cleanup_summary() {
    echo ""
    log_info "Cleanup Summary:"
    echo "=================================================="
    echo "Project: ${PROJECT_ID}"
    echo "Region: ${REGION:-unknown}"
    echo "Zone: ${ZONE:-unknown}"
    echo ""
    echo "Resources cleaned up:"
    echo "  ✓ TPU v6e instances terminated and deleted"
    echo "  ✓ Dataproc Serverless batches cancelled"
    echo "  ✓ Cloud Storage buckets and data removed"
    echo "  ✓ Monitoring dashboards deleted"
    echo "  ✓ Local files cleaned up"
    echo "=================================================="
    echo ""
    log_info "Cost Alert: Please verify in the Google Cloud Console that"
    log_info "all resources have been properly deleted to avoid ongoing charges."
    echo ""
}

# Main cleanup function
main() {
    echo "=============================================="
    echo "  ML Training Pipeline Cleanup Script"
    echo "  Recipe: TPU v6e + Dataproc Serverless"
    echo "=============================================="
    echo ""
    
    check_prerequisites
    load_environment
    confirm_destruction
    
    log_info "Starting cleanup process..."
    
    # Cleanup in reverse order of creation
    terminate_training
    cancel_dataproc_batches
    delete_tpu_instances
    delete_monitoring
    delete_storage
    cleanup_local_files
    
    log_success "Cleanup process completed!"
    
    verify_cleanup
    display_cleanup_summary
}

# Handle script arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --skip-confirmation)
            export SKIP_CONFIRMATION=true
            shift
            ;;
        --force)
            export SKIP_CONFIRMATION=true
            shift
            ;;
        --help)
            echo "Usage: $0 [options]"
            echo ""
            echo "Options:"
            echo "  --skip-confirmation    Skip confirmation prompt"
            echo "  --force                Same as --skip-confirmation"
            echo "  --help                 Show this help message"
            echo ""
            echo "Environment Variables:"
            echo "  SKIP_CONFIRMATION=true Skip confirmation prompt"
            echo ""
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Run main function
main "$@"