#!/bin/bash

# Simple Voting System with Cloud Functions and Firestore - Cleanup Script
# This script removes all resources created by the deployment script

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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

# Banner
echo -e "${RED}"
echo "========================================================"
echo "  Simple Voting System - Cleanup Script"
echo "  WARNING: This will delete all deployed resources!"
echo "========================================================"
echo -e "${NC}"

# State directory
STATE_DIR="${HOME}/.voting-system-state"
DEPLOYMENT_ENV="${STATE_DIR}/deployment.env"

# Check if deployment state exists
check_deployment_state() {
    log_info "Checking deployment state..."
    
    if [[ ! -f "${DEPLOYMENT_ENV}" ]]; then
        log_error "Deployment state file not found: ${DEPLOYMENT_ENV}"
        log_info "This usually means the deployment was not completed successfully"
        log_info "or the cleanup script was already run."
        
        # Try to find resources manually
        log_info "Attempting to find resources manually..."
        manual_cleanup
        exit 0
    fi
    
    # Source deployment environment
    source "${DEPLOYMENT_ENV}"
    
    log_info "Found deployment state:"
    log_info "- Project ID: ${PROJECT_ID}"
    log_info "- Region: ${REGION}"
    log_info "- Function Name: ${FUNCTION_NAME}"
    log_info "- Deployment Time: ${DEPLOYMENT_TIME}"
    
    log_success "Deployment state loaded successfully"
}

# Manual cleanup when deployment state is not available
manual_cleanup() {
    log_warning "Attempting manual cleanup without deployment state..."
    
    # Check if gcloud is available and authenticated
    if ! command -v gcloud &> /dev/null; then
        log_error "Google Cloud CLI not available for manual cleanup"
        exit 1
    fi
    
    local current_project=$(gcloud config get-value project 2>/dev/null || echo "")
    if [[ -z "${current_project}" ]]; then
        log_error "No active Google Cloud project set"
        exit 1
    fi
    
    log_info "Searching for voting system resources in project: ${current_project}"
    
    # Look for functions with vote-handler pattern
    local functions=$(gcloud functions list --format="value(name)" 2>/dev/null | grep "vote-handler" || true)
    
    if [[ -n "${functions}" ]]; then
        log_info "Found functions that may be from this deployment:"
        echo "${functions}"
        
        read -p "Do you want to delete these functions? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            for func in ${functions}; do
                local region=$(gcloud functions describe "${func}" --format="value(location)" 2>/dev/null || echo "us-central1")
                delete_function "${func}" "${region}"
            done
        fi
    else
        log_info "No voting system functions found"
    fi
    
    log_info "Manual cleanup completed. Some resources may require manual deletion in the console."
}

# Confirmation prompt
confirm_destruction() {
    echo ""
    log_warning "This action will permanently delete the following resources:"
    echo "- Cloud Functions: ${FUNCTION_NAME}-submit, ${FUNCTION_NAME}-results"
    echo "- Firestore data (if you choose to delete the database)"
    echo "- Web interface file (voting-interface.html)"
    echo "- Project: ${PROJECT_ID} (if you choose to delete it)"
    echo ""
    
    read -p "Are you sure you want to continue? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Cleanup cancelled by user"
        exit 0
    fi
    
    log_info "Proceeding with resource cleanup..."
}

# Delete a Cloud Function
delete_function() {
    local function_name="$1"
    local region="$2"
    
    log_info "Deleting function: ${function_name} in region ${region}..."
    
    if gcloud functions describe "${function_name}" --region="${region}" &> /dev/null; then
        if gcloud functions delete "${function_name}" --region="${region}" --quiet; then
            log_success "Deleted function: ${function_name}"
        else
            log_error "Failed to delete function: ${function_name}"
            return 1
        fi
    else
        log_warning "Function ${function_name} not found or already deleted"
    fi
}

# Delete Cloud Functions
delete_functions() {
    log_info "Deleting Cloud Functions..."
    
    # Delete vote submission function
    delete_function "${FUNCTION_NAME}-submit" "${REGION}"
    
    # Delete results function
    delete_function "${FUNCTION_NAME}-results" "${REGION}"
    
    log_success "Cloud Functions cleanup completed"
}

# Clean up Firestore data
cleanup_firestore() {
    log_info "Cleaning up Firestore data..."
    
    echo ""
    log_warning "Firestore database cleanup options:"
    echo "1. Keep database, delete collections (votes, voteCounts)"
    echo "2. Delete entire Firestore database"
    echo "3. Skip Firestore cleanup"
    
    read -p "Choose option (1/2/3): " -n 1 -r
    echo
    
    case $REPLY in
        1)
            log_info "Deleting Firestore collections..."
            delete_firestore_collections
            ;;
        2)
            log_warning "Database deletion must be done manually in the Google Cloud Console"
            log_info "Visit: https://console.cloud.google.com/firestore/databases?project=${PROJECT_ID}"
            log_info "Select the database and click 'Delete Database'"
            ;;
        3)
            log_info "Skipping Firestore cleanup"
            ;;
        *)
            log_warning "Invalid option. Skipping Firestore cleanup"
            ;;
    esac
}

# Delete Firestore collections
delete_firestore_collections() {
    log_info "Attempting to delete Firestore collections..."
    
    # Try to use gcloud firestore to delete documents
    # Note: This requires the gcloud firestore commands to be available
    
    local collections=("votes" "voteCounts")
    
    for collection in "${collections[@]}"; do
        log_info "Deleting collection: ${collection}"
        
        # Check if collection exists and has documents
        local doc_count=$(gcloud firestore databases collections list --database="(default)" --format="value(collectionIds)" 2>/dev/null | grep -c "^${collection}$" || echo "0")
        
        if [[ "${doc_count}" -gt 0 ]]; then
            log_info "Found collection ${collection}, attempting deletion..."
            
            # Delete all documents in the collection
            # Note: This is a simplified approach - in production you'd want to batch delete
            if gcloud firestore databases collections delete "${collection}" --database="(default)" --recursive --quiet 2>/dev/null; then
                log_success "Deleted collection: ${collection}"
            else
                log_warning "Could not delete collection ${collection} via CLI"
                log_info "You may need to delete it manually in the console"
            fi
        else
            log_info "Collection ${collection} not found or already empty"
        fi
    done
}

# Delete web interface
delete_web_interface() {
    log_info "Deleting web interface..."
    
    if [[ -f "voting-interface.html" ]]; then
        if rm -f "voting-interface.html"; then
            log_success "Deleted voting-interface.html"
        else
            log_error "Failed to delete voting-interface.html"
        fi
    else
        log_info "Web interface file not found (may have been moved or deleted)"
    fi
}

# Clean up temporary directories
cleanup_temp_directories() {
    log_info "Cleaning up temporary directories..."
    
    # Clean up any temporary function directories
    if [[ -n "${FUNCTION_DIR:-}" && -d "${FUNCTION_DIR}" ]]; then
        log_info "Removing temporary function directory: ${FUNCTION_DIR}"
        rm -rf "${FUNCTION_DIR}"
        log_success "Temporary function directory removed"
    fi
    
    # Look for any temp directories that might have been left behind
    local temp_dirs=$(find /tmp -name "tmp.*" -type d -user "$(whoami)" 2>/dev/null | grep -E "(voting|function)" || true)
    
    if [[ -n "${temp_dirs}" ]]; then
        log_info "Found potential temporary directories from deployment:"
        echo "${temp_dirs}"
        
        read -p "Delete these directories? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            echo "${temp_dirs}" | while read -r dir; do
                if [[ -d "${dir}" ]]; then
                    rm -rf "${dir}"
                    log_success "Deleted: ${dir}"
                fi
            done
        fi
    fi
}

# Project deletion
handle_project_deletion() {
    echo ""
    log_warning "Project deletion options:"
    echo "1. Keep project (recommended if you have other resources)"
    echo "2. Delete entire project (WARNING: This deletes ALL resources in the project)"
    
    read -p "Choose option (1/2): " -n 1 -r
    echo
    
    case $REPLY in
        1)
            log_info "Keeping project: ${PROJECT_ID}"
            ;;
        2)
            log_warning "Deleting entire project: ${PROJECT_ID}"
            echo "This will delete ALL resources in the project, not just the voting system!"
            
            read -p "Are you absolutely sure? Type 'DELETE' to confirm: " -r
            if [[ $REPLY == "DELETE" ]]; then
                log_info "Initiating project deletion..."
                if gcloud projects delete "${PROJECT_ID}" --quiet; then
                    log_success "Project deletion initiated: ${PROJECT_ID}"
                    log_info "Project deletion may take several minutes to complete"
                else
                    log_error "Failed to delete project: ${PROJECT_ID}"
                fi
            else
                log_info "Project deletion cancelled"
            fi
            ;;
        *)
            log_info "Keeping project by default"
            ;;
    esac
}

# Clean up deployment state
cleanup_deployment_state() {
    log_info "Cleaning up deployment state..."
    
    if [[ -f "${DEPLOYMENT_ENV}" ]]; then
        # Create backup of deployment state
        local backup_file="${STATE_DIR}/deployment.env.backup.$(date +%s)"
        cp "${DEPLOYMENT_ENV}" "${backup_file}"
        log_info "Deployment state backed up to: ${backup_file}"
        
        # Remove current deployment state
        rm -f "${DEPLOYMENT_ENV}"
        log_success "Deployment state file removed"
    fi
    
    # Remove state directory if empty
    if [[ -d "${STATE_DIR}" ]] && [[ -z "$(ls -A "${STATE_DIR}")" ]]; then
        rmdir "${STATE_DIR}"
        log_success "State directory removed"
    elif [[ -d "${STATE_DIR}" ]]; then
        log_info "State directory contains other files, keeping it"
    fi
}

# Verify cleanup
verify_cleanup() {
    log_info "Verifying cleanup..."
    
    # Check if functions still exist
    local remaining_functions=$(gcloud functions list --format="value(name)" 2>/dev/null | grep "${FUNCTION_NAME}" || true)
    
    if [[ -n "${remaining_functions}" ]]; then
        log_warning "Some functions may still exist:"
        echo "${remaining_functions}"
    else
        log_success "No voting system functions found"
    fi
    
    # Check if web interface still exists
    if [[ -f "voting-interface.html" ]]; then
        log_warning "Web interface file still exists: voting-interface.html"
    else
        log_success "Web interface file removed"
    fi
    
    log_success "Cleanup verification completed"
}

# Print cleanup summary
print_cleanup_summary() {
    echo ""
    log_info "Cleanup Summary"
    echo "==============="
    
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    echo "Cleanup completed in ${duration} seconds"
    echo ""
    echo "Resources processed:"
    echo "- Cloud Functions: Deleted (if they existed)"
    echo "- Firestore: Handled based on user choice"
    echo "- Web Interface: Deleted (if it existed)"
    echo "- Project: Handled based on user choice"
    echo "- Deployment State: Cleaned up"
    echo ""
    
    if [[ -d "${STATE_DIR}" ]]; then
        echo "Note: Some backup files may remain in: ${STATE_DIR}"
    fi
    
    echo ""
    log_success "Cleanup process completed!"
}

# Main execution flow
main() {
    local start_time=$(date +%s)
    
    check_deployment_state
    
    # If we have deployment state, proceed with full cleanup
    if [[ -f "${DEPLOYMENT_ENV}" ]]; then
        source "${DEPLOYMENT_ENV}"
        confirm_destruction
        delete_functions
        cleanup_firestore
        delete_web_interface
        cleanup_temp_directories
        handle_project_deletion
        cleanup_deployment_state
        verify_cleanup
        print_cleanup_summary
    fi
}

# Handle script interruption
cleanup_on_interrupt() {
    echo ""
    log_warning "Cleanup interrupted by user"
    log_info "Some resources may not have been deleted"
    log_info "You can run this script again to continue cleanup"
    exit 1
}

trap cleanup_on_interrupt INT TERM

# Run main function
main "$@"