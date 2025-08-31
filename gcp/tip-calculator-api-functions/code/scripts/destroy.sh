#!/bin/bash

# Destroy script for Tip Calculator API with Cloud Functions
# This script removes all resources created by the deployment script

set -euo pipefail

# Color codes for output
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

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if gcloud CLI is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "gcloud CLI is not installed. Please install it from: https://cloud.google.com/sdk/docs/install"
        exit 1
    fi
    
    # Check if gcloud is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        log_error "gcloud is not authenticated. Please run: gcloud auth login"
        exit 1
    fi
    
    log_success "Prerequisites check completed"
}

# Function to load environment variables
load_environment() {
    log_info "Loading environment variables..."
    
    # Use existing environment variables or defaults from deployment
    export PROJECT_ID="${PROJECT_ID:-}"
    export REGION="${REGION:-us-central1}"
    export FUNCTION_NAME="${FUNCTION_NAME:-tip-calculator}"
    
    # If PROJECT_ID is not set, try to get from gcloud config
    if [ -z "$PROJECT_ID" ]; then
        PROJECT_ID=$(gcloud config get-value project 2>/dev/null || true)
        export PROJECT_ID
    fi
    
    # If still no PROJECT_ID, prompt user
    if [ -z "$PROJECT_ID" ]; then
        log_warning "No PROJECT_ID found in environment or gcloud config."
        read -p "Enter the Project ID to clean up: " PROJECT_ID
        export PROJECT_ID
        
        if [ -z "$PROJECT_ID" ]; then
            log_error "Project ID is required for cleanup"
            exit 1
        fi
    fi
    
    log_info "Project ID: ${PROJECT_ID}"
    log_info "Region: ${REGION}"
    log_info "Function Name: ${FUNCTION_NAME}"
    
    # Set gcloud project context
    gcloud config set project "${PROJECT_ID}" || {
        log_error "Failed to set project context. Please verify project ID."
        exit 1
    }
    
    log_success "Environment loaded successfully"
}

# Function to confirm destruction
confirm_destruction() {
    log_warning "=== DESTRUCTION CONFIRMATION ==="
    echo -e "${YELLOW}This will delete the following resources:${NC}"
    echo "- Cloud Function: ${FUNCTION_NAME}"
    echo "- Associated logs and monitoring data"
    echo "- Local source code files"
    echo
    echo -e "${RED}This action cannot be undone!${NC}"
    echo
    
    # Check if function exists before asking for confirmation
    if gcloud functions describe "${FUNCTION_NAME}" --region="${REGION}" &> /dev/null; then
        echo -e "${YELLOW}Function found:${NC}"
        gcloud functions describe "${FUNCTION_NAME}" --region="${REGION}" \
            --format="table(name,status,httpsTrigger.url)" 2>/dev/null || true
        echo
    else
        log_info "Function ${FUNCTION_NAME} not found in region ${REGION}"
    fi
    
    read -p "Are you sure you want to proceed? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Destruction cancelled by user"
        exit 0
    fi
    
    log_info "Proceeding with resource destruction..."
}

# Function to delete Cloud Function
delete_function() {
    log_info "Deleting Cloud Function..."
    
    # Check if function exists
    if gcloud functions describe "${FUNCTION_NAME}" --region="${REGION}" &> /dev/null; then
        log_info "Found function ${FUNCTION_NAME}, proceeding with deletion..."
        
        # Delete the Cloud Function
        gcloud functions delete "${FUNCTION_NAME}" \
            --region="${REGION}" \
            --quiet || {
            log_error "Failed to delete Cloud Function ${FUNCTION_NAME}"
            return 1
        }
        
        log_success "Cloud Function ${FUNCTION_NAME} deleted successfully"
        
        # Wait a moment for deletion to propagate
        sleep 5
        
        # Verify deletion
        if ! gcloud functions describe "${FUNCTION_NAME}" --region="${REGION}" &> /dev/null; then
            log_success "Confirmed: Function ${FUNCTION_NAME} has been deleted"
        else
            log_warning "Function may still be in deletion process"
        fi
    else
        log_info "Function ${FUNCTION_NAME} not found in region ${REGION}, skipping deletion"
    fi
}

# Function to clean up local files
cleanup_local_files() {
    log_info "Cleaning up local files..."
    
    # List of files and directories to clean up
    local cleanup_items=(
        "tip-calculator-function"
        "test_data.json"
    )
    
    for item in "${cleanup_items[@]}"; do
        if [ -e "$item" ]; then
            log_info "Removing $item..."
            rm -rf "$item"
            log_success "Removed $item"
        else
            log_info "$item not found, skipping"
        fi
    done
    
    log_success "Local file cleanup completed"
}

# Function to clean up cloud logs (optional)
cleanup_logs() {
    log_info "Cleaning up Cloud Function logs (optional)..."
    
    # Check if there are logs to clean up
    local log_filter="resource.type=\"cloud_function\" AND resource.labels.function_name=\"${FUNCTION_NAME}\""
    
    # Note: We don't actually delete logs as they may contain valuable debugging information
    # and they will automatically expire based on retention policies
    log_info "Cloud Function logs will be retained according to your project's log retention policy"
    log_info "If you need to manually delete logs, use the Cloud Console or gcloud logging commands"
    
    log_success "Log cleanup information provided"
}

# Function to verify cleanup
verify_cleanup() {
    log_info "Verifying cleanup..."
    
    # Check if function still exists
    if gcloud functions describe "${FUNCTION_NAME}" --region="${REGION}" &> /dev/null; then
        log_warning "Function ${FUNCTION_NAME} still exists - deletion may be in progress"
    else
        log_success "Confirmed: Function ${FUNCTION_NAME} has been deleted"
    fi
    
    # Check local files
    local remaining_files=()
    if [ -d "tip-calculator-function" ]; then
        remaining_files+=("tip-calculator-function")
    fi
    if [ -f "test_data.json" ]; then
        remaining_files+=("test_data.json")
    fi
    
    if [ ${#remaining_files[@]} -gt 0 ]; then
        log_warning "Some local files remain: ${remaining_files[*]}"
    else
        log_success "All local files cleaned up successfully"
    fi
    
    log_success "Cleanup verification completed"
}

# Function to handle project deletion (optional)
handle_project_deletion() {
    log_info "Checking if entire project should be deleted..."
    
    # Only offer project deletion if project name suggests it was created for this demo
    if [[ "$PROJECT_ID" == tip-calc-* ]]; then
        echo
        log_warning "This appears to be a project created specifically for the tip calculator demo."
        read -p "Do you want to delete the entire project ${PROJECT_ID}? (y/N): " -n 1 -r
        echo
        
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            log_info "Deleting project ${PROJECT_ID}..."
            
            gcloud projects delete "${PROJECT_ID}" --quiet || {
                log_error "Failed to delete project ${PROJECT_ID}"
                log_info "You may need to delete it manually from the Cloud Console"
                return 1
            }
            
            log_success "Project ${PROJECT_ID} deletion initiated"
            log_info "Note: Project deletion may take several minutes to complete"
            
            return 0
        fi
    fi
    
    log_info "Project ${PROJECT_ID} will be retained"
}

# Function to display cleanup summary
display_summary() {
    log_success "=== Cleanup Summary ==="
    echo -e "${GREEN}Resources cleaned up:${NC}"
    echo "  ✅ Cloud Function: ${FUNCTION_NAME}"
    echo "  ✅ Local source files"
    echo "  ✅ Temporary test files"
    echo
    echo -e "${BLUE}Retained resources:${NC}"
    echo "  - Project: ${PROJECT_ID} (unless manually deleted)"
    echo "  - Enabled APIs (will not incur charges without active resources)"
    echo "  - Cloud Function logs (subject to retention policy)"
    echo
    echo -e "${GREEN}Estimated cost savings:${NC} All Cloud Function charges eliminated"
    echo -e "${YELLOW}Note:${NC} Some API enablement may remain but does not incur charges"
}

# Function for safe resource deletion with retries
safe_delete_with_retry() {
    local resource_type="$1"
    local delete_command="$2"
    local max_retries=3
    local retry_count=0
    
    while [ $retry_count -lt $max_retries ]; do
        if eval "$delete_command"; then
            log_success "$resource_type deleted successfully"
            return 0
        else
            retry_count=$((retry_count + 1))
            if [ $retry_count -lt $max_retries ]; then
                log_warning "$resource_type deletion failed, retrying in 10 seconds... (attempt $retry_count/$max_retries)"
                sleep 10
            else
                log_error "$resource_type deletion failed after $max_retries attempts"
                return 1
            fi
        fi
    done
}

# Main cleanup function
main() {
    log_info "Starting cleanup of Tip Calculator API resources..."
    
    check_prerequisites
    load_environment
    confirm_destruction
    
    # Perform cleanup operations
    delete_function
    cleanup_local_files
    cleanup_logs
    verify_cleanup
    handle_project_deletion
    
    display_summary
    
    log_success "Cleanup completed successfully!"
    log_info "Thank you for using the Tip Calculator API demo"
}

# Error handling for the main function
cleanup_on_error() {
    log_error "Cleanup script encountered an error"
    log_info "Some resources may not have been cleaned up completely"
    log_info "Please check the Google Cloud Console for any remaining resources"
    exit 1
}

trap cleanup_on_error ERR

# Check if script is being sourced or executed
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi