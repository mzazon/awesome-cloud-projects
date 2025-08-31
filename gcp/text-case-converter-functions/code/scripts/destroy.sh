#!/bin/bash

# destroy.sh - Cleanup script for Text Case Converter Cloud Function
# This script removes all resources created by the deployment script

set -e  # Exit on any error
set -o pipefail  # Exit on pipe failures

# Color codes for output formatting
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

# Configuration variables with defaults
PROJECT_ID="${PROJECT_ID:-}"
REGION="${REGION:-us-central1}"
FUNCTION_NAME="${FUNCTION_NAME:-text-case-converter}"
DRY_RUN="${DRY_RUN:-false}"
FORCE="${FORCE:-false}"
DELETE_PROJECT="${DELETE_PROJECT:-false}"

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if gcloud CLI is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "gcloud CLI is not installed. Please install Google Cloud SDK."
        log_error "Visit: https://cloud.google.com/sdk/docs/install"
        exit 1
    fi
    
    # Check if user is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" &> /dev/null; then
        log_error "No active gcloud authentication found."
        log_error "Please run: gcloud auth login"
        exit 1
    fi
    
    log_success "Prerequisites check completed"
}

# Function to detect project if not specified
detect_project() {
    if [ -z "$PROJECT_ID" ]; then
        # Try to get current project from gcloud config
        PROJECT_ID=$(gcloud config get-value project 2>/dev/null || echo "")
        
        if [ -z "$PROJECT_ID" ]; then
            log_error "No project ID specified and no default project configured."
            log_error "Please specify project ID with --project-id option or run:"
            log_error "gcloud config set project YOUR_PROJECT_ID"
            exit 1
        fi
        
        log_info "Using current project: $PROJECT_ID"
    fi
}

# Function to verify project exists and we have access
verify_project_access() {
    log_info "Verifying access to project: $PROJECT_ID"
    
    if ! gcloud projects describe "$PROJECT_ID" &> /dev/null; then
        log_error "Cannot access project $PROJECT_ID"
        log_error "Please verify the project ID and your permissions"
        exit 1
    fi
    
    # Set the project context
    gcloud config set project "$PROJECT_ID" --quiet
    gcloud config set compute/region "$REGION" --quiet
    
    log_success "Project access verified"
}

# Function to list resources that will be deleted
list_resources_to_delete() {
    log_info "Scanning for resources to delete..."
    
    local resources_found=false
    
    # Check for Cloud Functions
    log_info "Checking for Cloud Functions..."
    local functions
    functions=$(gcloud functions list --filter="name:$FUNCTION_NAME" --format="value(name)" 2>/dev/null || echo "")
    
    if [ -n "$functions" ]; then
        resources_found=true
        echo "  Cloud Functions:"
        while IFS= read -r func; do
            if [ -n "$func" ]; then
                echo "    - $func"
            fi
        done <<< "$functions"
    else
        echo "  No Cloud Functions found matching: $FUNCTION_NAME"
    fi
    
    # Check for logs (informational only)
    log_info "Checking for Cloud Logging resources..."
    local log_entries
    log_entries=$(gcloud logging logs list --filter="logName~'cloud-functions'" --format="value(logName)" --limit=1 2>/dev/null || echo "")
    
    if [ -n "$log_entries" ]; then
        echo "  Cloud Logging entries exist (will be retained)"
    fi
    
    # Check if project should be deleted
    if [ "$DELETE_PROJECT" = "true" ]; then
        resources_found=true
        echo "  Entire Project: $PROJECT_ID (DESTRUCTIVE)"
    fi
    
    if [ "$resources_found" = "false" ]; then
        log_warning "No resources found to delete"
        return 1
    fi
    
    return 0
}

# Function to confirm deletion
confirm_deletion() {
    if [ "$FORCE" = "true" ]; then
        log_warning "Force mode enabled - skipping confirmation"
        return 0
    fi
    
    echo ""
    if [ "$DELETE_PROJECT" = "true" ]; then
        log_warning "WARNING: You are about to DELETE THE ENTIRE PROJECT!"
        log_warning "This action is IRREVERSIBLE and will delete ALL resources in the project."
        echo ""
        echo -n "Type the project ID '$PROJECT_ID' to confirm project deletion: "
        read -r confirmation
        
        if [ "$confirmation" != "$PROJECT_ID" ]; then
            log_error "Project ID confirmation failed. Aborting."
            exit 1
        fi
    else
        log_warning "This will delete the resources listed above."
        echo -n "Are you sure you want to continue? (y/N): "
        read -r confirmation
        
        if [[ ! "$confirmation" =~ ^[Yy]$ ]]; then
            log_info "Operation cancelled by user"
            exit 0
        fi
    fi
    
    log_info "Proceeding with resource deletion..."
}

# Function to delete Cloud Functions
delete_cloud_functions() {
    log_info "Deleting Cloud Functions..."
    
    local functions
    functions=$(gcloud functions list --filter="name:$FUNCTION_NAME" --format="value(name)" 2>/dev/null || echo "")
    
    if [ -z "$functions" ]; then
        log_info "No Cloud Functions found to delete"
        return 0
    fi
    
    while IFS= read -r function_path; do
        if [ -n "$function_path" ]; then
            local func_name
            func_name=$(basename "$function_path")
            
            log_info "Deleting function: $func_name"
            
            if [ "$DRY_RUN" = "false" ]; then
                if gcloud functions delete "$func_name" \
                    --region="$REGION" \
                    --quiet 2>/dev/null; then
                    log_success "Deleted function: $func_name"
                else
                    log_warning "Failed to delete function: $func_name (may not exist)"
                fi
            else
                log_info "[DRY RUN] Would delete function: $func_name"
            fi
        fi
    done <<< "$functions"
}

# Function to wait for resource deletion
wait_for_deletion() {
    if [ "$DRY_RUN" = "true" ]; then
        return 0
    fi
    
    log_info "Waiting for resources to be fully deleted..."
    
    local max_attempts=30
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        local functions
        functions=$(gcloud functions list --filter="name:$FUNCTION_NAME" --format="value(name)" 2>/dev/null || echo "")
        
        if [ -z "$functions" ]; then
            log_success "All functions have been deleted"
            return 0
        fi
        
        log_info "Waiting for deletion to complete... ($attempt/$max_attempts)"
        sleep 10
        ((attempt++))
    done
    
    log_warning "Some resources may still be in deletion process"
}

# Function to delete entire project
delete_project() {
    if [ "$DELETE_PROJECT" != "true" ]; then
        return 0
    fi
    
    log_warning "Deleting entire project: $PROJECT_ID"
    
    if [ "$DRY_RUN" = "false" ]; then
        gcloud projects delete "$PROJECT_ID" --quiet
        log_success "Project deletion initiated: $PROJECT_ID"
        log_info "Note: Project deletion may take several minutes to complete"
    else
        log_info "[DRY RUN] Would delete project: $PROJECT_ID"
    fi
}

# Function to clean up local files
cleanup_local_files() {
    log_info "Cleaning up local temporary files..."
    
    local temp_files=(
        "/tmp/function_deployment_info.env"
        "/tmp/${FUNCTION_NAME}-source"
    )
    
    for file in "${temp_files[@]}"; do
        if [ -e "$file" ]; then
            if [ "$DRY_RUN" = "false" ]; then
                rm -rf "$file"
                log_info "Removed: $file"
            else
                log_info "[DRY RUN] Would remove: $file"
            fi
        fi
    done
}

# Function to verify deletion
verify_deletion() {
    if [ "$DRY_RUN" = "true" ] || [ "$DELETE_PROJECT" = "true" ]; then
        return 0
    fi
    
    log_info "Verifying resource deletion..."
    
    local functions
    functions=$(gcloud functions list --filter="name:$FUNCTION_NAME" --format="value(name)" 2>/dev/null || echo "")
    
    if [ -n "$functions" ]; then
        log_warning "Some functions may still exist:"
        echo "$functions"
        log_info "They may still be in the deletion process"
    else
        log_success "All targeted resources have been deleted"
    fi
}

