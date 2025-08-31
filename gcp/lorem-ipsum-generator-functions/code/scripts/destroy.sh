#!/bin/bash

# Destroy script for Lorem Ipsum Generator Cloud Functions API
# This script safely removes all resources created by the deployment

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

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if gcloud CLI is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "gcloud CLI is not installed. Please install Google Cloud CLI."
        exit 1
    fi
    
    # Check if gsutil is available
    if ! command -v gsutil &> /dev/null; then
        log_error "gsutil is not available. Please ensure Google Cloud SDK is properly installed."
        exit 1
    fi
    
    # Check if user is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        log_error "Not authenticated with Google Cloud. Please run 'gcloud auth login'."
        exit 1
    fi
    
    log_success "Prerequisites check passed"
}

# Function to load deployment information
load_deployment_info() {
    log_info "Loading deployment information..."
    
    # Check if deployment-info.txt exists
    if [ -f "deployment-info.txt" ]; then
        log_info "Found deployment-info.txt, loading configuration..."
        
        # Source the deployment info (convert format)
        export PROJECT_ID=$(grep "PROJECT_ID:" deployment-info.txt | cut -d' ' -f2)
        export REGION=$(grep "REGION:" deployment-info.txt | cut -d' ' -f2)
        export BUCKET_NAME=$(grep "BUCKET_NAME:" deployment-info.txt | cut -d' ' -f2)
        export FUNCTION_NAME=$(grep "FUNCTION_NAME:" deployment-info.txt | cut -d' ' -f2)
        export RANDOM_SUFFIX=$(grep "RANDOM_SUFFIX:" deployment-info.txt | cut -d' ' -f2)
        
        log_success "Deployment information loaded"
    else
        log_warning "deployment-info.txt not found, using environment variables or prompting for input"
        
        # Try to get from environment or prompt user
        if [ -z "$PROJECT_ID" ]; then
            export PROJECT_ID=$(gcloud config get-value project)
            if [ -z "$PROJECT_ID" ]; then
                log_error "No project ID found. Please set PROJECT_ID environment variable."
                exit 1
            fi
        fi
        
        if [ -z "$REGION" ]; then
            export REGION="us-central1"
            log_warning "Using default region: $REGION"
        fi
        
        if [ -z "$RANDOM_SUFFIX" ]; then
            read -p "Enter the random suffix used during deployment (6 characters): " RANDOM_SUFFIX
            if [ ${#RANDOM_SUFFIX} -ne 6 ]; then
                log_error "Invalid suffix length. Should be 6 characters."
                exit 1
            fi
        fi
        
        export BUCKET_NAME="lorem-cache-${RANDOM_SUFFIX}"
        export FUNCTION_NAME="lorem-generator-${RANDOM_SUFFIX}"
    fi
    
    log_info "Configuration:"
    log_info "  Project ID: $PROJECT_ID"
    log_info "  Region: $REGION"
    log_info "  Bucket Name: $BUCKET_NAME"
    log_info "  Function Name: $FUNCTION_NAME"
}

# Function to confirm destruction
confirm_destruction() {
    log_warning "⚠️  This will permanently delete the following resources:"
    echo "  🔧 Cloud Function: $FUNCTION_NAME"
    echo "  💾 Storage Bucket: $BUCKET_NAME (including all cached content)"
    echo "  📁 Local deployment files"
    echo ""
    
    if [ "$FORCE_DESTROY" != "true" ]; then
        read -p "Are you sure you want to proceed? (type 'yes' to confirm): " confirm
        if [ "$confirm" != "yes" ]; then
            log_info "Destruction cancelled by user"
            exit 0
        fi
    else
        log_warning "FORCE_DESTROY is set, proceeding without confirmation"
    fi
    
    log_info "Proceeding with resource destruction..."
}

# Function to delete Cloud Function
delete_function() {
    log_info "Deleting Cloud Function: $FUNCTION_NAME"
    
    # Check if function exists
    if gcloud functions describe "$FUNCTION_NAME" --region="$REGION" &> /dev/null; then
        # Delete the function
        if gcloud functions delete "$FUNCTION_NAME" \
            --gen2 \
            --region="$REGION" \
            --quiet; then
            log_success "Cloud Function deleted: $FUNCTION_NAME"
        else
            log_error "Failed to delete Cloud Function: $FUNCTION_NAME"
            return 1
        fi
    else
        log_warning "Cloud Function $FUNCTION_NAME not found (may already be deleted)"
    fi
}

# Function to delete Storage bucket
delete_storage_bucket() {
    log_info "Deleting Cloud Storage bucket: $BUCKET_NAME"
    
    # Check if bucket exists
    if gsutil ls -b "gs://${BUCKET_NAME}" &> /dev/null; then
        # Delete all objects in bucket first
        log_info "Removing all objects from bucket..."
        if gsutil -m rm -r "gs://${BUCKET_NAME}/**" 2>/dev/null || true; then
            log_info "Bucket contents removed"
        fi
        
        # Delete the bucket itself
        if gsutil rb "gs://${BUCKET_NAME}"; then
            log_success "Storage bucket deleted: $BUCKET_NAME"
        else
            log_error "Failed to delete storage bucket: $BUCKET_NAME"
            return 1
        fi
    else
        log_warning "Storage bucket gs://${BUCKET_NAME} not found (may already be deleted)"
    fi
}

# Function to clean up local files
cleanup_local_files() {
    log_info "Cleaning up local files..."
    
    local files_to_remove=(
        "deployment-info.txt"
        ".deployment-state"
    )
    
    for file in "${files_to_remove[@]}"; do
        if [ -f "$file" ]; then
            rm -f "$file"
            log_info "Removed: $file"
        fi
    done
    
    # Clean up environment variables
    unset PROJECT_ID REGION ZONE RANDOM_SUFFIX
    unset BUCKET_NAME FUNCTION_NAME FUNCTION_URL
    
    log_success "Local cleanup completed"
}

# Function to verify resource deletion
verify_deletion() {
    log_info "Verifying resource deletion..."
    
    local failed_deletions=()
    
    # Check if function still exists
    if gcloud functions describe "$FUNCTION_NAME" --region="$REGION" &> /dev/null; then
        failed_deletions+=("Cloud Function: $FUNCTION_NAME")
    fi
    
    # Check if bucket still exists
    if gsutil ls -b "gs://${BUCKET_NAME}" &> /dev/null; then
        failed_deletions+=("Storage Bucket: gs://${BUCKET_NAME}")
    fi
    
    if [ ${#failed_deletions[@]} -eq 0 ]; then
        log_success "✅ All resources successfully deleted"
        return 0
    else
        log_error "❌ Some resources failed to delete:"
        for resource in "${failed_deletions[@]}"; do
            echo "  - $resource"
        done
        return 1
    fi
}

# Function to handle partial cleanup
handle_partial_cleanup() {
    log_warning "Some resources may not have been deleted completely."
    echo ""
    echo "Manual cleanup commands:"
    echo "  gcloud functions delete $FUNCTION_NAME --region=$REGION --quiet"
    echo "  gsutil -m rm -r gs://$BUCKET_NAME"
    echo ""
    echo "You can also check the Google Cloud Console for any remaining resources."
}

# Main destruction function
main() {
    log_info "Starting Lorem Ipsum Generator resource cleanup..."
    
    check_prerequisites
    load_deployment_info
    confirm_destruction
    
    local cleanup_success=true
    
    # Perform cleanup in reverse order of creation
    if ! delete_function; then
        cleanup_success=false
    fi
    
    if ! delete_storage_bucket; then
        cleanup_success=false
    fi
    
    cleanup_local_files
    
    # Verify deletion
    if verify_deletion; then
        log_success "🎉 Cleanup completed successfully!"
        echo ""
        echo "All Lorem Ipsum Generator resources have been removed."
        echo "Your Google Cloud project is now clean."
    else
        handle_partial_cleanup
        exit 1
    fi
}

# Handle command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --force)
            export FORCE_DESTROY="true"
            shift
            ;;
        --project)
            export PROJECT_ID="$2"
            shift 2
            ;;
        --region)
            export REGION="$2"
            shift 2
            ;;
        --suffix)
            export RANDOM_SUFFIX="$2"
            shift 2
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --force          Skip confirmation prompt"
            echo "  --project ID     Specify project ID"
            echo "  --region REGION  Specify region"
            echo "  --suffix SUFFIX  Specify random suffix"
            echo "  --help           Show this help message"
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Run main function
main "$@"