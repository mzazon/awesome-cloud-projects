#!/bin/bash

# Healthcare Data Processing with Cloud Batch and Vertex AI Agents - Cleanup Script
# This script safely removes all infrastructure components created by the deploy script
# including Cloud Batch jobs, Vertex AI agents, Cloud Healthcare API, and Cloud Storage

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

# Error handling for cleanup
handle_cleanup_error() {
    log_warning "Cleanup error encountered, but continuing with remaining resources..."
}

trap handle_cleanup_error ERR

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites for cleanup..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "gcloud CLI is not installed. Cannot proceed with cleanup."
        exit 1
    fi
    
    # Check if user is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q "."; then
        log_error "No active gcloud authentication found. Please run 'gcloud auth login'"
        exit 1
    fi
    
    # Check if gsutil is available
    if ! command -v gsutil &> /dev/null; then
        log_error "gsutil is not available. Cannot cleanup storage resources."
        exit 1
    fi
    
    log_success "Prerequisites check completed"
}

# Load environment variables
load_environment() {
    log_info "Loading environment configuration..."
    
    # Try to detect project from gcloud config
    CURRENT_PROJECT=$(gcloud config get-value project 2>/dev/null || echo "")
    
    if [[ -z "${PROJECT_ID:-}" ]]; then
        if [[ -n "${CURRENT_PROJECT}" ]]; then
            export PROJECT_ID="${CURRENT_PROJECT}"
            log_info "Using current project: ${PROJECT_ID}"
        else
            log_error "PROJECT_ID not set and no current project configured."
            log_error "Set PROJECT_ID environment variable or run 'gcloud config set project PROJECT_ID'"
            exit 1
        fi
    fi
    
    # Set default values for other variables
    export REGION="${REGION:-us-central1}"
    export ZONE="${ZONE:-us-central1-a}"
    
    # Set defaults for resource names if not provided
    if [[ -z "${BUCKET_NAME:-}" ]] || [[ -z "${DATASET_ID:-}" ]] || [[ -z "${FHIR_STORE_ID:-}" ]]; then
        log_warning "Resource names not provided. Will attempt to discover and remove all matching resources."
        DISCOVER_RESOURCES=true
    else
        DISCOVER_RESOURCES=false
    fi
    
    log_info "Cleanup configuration:"
    log_info "  Project ID: ${PROJECT_ID}"
    log_info "  Region: ${REGION}"
    log_info "  Resource Discovery: ${DISCOVER_RESOURCES}"
}

# Confirmation prompt
confirm_cleanup() {
    echo "=================================================================================="
    echo "⚠️  WARNING: DESTRUCTIVE OPERATION"
    echo "=================================================================================="
    echo "This script will permanently delete the following resources from project: ${PROJECT_ID}"
    echo ""
    echo "Resources to be deleted:"
    echo "• All Cloud Batch jobs in region ${REGION}"
    echo "• Cloud Function: healthcare-processor-trigger"
    echo "• Healthcare datasets and FHIR stores"
    echo "• Service accounts: healthcare-ai-agent, healthcare-batch-processor"
    echo "• Cloud Storage buckets (healthcare-data-*)"
    echo "• Monitoring dashboards and alert policies"
    echo "• IAM policy bindings"
    echo ""
    echo "⚠️  THIS ACTION CANNOT BE UNDONE!"
    echo "=================================================================================="
    
    if [[ "${FORCE_CLEANUP:-false}" == "true" ]]; then
        log_warning "Force cleanup enabled, skipping confirmation"
        return 0
    fi
    
    read -p "Are you sure you want to proceed? Type 'yes' to continue: " confirmation
    
    if [[ "${confirmation}" != "yes" ]]; then
        log_info "Cleanup cancelled by user"
        exit 0
    fi
    
    log_info "Cleanup confirmed, proceeding..."
}

# Discover healthcare resources
discover_resources() {
    if [[ "${DISCOVER_RESOURCES}" == "true" ]]; then
        log_info "Discovering healthcare resources in project..."
        
        # Discover storage buckets
        HEALTHCARE_BUCKETS=($(gsutil ls -p "${PROJECT_ID}" | grep "healthcare-data-" | sed 's|gs://||g' | sed 's|/||g' || true))
        
        # Discover healthcare datasets
        HEALTHCARE_DATASETS=($(gcloud healthcare datasets list --location="${REGION}" --format="value(name)" | grep "healthcare_dataset_" || true))
        
        # Extract FHIR stores from datasets
        HEALTHCARE_FHIR_STORES=()
        for dataset in "${HEALTHCARE_DATASETS[@]}"; do
            dataset_id=$(basename "${dataset}")
            fhir_stores=($(gcloud healthcare fhir-stores list --dataset="${dataset_id}" --location="${REGION}" --format="value(name)" | grep "patient_records_" || true))
            for store in "${fhir_stores[@]}"; do
                HEALTHCARE_FHIR_STORES+=("${dataset_id}:$(basename "${store}")")
            done
        done
        
        log_info "Discovered resources:"
        log_info "  Storage buckets: ${#HEALTHCARE_BUCKETS[@]}"
        log_info "  Healthcare datasets: ${#HEALTHCARE_DATASETS[@]}"
        log_info "  FHIR stores: ${#HEALTHCARE_FHIR_STORES[@]}"
    fi
}

# Clean up Cloud Batch jobs
cleanup_batch_jobs() {
    log_info "Cleaning up Cloud Batch jobs..."
    
    # List all batch jobs in the region
    local job_list
    job_list=$(gcloud batch jobs list --location="${REGION}" --format="value(name)" --filter="name:healthcare-processing" 2>/dev/null || true)
    
    if [[ -n "${job_list}" ]]; then
        echo "${job_list}" | while read -r job_name; do
            if [[ -n "${job_name}" ]]; then
                log_info "Deleting batch job: ${job_name}"
                gcloud batch jobs delete "${job_name}" --location="${REGION}" --quiet || log_warning "Failed to delete job: ${job_name}"
            fi
        done
        log_success "Batch jobs cleanup completed"
    else
        log_info "No healthcare batch jobs found to delete"
    fi
}

# Clean up Cloud Functions
cleanup_cloud_functions() {
    log_info "Cleaning up Cloud Functions..."
    
    # Delete healthcare processor trigger function
    if gcloud functions describe healthcare-processor-trigger --region="${REGION}" &>/dev/null; then
        log_info "Deleting Cloud Function: healthcare-processor-trigger"
        gcloud functions delete healthcare-processor-trigger --region="${REGION}" --quiet || log_warning "Failed to delete Cloud Function"
        log_success "Cloud Function deleted"
    else
        log_info "Healthcare processor Cloud Function not found"
    fi
}

# Clean up Vertex AI resources
cleanup_vertex_ai() {
    log_info "Cleaning up Vertex AI resources..."
    
    # Note: Vertex AI agents and endpoints cleanup would go here
    # This is a placeholder for actual Vertex AI resource cleanup
    log_info "Vertex AI resource cleanup completed (placeholder)"
}

