#!/bin/bash
set -euo pipefail

# Location-Aware Content Generation with Gemini and Maps - Cleanup Script
# This script safely removes all infrastructure deployed for the location-aware content generation system

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

# Configuration variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOYMENT_ENV_FILE="${SCRIPT_DIR}/deployment.env"

# Function to validate prerequisites
validate_prerequisites() {
    log_info "Validating prerequisites for cleanup..."
    
    # Check if gcloud CLI is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "Google Cloud CLI (gcloud) is not installed"
        log_error "Please install it from: https://cloud.google.com/sdk/docs/install"
        exit 1
    fi
    
    # Check if gsutil is available
    if ! command -v gsutil &> /dev/null; then
        log_error "gsutil is not available"
        log_error "Please ensure Google Cloud SDK is properly installed"
        exit 1
    fi
    
    log_success "Prerequisites validated"
}

# Function to check authentication
check_authentication() {
    log_info "Checking Google Cloud authentication..."
    
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 > /dev/null; then
        log_error "No active Google Cloud authentication found"
        log_error "Please run: gcloud auth login"
        exit 1
    fi
    
    local active_account=$(gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1)
    log_success "Authenticated as: $active_account"
}

# Function to load deployment configuration
load_deployment_config() {
    log_info "Loading deployment configuration..."
    
    if [[ ! -f "$DEPLOYMENT_ENV_FILE" ]]; then
        log_error "Deployment configuration file not found: $DEPLOYMENT_ENV_FILE"
        log_error "This may indicate that the deployment was not completed or the file was deleted"
        
        # Try to get configuration from user or environment
        if [[ -n "${PROJECT_ID:-}" ]]; then
            log_warning "Using PROJECT_ID from environment: $PROJECT_ID"
            export PROJECT_ID
            export REGION="${REGION:-us-central1}"
            export ZONE="${ZONE:-us-central1-a}"
            export FUNCTION_NAME="${FUNCTION_NAME:-generate-location-content}"
            
            # We'll need to discover other resources
            log_warning "Some resource names may need to be discovered during cleanup"
        else
            log_error "No deployment configuration available"
            log_error "Please ensure you run this script from the same location as the deployment"
            exit 1
        fi
    else
        # Source the deployment configuration
        source "$DEPLOYMENT_ENV_FILE"
        log_success "Deployment configuration loaded"
        log_info "Project ID: $PROJECT_ID"
        log_info "Region: $REGION"
        log_info "Function: $FUNCTION_NAME"
        log_info "Bucket: $BUCKET_NAME"
    fi
    
    # Set the project context
    gcloud config set project "$PROJECT_ID" --quiet
}

# Function to display resources to be deleted
show_resources_summary() {
    log_info "Resources that will be deleted:"
    echo ""
    echo "============================================"
    echo "         RESOURCES TO DELETE"
    echo "============================================"
    echo "Project ID:       $PROJECT_ID"
    echo "Region:           $REGION"
    echo "Function Name:    ${FUNCTION_NAME:-unknown}"
    echo "Storage Bucket:   ${BUCKET_NAME:-unknown}"
    echo "Service Account:  ${SA_EMAIL:-unknown}"
    echo "============================================"
    echo ""
}

# Function to confirm deletion
confirm_deletion() {
    if [[ "${FORCE_DELETE:-}" == "true" ]]; then
        log_warning "FORCE_DELETE is set, skipping confirmation"
        return 0
    fi
    
    echo -e "${YELLOW}⚠️  WARNING: This will permanently delete all resources!${NC}"
    echo ""
    echo "This action cannot be undone. All data stored in the Cloud Storage bucket"
    echo "and the deployed Cloud Function will be permanently removed."
    echo ""
    
    # Special warning for project deletion
    if [[ "${DELETE_PROJECT:-}" == "true" ]]; then
        echo -e "${RED}🚨 PROJECT DELETION ENABLED: The entire project will be deleted!${NC}"
        echo "This will remove ALL resources in the project, not just the ones created by this recipe."
        echo ""
    fi
    
    read -p "Are you sure you want to continue? (type 'yes' to confirm): " confirmation
    
    if [[ "$confirmation" != "yes" ]]; then
        log_info "Cleanup cancelled by user"
        exit 0
    fi
    
    log_warning "User confirmed deletion, proceeding with cleanup..."
}

# Function to delete Cloud Function
delete_function() {
    log_info "Deleting Cloud Function..."
    
    if [[ -z "${FUNCTION_NAME:-}" ]]; then
        log_warning "Function name not available, attempting to discover..."
        
        # Try to find functions in the region
        local functions=$(gcloud functions list --regions="$REGION" \
            --filter="name:generate-location-content" \
            --format="value(name)" 2>/dev/null || echo "")
        
        if [[ -n "$functions" ]]; then
            FUNCTION_NAME=$(echo "$functions" | head -n1)
            log_info "Discovered function: $FUNCTION_NAME"
        else
            log_warning "No matching Cloud Functions found in region $REGION"
            return 0
        fi
    fi
    
    # Check if function exists
    if gcloud functions describe "$FUNCTION_NAME" --region="$REGION" &>/dev/null; then
        log_info "Deleting Cloud Function: $FUNCTION_NAME"
        
        gcloud functions delete "$FUNCTION_NAME" \
            --region="$REGION" \
            --quiet
        
        log_success "Cloud Function deleted: $FUNCTION_NAME"
    else
        log_warning "Cloud Function not found: $FUNCTION_NAME"
    fi
}

