#!/bin/bash

# Content Syndication with Hierarchical Namespace Storage and Agent Development Kit - Destroy Script
# This script removes all resources created by the content syndication platform

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✅ $1${NC}"
}

warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️  $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ❌ $1${NC}"
}

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to validate prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command_exists gcloud; then
        error "Google Cloud CLI (gcloud) is not installed."
        exit 1
    fi
    
    # Check if user is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        error "You are not authenticated with Google Cloud. Please run: gcloud auth login"
        exit 1
    fi
    
    success "Prerequisites check passed"
}

# Function to load environment variables
load_environment() {
    log "Loading environment variables..."
    
    # Check if PROJECT_ID is set
    if [[ -z "${PROJECT_ID:-}" ]]; then
        error "PROJECT_ID environment variable is not set"
        error "Please run: export PROJECT_ID=your-project-id"
        exit 1
    fi
    
    # Set default values for optional variables
    export REGION="${REGION:-us-central1}"
    export ZONE="${ZONE:-us-central1-a}"
    
    # Try to get suffix from existing resources if not provided
    if [[ -z "${RANDOM_SUFFIX:-}" ]]; then
        # Try to find existing bucket with our naming pattern
        local existing_bucket
        existing_bucket=$(gcloud storage ls --format="value(name)" | grep "content-hns-" | head -1 | sed 's/gs:\/\///' | sed 's/content-hns-//' | sed 's/\///')
        
        if [[ -n "$existing_bucket" ]]; then
            export RANDOM_SUFFIX="$existing_bucket"
            log "Found existing resources with suffix: $RANDOM_SUFFIX"
        else
            warning "RANDOM_SUFFIX not set and no existing resources found. You may need to specify resource names manually."
            export RANDOM_SUFFIX="unknown"
        fi
    fi
    
    # Set resource names
    export BUCKET_NAME="${BUCKET_NAME:-content-hns-${RANDOM_SUFFIX}}"
    export WORKFLOW_NAME="${WORKFLOW_NAME:-content-workflow-${RANDOM_SUFFIX}}"
    export FUNCTION_NAME="${FUNCTION_NAME:-process-content-${RANDOM_SUFFIX}}"
    
    log "Using PROJECT_ID: $PROJECT_ID"
    log "Using REGION: $REGION"
    log "Using BUCKET_NAME: $BUCKET_NAME"
    log "Using WORKFLOW_NAME: $WORKFLOW_NAME"
    log "Using FUNCTION_NAME: $FUNCTION_NAME"
    
    success "Environment variables loaded"
}

# Function to confirm deletion
confirm_deletion() {
    echo ""
    warning "⚠️  DANGER: This will permanently delete the following resources:"
    echo "   - Cloud Storage Bucket: gs://$BUCKET_NAME (and all contents)"
    echo "   - Cloud Function: $FUNCTION_NAME"
    echo "   - Cloud Workflow: $WORKFLOW_NAME"
    echo "   - Local Agent Development Kit environment"
    echo "   - Test files and configuration"
    echo ""
    
    # Skip confirmation if FORCE_DELETE is set
    if [[ "${FORCE_DELETE:-}" == "true" ]]; then
        warning "FORCE_DELETE is set, skipping confirmation"
        return 0
    fi
    
    read -p "Are you sure you want to continue? (yes/no): " -r
    if [[ ! $REPLY =~ ^yes$ ]]; then
        log "Deletion cancelled by user"
        exit 0
    fi
    
    echo ""
    log "Proceeding with resource deletion..."
}

# Function to delete Cloud Workflow
delete_workflow() {
    log "Deleting Cloud Workflow: $WORKFLOW_NAME..."
    
    # Check if workflow exists
    if gcloud workflows describe "$WORKFLOW_NAME" --location="$REGION" >/dev/null 2>&1; then
        # Cancel any running executions first
        log "Checking for running workflow executions..."
        local running_executions
        running_executions=$(gcloud workflows executions list \
            --workflow="$WORKFLOW_NAME" \
            --location="$REGION" \
            --filter="state:ACTIVE" \
            --format="value(name)" 2>/dev/null || echo "")
        
        if [[ -n "$running_executions" ]]; then
            warning "Found running executions, attempting to cancel them..."
            while IFS= read -r execution; do
                if [[ -n "$execution" ]]; then
                    gcloud workflows executions cancel "$execution" \
                        --workflow="$WORKFLOW_NAME" \
                        --location="$REGION" \
                        --quiet || warning "Failed to cancel execution: $execution"
                fi
            done <<< "$running_executions"
            
            # Wait a moment for cancellations to process
            sleep 5
        fi
        
        # Delete the workflow
        if gcloud workflows delete "$WORKFLOW_NAME" \
            --location="$REGION" \
            --quiet; then
            success "Deleted Cloud Workflow: $WORKFLOW_NAME"
        else
            error "Failed to delete Cloud Workflow: $WORKFLOW_NAME"
            return 1
        fi
    else
        warning "Cloud Workflow $WORKFLOW_NAME not found or already deleted"
    fi
}

# Function to delete Cloud Function
delete_function() {
    log "Deleting Cloud Function: $FUNCTION_NAME..."
    
    # Check if function exists
    if gcloud functions describe "$FUNCTION_NAME" --region="$REGION" >/dev/null 2>&1; then
        if gcloud functions delete "$FUNCTION_NAME" \
            --region="$REGION" \
            --quiet; then
            success "Deleted Cloud Function: $FUNCTION_NAME"
        else
            error "Failed to delete Cloud Function: $FUNCTION_NAME"
            return 1
        fi
    else
        warning "Cloud Function $FUNCTION_NAME not found or already deleted"
    fi
}

# Function to delete storage bucket
delete_storage_bucket() {
    log "Deleting Storage Bucket: gs://$BUCKET_NAME..."
    
    # Check if bucket exists
    if gcloud storage ls "gs://$BUCKET_NAME" >/dev/null 2>&1; then
        log "Removing all contents from bucket..."
        
        # Remove all objects and folders recursively
        if gcloud storage rm -r "gs://$BUCKET_NAME/**" 2>/dev/null || true; then
            log "Bucket contents removed"
        else
            warning "Failed to remove some bucket contents or bucket was already empty"
        fi
        
        # Delete the bucket itself
        if gcloud storage buckets delete "gs://$BUCKET_NAME" --quiet; then
            success "Deleted Storage Bucket: gs://$BUCKET_NAME"
        else
            error "Failed to delete Storage Bucket: gs://$BUCKET_NAME"
            return 1
        fi
    else
        warning "Storage Bucket gs://$BUCKET_NAME not found or already deleted"
    fi
}

# Function to clean up local environment
cleanup_local_environment() {
    log "Cleaning up local environment..."
    
    # Remove Agent Development Kit virtual environment
    if [[ -d "adk-env" ]]; then
        log "Removing virtual environment: adk-env"
        rm -rf adk-env
        success "Removed virtual environment"
    else
        warning "Virtual environment adk-env not found"
    fi
    
    # Remove agent project structure
    if [[ -d "content-agents" ]]; then
        log "Removing agent project: content-agents"
        rm -rf content-agents
        success "Removed agent project"
    else
        warning "Agent project content-agents not found"
    fi
    
    # Remove Cloud Function source
    if [[ -d "cloud-function" ]]; then
        log "Removing Cloud Function source: cloud-function"
        rm -rf cloud-function
        success "Removed Cloud Function source"
    else
        warning "Cloud Function source directory not found"
    fi
    
    # Remove workflow definition file
    if [[ -f "content-syndication-workflow.yaml" ]]; then
        log "Removing workflow definition file"
        rm -f content-syndication-workflow.yaml
        success "Removed workflow definition file"
    else
        warning "Workflow definition file not found"
    fi
    
    # Remove test files
    local test_files=("test-video.mp4" "test-image.jpg" "test-audio.mp3" "test-document.txt")
    for file in "${test_files[@]}"; do
        if [[ -f "$file" ]]; then
            rm -f "$file"
            log "Removed test file: $file"
        fi
    done
    
    success "Local environment cleanup completed"
}

# Function to verify deletion
verify_deletion() {
    log "Verifying resource deletion..."
    
    local failed=false
    
    # Check if bucket still exists
    if gcloud storage ls "gs://$BUCKET_NAME" >/dev/null 2>&1; then
        error "Storage bucket still exists: gs://$BUCKET_NAME"
        failed=true
    else
        success "Confirmed: Storage bucket deleted"
    fi
    
    # Check if function still exists
    if gcloud functions describe "$FUNCTION_NAME" --region="$REGION" >/dev/null 2>&1; then
        error "Cloud Function still exists: $FUNCTION_NAME"
        failed=true
    else
        success "Confirmed: Cloud Function deleted"
    fi
    
    # Check if workflow still exists
    if gcloud workflows describe "$WORKFLOW_NAME" --location="$REGION" >/dev/null 2>&1; then
        error "Cloud Workflow still exists: $WORKFLOW_NAME"
        failed=true
    else
        success "Confirmed: Cloud Workflow deleted"
    fi
    
    if [[ "$failed" == "true" ]]; then
        error "Some resources failed to delete. Please check the Google Cloud Console."
        return 1
    else
        success "All resources successfully deleted"
    fi
}

# Function to display cleanup summary
display_summary() {
    log "Cleanup Summary"
    echo "===================="
    echo "Project ID: $PROJECT_ID"
    echo "Region: $REGION"
    echo ""
    echo "Resources Removed:"
    echo "- Hierarchical Namespace Storage Bucket: gs://$BUCKET_NAME"
    echo "- Cloud Function: $FUNCTION_NAME"
    echo "- Cloud Workflow: $WORKFLOW_NAME"
    echo "- Local Agent Development Kit environment"
    echo "- Test files and configuration"
    echo ""
    echo "Note: This script does not disable APIs to avoid affecting other resources."
    echo "If you want to disable APIs, run:"
    echo "  gcloud services disable storage.googleapis.com"
    echo "  gcloud services disable aiplatform.googleapis.com"
    echo "  gcloud services disable workflows.googleapis.com"
    echo "  gcloud services disable cloudfunctions.googleapis.com"
    echo ""
    success "Content Syndication Platform cleanup completed!"
}

# Function to handle errors gracefully
handle_error() {
    local exit_code=$?
    error "Cleanup failed at line $1 with exit code $exit_code"
    error "Some resources may not have been deleted. Please check manually:"
    error "- Bucket: gs://$BUCKET_NAME"
    error "- Function: $FUNCTION_NAME"
    error "- Workflow: $WORKFLOW_NAME"
    exit $exit_code
}

# Main cleanup function
main() {
    log "Starting Content Syndication Platform Cleanup"
    
    # Check prerequisites
    check_prerequisites
    
    # Load environment variables
    load_environment
    
    # Confirm deletion
    confirm_deletion
    
    # Delete resources in reverse order of creation
    log "Deleting cloud resources..."
    
    # Delete Cloud Workflow first (depends on Cloud Function)
    delete_workflow
    
    # Delete Cloud Function
    delete_function
    
    # Delete Storage Bucket and contents
    delete_storage_bucket
    
    # Clean up local environment
    cleanup_local_environment
    
    # Verify deletion
    verify_deletion
    
    # Display summary
    display_summary
}

# Set up error handling
trap 'handle_error $LINENO' ERR

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --force)
            export FORCE_DELETE="true"
            shift
            ;;
        --help|-h)
            echo "Content Syndication Platform Cleanup Script"
            echo ""
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --force    Skip confirmation prompts"
            echo "  --help     Show this help message"
            echo ""
            echo "Environment Variables:"
            echo "  PROJECT_ID      Google Cloud Project ID (required)"
            echo "  REGION          Google Cloud Region (default: us-central1)"
            echo "  RANDOM_SUFFIX   Resource name suffix (auto-detected if not set)"
            echo "  BUCKET_NAME     Storage bucket name (default: content-hns-\${RANDOM_SUFFIX})"
            echo "  WORKFLOW_NAME   Workflow name (default: content-workflow-\${RANDOM_SUFFIX})"
            echo "  FUNCTION_NAME   Function name (default: process-content-\${RANDOM_SUFFIX})"
            echo ""
            exit 0
            ;;
        *)
            error "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Run main function
main "$@"