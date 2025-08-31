#!/bin/bash

# Multi-Speaker Transcription with Chirp and Cloud Functions - Cleanup Script
# This script removes all infrastructure resources created for the speech transcription system

set -e  # Exit on any error
set -u  # Exit on undefined variables

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

log_success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✅ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️  $1${NC}"
}

log_error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ❌ $1${NC}"
}

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "Google Cloud CLI (gcloud) is not installed."
        exit 1
    fi
    
    # Check if gsutil is installed
    if ! command -v gsutil &> /dev/null; then
        log_error "Google Cloud Storage utility (gsutil) is not installed."
        exit 1
    fi
    
    # Check if authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 &> /dev/null; then
        log_error "Not authenticated with Google Cloud. Run 'gcloud auth login' first."
        exit 1
    fi
    
    log_success "Prerequisites check passed"
}

# Load configuration from deployment
load_configuration() {
    log "Loading deployment configuration..."
    
    # Try to load from deployment-config.env if it exists
    if [ -f "deployment-config.env" ]; then
        log "Loading configuration from deployment-config.env..."
        source deployment-config.env
        log_success "Configuration loaded from file"
    else
        log_warning "deployment-config.env not found. Using environment variables or prompting for input."
        
        # Check if essential variables are set
        if [ -z "${PROJECT_ID:-}" ]; then
            echo -n "Enter PROJECT_ID: "
            read PROJECT_ID
            export PROJECT_ID
        fi
        
        if [ -z "${REGION:-}" ]; then
            export REGION="us-central1"
            log "Using default REGION: ${REGION}"
        fi
        
        # Try to detect bucket names from current project
        if [ -z "${INPUT_BUCKET:-}" ] || [ -z "${OUTPUT_BUCKET:-}" ]; then
            log "Attempting to detect bucket names from project..."
            
            # Set project context
            gcloud config set project ${PROJECT_ID} 2>/dev/null || true
            
            # Try to find buckets with expected naming pattern
            local buckets=$(gsutil ls 2>/dev/null | grep "gs://${PROJECT_ID}.*audio\|gs://${PROJECT_ID}.*transcript" || echo "")
            
            if [ -n "$buckets" ]; then
                log "Found potential buckets:"
                echo "$buckets"
                
                if [ -z "${INPUT_BUCKET:-}" ]; then
                    INPUT_BUCKET=$(echo "$buckets" | grep "audio" | head -n1 | sed 's|gs://||' | sed 's|/||')
                    if [ -n "$INPUT_BUCKET" ]; then
                        export INPUT_BUCKET
                        log "Detected INPUT_BUCKET: ${INPUT_BUCKET}"
                    fi
                fi
                
                if [ -z "${OUTPUT_BUCKET:-}" ]; then
                    OUTPUT_BUCKET=$(echo "$buckets" | grep "transcript" | head -n1 | sed 's|gs://||' | sed 's|/||')
                    if [ -n "$OUTPUT_BUCKET" ]; then
                        export OUTPUT_BUCKET
                        log "Detected OUTPUT_BUCKET: ${OUTPUT_BUCKET}"
                    fi
                fi
            fi
        fi
    fi
    
    # Validate required variables
    if [ -z "${PROJECT_ID:-}" ]; then
        log_error "PROJECT_ID is required but not set"
        exit 1
    fi
    
    # Set defaults for optional variables
    export REGION="${REGION:-us-central1}"
    export FUNCTION_NAME="${FUNCTION_NAME:-process-audio-transcription}"
    
    log "Configuration summary:"
    log "  PROJECT_ID: ${PROJECT_ID}"
    log "  REGION: ${REGION}"
    log "  INPUT_BUCKET: ${INPUT_BUCKET:-not set}"
    log "  OUTPUT_BUCKET: ${OUTPUT_BUCKET:-not set}"
    log "  FUNCTION_NAME: ${FUNCTION_NAME}"
}

# Confirmation prompt
confirm_destruction() {
    echo ""
    echo "⚠️  WARNING: This will permanently delete the following resources:"
    echo "   - Cloud Function: ${FUNCTION_NAME}"
    [ -n "${INPUT_BUCKET:-}" ] && echo "   - Input Storage Bucket: ${INPUT_BUCKET} (and all contents)"
    [ -n "${OUTPUT_BUCKET:-}" ] && echo "   - Output Storage Bucket: ${OUTPUT_BUCKET} (and all contents)"
    echo "   - Local function source code directory"
    echo ""
    
    # Check if running in interactive mode
    if [ -t 0 ]; then
        echo -n "Are you sure you want to proceed? (yes/no): "
        read -r response
        case "$response" in
            [yY][eE][sS]|[yY])
                log "Proceeding with resource deletion..."
                ;;
            *)
                log "Cleanup cancelled by user"
                exit 0
                ;;
        esac
    else
        log_warning "Running in non-interactive mode. Use --force flag to skip confirmation."
        if [[ "$*" != *"--force"* ]]; then
            log_error "Confirmation required. Add --force flag to skip confirmation in non-interactive mode."
            exit 1
        fi
        log "Force flag detected. Proceeding with cleanup..."
    fi
}

# Delete Cloud Function
delete_cloud_function() {
    log "Deleting Cloud Function..."
    
    # Set project context
    gcloud config set project ${PROJECT_ID}
    
    # Check if function exists
    if gcloud functions describe ${FUNCTION_NAME} --region=${REGION} &> /dev/null; then
        log "Deleting function: ${FUNCTION_NAME}"
        gcloud functions delete ${FUNCTION_NAME} \
            --region=${REGION} \
            --quiet
        
        # Wait for deletion to complete
        log "Waiting for function deletion to complete..."
        local max_attempts=30
        local attempt=0
        
        while [ $attempt -lt $max_attempts ]; do
            if ! gcloud functions describe ${FUNCTION_NAME} --region=${REGION} &> /dev/null; then
                log_success "Cloud Function deleted successfully"
                return 0
            fi
            sleep 10
            ((attempt++))
        done
        
        log_warning "Function deletion may still be in progress"
    else
        log_warning "Cloud Function ${FUNCTION_NAME} not found"
    fi
}

# Delete Cloud Storage buckets
delete_storage_buckets() {
    log "Deleting Cloud Storage buckets..."
    
    # Delete input bucket
    if [ -n "${INPUT_BUCKET:-}" ] && gsutil ls gs://${INPUT_BUCKET} &> /dev/null; then
        log "Deleting input bucket and all contents: ${INPUT_BUCKET}"
        gsutil -m rm -r gs://${INPUT_BUCKET}
        log_success "Input bucket deleted: ${INPUT_BUCKET}"
    else
        log_warning "Input bucket not found or not specified"
    fi
    
    # Delete output bucket
    if [ -n "${OUTPUT_BUCKET:-}" ] && gsutil ls gs://${OUTPUT_BUCKET} &> /dev/null; then
        log "Deleting output bucket and all contents: ${OUTPUT_BUCKET}"
        gsutil -m rm -r gs://${OUTPUT_BUCKET}
        log_success "Output bucket deleted: ${OUTPUT_BUCKET}"
    else
        log_warning "Output bucket not found or not specified"
    fi
}

# Clean up local files
cleanup_local_files() {
    log "Cleaning up local files..."
    
    # Remove function source directory
    if [ -d "transcription-function" ]; then
        rm -rf transcription-function
        log_success "Removed transcription-function directory"
    fi
    
    # Remove output directory if it exists
    if [ -d "output" ]; then
        rm -rf output
        log_success "Removed output directory"
    fi
    
    # Remove test files
    local test_files=("sample_meeting.wav" "test_samples.py")
    for file in "${test_files[@]}"; do
        if [ -f "$file" ]; then
            rm -f "$file"
            log_success "Removed test file: $file"
        fi
    done
    
    # Remove configuration file (optional - ask user)
    if [ -f "deployment-config.env" ]; then
        if [ -t 0 ] && [[ "$*" != *"--force"* ]]; then
            echo -n "Remove deployment-config.env? (y/n): "
            read -r response
            case "$response" in
                [yY])
                    rm -f deployment-config.env
                    log_success "Removed deployment-config.env"
                    ;;
                *)
                    log "Keeping deployment-config.env for future reference"
                    ;;
            esac
        else
            # In non-interactive mode or with force flag, keep the config file
            log "Keeping deployment-config.env for future reference"
        fi
    fi
}

# Disable APIs (optional)
disable_apis() {
    if [ -t 0 ] && [[ "$*" != *"--force"* ]]; then
        echo -n "Disable APIs (speech, cloudfunctions, etc.)? This may affect other resources (y/n): "
        read -r response
        case "$response" in
            [yY])
                log "Disabling APIs..."
                
                local apis=(
                    "speech.googleapis.com"
                    "cloudfunctions.googleapis.com"
                    "cloudbuild.googleapis.com"
                    "eventarc.googleapis.com"
                )
                
                for api in "${apis[@]}"; do
                    log "Disabling ${api}..."
                    gcloud services disable ${api} --force 2>/dev/null || log_warning "Could not disable ${api}"
                done
                
                log_success "APIs disabled"
                ;;
            *)
                log "Keeping APIs enabled"
                ;;
        esac
    else
        log "Skipping API disabling in non-interactive mode"
    fi
}

# Offer to delete project
offer_project_deletion() {
    if [ -t 0 ] && [[ "$*" != *"--force"* ]]; then
        echo ""
        echo "🗑️  The project ${PROJECT_ID} still exists with potentially other resources."
        echo -n "Do you want to delete the entire project? This cannot be undone (y/n): "
        read -r response
        case "$response" in
            [yY])
                log "Deleting project: ${PROJECT_ID}"
                gcloud projects delete ${PROJECT_ID} --quiet
                log_success "Project deletion initiated. It may take several minutes to complete."
                ;;
            *)
                log "Project ${PROJECT_ID} will be kept"
                ;;
        esac
    else
        log "Project deletion skipped in non-interactive mode"
        log "To delete the project manually: gcloud projects delete ${PROJECT_ID}"
    fi
}

# Verify cleanup completion
verify_cleanup() {
    log "Verifying cleanup completion..."
    
    local issues_found=false
    
    # Check if function still exists
    if gcloud functions describe ${FUNCTION_NAME} --region=${REGION} &> /dev/null; then
        log_warning "Cloud Function ${FUNCTION_NAME} still exists"
        issues_found=true
    fi
    
    # Check if buckets still exist
    if [ -n "${INPUT_BUCKET:-}" ] && gsutil ls gs://${INPUT_BUCKET} &> /dev/null; then
        log_warning "Input bucket ${INPUT_BUCKET} still exists"
        issues_found=true
    fi
    
    if [ -n "${OUTPUT_BUCKET:-}" ] && gsutil ls gs://${OUTPUT_BUCKET} &> /dev/null; then
        log_warning "Output bucket ${OUTPUT_BUCKET} still exists"
        issues_found=true
    fi
    
    # Check local files
    if [ -d "transcription-function" ]; then
        log_warning "Local transcription-function directory still exists"
        issues_found=true
    fi
    
    if [ "$issues_found" = true ]; then
        log_warning "Some resources may not have been fully cleaned up"
        log "Please check manually and remove any remaining resources"
    else
        log_success "Cleanup verification completed successfully"
    fi
}

# Main cleanup function
main() {
    echo "🧹 Starting Multi-Speaker Transcription Infrastructure Cleanup"
    echo "============================================================="
    
    check_prerequisites
    load_configuration
    confirm_destruction "$@"
    delete_cloud_function
    delete_storage_buckets
    cleanup_local_files "$@"
    disable_apis "$@"
    offer_project_deletion "$@"
    verify_cleanup
    
    echo ""
    echo "============================================================="
    log_success "Cleanup completed!"
    echo ""
    log "📋 Cleanup Summary:"
    log "  ✅ Cloud Function removed"
    log "  ✅ Storage buckets removed"
    log "  ✅ Local files cleaned up"
    echo ""
    
    if [ -f "deployment-config.env" ]; then
        log "📝 Note: deployment-config.env was preserved for reference"
    fi
    
    log "💡 If you want to redeploy later, run: ./deploy.sh"
    echo ""
}

# Display help information
show_help() {
    echo "Multi-Speaker Transcription Cleanup Script"
    echo ""
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --force    Skip confirmation prompts (use in non-interactive mode)"
    echo "  --help     Show this help message"
    echo ""
    echo "Environment Variables:"
    echo "  PROJECT_ID     Google Cloud Project ID (required)"
    echo "  REGION         Google Cloud Region (default: us-central1)"
    echo "  INPUT_BUCKET   Input storage bucket name"
    echo "  OUTPUT_BUCKET  Output storage bucket name"
    echo "  FUNCTION_NAME  Cloud Function name (default: process-audio-transcription)"
    echo ""
    echo "Examples:"
    echo "  $0                    # Interactive cleanup"
    echo "  $0 --force           # Non-interactive cleanup"
    echo "  PROJECT_ID=my-project $0  # Cleanup with specific project"
    echo ""
}

# Handle command line arguments
case "${1:-}" in
    --help|-h)
        show_help
        exit 0
        ;;
    *)
        # Handle script interruption
        trap 'log_error "Cleanup interrupted. Some resources may still exist."; exit 1' INT TERM
        
        # Run main function
        main "$@"
        ;;
esac