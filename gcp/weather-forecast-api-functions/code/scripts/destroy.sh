#!/bin/bash

#######################################################################
# Weather Forecast API with Cloud Functions - Cleanup Script
# 
# This script removes all resources created by the Weather Forecast API
# deployment, including the Cloud Run service, local files, and 
# optionally the entire GCP project.
#
# Prerequisites:
# - gcloud CLI installed and configured
# - Appropriate permissions to delete resources
#
# Usage:
#   chmod +x destroy.sh
#   ./destroy.sh [PROJECT_ID] [--delete-project]
#
# Examples:
#   ./destroy.sh                           # Clean up using current project
#   ./destroy.sh my-weather-project        # Clean up specific project
#   ./destroy.sh --delete-project          # Clean up and delete entire project
#   ./destroy.sh my-project --delete-project # Clean up specific project and delete it
#######################################################################

set -euo pipefail  # Exit on error, undefined vars, pipe failures

# Color codes for output formatting
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

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
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

# Configuration variables
readonly DEFAULT_REGION="us-central1"
readonly FUNCTION_NAME="weather-forecast"

# Parse command line arguments
PROJECT_ID=""
DELETE_PROJECT=false
REGION=${REGION:-$DEFAULT_REGION}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --delete-project)
                DELETE_PROJECT=true
                shift
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            *)
                if [[ -z "$PROJECT_ID" ]]; then
                    PROJECT_ID="$1"
                else
                    log_error "Unknown argument: $1"
                    show_help
                    exit 1
                fi
                shift
                ;;
        esac
    done
    
    # Get current project if not specified
    if [[ -z "$PROJECT_ID" ]]; then
        PROJECT_ID=$(gcloud config get-value project 2>/dev/null || echo "")
        if [[ -z "$PROJECT_ID" ]]; then
            log_error "No project specified and no default project configured"
            log_info "Please specify a PROJECT_ID or run: gcloud config set project YOUR_PROJECT_ID"
            exit 1
        fi
    fi
}

show_help() {
    cat << EOF
Weather Forecast API Cleanup Script

This script removes all resources created by the Weather Forecast API deployment.

Usage:
    $0 [PROJECT_ID] [--delete-project] [--help]

Arguments:
    PROJECT_ID          GCP project ID (optional, uses current project if not specified)
    --delete-project    Delete the entire GCP project after cleaning up resources
    --help, -h          Show this help message

Examples:
    $0                              # Clean up resources in current project
    $0 my-weather-project           # Clean up resources in specific project
    $0 --delete-project             # Clean up and delete entire current project
    $0 my-project --delete-project  # Clean up specific project and delete it

Warning: The --delete-project option will permanently delete the entire GCP project
and all its resources. This action cannot be undone.
EOF
}

# Validate prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "gcloud CLI is not installed. Please install it from: https://cloud.google.com/sdk/docs/install"
        exit 1
    fi
    
    # Check if gcloud is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 > /dev/null; then
        log_error "gcloud is not authenticated. Please run: gcloud auth login"
        exit 1
    fi
    
    # Verify project exists and is accessible
    if ! gcloud projects describe "$PROJECT_ID" &> /dev/null; then
        log_error "Project '$PROJECT_ID' does not exist or you don't have access to it"
        exit 1
    fi
    
    log_success "Prerequisites check completed"
}

# Confirm destructive operations
confirm_cleanup() {
    log_warning "This will delete the following resources in project '$PROJECT_ID':"
    echo "  - Cloud Run service: $FUNCTION_NAME"
    echo "  - Associated Cloud Build artifacts"
    echo "  - Function source code files (local)"
    
    if [[ "$DELETE_PROJECT" == true ]]; then
        echo
        log_warning "WARNING: --delete-project flag detected!"
        echo "This will also PERMANENTLY DELETE the entire project '$PROJECT_ID'"
        echo "and ALL resources within it. This action CANNOT be undone!"
    fi
    
    echo
    read -p "Are you sure you want to continue? (y/N): " -r
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Cleanup cancelled by user"
        exit 0
    fi
    
    if [[ "$DELETE_PROJECT" == true ]]; then
        echo
        log_error "FINAL WARNING: You are about to delete the entire project '$PROJECT_ID'"
        read -p "Type the project ID to confirm deletion: " -r
        if [[ "$REPLY" != "$PROJECT_ID" ]]; then
            log_error "Project ID confirmation failed. Cleanup cancelled."
            exit 1
        fi
    fi
}

# Set project context
set_project_context() {
    log_info "Setting project context..."
    
    # Set the project for gcloud commands
    gcloud config set project "$PROJECT_ID"
    gcloud config set compute/region "$REGION"
    gcloud config set functions/region "$REGION"
    
    log_success "Project context set to $PROJECT_ID"
}

# Delete Cloud Run service
delete_cloud_run_service() {
    log_info "Checking for Cloud Run service: $FUNCTION_NAME"
    
    # Check if the service exists
    if gcloud run services describe "$FUNCTION_NAME" --region "$REGION" &> /dev/null; then
        log_info "Deleting Cloud Run service: $FUNCTION_NAME"
        
        if gcloud run services delete "$FUNCTION_NAME" \
            --region "$REGION" \
            --quiet; then
            log_success "Cloud Run service deleted successfully"
        else
            log_error "Failed to delete Cloud Run service"
            return 1
        fi
    else
        log_info "Cloud Run service '$FUNCTION_NAME' not found (may already be deleted)"
    fi
}

# Clean up Cloud Build artifacts
cleanup_cloud_build() {
    log_info "Cleaning up Cloud Build artifacts..."
    
    # List and delete recent builds related to our function
    local builds
    builds=$(gcloud builds list \
        --filter="source.repoSource.repoName:'$FUNCTION_NAME' OR source.storageSource.object~'$FUNCTION_NAME'" \
        --format="value(id)" \
        --limit=10 2>/dev/null || echo "")
    
    if [[ -n "$builds" ]]; then
        log_info "Found Cloud Build artifacts to clean up"
        while IFS= read -r build_id; do
            if [[ -n "$build_id" ]]; then
                log_info "Cleaning up build: $build_id"
                gcloud builds cancel "$build_id" --quiet 2>/dev/null || true
            fi
        done <<< "$builds"
        log_success "Cloud Build artifacts cleaned up"
    else
        log_info "No Cloud Build artifacts found to clean up"
    fi
}

# Clean up local files
cleanup_local_files() {
    log_info "Cleaning up local files..."
    
    local files_cleaned=false
    
    # Remove function URL environment file
    if [[ -f "function_url.env" ]]; then
        rm -f function_url.env
        log_info "Removed function_url.env"
        files_cleaned=true
    fi
    
    # Remove any temporary function directories
    local temp_dirs=("weather-function" "weather-function-deployment")
    for dir in "${temp_dirs[@]}"; do
        if [[ -d "$dir" ]]; then
            rm -rf "$dir"
            log_info "Removed directory: $dir"
            files_cleaned=true
        fi
    done
    
    # Clean up any backup files
    if find . -name "*.backup" -o -name "*~" | grep -q .; then
        find . -name "*.backup" -o -name "*~" -delete
        log_info "Removed backup files"
        files_cleaned=true
    fi
    
    if [[ "$files_cleaned" == true ]]; then
        log_success "Local files cleaned up"
    else
        log_info "No local files found to clean up"
    fi
}

# Delete the entire project
delete_project() {
    if [[ "$DELETE_PROJECT" != true ]]; then
        return 0
    fi
    
    log_info "Deleting project: $PROJECT_ID"
    log_warning "This operation may take several minutes to complete..."
    
    if gcloud projects delete "$PROJECT_ID" --quiet; then
        log_success "Project deletion initiated successfully"
        log_info "Note: Complete project deletion may take up to 30 minutes"
        log_info "You can check deletion status at: https://console.cloud.google.com/cloud-resource-manager"
    else
        log_error "Failed to delete project"
        return 1
    fi
}

# Verify cleanup completion
verify_cleanup() {
    if [[ "$DELETE_PROJECT" == true ]]; then
        log_info "Project deletion initiated - skipping resource verification"
        return 0
    fi
    
    log_info "Verifying cleanup completion..."
    
    # Check if Cloud Run service still exists
    if gcloud run services describe "$FUNCTION_NAME" --region "$REGION" &> /dev/null; then
        log_warning "Cloud Run service still exists - cleanup may be incomplete"
    else
        log_success "Cloud Run service successfully removed"
    fi
    
    # Check for any remaining Cloud Functions (in case of mixed deployment)
    local functions
    functions=$(gcloud functions list --filter="name~'$FUNCTION_NAME'" --format="value(name)" 2>/dev/null || echo "")
    if [[ -n "$functions" ]]; then
        log_warning "Found remaining Cloud Functions that may need manual cleanup:"
        echo "$functions"
    fi
    
    log_success "Cleanup verification completed"
}

# Display cleanup summary
show_cleanup_summary() {
    log_info "=== Cleanup Summary ==="
    echo
    echo "Project ID: $PROJECT_ID"
    echo "Region: $REGION"
    echo "Function Name: $FUNCTION_NAME"
    echo
    
    if [[ "$DELETE_PROJECT" == true ]]; then
        echo "✅ Project deletion initiated"
        echo "✅ All resources will be deleted with the project"
        echo
        log_success "Complete project cleanup initiated!"
        log_info "The project and all its resources will be permanently deleted."
    else
        echo "✅ Cloud Run service removed"
        echo "✅ Cloud Build artifacts cleaned up"
        echo "✅ Local files removed"
        echo
        log_success "Weather Forecast API cleanup completed successfully!"
        
        echo
        log_info "If you want to completely remove the project, run:"
        echo "  $0 $PROJECT_ID --delete-project"
    fi
    
    echo
    log_info "Cleanup completed at $(date)"
}

# Error handling
handle_error() {
    local exit_code=$?
    log_error "Cleanup failed with exit code $exit_code"
    log_info "Some resources may still exist and require manual cleanup"
    
    # Provide helpful information for manual cleanup
    echo
    log_info "For manual cleanup, you can use these commands:"
    echo "  gcloud run services delete $FUNCTION_NAME --region $REGION"
    echo "  gcloud projects delete $PROJECT_ID  # (if you want to delete the entire project)"
    
    exit $exit_code
}

trap handle_error ERR

# Main cleanup flow
main() {
    parse_args "$@"
    
    log_info "Starting Weather Forecast API cleanup..."
    log_info "Project ID: $PROJECT_ID"
    log_info "Region: $REGION"
    if [[ "$DELETE_PROJECT" == true ]]; then
        log_warning "Project deletion enabled"
    fi
    echo
    
    check_prerequisites
    confirm_cleanup
    set_project_context
    delete_cloud_run_service
    cleanup_cloud_build
    cleanup_local_files
    delete_project
    verify_cleanup
    show_cleanup_summary
}

# Run main function
main "$@"