#!/bin/bash

# Destroy script for Newsletter Content Generation with Gemini and Scheduler
# This script removes all resources created by the deployment script

set -euo pipefail

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Script configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
readonly LOG_FILE="/tmp/newsletter-destroy-$(date +%Y%m%d_%H%M%S).log"
readonly CONFIG_FILE="${SCRIPT_DIR}/../.deployment-config"

# Initialize logging
exec 1> >(tee -a "${LOG_FILE}")
exec 2> >(tee -a "${LOG_FILE}" >&2)

# Utility functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "${LOG_FILE}"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "${LOG_FILE}"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "${LOG_FILE}"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "${LOG_FILE}"
}

# Function to display usage
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Destroy Newsletter Content Generation infrastructure

OPTIONS:
    -p, --project PROJECT_ID    Google Cloud project ID
    -r, --region REGION         Deployment region
    -f, --force                 Skip confirmation prompts
    -d, --dry-run              Show what would be destroyed without making changes
    -k, --keep-data            Keep Cloud Storage bucket and data
    --config-file FILE         Use specific config file (default: ../.deployment-config)
    -h, --help                 Show this help message

EXAMPLES:
    $0                         # Use configuration from deployment
    $0 --project my-project    # Override project ID
    $0 --force                 # Skip confirmations
    $0 --dry-run              # Preview destruction

EOF
}

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "Google Cloud CLI (gcloud) is not installed"
        exit 1
    fi
    
    # Check if gsutil is installed
    if ! command -v gsutil &> /dev/null; then
        log_error "gsutil is not installed or not in PATH"
        exit 1
    fi
    
    # Check gcloud authentication
    if ! gcloud auth list --filter="status:ACTIVE" --format="value(account)" | head -n1 &> /dev/null; then
        log_error "No active gcloud authentication found"
        log_error "Please run: gcloud auth login"
        exit 1
    fi
    
    log_success "Prerequisites check completed"
}

# Function to load configuration
load_configuration() {
    log_info "Loading deployment configuration..."
    
    if [[ ! -f "${CONFIG_FILE}" ]]; then
        log_warning "Configuration file not found: ${CONFIG_FILE}"
        
        # Try to proceed with manual input if no config file
        if [[ -z "${PROJECT_ID:-}" ]]; then
            log_error "No configuration file found and no project ID provided"
            log_error "Please provide project ID with --project option"
            exit 1
        fi
        
        log_warning "Proceeding with manual configuration"
        export REGION="${REGION:-us-central1}"
        export FUNCTION_NAME=""
        export BUCKET_NAME=""
        export JOB_NAME=""
        export FUNCTION_URL=""
        return 0
    fi
    
    # Source the configuration file
    source "${CONFIG_FILE}"
    
    # Override with command line parameters if provided
    if [[ -n "${PROJECT_ID_OVERRIDE:-}" ]]; then
        PROJECT_ID="${PROJECT_ID_OVERRIDE}"
    fi
    
    if [[ -n "${REGION_OVERRIDE:-}" ]]; then
        REGION="${REGION_OVERRIDE}"
    fi
    
    # Validate required configuration
    if [[ -z "${PROJECT_ID:-}" ]]; then
        log_error "PROJECT_ID not found in configuration"
        exit 1
    fi
    
    if [[ -z "${REGION:-}" ]]; then
        REGION="us-central1"
        log_warning "REGION not found in configuration, using default: ${REGION}"
    fi
    
    log_success "Configuration loaded successfully"
    log_info "Project: ${PROJECT_ID}"
    log_info "Region: ${REGION}"
    
    # Set gcloud configuration
    gcloud config set project "${PROJECT_ID}"
    gcloud config set compute/region "${REGION}"
}

# Function to discover resources if not in config
discover_resources() {
    log_info "Discovering resources to destroy..."
    
    # If function name is not in config, try to discover it
    if [[ -z "${FUNCTION_NAME:-}" ]]; then
        log_info "Searching for newsletter generation functions..."
        local functions
        functions=$(gcloud functions list --region="${REGION}" \
            --filter="name~newsletter-generator" \
            --format="value(name)" 2>/dev/null || true)
        
        if [[ -n "${functions}" ]]; then
            log_info "Found functions:"
            echo "${functions}" | while read -r func; do
                log_info "  - ${func}"
            done
            
            # Use the first function found
            FUNCTION_NAME=$(echo "${functions}" | head -n1 | xargs basename)
            log_info "Will target function: ${FUNCTION_NAME}"
        else
            log_warning "No newsletter generator functions found"
        fi
    fi
    
    # If bucket name is not in config, try to discover it
    if [[ -z "${BUCKET_NAME:-}" ]]; then
        log_info "Searching for newsletter content buckets..."
        local buckets
        buckets=$(gsutil ls -p "${PROJECT_ID}" 2>/dev/null | \
            grep "newsletter-content" || true)
        
        if [[ -n "${buckets}" ]]; then
            log_info "Found buckets:"
            echo "${buckets}" | while read -r bucket; do
                log_info "  - ${bucket}"
            done
            
            # Use the first bucket found (remove gs:// prefix and trailing /)
            BUCKET_NAME=$(echo "${buckets}" | head -n1 | sed 's|gs://||' | sed 's|/$||')
            log_info "Will target bucket: ${BUCKET_NAME}"
        else
            log_warning "No newsletter content buckets found"
        fi
    fi
    
    # If job name is not in config, try to discover it
    if [[ -z "${JOB_NAME:-}" ]]; then
        log_info "Searching for newsletter scheduler jobs..."
        local jobs
        jobs=$(gcloud scheduler jobs list --location="${REGION}" \
            --filter="name~newsletter-schedule" \
            --format="value(name)" 2>/dev/null || true)
        
        if [[ -n "${jobs}" ]]; then
            log_info "Found scheduler jobs:"
            echo "${jobs}" | while read -r job; do
                log_info "  - ${job}"
            done
            
            # Use the first job found
            JOB_NAME=$(echo "${jobs}" | head -n1 | xargs basename)
            log_info "Will target job: ${JOB_NAME}"
        else
            log_warning "No newsletter scheduler jobs found"
        fi
    fi
}

# Function to show destruction plan
show_destruction_plan() {
    log_info "=== Destruction Plan ==="
    echo
    echo "The following resources will be destroyed:"
    echo
    
    # Cloud Scheduler Job
    if [[ -n "${JOB_NAME:-}" ]]; then
        echo "  📅 Cloud Scheduler Job: ${JOB_NAME}"
        echo "     Location: ${REGION}"
    else
        echo "  📅 Cloud Scheduler Job: None found"
    fi
    
    # Cloud Function
    if [[ -n "${FUNCTION_NAME:-}" ]]; then
        echo "  ⚡ Cloud Function: ${FUNCTION_NAME}"
        echo "     Region: ${REGION}"
    else
        echo "  ⚡ Cloud Function: None found"
    fi
    
    # Cloud Storage Bucket
    if [[ -n "${BUCKET_NAME:-}" ]]; then
        echo "  🪣 Cloud Storage Bucket: gs://${BUCKET_NAME}"
        if [[ "${KEEP_DATA}" == "true" ]]; then
            echo "     Status: WILL BE PRESERVED (--keep-data flag)"
        else
            echo "     Status: WILL BE DELETED"
        fi
    else
        echo "  🪣 Cloud Storage Bucket: None found"
    fi
    
    echo
    echo "Project: ${PROJECT_ID}"
    echo "Region: ${REGION}"
    echo "Dry Run: ${DRY_RUN}"
    echo
}

# Function to delete Cloud Scheduler job
delete_scheduler_job() {
    if [[ -z "${JOB_NAME:-}" ]]; then
        log_info "No scheduler job to delete"
        return 0
    fi
    
    log_info "Deleting Cloud Scheduler job: ${JOB_NAME}"
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would delete scheduler job: ${JOB_NAME}"
        return 0
    fi
    
    # Check if job exists
    if ! gcloud scheduler jobs describe "${JOB_NAME}" \
        --location="${REGION}" &> /dev/null; then
        log_warning "Scheduler job ${JOB_NAME} not found"
        return 0
    fi
    
    # Delete the job
    if gcloud scheduler jobs delete "${JOB_NAME}" \
        --location="${REGION}" \
        --quiet; then
        log_success "Deleted scheduler job: ${JOB_NAME}"
    else
        log_error "Failed to delete scheduler job: ${JOB_NAME}"
        return 1
    fi
}

# Function to delete Cloud Function
delete_cloud_function() {
    if [[ -z "${FUNCTION_NAME:-}" ]]; then
        log_info "No Cloud Function to delete"
        return 0
    fi
    
    log_info "Deleting Cloud Function: ${FUNCTION_NAME}"
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would delete function: ${FUNCTION_NAME}"
        return 0
    fi
    
    # Check if function exists
    if ! gcloud functions describe "${FUNCTION_NAME}" \
        --region="${REGION}" &> /dev/null; then
        log_warning "Cloud Function ${FUNCTION_NAME} not found"
        return 0
    fi
    
    # Delete the function
    if gcloud functions delete "${FUNCTION_NAME}" \
        --region="${REGION}" \
        --quiet; then
        log_success "Deleted Cloud Function: ${FUNCTION_NAME}"
    else
        log_error "Failed to delete Cloud Function: ${FUNCTION_NAME}"
        return 1
    fi
}

# Function to delete Cloud Storage bucket
delete_storage_bucket() {
    if [[ -z "${BUCKET_NAME:-}" ]]; then
        log_info "No storage bucket to delete"
        return 0
    fi
    
    if [[ "${KEEP_DATA}" == "true" ]]; then
        log_info "Preserving storage bucket due to --keep-data flag: gs://${BUCKET_NAME}"
        return 0
    fi
    
    log_info "Deleting Cloud Storage bucket: gs://${BUCKET_NAME}"
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would delete bucket: gs://${BUCKET_NAME}"
        return 0
    fi
    
    # Check if bucket exists
    if ! gsutil ls "gs://${BUCKET_NAME}" &> /dev/null; then
        log_warning "Storage bucket gs://${BUCKET_NAME} not found"
        return 0
    fi
    
    # Show bucket contents before deletion
    log_info "Bucket contents that will be deleted:"
    gsutil ls -r "gs://${BUCKET_NAME}" | head -10 || true
    
    local object_count
    object_count=$(gsutil ls -r "gs://${BUCKET_NAME}/**" 2>/dev/null | wc -l || echo "0")
    
    if [[ "${object_count}" -gt 0 ]]; then
        log_warning "Bucket contains ${object_count} objects"
        
        if [[ "${SKIP_CONFIRMATION}" != "true" ]]; then
            echo -n "Are you sure you want to delete all bucket contents? (y/N): "
            read -r response
            if [[ ! "${response}" =~ ^[Yy]$ ]]; then
                log_info "Bucket deletion cancelled by user"
                return 0
            fi
        fi
    fi
    
    # Delete bucket contents and bucket
    if gsutil -m rm -r "gs://${BUCKET_NAME}"; then
        log_success "Deleted storage bucket: gs://${BUCKET_NAME}"
    else
        log_error "Failed to delete storage bucket: gs://${BUCKET_NAME}"
        return 1
    fi
}

# Function to clean up local files
cleanup_local_files() {
    log_info "Cleaning up local configuration files..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would clean up local files"
        return 0
    fi
    
    # Remove deployment configuration file
    if [[ -f "${CONFIG_FILE}" ]]; then
        if rm -f "${CONFIG_FILE}"; then
            log_success "Removed configuration file: ${CONFIG_FILE}"
        else
            log_warning "Failed to remove configuration file: ${CONFIG_FILE}"
        fi
    fi
    
    # Clean up any temporary files
    rm -f /tmp/test_response.json 2>/dev/null || true
    
    log_success "Local cleanup completed"
}

