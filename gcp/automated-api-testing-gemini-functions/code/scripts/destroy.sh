#!/bin/bash

# Automated API Testing with Gemini and Functions - Cleanup Script
# This script safely removes all infrastructure components deployed for the API testing solution

set -euo pipefail  # Exit on error, undefined variables, and pipe failures

# Script configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"
readonly LOG_FILE="${SCRIPT_DIR}/destroy_$(date +%Y%m%d_%H%M%S).log"

# Default configuration
readonly DEFAULT_REGION="us-central1"

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
    log_error "Cleanup failed. Check ${LOG_FILE} for details."
    log_error "Some resources may still exist and require manual cleanup."
    exit 1
}

trap cleanup_on_error ERR

# Usage function
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Safely destroy Automated API Testing with Gemini and Functions infrastructure on GCP.

OPTIONS:
    -p, --project-id PROJECT_ID    Google Cloud Project ID (required)
    -r, --region REGION           Deployment region (default: ${DEFAULT_REGION})
    -s, --suffix SUFFIX          Custom suffix for resource names (optional)
    -i, --info-file FILE         Path to deployment info file (optional)
    -f, --force                  Skip confirmation prompts
    -h, --help                   Show this help message
    --keep-bucket               Keep the storage bucket and its contents
    --keep-apis                 Skip disabling APIs
    --dry-run                   Show what would be destroyed without executing

Examples:
    $0 --project-id my-gcp-project
    $0 --project-id my-gcp-project --suffix test
    $0 --info-file ./deployment_info.env
    $0 --project-id my-gcp-project --force --dry-run

EOF
}

# Parse command line arguments
parse_args() {
    PROJECT_ID=""
    REGION="${DEFAULT_REGION}"
    CUSTOM_SUFFIX=""
    INFO_FILE=""
    FORCE=false
    KEEP_BUCKET=false
    KEEP_APIS=false
    DRY_RUN=false

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
            -s|--suffix)
                CUSTOM_SUFFIX="$2"
                shift 2
                ;;
            -i|--info-file)
                INFO_FILE="$2"
                shift 2
                ;;
            -f|--force)
                FORCE=true
                shift
                ;;
            --keep-bucket)
                KEEP_BUCKET=true
                shift
                ;;
            --keep-apis)
                KEEP_APIS=true
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                log_error "Unknown parameter: $1"
                usage
                exit 1
                ;;
        esac
    done

    # Load from deployment info file if provided
    if [[ -n "${INFO_FILE}" && -f "${INFO_FILE}" ]]; then
        log_info "Loading deployment information from: ${INFO_FILE}"
        source "${INFO_FILE}"
        PROJECT_ID="${PROJECT_ID:-}"
        REGION="${REGION:-$DEFAULT_REGION}"
        CUSTOM_SUFFIX="${RANDOM_SUFFIX:-}"
    fi

    # Try to load from default deployment info file if it exists
    local default_info_file="${SCRIPT_DIR}/deployment_info.env"
    if [[ -z "${INFO_FILE}" && -f "${default_info_file}" && -z "${PROJECT_ID}" ]]; then
        log_info "Loading deployment information from default file: ${default_info_file}"
        source "${default_info_file}"
        PROJECT_ID="${PROJECT_ID:-}"
        REGION="${REGION:-$DEFAULT_REGION}"
        CUSTOM_SUFFIX="${RANDOM_SUFFIX:-}"
    fi

    # Validate required parameters
    if [[ -z "${PROJECT_ID}" ]]; then
        log_error "Project ID is required. Use -p or --project-id to specify, or provide --info-file."
        usage
        exit 1
    fi

    # Generate suffix if not provided
    if [[ -z "${CUSTOM_SUFFIX}" ]]; then
        log_warning "No suffix provided. Will attempt to find resources with common patterns."
        RANDOM_SUFFIX=""
    else
        RANDOM_SUFFIX="${CUSTOM_SUFFIX}"
    fi

    # Set resource names (will be updated during discovery if needed)
    FUNCTION_NAME="api-test-orchestrator-${RANDOM_SUFFIX}"
    SERVICE_NAME="api-test-runner-${RANDOM_SUFFIX}"
    BUCKET_NAME="${PROJECT_ID}-test-results-${RANDOM_SUFFIX}"

    log_info "Configuration:"
    log_info "  Project ID: ${PROJECT_ID}"
    log_info "  Region: ${REGION}"
    log_info "  Resource Suffix: ${RANDOM_SUFFIX}"
    log_info "  Force Mode: ${FORCE}"
    log_info "  Keep Bucket: ${KEEP_BUCKET}"
    log_info "  Keep APIs: ${KEEP_APIS}"
    log_info "  Dry Run: ${DRY_RUN}"
}

# Check prerequisites
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
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        log_error "Not authenticated with gcloud. Please run 'gcloud auth login'"
        exit 1
    fi

    # Verify project exists and user has access
    if ! gcloud projects describe "${PROJECT_ID}" &> /dev/null; then
        log_error "Project '${PROJECT_ID}' does not exist or you don't have access to it"
        exit 1
    fi

    log_success "Prerequisites check completed"
}

# Configure gcloud settings
configure_gcloud() {
    log_info "Configuring gcloud settings..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would set project to ${PROJECT_ID}"
        return
    fi

    gcloud config set project "${PROJECT_ID}"

    log_success "gcloud configuration completed"
}

# Discover existing resources
discover_resources() {
    log_info "Discovering existing resources..."

    # Discover Cloud Functions
    log_info "Discovering Cloud Functions..."
    DISCOVERED_FUNCTIONS=()
    if [[ -n "${RANDOM_SUFFIX}" ]]; then
        # Look for exact match
        if gcloud functions describe "${FUNCTION_NAME}" --region="${REGION}" &> /dev/null; then
            DISCOVERED_FUNCTIONS+=("${FUNCTION_NAME}")
        fi
    else
        # Look for pattern matches
        while IFS= read -r func_name; do
            if [[ "${func_name}" =~ api-test-orchestrator-.* ]]; then
                DISCOVERED_FUNCTIONS+=("${func_name}")
            fi
        done < <(gcloud functions list --regions="${REGION}" --format="value(name)" 2>/dev/null || true)
    fi

    # Discover Cloud Run services
    log_info "Discovering Cloud Run services..."
    DISCOVERED_SERVICES=()
    if [[ -n "${RANDOM_SUFFIX}" ]]; then
        # Look for exact match
        if gcloud run services describe "${SERVICE_NAME}" --region="${REGION}" &> /dev/null; then
            DISCOVERED_SERVICES+=("${SERVICE_NAME}")
        fi
    else
        # Look for pattern matches
        while IFS= read -r svc_name; do
            if [[ "${svc_name}" =~ api-test-runner-.* ]]; then
                DISCOVERED_SERVICES+=("${svc_name}")
            fi
        done < <(gcloud run services list --regions="${REGION}" --format="value(metadata.name)" 2>/dev/null || true)
    fi

    # Discover Storage buckets
    log_info "Discovering Storage buckets..."
    DISCOVERED_BUCKETS=()
    if [[ -n "${RANDOM_SUFFIX}" ]]; then
        # Look for exact match
        if gsutil ls -b gs://"${BUCKET_NAME}" &> /dev/null; then
            DISCOVERED_BUCKETS+=("${BUCKET_NAME}")
        fi
    else
        # Look for pattern matches
        while IFS= read -r bucket_name; do
            if [[ "${bucket_name}" =~ gs://.*-test-results-.* ]]; then
                bucket_name="${bucket_name#gs://}"
                bucket_name="${bucket_name%/}"
                DISCOVERED_BUCKETS+=("${bucket_name}")
            fi
        done < <(gsutil ls -b | grep "${PROJECT_ID}" || true)
    fi

    # Report discoveries
    log_info "Resource Discovery Summary:"
    log_info "  Cloud Functions (${#DISCOVERED_FUNCTIONS[@]}): ${DISCOVERED_FUNCTIONS[*]}"
    log_info "  Cloud Run Services (${#DISCOVERED_SERVICES[@]}): ${DISCOVERED_SERVICES[*]}"
    log_info "  Storage Buckets (${#DISCOVERED_BUCKETS[@]}): ${DISCOVERED_BUCKETS[*]}"

    # Update primary resource names if single matches found
    if [[ ${#DISCOVERED_FUNCTIONS[@]} -eq 1 ]]; then
        FUNCTION_NAME="${DISCOVERED_FUNCTIONS[0]}"
    fi
    if [[ ${#DISCOVERED_SERVICES[@]} -eq 1 ]]; then
        SERVICE_NAME="${DISCOVERED_SERVICES[0]}"
    fi
    if [[ ${#DISCOVERED_BUCKETS[@]} -eq 1 ]]; then
        BUCKET_NAME="${DISCOVERED_BUCKETS[0]}"
    fi
}

# Confirm destruction
confirm_destruction() {
    if [[ "${FORCE}" == "true" || "${DRY_RUN}" == "true" ]]; then
        return
    fi

    log_warning "=== DESTRUCTIVE OPERATION WARNING ==="
    log_warning "This will permanently delete the following resources:"
    log_warning "  • Cloud Functions: ${DISCOVERED_FUNCTIONS[*]}"
    log_warning "  • Cloud Run Services: ${DISCOVERED_SERVICES[*]}"
    if [[ "${KEEP_BUCKET}" == "false" ]]; then
        log_warning "  • Storage Buckets and ALL CONTENTS: ${DISCOVERED_BUCKETS[*]}"
    fi
    log_warning ""
    log_warning "This action CANNOT be undone!"
    log_warning ""

    read -p "Are you sure you want to continue? Type 'yes' to confirm: " confirmation

    if [[ "${confirmation}" != "yes" ]]; then
        log_info "Operation cancelled by user"
        exit 0
    fi

    log_info "Proceeding with resource destruction..."
}

# Delete Cloud Functions
delete_cloud_functions() {
    if [[ ${#DISCOVERED_FUNCTIONS[@]} -eq 0 ]]; then
        log_info "No Cloud Functions found to delete"
        return
    fi

    log_info "Deleting Cloud Functions..."

    for func_name in "${DISCOVERED_FUNCTIONS[@]}"; do
        log_info "Deleting function: ${func_name}"
        
        if [[ "${DRY_RUN}" == "true" ]]; then
            log_info "[DRY RUN] Would delete function: ${func_name}"
            continue
        fi

        if gcloud functions delete "${func_name}" \
            --region="${REGION}" \
            --quiet; then
            log_success "Deleted function: ${func_name}"
        else
            log_warning "Failed to delete function: ${func_name} (may not exist)"
        fi
    done

    log_success "Cloud Functions cleanup completed"
}

# Delete Cloud Run services
delete_cloud_run_services() {
    if [[ ${#DISCOVERED_SERVICES[@]} -eq 0 ]]; then
        log_info "No Cloud Run services found to delete"
        return
    fi

    log_info "Deleting Cloud Run services..."

    for svc_name in "${DISCOVERED_SERVICES[@]}"; do
        log_info "Deleting service: ${svc_name}"
        
        if [[ "${DRY_RUN}" == "true" ]]; then
            log_info "[DRY RUN] Would delete service: ${svc_name}"
            continue
        fi

        if gcloud run services delete "${svc_name}" \
            --region="${REGION}" \
            --quiet; then
            log_success "Deleted service: ${svc_name}"
        else
            log_warning "Failed to delete service: ${svc_name} (may not exist)"
        fi
    done

    log_success "Cloud Run services cleanup completed"
}

# Delete storage buckets
delete_storage_buckets() {
    if [[ "${KEEP_BUCKET}" == "true" ]]; then
        log_info "Skipping bucket deletion as requested (--keep-bucket)"
        return
    fi

    if [[ ${#DISCOVERED_BUCKETS[@]} -eq 0 ]]; then
        log_info "No storage buckets found to delete"
        return
    fi

    log_info "Deleting storage buckets and all contents..."

    for bucket_name in "${DISCOVERED_BUCKETS[@]}"; do
        log_info "Deleting bucket and contents: gs://${bucket_name}"
        
        if [[ "${DRY_RUN}" == "true" ]]; then
            log_info "[DRY RUN] Would delete bucket: gs://${bucket_name}"
            continue
        fi

        # Check if bucket exists
        if ! gsutil ls -b gs://"${bucket_name}" &> /dev/null; then
            log_warning "Bucket gs://${bucket_name} does not exist"
            continue
        fi

        # Remove all objects and the bucket
        if gsutil -m rm -r gs://"${bucket_name}"; then
            log_success "Deleted bucket: gs://${bucket_name}"
        else
            log_warning "Failed to delete bucket: gs://${bucket_name}"
        fi
    done

    log_success "Storage buckets cleanup completed"
}

# Clean up local files
cleanup_local_files() {
    log_info "Cleaning up local files..."

    local files_to_remove=(
        "${PROJECT_ROOT}/test-generator-function"
        "${PROJECT_ROOT}/test-runner-service"
        "${PROJECT_ROOT}/test-workflow.py"
    )

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would remove local files: ${files_to_remove[*]}"
        return
    fi

    for file_path in "${files_to_remove[@]}"; do
        if [[ -e "${file_path}" ]]; then
            rm -rf "${file_path}"
            log_success "Removed: ${file_path}"
        else
            log_info "File not found: ${file_path}"
        fi
    done

    log_success "Local files cleanup completed"
}

# Disable APIs (optional)
disable_apis() {
    if [[ "${KEEP_APIS}" == "true" ]]; then
        log_info "Skipping API disabling as requested (--keep-apis)"
        return
    fi

    log_info "Disabling APIs (optional step)..."

    local apis=(
        "cloudfunctions.googleapis.com"
        "run.googleapis.com"
        "aiplatform.googleapis.com"
    )

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would disable APIs: ${apis[*]}"
        return
    fi

    for api in "${apis[@]}"; do
        log_info "Disabling ${api}..."
        if gcloud services disable "${api}" --force --quiet 2>/dev/null; then
            log_success "Disabled ${api}"
        else
            log_warning "Failed to disable ${api} (may be used by other resources)"
        fi
    done

    log_success "API disabling completed"
}

# Remove deployment info file
cleanup_deployment_info() {
    log_info "Cleaning up deployment information..."

    local info_file="${SCRIPT_DIR}/deployment_info.env"
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would remove deployment info file: ${info_file}"
        return
    fi

    if [[ -f "${info_file}" ]]; then
        rm -f "${info_file}"
        log_success "Removed deployment info file: ${info_file}"
    else
        log_info "Deployment info file not found: ${info_file}"
    fi
}

# Validate cleanup
validate_cleanup() {
    log_info "Validating cleanup..."

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would validate that resources are deleted"
        return
    fi

    local cleanup_issues=()

    # Check Cloud Functions
    for func_name in "${DISCOVERED_FUNCTIONS[@]}"; do
        if gcloud functions describe "${func_name}" --region="${REGION}" &> /dev/null; then
            cleanup_issues+=("Cloud Function still exists: ${func_name}")
        fi
    done

    # Check Cloud Run services
    for svc_name in "${DISCOVERED_SERVICES[@]}"; do
        if gcloud run services describe "${svc_name}" --region="${REGION}" &> /dev/null; then
            cleanup_issues+=("Cloud Run service still exists: ${svc_name}")
        fi
    done

    # Check storage buckets (only if not keeping them)
    if [[ "${KEEP_BUCKET}" == "false" ]]; then
        for bucket_name in "${DISCOVERED_BUCKETS[@]}"; do
            if gsutil ls -b gs://"${bucket_name}" &> /dev/null; then
                cleanup_issues+=("Storage bucket still exists: gs://${bucket_name}")
            fi
        done
    fi

    if [[ ${#cleanup_issues[@]} -gt 0 ]]; then
        log_warning "Cleanup validation found issues:"
        for issue in "${cleanup_issues[@]}"; do
            log_warning "  • ${issue}"
        done
        log_warning "Manual cleanup may be required"
    else
        log_success "Cleanup validation completed successfully"
    fi
}

# Print cleanup summary
print_summary() {
    log_success "=== CLEANUP COMPLETED ==="
    log_info ""
    log_info "Destroyed Infrastructure:"
    log_info "  📦 Project ID: ${PROJECT_ID}"
    log_info "  🌍 Region: ${REGION}"
    log_info "  ⚡ Cloud Functions: ${#DISCOVERED_FUNCTIONS[@]} deleted"
    log_info "  🚀 Cloud Run Services: ${#DISCOVERED_SERVICES[@]} deleted"
    if [[ "${KEEP_BUCKET}" == "false" ]]; then
        log_info "  💾 Storage Buckets: ${#DISCOVERED_BUCKETS[@]} deleted"
    else
        log_info "  💾 Storage Buckets: preserved as requested"
    fi
    log_info ""
    log_info "Log file: ${LOG_FILE}"
    log_info ""
    if [[ "${KEEP_BUCKET}" == "false" && "${KEEP_APIS}" == "false" ]]; then
        log_success "All resources have been cleaned up"
    else
        log_info "Some resources were preserved as requested"
    fi
}

# Main execution
main() {
    log_info "=== Automated API Testing with Gemini and Functions - Cleanup Script ==="
    log_info "Starting cleanup at $(date)"
    log_info ""

    parse_args "$@"
    check_prerequisites
    configure_gcloud
    discover_resources
    confirm_destruction
    delete_cloud_functions
    delete_cloud_run_services
    delete_storage_buckets
    cleanup_local_files
    disable_apis
    cleanup_deployment_info
    validate_cleanup
    print_summary

    log_success "Cleanup completed successfully at $(date)"
}

# Execute main function if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi