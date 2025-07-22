#!/bin/bash

# Scientific Video Analysis Workflows with Cluster Toolkit and Gemini Fine-tuning
# Cleanup/Destroy Script for GCP Infrastructure
# 
# This script safely removes all infrastructure components created by the deploy script
# including HPC cluster, storage, AI resources, and monitoring components

set -euo pipefail

# Color codes for output formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FORCE_DELETE="false"
PRESERVE_DATA="false"
DRY_RUN="false"

# Function to display usage
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Destroy Scientific Video Analysis Workflows infrastructure on GCP

OPTIONS:
    -p, --project       GCP Project ID (required)
    -r, --region        GCP Region (default: us-central1)
    -c, --cluster-name  HPC Cluster name (default: video-analysis-cluster)
    -b, --bucket-name   Storage bucket name (required if non-standard)
    -d, --dataset-name  BigQuery dataset name (default: video_analysis_results)
    --force             Force deletion without confirmation prompts
    --preserve-data     Preserve Cloud Storage data and BigQuery datasets
    --dry-run           Show what would be deleted without executing
    -h, --help          Show this help message

EXAMPLES:
    $0 -p my-project                    # Delete all resources with confirmation
    $0 -p my-project --force           # Delete all resources without confirmation
    $0 -p my-project --preserve-data   # Delete compute resources but preserve data
    $0 --dry-run -p my-project         # Preview what would be deleted

WARNING:
    This script will permanently delete infrastructure and data.
    Use --preserve-data to keep Cloud Storage and BigQuery data.

EOF
}

# Function to confirm deletion
confirm_deletion() {
    local resource_type="$1"
    local resource_name="$2"
    
    if [[ "$FORCE_DELETE" == "true" ]]; then
        return 0
    fi
    
    echo -e "${YELLOW}Warning: About to delete ${resource_type}: ${resource_name}${NC}"
    read -p "Are you sure you want to continue? (yes/no): " -r
    
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        log "Deletion of ${resource_type} cancelled by user"
        return 1
    fi
    
    return 0
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites for cleanup..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        error "gcloud CLI is not installed. Please install Google Cloud SDK."
        exit 1
    fi
    
    # Check if gsutil is installed
    if ! command -v gsutil &> /dev/null; then
        error "gsutil is not installed. Please install Google Cloud SDK."
        exit 1
    fi
    
    # Check if bq is installed
    if ! command -v bq &> /dev/null; then
        error "bq is not installed. Please install Google Cloud SDK."
        exit 1
    fi
    
    # Check gcloud authentication
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q "@"; then
        error "No active gcloud authentication found. Please run 'gcloud auth login'."
        exit 1
    fi
    
    # Verify project exists and is accessible
    if ! gcloud projects describe "${PROJECT_ID}" &>/dev/null; then
        error "Project ${PROJECT_ID} not found or not accessible."
        exit 1
    fi
    
    success "Prerequisites check completed"
}

# Function to validate configuration
validate_config() {
    log "Validating configuration..."
    
    if [[ -z "${PROJECT_ID:-}" ]]; then
        error "Project ID is required. Use -p option or set PROJECT_ID environment variable."
        exit 1
    fi
    
    # Set project configuration
    gcloud config set project "${PROJECT_ID}"
    gcloud config set compute/region "${REGION}"
    
    log "Project ID: ${PROJECT_ID}"
    log "Region: ${REGION}"
    log "Cluster Name: ${CLUSTER_NAME}"
    log "Bucket Name: ${BUCKET_NAME}"
    log "Dataset Name: ${DATASET_NAME}"
    
    success "Configuration validated"
}

# Function to stop running jobs
stop_running_jobs() {
    log "Stopping running video analysis jobs..."
    
    # Check if cluster exists and is accessible
    local login_node="${CLUSTER_NAME}-login-0"
    
    if gcloud compute instances describe "${login_node}" --zone="${ZONE}" &>/dev/null; then
        log "Found cluster login node, attempting to stop jobs..."
        
        # Try to gracefully stop all running jobs
        if confirm_deletion "running Slurm jobs" "all video analysis jobs"; then
            # Cancel all running jobs
            gcloud compute ssh "${login_node}" \
                --zone="${ZONE}" \
                --command="scancel -u \$USER" \
                &>/dev/null || warning "Could not cancel jobs (cluster may be inaccessible)"
            
            # Wait for jobs to finish
            log "Waiting for jobs to complete gracefully..."
            sleep 30
            
            success "Job termination attempted"
        fi
    else
        log "Cluster login node not found, skipping job termination"
    fi
}

# Function to destroy HPC cluster
destroy_hpc_cluster() {
    log "Destroying HPC cluster infrastructure..."
    
    # Check if terraform state exists
    local terraform_dir="${SCRIPT_DIR}/hpc-toolkit/video-analysis-cluster"
    
    if [[ -d "$terraform_dir" ]]; then
        if confirm_deletion "HPC cluster" "${CLUSTER_NAME}"; then
            cd "$terraform_dir"
            
            if [[ "$DRY_RUN" == "true" ]]; then
                log "Dry run: would destroy Terraform infrastructure..."
                terraform plan -destroy
            else
                log "Destroying HPC cluster with Terraform..."
                
                # Initialize terraform if needed
                terraform init &>/dev/null || true
                
                # Destroy infrastructure
                if terraform destroy -auto-approve; then
                    success "HPC cluster destroyed successfully"
                else
                    error "Failed to destroy HPC cluster completely"
                    warning "Some resources may need manual cleanup"
                fi
            fi
            
            cd "${SCRIPT_DIR}"
        fi
    else
        log "No Terraform state found for HPC cluster, checking for manual resources..."
        
        # Check for cluster components manually
        local components=(
            "instances"
            "instance-groups"
            "instance-templates"
        )
        
        for component in "${components[@]}"; do
            local resources=$(gcloud compute $component list \
                --filter="name~${CLUSTER_NAME}" \
                --format="value(name)" 2>/dev/null || echo "")
            
            if [[ -n "$resources" ]]; then
                warning "Found ${component} related to cluster ${CLUSTER_NAME}"
                if confirm_deletion "${component}" "${resources}"; then
                    if [[ "$DRY_RUN" != "true" ]]; then
                        echo "$resources" | while read -r resource; do
                            if [[ -n "$resource" ]]; then
                                gcloud compute $component delete "$resource" \
                                    --zone="${ZONE}" --quiet &>/dev/null || true
                            fi
                        done
                    fi
                fi
            fi
        done
    fi
}

# Function to cleanup Vertex AI resources
cleanup_vertex_ai() {
    log "Cleaning up Vertex AI resources..."
    
    # List and delete endpoints
    local endpoints=$(gcloud ai endpoints list \
        --region="${REGION}" \
        --filter="displayName~scientific-video" \
        --format="value(name)" 2>/dev/null || echo "")
    
    if [[ -n "$endpoints" ]]; then
        if confirm_deletion "Vertex AI endpoints" "scientific video analysis endpoints"; then
            if [[ "$DRY_RUN" != "true" ]]; then
                echo "$endpoints" | while read -r endpoint; do
                    if [[ -n "$endpoint" ]]; then
                        local endpoint_id=$(echo "$endpoint" | cut -d'/' -f6)
                        gcloud ai endpoints delete "$endpoint_id" \
                            --region="${REGION}" --quiet &>/dev/null || true
                    fi
                done
                success "Vertex AI endpoints deleted"
            fi
        fi
    else
        log "No Vertex AI endpoints found to delete"
    fi
    
    # List and delete datasets
    local datasets=$(gcloud ai datasets list \
        --region="${REGION}" \
        --filter="displayName~scientific-video" \
        --format="value(name)" 2>/dev/null || echo "")
    
    if [[ -n "$datasets" ]]; then
        if confirm_deletion "Vertex AI datasets" "scientific video analysis datasets"; then
            if [[ "$DRY_RUN" != "true" ]]; then
                echo "$datasets" | while read -r dataset; do
                    if [[ -n "$dataset" ]]; then
                        local dataset_id=$(echo "$dataset" | cut -d'/' -f6)
                        gcloud ai datasets delete "$dataset_id" \
                            --region="${REGION}" --quiet &>/dev/null || true
                    fi
                done
                success "Vertex AI datasets deleted"
            fi
        fi
    else
        log "No Vertex AI datasets found to delete"
    fi
}

