#!/bin/bash

# Privacy-Preserving Analytics with Confidential GKE and BigQuery - Cleanup Script
# This script removes all resources created by the deployment script
# including Confidential GKE, BigQuery datasets, Cloud KMS keys, and Cloud Storage

set -euo pipefail

# Configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_FILE="${SCRIPT_DIR}/destroy_$(date +%Y%m%d_%H%M%S).log"

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Logging functions
log() {
    echo -e "${1}" | tee -a "${LOG_FILE}"
}

log_info() {
    log "${BLUE}[INFO]${NC} ${1}"
}

log_success() {
    log "${GREEN}[SUCCESS]${NC} ${1}"
}

log_warning() {
    log "${YELLOW}[WARNING]${NC} ${1}"
}

log_error() {
    log "${RED}[ERROR]${NC} ${1}"
}

# Error handling
cleanup_on_error() {
    local exit_code=$?
    log_error "Cleanup failed with exit code ${exit_code}"
    log_error "Check the log file: ${LOG_FILE}"
    log_warning "Some resources may still exist. Review the log and manually clean up if needed."
    exit ${exit_code}
}

trap cleanup_on_error ERR

# Show usage information
show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Remove all privacy-preserving analytics infrastructure resources.

OPTIONS:
    -p, --project PROJECT_ID    Google Cloud project ID (required)
    -r, --region REGION         Google Cloud region (default: us-central1)
    -z, --zone ZONE            Google Cloud zone (default: us-central1-a)
    -s, --suffix SUFFIX        Resource name suffix (required if not auto-detected)
    -a, --all                  Remove all matching resources regardless of suffix
    -f, --force                Skip confirmation prompts (dangerous!)
    -d, --dry-run              Show what would be deleted without executing
    -v, --verbose              Enable verbose logging
    -h, --help                 Show this help message

EXAMPLES:
    $0 --project my-project-123 --suffix abc123
    $0 --project my-project-123 --all --force
    $0 --dry-run --project my-project-123

SAFETY:
    - This script will DELETE resources and data permanently
    - Use --dry-run first to verify what will be deleted
    - Resources are deleted in dependency order for safety
    - KMS keys are scheduled for destruction (24-hour waiting period)

EOF
}

# Parse command line arguments
parse_arguments() {
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
            -z|--zone)
                ZONE="$2"
                shift 2
                ;;
            -s|--suffix)
                RESOURCE_SUFFIX="$2"
                shift 2
                ;;
            -a|--all)
                DELETE_ALL=true
                shift
                ;;
            -f|--force)
                FORCE=true
                shift
                ;;
            -d|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -v|--verbose)
                VERBOSE=true
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
}

# Set default values
set_defaults() {
    REGION="${REGION:-us-central1}"
    ZONE="${ZONE:-us-central1-a}"
    DRY_RUN="${DRY_RUN:-false}"
    VERBOSE="${VERBOSE:-false}"
    FORCE="${FORCE:-false}"
    DELETE_ALL="${DELETE_ALL:-false}"
}

# Validate prerequisites
validate_prerequisites() {
    log_info "Validating prerequisites..."
    
    # Check if PROJECT_ID is set
    if [[ -z "${PROJECT_ID:-}" ]]; then
        log_error "Project ID is required. Use --project flag or set PROJECT_ID environment variable."
        show_usage
        exit 1
    fi
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "Google Cloud CLI (gcloud) is not installed or not in PATH"
        log_error "Install from: https://cloud.google.com/sdk/docs/install"
        exit 1
    fi
    
    # Check if kubectl is installed
    if ! command -v kubectl &> /dev/null; then
        log_warning "kubectl is not installed - Kubernetes cleanup will be skipped"
    fi
    
    # Validate gcloud authentication
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -1 &> /dev/null; then
        log_error "Not authenticated with Google Cloud. Run: gcloud auth login"
        exit 1
    fi
    
    # Validate project access
    if ! gcloud projects describe "${PROJECT_ID}" &> /dev/null; then
        log_error "Cannot access project ${PROJECT_ID} or project doesn't exist"
        exit 1
    fi
    
    log_success "Prerequisites validation completed"
}

