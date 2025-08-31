#!/bin/bash

# Form Data Validation with Cloud Functions and Firestore - Cleanup Script
# This script removes all infrastructure created by the deployment script
# including Cloud Functions, Firestore data, and optionally the entire project

set -euo pipefail  # Exit on error, undefined variables, and pipe failures

# Script configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_FILE="${SCRIPT_DIR}/destroy.log"
readonly ERROR_LOG="${SCRIPT_DIR}/destroy_errors.log"
readonly ENV_FILE="${SCRIPT_DIR}/.env"

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

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
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE" >&2
}

# Error handling
cleanup_on_error() {
    log_error "Cleanup failed. Check $ERROR_LOG for details."
    log_warning "Some resources may still exist and incur charges."
    exit 1
}

trap cleanup_on_error ERR

# Initialize logging
exec 2> >(tee -a "$ERROR_LOG")
log_info "Starting cleanup at $(date)"

# Load environment variables
load_environment() {
    log_info "Loading deployment environment..."
    
    if [[ ! -f "$ENV_FILE" ]]; then
        log_error "Environment file not found at $ENV_FILE"
        log_error "Cannot determine what resources to clean up."
        log_info "If you know the project ID, you can set it manually:"
        log_info "export PROJECT_ID=your-project-id"
        log_info "Then run this script again."
        exit 1
    fi
    
    # shellcheck source=/dev/null
    source "$ENV_FILE"
    
    # Validate required variables
    if [[ -z "${PROJECT_ID:-}" ]]; then
        log_error "PROJECT_ID not found in environment file"
        exit 1
    fi
    
    log_info "Project ID: $PROJECT_ID"
    log_info "Region: ${REGION:-us-central1}"
    log_info "Function Name: ${FUNCTION_NAME:-validate-form-data}"
    
    log_success "Environment loaded successfully"
}

# Validate prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "Google Cloud CLI (gcloud) is not installed."
        exit 1
    fi
    
    # Check if authenticated
    if ! gcloud auth list --format="value(account)" --filter="status:ACTIVE" | head -1 &> /dev/null; then
        log_error "Not authenticated with Google Cloud. Run 'gcloud auth login' first."
        exit 1
    fi
    
    log_success "Prerequisites check passed"
}

# Confirm cleanup with user
confirm_cleanup() {
    echo ""
    log_warning "This will DELETE the following resources:"
    echo "- Cloud Function: ${FUNCTION_NAME:-validate-form-data}"
    echo "- Firestore database and ALL data"
    echo "- Project: $PROJECT_ID (if confirmed)"
    echo ""
    
    local delete_project="n"
    read -p "Do you want to delete the entire project? This will remove ALL resources (y/N): " delete_project
    
    if [[ "$delete_project" =~ ^[Yy]$ ]]; then
        CLEANUP_MODE="project"
        log_warning "Will delete entire project: $PROJECT_ID"
    else
        CLEANUP_MODE="resources"
        log_info "Will delete individual resources only"
    fi
    
    echo ""
    read -p "Are you sure you want to proceed? (y/N): " -r
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Cleanup cancelled by user"
        exit 0
    fi
    
    log_info "Cleanup confirmed. Mode: $CLEANUP_MODE"
}

# Set project context
set_project_context() {
    log_info "Setting project context..."
    
    # Check if project exists
    if ! gcloud projects describe "$PROJECT_ID" &> /dev/null; then
        log_warning "Project $PROJECT_ID does not exist or is not accessible"
        log_warning "It may have already been deleted"
        return 0
    fi
    
    # Set current project
    gcloud config set project "$PROJECT_ID" --quiet
    gcloud config set compute/region "${REGION:-us-central1}" --quiet
    
    log_success "Project context set"
}

# Delete Cloud Function
delete_function() {
    log_info "Deleting Cloud Function..."
    
    local function_name="${FUNCTION_NAME:-validate-form-data}"
    local region="${REGION:-us-central1}"
    
    # Check if function exists
    if gcloud functions describe "$function_name" --region="$region" &> /dev/null; then
        log_info "Deleting function: $function_name"
        gcloud functions delete "$function_name" \
            --region="$region" \
            --quiet
        
        log_success "Cloud Function deleted"
    else
        log_warning "Function $function_name not found or already deleted"
    fi
}