# Function to show destruction summary
show_destruction_summary() {
    log_success "=== Destruction Summary ==="
    echo
    echo "Resources destroyed:"
    
    if [[ -n "${JOB_NAME:-}" ]]; then
        echo "  ✅ Cloud Scheduler Job: ${JOB_NAME}"
    fi
    
    if [[ -n "${FUNCTION_NAME:-}" ]]; then
        echo "  ✅ Cloud Function: ${FUNCTION_NAME}"
    fi
    
    if [[ -n "${BUCKET_NAME:-}" ]]; then
        if [[ "${KEEP_DATA}" == "true" ]]; then
            echo "  💾 Cloud Storage Bucket: gs://${BUCKET_NAME} (preserved)"
        else
            echo "  ✅ Cloud Storage Bucket: gs://${BUCKET_NAME}"
        fi
    fi
    
    echo
    echo "Project: ${PROJECT_ID}"
    echo "Region: ${REGION}"
    echo "Destruction log: ${LOG_FILE}"
    echo
    
    if [[ "${KEEP_DATA}" == "true" ]]; then
        echo "Note: Bucket data was preserved. To delete manually:"
        echo "  gsutil -m rm -r gs://${BUCKET_NAME}"
    fi
    
    log_success "Destruction completed successfully!"
}

# Function to handle errors during destruction
handle_destruction_error() {
    log_error "Destruction process encountered errors"
    log_info "Some resources may not have been deleted"
    log_info "Check the log file for details: ${LOG_FILE}"
    log_info "You may need to manually clean up remaining resources"
    exit 1
}

# Main destruction function
main() {
    # Default values
    PROJECT_ID_OVERRIDE=""
    REGION_OVERRIDE=""
    SKIP_CONFIRMATION="false"
    DRY_RUN="false"
    KEEP_DATA="false"
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -p|--project)
                PROJECT_ID_OVERRIDE="$2"
                shift 2
                ;;
            -r|--region)
                REGION_OVERRIDE="$2"
                shift 2
                ;;
            -f|--force)
                SKIP_CONFIRMATION="true"
                shift
                ;;
            -d|--dry-run)
                DRY_RUN="true"
                shift
                ;;
            -k|--keep-data)
                KEEP_DATA="true"
                shift
                ;;
            --config-file)
                CONFIG_FILE="$2"
                shift 2
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
    
    # Set up error handling
    trap handle_destruction_error ERR
    
    # Display banner
    echo -e "${BLUE}"
    echo "=============================================="
    echo "  Newsletter Content Generation Destruction"
    echo "  Removing Gemini AI + Scheduler + Functions"
    echo "=============================================="
    echo -e "${NC}"
    
    # Execute destruction steps
    check_prerequisites
    load_configuration
    discover_resources
    show_destruction_plan
    
    # Confirmation prompt
    if [[ "${SKIP_CONFIRMATION}" != "true" ]] && [[ "${DRY_RUN}" != "true" ]]; then
        echo
        echo -e "${RED}WARNING: This will permanently delete cloud resources!${NC}"
        echo -n "Do you want to proceed with destruction? (y/N): "
        read -r response
        if [[ ! "${response}" =~ ^[Yy]$ ]]; then
            log_info "Destruction cancelled by user"
            exit 0
        fi
    fi
    
    echo
    log_info "Starting destruction process..."
    
    # Delete resources in reverse order of creation
    delete_scheduler_job
    delete_cloud_function
    delete_storage_bucket
    cleanup_local_files
    
    show_destruction_summary
    
    log_success "All destruction steps completed successfully!"
}

# Run main function with all arguments
main "$@"