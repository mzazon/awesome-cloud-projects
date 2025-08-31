#!/bin/bash

# Content Quality Scoring with Vertex AI and Functions - Cleanup Script
# This script safely removes all resources created for the content quality scoring system

set -euo pipefail  # Exit on error, undefined vars, and pipe failures

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

warn() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check if user is authenticated
check_auth() {
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        error "No active gcloud authentication found. Please run 'gcloud auth login'"
        exit 1
    fi
}

# Function to load deployment state
load_deployment_state() {
    local state_file="./.deployment_state"
    
    if [[ -f "$state_file" ]]; then
        log "Loading deployment state from $state_file"
        source "$state_file"
        
        log "Loaded deployment configuration:"
        log "  Project ID: ${PROJECT_ID:-<not set>}"
        log "  Region: ${REGION:-<not set>}"
        log "  Content Bucket: ${BUCKET_NAME:-<not set>}"
        log "  Results Bucket: ${RESULTS_BUCKET:-<not set>}"
        log "  Function Name: ${FUNCTION_NAME:-<not set>}"
        
        return 0
    else
        warn "No deployment state file found at $state_file"
        return 1
    fi
}

# Function to setup environment from user input or defaults
setup_environment() {
    log "Setting up environment for cleanup..."
    
    # If deployment state wasn't loaded, use environment variables or prompt
    if [[ -z "${PROJECT_ID:-}" ]]; then
        if [[ -n "${1:-}" ]]; then
            export PROJECT_ID="$1"
        else
            echo -n "Enter Project ID: "
            read -r PROJECT_ID
            export PROJECT_ID
        fi
    fi
    
    # Set defaults for other variables if not loaded
    export REGION="${REGION:-us-central1}"
    export ZONE="${ZONE:-us-central1-a}"
    
    # If we don't have specific resource names, try to discover them
    if [[ -z "${BUCKET_NAME:-}" || -z "${RESULTS_BUCKET:-}" || -z "${FUNCTION_NAME:-}" ]]; then
        discover_resources
    fi
    
    # Configure gcloud
    gcloud config set project "${PROJECT_ID}" || true
    gcloud config set compute/region "${REGION}" || true
    gcloud config set compute/zone "${ZONE}" || true
    
    log "Environment configured for cleanup"
}

# Function to discover resources
discover_resources() {
    log "Discovering resources to clean up..."
    
    # Try to find function
    if [[ -z "${FUNCTION_NAME:-}" ]]; then
        local functions
        functions=$(gcloud functions list --gen2 --regions="${REGION}" --filter="name:analyze-content-quality" --format="value(name)" 2>/dev/null || echo "")
        if [[ -n "$functions" ]]; then
            FUNCTION_NAME=$(basename "$functions")
            log "Found function: ${FUNCTION_NAME}"
        else
            FUNCTION_NAME="analyze-content-quality"
            warn "No function found, using default name: ${FUNCTION_NAME}"
        fi
    fi
    
    # Try to find buckets
    if [[ -z "${BUCKET_NAME:-}" || -z "${RESULTS_BUCKET:-}" ]]; then
        local buckets
        buckets=$(gsutil ls -p "${PROJECT_ID}" 2>/dev/null | grep -E "(content-analysis|quality-results)" || echo "")
        
        for bucket in $buckets; do
            bucket_name=$(basename "$bucket" | sed 's/\/$//')
            if [[ "$bucket_name" =~ content-analysis.* ]]; then
                BUCKET_NAME="$bucket_name"
                log "Found content bucket: ${BUCKET_NAME}"
            elif [[ "$bucket_name" =~ quality-results.* ]]; then
                RESULTS_BUCKET="$bucket_name"
                log "Found results bucket: ${RESULTS_BUCKET}"
            fi
        done
        
        # Set defaults if not found
        if [[ -z "${BUCKET_NAME:-}" ]]; then
            warn "Content bucket not found, cleanup may be incomplete"
        fi
        if [[ -z "${RESULTS_BUCKET:-}" ]]; then
            warn "Results bucket not found, cleanup may be incomplete"
        fi
    fi
}

# Function to validate prerequisites
validate_prerequisites() {
    log "Validating prerequisites..."
    
    # Check if gcloud CLI is installed
    if ! command_exists gcloud; then
        error "Google Cloud CLI (gcloud) is not installed."
        exit 1
    fi
    
    # Check authentication
    check_auth
    
    # Check if gsutil is available
    if ! command_exists gsutil; then
        error "gsutil is not available."
        exit 1
    fi
    
    success "Prerequisites validated"
}

# Function to confirm cleanup
confirm_cleanup() {
    echo
    warn "This will DELETE the following resources:"
    [[ -n "${FUNCTION_NAME:-}" ]] && echo "  - Cloud Function: ${FUNCTION_NAME}"
    [[ -n "${BUCKET_NAME:-}" ]] && echo "  - Content Bucket: gs://${BUCKET_NAME} (and all contents)"
    [[ -n "${RESULTS_BUCKET:-}" ]] && echo "  - Results Bucket: gs://${RESULTS_BUCKET} (and all contents)"
    echo "  - Local files: content-quality-function/, sample-content/, .deployment_state"
    
    if [[ "${DELETE_PROJECT:-}" == "true" ]]; then
        echo "  - ENTIRE PROJECT: ${PROJECT_ID}"
    fi
    
    echo
    warn "This action CANNOT be undone!"
    echo
    
    if [[ "${FORCE_DELETE:-}" == "true" ]]; then
        log "Force delete enabled, skipping confirmation"
        return 0
    fi
    
    echo -n "Are you sure you want to continue? (type 'yes' to confirm): "
    read -r confirmation
    
    if [[ "$confirmation" != "yes" ]]; then
        log "Cleanup cancelled by user"
        exit 0
    fi
    
    success "Cleanup confirmed"
}

# Function to delete Cloud Function
delete_function() {
    if [[ -z "${FUNCTION_NAME:-}" ]]; then
        warn "No function name specified, skipping function deletion"
        return 0
    fi
    
    log "Deleting Cloud Function: ${FUNCTION_NAME}"
    
    # Check if function exists
    if gcloud functions describe "${FUNCTION_NAME}" --gen2 --region="${REGION}" >/dev/null 2>&1; then
        if gcloud functions delete "${FUNCTION_NAME}" \
            --gen2 \
            --region="${REGION}" \
            --quiet; then
            success "Function deleted: ${FUNCTION_NAME}"
        else
            error "Failed to delete function: ${FUNCTION_NAME}"
            return 1
        fi
    else
        warn "Function ${FUNCTION_NAME} not found, skipping"
    fi
}

# Function to delete storage buckets
delete_storage_buckets() {
    local buckets_to_delete=()
    
    # Add buckets to deletion list if they exist
    [[ -n "${BUCKET_NAME:-}" ]] && buckets_to_delete+=("${BUCKET_NAME}")
    [[ -n "${RESULTS_BUCKET:-}" ]] && buckets_to_delete+=("${RESULTS_BUCKET}")
    
    if [[ ${#buckets_to_delete[@]} -eq 0 ]]; then
        warn "No bucket names specified, skipping bucket deletion"
        return 0
    fi
    
    for bucket in "${buckets_to_delete[@]}"; do
        log "Deleting bucket and contents: gs://${bucket}"
        
        # Check if bucket exists
        if gsutil ls -b "gs://${bucket}" >/dev/null 2>&1; then
            # Delete all objects in bucket (including versions)
            log "Removing all objects from gs://${bucket}..."
            if gsutil -m rm -r "gs://${bucket}/**" 2>/dev/null || true; then
                log "Objects removed from gs://${bucket}"
            fi
            
            # Delete bucket
            if gsutil rb "gs://${bucket}"; then
                success "Bucket deleted: gs://${bucket}"
            else
                error "Failed to delete bucket: gs://${bucket}"
                return 1
            fi
        else
            warn "Bucket gs://${bucket} not found, skipping"
        fi
    done
}

# Function to clean up local files
cleanup_local_files() {
    log "Cleaning up local files and directories..."
    
    local items_to_delete=(
        "./content-quality-function"
        "./sample-content"
        "./.deployment_state"
    )
    
    for item in "${items_to_delete[@]}"; do
        if [[ -e "$item" ]]; then
            log "Removing: $item"
            rm -rf "$item"
        fi
    done
    
    success "Local files cleaned up"
}

# Function to delete project (optional)
delete_project() {
    if [[ "${DELETE_PROJECT:-}" != "true" ]]; then
        log "Project deletion not requested, skipping"
        return 0
    fi
    
    log "Deleting project: ${PROJECT_ID}"
    warn "This will delete the ENTIRE project and ALL resources within it!"
    
    # Additional confirmation for project deletion
    echo -n "Type the project ID '${PROJECT_ID}' to confirm project deletion: "
    read -r project_confirmation
    
    if [[ "$project_confirmation" != "${PROJECT_ID}" ]]; then
        error "Project ID confirmation failed. Project deletion cancelled."
        return 1
    fi
    
    if gcloud projects delete "${PROJECT_ID}" --quiet; then
        success "Project deletion initiated: ${PROJECT_ID}"
        log "Note: Project deletion may take several minutes to complete"
    else
        error "Failed to delete project: ${PROJECT_ID}"
        return 1
    fi
}

# Function to verify cleanup
verify_cleanup() {
    log "Verifying cleanup completion..."
    
    local cleanup_issues=0
    
    # Check if function still exists
    if [[ -n "${FUNCTION_NAME:-}" ]]; then
        if gcloud functions describe "${FUNCTION_NAME}" --gen2 --region="${REGION}" >/dev/null 2>&1; then
            warn "Function ${FUNCTION_NAME} still exists"
            ((cleanup_issues++))
        fi
    fi
    
    # Check if buckets still exist
    for bucket in "${BUCKET_NAME:-}" "${RESULTS_BUCKET:-}"; do
        if [[ -n "$bucket" ]] && gsutil ls -b "gs://${bucket}" >/dev/null 2>&1; then
            warn "Bucket gs://${bucket} still exists"
            ((cleanup_issues++))
        fi
    done
    
    # Check if local files still exist
    local local_files=("./content-quality-function" "./sample-content" "./.deployment_state")
    for file in "${local_files[@]}"; do
        if [[ -e "$file" ]]; then
            warn "Local file/directory still exists: $file"
            ((cleanup_issues++))
        fi
    done
    
    if [[ $cleanup_issues -eq 0 ]]; then
        success "Cleanup verification passed - all resources removed"
    else
        warn "Cleanup verification found $cleanup_issues issues"
        warn "Some resources may still exist - manual cleanup may be required"
    fi
}

# Function to display cleanup summary
display_cleanup_summary() {
    echo
    success "Cleanup completed!"
    echo
    echo "=== CLEANUP SUMMARY ==="
    echo "Project ID: ${PROJECT_ID}"
    [[ -n "${FUNCTION_NAME:-}" ]] && echo "Function: ${FUNCTION_NAME} - DELETED"
    [[ -n "${BUCKET_NAME:-}" ]] && echo "Content Bucket: gs://${BUCKET_NAME} - DELETED"
    [[ -n "${RESULTS_BUCKET:-}" ]] && echo "Results Bucket: gs://${RESULTS_BUCKET} - DELETED"
    echo "Local Files: DELETED"
    
    if [[ "${DELETE_PROJECT:-}" == "true" ]]; then
        echo "Project: ${PROJECT_ID} - DELETION INITIATED"
    fi
    
    echo
    echo "=== NEXT STEPS ==="
    if [[ "${DELETE_PROJECT:-}" != "true" ]]; then
        echo "1. The project ${PROJECT_ID} still exists"
        echo "2. You may want to disable APIs to avoid charges:"
        echo "   gcloud services disable cloudfunctions.googleapis.com aiplatform.googleapis.com --project=${PROJECT_ID}"
        echo "3. To delete the entire project:"
        echo "   gcloud projects delete ${PROJECT_ID}"
    else
        echo "1. Project deletion is in progress and may take several minutes"
        echo "2. Verify project deletion: gcloud projects describe ${PROJECT_ID}"
    fi
    echo
    success "Content Quality Scoring system resources have been cleaned up!"
}

# Main cleanup function
main() {
    log "Starting Content Quality Scoring cleanup..."
    
    validate_prerequisites
    
    # Try to load deployment state first
    if ! load_deployment_state; then
        setup_environment "$@"
    fi
    
    confirm_cleanup
    delete_function
    delete_storage_buckets
    cleanup_local_files
    delete_project
    verify_cleanup
    display_cleanup_summary
}

# Error handling
trap 'error "Cleanup failed at line $LINENO. Exit code: $?"' ERR

# Check for help flag
if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    echo "Content Quality Scoring Cleanup Script"
    echo
    echo "Usage: $0 [PROJECT_ID] [options]"
    echo
    echo "Options:"
    echo "  --force              Skip confirmation prompts"
    echo "  --delete-project     Delete the entire GCP project"
    echo "  --help, -h           Show this help message"
    echo
    echo "Environment Variables:"
    echo "  PROJECT_ID          - GCP Project ID to clean up"
    echo "  REGION              - GCP Region (default: us-central1)"
    echo "  FORCE_DELETE        - Set to 'true' to skip confirmations"
    echo "  DELETE_PROJECT      - Set to 'true' to delete entire project"
    echo
    echo "Examples:"
    echo "  # Interactive cleanup (loads from .deployment_state if available)"
    echo "  $0"
    echo
    echo "  # Cleanup specific project"
    echo "  $0 my-content-project"
    echo
    echo "  # Force cleanup without prompts"
    echo "  FORCE_DELETE=true $0 my-content-project"
    echo
    echo "  # Delete entire project"
    echo "  DELETE_PROJECT=true $0 my-content-project"
    echo
    echo "  # Combine options"
    echo "  FORCE_DELETE=true DELETE_PROJECT=true $0 my-content-project"
    echo
    echo "Note: This script will attempt to load resource names from .deployment_state"
    echo "      if available, otherwise it will try to discover them automatically."
    exit 0
fi

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --force)
            export FORCE_DELETE=true
            shift
            ;;
        --delete-project)
            export DELETE_PROJECT=true
            shift
            ;;
        --help|-h)
            # Already handled above
            shift
            ;;
        *)
            # Assume it's a project ID if no PROJECT_ID is set
            if [[ -z "${PROJECT_ID:-}" ]]; then
                export PROJECT_ID="$1"
            fi
            shift
            ;;
    esac
done

# Run main function
main "$@"