#!/bin/bash

# Color Palette Generator with Cloud Functions and Storage - Cleanup Script
# This script safely removes all resources created by the color palette generator deployment
# Version: 1.0
# Compatible with: Google Cloud SDK (gcloud CLI)

set -euo pipefail

# Colors for output formatting
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

# Error handler
error_exit() {
    log_error "$1"
    exit 1
}

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Validate prerequisites
validate_prerequisites() {
    log_info "Validating prerequisites for cleanup..."
    
    # Check if gcloud CLI is installed
    if ! command_exists gcloud; then
        error_exit "Google Cloud CLI (gcloud) is not installed. Cannot proceed with cleanup."
    fi
    
    # Check if gsutil is available
    if ! command_exists gsutil; then
        error_exit "gsutil is not available. Please ensure Google Cloud SDK is properly installed."
    fi
    
    # Check if user is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 > /dev/null 2>&1; then
        error_exit "Not authenticated with Google Cloud. Please run 'gcloud auth login' first."
    fi
    
    log_success "Prerequisites validated successfully"
}

# Load environment variables from deployment info or prompt user
setup_environment() {
    log_info "Setting up environment for cleanup..."
    
    # Try to load from deployment info file first
    local info_file="deployment-info.txt"
    if [[ -f "$info_file" ]]; then
        log_info "Found deployment info file, extracting configuration..."
        
        export PROJECT_ID=$(grep "Project ID:" "$info_file" | cut -d: -f2 | xargs)
        export REGION=$(grep "Region:" "$info_file" | cut -d: -f2 | xargs)
        export FUNCTION_NAME=$(grep "Function Name:" "$info_file" | cut -d: -f2 | xargs)
        export BUCKET_NAME=$(grep "Storage Bucket:" "$info_file" | cut -d: -f2 | xargs | sed 's/gs:\/\///')
        
        log_success "Configuration loaded from deployment info"
    else
        log_warning "Deployment info file not found. Using environment variables or defaults."
        
        # Use environment variables or prompt for required values
        if [[ -z "${PROJECT_ID:-}" ]]; then
            # Try to get current project
            PROJECT_ID=$(gcloud config get-value project 2>/dev/null || echo "")
            if [[ -z "$PROJECT_ID" ]]; then
                error_exit "PROJECT_ID not set and no current project configured. Please export PROJECT_ID variable."
            fi
        fi
        
        export PROJECT_ID="${PROJECT_ID}"
        export REGION="${REGION:-us-central1}"
        export FUNCTION_NAME="${FUNCTION_NAME:-generate-color-palette}"
        export BUCKET_NAME="${BUCKET_NAME:-}"
        
        if [[ -z "$BUCKET_NAME" ]]; then
            log_warning "BUCKET_NAME not specified. Will attempt to find buckets with 'color-palettes-' prefix."
        fi
    fi
    
    log_info "Cleanup configuration:"
    log_info "  Project ID: $PROJECT_ID"
    log_info "  Region: $REGION"
    log_info "  Function Name: $FUNCTION_NAME"
    log_info "  Storage Bucket: ${BUCKET_NAME:-'(will auto-detect)'}"
}

# Confirm destructive action
confirm_cleanup() {
    echo
    log_warning "This script will DELETE the following resources:"
    log_warning "  - Cloud Function: $FUNCTION_NAME (in region $REGION)"
    log_warning "  - Cloud Storage bucket: ${BUCKET_NAME:-'color-palettes-* buckets'}"
    log_warning "  - All stored color palettes and data"
    log_warning "  - Local function source code directory"
    
    if [[ "${FORCE_DESTROY:-}" == "true" ]]; then
        log_warning "Force mode enabled - skipping confirmation"
        return 0
    fi
    
    echo
    read -p "Are you sure you want to proceed? (yes/no): " -r
    echo
    
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        log_info "Cleanup cancelled by user"
        exit 0
    fi
    
    log_info "Cleanup confirmed, proceeding..."
}

# Set active project
set_project_context() {
    log_info "Setting project context..."
    
    # Check if project exists
    if ! gcloud projects describe "$PROJECT_ID" >/dev/null 2>&1; then
        log_warning "Project $PROJECT_ID does not exist or is not accessible"
        log_warning "Skipping project-specific cleanup"
        return 1
    fi
    
    # Set project configuration
    gcloud config set project "$PROJECT_ID" --quiet || error_exit "Failed to set project context"
    gcloud config set compute/region "$REGION" --quiet || error_exit "Failed to set region"
    
    log_success "Project context set: $PROJECT_ID"
    return 0
}

# Delete Cloud Function
delete_function() {
    log_info "Deleting Cloud Function..."
    
    # Check if function exists
    if gcloud functions describe "$FUNCTION_NAME" --region="$REGION" >/dev/null 2>&1; then
        log_info "Found function $FUNCTION_NAME, deleting..."
        
        # Delete function with retry logic
        local max_attempts=3
        local attempt=1
        
        while [ $attempt -le $max_attempts ]; do
            log_info "Deletion attempt $attempt of $max_attempts..."
            
            if gcloud functions delete "$FUNCTION_NAME" \
                --region="$REGION" \
                --quiet; then
                
                log_success "Cloud Function deleted successfully on attempt $attempt"
                return 0
            else
                if [ $attempt -eq $max_attempts ]; then
                    log_error "Failed to delete Cloud Function after $max_attempts attempts"
                    return 1
                else
                    log_warning "Deletion attempt $attempt failed. Retrying in 10 seconds..."
                    sleep 10
                fi
            fi
            
            ((attempt++))
        done
    else
        log_warning "Cloud Function $FUNCTION_NAME not found in region $REGION"
        log_info "Function may have already been deleted or never existed"
    fi
}

# Find and delete storage buckets
delete_storage_buckets() {
    log_info "Deleting Cloud Storage buckets..."
    
    local buckets_to_delete=()
    
    if [[ -n "$BUCKET_NAME" ]]; then
        # Bucket name specified, try to delete it
        if gsutil ls -b "gs://$BUCKET_NAME" >/dev/null 2>&1; then
            buckets_to_delete+=("$BUCKET_NAME")
        else
            log_warning "Specified bucket gs://$BUCKET_NAME not found"
        fi
    else
        # Find buckets with color-palettes prefix
        log_info "Searching for color-palettes-* buckets in project $PROJECT_ID..."
        
        # Get buckets that start with color-palettes-
        local found_buckets
        found_buckets=$(gsutil ls -p "$PROJECT_ID" 2>/dev/null | grep "gs://color-palettes-" | sed 's|gs://||' | sed 's|/$||' || echo "")
        
        if [[ -n "$found_buckets" ]]; then
            while IFS= read -r bucket; do
                [[ -n "$bucket" ]] && buckets_to_delete+=("$bucket")
            done <<< "$found_buckets"
        fi
    fi
    
    if [[ ${#buckets_to_delete[@]} -eq 0 ]]; then
        log_warning "No storage buckets found to delete"
        return 0
    fi
    
    # Delete each bucket
    for bucket in "${buckets_to_delete[@]}"; do
        log_info "Deleting bucket: gs://$bucket"
        
        # Check if bucket exists and has objects
        if gsutil ls -b "gs://$bucket" >/dev/null 2>&1; then
            # Check if bucket has objects
            local object_count
            object_count=$(gsutil ls "gs://$bucket/**" 2>/dev/null | wc -l)
            
            if [[ $object_count -gt 0 ]]; then
                log_info "Bucket gs://$bucket contains $object_count objects, deleting all objects..."
                
                # Delete all objects in bucket
                if gsutil -m rm -r "gs://$bucket/**" 2>/dev/null; then
                    log_success "Deleted all objects from gs://$bucket"
                else
                    log_warning "Some objects may not have been deleted from gs://$bucket"
                fi
            fi
            
            # Delete the bucket itself
            if gsutil rb "gs://$bucket"; then
                log_success "Deleted bucket: gs://$bucket"
            else
                log_error "Failed to delete bucket: gs://$bucket"
            fi
        else
            log_warning "Bucket gs://$bucket not found or already deleted"
        fi
    done
}

# Clean up local files
cleanup_local_files() {
    log_info "Cleaning up local files..."
    
    # Remove function source directory
    if [[ -d "palette-function" ]]; then
        log_info "Removing local function source directory..."
        rm -rf palette-function
        log_success "Removed palette-function directory"
    else
        log_info "Local function source directory not found"
    fi
    
    # Remove deployment info file
    if [[ -f "deployment-info.txt" ]]; then
        log_info "Removing deployment info file..."
        rm -f deployment-info.txt
        log_success "Removed deployment-info.txt"
    else
        log_info "Deployment info file not found"
    fi
    
    # Remove any other generated files
    for file in "function-url.txt" "*.log"; do
        if [[ -f "$file" ]]; then
            log_info "Removing $file..."
            rm -f "$file"
        fi
    done
}

# Optional: Delete entire project
delete_project() {
    if [[ "${DELETE_PROJECT:-}" == "true" ]]; then
        log_warning "DELETE_PROJECT flag is set - this will delete the entire project!"
        log_warning "Project to delete: $PROJECT_ID"
        echo
        
        if [[ "${FORCE_DESTROY:-}" != "true" ]]; then
            read -p "Are you absolutely sure you want to DELETE THE ENTIRE PROJECT '$PROJECT_ID'? (DELETE/no): " -r
            echo
            
            if [[ ! $REPLY == "DELETE" ]]; then
                log_info "Project deletion cancelled"
                return 0
            fi
        fi
        
        log_warning "Deleting entire project: $PROJECT_ID"
        
        if gcloud projects delete "$PROJECT_ID" --quiet; then
            log_success "Project $PROJECT_ID deletion initiated"
            log_info "Note: Project deletion may take several minutes to complete"
        else
            log_error "Failed to delete project $PROJECT_ID"
        fi
    else
        log_info "Project $PROJECT_ID preserved (set DELETE_PROJECT=true to delete entire project)"
    fi
}

# Verify cleanup completion
verify_cleanup() {
    log_info "Verifying cleanup completion..."
    
    local cleanup_issues=0
    
    # Check if function still exists
    if gcloud functions describe "$FUNCTION_NAME" --region="$REGION" >/dev/null 2>&1; then
        log_warning "Cloud Function $FUNCTION_NAME still exists"
        ((cleanup_issues++))
    else
        log_success "Cloud Function successfully removed"
    fi
    
    # Check if buckets still exist
    if [[ -n "${BUCKET_NAME:-}" ]]; then
        if gsutil ls -b "gs://$BUCKET_NAME" >/dev/null 2>&1; then
            log_warning "Storage bucket gs://$BUCKET_NAME still exists"
            ((cleanup_issues++))
        else
            log_success "Storage bucket successfully removed"
        fi
    fi
    
    # Check local files
    if [[ -d "palette-function" ]] || [[ -f "deployment-info.txt" ]]; then
        log_warning "Some local files still exist"
        ((cleanup_issues++))
    else
        log_success "Local files successfully cleaned up"
    fi
    
    if [[ $cleanup_issues -eq 0 ]]; then
        log_success "Cleanup verification passed - all resources removed"
    else
        log_warning "Cleanup verification found $cleanup_issues potential issues"
        log_info "You may need to manually verify and clean up remaining resources"
    fi
}

# Display cleanup summary
display_summary() {
    echo
    echo "============================================"
    log_success "Cleanup process completed!"
    echo "============================================"
    echo
    log_info "Summary of actions taken:"
    log_info "  ✓ Cloud Function removal attempted"
    log_info "  ✓ Storage bucket cleanup attempted"
    log_info "  ✓ Local files cleanup completed"
    
    if [[ "${DELETE_PROJECT:-}" == "true" ]]; then
        log_info "  ✓ Project deletion initiated"
    fi
    
    echo
    log_info "If you need to redeploy, run: ./deploy.sh"
    
    if [[ "${DELETE_PROJECT:-}" != "true" ]]; then
        echo
        log_info "Note: Project $PROJECT_ID was preserved"
        log_info "To delete the entire project, set DELETE_PROJECT=true and run this script again"
    fi
    echo
}

# Main cleanup function
main() {
    echo "============================================"
    echo "Color Palette Generator Cleanup Script"
    echo "============================================"
    echo
    
    validate_prerequisites
    setup_environment
    confirm_cleanup
    
    if set_project_context; then
        delete_function
        delete_storage_buckets
        delete_project
        verify_cleanup
    else
        log_warning "Skipping cloud resource cleanup due to project access issues"
    fi
    
    cleanup_local_files
    display_summary
}

# Handle script interruption
cleanup_on_interrupt() {
    echo
    log_warning "Cleanup interrupted by user"
    log_warning "Some resources may not have been cleaned up"
    log_info "You may need to manually verify and clean up remaining resources"
    exit 130
}

# Display help information
show_help() {
    echo "Color Palette Generator Cleanup Script"
    echo
    echo "Usage: $0 [OPTIONS]"
    echo
    echo "Options:"
    echo "  -h, --help              Show this help message"
    echo "  -f, --force             Skip confirmation prompts"
    echo "  -p, --delete-project    Delete the entire Google Cloud project"
    echo
    echo "Environment Variables:"
    echo "  PROJECT_ID              Google Cloud project ID (auto-detected if not set)"
    echo "  REGION                  Google Cloud region (default: us-central1)"
    echo "  FUNCTION_NAME           Cloud Function name (default: generate-color-palette)"
    echo "  BUCKET_NAME             Storage bucket name (auto-detected if not set)"
    echo "  FORCE_DESTROY           Set to 'true' to skip confirmations"
    echo "  DELETE_PROJECT          Set to 'true' to delete entire project"
    echo
    echo "Examples:"
    echo "  $0                      Interactive cleanup with confirmations"
    echo "  $0 --force              Cleanup without confirmations"
    echo "  $0 --delete-project     Cleanup and delete entire project"
    echo "  FORCE_DESTROY=true $0   Cleanup without confirmations (env var)"
    echo
}

# Parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
                ;;
            -f|--force)
                export FORCE_DESTROY="true"
                shift
                ;;
            -p|--delete-project)
                export DELETE_PROJECT="true"
                shift
                ;;
            *)
                log_error "Unknown option: $1"
                echo "Use --help for usage information"
                exit 1
                ;;
        esac
    done
}

# Set up signal handlers
trap cleanup_on_interrupt SIGINT SIGTERM

# Parse arguments and run main function
parse_arguments "$@"
main