#!/bin/bash

# Timestamp Converter API with Cloud Functions - Cleanup Script
# This script removes all resources created by the deployment script

set -euo pipefail

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

# Function to check if command exists
check_command() {
    if ! command -v "$1" &> /dev/null; then
        log_error "Command '$1' is required but not installed."
        return 1
    fi
}

# Function to check if gcloud is authenticated
check_gcloud_auth() {
    local current_account
    current_account=$(gcloud auth list --filter=status:ACTIVE --format="value(account)" 2>/dev/null)
    if [[ -z "$current_account" ]]; then
        log_error "gcloud is not authenticated. Please run 'gcloud auth login'"
        return 1
    fi
    log_info "Authenticated as: $current_account"
}

# Function to load deployment info from file
load_deployment_info() {
    local info_file="deployment_info.txt"
    
    if [[ -f "$info_file" ]]; then
        log_info "Loading deployment information from $info_file"
        
        # Extract values from deployment info file
        PROJECT_ID=$(grep "Project ID:" "$info_file" | cut -d' ' -f3 || echo "")
        REGION=$(grep "Region:" "$info_file" | cut -d' ' -f2 || echo "")
        FUNCTION_NAME=$(grep "Function Name:" "$info_file" | cut -d' ' -f3 || echo "")
        BUCKET_NAME=$(grep "Storage Bucket:" "$info_file" | cut -d' ' -f3 | sed 's|gs://||' || echo "")
        
        log_info "Loaded deployment info:"
        log_info "  Project ID: $PROJECT_ID"
        log_info "  Region: $REGION"
        log_info "  Function Name: $FUNCTION_NAME"
        log_info "  Bucket Name: $BUCKET_NAME"
        
        return 0
    else
        log_warning "Deployment info file not found. Using environment variables or defaults."
        return 1
    fi
}

# Function to confirm destructive actions
confirm_action() {
    local action="$1"
    local resource="$2"
    
    log_warning "This will $action: $resource"
    read -p "Are you sure? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Action cancelled by user"
        return 1
    fi
    return 0
}

# Function to delete Cloud Function
delete_function() {
    local function_name="$1"
    local region="$2"
    local project_id="$3"
    
    log_info "Checking if Cloud Function $function_name exists..."
    
    # Check if function exists
    if ! gcloud run services describe "$function_name" --region="$region" --project="$project_id" &>/dev/null; then
        log_info "Cloud Function $function_name not found, skipping deletion"
        return 0
    fi
    
    if confirm_action "delete" "Cloud Function $function_name"; then
        log_info "Deleting Cloud Function: $function_name"
        
        if gcloud run services delete "$function_name" \
            --region="$region" \
            --project="$project_id" \
            --quiet; then
            log_success "Cloud Function $function_name deleted successfully"
        else
            log_error "Failed to delete Cloud Function $function_name"
            return 1
        fi
    else
        log_info "Skipped deletion of Cloud Function $function_name"
    fi
}

# Function to delete Cloud Storage bucket
delete_storage_bucket() {
    local bucket_name="$1"
    
    log_info "Checking if storage bucket gs://$bucket_name exists..."
    
    # Check if bucket exists
    if ! gsutil ls -b "gs://$bucket_name" &>/dev/null; then
        log_info "Storage bucket gs://$bucket_name not found, skipping deletion"
        return 0
    fi
    
    if confirm_action "delete" "Storage bucket gs://$bucket_name and all its contents"; then
        log_info "Deleting storage bucket: gs://$bucket_name"
        
        # Delete all objects in bucket first
        log_info "Deleting all objects in bucket..."
        if gsutil -m rm -r "gs://$bucket_name/*" 2>/dev/null || true; then
            log_info "Bucket contents deleted"
        fi
        
        # Delete the bucket itself
        if gsutil rb "gs://$bucket_name"; then
            log_success "Storage bucket gs://$bucket_name deleted successfully"
        else
            log_error "Failed to delete storage bucket gs://$bucket_name"
            return 1
        fi
    else
        log_info "Skipped deletion of storage bucket gs://$bucket_name"
    fi
}

# Function to disable APIs
disable_apis() {
    local project_id="$1"
    local apis=(
        "cloudfunctions.googleapis.com"
        "cloudbuild.googleapis.com"
        "run.googleapis.com"
        "logging.googleapis.com"
        "storage.googleapis.com"
    )
    
    if confirm_action "disable" "APIs for project $project_id"; then
        log_info "Disabling APIs..."
        for api in "${apis[@]}"; do
            log_info "Disabling $api..."
            if gcloud services disable "$api" --project="$project_id" --quiet 2>/dev/null; then
                log_info "Disabled $api"
            else
                log_warning "Failed to disable $api (may not be enabled)"
            fi
        done
        log_success "API disabling completed"
    else
        log_info "Skipped API disabling"
    fi
}

# Function to delete project
delete_project() {
    local project_id="$1"
    
    log_warning "DANGER: This will permanently delete the entire project and all its resources!"
    log_warning "Project: $project_id"
    log_warning "This action cannot be undone and may take several minutes to complete."
    
    if confirm_action "PERMANENTLY DELETE" "entire project $project_id"; then
        log_info "Deleting project: $project_id"
        
        if gcloud projects delete "$project_id" --quiet; then
            log_success "Project $project_id deletion initiated"
            log_info "Note: Project deletion may take several minutes to complete"
        else
            log_error "Failed to delete project $project_id"
            return 1
        fi
    else
        log_info "Skipped project deletion"
    fi
}

# Function to clean up local files
cleanup_local_files() {
    local function_dir="${FUNCTION_DIR:-timestamp-converter-function}"
    local files_to_clean=(
        "deployment_info.txt"
        "function_url.txt"
        "$function_dir"
    )
    
    if confirm_action "delete" "local deployment files and directories"; then
        log_info "Cleaning up local files..."
        
        for item in "${files_to_clean[@]}"; do
            if [[ -f "$item" ]] || [[ -d "$item" ]]; then
                log_info "Removing: $item"
                rm -rf "$item"
            fi
        done
        
        log_success "Local files cleaned up"
    else
        log_info "Skipped local file cleanup"
    fi
}

# Function to display cleanup summary
display_cleanup_summary() {
    local project_id="$1"
    
    log_info ""
    log_info "Cleanup Summary"
    log_info "==============="
    log_info "The following resources have been processed for cleanup:"
    log_info "  - Cloud Function (Cloud Run service)"
    log_info "  - Cloud Storage bucket"
    log_info "  - Local deployment files"
    log_info ""
    
    if [[ -n "$project_id" ]]; then
        log_info "Project $project_id may still exist with disabled APIs."
        log_info "To completely remove the project, run this script again and confirm project deletion."
    fi
    
    log_info ""
    log_info "If you experience any issues, you can manually clean up resources using:"
    log_info "  gcloud run services list --project=$project_id"
    log_info "  gsutil ls"
    log_info "  gcloud projects list --filter='projectId:timestamp-converter-*'"
}

# Main cleanup function
main() {
    log_info "Starting Timestamp Converter API cleanup..."
    
    # Check prerequisites
    log_info "Checking prerequisites..."
    check_command "gcloud" || exit 1
    check_command "gsutil" || exit 1
    check_gcloud_auth || exit 1
    
    # Try to load deployment info from file, fallback to environment variables
    if ! load_deployment_info; then
        log_info "Using environment variables or defaults..."
        PROJECT_ID="${PROJECT_ID:-}"
        REGION="${REGION:-us-central1}"
        FUNCTION_NAME="${FUNCTION_NAME:-timestamp-converter}"
        BUCKET_NAME="${BUCKET_NAME:-}"
    fi
    
    # If no project ID is available, try to detect it
    if [[ -z "$PROJECT_ID" ]]; then
        log_warning "Project ID not found in deployment info or environment variables."
        log_info "Attempting to use current gcloud project..."
        PROJECT_ID=$(gcloud config get-value project 2>/dev/null || echo "")
        
        if [[ -z "$PROJECT_ID" ]]; then
            log_error "Cannot determine project ID. Please set PROJECT_ID environment variable."
            exit 1
        fi
        
        log_info "Using current project: $PROJECT_ID"
    fi
    
    # Verify project exists
    if ! gcloud projects describe "$PROJECT_ID" &>/dev/null; then
        log_error "Project $PROJECT_ID does not exist or you don't have access to it."
        exit 1
    fi
    
    # Set project context
    gcloud config set project "$PROJECT_ID"
    
    log_info "Cleanup configuration:"
    log_info "  Project ID: $PROJECT_ID"
    log_info "  Region: $REGION"
    log_info "  Function Name: $FUNCTION_NAME"
    log_info "  Bucket Name: $BUCKET_NAME"
    
    log_warning ""
    log_warning "This will remove resources created by the Timestamp Converter API deployment."
    log_warning "Please review the resources above before proceeding."
    log_warning ""
    
    # Option to delete individual resources or entire project
    echo "Cleanup options:"
    echo "1. Delete individual resources (recommended)"
    echo "2. Delete entire project (WARNING: removes everything)"
    echo "3. Cancel cleanup"
    read -p "Choose option (1-3): " -n 1 -r
    echo
    
    case $REPLY in
        1)
            log_info "Proceeding with individual resource cleanup..."
            
            # Delete Cloud Function
            delete_function "$FUNCTION_NAME" "$REGION" "$PROJECT_ID"
            
            # Delete Cloud Storage bucket
            if [[ -n "$BUCKET_NAME" ]]; then
                delete_storage_bucket "$BUCKET_NAME"
            else
                log_warning "Bucket name not found, skipping bucket deletion"
            fi
            
            # Optionally disable APIs
            read -p "Disable APIs to prevent charges? (y/N): " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                disable_apis "$PROJECT_ID"
            fi
            
            # Clean up local files
            cleanup_local_files
            
            display_cleanup_summary "$PROJECT_ID"
            ;;
        2)
            log_warning "You chose to delete the entire project."
            delete_project "$PROJECT_ID"
            cleanup_local_files
            log_success "Project deletion initiated. Local files cleaned up."
            ;;
        3)
            log_info "Cleanup cancelled by user"
            exit 0
            ;;
        *)
            log_error "Invalid option selected"
            exit 1
            ;;
    esac
    
    log_success "Cleanup process completed!"
}

# Handle script interruption
trap 'log_error "Script interrupted"; exit 1' INT TERM

# Run main function
main "$@"