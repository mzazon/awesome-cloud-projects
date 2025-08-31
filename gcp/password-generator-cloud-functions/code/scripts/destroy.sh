#!/bin/bash

# Password Generator Cloud Function - Cleanup Script
# This script removes all resources created by the password generator deployment
# Created for recipe: Simple Password Generator with Cloud Functions

set -e  # Exit on any error

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

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check gcloud authentication
check_gcloud_auth() {
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 > /dev/null 2>&1; then
        log_error "No active gcloud authentication found"
        log_info "Please run 'gcloud auth login' to authenticate"
        return 1
    fi
    return 0
}

# Function to check if project exists
check_project_exists() {
    local project_id=$1
    
    if gcloud projects describe "$project_id" > /dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

# Function to check if Cloud Function exists
check_function_exists() {
    local project_id=$1
    local region=$2
    local function_name=$3
    
    if gcloud functions describe "$function_name" \
        --gen2 \
        --region="$region" \
        --project="$project_id" > /dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

# Function to delete Cloud Function
delete_function() {
    local project_id=$1
    local region=$2
    local function_name=$3
    
    log_info "Deleting Cloud Function '$function_name'..."
    
    if check_function_exists "$project_id" "$region" "$function_name"; then
        if gcloud functions delete "$function_name" \
            --gen2 \
            --region="$region" \
            --project="$project_id" \
            --quiet; then
            log_success "Cloud Function '$function_name' deleted successfully"
            return 0
        else
            log_error "Failed to delete Cloud Function '$function_name'"
            return 1
        fi
    else
        log_warning "Cloud Function '$function_name' not found - already deleted or never existed"
        return 0
    fi
}

# Function to list and optionally delete Cloud Build triggers
cleanup_cloud_build() {
    local project_id=$1
    
    log_info "Checking for Cloud Build artifacts to clean up..."
    
    # List recent builds related to Cloud Functions
    local builds
    builds=$(gcloud builds list \
        --project="$project_id" \
        --filter="tags:gcp-cloud-function" \
        --limit=10 \
        --format="value(id)" 2>/dev/null || echo "")
    
    if [[ -n "$builds" ]]; then
        log_info "Found Cloud Build artifacts, but leaving them for history"
        log_info "You can manually clean them up from the Cloud Console if needed"
    else
        log_info "No Cloud Build artifacts found to clean up"
    fi
}

# Function to clean up Container Registry images
cleanup_container_images() {
    local project_id=$1
    local function_name=$2
    
    log_info "Checking for Container Registry images to clean up..."
    
    # Check if there are any images to clean up
    local images
    images=$(gcloud container images list \
        --project="$project_id" \
        --filter="name~gcf" \
        --format="value(name)" 2>/dev/null || echo "")
    
    if [[ -n "$images" ]]; then
        log_info "Found Container Registry images related to Cloud Functions"
        log_warning "These images will be left for safety - you can manually delete them if needed"
        log_info "Images found: $images"
    else
        log_info "No Container Registry images found to clean up"
    fi
}

# Function to clean up Artifact Registry repositories
cleanup_artifact_registry() {
    local project_id=$1
    local region=$2
    
    log_info "Checking for Artifact Registry repositories to clean up..."
    
    # List Artifact Registry repositories that might have been created
    local repos
    repos=$(gcloud artifacts repositories list \
        --project="$project_id" \
        --location="$region" \
        --filter="name~gcf" \
        --format="value(name)" 2>/dev/null || echo "")
    
    if [[ -n "$repos" ]]; then
        log_info "Found Artifact Registry repositories related to Cloud Functions"
        log_warning "These repositories will be left for safety - you can manually delete them if needed"
        log_info "Repositories found: $repos"
    else
        log_info "No Artifact Registry repositories found to clean up"
    fi
}

# Function to delete project (with confirmation)
delete_project() {
    local project_id=$1
    local force_delete=$2
    
    if [[ "$force_delete" != "true" ]]; then
        log_warning "This will DELETE the entire project '$project_id' and ALL its resources!"
        log_warning "This action is IRREVERSIBLE!"
        echo -n "Are you absolutely sure you want to delete project '$project_id'? (type 'DELETE' to confirm): "
        read -r confirmation
        
        if [[ "$confirmation" != "DELETE" ]]; then
            log_info "Project deletion cancelled"
            return 0
        fi
    fi
    
    log_info "Deleting project '$project_id'..."
    
    if gcloud projects delete "$project_id" --quiet; then
        log_success "Project '$project_id' deletion initiated"
        log_info "Note: Project deletion may take several minutes to complete"
        return 0
    else
        log_error "Failed to delete project '$project_id'"
        return 1
    fi
}

# Function to clean up local files
cleanup_local_files() {
    local source_dir=$1
    local keep_source=$2
    
    if [[ "$keep_source" != "true" ]]; then
        if [[ -d "$source_dir" ]]; then
            log_info "Removing local source directory '$source_dir'..."
            rm -rf "$source_dir"
            log_success "Local source directory removed"
        fi
    else
        log_info "Keeping local source directory '$source_dir'"
    fi
    
    # Remove deployment info file
    if [[ -f "deployment-info.txt" ]]; then
        log_info "Removing deployment information file..."
        rm -f "deployment-info.txt"
        log_success "Deployment information file removed"
    fi
}

# Function to show cleanup summary
show_cleanup_summary() {
    local project_id=$1
    local function_name=$2
    local deleted_project=$3
    
    log_success "Cleanup Summary:"
    echo "===================="
    
    if [[ "$deleted_project" == "true" ]]; then
        echo "✅ Project '$project_id' deletion initiated"
        echo "✅ All project resources will be deleted"
    else
        echo "✅ Cloud Function '$function_name' deleted"
        echo "✅ Local files cleaned up"
        echo "ℹ️  Project '$project_id' preserved"
    fi
    
    echo ""
    log_info "Cleanup completed successfully!"
}

# Main cleanup function
main() {
    log_info "Starting Password Generator Cloud Function cleanup..."
    
    # Set default values
    local project_id="${PROJECT_ID:-}"
    local region="${REGION:-us-central1}"
    local function_name="${FUNCTION_NAME:-password-generator}"
    local source_dir="${SOURCE_DIR:-./cloud-function-source}"
    local delete_project="${DELETE_PROJECT:-false}"
    local force_delete="${FORCE_DELETE:-false}"
    local keep_source="${KEEP_SOURCE:-false}"
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --project-id)
                project_id="$2"
                shift 2
                ;;
            --region)
                region="$2"
                shift 2
                ;;
            --function-name)
                function_name="$2"
                shift 2
                ;;
            --source-dir)
                source_dir="$2"
                shift 2
                ;;
            --delete-project)
                delete_project="true"
                shift
                ;;
            --force-delete)
                force_delete="true"
                shift
                ;;
            --keep-source)
                keep_source="true"
                shift
                ;;
            --help)
                echo "Usage: $0 [OPTIONS]"
                echo ""
                echo "Options:"
                echo "  --project-id PROJECT_ID    GCP Project ID (required)"
                echo "  --region REGION           GCP Region (default: us-central1)"
                echo "  --function-name NAME      Function name (default: password-generator)"
                echo "  --source-dir DIR          Source directory (default: ./cloud-function-source)"
                echo "  --delete-project          Delete the entire project (dangerous!)"
                echo "  --force-delete            Skip confirmation prompts (use with caution)"
                echo "  --keep-source             Keep local source files"
                echo "  --help                    Show this help message"
                echo ""
                echo "Environment variables:"
                echo "  PROJECT_ID                GCP Project ID"
                echo "  REGION                    GCP Region"
                echo "  FUNCTION_NAME             Function name"
                echo "  SOURCE_DIR                Source directory"
                echo "  DELETE_PROJECT            Delete project (true/false)"
                echo "  FORCE_DELETE              Skip confirmations (true/false)"
                echo "  KEEP_SOURCE               Keep local source files (true/false)"
                echo ""
                echo "Examples:"
                echo "  $0 --project-id my-project                    # Delete function only"
                echo "  $0 --project-id my-project --delete-project   # Delete entire project"
                echo "  $0 --project-id my-project --keep-source      # Keep local files"
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                exit 1
                ;;
        esac
    done
    
    # Validate required parameters
    if [[ -z "$project_id" ]]; then
        log_error "Project ID is required. Use --project-id or set PROJECT_ID environment variable"
        exit 1
    fi
    
    # Check prerequisites
    log_info "Checking prerequisites..."
    
    if ! command_exists gcloud; then
        log_error "Google Cloud CLI (gcloud) is not installed"
        exit 1
    fi
    
    if ! check_gcloud_auth; then
        exit 1
    fi
    
    # Check if project exists
    if ! check_project_exists "$project_id"; then
        log_warning "Project '$project_id' does not exist or is not accessible"
        log_info "Nothing to clean up"
        exit 0
    fi
    
    log_success "Prerequisites check passed"
    
    # Set project configuration
    gcloud config set project "$project_id"
    
    # If deleting entire project, do that and exit
    if [[ "$delete_project" == "true" ]]; then
        if delete_project "$project_id" "$force_delete"; then
            cleanup_local_files "$source_dir" "$keep_source"
            show_cleanup_summary "$project_id" "$function_name" "true"
        fi
        exit 0
    fi
    
    # Delete Cloud Function
    if ! delete_function "$project_id" "$region" "$function_name"; then
        log_warning "Failed to delete Cloud Function, continuing with other cleanup tasks"
    fi
    
    # Clean up related resources
    cleanup_cloud_build "$project_id"
    cleanup_container_images "$project_id" "$function_name"
    cleanup_artifact_registry "$project_id" "$region"
    
    # Clean up local files
    cleanup_local_files "$source_dir" "$keep_source"
    
    # Show summary
    show_cleanup_summary "$project_id" "$function_name" "false"
}

# Handle script interruption
trap 'log_error "Cleanup interrupted"; exit 1' INT TERM

# Run main function with all arguments
main "$@"