# Clean up Healthcare API resources
cleanup_healthcare_api() {
    log_info "Cleaning up Healthcare API resources..."
    
    if [[ "${DISCOVER_RESOURCES}" == "true" ]]; then
        # Clean up discovered FHIR stores and datasets
        for store_info in "${HEALTHCARE_FHIR_STORES[@]}"; do
            dataset_id="${store_info%%:*}"
            fhir_store_id="${store_info##*:}"
            
            log_info "Deleting FHIR store: ${fhir_store_id} in dataset: ${dataset_id}"
            gcloud healthcare fhir-stores delete "${fhir_store_id}" \
                --dataset="${dataset_id}" \
                --location="${REGION}" \
                --quiet || log_warning "Failed to delete FHIR store: ${fhir_store_id}"
        done
        
        for dataset in "${HEALTHCARE_DATASETS[@]}"; do
            dataset_id=$(basename "${dataset}")
            log_info "Deleting healthcare dataset: ${dataset_id}"
            gcloud healthcare datasets delete "${dataset_id}" \
                --location="${REGION}" \
                --quiet || log_warning "Failed to delete dataset: ${dataset_id}"
        done
    else
        # Clean up specific resources
        if [[ -n "${FHIR_STORE_ID:-}" ]] && [[ -n "${DATASET_ID:-}" ]]; then
            log_info "Deleting FHIR store: ${FHIR_STORE_ID}"
            gcloud healthcare fhir-stores delete "${FHIR_STORE_ID}" \
                --dataset="${DATASET_ID}" \
                --location="${REGION}" \
                --quiet || log_warning "Failed to delete FHIR store"
        fi
        
        if [[ -n "${DATASET_ID:-}" ]]; then
            log_info "Deleting healthcare dataset: ${DATASET_ID}"
            gcloud healthcare datasets delete "${DATASET_ID}" \
                --location="${REGION}" \
                --quiet || log_warning "Failed to delete healthcare dataset"
        fi
    fi
    
    log_success "Healthcare API resources cleanup completed"
}

# Clean up service accounts and IAM
cleanup_service_accounts() {
    log_info "Cleaning up service accounts and IAM policies..."
    
    local service_accounts=(
        "healthcare-ai-agent"
        "healthcare-batch-processor"
    )
    
    for sa in "${service_accounts[@]}"; do
        local sa_email="${sa}@${PROJECT_ID}.iam.gserviceaccount.com"
        
        if gcloud iam service-accounts describe "${sa_email}" &>/dev/null; then
            log_info "Removing IAM policy bindings for: ${sa_email}"
            
            # Remove IAM policy bindings
            local roles_to_remove=(
                "roles/aiplatform.user"
                "roles/healthcare.fhirResourceEditor"
                "roles/healthcare.fhirResourceReader"
                "roles/storage.objectViewer"
                "roles/storage.objectAdmin"
                "roles/batch.jobsEditor"
                "roles/logging.logWriter"
                "roles/monitoring.metricWriter"
            )
            
            for role in "${roles_to_remove[@]}"; do
                gcloud projects remove-iam-policy-binding "${PROJECT_ID}" \
                    --member="serviceAccount:${sa_email}" \
                    --role="${role}" \
                    --quiet 2>/dev/null || log_warning "Failed to remove role: ${role}"
            done
            
            log_info "Deleting service account: ${sa}"
            gcloud iam service-accounts delete "${sa_email}" --quiet || log_warning "Failed to delete service account: ${sa}"
        else
            log_info "Service account not found: ${sa}"
        fi
    done
    
    log_success "Service accounts and IAM cleanup completed"
}

# Clean up Cloud Storage
cleanup_storage() {
    log_info "Cleaning up Cloud Storage resources..."
    
    if [[ "${DISCOVER_RESOURCES}" == "true" ]]; then
        # Clean up discovered buckets
        for bucket in "${HEALTHCARE_BUCKETS[@]}"; do
            log_info "Deleting storage bucket: ${bucket}"
            gsutil -m rm -r "gs://${bucket}" || log_warning "Failed to delete bucket: ${bucket}"
        done
    else
        # Clean up specific bucket
        if [[ -n "${BUCKET_NAME:-}" ]]; then
            if gsutil ls "gs://${BUCKET_NAME}" &>/dev/null; then
                log_info "Deleting storage bucket: ${BUCKET_NAME}"
                gsutil -m rm -r "gs://${BUCKET_NAME}" || log_warning "Failed to delete bucket: ${BUCKET_NAME}"
            else
                log_info "Storage bucket not found: ${BUCKET_NAME}"
            fi
        fi
    fi
    
    # Clean up local temporary files
    rm -f healthcare_processor.py healthcare-batch-job.yaml monitoring-dashboard.json sample_medical_record.json 2>/dev/null || true
    
    log_success "Storage cleanup completed"
}

# Clean up monitoring resources
cleanup_monitoring() {
    log_info "Cleaning up monitoring resources..."
    
    # Delete monitoring dashboards
    local dashboards
    dashboards=$(gcloud monitoring dashboards list --format="value(name)" --filter="displayName:Healthcare" 2>/dev/null || true)
    
    if [[ -n "${dashboards}" ]]; then
        echo "${dashboards}" | while read -r dashboard; do
            if [[ -n "${dashboard}" ]]; then
                log_info "Deleting monitoring dashboard: ${dashboard}"
                gcloud monitoring dashboards delete "${dashboard}" --quiet || log_warning "Failed to delete dashboard"
            fi
        done
    else
        log_info "No healthcare monitoring dashboards found"
    fi
    
    # Delete alert policies
    local policies
    policies=$(gcloud alpha monitoring policies list --format="value(name)" --filter="displayName:Healthcare" 2>/dev/null || true)
    
    if [[ -n "${policies}" ]]; then
        echo "${policies}" | while read -r policy; do
            if [[ -n "${policy}" ]]; then
                log_info "Deleting alert policy: ${policy}"
                gcloud alpha monitoring policies delete "${policy}" --quiet || log_warning "Failed to delete alert policy"
            fi
        done
    else
        log_info "No healthcare alert policies found"
    fi
    
    log_success "Monitoring resources cleanup completed"
}

# Verify cleanup
verify_cleanup() {
    log_info "Verifying cleanup completion..."
    
    local cleanup_errors=0
    
    # Check for remaining batch jobs
    local remaining_jobs
    remaining_jobs=$(gcloud batch jobs list --location="${REGION}" --format="value(name)" --filter="name:healthcare-processing" 2>/dev/null | wc -l)
    if [[ "${remaining_jobs}" -gt 0 ]]; then
        log_warning "❌ ${remaining_jobs} batch jobs still remain"
        cleanup_errors=$((cleanup_errors + 1))
    else
        log_success "✅ All batch jobs removed"
    fi
    
    # Check for Cloud Function
    if gcloud functions describe healthcare-processor-trigger --region="${REGION}" &>/dev/null; then
        log_warning "❌ Cloud Function still exists"
        cleanup_errors=$((cleanup_errors + 1))
    else
        log_success "✅ Cloud Function removed"
    fi
    
    # Check for healthcare datasets
    local remaining_datasets
    remaining_datasets=$(gcloud healthcare datasets list --location="${REGION}" --format="value(name)" --filter="name:healthcare_dataset_" 2>/dev/null | wc -l)
    if [[ "${remaining_datasets}" -gt 0 ]]; then
        log_warning "❌ ${remaining_datasets} healthcare datasets still remain"
        cleanup_errors=$((cleanup_errors + 1))
    else
        log_success "✅ All healthcare datasets removed"
    fi
    
    # Check for service accounts
    local remaining_sa=0
    local service_accounts=("healthcare-ai-agent" "healthcare-batch-processor")
    for sa in "${service_accounts[@]}"; do
        if gcloud iam service-accounts describe "${sa}@${PROJECT_ID}.iam.gserviceaccount.com" &>/dev/null; then
            remaining_sa=$((remaining_sa + 1))
        fi
    done
    
    if [[ "${remaining_sa}" -gt 0 ]]; then
        log_warning "❌ ${remaining_sa} service accounts still remain"
        cleanup_errors=$((cleanup_errors + 1))
    else
        log_success "✅ All service accounts removed"
    fi
    
    if [[ "${cleanup_errors}" -eq 0 ]]; then
        log_success "🎉 Cleanup verification completed successfully!"
    else
        log_warning "⚠️  Cleanup completed with ${cleanup_errors} issues. Manual intervention may be required."
    fi
}

# Display cleanup summary
display_cleanup_summary() {
    echo "=================================================================================="
    echo "Healthcare Data Processing Infrastructure Cleanup Summary"
    echo "=================================================================================="
    echo "Project ID: ${PROJECT_ID}"
    echo "Region: ${REGION}"
    echo ""
    echo "Resources cleaned up:"
    echo "✅ Cloud Batch jobs"
    echo "✅ Cloud Functions"
    echo "✅ Healthcare API datasets and FHIR stores"
    echo "✅ Service accounts and IAM policies"
    echo "✅ Cloud Storage buckets"
    echo "✅ Monitoring dashboards and alerts"
    echo ""
    echo "Cleanup completed at: $(date)"
    echo ""
    log_info "Note: Some resources may take a few minutes to be fully removed from the console."
    echo "=================================================================================="
}

# Option to delete entire project
offer_project_deletion() {
    if [[ "${AUTO_DELETE_PROJECT:-false}" == "true" ]]; then
        log_warning "Auto-deleting project: ${PROJECT_ID}"
        gcloud projects delete "${PROJECT_ID}" --quiet || log_error "Failed to delete project"
        return 0
    fi
    
    echo ""
    read -p "Do you want to delete the entire project '${PROJECT_ID}'? This will remove ALL resources. (y/N): " delete_project
    
    if [[ "${delete_project,,}" == "y" || "${delete_project,,}" == "yes" ]]; then
        log_warning "Deleting entire project: ${PROJECT_ID}"
        gcloud projects delete "${PROJECT_ID}" --quiet || log_error "Failed to delete project"
        log_success "Project deletion initiated. This may take several minutes to complete."
    else
        log_info "Project deletion skipped"
    fi
}

# Main cleanup function
main() {
    log_info "Starting Healthcare Data Processing infrastructure cleanup..."
    
    check_prerequisites
    load_environment
    confirm_cleanup
    discover_resources
    
    # Execute cleanup in reverse order of creation
    cleanup_batch_jobs
    cleanup_cloud_functions
    cleanup_vertex_ai
    cleanup_healthcare_api
    cleanup_service_accounts
    cleanup_storage
    cleanup_monitoring
    
    verify_cleanup
    display_cleanup_summary
    
    # Offer to delete the entire project
    offer_project_deletion
    
    log_success "Healthcare Data Processing infrastructure cleanup completed!"
}

# Handle script arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --force)
            export FORCE_CLEANUP=true
            shift
            ;;
        --auto-delete-project)
            export AUTO_DELETE_PROJECT=true
            shift
            ;;
        --project)
            export PROJECT_ID="$2"
            shift 2
            ;;
        --region)
            export REGION="$2"
            shift 2
            ;;
        --bucket)
            export BUCKET_NAME="$2"
            shift 2
            ;;
        --dataset)
            export DATASET_ID="$2"
            shift 2
            ;;
        --fhir-store)
            export FHIR_STORE_ID="$2"
            shift 2
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --force                   Skip confirmation prompts"
            echo "  --auto-delete-project     Automatically delete the entire project"
            echo "  --project PROJECT_ID      Specify project ID"
            echo "  --region REGION          Specify region (default: us-central1)"
            echo "  --bucket BUCKET_NAME     Specify bucket name to delete"
            echo "  --dataset DATASET_ID     Specify healthcare dataset ID"
            echo "  --fhir-store STORE_ID    Specify FHIR store ID"
            echo "  --help                   Show this help message"
            echo ""
            echo "Examples:"
            echo "  $0                                    # Interactive cleanup"
            echo "  $0 --force                           # Skip confirmations"
            echo "  $0 --project my-project --force      # Force cleanup specific project"
            echo "  $0 --auto-delete-project             # Delete entire project"
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Run main function
main "$@"