# Function to display cleanup summary
display_summary() {
    log_info "Cleanup Summary:"
    echo "===================="
    echo "Project ID: $PROJECT_ID"
    echo "Region: $REGION"
    echo "Function Name: $FUNCTION_NAME"
    
    if [ "$DELETE_PROJECT" = "true" ]; then
        echo "Action: Entire project deleted"
    else
        echo "Action: Function-specific resources deleted"
    fi
    
    if [ "$DRY_RUN" = "true" ]; then
        echo "Mode: DRY RUN (no actual changes made)"
    fi
    echo "===================="
}

# Function to show usage
show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Clean up Text Case Converter Cloud Function resources from Google Cloud Platform"
    echo ""
    echo "Options:"
    echo "  --project-id PROJECT_ID    Specify the GCP project ID to clean up"
    echo "  --region REGION            Specify the region (default: us-central1)"
    echo "  --function-name NAME       Specify the function name (default: text-case-converter)"
    echo "  --delete-project           Delete the entire project (DESTRUCTIVE)"
    echo "  --force                    Skip confirmation prompts"
    echo "  --dry-run                  Show what would be deleted without making changes"
    echo "  --help                     Show this help message"
    echo ""
    echo "Environment Variables:"
    echo "  PROJECT_ID                 GCP project ID"
    echo "  REGION                     GCP region"
    echo "  FUNCTION_NAME              Cloud Function name"
    echo "  DELETE_PROJECT             Set to 'true' to delete entire project"
    echo "  FORCE                      Set to 'true' to skip confirmations"
    echo "  DRY_RUN                    Set to 'true' for dry run mode"
    echo ""
    echo "Examples:"
    echo "  $0                                        # Clean up with current project"
    echo "  $0 --project-id my-project               # Clean up specific project"
    echo "  $0 --dry-run                             # Preview what would be deleted"
    echo "  $0 --delete-project --force              # Delete entire project without confirmation"
    echo "  $0 --function-name my-function           # Clean up specific function"
    echo ""
    echo "WARNING: The --delete-project option will delete the ENTIRE project and ALL its resources!"
}

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
        --function-name)
            FUNCTION_NAME="$2"
            shift 2
            ;;
        --delete-project)
            DELETE_PROJECT="true"
            shift
            ;;
        --force)
            FORCE="true"
            shift
            ;;
        --dry-run)
            DRY_RUN="true"
            shift
            ;;
        --help)
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

# Main cleanup flow
main() {
    log_info "Starting Text Case Converter Cloud Function cleanup..."
    
    if [ "$DRY_RUN" = "true" ]; then
        log_info "Running in DRY RUN mode - no resources will be deleted"
    fi
    
    if [ "$DELETE_PROJECT" = "true" ]; then
        log_warning "PROJECT DELETION MODE ENABLED"
    fi
    
    # Execute cleanup steps
    check_prerequisites
    detect_project
    verify_project_access
    
    # List resources and confirm deletion
    if list_resources_to_delete; then
        confirm_deletion
        
        if [ "$DELETE_PROJECT" = "true" ]; then
            delete_project
        else
            delete_cloud_functions
            wait_for_deletion
            verify_deletion
        fi
        
        cleanup_local_files
        display_summary
        
        log_success "Cleanup completed successfully!"
    else
        log_info "No resources found to clean up"
    fi
    
    if [ "$DELETE_PROJECT" = "false" ] && [ "$DRY_RUN" = "false" ]; then
        log_info "Note: Cloud Logging entries are retained and may incur minimal storage costs"
        log_info "To delete the entire project, run: $0 --delete-project --project-id $PROJECT_ID"
    fi
}

# Execute main function
main "$@"