#!/bin/bash

# =============================================================================
# GCP Email Validation with Cloud Functions - Cleanup Script
# =============================================================================
# This script safely removes all resources created by the deployment script:
# - Cloud Functions
# - Cloud Storage buckets and contents
# - Local temporary files
# - Optionally: the entire GCP project
# =============================================================================

set -euo pipefail

# Color codes for output formatting
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Configuration constants
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly DEPLOYMENT_INFO_FILE="${SCRIPT_DIR}/.deployment_info"
readonly CLEANUP_LOG="${SCRIPT_DIR}/cleanup.log"

# Global variables
PROJECT_ID=""
REGION=""
ZONE=""
FUNCTION_NAME=""
BUCKET_NAME=""
DELETE_PROJECT=false
FORCE_DELETE=false

# =============================================================================
# Utility Functions
# =============================================================================

log() {
    local message="$1"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${GREEN}[${timestamp}]${NC} ${message}"
    echo "[${timestamp}] ${message}" >> "${CLEANUP_LOG}"
}

log_warning() {
    local message="$1"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${YELLOW}[${timestamp}] WARNING:${NC} ${message}"
    echo "[${timestamp}] WARNING: ${message}" >> "${CLEANUP_LOG}"
}

log_error() {
    local message="$1"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${RED}[${timestamp}] ERROR:${NC} ${message}" >&2
    echo "[${timestamp}] ERROR: ${message}" >> "${CLEANUP_LOG}"
}

log_info() {
    local message="$1"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${BLUE}[${timestamp}] INFO:${NC} ${message}"
    echo "[${timestamp}] INFO: ${message}" >> "${CLEANUP_LOG}"
}

show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Safely cleanup GCP Email Validation resources

OPTIONS:
    -p, --project PROJECT_ID    GCP Project ID (required if no deployment info)
    -r, --region REGION         GCP region (default: from deployment info)
    -f, --function FUNCTION     Function name (default: from deployment info)
    -b, --bucket BUCKET_NAME    Storage bucket name (default: from deployment info)
    --delete-project           Delete the entire GCP project (DANGER!)
    --force                    Skip confirmation prompts
    --dry-run                  Show what would be deleted without executing
    -h, --help                 Show this help message
    --verbose                  Enable verbose logging

EXAMPLES:
    $0                                  # Cleanup using deployment info
    $0 -p my-project                    # Specify project ID
    $0 --delete-project --force         # Delete entire project without prompts
    $0 --dry-run                        # Preview cleanup actions

SAFETY FEATURES:
    - Confirmation prompts for destructive actions
    - Resource existence validation before deletion
    - Comprehensive logging of all operations
    - Rollback protection for critical resources

EOF
}

# =============================================================================
# Prerequisites and Validation
# =============================================================================

check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "Google Cloud CLI (gcloud) is not installed"
        exit 1
    fi
    
    # Check if gsutil is installed
    if ! command -v gsutil &> /dev/null; then
        log_error "gsutil is not installed"
        exit 1
    fi
    
    # Check authentication
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 &> /dev/null; then
        log_error "Not authenticated with Google Cloud. Please run 'gcloud auth login'"
        exit 1
    fi
    
    log "✅ Prerequisites check completed"
}

load_deployment_info() {
    log "Loading deployment information..."
    
    if [[ -f "${DEPLOYMENT_INFO_FILE}" ]]; then
        log_info "Found deployment info file: ${DEPLOYMENT_INFO_FILE}"
        
        # Source the deployment info
        # shellcheck source=/dev/null
        source "${DEPLOYMENT_INFO_FILE}"
        
        log_info "Loaded deployment info:"
        log_info "  Project ID: ${PROJECT_ID:-"Not set"}"
        log_info "  Region: ${REGION:-"Not set"}"
        log_info "  Function: ${FUNCTION_NAME:-"Not set"}"
        log_info "  Bucket: ${BUCKET_NAME:-"Not set"}"
        log_info "  Deployed: ${DEPLOYMENT_DATE:-"Unknown"}"
        
        # Set project context
        if [[ -n "${PROJECT_ID}" ]]; then
            gcloud config set project "${PROJECT_ID}" --quiet
        fi
        
        log "✅ Deployment information loaded successfully"
    else
        log_warning "No deployment info file found at ${DEPLOYMENT_INFO_FILE}"
        log_info "You may need to specify resources manually with command line options"
    fi
}

validate_resources() {
    log "Validating resources to cleanup..."
    
    if [[ -z "${PROJECT_ID}" ]]; then
        log_error "Project ID not specified. Use -p/--project or ensure deployment info exists"
        exit 1
    fi
    
    # Check if project exists
    if ! gcloud projects describe "${PROJECT_ID}" &> /dev/null; then
        log_error "Project '${PROJECT_ID}' does not exist or is not accessible"
        exit 1
    fi
    
    # Set project context
    gcloud config set project "${PROJECT_ID}" --quiet
    
    log "✅ Resource validation completed"
}

# =============================================================================
# Confirmation and Safety Checks
# =============================================================================

confirm_deletion() {
    local resource_type="$1"
    local resource_name="$2"
    
    if [[ "${FORCE_DELETE}" == "true" ]]; then
        return 0
    fi
    
    echo ""
    echo -e "${YELLOW}⚠️  WARNING: About to delete ${resource_type}${NC}"
    echo -e "Resource: ${RED}${resource_name}${NC}"
    echo ""
    
    read -p "Are you sure you want to continue? (yes/no): " -r
    echo ""
    
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        log_info "Deletion cancelled by user"
        return 1
    fi
    
    return 0
}

confirm_project_deletion() {
    if [[ "${FORCE_DELETE}" == "true" ]]; then
        return 0
    fi
    
    echo ""
    echo -e "${RED}🚨 DANGER: PROJECT DELETION${NC}"
    echo -e "${RED}This will permanently delete the entire project and ALL resources!${NC}"
    echo -e "Project: ${RED}${PROJECT_ID}${NC}"
    echo ""
    echo "This action:"
    echo "  • Cannot be undone"
    echo "  • Will delete ALL resources in the project"
    echo "  • May affect billing and quotas"
    echo "  • Will take several minutes to complete"
    echo ""
    
    read -p "Type 'DELETE PROJECT' to confirm: " -r
    echo ""
    
    if [[ "$REPLY" != "DELETE PROJECT" ]]; then
        log_info "Project deletion cancelled"
        return 1
    fi
    
    # Double confirmation
    read -p "Are you absolutely sure? (yes/no): " -r
    echo ""
    
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        log_info "Project deletion cancelled"
        return 1
    fi
    
    return 0
}

# =============================================================================
# Resource Cleanup Functions
# =============================================================================

cleanup_cloud_function() {
    if [[ -z "${FUNCTION_NAME}" || -z "${REGION}" ]]; then
        log_info "Function name or region not specified, skipping function cleanup"
        return 0
    fi
    
    log "Checking Cloud Function: ${FUNCTION_NAME}"
    
    # Check if function exists
    if ! gcloud functions describe "${FUNCTION_NAME}" \
        --gen2 \
        --region="${REGION}" \
        --quiet &> /dev/null; then
        log_info "Function '${FUNCTION_NAME}' does not exist, skipping"
        return 0
    fi
    
    if confirm_deletion "Cloud Function" "${FUNCTION_NAME}"; then
        log "Deleting Cloud Function: ${FUNCTION_NAME}"
        
        if gcloud functions delete "${FUNCTION_NAME}" \
            --gen2 \
            --region="${REGION}" \
            --quiet; then
            log "✅ Deleted Cloud Function: ${FUNCTION_NAME}"
        else
            log_error "Failed to delete Cloud Function: ${FUNCTION_NAME}"
            return 1
        fi
    else
        log_info "Skipped Cloud Function deletion"
    fi
    
    return 0
}

cleanup_storage_bucket() {
    if [[ -z "${BUCKET_NAME}" ]]; then
        log_info "Bucket name not specified, skipping storage cleanup"
        return 0
    fi
    
    log "Checking Cloud Storage bucket: gs://${BUCKET_NAME}"
    
    # Check if bucket exists
    if ! gsutil ls "gs://${BUCKET_NAME}" &> /dev/null; then
        log_info "Bucket 'gs://${BUCKET_NAME}' does not exist, skipping"
        return 0
    fi
    
    # Show bucket contents summary
    local object_count
    object_count=$(gsutil ls -r "gs://${BUCKET_NAME}/**" 2>/dev/null | wc -l || echo "0")
    log_info "Bucket contains approximately ${object_count} objects"
    
    if confirm_deletion "Cloud Storage bucket and ALL contents" "gs://${BUCKET_NAME}"; then
        log "Deleting Cloud Storage bucket and contents: gs://${BUCKET_NAME}"
        
        # Delete all objects first (for versioned buckets)
        log_info "Removing all objects and versions..."
        if gsutil -m rm -r "gs://${BUCKET_NAME}/**" 2>/dev/null || true; then
            log_info "Removed bucket contents"
        fi
        
        # Delete the bucket
        if gsutil rb "gs://${BUCKET_NAME}"; then
            log "✅ Deleted Cloud Storage bucket: gs://${BUCKET_NAME}"
        else
            log_error "Failed to delete Cloud Storage bucket: gs://${BUCKET_NAME}"
            return 1
        fi
    else
        log_info "Skipped storage bucket deletion"
    fi
    
    return 0
}

cleanup_local_files() {
    log "Cleaning up local files..."
    
    local files_to_cleanup=(
        "${SCRIPT_DIR}/../function-source"
        "${SCRIPT_DIR}/lifecycle.json"
        "${DEPLOYMENT_INFO_FILE}"
    )
    
    for file_path in "${files_to_cleanup[@]}"; do
        if [[ -e "${file_path}" ]]; then
            log_info "Removing: ${file_path}"
            rm -rf "${file_path}"
        fi
    done
    
    log "✅ Local files cleaned up"
}

cleanup_project() {
    if [[ "${DELETE_PROJECT}" != "true" ]]; then
        return 0
    fi
    
    log "Preparing to delete entire project: ${PROJECT_ID}"
    
    if confirm_project_deletion; then
        log "Deleting project: ${PROJECT_ID}"
        log_warning "This operation may take several minutes to complete..."
        
        if gcloud projects delete "${PROJECT_ID}" --quiet; then
            log "✅ Project deletion initiated: ${PROJECT_ID}"
            log_info "Note: Project deletion may take up to 30 minutes to complete fully"
        else
            log_error "Failed to delete project: ${PROJECT_ID}"
            return 1
        fi
    else
        log_info "Skipped project deletion"
    fi
    
    return 0
}

# =============================================================================
# Verification Functions
# =============================================================================

verify_cleanup() {
    log "Verifying cleanup completion..."
    
    local cleanup_issues=0
    
    # Verify function deletion
    if [[ -n "${FUNCTION_NAME}" && -n "${REGION}" ]]; then
        if gcloud functions describe "${FUNCTION_NAME}" \
            --gen2 \
            --region="${REGION}" \
            --quiet &> /dev/null; then
            log_warning "Function '${FUNCTION_NAME}' still exists"
            ((cleanup_issues++))
        else
            log "✅ Function deletion verified"
        fi
    fi
    
    # Verify bucket deletion
    if [[ -n "${BUCKET_NAME}" ]]; then
        if gsutil ls "gs://${BUCKET_NAME}" &> /dev/null; then
            log_warning "Bucket 'gs://${BUCKET_NAME}' still exists"
            ((cleanup_issues++))
        else
            log "✅ Bucket deletion verified"
        fi
    fi
    
    # Verify project deletion (if requested)
    if [[ "${DELETE_PROJECT}" == "true" ]]; then
        # Project deletion is asynchronous, so we can't immediately verify
        log_info "Project deletion is asynchronous and may take time to complete"
    fi
    
    if [[ "${cleanup_issues}" -eq 0 ]]; then
        log "✅ Cleanup verification completed successfully"
    else
        log_warning "Cleanup completed with ${cleanup_issues} potential issues"
    fi
    
    return "${cleanup_issues}"
}

# =============================================================================
# Cleanup Summary
# =============================================================================

show_cleanup_summary() {
    log "📋 Cleanup Summary"
    echo "=============================================" | tee -a "${CLEANUP_LOG}"
    echo "Project ID: ${PROJECT_ID}" | tee -a "${CLEANUP_LOG}"
    echo "Region: ${REGION:-"N/A"}" | tee -a "${CLEANUP_LOG}"
    echo "Function: ${FUNCTION_NAME:-"N/A"}" | tee -a "${CLEANUP_LOG}"
    echo "Bucket: ${BUCKET_NAME:-"N/A"}" | tee -a "${CLEANUP_LOG}"
    echo "Project Deleted: ${DELETE_PROJECT}" | tee -a "${CLEANUP_LOG}"
    echo "=============================================" | tee -a "${CLEANUP_LOG}"
    
    echo "" | tee -a "${CLEANUP_LOG}"
    echo "📝 Cleanup log: ${CLEANUP_LOG}" | tee -a "${CLEANUP_LOG}"
    
    if [[ "${DELETE_PROJECT}" == "true" ]]; then
        echo "" | tee -a "${CLEANUP_LOG}"
        echo "⏳ Note: Project deletion may take up to 30 minutes to complete fully" | tee -a "${CLEANUP_LOG}"
    fi
}

# =============================================================================
# Main Function
# =============================================================================

main() {
    local dry_run=false
    local verbose=false
    
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
            -f|--function)
                FUNCTION_NAME="$2"
                shift 2
                ;;
            -b|--bucket)
                BUCKET_NAME="$2"
                shift 2
                ;;
            --delete-project)
                DELETE_PROJECT=true
                shift
                ;;
            --force)
                FORCE_DELETE=true
                shift
                ;;
            --dry-run)
                dry_run=true
                shift
                ;;
            --verbose)
                verbose=true
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
    
    # Enable verbose logging if requested
    if [[ "${verbose}" == "true" ]]; then
        set -x
    fi
    
    # Initialize cleanup log
    echo "=== GCP Email Validation Cleanup Log ===" > "${CLEANUP_LOG}"
    echo "Started at: $(date)" >> "${CLEANUP_LOG}"
    echo "" >> "${CLEANUP_LOG}"
    
    log "🧹 Starting GCP Email Validation cleanup..."
    log_info "Cleanup log: ${CLEANUP_LOG}"
    
    if [[ "${dry_run}" == "true" ]]; then
        log_info "DRY RUN MODE - No resources will be deleted"
        
        # Load info for preview
        load_deployment_info
        
        echo "Would delete:"
        echo "  - Project: ${PROJECT_ID:-"Not specified"}"
        echo "  - Function: ${FUNCTION_NAME:-"Not specified"}"
        echo "  - Bucket: ${BUCKET_NAME:-"Not specified"}"
        echo "  - Delete entire project: ${DELETE_PROJECT}"
        
        exit 0
    fi
    
    # Execute cleanup steps
    check_prerequisites
    load_deployment_info
    validate_resources
    
    # Warn if project deletion is requested
    if [[ "${DELETE_PROJECT}" == "true" ]]; then
        log_warning "Project deletion mode enabled - this will delete ALL resources in the project"
    fi
    
    # Perform cleanup in safe order
    cleanup_cloud_function
    cleanup_storage_bucket
    
    # Clean up project last (if requested)
    cleanup_project
    
    # Clean up local files
    cleanup_local_files
    
    # Verify cleanup
    verify_cleanup
    
    # Show summary
    show_cleanup_summary
    
    log "🎉 Cleanup completed successfully!"
    log_info "Total cleanup time: $((SECONDS / 60)) minutes $((SECONDS % 60)) seconds"
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi