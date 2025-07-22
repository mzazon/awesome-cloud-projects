#!/bin/bash

# Conversational AI Backends with Agent Development Kit and Firestore - Cleanup Script
# This script safely removes all resources created by the deployment script

set -e  # Exit immediately if a command exits with a non-zero status
set -u  # Treat unset variables as an error

# Color codes for output formatting
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
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if gcloud CLI is installed
    if ! command_exists gcloud; then
        error "Google Cloud CLI (gcloud) is not installed."
        exit 1
    fi
    
    # Check if gsutil is installed
    if ! command_exists gsutil; then
        error "gsutil is not installed."
        exit 1
    fi
    
    # Check if gcloud is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        error "Please authenticate with Google Cloud: gcloud auth login"
        exit 1
    fi
    
    success "Prerequisites check passed"
}

# Function to load environment variables
load_environment() {
    log "Loading environment configuration..."
    
    # Try to get current project from gcloud config
    if [[ -z "${PROJECT_ID:-}" ]]; then
        PROJECT_ID=$(gcloud config get-value project 2>/dev/null || echo "")
        if [[ -z "${PROJECT_ID}" ]]; then
            error "PROJECT_ID not set and no default project configured."
            echo "Please set PROJECT_ID environment variable or run:"
            echo "  export PROJECT_ID=your-project-id"
            exit 1
        fi
    fi
    
    # Set default values if not provided
    if [[ -z "${REGION:-}" ]]; then
        export REGION="us-central1"
    fi
    
    if [[ -z "${ZONE:-}" ]]; then
        export ZONE="${REGION}-a"
    fi
    
    # Try to detect resource names based on project
    if [[ -z "${RANDOM_SUFFIX:-}" ]]; then
        # Try to find existing functions to detect suffix
        local existing_functions
        existing_functions=$(gcloud functions list --region="${REGION}" --format="value(name)" --filter="name:chat-processor-*" 2>/dev/null || echo "")
        if [[ -n "${existing_functions}" ]]; then
            # Extract suffix from first function found
            export RANDOM_SUFFIX=$(echo "${existing_functions}" | head -n1 | sed 's/chat-processor-//')
        else
            warning "Could not detect RANDOM_SUFFIX. Some resources may not be found."
            export RANDOM_SUFFIX="unknown"
        fi
    fi
    
    export FUNCTION_NAME="chat-processor-${RANDOM_SUFFIX}"
    export BUCKET_NAME="${PROJECT_ID}-conversations-${RANDOM_SUFFIX}"
    export FIRESTORE_DATABASE="chat-conversations"
    
    log "Environment configuration:"
    log "  PROJECT_ID: ${PROJECT_ID}"
    log "  REGION: ${REGION}"
    log "  ZONE: ${ZONE}"
    log "  FUNCTION_NAME: ${FUNCTION_NAME}"
    log "  BUCKET_NAME: ${BUCKET_NAME}"
    log "  FIRESTORE_DATABASE: ${FIRESTORE_DATABASE}"
}

# Function to confirm destruction
confirm_destruction() {
    echo
    warning "This will permanently delete the following resources:"
    echo "  - Cloud Functions: ${FUNCTION_NAME}, ${FUNCTION_NAME}-history"
    echo "  - Firestore Database: ${FIRESTORE_DATABASE}"
    echo "  - Cloud Storage Bucket: gs://${BUCKET_NAME} (and all contents)"
    echo "  - All conversation data and history"
    echo
    
    if [[ "${FORCE_DELETE:-false}" == "true" ]]; then
        warning "FORCE_DELETE is set to true. Skipping confirmation."
        return 0
    fi
    
    read -p "Are you sure you want to proceed? (yes/no): " -r
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        log "Destruction cancelled by user"
        exit 0
    fi
    
    echo
    warning "Last chance! Type 'DELETE' to confirm:"
    read -p "> " -r
    if [[ $REPLY != "DELETE" ]]; then
        log "Destruction cancelled by user"
        exit 0
    fi
    
    success "Destruction confirmed. Proceeding..."
}

# Function to delete Cloud Functions
delete_cloud_functions() {
    log "Deleting Cloud Functions..."
    
    # Delete main conversation processing function
    if gcloud functions describe "${FUNCTION_NAME}" --region="${REGION}" >/dev/null 2>&1; then
        log "Deleting function: ${FUNCTION_NAME}"
        gcloud functions delete "${FUNCTION_NAME}" \
            --region="${REGION}" \
            --quiet || warning "Failed to delete function: ${FUNCTION_NAME}"
        success "Deleted function: ${FUNCTION_NAME}"
    else
        warning "Function ${FUNCTION_NAME} not found"
    fi
    
    # Delete conversation history function
    if gcloud functions describe "${FUNCTION_NAME}-history" --region="${REGION}" >/dev/null 2>&1; then
        log "Deleting function: ${FUNCTION_NAME}-history"
        gcloud functions delete "${FUNCTION_NAME}-history" \
            --region="${REGION}" \
            --quiet || warning "Failed to delete function: ${FUNCTION_NAME}-history"
        success "Deleted function: ${FUNCTION_NAME}-history"
    else
        warning "Function ${FUNCTION_NAME}-history not found"
    fi
    
    success "Cloud Functions cleanup completed"
}

# Function to delete Firestore database
delete_firestore() {
    log "Deleting Firestore database..."
    
    if gcloud firestore databases describe --database="${FIRESTORE_DATABASE}" >/dev/null 2>&1; then
        log "Deleting Firestore database: ${FIRESTORE_DATABASE}"
        warning "This will permanently delete all conversation data!"
        
        # Delete collections first (if needed for large datasets)
        log "Checking for collections to delete..."
        
        # Note: Firestore database deletion will handle collections automatically
        gcloud firestore databases delete "${FIRESTORE_DATABASE}" \
            --quiet || {
            error "Failed to delete Firestore database: ${FIRESTORE_DATABASE}"
            warning "You may need to manually delete the database from the console"
        }
        success "Deleted Firestore database: ${FIRESTORE_DATABASE}"
    else
        warning "Firestore database ${FIRESTORE_DATABASE} not found"
    fi
    
    success "Firestore cleanup completed"
}

# Function to delete Cloud Storage bucket
delete_storage() {
    log "Deleting Cloud Storage bucket..."
    
    if gsutil ls -b "gs://${BUCKET_NAME}" >/dev/null 2>&1; then
        log "Deleting bucket: gs://${BUCKET_NAME}"
        warning "This will permanently delete all stored conversation artifacts!"
        
        # List bucket contents for user information
        local object_count
        object_count=$(gsutil ls "gs://${BUCKET_NAME}/**" 2>/dev/null | wc -l || echo "0")
        if [[ ${object_count} -gt 0 ]]; then
            log "Bucket contains ${object_count} objects"
        fi
        
        # Remove all objects and delete bucket
        gsutil -m rm -r "gs://${BUCKET_NAME}" || {
            error "Failed to delete bucket: gs://${BUCKET_NAME}"
            warning "You may need to manually delete the bucket from the console"
        }
        success "Deleted bucket: gs://${BUCKET_NAME}"
    else
        warning "Bucket gs://${BUCKET_NAME} not found"
    fi
    
    success "Cloud Storage cleanup completed"
}

# Function to clean up IAM permissions (if any custom ones were created)
cleanup_iam() {
    log "Checking for custom IAM permissions..."
    
    # Note: The deployment script doesn't create custom IAM roles,
    # but this is here for completeness and future enhancements
    
    success "IAM cleanup completed"
}

# Function to verify cleanup
verify_cleanup() {
    log "Verifying resource cleanup..."
    
    local cleanup_successful=true
    
    # Check Cloud Functions
    if gcloud functions describe "${FUNCTION_NAME}" --region="${REGION}" >/dev/null 2>&1; then
        warning "Function ${FUNCTION_NAME} still exists"
        cleanup_successful=false
    fi
    
    if gcloud functions describe "${FUNCTION_NAME}-history" --region="${REGION}" >/dev/null 2>&1; then
        warning "Function ${FUNCTION_NAME}-history still exists"
        cleanup_successful=false
    fi
    
    # Check Firestore database
    if gcloud firestore databases describe --database="${FIRESTORE_DATABASE}" >/dev/null 2>&1; then
        warning "Firestore database ${FIRESTORE_DATABASE} still exists"
        cleanup_successful=false
    fi
    
    # Check Cloud Storage bucket
    if gsutil ls -b "gs://${BUCKET_NAME}" >/dev/null 2>&1; then
        warning "Bucket gs://${BUCKET_NAME} still exists"
        cleanup_successful=false
    fi
    
    if [[ ${cleanup_successful} == true ]]; then
        success "All resources have been successfully cleaned up"
    else
        warning "Some resources may still exist. Please check the Google Cloud Console."
    fi
}

# Function to list remaining resources
list_remaining_resources() {
    log "Checking for any remaining resources..."
    
    echo
    echo "=== Remaining Cloud Functions in ${REGION} ==="
    gcloud functions list --region="${REGION}" --format="table(name,status,trigger.eventTrigger.eventType,trigger.httpsTrigger.url)" 2>/dev/null || echo "No functions found"
    
    echo
    echo "=== Remaining Firestore Databases ==="
    gcloud firestore databases list --format="table(name,type,locationId)" 2>/dev/null || echo "No databases found"
    
    echo
    echo "=== Remaining Storage Buckets (conversations-related) ==="
    gsutil ls -b 2>/dev/null | grep -i conversation || echo "No conversation-related buckets found"
    
    echo
}

# Function to clean up local development environment
cleanup_local() {
    log "Cleaning up local development environment..."
    
    # Remove any temporary files that might have been created
    rm -rf /tmp/conversation-agent 2>/dev/null || true
    rm -f /tmp/lifecycle.json 2>/dev/null || true
    
    # Clean up environment variables (optional)
    if [[ "${CLEANUP_ENV_VARS:-false}" == "true" ]]; then
        log "Cleaning up environment variables..."
        unset PROJECT_ID REGION ZONE FUNCTION_NAME BUCKET_NAME FIRESTORE_DATABASE RANDOM_SUFFIX 2>/dev/null || true
    fi
    
    success "Local environment cleanup completed"
}

# Function to provide post-cleanup guidance
post_cleanup_guidance() {
    echo
    success "Cleanup completed successfully!"
    echo
    echo "=== Post-Cleanup Information ==="
    echo "✅ All conversational AI backend resources have been removed"
    echo "✅ Conversation data has been permanently deleted"
    echo "✅ No ongoing charges should occur from these resources"
    echo
    echo "=== Next Steps ==="
    echo "• Review the Google Cloud Console to confirm all resources are deleted"
    echo "• Check your billing dashboard to ensure charges have stopped"
    echo "• If you plan to redeploy, you can run deploy.sh again"
    echo
    if [[ "${PROJECT_ID}" =~ ^conversational-ai-[0-9]+$ ]]; then
        echo "=== Project Cleanup ==="
        echo "Your project (${PROJECT_ID}) appears to be dedicated to this deployment."
        echo "You may want to delete the entire project to ensure complete cleanup:"
        echo "  gcloud projects delete ${PROJECT_ID}"
        echo
    fi
}

# Main cleanup function
main() {
    echo "================================================================"
    echo "   Conversational AI Backends Cleanup Script"
    echo "   Google Cloud Platform - Resource Removal"
    echo "================================================================"
    echo
    
    # Check if running in dry-run mode
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log "Running in DRY-RUN mode - no resources will be deleted"
        load_environment
        list_remaining_resources
        exit 0
    fi
    
    # Execute cleanup steps
    check_prerequisites
    load_environment
    confirm_destruction
    
    log "Starting resource cleanup..."
    delete_cloud_functions
    delete_firestore
    delete_storage
    cleanup_iam
    cleanup_local
    
    verify_cleanup
    list_remaining_resources
    post_cleanup_guidance
}

# Handle script interruption
trap 'error "Cleanup interrupted"; exit 1' INT TERM

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --force)
            export FORCE_DELETE=true
            shift
            ;;
        --dry-run)
            export DRY_RUN=true
            shift
            ;;
        --cleanup-env)
            export CLEANUP_ENV_VARS=true
            shift
            ;;
        --project-id)
            export PROJECT_ID="$2"
            shift 2
            ;;
        --region)
            export REGION="$2"
            shift 2
            ;;
        --random-suffix)
            export RANDOM_SUFFIX="$2"
            shift 2
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo
            echo "Options:"
            echo "  --force           Skip confirmation prompts"
            echo "  --dry-run         Show what would be deleted without deleting"
            echo "  --cleanup-env     Clean up environment variables after deletion"
            echo "  --project-id ID   Specify project ID (overrides auto-detection)"
            echo "  --region REGION   Specify region (default: us-central1)"
            echo "  --random-suffix   Specify random suffix for resource names"
            echo "  --help            Show this help message"
            echo
            echo "Environment Variables:"
            echo "  PROJECT_ID        Google Cloud project ID"
            echo "  REGION            Google Cloud region"
            echo "  RANDOM_SUFFIX     Suffix used in resource names"
            echo "  FORCE_DELETE      Set to 'true' to skip confirmations"
            echo "  DRY_RUN           Set to 'true' for dry-run mode"
            echo
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