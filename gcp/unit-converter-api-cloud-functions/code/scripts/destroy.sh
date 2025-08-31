#!/bin/bash

#===============================================================================
# Unit Converter API Cloud Functions - Cleanup Script
#===============================================================================
# This script safely removes all resources created by the Unit Converter API
# deployment, including Cloud Functions and local files. It includes safety
# checks and confirmation prompts to prevent accidental resource deletion.
#
# Features:
# - Safe resource deletion with confirmation prompts
# - Comprehensive cleanup of all created resources
# - Verification of resource deletion
# - Detailed logging and error handling
# - Support for force deletion (non-interactive)
#===============================================================================

set -e  # Exit on any error
set -o pipefail  # Exit if any command in a pipeline fails

#===============================================================================
# Configuration and Constants
#===============================================================================

# Script metadata
readonly SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
readonly FUNCTION_SOURCE_DIR="${PROJECT_DIR}/function-source"

# Default configuration
readonly DEFAULT_REGION="us-central1"
readonly DEFAULT_FUNCTION_NAME="unit-converter-api"

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

#===============================================================================
# Utility Functions
#===============================================================================

# Print colored output
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

# Print usage information
print_usage() {
    cat << EOF
Usage: $SCRIPT_NAME [OPTIONS]

Clean up Unit Converter API Cloud Function resources

OPTIONS:
    -p, --project PROJECT_ID     Google Cloud Project ID (required)
    -r, --region REGION          Function region (default: $DEFAULT_REGION)
    -n, --name FUNCTION_NAME     Function name (default: $DEFAULT_FUNCTION_NAME)
    -f, --force                  Skip confirmation prompts (non-interactive)
    --dry-run                    Show what would be deleted without executing
    --skip-local                 Skip local file cleanup
    -h, --help                   Display this help message

EXAMPLES:
    $SCRIPT_NAME --project my-gcp-project
    $SCRIPT_NAME --project my-project --region us-west1
    $SCRIPT_NAME --project my-project --force
    $SCRIPT_NAME --project my-project --dry-run

ENVIRONMENT VARIABLES:
    GOOGLE_CLOUD_PROJECT         Default project ID if not specified
    GOOGLE_CLOUD_REGION          Default region if not specified

EOF
}

# Check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Validate Google Cloud CLI authentication and project access
validate_gcloud_setup() {
    print_info "Validating Google Cloud CLI setup..."
    
    if ! command_exists gcloud; then
        print_error "Google Cloud CLI (gcloud) is not installed"
        print_error "Please install it from: https://cloud.google.com/sdk/docs/install"
        exit 1
    fi
    
    # Check authentication
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 >/dev/null 2>&1; then
        print_error "Not authenticated with Google Cloud CLI"
        print_error "Please run: gcloud auth login"
        exit 1
    fi
    
    local active_account
    active_account=$(gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1)
    print_success "Authenticated as: $active_account"
    
    # Validate project access
    if ! gcloud projects describe "$PROJECT_ID" >/dev/null 2>&1; then
        print_error "Cannot access project '$PROJECT_ID'"
        print_error "Please ensure the project exists and you have appropriate permissions"
        exit 1
    fi
    
    print_success "Project '$PROJECT_ID' is accessible"
}

# Check if function exists
function_exists() {
    gcloud functions describe "$FUNCTION_NAME" \
        --region="$REGION" \
        --project="$PROJECT_ID" \
        >/dev/null 2>&1
}

# Get user confirmation for destructive actions
confirm_action() {
    local message="$1"
    local default_response="${2:-n}"
    
    if [[ "$FORCE" == "true" ]]; then
        print_warning "Force mode enabled - proceeding with $message"
        return 0
    fi
    
    local response
    if [[ "$default_response" == "y" ]]; then
        echo -n -e "${YELLOW}$message [Y/n]: ${NC}"
    else
        echo -n -e "${YELLOW}$message [y/N]: ${NC}"
    fi
    
    read -r response
    response=${response:-$default_response}
    
    if [[ "$response" =~ ^[Yy]$ ]]; then
        return 0
    else
        return 1
    fi
}

# Display resources to be deleted
display_resources_to_delete() {
    print_info "======================================"
    print_info "RESOURCES TO BE DELETED"
    print_info "======================================"
    echo
    
    print_info "Google Cloud Resources:"
    
    # Check if function exists
    if function_exists; then
        print_info "  ✓ Cloud Function: $FUNCTION_NAME (in region: $REGION)"
        
        # Get function details
        local function_url
        if function_url=$(gcloud functions describe "$FUNCTION_NAME" \
            --region="$REGION" \
            --project="$PROJECT_ID" \
            --format="value(httpsTrigger.url)" 2>/dev/null); then
            print_info "    URL: $function_url"
        fi
    else
        print_info "  ○ Cloud Function: $FUNCTION_NAME (not found)"
    fi
    
    echo
    print_info "Local Files and Directories:"
    
    # Check local resources
    if [[ -d "$FUNCTION_SOURCE_DIR" ]]; then
        print_info "  ✓ Function source directory: $FUNCTION_SOURCE_DIR"
    else
        print_info "  ○ Function source directory: $FUNCTION_SOURCE_DIR (not found)"
    fi
    
    if [[ -f "$PROJECT_DIR/function-url.txt" ]]; then
        print_info "  ✓ Function URL file: $PROJECT_DIR/function-url.txt"
    else
        print_info "  ○ Function URL file: $PROJECT_DIR/function-url.txt (not found)"
    fi
    
    echo
    print_warning "⚠️  This action cannot be undone!"
    print_warning "⚠️  Function deletion is immediate and stops all billing"
    echo
}

# Delete the Cloud Function
delete_function() {
    print_info "Checking for Cloud Function: $FUNCTION_NAME"
    
    if ! function_exists; then
        print_warning "Cloud Function '$FUNCTION_NAME' not found in region '$REGION'"
        return 0
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        print_warning "DRY RUN: Would delete Cloud Function: $FUNCTION_NAME"
        return 0
    fi
    
    print_info "Deleting Cloud Function: $FUNCTION_NAME"
    
    if ! gcloud functions delete "$FUNCTION_NAME" \
        --region="$REGION" \
        --project="$PROJECT_ID" \
        --quiet; then
        print_error "Failed to delete Cloud Function: $FUNCTION_NAME"
        exit 1
    fi
    
    print_success "Cloud Function deleted successfully"
    
    # Wait a moment and verify deletion
    print_info "Verifying function deletion..."
    sleep 3
    
    if function_exists; then
        print_warning "Function still exists, but deletion may be in progress"
    else
        print_success "Function deletion verified"
    fi
}

# Clean up local files
cleanup_local_files() {
    if [[ "$SKIP_LOCAL" == "true" ]]; then
        print_info "Skipping local file cleanup (--skip-local specified)"
        return 0
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        print_warning "DRY RUN: Would clean up local files"
        return 0
    fi
    
    print_info "Cleaning up local files..."
    
    # Remove function source directory
    if [[ -d "$FUNCTION_SOURCE_DIR" ]]; then
        print_info "Removing function source directory: $FUNCTION_SOURCE_DIR"
        if ! rm -rf "$FUNCTION_SOURCE_DIR"; then
            print_error "Failed to remove function source directory"
            exit 1
        fi
        print_success "Function source directory removed"
    else
        print_info "Function source directory not found (already clean)"
    fi
    
    # Remove function URL file
    if [[ -f "$PROJECT_DIR/function-url.txt" ]]; then
        print_info "Removing function URL file: $PROJECT_DIR/function-url.txt"
        if ! rm -f "$PROJECT_DIR/function-url.txt"; then
            print_error "Failed to remove function URL file"
            exit 1
        fi
        print_success "Function URL file removed"
    else
        print_info "Function URL file not found (already clean)"
    fi
    
    print_success "Local file cleanup completed"
}

# Verify cleanup completion
verify_cleanup() {
    if [[ "$DRY_RUN" == "true" ]]; then
        print_info "DRY RUN: Would verify cleanup completion"
        return 0
    fi
    
    print_info "Verifying cleanup completion..."
    
    local cleanup_success=true
    
    # Check if function still exists
    if function_exists; then
        print_warning "Cloud Function still exists (deletion may be in progress)"
        cleanup_success=false
    else
        print_success "Cloud Function successfully deleted"
    fi
    
    # Check local files
    if [[ -d "$FUNCTION_SOURCE_DIR" ]]; then
        print_warning "Function source directory still exists"
        cleanup_success=false
    fi
    
    if [[ -f "$PROJECT_DIR/function-url.txt" ]]; then
        print_warning "Function URL file still exists"
        cleanup_success=false
    fi
    
    if [[ "$cleanup_success" == "true" ]]; then
        print_success "All resources cleaned up successfully"
    else
        print_warning "Some resources may still exist - manual cleanup may be required"
    fi
}

# Display cleanup summary
display_summary() {
    if [[ "$DRY_RUN" == "true" ]]; then
        print_info "DRY RUN: Cleanup summary would be displayed here"
        return 0
    fi
    
    print_success "======================================"
    print_success "CLEANUP COMPLETED"
    print_success "======================================"
    echo
    print_info "Resources removed:"
    echo "  - Cloud Function: $FUNCTION_NAME"
    echo "  - Function source directory"
    echo "  - Function URL file"
    echo "  - Project: $PROJECT_ID"
    echo "  - Region: $REGION"
    echo
    print_success "All Unit Converter API resources have been cleaned up"
    print_info "Billing for the Cloud Function has stopped"
    echo
    print_info "To redeploy, run: ./deploy.sh --project $PROJECT_ID"
}

# List all functions in the project (for troubleshooting)
list_functions() {
    print_info "Listing all Cloud Functions in project '$PROJECT_ID':"
    
    if ! gcloud functions list --project="$PROJECT_ID" --format="table(name,status,trigger.httpsTrigger.url)"; then
        print_warning "Failed to list functions or no functions found"
    fi
    
    echo
}

#===============================================================================
# Main Execution
#===============================================================================

main() {
    # Initialize variables
    PROJECT_ID=""
    REGION="$DEFAULT_REGION"
    FUNCTION_NAME="$DEFAULT_FUNCTION_NAME"
    FORCE="false"
    DRY_RUN="false"
    SKIP_LOCAL="false"
    LIST_FUNCTIONS="false"
    
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
            -n|--name)
                FUNCTION_NAME="$2"
                shift 2
                ;;
            -f|--force)
                FORCE="true"
                shift
                ;;
            --dry-run)
                DRY_RUN="true"
                shift
                ;;
            --skip-local)
                SKIP_LOCAL="true"
                shift
                ;;
            --list)
                LIST_FUNCTIONS="true"
                shift
                ;;
            -h|--help)
                print_usage
                exit 0
                ;;
            *)
                print_error "Unknown option: $1"
                print_usage
                exit 1
                ;;
        esac
    done
    
    # Use environment variables as fallbacks
    if [[ -z "$PROJECT_ID" ]]; then
        PROJECT_ID="${GOOGLE_CLOUD_PROJECT:-}"
    fi
    
    if [[ -z "$PROJECT_ID" ]]; then
        print_error "Project ID is required"
        print_error "Use --project flag or set GOOGLE_CLOUD_PROJECT environment variable"
        print_usage
        exit 1
    fi
    
    # Update region from environment if not set
    if [[ "$REGION" == "$DEFAULT_REGION" && -n "${GOOGLE_CLOUD_REGION:-}" ]]; then
        REGION="$GOOGLE_CLOUD_REGION"
    fi
    
    print_info "Starting Unit Converter API cleanup..."
    print_info "Project: $PROJECT_ID"
    print_info "Region: $REGION"
    print_info "Function: $FUNCTION_NAME"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        print_warning "DRY RUN MODE - No resources will be deleted"
    fi
    
    if [[ "$FORCE" == "true" ]]; then
        print_warning "FORCE MODE - Skipping confirmation prompts"
    fi
    
    # Set gcloud configuration
    if [[ "$DRY_RUN" != "true" ]]; then
        gcloud config set project "$PROJECT_ID"
        gcloud config set compute/region "$REGION"
        gcloud config set functions/region "$REGION"
    fi
    
    # Execute cleanup steps
    validate_gcloud_setup
    
    # List functions if requested
    if [[ "$LIST_FUNCTIONS" == "true" ]]; then
        list_functions
        return 0
    fi
    
    # Display what will be deleted
    display_resources_to_delete
    
    # Get confirmation
    if [[ "$DRY_RUN" != "true" ]]; then
        if ! confirm_action "Do you want to proceed with the cleanup?"; then
            print_info "Cleanup cancelled by user"
            exit 0
        fi
        echo
    fi
    
    # Execute cleanup
    delete_function
    cleanup_local_files
    verify_cleanup
    display_summary
    
    print_success "Cleanup completed successfully!"
}

# Handle script interruption
trap 'print_error "Script interrupted"; exit 130' INT TERM

# Run main function with all arguments
main "$@"