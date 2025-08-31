#!/bin/bash

# ==============================================================================
# GCP Basic Application Logging with Cloud Functions - Cleanup Script
# ==============================================================================
# This script safely removes all resources created by the deployment script
# including the Cloud Function, project (optionally), and temporary files.
#
# Prerequisites:
# - Google Cloud CLI installed and authenticated
# - Deployment completed (deployment_info.env file exists)
# ==============================================================================

set -euo pipefail  # Exit on error, undefined vars, pipe failures

# Color codes for output formatting
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Script configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"
readonly LOG_FILE="${SCRIPT_DIR}/destroy.log"
readonly DEPLOYMENT_INFO="${SCRIPT_DIR}/deployment_info.env"

# Cleanup configuration (can be overridden by command line)
FORCE_CLEANUP=${FORCE_CLEANUP:-false}
DELETE_PROJECT=${DELETE_PROJECT:-false}
INTERACTIVE=${INTERACTIVE:-true}

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1" | tee -a "$LOG_FILE"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" | tee -a "$LOG_FILE"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE"
}

# Error handling
handle_error() {
    local exit_code=$?
    log_error "Cleanup script encountered an error (exit code: $exit_code)"
    log_warning "Some resources may not have been fully cleaned up"
    log_info "You may need to manually clean up remaining resources in the Google Cloud Console"
    exit $exit_code
}

trap handle_error ERR

# Validation functions
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "Google Cloud CLI (gcloud) is not installed or not in PATH"
        log_info "Please install gcloud: https://cloud.google.com/sdk/docs/install"
        exit 1
    fi
    
    # Check if authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 &> /dev/null; then
        log_error "Not authenticated with Google Cloud"
        log_info "Please run: gcloud auth login"
        exit 1
    fi
    
    log_success "Prerequisites check completed"
}

load_deployment_info() {
    log_info "Loading deployment information..."
    
    if [[ ! -f "$DEPLOYMENT_INFO" ]]; then
        log_warning "Deployment info file not found: $DEPLOYMENT_INFO"
        log_info "This may indicate that the deployment was not completed or files were moved"
        
        if [[ "$FORCE_CLEANUP" != "true" ]]; then
            log_error "Cannot proceed without deployment information. Use --force to override."
            exit 1
        else
            log_warning "Force mode enabled, will attempt cleanup with manual input"
            return 1
        fi
    fi
    
    # Source deployment info
    source "$DEPLOYMENT_INFO"
    
    # Validate required variables
    local required_vars=("PROJECT_ID" "REGION" "FUNCTION_NAME")
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            log_error "Missing required variable: $var"
            exit 1
        fi
    done
    
    log_success "Loaded deployment information:"
    log_info "  Project ID: $PROJECT_ID"
    log_info "  Region: $REGION"
    log_info "  Function Name: $FUNCTION_NAME"
    
    return 0
}

get_manual_input() {
    log_info "Gathering deployment information manually..."
    
    # Get current project if not set
    if [[ -z "${PROJECT_ID:-}" ]]; then
        PROJECT_ID=$(gcloud config get-value project 2>/dev/null || echo "")
        if [[ -z "$PROJECT_ID" ]]; then
            read -p "Enter Google Cloud Project ID: " PROJECT_ID
        fi
    fi
    
    # Get region with default
    if [[ -z "${REGION:-}" ]]; then
        REGION=$(gcloud config get-value compute/region 2>/dev/null || echo "us-central1")
        read -p "Enter region [$REGION]: " region_input
        REGION=${region_input:-$REGION}
    fi
    
    # Get function name with default
    if [[ -z "${FUNCTION_NAME:-}" ]]; then
        FUNCTION_NAME="logging-demo-function"
        read -p "Enter function name [$FUNCTION_NAME]: " function_input
        FUNCTION_NAME=${function_input:-$FUNCTION_NAME}
    fi
    
    log_info "Using manual configuration:"
    log_info "  Project ID: $PROJECT_ID"
    log_info "  Region: $REGION" 
    log_info "  Function Name: $FUNCTION_NAME"
}

confirm_deletion() {
    if [[ "$INTERACTIVE" != "true" ]] || [[ "$FORCE_CLEANUP" == "true" ]]; then
        return 0
    fi
    
    log_warning "This will delete the following resources:"
    log_warning "  - Cloud Function: $FUNCTION_NAME in $REGION"
    
    if [[ "$DELETE_PROJECT" == "true" ]]; then
        log_warning "  - Entire Google Cloud Project: $PROJECT_ID"
        log_warning "    ⚠️  This will delete ALL resources in the project!"
    fi
    
    echo
    read -p "Are you sure you want to continue? (yes/no): " confirm
    
    case "$confirm" in
        yes|YES|y|Y)
            log_info "Proceeding with cleanup..."
            ;;
        *)
            log_info "Cleanup cancelled by user"
            exit 0
            ;;
    esac
}

delete_cloud_function() {
    log_info "Deleting Cloud Function: $FUNCTION_NAME"
    
    # Check if function exists
    if ! gcloud functions describe "$FUNCTION_NAME" --region "$REGION" &>/dev/null; then
        log_warning "Function $FUNCTION_NAME not found in region $REGION"
        return 0
    fi
    
    # Delete the function
    if gcloud functions delete "$FUNCTION_NAME" \
        --region "$REGION" \
        --quiet; then
        log_success "Deleted Cloud Function: $FUNCTION_NAME"
    else
        log_error "Failed to delete Cloud Function: $FUNCTION_NAME"
        log_warning "You may need to delete it manually from the console"
        return 1
    fi
    
    # Wait for deletion to complete
    log_info "Waiting for function deletion to complete..."
    local timeout=60
    local elapsed=0
    
    while gcloud functions describe "$FUNCTION_NAME" --region "$REGION" &>/dev/null; do
        if [[ $elapsed -ge $timeout ]]; then
            log_warning "Function deletion is taking longer than expected"
            break
        fi
        sleep 5
        elapsed=$((elapsed + 5))
    done
    
    log_success "Cloud Function deletion completed"
}

delete_project() {
    if [[ "$DELETE_PROJECT" != "true" ]]; then
        log_info "Skipping project deletion (use --delete-project to enable)"
        return 0
    fi
    
    log_warning "Deleting entire project: $PROJECT_ID"
    log_warning "This action is IRREVERSIBLE and will delete ALL resources in the project!"
    
    if [[ "$INTERACTIVE" == "true" ]] && [[ "$FORCE_CLEANUP" != "true" ]]; then
        echo
        read -p "Type the project ID to confirm deletion [$PROJECT_ID]: " confirm_project
        
        if [[ "$confirm_project" != "$PROJECT_ID" ]]; then
            log_error "Project ID confirmation failed. Aborting project deletion."
            return 1
        fi
    fi
    
    # Delete the project
    if gcloud projects delete "$PROJECT_ID" --quiet; then
        log_success "Project deletion initiated: $PROJECT_ID"
        log_info "Project deletion may take several minutes to complete"
    else
        log_error "Failed to delete project: $PROJECT_ID"
        log_warning "You may need to delete it manually from the console"
        return 1
    fi
}

cleanup_local_files() {
    log_info "Cleaning up local files..."
    
    local files_to_remove=(
        "$DEPLOYMENT_INFO"
        "${SCRIPT_DIR}/tmp"
        "${SCRIPT_DIR}/*.env"
    )
    
    local removed_count=0
    
    for file_pattern in "${files_to_remove[@]}"; do
        if [[ -e "$file_pattern" ]] || [[ -d "$file_pattern" ]]; then
            if rm -rf "$file_pattern" 2>/dev/null; then
                log_info "Removed: $(basename "$file_pattern")"
                removed_count=$((removed_count + 1))
            else
                log_warning "Failed to remove: $file_pattern"
            fi
        fi
    done
    
    if [[ $removed_count -gt 0 ]]; then
        log_success "Cleaned up $removed_count local files/directories"
    else
        log_info "No local files found to clean up"
    fi
}

verify_cleanup() {
    log_info "Verifying cleanup completion..."
    
    # Check if function still exists
    if gcloud functions describe "$FUNCTION_NAME" --region "$REGION" &>/dev/null; then
        log_warning "Function $FUNCTION_NAME still exists in $REGION"
        log_info "It may take a few more minutes for deletion to complete"
    else
        log_success "Function $FUNCTION_NAME has been successfully deleted"
    fi
    
    # Check if project still exists (if we tried to delete it)
    if [[ "$DELETE_PROJECT" == "true" ]]; then
        if gcloud projects describe "$PROJECT_ID" &>/dev/null; then
            log_info "Project $PROJECT_ID deletion is in progress..."
        else
            log_success "Project $PROJECT_ID has been deleted"
        fi
    fi
    
    # Check local files
    if [[ ! -f "$DEPLOYMENT_INFO" ]]; then
        log_success "Local deployment files have been cleaned up"
    else
        log_warning "Some local files may still exist"
    fi
    
    log_success "Cleanup verification completed"
}

display_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Clean up resources created by the GCP Cloud Functions logging demo deployment.

OPTIONS:
    -f, --force                Skip confirmation prompts
    --delete-project           Delete the entire Google Cloud project
    --non-interactive          Run without user interaction
    -h, --help                 Display this help message
    --dry-run                  Show what would be deleted without executing

ENVIRONMENT VARIABLES:
    FORCE_CLEANUP              Skip confirmation prompts (true/false)
    DELETE_PROJECT             Delete the entire project (true/false)
    INTERACTIVE                Enable interactive prompts (true/false)

EXAMPLES:
    $0                         # Interactive cleanup (function only)
    $0 --force                 # Force cleanup without prompts
    $0 --delete-project        # Delete entire project (with confirmation)
    $0 --force --delete-project # Force delete entire project
    $0 --dry-run               # Show what would be deleted

SAFETY FEATURES:
    - Requires explicit confirmation for destructive actions
    - Validates deployment information before proceeding
    - Provides detailed logging of all operations
    - Graceful error handling with partial cleanup support

EOF
}

# Main cleanup function
main() {
    local dry_run=false
    
    # Initialize log file
    echo "Cleanup started at $(date)" > "$LOG_FILE"
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -f|--force)
                FORCE_CLEANUP=true
                shift
                ;;
            --delete-project)
                DELETE_PROJECT=true
                shift
                ;;
            --non-interactive)
                INTERACTIVE=false
                shift
                ;;
            --dry-run)
                dry_run=true
                shift
                ;;
            -h|--help)
                display_usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                display_usage
                exit 1
                ;;
        esac
    done
    
    log_info "=== GCP Cloud Functions Logging Demo Cleanup ==="
    log_info "Force cleanup: $FORCE_CLEANUP"
    log_info "Delete project: $DELETE_PROJECT"
    log_info "Interactive mode: $INTERACTIVE"
    log_info "Dry run: $dry_run"
    
    # Load deployment configuration
    check_prerequisites
    
    if ! load_deployment_info; then
        if [[ "$FORCE_CLEANUP" == "true" ]]; then
            get_manual_input
        else
            exit 1
        fi
    fi
    
    if [[ "$dry_run" == "true" ]]; then
        log_info "DRY RUN: Would delete the following resources:"
        log_info "  - Cloud Function: $FUNCTION_NAME in $REGION"
        if [[ "$DELETE_PROJECT" == "true" ]]; then
            log_info "  - Google Cloud Project: $PROJECT_ID (ALL RESOURCES)"
        fi
        log_info "  - Local deployment files and directories"
        exit 0
    fi
    
    # Confirm deletion if interactive
    confirm_deletion
    
    # Execute cleanup steps
    if [[ "$DELETE_PROJECT" == "true" ]]; then
        # If deleting project, function will be deleted automatically
        delete_project
    else
        # Delete function individually
        delete_cloud_function
    fi
    
    cleanup_local_files
    verify_cleanup
    
    log_success "=== Cleanup completed successfully! ==="
    
    if [[ "$DELETE_PROJECT" == "true" ]]; then
        log_info "Project deletion may take several minutes to fully complete."
        log_info "You can monitor the deletion status in the Google Cloud Console."
    else
        log_info "Cloud Function has been removed. Project and other resources remain."
        log_info "If you want to delete the entire project, run: $0 --delete-project"
    fi
    
    log_info "Full cleanup log: $LOG_FILE"
}

# Execute main function with all arguments
main "$@"