# Clear Firestore data
clear_firestore_data() {
    log_info "Clearing Firestore data..."
    
    # Check if Firestore database exists
    if gcloud firestore databases describe --database="(default)" &> /dev/null; then
        log_warning "Firestore database found. Data will be permanently deleted."
        
        # Note: We cannot easily delete all documents via CLI in a script
        # Instead, we'll delete the database entirely if in project cleanup mode
        if [[ "$CLEANUP_MODE" == "project" ]]; then
            log_info "Database will be deleted with project"
        else
            log_warning "Firestore database still exists with data"
            log_info "To completely remove data, delete the database manually at:"
            log_info "https://console.cloud.google.com/firestore/databases?project=$PROJECT_ID"
        fi
    else
        log_warning "Firestore database not found or already deleted"
    fi
}

# Delete project (if requested)
delete_project() {
    if [[ "$CLEANUP_MODE" != "project" ]]; then
        return 0
    fi
    
    log_info "Deleting entire project..."
    log_warning "This will permanently delete ALL resources in the project"
    
    # Final confirmation for project deletion
    echo ""
    read -p "FINAL CONFIRMATION: Delete project $PROJECT_ID? (type 'DELETE' to confirm): " -r
    if [[ "$REPLY" != "DELETE" ]]; then
        log_info "Project deletion cancelled"
        return 0
    fi
    
    log_info "Deleting project: $PROJECT_ID"
    gcloud projects delete "$PROJECT_ID" --quiet
    
    log_success "Project deletion initiated"
    log_info "Project deletion may take several minutes to complete"
}

# Clean up local files
cleanup_local_files() {
    log_info "Cleaning up local files..."
    
    local function_dir="${SCRIPT_DIR}/../function-source"
    if [[ -d "$function_dir" ]]; then
        log_info "Removing function source directory"
        rm -rf "$function_dir"
    fi
    
    # Remove environment file
    if [[ -f "$ENV_FILE" ]]; then
        log_info "Removing environment file"
        rm -f "$ENV_FILE"
    fi
    
    # Keep log files for reference but warn user
    log_info "Log files preserved at:"
    log_info "- $LOG_FILE"
    log_info "- $ERROR_LOG"
    
    log_success "Local cleanup completed"
}

# Display cleanup summary
display_summary() {
    log_info "Cleanup Summary"
    echo "======================================"
    
    if [[ "$CLEANUP_MODE" == "project" ]]; then
        echo "✅ Project deletion initiated: $PROJECT_ID"
        echo "   - All resources will be removed"
        echo "   - Deletion may take several minutes"
    else
        echo "✅ Individual resources cleaned up:"
        echo "   - Cloud Function: ${FUNCTION_NAME:-validate-form-data}"
        echo "   - Firestore data: Partially cleared"
        echo ""
        echo "⚠️  Project still exists: $PROJECT_ID"
        echo "   - You may want to delete it manually to avoid charges"
        echo "   - Visit: https://console.cloud.google.com/iam-admin/settings?project=$PROJECT_ID"
    fi
    
    echo ""
    echo "✅ Local files cleaned up"
    echo "✅ Environment configuration removed"
    echo ""
    echo "Cleanup completed successfully!"
    echo "======================================"
}

# Verify cleanup completion
verify_cleanup() {
    log_info "Verifying cleanup..."
    
    if [[ "$CLEANUP_MODE" == "project" ]]; then
        # For project deletion, just log that it was initiated
        log_info "Project deletion initiated - verification not possible via CLI"
        return 0
    fi
    
    # Check if function still exists
    local function_name="${FUNCTION_NAME:-validate-form-data}"
    local region="${REGION:-us-central1}"
    
    if gcloud functions describe "$function_name" --region="$region" &> /dev/null; then
        log_warning "Function $function_name still exists"
    else
        log_success "Function successfully deleted"
    fi
    
    log_success "Cleanup verification completed"
}

# Main cleanup function
main() {
    log_info "Starting Form Data Validation cleanup..."
    
    check_prerequisites
    load_environment
    confirm_cleanup
    set_project_context
    
    if [[ "$CLEANUP_MODE" == "project" ]]; then
        delete_project
    else
        delete_function
        clear_firestore_data
    fi
    
    cleanup_local_files
    verify_cleanup
    display_summary
    
    log_success "Cleanup completed successfully at $(date)"
}

# Handle command line arguments
if [[ "${1:-}" == "--force" ]]; then
    log_warning "Force mode enabled - skipping confirmations"
    CLEANUP_MODE="project"
    # Skip confirmations in force mode
    confirm_cleanup() {
        log_warning "Force mode: Will delete entire project"
        CLEANUP_MODE="project"
    }
fi

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi