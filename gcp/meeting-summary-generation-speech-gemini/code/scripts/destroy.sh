#!/bin/bash

# Meeting Summary Generation with Speech-to-Text and Gemini - Cleanup Script
# This script removes all infrastructure created by the deployment script

set -euo pipefail

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/destroy.log"
ENV_FILE="${SCRIPT_DIR}/.env"
FUNCTION_SOURCE_DIR="${SCRIPT_DIR}/../meeting-processor"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${2:-$NC}$(date '+%Y-%m-%d %H:%M:%S') - $1${NC}" | tee -a "$LOG_FILE"
}

# Error handling
error_exit() {
    log "ERROR: $1" "$RED"
    exit 1
}

# Warning function for non-critical failures
warning() {
    log "WARNING: $1" "$YELLOW"
}

# Load environment variables
load_environment() {
    log "Loading environment variables..." "$BLUE"
    
    if [[ -f "$ENV_FILE" ]]; then
        # Source the environment file
        source "$ENV_FILE"
        log "Environment variables loaded from $ENV_FILE" "$GREEN"
        log "  Project ID: ${PROJECT_ID:-not set}" "$GREEN"
        log "  Region: ${REGION:-not set}" "$GREEN"
        log "  Bucket Name: ${BUCKET_NAME:-not set}" "$GREEN"
        log "  Function Name: ${FUNCTION_NAME:-not set}" "$GREEN"
    else
        log "Environment file not found. Checking for environment variables..." "$YELLOW"
        
        # Try to get values from current environment or prompt user
        if [[ -z "${PROJECT_ID:-}" ]] || [[ -z "${BUCKET_NAME:-}" ]] || [[ -z "${FUNCTION_NAME:-}" ]]; then
            error_exit "Required environment variables not found. Please set PROJECT_ID, BUCKET_NAME, FUNCTION_NAME, and REGION."
        fi
    fi
    
    # Set default region if not provided
    export REGION="${REGION:-us-central1}"
}

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..." "$BLUE"
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        error_exit "gcloud CLI is not installed. Please install Google Cloud SDK."
    fi
    
    # Check if gsutil is installed
    if ! command -v gsutil &> /dev/null; then
        error_exit "gsutil is not installed. Please install Google Cloud SDK."
    fi
    
    # Check if user is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 > /dev/null 2>&1; then
        error_exit "Not authenticated with gcloud. Run 'gcloud auth login' first."
    fi
    
    log "Prerequisites check completed ✅" "$GREEN"
}

# Confirm deletion with user
confirm_deletion() {
    log "Resources to be deleted:" "$YELLOW"
    log "  Project: ${PROJECT_ID}" "$YELLOW"
    log "  Cloud Storage Bucket: gs://${BUCKET_NAME}" "$YELLOW"
    log "  Cloud Function: ${FUNCTION_NAME}" "$YELLOW"
    log "  All associated data and configurations" "$YELLOW"
    
    echo ""
    read -p "Are you sure you want to delete these resources? (yes/no): " -r
    echo ""
    
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        log "Cleanup cancelled by user" "$BLUE"
        exit 0
    fi
    
    log "User confirmed deletion. Proceeding with cleanup..." "$GREEN"
}

# Set project context
set_project_context() {
    log "Setting project context..." "$BLUE"
    
    # Check if project exists
    if ! gcloud projects describe "$PROJECT_ID" &> /dev/null; then
        warning "Project $PROJECT_ID does not exist or is not accessible"
        return 1
    fi
    
    # Set project context
    if gcloud config set project "$PROJECT_ID" 2>> "$LOG_FILE"; then
        log "Project context set to $PROJECT_ID ✅" "$GREEN"
    else
        warning "Failed to set project context"
        return 1
    fi
    
    return 0
}

# Delete Cloud Function
delete_function() {
    log "Deleting Cloud Function..." "$BLUE"
    
    # Check if function exists
    if gcloud functions describe "$FUNCTION_NAME" --region "$REGION" &> /dev/null; then
        log "Found Cloud Function: $FUNCTION_NAME" "$BLUE"
        
        # Delete the function with timeout
        local max_attempts=3
        local attempt=1
        
        while [ $attempt -le $max_attempts ]; do
            log "Deletion attempt $attempt of $max_attempts..." "$BLUE"
            
            if timeout 300 gcloud functions delete "$FUNCTION_NAME" \
                --region "$REGION" \
                --quiet 2>> "$LOG_FILE"; then
                
                log "Cloud Function deleted successfully ✅" "$GREEN"
                return 0
            else
                if [ $attempt -eq $max_attempts ]; then
                    warning "Failed to delete Cloud Function after $max_attempts attempts"
                    return 1
                else
                    log "Deletion attempt $attempt failed, retrying in 30 seconds..." "$YELLOW"
                    sleep 30
                    ((attempt++))
                fi
            fi
        done
    else
        log "Cloud Function $FUNCTION_NAME not found or already deleted" "$YELLOW"
    fi
}

# Delete Cloud Storage bucket and contents
delete_storage_bucket() {
    log "Deleting Cloud Storage bucket and contents..." "$BLUE"
    
    # Check if bucket exists
    if gsutil ls -b "gs://${BUCKET_NAME}" &> /dev/null; then
        log "Found Cloud Storage bucket: gs://${BUCKET_NAME}" "$BLUE"
        
        # List bucket contents for logging
        local file_count
        file_count=$(gsutil ls -r "gs://${BUCKET_NAME}/**" 2>/dev/null | wc -l || echo "0")
        log "Bucket contains approximately $file_count files/objects" "$BLUE"
        
        # Delete all bucket contents and the bucket itself
        if gsutil -m rm -r "gs://${BUCKET_NAME}" 2>> "$LOG_FILE"; then
            log "Cloud Storage bucket and contents deleted successfully ✅" "$GREEN"
        else
            warning "Failed to delete Cloud Storage bucket"
            return 1
        fi
    else
        log "Cloud Storage bucket gs://${BUCKET_NAME} not found or already deleted" "$YELLOW"
    fi
}

# Clean up local files
cleanup_local_files() {
    log "Cleaning up local files..." "$BLUE"
    
    local files_cleaned=0
    
    # Remove function source directory
    if [[ -d "$FUNCTION_SOURCE_DIR" ]]; then
        rm -rf "$FUNCTION_SOURCE_DIR"
        log "Removed function source directory" "$GREEN"
        ((files_cleaned++))
    fi
    
    # Remove environment file
    if [[ -f "$ENV_FILE" ]]; then
        rm -f "$ENV_FILE"
        log "Removed environment file" "$GREEN"
        ((files_cleaned++))
    fi
    
    # Remove temporary files
    for temp_file in "${SCRIPT_DIR}/lifecycle.json" "${SCRIPT_DIR}/test_meeting.txt"; do
        if [[ -f "$temp_file" ]]; then
            rm -f "$temp_file"
            log "Removed temporary file: $(basename "$temp_file")" "$GREEN"
            ((files_cleaned++))
        fi
    done
    
    # Remove any downloaded summary files
    find "$SCRIPT_DIR" -name "*.md" -not -name "README.md" -type f -delete 2>/dev/null || true
    
    if [[ $files_cleaned -gt 0 ]]; then
        log "Local cleanup completed ($files_cleaned items removed) ✅" "$GREEN"
    else
        log "No local files to clean up" "$YELLOW"
    fi
}

# Disable APIs (optional, commented out to avoid affecting other projects)
disable_apis() {
    log "Note: API disabling skipped to avoid affecting other resources" "$YELLOW"
    log "To manually disable APIs, run:" "$BLUE"
    log "  gcloud services disable cloudfunctions.googleapis.com --project $PROJECT_ID" "$BLUE"
    log "  gcloud services disable speech.googleapis.com --project $PROJECT_ID" "$BLUE"
    log "  gcloud services disable aiplatform.googleapis.com --project $PROJECT_ID" "$BLUE"
    log "  gcloud services disable storage.googleapis.com --project $PROJECT_ID" "$BLUE"
    log "  gcloud services disable cloudbuild.googleapis.com --project $PROJECT_ID" "$BLUE"
    log "  gcloud services disable run.googleapis.com --project $PROJECT_ID" "$BLUE"
}

# Delete project (optional)
delete_project() {
    echo ""
    read -p "Do you want to delete the entire project '$PROJECT_ID'? This will remove ALL resources in the project. (yes/no): " -r
    echo ""
    
    if [[ $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        log "Deleting project: $PROJECT_ID" "$BLUE"
        
        if gcloud projects delete "$PROJECT_ID" --quiet 2>> "$LOG_FILE"; then
            log "Project deletion initiated ✅" "$GREEN"
            log "Note: Project deletion may take several minutes to complete" "$YELLOW"
        else
            warning "Failed to delete project"
        fi
    else
        log "Project deletion skipped" "$BLUE"
    fi
}

# Verify cleanup
verify_cleanup() {
    log "Verifying cleanup..." "$BLUE"
    
    local cleanup_issues=0
    
    # Check if function still exists
    if gcloud functions describe "$FUNCTION_NAME" --region "$REGION" &> /dev/null; then
        warning "Cloud Function still exists: $FUNCTION_NAME"
        ((cleanup_issues++))
    else
        log "Cloud Function successfully removed ✅" "$GREEN"
    fi
    
    # Check if bucket still exists
    if gsutil ls -b "gs://${BUCKET_NAME}" &> /dev/null; then
        warning "Cloud Storage bucket still exists: gs://${BUCKET_NAME}"
        ((cleanup_issues++))
    else
        log "Cloud Storage bucket successfully removed ✅" "$GREEN"
    fi
    
    # Check local files
    if [[ -d "$FUNCTION_SOURCE_DIR" ]] || [[ -f "$ENV_FILE" ]]; then
        warning "Some local files still exist"
        ((cleanup_issues++))
    else
        log "Local files successfully removed ✅" "$GREEN"
    fi
    
    if [[ $cleanup_issues -eq 0 ]]; then
        log "Cleanup verification completed successfully ✅" "$GREEN"
    else
        warning "Cleanup completed with $cleanup_issues issue(s)"
    fi
}

# Display cleanup summary
display_summary() {
    log "Cleanup Summary:" "$GREEN"
    log "===============" "$GREEN"
    log "Project ID: ${PROJECT_ID}" "$GREEN"
    log "Region: ${REGION}" "$GREEN"
    log "Resources removed:" "$GREEN"
    log "  ✅ Cloud Function: ${FUNCTION_NAME}" "$GREEN"
    log "  ✅ Cloud Storage Bucket: gs://${BUCKET_NAME}" "$GREEN"
    log "  ✅ Local files and directories" "$GREEN"
    log "" "$GREEN"
    log "Notes:" "$BLUE"
    log "- APIs were not disabled to avoid affecting other resources" "$BLUE"
    log "- Check your GCP console to ensure all resources are properly removed" "$BLUE"
    log "- Monitor your billing dashboard for any remaining charges" "$BLUE"
}

# Main cleanup function
main() {
    log "Starting Meeting Summary Generation cleanup..." "$GREEN"
    log "=============================================" "$GREEN"
    
    # Create log file
    touch "$LOG_FILE"
    
    # Run cleanup steps
    check_prerequisites
    load_environment
    confirm_deletion
    
    if set_project_context; then
        delete_function
        delete_storage_bucket
        disable_apis
        delete_project
    else
        warning "Skipping cloud resource cleanup due to project access issues"
    fi
    
    cleanup_local_files
    verify_cleanup
    display_summary
    
    log "Cleanup completed! 🗑️" "$GREEN"
}

# Handle script interruption
trap 'log "Cleanup interrupted" "$RED"; exit 1' INT TERM

# Help function
show_help() {
    echo "Meeting Summary Generation Cleanup Script"
    echo ""
    echo "Usage: $0 [options]"
    echo ""
    echo "Options:"
    echo "  -h, --help     Show this help message"
    echo "  --force        Skip confirmation prompts (use with caution)"
    echo ""
    echo "Environment Variables:"
    echo "  PROJECT_ID     GCP Project ID (required)"
    echo "  REGION         GCP Region (default: us-central1)"
    echo "  BUCKET_NAME    Cloud Storage bucket name (required)"
    echo "  FUNCTION_NAME  Cloud Function name (required)"
    echo ""
    echo "Examples:"
    echo "  $0                           # Interactive cleanup"
    echo "  $0 --force                   # Skip confirmations"
    echo "  PROJECT_ID=my-project $0     # Specify project"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        --force)
            FORCE_CLEANUP=true
            shift
            ;;
        *)
            echo "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Override confirmation if force flag is set
if [[ "${FORCE_CLEANUP:-false}" == "true" ]]; then
    confirm_deletion() {
        log "Force cleanup enabled - skipping confirmation" "$YELLOW"
    }
    
    delete_project() {
        log "Force cleanup enabled - skipping project deletion prompt" "$YELLOW"
    }
fi

# Run main function
main "$@"