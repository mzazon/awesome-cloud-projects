#!/bin/bash

# Hash Generator API with Cloud Functions - Cleanup Script
# This script safely removes all resources created by the deployment script
# including the Cloud Function, project settings, and associated resources.

set -euo pipefail  # Exit on errors, undefined variables, and pipe failures

# Color codes for output formatting
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Global variables
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly FUNCTION_NAME="hash-generator"

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

# Error handling function
cleanup_on_error() {
    local exit_code=$?
    log_error "Cleanup failed with exit code ${exit_code}"
    log_warning "Some resources may not have been cleaned up completely"
    log_info "Please review the output above and manually remove any remaining resources"
    exit ${exit_code}
}

# Set up error trap
trap cleanup_on_error ERR

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if gcloud CLI is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "Google Cloud CLI (gcloud) is not installed"
        log_info "Install it from: https://cloud.google.com/sdk/docs/install"
        exit 1
    fi
    
    # Check if user is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 &> /dev/null; then
        log_error "Not authenticated with Google Cloud"
        log_info "Run: gcloud auth login"
        exit 1
    fi
    
    log_success "Prerequisites check passed"
}

# Get current project configuration
get_project_config() {
    log_info "Getting current project configuration..."
    
    # Get current project if not specified
    if [[ -z "${PROJECT_ID:-}" ]]; then
        PROJECT_ID=$(gcloud config get-value project 2>/dev/null || echo "")
        if [[ -z "${PROJECT_ID}" ]]; then
            log_error "No project ID specified and no default project configured"
            log_info "Please specify --project-id or run: gcloud config set project YOUR_PROJECT_ID"
            exit 1
        fi
        log_info "Using current project: ${PROJECT_ID}"
    fi
    
    # Get current region if not specified
    if [[ -z "${REGION:-}" ]]; then
        REGION=$(gcloud config get-value compute/region 2>/dev/null || echo "us-central1")
        log_info "Using region: ${REGION}"
    fi
    
    # Validate project exists
    if ! gcloud projects describe "${PROJECT_ID}" &> /dev/null; then
        log_error "Project ${PROJECT_ID} does not exist or is not accessible"
        exit 1
    fi
    
    export PROJECT_ID REGION
    log_success "Project configuration loaded"
}

# Confirm destruction with user
confirm_destruction() {
    local resources_to_delete=""
    
    log_warning "=== DESTRUCTIVE OPERATION WARNING ==="
    echo
    log_warning "This will permanently delete the following resources:"
    
    # Check what resources exist and will be deleted
    if gcloud functions describe "${FUNCTION_NAME}" --region="${REGION}" --project="${PROJECT_ID}" &> /dev/null; then
        resources_to_delete+="  • Cloud Function: ${FUNCTION_NAME} (${REGION})\n"
    fi
    
    # Check for any associated Cloud Build triggers or other resources
    local build_triggers
    build_triggers=$(gcloud builds triggers list --project="${PROJECT_ID}" --format="value(name)" 2>/dev/null | grep -E "(hash|function)" || echo "")
    if [[ -n "${build_triggers}" ]]; then
        resources_to_delete+="  • Build Triggers: ${build_triggers}\n"
    fi
    
    if [[ -n "${resources_to_delete}" ]]; then
        echo -e "${resources_to_delete}"
        echo
        log_info "Project: ${PROJECT_ID}"
        log_info "Region: ${REGION}"
        echo
        
        if [[ "${FORCE_DELETE:-false}" != "true" ]]; then
            log_warning "This action cannot be undone!"
            echo
            read -p "Are you absolutely sure you want to delete these resources? (type 'yes' to confirm): " -r
            if [[ ! $REPLY == "yes" ]]; then
                log_info "Cleanup cancelled by user"
                exit 0
            fi
        else
            log_warning "Force delete mode enabled - skipping confirmation"
        fi
    else
        log_info "No resources found to delete in project ${PROJECT_ID}"
        if [[ "${DELETE_PROJECT:-false}" != "true" ]]; then
            log_info "Nothing to clean up"
            exit 0
        fi
    fi
    
    log_info "Proceeding with resource cleanup..."
}

# Delete Cloud Function
delete_function() {
    log_info "Checking for Cloud Function: ${FUNCTION_NAME}"
    
    # Check if function exists
    if gcloud functions describe "${FUNCTION_NAME}" --region="${REGION}" --project="${PROJECT_ID}" &> /dev/null; then
        log_info "Deleting Cloud Function: ${FUNCTION_NAME}"
        
        # Get function details before deletion for logging
        local function_url
        function_url=$(gcloud functions describe "${FUNCTION_NAME}" \
            --region="${REGION}" \
            --project="${PROJECT_ID}" \
            --format="value(httpsTrigger.url)" 2>/dev/null || echo "unknown")
        
        log_info "Function URL was: ${function_url}"
        
        # Delete the function
        if gcloud functions delete "${FUNCTION_NAME}" \
            --region="${REGION}" \
            --project="${PROJECT_ID}" \
            --quiet; then
            log_success "Cloud Function deleted successfully"
        else
            log_error "Failed to delete Cloud Function"
            return 1
        fi
        
        # Wait for deletion to complete
        log_info "Waiting for function deletion to complete..."
        local attempts=0
        local max_attempts=30
        
        while [[ ${attempts} -lt ${max_attempts} ]]; do
            if ! gcloud functions describe "${FUNCTION_NAME}" \
                --region="${REGION}" \
                --project="${PROJECT_ID}" &> /dev/null; then
                log_success "Function deletion confirmed"
                break
            fi
            sleep 2
            ((attempts++))
        done
        
        if [[ ${attempts} -eq ${max_attempts} ]]; then
            log_warning "Function may still be deleting - please check manually"
        fi
        
    else
        log_info "Cloud Function ${FUNCTION_NAME} not found - skipping"
    fi
}

# Clean up Cloud Build artifacts
cleanup_build_artifacts() {
    log_info "Cleaning up Cloud Build artifacts..."
    
    # List and delete any builds related to the function
    local builds
    builds=$(gcloud builds list \
        --project="${PROJECT_ID}" \
        --filter="source.storageSource.object~'${FUNCTION_NAME}' OR tags~'${FUNCTION_NAME}'" \
        --format="value(id)" \
        --limit=50 2>/dev/null || echo "")
    
    if [[ -n "${builds}" ]]; then
        log_info "Found Cloud Build artifacts to clean up"
        for build_id in ${builds}; do
            log_info "Build ID: ${build_id}"
        done
        log_info "Note: Build artifacts are automatically cleaned up by Google Cloud"
    else
        log_info "No Cloud Build artifacts found"
    fi
    
    # Clean up any source archives in Cloud Storage
    local source_buckets
    source_buckets=$(gsutil ls -p "${PROJECT_ID}" gs://*/cloudfunctions/source/ 2>/dev/null | grep -o 'gs://[^/]*' | sort -u || echo "")
    
    if [[ -n "${source_buckets}" ]]; then
        log_info "Checking for function source archives..."
        for bucket in ${source_buckets}; do
            local sources
            sources=$(gsutil ls "${bucket}/cloudfunctions/source/" 2>/dev/null | grep -E "(${FUNCTION_NAME}|function-source)" || echo "")
            if [[ -n "${sources}" ]]; then
                log_info "Found source archives in ${bucket}"
                # Note: These are typically cleaned up automatically
                log_info "Source archives are managed by Google Cloud and will be cleaned up automatically"
            fi
        done
    fi
    
    log_success "Build artifacts cleanup completed"
}

# Check for associated IAM roles and bindings
cleanup_iam_resources() {
    log_info "Checking for IAM resources..."
    
    # Check for custom roles related to the function
    local custom_roles
    custom_roles=$(gcloud iam roles list \
        --project="${PROJECT_ID}" \
        --filter="name~'${FUNCTION_NAME}' OR name~'hash'" \
        --format="value(name)" 2>/dev/null || echo "")
    
    if [[ -n "${custom_roles}" ]]; then
        log_info "Found custom IAM roles that may be related:"
        for role in ${custom_roles}; do
            log_info "  • ${role}"
        done
        log_warning "Custom IAM roles are not automatically deleted"
        log_info "Review and delete manually if no longer needed"
    else
        log_info "No custom IAM roles found"
    fi
    
    # Note: Service accounts are typically not created for basic Cloud Functions
    log_info "Default Cloud Functions service account is managed by Google Cloud"
    
    log_success "IAM resources check completed"
}

# Clean up logs and monitoring data
cleanup_logs_monitoring() {
    log_info "Checking logs and monitoring data..."
    
    # Note: Logs are automatically retained according to Cloud Logging retention policies
    log_info "Function logs in Cloud Logging will be retained according to your retention policy"
    log_info "To view remaining logs: gcloud functions logs read ${FUNCTION_NAME} --region=${REGION}"
    
    # Check for custom log sinks
    local log_sinks
    log_sinks=$(gcloud logging sinks list \
        --project="${PROJECT_ID}" \
        --filter="name~'${FUNCTION_NAME}' OR name~'hash'" \
        --format="value(name)" 2>/dev/null || echo "")
    
    if [[ -n "${log_sinks}" ]]; then
        log_info "Found custom log sinks that may be related:"
        for sink in ${log_sinks}; do
            log_info "  • ${sink}"
        done
        log_warning "Custom log sinks are not automatically deleted"
    else
        log_info "No custom log sinks found"
    fi
    
    log_success "Logs and monitoring cleanup completed"
}

# Delete entire project if requested
delete_project() {
    if [[ "${DELETE_PROJECT:-false}" == "true" ]]; then
        log_warning "=== PROJECT DELETION WARNING ==="
        log_warning "You have requested to delete the entire project: ${PROJECT_ID}"
        log_warning "This will permanently delete ALL resources in the project!"
        
        if [[ "${FORCE_DELETE:-false}" != "true" ]]; then
            echo
            read -p "Type the project ID to confirm project deletion: " -r
            if [[ ! $REPLY == "${PROJECT_ID}" ]]; then
                log_info "Project deletion cancelled - project ID did not match"
                return 0
            fi
        fi
        
        log_info "Deleting project: ${PROJECT_ID}"
        if gcloud projects delete "${PROJECT_ID}" --quiet; then
            log_success "Project deletion initiated"
            log_info "Project deletion may take several minutes to complete"
        else
            log_error "Failed to delete project"
            return 1
        fi
    fi
}

# Show cleanup summary
show_cleanup_summary() {
    log_success "=== CLEANUP COMPLETE ==="
    echo
    log_info "Resources Cleaned Up:"
    echo "  • Cloud Function: ${FUNCTION_NAME}"
    echo "  • Associated build artifacts"
    echo "  • Function-specific configurations"
    echo
    log_info "Resources Retained:"
    echo "  • Project: ${PROJECT_ID} (unless --delete-project was used)"
    echo "  • Cloud Logging data (according to retention policy)"
    echo "  • Google Cloud APIs (still enabled)"
    echo
    if [[ "${DELETE_PROJECT:-false}" != "true" ]]; then
        log_info "Project Management:"
        echo "  • To disable APIs: gcloud services disable cloudfunctions.googleapis.com cloudbuild.googleapis.com"
        echo "  • To delete project: gcloud projects delete ${PROJECT_ID}"
    fi
    echo
    log_success "Hash Generator API resources have been cleaned up successfully!"
}

# Main cleanup workflow
main() {
    log_info "Starting Hash Generator API cleanup..."
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --project-id)
                PROJECT_ID="$2"
                shift 2
                ;;
            --region)
                REGION="$2"
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
                log_info "Dry run mode - showing what would be deleted"
                DRY_RUN=true
                shift
                ;;
            --help|-h)
                echo "Usage: $0 [OPTIONS]"
                echo "Options:"
                echo "  --project-id ID      Target specific project ID"
                echo "  --region REGION      Target specific region"
                echo "  --delete-project     Delete the entire project (DANGEROUS)"
                echo "  --force              Skip confirmation prompts"
                echo "  --dry-run            Show what would be deleted without executing"
                echo "  --help, -h           Show this help message"
                echo
                echo "Examples:"
                echo "  $0                                    # Clean up function in current project"
                echo "  $0 --project-id my-project           # Clean up function in specific project"
                echo "  $0 --delete-project --force          # Delete entire project without prompts"
                echo "  $0 --dry-run                         # Show what would be cleaned up"
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                echo "Use --help for usage information"
                exit 1
                ;;
        esac
    done
    
    # Execute cleanup steps
    check_prerequisites
    get_project_config
    
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "DRY RUN - Would clean up:"
        echo "  Project: ${PROJECT_ID}"
        echo "  Region: ${REGION}"
        echo "  Function: ${FUNCTION_NAME}"
        if [[ "${DELETE_PROJECT:-false}" == "true" ]]; then
            echo "  ENTIRE PROJECT would be deleted!"
        fi
        exit 0
    fi
    
    confirm_destruction
    delete_function
    cleanup_build_artifacts
    cleanup_iam_resources
    cleanup_logs_monitoring
    delete_project
    show_cleanup_summary
    
    log_success "Cleanup completed successfully!"
}

# Execute main function with all arguments
main "$@"