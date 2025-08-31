#!/bin/bash

#############################################
# GCP BigQuery Serverless Spark Cleanup Script
# 
# This script safely removes all resources created by the
# BigQuery Serverless Spark deployment, including storage
# buckets, BigQuery datasets, and associated data.
#
# Usage: ./destroy.sh [OPTIONS]
# Options:
#   --project-id PROJECT_ID    Specify GCP project ID (required)
#   --bucket-name BUCKET       Specify storage bucket name
#   --dataset-name DATASET     Specify BigQuery dataset name
#   --region REGION           Specify GCP region (default: us-central1)
#   --force                   Skip confirmation prompts
#   --dry-run                 Show what would be deleted without executing
#   --verbose                 Enable verbose logging
#   --help                    Show this help message
#############################################

set -euo pipefail  # Exit on error, undefined vars, pipe failures

# Script configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_FILE="/tmp/gcp-spark-destroy-$(date +%Y%m%d-%H%M%S).log"
readonly SCRIPT_NAME="$(basename "$0")"

# Default configuration
DEFAULT_REGION="us-central1"
DRY_RUN=false
VERBOSE=false
FORCE=false

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

#############################################
# Logging Functions
#############################################

log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    echo "[${timestamp}] [${level}] ${message}" | tee -a "${LOG_FILE}"
}

log_info() {
    log "INFO" "$@"
    if [[ "${VERBOSE}" == "true" ]]; then
        echo -e "${BLUE}[INFO]${NC} $*"
    fi
}

log_success() {
    log "SUCCESS" "$@"
    echo -e "${GREEN}[SUCCESS]${NC} $*"
}

log_warning() {
    log "WARNING" "$@"
    echo -e "${YELLOW}[WARNING]${NC} $*"
}

log_error() {
    log "ERROR" "$@"
    echo -e "${RED}[ERROR]${NC} $*" >&2
}

#############################################
# Utility Functions
#############################################

show_help() {
    cat << EOF
${SCRIPT_NAME} - Cleanup GCP BigQuery Serverless Spark Resources

USAGE:
    ${SCRIPT_NAME} [OPTIONS]

OPTIONS:
    --project-id PROJECT_ID    Specify GCP project ID (required)
    --bucket-name BUCKET       Specify storage bucket name to delete
    --dataset-name DATASET     Specify BigQuery dataset name to delete
    --region REGION           Specify GCP region (default: ${DEFAULT_REGION})
    --force                   Skip confirmation prompts (dangerous!)
    --dry-run                 Show what would be deleted without executing
    --verbose                 Enable verbose logging
    --help                    Show this help message

EXAMPLES:
    ${SCRIPT_NAME} --project-id my-gcp-project
    ${SCRIPT_NAME} --project-id my-project --bucket-name data-lake-spark-abc123
    ${SCRIPT_NAME} --project-id my-project --force --verbose
    ${SCRIPT_NAME} --project-id my-project --dry-run

SAFETY:
    - By default, prompts for confirmation before destructive operations
    - Use --force to skip confirmations (not recommended for production)
    - Use --dry-run to preview what would be deleted
    - All operations are logged to ${LOG_FILE}

WARNING:
    This script will permanently delete:
    - Cloud Storage buckets and all contents
    - BigQuery datasets and all tables
    - Dataproc batch job history
    
    Deleted data cannot be recovered unless you have backups.

EOF
}

check_command() {
    local cmd="$1"
    if ! command -v "${cmd}" &> /dev/null; then
        log_error "Required command '${cmd}' not found. Please install it first."
        exit 1
    fi
}

check_gcp_authentication() {
    log_info "Checking GCP authentication..."
    
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 > /dev/null; then
        log_error "No active GCP authentication found. Please run 'gcloud auth login'"
        exit 1
    fi
    
    local active_account=$(gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1)
    log_success "Authenticated as: ${active_account}"
}

check_gcp_project() {
    local project_id="$1"
    
    log_info "Validating GCP project: ${project_id}"
    
    if ! gcloud projects describe "${project_id}" &>/dev/null; then
        log_error "Project '${project_id}' not found or not accessible"
        exit 1
    fi
    
    log_success "Project validation successful: ${project_id}"
}

confirm_deletion() {
    local resource_type="$1"
    local resource_name="$2"
    
    if [[ "${FORCE}" == "true" ]]; then
        return 0
    fi
    
    echo
    log_warning "⚠️  DESTRUCTIVE OPERATION WARNING ⚠️"
    echo -e "${RED}You are about to delete:${NC}"
    echo -e "${RED}Type: ${resource_type}${NC}"
    echo -e "${RED}Name: ${resource_name}${NC}"
    echo -e "${RED}This action cannot be undone!${NC}"
    echo
    
    read -p "Are you sure you want to proceed? Type 'DELETE' to confirm: " -r
    echo
    
    if [[ "${REPLY}" != "DELETE" ]]; then
        log_info "Deletion cancelled by user"
        return 1
    fi
    
    return 0
}

discover_resources() {
    local project_id="$1"
    local discovered_buckets=()
    local discovered_datasets=()
    local discovered_jobs=()
    
    log_info "Discovering Spark-related resources in project: ${project_id}"
    
    # Discover storage buckets with spark-related names
    log_info "Searching for storage buckets..."
    while IFS= read -r bucket; do
        if [[ "${bucket}" =~ data-lake-spark|spark-data|analytics ]]; then
            discovered_buckets+=("${bucket}")
            log_info "Found bucket: gs://${bucket}"
        fi
    done < <(gsutil ls -p "${project_id}" 2>/dev/null | sed 's|gs://||g' | sed 's|/||g')
    
    # Discover BigQuery datasets with analytics-related names
    log_info "Searching for BigQuery datasets..."
    while IFS= read -r dataset; do
        if [[ "${dataset}" =~ analytics_dataset|spark_data|data_processing ]]; then
            discovered_datasets+=("${dataset}")
            log_info "Found dataset: ${dataset}"
        fi
    done < <(bq ls --project_id="${project_id}" --format="value(datasetId)" 2>/dev/null)
    
    # Discover recent Dataproc batch jobs
    log_info "Searching for recent Dataproc batch jobs..."
    while IFS= read -r job; do
        if [[ "${job}" =~ processing-job|spark-job|analytics ]]; then
            discovered_jobs+=("${job}")
            log_info "Found batch job: ${job}"
        fi
    done < <(gcloud dataproc batches list --project="${project_id}" --region="${DEFAULT_REGION}" \
        --format="value(name)" --filter="createTime>-P7D" 2>/dev/null | grep -v "^$")
    
    echo
    log_info "Discovery Summary:"
    echo "  - Storage Buckets: ${#discovered_buckets[@]}"
    echo "  - BigQuery Datasets: ${#discovered_datasets[@]}" 
    echo "  - Dataproc Jobs: ${#discovered_jobs[@]}"
    echo
    
    # Export arrays for use in main function
    printf '%s\n' "${discovered_buckets[@]}" > /tmp/discovered_buckets.txt 2>/dev/null || touch /tmp/discovered_buckets.txt
    printf '%s\n' "${discovered_datasets[@]}" > /tmp/discovered_datasets.txt 2>/dev/null || touch /tmp/discovered_datasets.txt
    printf '%s\n' "${discovered_jobs[@]}" > /tmp/discovered_jobs.txt 2>/dev/null || touch /tmp/discovered_jobs.txt
}

delete_storage_buckets() {
    local project_id="$1"
    local specific_bucket="$2"
    
    local buckets_to_delete=()
    
    if [[ -n "${specific_bucket}" ]]; then
        buckets_to_delete=("${specific_bucket}")
    else
        # Read discovered buckets
        while IFS= read -r bucket; do
            [[ -n "${bucket}" ]] && buckets_to_delete+=("${bucket}")
        done < /tmp/discovered_buckets.txt
    fi
    
    if [[ ${#buckets_to_delete[@]} -eq 0 ]]; then
        log_info "No storage buckets found to delete"
        return 0
    fi
    
    for bucket in "${buckets_to_delete[@]}"; do
        log_info "Processing storage bucket: gs://${bucket}"
        
        if [[ "${DRY_RUN}" == "true" ]]; then
            log_info "[DRY-RUN] Would delete bucket: gs://${bucket}"
            continue
        fi
        
        # Check if bucket exists
        if ! gsutil ls "gs://${bucket}" &>/dev/null; then
            log_warning "Bucket does not exist: gs://${bucket}"
            continue
        fi
        
        # Confirm deletion
        if ! confirm_deletion "Cloud Storage Bucket" "gs://${bucket}"; then
            log_info "Skipping bucket deletion: gs://${bucket}"
            continue
        fi
        
        # Delete bucket and all contents
        log_info "Deleting bucket and all contents: gs://${bucket}"
        if gsutil -m rm -r "gs://${bucket}" 2>/dev/null; then
            log_success "Deleted bucket: gs://${bucket}"
        else
            log_error "Failed to delete bucket: gs://${bucket}"
        fi
    done
}

delete_bigquery_datasets() {
    local project_id="$1"
    local specific_dataset="$2"
    
    local datasets_to_delete=()
    
    if [[ -n "${specific_dataset}" ]]; then
        datasets_to_delete=("${specific_dataset}")
    else
        # Read discovered datasets
        while IFS= read -r dataset; do
            [[ -n "${dataset}" ]] && datasets_to_delete+=("${dataset}")
        done < /tmp/discovered_datasets.txt
    fi
    
    if [[ ${#datasets_to_delete[@]} -eq 0 ]]; then
        log_info "No BigQuery datasets found to delete"
        return 0
    fi
    
    for dataset in "${datasets_to_delete[@]}"; do
        log_info "Processing BigQuery dataset: ${dataset}"
        
        if [[ "${DRY_RUN}" == "true" ]]; then
            log_info "[DRY-RUN] Would delete dataset: ${dataset}"
            continue
        fi
        
        # Check if dataset exists
        if ! bq ls --project_id="${project_id}" | grep -q "${dataset}"; then
            log_warning "Dataset does not exist: ${dataset}"
            continue
        fi
        
        # List tables in dataset
        local table_count=$(bq ls --project_id="${project_id}" "${dataset}" 2>/dev/null | wc -l)
        log_info "Dataset contains approximately ${table_count} tables"
        
        # Confirm deletion
        if ! confirm_deletion "BigQuery Dataset" "${project_id}:${dataset}"; then
            log_info "Skipping dataset deletion: ${dataset}"
            continue
        fi
        
        # Delete dataset and all tables
        log_info "Deleting dataset and all tables: ${dataset}"
        if bq rm -r -f "${project_id}:${dataset}"; then
            log_success "Deleted dataset: ${dataset}"
        else
            log_error "Failed to delete dataset: ${dataset}"
        fi
    done
}

cancel_running_jobs() {
    local project_id="$1"
    local region="$2"
    
    log_info "Checking for running Dataproc batch jobs..."
    
    local running_jobs=()
    while IFS= read -r job; do
        if [[ -n "${job}" ]]; then
            local job_state=$(gcloud dataproc batches describe "${job}" \
                --region="${region}" --project="${project_id}" \
                --format="value(state)" 2>/dev/null || echo "UNKNOWN")
            
            if [[ "${job_state}" =~ PENDING|RUNNING ]]; then
                running_jobs+=("${job}")
                log_warning "Found running job: ${job} (State: ${job_state})"
            fi
        fi
    done < /tmp/discovered_jobs.txt
    
    if [[ ${#running_jobs[@]} -eq 0 ]]; then
        log_info "No running jobs found"
        return 0
    fi
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY-RUN] Would cancel ${#running_jobs[@]} running jobs"
        return 0
    fi
    
    if confirm_deletion "Running Dataproc Jobs" "${#running_jobs[@]} job(s)"; then
        for job in "${running_jobs[@]}"; do
            log_info "Cancelling job: ${job}"
            if gcloud dataproc batches cancel "${job}" --region="${region}" --project="${project_id}" 2>/dev/null; then
                log_success "Cancelled job: ${job}"
            else
                log_warning "Failed to cancel job: ${job} (may have completed)"
            fi
        done
    fi
}

cleanup_local_files() {
    local script_dir="$1"
    
    log_info "Cleaning up local temporary files"
    
    local files_to_clean=(
        "${script_dir}/../sample_data/sample_transactions.csv"
        "/tmp/discovered_buckets.txt"
        "/tmp/discovered_datasets.txt"
        "/tmp/discovered_jobs.txt"
    )
    
    for file in "${files_to_clean[@]}"; do
        if [[ -f "${file}" ]]; then
            if [[ "${DRY_RUN}" == "true" ]]; then
                log_info "[DRY-RUN] Would delete local file: ${file}"
            else
                if rm -f "${file}"; then
                    log_success "Deleted local file: $(basename "${file}")"
                else
                    log_warning "Failed to delete local file: ${file}"
                fi
            fi
        fi
    done
}

show_final_verification() {
    local project_id="$1"
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        return 0
    fi
    
    log_info "Performing final verification of resource cleanup..."
    
    # Check remaining buckets
    local remaining_buckets=$(gsutil ls -p "${project_id}" 2>/dev/null | grep -E "data-lake-spark|spark-data|analytics" | wc -l)
    log_info "Remaining spark-related buckets: ${remaining_buckets}"
    
    # Check remaining datasets  
    local remaining_datasets=$(bq ls --project_id="${project_id}" --format="value(datasetId)" 2>/dev/null | grep -E "analytics_dataset|spark_data" | wc -l)
    log_info "Remaining analytics datasets: ${remaining_datasets}"
    
    # Check recent jobs
    local recent_jobs=$(gcloud dataproc batches list --project="${project_id}" --region="${DEFAULT_REGION}" \
        --format="value(name)" --filter="createTime>-P1D" 2>/dev/null | grep -E "processing-job|spark-job" | wc -l)
    log_info "Recent spark jobs (last 24h): ${recent_jobs}"
    
    echo
    if [[ "${remaining_buckets}" -eq 0 && "${remaining_datasets}" -eq 0 ]]; then
        log_success "✅ All targeted resources have been successfully cleaned up"
    else
        log_warning "⚠️  Some resources may still exist. Review manually if needed."
    fi
}

#############################################
# Main Cleanup Logic
#############################################

main() {
    local project_id=""
    local region="${DEFAULT_REGION}"
    local bucket_name=""
    local dataset_name=""
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --project-id)
                project_id="$2"
                shift 2
                ;;
            --bucket-name)
                bucket_name="$2"
                shift 2
                ;;
            --dataset-name)
                dataset_name="$2"
                shift 2
                ;;
            --region)
                region="$2"
                shift 2
                ;;
            --force)
                FORCE=true
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --verbose)
                VERBOSE=true
                shift
                ;;
            --help)
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
    
    # Validate required parameters
    if [[ -z "${project_id}" ]]; then
        log_error "Project ID is required. Use --project-id option."
        show_help
        exit 1
    fi
    
    # Display cleanup configuration
    cat << EOF

====================================================
GCP BigQuery Serverless Spark Resource Cleanup
====================================================
Project ID:     ${project_id}
Region:         ${region}
Bucket Name:    ${bucket_name:-"Auto-discover"}
Dataset Name:   ${dataset_name:-"Auto-discover"}
Force Mode:     ${FORCE}
Dry Run:        ${DRY_RUN}
Verbose:        ${VERBOSE}
Log File:       ${LOG_FILE}
====================================================

EOF
    
    if [[ "${DRY_RUN}" == "false" && "${FORCE}" == "false" ]]; then
        echo -e "${RED}⚠️  WARNING: This will permanently delete cloud resources!${NC}"
        echo -e "${RED}⚠️  Deleted data cannot be recovered!${NC}"
        echo
        read -p "Do you understand and wish to continue? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Cleanup cancelled by user"
            exit 0
        fi
    fi
    
    # Prerequisites check
    log_info "Starting cleanup prerequisites check..."
    
    check_command "gcloud"
    check_command "bq"
    check_command "gsutil"
    
    check_gcp_authentication
    check_gcp_project "${project_id}"
    
    # Set gcloud configuration
    if [[ "${DRY_RUN}" == "false" ]]; then
        gcloud config set project "${project_id}"
        gcloud config set compute/region "${region}"
        log_success "GCP configuration updated"
    fi
    
    # Discover resources if not specified
    if [[ -z "${bucket_name}" && -z "${dataset_name}" ]]; then
        discover_resources "${project_id}"
    fi
    
    # Main cleanup steps
    log_info "Starting resource cleanup..."
    
    cancel_running_jobs "${project_id}" "${region}"
    delete_bigquery_datasets "${project_id}" "${dataset_name}"
    delete_storage_buckets "${project_id}" "${bucket_name}"
    cleanup_local_files "${SCRIPT_DIR}"
    
    # Final verification
    show_final_verification "${project_id}"
    
    # Display completion message
    cat << EOF

====================================================
🧹 CLEANUP COMPLETED
====================================================
Project ID:    ${project_id}
Mode:          $([ "${DRY_RUN}" == "true" ] && echo "DRY RUN" || echo "EXECUTED")
Timestamp:     $(date)

Summary:
- Cancelled running Spark jobs
- Removed BigQuery datasets and tables
- Deleted Cloud Storage buckets and contents
- Cleaned up local temporary files

$([ "${DRY_RUN}" == "false" ] && echo "✅ Resources have been permanently deleted" || echo "ℹ️  This was a dry run - no resources were actually deleted")

Next Steps:
1. Verify remaining resources in Cloud Console
2. Check billing for any unexpected charges
3. Review audit logs if needed

Log File: ${LOG_FILE}
====================================================

EOF
    
    log_success "Cleanup process completed!"
}

# Handle script interruption
trap 'log_error "Script interrupted"; exit 130' INT TERM

# Execute main function
main "$@"