# Function to cleanup Cloud Storage
cleanup_storage() {
    if [[ "$PRESERVE_DATA" == "true" ]]; then
        warning "Preserving Cloud Storage data (--preserve-data flag provided)"
        return 0
    fi
    
    log "Cleaning up Cloud Storage resources..."
    
    # Check if bucket exists
    if gsutil ls "gs://${BUCKET_NAME}" &>/dev/null; then
        if confirm_deletion "Cloud Storage bucket" "gs://${BUCKET_NAME}"; then
            if [[ "$DRY_RUN" == "true" ]]; then
                log "Dry run: would delete bucket gs://${BUCKET_NAME}"
                gsutil du -sh "gs://${BUCKET_NAME}"
            else
                log "Deleting Cloud Storage bucket and all contents..."
                
                # Remove versioning to allow deletion
                gsutil versioning set off "gs://${BUCKET_NAME}" &>/dev/null || true
                
                # Delete all objects and versions
                gsutil -m rm -r "gs://${BUCKET_NAME}" || {
                    warning "Failed to delete bucket, attempting force deletion..."
                    gsutil -m rm -a "gs://${BUCKET_NAME}/**" &>/dev/null || true
                    gsutil rb "gs://${BUCKET_NAME}" &>/dev/null || true
                }
                
                success "Cloud Storage bucket deleted"
            fi
        fi
    else
        log "Cloud Storage bucket gs://${BUCKET_NAME} not found"
    fi
}

# Function to cleanup BigQuery resources
cleanup_bigquery() {
    if [[ "$PRESERVE_DATA" == "true" ]]; then
        warning "Preserving BigQuery data (--preserve-data flag provided)"
        return 0
    fi
    
    log "Cleaning up BigQuery resources..."
    
    # Check if dataset exists
    if bq ls -d "${PROJECT_ID}:${DATASET_NAME}" &>/dev/null; then
        if confirm_deletion "BigQuery dataset" "${PROJECT_ID}:${DATASET_NAME}"; then
            if [[ "$DRY_RUN" == "true" ]]; then
                log "Dry run: would delete BigQuery dataset ${PROJECT_ID}:${DATASET_NAME}"
                bq ls "${PROJECT_ID}:${DATASET_NAME}"
            else
                log "Deleting BigQuery dataset and all tables..."
                bq rm -r -f "${PROJECT_ID}:${DATASET_NAME}"
                success "BigQuery dataset deleted"
            fi
        fi
    else
        log "BigQuery dataset ${PROJECT_ID}:${DATASET_NAME} not found"
    fi
}

# Function to cleanup Dataflow jobs
cleanup_dataflow() {
    log "Cleaning up Dataflow jobs..."
    
    # List running jobs
    local jobs=$(gcloud dataflow jobs list \
        --region="${REGION}" \
        --filter="state:JOB_STATE_RUNNING" \
        --format="value(id)" 2>/dev/null || echo "")
    
    if [[ -n "$jobs" ]]; then
        if confirm_deletion "running Dataflow jobs" "video analysis pipelines"; then
            if [[ "$DRY_RUN" != "true" ]]; then
                echo "$jobs" | while read -r job_id; do
                    if [[ -n "$job_id" ]]; then
                        gcloud dataflow jobs cancel "$job_id" \
                            --region="${REGION}" --quiet &>/dev/null || true
                    fi
                done
                success "Dataflow jobs cancelled"
            fi
        fi
    else
        log "No running Dataflow jobs found"
    fi
}

# Function to cleanup monitoring resources
cleanup_monitoring() {
    log "Cleaning up monitoring resources..."
    
    # Remove custom metrics if they exist
    local metrics=(
        "custom.googleapis.com/video_analysis/active_jobs"
        "custom.googleapis.com/video_analysis/jobs_running"
        "custom.googleapis.com/video_analysis/jobs_pending"
        "custom.googleapis.com/video_analysis/jobs_completed"
    )
    
    for metric in "${metrics[@]}"; do
        if [[ "$DRY_RUN" != "true" ]]; then
            # Note: Custom metrics are automatically cleaned up when no data is sent
            log "Custom metric ${metric} will be automatically removed after 24 hours of no data"
        fi
    done
    
    success "Monitoring cleanup completed"
}

# Function to cleanup local files
cleanup_local_files() {
    log "Cleaning up local files..."
    
    local files_to_remove=(
        "${SCRIPT_DIR}/hpc-toolkit"
        "${SCRIPT_DIR}/video-analysis-script.py"
        "${SCRIPT_DIR}/submit-video-analysis.sh"
        "${SCRIPT_DIR}/monitor-video-jobs.py"
        "${SCRIPT_DIR}/sample-video-metadata.json"
        "${SCRIPT_DIR}/scientific-video-training.jsonl"
    )
    
    if confirm_deletion "local files and directories" "downloaded repositories and generated scripts"; then
        if [[ "$DRY_RUN" != "true" ]]; then
            for file in "${files_to_remove[@]}"; do
                if [[ -e "$file" ]]; then
                    rm -rf "$file"
                    log "Removed: $file"
                fi
            done
            success "Local files cleaned up"
        else
            log "Dry run: would remove local files:"
            for file in "${files_to_remove[@]}"; do
                if [[ -e "$file" ]]; then
                    log "  - $file"
                fi
            done
        fi
    fi
}

# Function to cleanup IAM resources (if any were created)
cleanup_iam() {
    log "Checking for IAM resources to cleanup..."
    
    # List service accounts created for the project
    local service_accounts=$(gcloud iam service-accounts list \
        --filter="email~video-analysis OR email~scientific-video" \
        --format="value(email)" 2>/dev/null || echo "")
    
    if [[ -n "$service_accounts" ]]; then
        if confirm_deletion "service accounts" "video analysis service accounts"; then
            if [[ "$DRY_RUN" != "true" ]]; then
                echo "$service_accounts" | while read -r account; do
                    if [[ -n "$account" ]]; then
                        gcloud iam service-accounts delete "$account" --quiet &>/dev/null || true
                    fi
                done
                success "Service accounts deleted"
            fi
        fi
    else
        log "No video analysis service accounts found"
    fi
}

# Function to display cleanup summary
display_cleanup_summary() {
    log "Cleanup Summary"
    echo "==============="
    echo "Project ID: ${PROJECT_ID}"
    echo "Region: ${REGION}"
    echo ""
    
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "DRY RUN COMPLETED - No resources were actually deleted"
    else
        echo "Resources Cleaned Up:"
        echo "- HPC Cluster and compute resources"
        echo "- Vertex AI endpoints and datasets"
        if [[ "$PRESERVE_DATA" != "true" ]]; then
            echo "- Cloud Storage bucket and data"
            echo "- BigQuery dataset and tables"
        else
            echo "- Data resources preserved (--preserve-data flag)"
        fi
        echo "- Dataflow jobs cancelled"
        echo "- Monitoring resources cleaned"
        echo "- Local files and repositories"
        echo "- IAM service accounts"
    fi
    
    echo ""
    if [[ "$PRESERVE_DATA" == "true" ]]; then
        warning "Data preservation enabled - storage and BigQuery resources were not deleted"
        echo "To delete data later, run: $0 -p ${PROJECT_ID} --force"
    fi
    
    echo ""
    echo "Notes:"
    echo "- Custom monitoring metrics will be automatically removed after 24 hours"
    echo "- Some GCP resources may take a few minutes to be fully removed"
    echo "- Check the GCP Console to verify all resources have been deleted"
    
    success "Cleanup completed!"
}

# Main cleanup function
main() {
    log "Starting Scientific Video Analysis Workflows cleanup..."
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -p|--project)
                PROJECT_ID="$2"
                shift 2
                ;;
            -r|--region)
                REGION="$2"
                shift 2
                ;;
            -c|--cluster-name)
                CLUSTER_NAME="$2"
                shift 2
                ;;
            -b|--bucket-name)
                BUCKET_NAME="$2"
                shift 2
                ;;
            -d|--dataset-name)
                DATASET_NAME="$2"
                shift 2
                ;;
            --force)
                FORCE_DELETE="true"
                shift
                ;;
            --preserve-data)
                PRESERVE_DATA="true"
                shift
                ;;
            --dry-run)
                DRY_RUN="true"
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                error "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done
    
    # Set defaults for unspecified parameters
    REGION="${REGION:-us-central1}"
    ZONE="${ZONE:-us-central1-a}"
    CLUSTER_NAME="${CLUSTER_NAME:-video-analysis-cluster}"
    DATASET_NAME="${DATASET_NAME:-video_analysis_results}"
    
    # Try to detect bucket name if not provided
    if [[ -z "${BUCKET_NAME:-}" ]]; then
        log "Attempting to detect bucket name..."
        BUCKET_NAME=$(gsutil ls -p "${PROJECT_ID}" | grep "scientific-video-data-" | head -1 | sed 's|gs://||' | sed 's|/||' || echo "")
        
        if [[ -z "$BUCKET_NAME" ]]; then
            warning "Could not detect bucket name. Use -b option if you have a non-standard bucket name."
            BUCKET_NAME="scientific-video-data-unknown"
        else
            log "Detected bucket: $BUCKET_NAME"
        fi
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY RUN MODE - No resources will be deleted"
    fi
    
    if [[ "$FORCE_DELETE" == "true" ]]; then
        warning "FORCE MODE - All confirmations will be skipped"
    fi
    
    # Execute cleanup steps
    check_prerequisites
    validate_config
    
    # Display final warning
    if [[ "$DRY_RUN" != "true" ]] && [[ "$FORCE_DELETE" != "true" ]]; then
        echo ""
        echo -e "${RED}WARNING: This will permanently delete infrastructure and potentially data!${NC}"
        echo "Project: ${PROJECT_ID}"
        echo "Resources to be deleted:"
        echo "  - HPC Cluster: ${CLUSTER_NAME}"
        echo "  - Storage Bucket: gs://${BUCKET_NAME}"
        echo "  - BigQuery Dataset: ${DATASET_NAME}"
        echo "  - Vertex AI resources"
        echo "  - All related compute and monitoring resources"
        echo ""
        read -p "Are you absolutely sure you want to continue? (type 'yes' to confirm): " -r
        
        if [[ ! $REPLY == "yes" ]]; then
            log "Cleanup cancelled by user"
            exit 0
        fi
    fi
    
    # Execute cleanup in proper order
    log "Beginning infrastructure cleanup..."
    
    stop_running_jobs
    cleanup_dataflow
    destroy_hpc_cluster
    cleanup_vertex_ai
    cleanup_storage
    cleanup_bigquery
    cleanup_monitoring
    cleanup_iam
    cleanup_local_files
    
    display_cleanup_summary
}

# Execute main function with all arguments
main "$@"