# Configure gcloud settings
configure_gcloud() {
    log_info "Configuring gcloud settings..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would set project to ${PROJECT_ID}"
        return 0
    fi
    
    gcloud config set project "${PROJECT_ID}" 2>> "${LOG_FILE}"
    gcloud config set compute/region "${REGION}" 2>> "${LOG_FILE}"
    gcloud config set compute/zone "${ZONE}" 2>> "${LOG_FILE}"
    
    log_success "Gcloud configuration completed"
}

# Auto-detect resources if suffix not provided
auto_detect_resources() {
    if [[ "${DELETE_ALL}" == "true" ]]; then
        log_info "DELETE_ALL mode - will find all matching resources"
        return 0
    fi
    
    if [[ -n "${RESOURCE_SUFFIX:-}" ]]; then
        log_info "Using provided resource suffix: ${RESOURCE_SUFFIX}"
        return 0
    fi
    
    log_info "Auto-detecting resources..."
    
    # Try to find GKE clusters with our naming pattern
    local clusters
    clusters=$(gcloud container clusters list --format="value(name)" --filter="name:confidential-cluster-*" 2>/dev/null || true)
    
    if [[ -n "${clusters}" ]]; then
        local cluster_count
        cluster_count=$(echo "${clusters}" | wc -l)
        if [[ ${cluster_count} -eq 1 ]]; then
            RESOURCE_SUFFIX=$(echo "${clusters}" | sed 's/confidential-cluster-//')
            log_info "Auto-detected resource suffix: ${RESOURCE_SUFFIX}"
        else
            log_warning "Multiple clusters found. Please specify --suffix or use --all"
            log_info "Found clusters: ${clusters}"
            exit 1
        fi
    else
        log_warning "No confidential GKE clusters found in project ${PROJECT_ID}"
        log_info "Use --suffix to specify resources manually or --all to delete all matching resources"
        exit 1
    fi
}

# Set resource names based on suffix
set_resource_names() {
    if [[ "${DELETE_ALL}" != "true" ]] && [[ -z "${RESOURCE_SUFFIX:-}" ]]; then
        log_error "Resource suffix is required when not using --all"
        exit 1
    fi
    
    if [[ "${DELETE_ALL}" == "true" ]]; then
        # Use wildcard patterns for delete-all mode
        CLUSTER_PATTERN="confidential-cluster-*"
        KEYRING_PATTERN="analytics-keyring-*"
        DATASET_PATTERN="sensitive_analytics_*"
        BUCKET_PATTERN="privacy-analytics-${PROJECT_ID}-*"
    else
        # Use specific resource names
        CLUSTER_NAME="confidential-cluster-${RESOURCE_SUFFIX}"
        KEYRING_NAME="analytics-keyring-${RESOURCE_SUFFIX}"
        KEY_NAME="analytics-key-${RESOURCE_SUFFIX}"
        DATASET_NAME="sensitive_analytics_${RESOURCE_SUFFIX}"
        BUCKET_NAME="privacy-analytics-${PROJECT_ID}-${RESOURCE_SUFFIX}"
    fi
}

# Confirm destruction with user
confirm_destruction() {
    if [[ "${FORCE}" == "true" ]] || [[ "${DRY_RUN}" == "true" ]]; then
        return 0
    fi
    
    log_warning "This will PERMANENTLY DELETE the following resources:"
    log_warning "- Confidential GKE clusters and all workloads"
    log_warning "- BigQuery datasets and all data"
    log_warning "- Cloud Storage buckets and contents"
    log_warning "- Cloud KMS keys (scheduled for destruction)"
    log_warning ""
    log_warning "Project: ${PROJECT_ID}"
    log_warning "Region: ${REGION}"
    
    if [[ "${DELETE_ALL}" == "true" ]]; then
        log_warning "Mode: DELETE ALL MATCHING RESOURCES"
    else
        log_warning "Resource Suffix: ${RESOURCE_SUFFIX}"
    fi
    
    echo ""
    read -p "Are you sure you want to continue? Type 'yes' to confirm: " -r
    if [[ ! $REPLY =~ ^yes$ ]]; then
        log_info "Destruction cancelled by user"
        exit 0
    fi
}

# Delete Kubernetes applications
delete_k8s_applications() {
    log_info "Removing Kubernetes applications..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would delete Kubernetes applications"
        return 0
    fi
    
    if ! command -v kubectl &> /dev/null; then
        log_warning "kubectl not available - skipping Kubernetes cleanup"
        return 0
    fi
    
    # Try to delete applications if cluster exists
    if [[ "${DELETE_ALL}" == "true" ]]; then
        # Get all matching clusters
        local clusters
        clusters=$(gcloud container clusters list --format="value(name)" --filter="name:confidential-cluster-*" 2>/dev/null || true)
        for cluster in ${clusters}; do
            log_info "Cleaning up applications in cluster: ${cluster}"
            if gcloud container clusters get-credentials "${cluster}" --zone="${ZONE}" 2>/dev/null; then
                kubectl delete deployment privacy-analytics-app --ignore-not-found=true 2>> "${LOG_FILE}" || true
                kubectl delete service privacy-analytics-service --ignore-not-found=true 2>> "${LOG_FILE}" || true
            fi
        done
    else
        if gcloud container clusters describe "${CLUSTER_NAME}" --zone="${ZONE}" &>/dev/null; then
            if gcloud container clusters get-credentials "${CLUSTER_NAME}" --zone="${ZONE}" 2>/dev/null; then
                kubectl delete deployment privacy-analytics-app --ignore-not-found=true 2>> "${LOG_FILE}" || true
                kubectl delete service privacy-analytics-service --ignore-not-found=true 2>> "${LOG_FILE}" || true
                log_success "Kubernetes applications removed"
            fi
        else
            log_info "Cluster not found - skipping Kubernetes cleanup"
        fi
    fi
}

# Delete Confidential GKE clusters
delete_gke_clusters() {
    log_info "Removing Confidential GKE clusters..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        if [[ "${DELETE_ALL}" == "true" ]]; then
            log_info "[DRY RUN] Would delete all clusters matching: ${CLUSTER_PATTERN}"
        else
            log_info "[DRY RUN] Would delete cluster: ${CLUSTER_NAME}"
        fi
        return 0
    fi
    
    if [[ "${DELETE_ALL}" == "true" ]]; then
        # Delete all matching clusters
        local clusters
        clusters=$(gcloud container clusters list --format="value(name)" --filter="name:confidential-cluster-*" 2>/dev/null || true)
        if [[ -n "${clusters}" ]]; then
            for cluster in ${clusters}; do
                log_info "Deleting cluster: ${cluster}"
                if gcloud container clusters delete "${cluster}" --zone="${ZONE}" --quiet 2>> "${LOG_FILE}"; then
                    log_success "Deleted cluster: ${cluster}"
                else
                    log_warning "Failed to delete cluster: ${cluster}"
                fi
            done
        else
            log_info "No Confidential GKE clusters found to delete"
        fi
    else
        # Delete specific cluster
        if gcloud container clusters describe "${CLUSTER_NAME}" --zone="${ZONE}" &>/dev/null; then
            if gcloud container clusters delete "${CLUSTER_NAME}" --zone="${ZONE}" --quiet 2>> "${LOG_FILE}"; then
                log_success "Deleted Confidential GKE cluster: ${CLUSTER_NAME}"
            else
                log_error "Failed to delete cluster: ${CLUSTER_NAME}"
            fi
        else
            log_info "Cluster ${CLUSTER_NAME} not found - may already be deleted"
        fi
    fi
}

# Delete BigQuery datasets
delete_bigquery_datasets() {
    log_info "Removing BigQuery datasets..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        if [[ "${DELETE_ALL}" == "true" ]]; then
            log_info "[DRY RUN] Would delete all datasets matching: ${DATASET_PATTERN}"
        else
            log_info "[DRY RUN] Would delete dataset: ${DATASET_NAME}"
        fi
        return 0
    fi
    
    if [[ "${DELETE_ALL}" == "true" ]]; then
        # Delete all matching datasets
        local datasets
        datasets=$(bq ls --format=csv --max_results=1000 | grep "sensitive_analytics_" | cut -d',' -f1 2>/dev/null || true)
        if [[ -n "${datasets}" ]]; then
            for dataset in ${datasets}; do
                log_info "Deleting dataset: ${dataset}"
                if bq rm -r -f "${PROJECT_ID}:${dataset}" 2>> "${LOG_FILE}"; then
                    log_success "Deleted dataset: ${dataset}"
                else
                    log_warning "Failed to delete dataset: ${dataset}"
                fi
            done
        else
            log_info "No BigQuery datasets found to delete"
        fi
    else
        # Delete specific dataset
        if bq ls "${PROJECT_ID}" | grep -q "${DATASET_NAME}" 2>/dev/null; then
            if bq rm -r -f "${PROJECT_ID}:${DATASET_NAME}" 2>> "${LOG_FILE}"; then
                log_success "Deleted BigQuery dataset: ${DATASET_NAME}"
            else
                log_error "Failed to delete dataset: ${DATASET_NAME}"
            fi
        else
            log_info "Dataset ${DATASET_NAME} not found - may already be deleted"
        fi
    fi
}

# Delete Cloud Storage buckets
delete_storage_buckets() {
    log_info "Removing Cloud Storage buckets..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        if [[ "${DELETE_ALL}" == "true" ]]; then
            log_info "[DRY RUN] Would delete all buckets matching: ${BUCKET_PATTERN}"
        else
            log_info "[DRY RUN] Would delete bucket: ${BUCKET_NAME}"
        fi
        return 0
    fi
    
    if [[ "${DELETE_ALL}" == "true" ]]; then
        # Delete all matching buckets
        local buckets
        buckets=$(gsutil ls | grep "privacy-analytics-${PROJECT_ID}-" | sed 's|gs://||' | sed 's|/||' 2>/dev/null || true)
        if [[ -n "${buckets}" ]]; then
            for bucket in ${buckets}; do
                log_info "Deleting bucket: ${bucket}"
                if gsutil -m rm -r "gs://${bucket}" 2>> "${LOG_FILE}"; then
                    log_success "Deleted bucket: ${bucket}"
                else
                    log_warning "Failed to delete bucket: ${bucket}"
                fi
            done
        else
            log_info "No Cloud Storage buckets found to delete"
        fi
    else
        # Delete specific bucket
        if gsutil ls "gs://${BUCKET_NAME}" &>/dev/null; then
            if gsutil -m rm -r "gs://${BUCKET_NAME}" 2>> "${LOG_FILE}"; then
                log_success "Deleted Cloud Storage bucket: ${BUCKET_NAME}"
            else
                log_error "Failed to delete bucket: ${BUCKET_NAME}"
            fi
        else
            log_info "Bucket ${BUCKET_NAME} not found - may already be deleted"
        fi
    fi
}

# Delete Cloud KMS keys
delete_kms_keys() {
    log_info "Scheduling Cloud KMS keys for destruction..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        if [[ "${DELETE_ALL}" == "true" ]]; then
            log_info "[DRY RUN] Would schedule all matching KMS keys for destruction"
        else
            log_info "[DRY RUN] Would schedule KMS key for destruction: ${KEY_NAME}"
        fi
        return 0
    fi
    
    if [[ "${DELETE_ALL}" == "true" ]]; then
        # Delete all matching key rings and keys
        local keyrings
        keyrings=$(gcloud kms keyrings list --location="${REGION}" --format="value(name)" | grep "analytics-keyring-" 2>/dev/null || true)
        if [[ -n "${keyrings}" ]]; then
            for keyring in ${keyrings}; do
                local keyring_name
                keyring_name=$(basename "${keyring}")
                log_info "Processing keyring: ${keyring_name}"
                
                # Get all keys in the keyring
                local keys
                keys=$(gcloud kms keys list --location="${REGION}" --keyring="${keyring_name}" --format="value(name)" 2>/dev/null || true)
                for key in ${keys}; do
                    local key_name
                    key_name=$(basename "${key}")
                    log_info "Scheduling key for destruction: ${key_name}"
                    
                    # Schedule key version for destruction
                    local versions
                    versions=$(gcloud kms keys versions list --location="${REGION}" --keyring="${keyring_name}" --key="${key_name}" --filter="state:ENABLED" --format="value(name)" 2>/dev/null || true)
                    for version in ${versions}; do
                        local version_name
                        version_name=$(basename "${version}")
                        if gcloud kms keys versions destroy "${version_name}" --location="${REGION}" --keyring="${keyring_name}" --key="${key_name}" --quiet 2>> "${LOG_FILE}"; then
                            log_success "Scheduled key version for destruction: ${key_name}/${version_name}"
                        else
                            log_warning "Failed to schedule key version: ${key_name}/${version_name}"
                        fi
                    done
                done
            done
        else
            log_info "No KMS keyrings found to delete"
        fi
    else
        # Delete specific key
        if gcloud kms keys describe "${KEY_NAME}" --location="${REGION}" --keyring="${KEYRING_NAME}" &>/dev/null; then
            # Schedule key versions for destruction
            local versions
            versions=$(gcloud kms keys versions list --location="${REGION}" --keyring="${KEYRING_NAME}" --key="${KEY_NAME}" --filter="state:ENABLED" --format="value(name)" 2>/dev/null || true)
            for version in ${versions}; do
                local version_name
                version_name=$(basename "${version}")
                if gcloud kms keys versions destroy "${version_name}" --location="${REGION}" --keyring="${KEYRING_NAME}" --key="${KEY_NAME}" --quiet 2>> "${LOG_FILE}"; then
                    log_success "Scheduled key version for destruction: ${KEY_NAME}/${version_name}"
                else
                    log_warning "Failed to schedule key version: ${KEY_NAME}/${version_name}"
                fi
            done
        else
            log_info "KMS key ${KEY_NAME} not found - may already be deleted"
        fi
    fi
    
    log_warning "KMS keys are scheduled for destruction with a 24-hour waiting period"
    log_warning "They will be permanently deleted after the waiting period expires"
}

# Clean up temporary files
cleanup_temp_files() {
    log_info "Cleaning up temporary files..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would clean up temporary files"
        return 0
    fi
    
    # Remove analytics app manifest if it exists
    if [[ -f "${SCRIPT_DIR}/analytics-app.yaml" ]]; then
        rm -f "${SCRIPT_DIR}/analytics-app.yaml"
        log_success "Removed temporary Kubernetes manifest"
    fi
}

# Display cleanup summary
show_cleanup_summary() {
    log_info "Cleanup Summary"
    log_info "==============="
    log_info "Project ID: ${PROJECT_ID}"
    log_info "Region: ${REGION}"
    log_info "Zone: ${ZONE}"
    
    if [[ "${DELETE_ALL}" == "true" ]]; then
        log_info "Mode: Deleted all matching resources"
    else
        log_info "Resource Suffix: ${RESOURCE_SUFFIX}"
    fi
    
    log_info ""
    log_info "Resources Processed:"
    log_info "- Kubernetes applications (removed)"
    log_info "- Confidential GKE clusters (deleted)"
    log_info "- BigQuery datasets (deleted)"
    log_info "- Cloud Storage buckets (deleted)"
    log_info "- Cloud KMS keys (scheduled for destruction)"
    log_info ""
    log_warning "Important Notes:"
    log_warning "- KMS keys have a 24-hour destruction waiting period"
    log_warning "- Verify all resources are deleted in the Google Cloud Console"
    log_warning "- Monitor billing to ensure no unexpected charges"
    log_info ""
    log_info "Log file: ${LOG_FILE}"
}

# Main cleanup function
main() {
    log_info "Starting Privacy-Preserving Analytics cleanup"
    log_info "Log file: ${LOG_FILE}"
    
    # Parse arguments and set defaults
    parse_arguments "$@"
    set_defaults
    
    # Show configuration
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_warning "DRY RUN MODE - No resources will be deleted"
    fi
    
    # Execute cleanup steps
    validate_prerequisites
    configure_gcloud
    auto_detect_resources
    set_resource_names
    confirm_destruction
    
    delete_k8s_applications
    delete_gke_clusters
    delete_bigquery_datasets
    delete_storage_buckets
    delete_kms_keys
    cleanup_temp_files
    
    # Show summary
    show_cleanup_summary
    
    log_success "Privacy-preserving analytics infrastructure cleanup completed!"
    log_info "Total cleanup time: $((SECONDS / 60)) minutes"
}

# Run main function with all arguments
main "$@"