# Function to delete storage bucket and contents
delete_storage() {
    log_info "Deleting Cloud Storage resources..."
    
    if [[ -z "${BUCKET_NAME:-}" ]]; then
        log_warning "Bucket name not available, attempting to discover..."
        
        # Try to find buckets with our naming pattern
        local buckets=$(gsutil ls -p "$PROJECT_ID" 2>/dev/null | \
            grep "gs://location-content-" || echo "")
        
        if [[ -n "$buckets" ]]; then
            BUCKET_NAME=$(echo "$buckets" | head -n1 | sed 's|gs://||' | sed 's|/||')
            log_info "Discovered bucket: $BUCKET_NAME"
        else
            log_warning "No matching storage buckets found"
            return 0
        fi
    fi
    
    # Check if bucket exists and delete it
    if gsutil ls -b "gs://${BUCKET_NAME}" &>/dev/null; then
        log_info "Deleting storage bucket and all contents: gs://$BUCKET_NAME"
        
        # Delete all objects and versions first
        log_info "Removing all objects and versions from bucket..."
        gsutil -m rm -r "gs://${BUCKET_NAME}/**" 2>/dev/null || true
        
        # Delete the bucket itself
        gsutil rb "gs://${BUCKET_NAME}"
        
        log_success "Storage bucket deleted: gs://$BUCKET_NAME"
    else
        log_warning "Storage bucket not found: gs://$BUCKET_NAME"
    fi
}

# Function to delete service account
delete_service_account() {
    log_info "Deleting service account..."
    
    if [[ -z "${SA_EMAIL:-}" ]]; then
        log_warning "Service account email not available, attempting to discover..."
        
        # Try to find service accounts with our naming pattern
        local service_accounts=$(gcloud iam service-accounts list \
            --filter="email:location-content-sa@" \
            --format="value(email)" 2>/dev/null || echo "")
        
        if [[ -n "$service_accounts" ]]; then
            SA_EMAIL=$(echo "$service_accounts" | head -n1)
            log_info "Discovered service account: $SA_EMAIL"
        else
            log_warning "No matching service accounts found"
            return 0
        fi
    fi
    
    # Check if service account exists and delete it
    if gcloud iam service-accounts describe "$SA_EMAIL" &>/dev/null; then
        log_info "Deleting service account: $SA_EMAIL"
        
        # Remove IAM bindings first (best effort)
        local roles=("roles/viewer" "roles/aiplatform.user" "roles/storage.admin")
        for role in "${roles[@]}"; do
            log_info "Removing IAM binding for role: $role"
            gcloud projects remove-iam-policy-binding "$PROJECT_ID" \
                --member="serviceAccount:${SA_EMAIL}" \
                --role="$role" \
                --quiet 2>/dev/null || true
        done
        
        # Delete the service account
        gcloud iam service-accounts delete "$SA_EMAIL" --quiet
        
        log_success "Service account deleted: $SA_EMAIL"
    else
        log_warning "Service account not found: $SA_EMAIL"
    fi
}

# Function to delete project (optional)
delete_project() {
    if [[ "${DELETE_PROJECT:-}" == "true" ]]; then
        log_warning "Deleting entire project: $PROJECT_ID"
        log_warning "This will remove ALL resources in the project!"
        
        # Final confirmation for project deletion
        if [[ "${FORCE_DELETE:-}" != "true" ]]; then
            echo ""
            echo -e "${RED}🚨 FINAL WARNING: Project deletion will remove EVERYTHING!${NC}"
            read -p "Type the project ID to confirm project deletion: " project_confirmation
            
            if [[ "$project_confirmation" != "$PROJECT_ID" ]]; then
                log_info "Project deletion cancelled - project ID did not match"
                return 0
            fi
        fi
        
        gcloud projects delete "$PROJECT_ID" --quiet
        log_success "Project deletion initiated: $PROJECT_ID"
        log_info "Note: Project deletion may take several minutes to complete"
    else
        log_info "Project deletion not requested, keeping project: $PROJECT_ID"
    fi
}

# Function to cleanup local files
cleanup_local_files() {
    log_info "Cleaning up local deployment files..."
    
    # Remove deployment configuration file
    if [[ -f "$DEPLOYMENT_ENV_FILE" ]]; then
        rm -f "$DEPLOYMENT_ENV_FILE"
        log_success "Removed deployment configuration file"
    fi
    
    # Remove test script if it exists
    local test_script="${SCRIPT_DIR}/test_deployment.py"
    if [[ -f "$test_script" ]]; then
        rm -f "$test_script"
        log_success "Removed test script"
    fi
    
    log_success "Local cleanup completed"
}

# Function to verify cleanup completion
verify_cleanup() {
    log_info "Verifying cleanup completion..."
    
    local cleanup_success=true
    
    # Check if function still exists
    if [[ -n "${FUNCTION_NAME:-}" ]] && gcloud functions describe "$FUNCTION_NAME" --region="$REGION" &>/dev/null; then
        log_error "Cloud Function still exists: $FUNCTION_NAME"
        cleanup_success=false
    fi
    
    # Check if bucket still exists
    if [[ -n "${BUCKET_NAME:-}" ]] && gsutil ls -b "gs://${BUCKET_NAME}" &>/dev/null; then
        log_error "Storage bucket still exists: gs://$BUCKET_NAME"
        cleanup_success=false
    fi
    
    # Check if service account still exists
    if [[ -n "${SA_EMAIL:-}" ]] && gcloud iam service-accounts describe "$SA_EMAIL" &>/dev/null; then
        log_error "Service account still exists: $SA_EMAIL"
        cleanup_success=false
    fi
    
    if [[ "$cleanup_success" == "true" ]]; then
        log_success "Cleanup verification completed successfully"
        return 0
    else
        log_error "Some resources may not have been deleted properly"
        return 1
    fi
}

# Function to show cleanup summary
show_cleanup_summary() {
    echo ""
    echo "============================================"
    echo "         CLEANUP SUMMARY"
    echo "============================================"
    echo "Project ID:       $PROJECT_ID"
    echo "Cleanup Time:     $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    echo ""
    
    if [[ "${DELETE_PROJECT:-}" == "true" ]]; then
        echo "✅ Project deletion initiated"
        echo "   Note: Complete project deletion may take several minutes"
    else
        echo "✅ Cloud Function removed"
        echo "✅ Storage bucket removed"
        echo "✅ Service account removed"
        echo "✅ Local files cleaned up"
    fi
    
    echo "============================================"
    echo ""
    
    if [[ "${DELETE_PROJECT:-}" != "true" ]]; then
        log_info "To verify no charges are incurred, check the Google Cloud Console:"
        log_info "https://console.cloud.google.com/billing"
    fi
}

# Main cleanup function
main() {
    log_info "Starting cleanup of Location-Aware Content Generation system..."
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --force)
                export FORCE_DELETE="true"
                log_warning "Force mode enabled - skipping confirmations"
                shift
                ;;
            --delete-project)
                export DELETE_PROJECT="true"
                log_warning "Project deletion enabled"
                shift
                ;;
            --help|-h)
                usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done
    
    # Validate prerequisites and authentication
    validate_prerequisites
    check_authentication
    
    # Load deployment configuration
    load_deployment_config
    
    # Show what will be deleted and confirm
    show_resources_summary
    confirm_deletion
    
    # Perform cleanup operations
    log_info "Beginning resource cleanup..."
    
    delete_function
    delete_storage
    delete_service_account
    
    # Project deletion (optional)
    delete_project
    
    # Cleanup local files
    cleanup_local_files
    
    # Verify cleanup completion
    if verify_cleanup; then
        show_cleanup_summary
        log_success "Cleanup completed successfully! 🎉"
    else
        log_warning "Cleanup completed with some issues"
        log_warning "Please check the Google Cloud Console to verify all resources are removed"
        exit 1
    fi
}

# Function to display usage information
usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Cleanup Location-Aware Content Generation infrastructure"
    echo ""
    echo "Options:"
    echo "  --force             Skip confirmation prompts"
    echo "  --delete-project    Delete the entire project (removes ALL resources)"
    echo "  --help              Show this help message"
    echo ""
    echo "Environment Variables (optional):"
    echo "  PROJECT_ID         Google Cloud Project ID (if deployment.env is missing)"
    echo "  REGION             Deployment region (default: us-central1)"
    echo "  FUNCTION_NAME      Cloud Function name (default: generate-location-content)"
    echo ""
    echo "Examples:"
    echo "  $0                                    # Interactive cleanup"
    echo "  $0 --force                           # Cleanup without confirmations"
    echo "  $0 --delete-project --force          # Delete entire project"
    echo "  PROJECT_ID=my-project $0             # Cleanup specific project"
    echo ""
    echo "Safety Features:"
    echo "  - Interactive confirmation for destructive operations"
    echo "  - Verification of resource deletion"
    echo "  - Graceful handling of missing resources"
    echo "  - Protection against accidental project deletion"
}

# Error handling
handle_error() {
    log_error "Cleanup failed at line $1"
    log_error "Some resources may not have been deleted"
    log_error "Please check the Google Cloud Console and clean up manually if needed"
    exit 1
}

trap 'handle_error $LINENO' ERR

# Handle command line arguments and run main function
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi