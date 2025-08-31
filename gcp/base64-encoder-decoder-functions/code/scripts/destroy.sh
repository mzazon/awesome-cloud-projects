#!/bin/bash

# Base64 Encoder Decoder Functions - Cleanup Script
# This script safely removes all resources created by the deployment script
# Recipe: Base64 Encoder Decoder with Cloud Functions

set -e  # Exit on any error
set -u  # Exit on undefined variables

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
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to validate prerequisites
validate_prerequisites() {
    log_info "Validating prerequisites..."
    
    # Check if gcloud CLI is installed
    if ! command_exists gcloud; then
        log_error "Google Cloud CLI (gcloud) is not installed"
        log_error "Install it from: https://cloud.google.com/sdk/docs/install"
        exit 1
    fi
    
    # Check if user is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 >/dev/null 2>&1; then
        log_error "Not authenticated with Google Cloud"
        log_error "Run: gcloud auth login"
        exit 1
    fi
    
    log_success "Prerequisites validated"
}

# Function to load deployment information
load_deployment_info() {
    local info_file="deployment-info.json"
    
    if [ -f "$info_file" ]; then
        log_info "Loading deployment information from $info_file..."
        
        # Extract information from JSON file using Python
        if command_exists python3; then
            PROJECT_ID=$(python3 -c "import json; print(json.load(open('$info_file'))['project_id'])" 2>/dev/null || echo "")
            REGION=$(python3 -c "import json; print(json.load(open('$info_file'))['region'])" 2>/dev/null || echo "")
            BUCKET_NAME=$(python3 -c "import json; print(json.load(open('$info_file'))['bucket_name'])" 2>/dev/null || echo "")
            ENCODER_FUNCTION=$(python3 -c "import json; print(json.load(open('$info_file'))['encoder_function']['name'])" 2>/dev/null || echo "")
            DECODER_FUNCTION=$(python3 -c "import json; print(json.load(open('$info_file'))['decoder_function']['name'])" 2>/dev/null || echo "")
        fi
        
        if [ -n "$PROJECT_ID" ] && [ -n "$REGION" ] && [ -n "$BUCKET_NAME" ]; then
            log_success "Loaded deployment information:"
            log_info "  Project ID: $PROJECT_ID"
            log_info "  Region: $REGION"
            log_info "  Bucket Name: $BUCKET_NAME"
            log_info "  Encoder Function: $ENCODER_FUNCTION"
            log_info "  Decoder Function: $DECODER_FUNCTION"
            return 0
        else
            log_warning "Could not parse deployment information from $info_file"
            return 1
        fi
    else
        log_warning "Deployment info file '$info_file' not found"
        return 1
    fi
}

# Function to prompt for manual configuration
prompt_manual_configuration() {
    log_info "Manual configuration required..."
    
    # Get current project if set
    local current_project
    current_project=$(gcloud config get-value project 2>/dev/null || echo "")
    
    if [ -n "$current_project" ]; then
        read -p "Current project is '$current_project'. Use this project for cleanup? (y/n): " use_current
        if [[ $use_current =~ ^[Yy]$ ]]; then
            PROJECT_ID="$current_project"
        else
            read -p "Enter the Google Cloud Project ID to clean up: " PROJECT_ID
        fi
    else
        read -p "Enter the Google Cloud Project ID to clean up: " PROJECT_ID
    fi
    
    # Validate project ID format
    if [[ ! "$PROJECT_ID" =~ ^[a-z][a-z0-9-]{4,28}[a-z0-9]$ ]]; then
        log_error "Invalid project ID format"
        exit 1
    fi
    
    read -p "Enter the region where resources were deployed (default: us-central1): " REGION
    REGION=${REGION:-us-central1}
    
    read -p "Enter the Cloud Storage bucket name to delete (leave empty to skip): " BUCKET_NAME
    
    read -p "Enter the encoder function name (default: base64-encoder): " ENCODER_FUNCTION
    ENCODER_FUNCTION=${ENCODER_FUNCTION:-base64-encoder}
    
    read -p "Enter the decoder function name (default: base64-decoder): " DECODER_FUNCTION
    DECODER_FUNCTION=${DECODER_FUNCTION:-base64-decoder}
    
    log_info "Manual configuration:"
    log_info "  Project ID: $PROJECT_ID"
    log_info "  Region: $REGION"
    log_info "  Bucket Name: ${BUCKET_NAME:-"(skip)"}"
    log_info "  Encoder Function: $ENCODER_FUNCTION"
    log_info "  Decoder Function: $DECODER_FUNCTION"
}

# Function to confirm cleanup
confirm_cleanup() {
    log_warning "⚠️  WARNING: This will permanently delete the following resources:"
    
    if [ -n "${BUCKET_NAME:-}" ]; then
        log_warning "  - Cloud Storage bucket: gs://$BUCKET_NAME (and all contents)"
    fi
    
    log_warning "  - Cloud Function: $ENCODER_FUNCTION"
    log_warning "  - Cloud Function: $DECODER_FUNCTION"
    log_warning "  - Local source code directories"
    log_warning ""
    
    read -p "Are you sure you want to proceed with cleanup? Type 'yes' to confirm: " confirm
    if [ "$confirm" != "yes" ]; then
        log_info "Cleanup cancelled"
        exit 0
    fi
    
    log_info "Proceeding with resource cleanup..."
}

# Function to set up GCP configuration
setup_gcp_config() {
    log_info "Setting up Google Cloud configuration..."
    
    # Set project and region
    gcloud config set project "$PROJECT_ID"
    gcloud config set compute/region "$REGION"
    gcloud config set functions/region "$REGION"
    
    # Verify project exists and is accessible
    if ! gcloud projects describe "$PROJECT_ID" >/dev/null 2>&1; then
        log_error "Project '$PROJECT_ID' does not exist or is not accessible"
        exit 1
    fi
    
    log_success "Google Cloud configuration completed"
}

# Function to delete Cloud Functions
delete_functions() {
    log_info "Deleting Cloud Functions..."
    
    # Delete encoder function
    if gcloud functions describe "$ENCODER_FUNCTION" --region="$REGION" >/dev/null 2>&1; then
        log_info "Deleting encoder function: $ENCODER_FUNCTION"
        if gcloud functions delete "$ENCODER_FUNCTION" --region="$REGION" --quiet; then
            log_success "Deleted encoder function: $ENCODER_FUNCTION"
        else
            log_error "Failed to delete encoder function: $ENCODER_FUNCTION"
        fi
    else
        log_warning "Encoder function '$ENCODER_FUNCTION' not found, skipping"
    fi
    
    # Delete decoder function
    if gcloud functions describe "$DECODER_FUNCTION" --region="$REGION" >/dev/null 2>&1; then
        log_info "Deleting decoder function: $DECODER_FUNCTION"
        if gcloud functions delete "$DECODER_FUNCTION" --region="$REGION" --quiet; then
            log_success "Deleted decoder function: $DECODER_FUNCTION"
        else
            log_error "Failed to delete decoder function: $DECODER_FUNCTION"
        fi
    else
        log_warning "Decoder function '$DECODER_FUNCTION' not found, skipping"
    fi
    
    log_success "Cloud Functions cleanup completed"
}

# Function to delete Cloud Storage bucket
delete_storage_bucket() {
    if [ -z "${BUCKET_NAME:-}" ]; then
        log_info "No bucket name provided, skipping bucket deletion"
        return 0
    fi
    
    log_info "Deleting Cloud Storage bucket..."
    
    # Check if bucket exists
    if gsutil ls -p "$PROJECT_ID" "gs://$BUCKET_NAME" >/dev/null 2>&1; then
        log_info "Deleting bucket contents and bucket: gs://$BUCKET_NAME"
        
        # Delete all objects in the bucket first
        if gsutil -m rm -r "gs://$BUCKET_NAME/**" 2>/dev/null || true; then
            log_info "Deleted bucket contents"
        fi
        
        # Delete the bucket itself
        if gsutil rb "gs://$BUCKET_NAME"; then
            log_success "Deleted Cloud Storage bucket: gs://$BUCKET_NAME"
        else
            log_error "Failed to delete Cloud Storage bucket: gs://$BUCKET_NAME"
            log_warning "You may need to delete it manually from the console"
        fi
    else
        log_warning "Bucket 'gs://$BUCKET_NAME' not found, skipping"
    fi
}

# Function to clean up local files
cleanup_local_files() {
    log_info "Cleaning up local files..."
    
    local dirs_to_remove=("encoder-function" "decoder-function")
    local files_to_remove=("deployment-info.json" "test-file.txt")
    
    # Remove directories
    for dir in "${dirs_to_remove[@]}"; do
        if [ -d "$dir" ]; then
            log_info "Removing directory: $dir"
            rm -rf "$dir"
            log_success "Removed directory: $dir"
        fi
    done
    
    # Remove files
    for file in "${files_to_remove[@]}"; do
        if [ -f "$file" ]; then
            log_info "Removing file: $file"
            rm -f "$file"
            log_success "Removed file: $file"
        fi
    done
    
    log_success "Local cleanup completed"
}

# Function to verify cleanup completion
verify_cleanup() {
    log_info "Verifying cleanup completion..."
    
    local cleanup_errors=0
    
    # Check if functions are deleted
    if gcloud functions describe "$ENCODER_FUNCTION" --region="$REGION" >/dev/null 2>&1; then
        log_warning "Encoder function '$ENCODER_FUNCTION' still exists"
        cleanup_errors=$((cleanup_errors + 1))
    fi
    
    if gcloud functions describe "$DECODER_FUNCTION" --region="$REGION" >/dev/null 2>&1; then
        log_warning "Decoder function '$DECODER_FUNCTION' still exists"
        cleanup_errors=$((cleanup_errors + 1))
    fi
    
    # Check if bucket is deleted
    if [ -n "${BUCKET_NAME:-}" ] && gsutil ls -p "$PROJECT_ID" "gs://$BUCKET_NAME" >/dev/null 2>&1; then
        log_warning "Bucket 'gs://$BUCKET_NAME' still exists"
        cleanup_errors=$((cleanup_errors + 1))
    fi
    
    # Check local directories
    if [ -d "encoder-function" ] || [ -d "decoder-function" ]; then
        log_warning "Local function directories still exist"
        cleanup_errors=$((cleanup_errors + 1))
    fi
    
    if [ $cleanup_errors -eq 0 ]; then
        log_success "✅ All resources cleaned up successfully"
    else
        log_warning "⚠️  Some resources may still exist. Check the warnings above."
        log_info "You may need to clean them up manually from the Google Cloud Console"
    fi
}

# Function to display cleanup summary
display_cleanup_summary() {
    log_info "=== CLEANUP SUMMARY ==="
    log_success "✅ Attempted to delete Cloud Functions:"
    log_info "  - $ENCODER_FUNCTION"
    log_info "  - $DECODER_FUNCTION"
    
    if [ -n "${BUCKET_NAME:-}" ]; then
        log_success "✅ Attempted to delete Cloud Storage bucket:"
        log_info "  - gs://$BUCKET_NAME"
    fi
    
    log_success "✅ Cleaned up local files and directories"
    log_info ""
    log_info "Cleanup process completed!"
    log_info "You can verify resource deletion in the Google Cloud Console:"
    log_info "  - Cloud Functions: https://console.cloud.google.com/functions"
    log_info "  - Cloud Storage: https://console.cloud.google.com/storage"
    log_info "======================"
}

# Function to handle automatic cleanup (non-interactive mode)
auto_cleanup() {
    log_info "Running in automatic cleanup mode..."
    
    # Load deployment info or exit if not found
    if ! load_deployment_info; then
        log_error "Cannot run automatic cleanup without deployment info"
        log_error "Run with manual mode: $0 --manual"
        exit 1
    fi
    
    # Set up configuration
    setup_gcp_config
    
    # Delete resources
    delete_functions
    delete_storage_bucket
    cleanup_local_files
    
    # Verify cleanup
    verify_cleanup
    
    # Display summary
    display_cleanup_summary
}

# Function to handle manual cleanup (interactive mode)
manual_cleanup() {
    log_info "Running in manual cleanup mode..."
    
    # Try to load deployment info, prompt if not available
    if ! load_deployment_info; then
        prompt_manual_configuration
    fi
    
    # Confirm cleanup
    confirm_cleanup
    
    # Set up configuration
    setup_gcp_config
    
    # Delete resources
    delete_functions
    delete_storage_bucket
    cleanup_local_files
    
    # Verify cleanup
    verify_cleanup
    
    # Display summary
    display_cleanup_summary
}

# Function to display help
display_help() {
    echo "Base64 Encoder Decoder Functions - Cleanup Script"
    echo ""
    echo "Usage:"
    echo "  $0                    # Interactive cleanup (default)"
    echo "  $0 --manual           # Force manual configuration"
    echo "  $0 --auto             # Automatic cleanup using deployment-info.json"
    echo "  $0 --help             # Display this help message"
    echo ""
    echo "Options:"
    echo "  --manual              Prompt for all configuration values"
    echo "  --auto                Use deployment-info.json without prompts"
    echo "  --help                Show this help message"
    echo ""
    echo "This script safely removes all resources created by the deployment script:"
    echo "  - Cloud Functions (encoder and decoder)"
    echo "  - Cloud Storage bucket and contents"
    echo "  - Local source code directories"
    echo ""
}

# Main cleanup function
main() {
    local mode="${1:-interactive}"
    
    case "$mode" in
        --help|-h)
            display_help
            exit 0
            ;;
        --auto)
            log_info "Starting automatic cleanup of Base64 Encoder Decoder Functions..."
            validate_prerequisites
            auto_cleanup
            ;;
        --manual)
            log_info "Starting manual cleanup of Base64 Encoder Decoder Functions..."
            validate_prerequisites
            manual_cleanup
            ;;
        *)
            log_info "Starting interactive cleanup of Base64 Encoder Decoder Functions..."
            validate_prerequisites
            manual_cleanup
            ;;
    esac
    
    log_success "Cleanup process completed!"
}

# Cleanup function for script interruption
cleanup_on_exit() {
    local exit_code=$?
    if [ $exit_code -ne 0 ]; then
        log_error "Cleanup failed with exit code $exit_code"
        log_info "Some resources may still exist and need manual cleanup"
    fi
}

# Set trap for cleanup
trap cleanup_on_exit EXIT

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi