#!/bin/bash

# Destroy script for Custom Voice Generation with Chirp 3 and Functions
# This script safely removes all resources created by the deploy script
# Following the recipe: custom-voice-generation-chirp-functions

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1${NC}"
}

# Function to load environment variables
load_environment() {
    log "Loading environment variables..."
    
    if [[ -f ".env.deploy" ]]; then
        source .env.deploy
        log "Environment variables loaded from .env.deploy"
    else
        warn "No .env.deploy file found. Please set environment variables manually:"
        echo "export PROJECT_ID=\"your-project-id\""
        echo "export BUCKET_NAME=\"your-bucket-name\""
        echo "export DB_INSTANCE=\"your-db-instance\""
        echo "export REGION=\"your-region\""
        
        # Try to get current project
        if command -v gcloud &> /dev/null; then
            current_project=$(gcloud config get-value project 2>/dev/null || echo "")
            if [[ -n "$current_project" ]]; then
                export PROJECT_ID="$current_project"
                info "Using current gcloud project: $PROJECT_ID"
            fi
        fi
        
        # Ask user to confirm destruction if no env file
        read -p "Do you want to continue with manual cleanup? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            info "Cleanup cancelled by user"
            exit 0
        fi
    fi
}

# Function to confirm destruction
confirm_destruction() {
    log "Resource Destruction Confirmation"
    echo "=================================="
    
    if [[ -n "${PROJECT_ID:-}" ]]; then
        echo "Project ID: ${PROJECT_ID}"
    fi
    if [[ -n "${BUCKET_NAME:-}" ]]; then
        echo "Bucket: ${BUCKET_NAME}"
    fi
    if [[ -n "${DB_INSTANCE:-}" ]]; then
        echo "Database Instance: ${DB_INSTANCE}"
    fi
    echo ""
    
    warn "This will permanently delete ALL resources created by the deployment script!"
    warn "This action cannot be undone!"
    echo ""
    
    read -p "Are you sure you want to proceed? Type 'yes' to confirm: " confirmation
    if [[ "$confirmation" != "yes" ]]; then
        info "Destruction cancelled by user"
        exit 0
    fi
    
    log "Destruction confirmed. Proceeding with resource cleanup..."
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        error "Google Cloud CLI (gcloud) is not installed."
        exit 1
    fi
    
    # Check if gsutil is installed
    if ! command -v gsutil &> /dev/null; then
        error "gsutil is not installed."
        exit 1
    fi
    
    # Check if authenticated with gcloud
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        error "Not authenticated with gcloud. Please run 'gcloud auth login'."
        exit 1
    fi
    
    # Set project if available
    if [[ -n "${PROJECT_ID:-}" ]]; then
        gcloud config set project "${PROJECT_ID}" || {
            error "Failed to set project ${PROJECT_ID}"
            exit 1
        }
    fi
    
    log "Prerequisites check completed"
}

# Function to delete Cloud Functions
delete_functions() {
    log "Deleting Cloud Functions..."
    
    # List of functions to delete
    local functions=(
        "profile-manager"
        "voice-synthesis"
    )
    
    for func in "${functions[@]}"; do
        info "Checking for function: ${func}"
        if gcloud functions describe "${func}" --region="${REGION:-us-central1}" &>/dev/null; then
            info "Deleting function: ${func}"
            gcloud functions delete "${func}" \
                --region="${REGION:-us-central1}" \
                --quiet || {
                warn "Failed to delete function: ${func}"
            }
            log "Function ${func} deleted successfully"
        else
            info "Function ${func} not found or already deleted"
        fi
    done
    
    log "Cloud Functions cleanup completed"
}

# Function to delete Cloud SQL instance
delete_cloud_sql() {
    log "Deleting Cloud SQL instance..."
    
    if [[ -z "${DB_INSTANCE:-}" ]]; then
        warn "DB_INSTANCE not set, skipping Cloud SQL deletion"
        return
    fi
    
    # Check if instance exists
    if gcloud sql instances describe "${DB_INSTANCE}" &>/dev/null; then
        info "Deleting Cloud SQL instance: ${DB_INSTANCE}"
        
        # Delete instance with confirmation
        gcloud sql instances delete "${DB_INSTANCE}" \
            --quiet || {
            error "Failed to delete Cloud SQL instance: ${DB_INSTANCE}"
            return 1
        }
        
        log "Cloud SQL instance ${DB_INSTANCE} deleted successfully"
        
        # Wait for deletion to complete
        info "Waiting for Cloud SQL instance deletion to complete..."
        local max_attempts=30
        local attempt=1
        
        while [[ $attempt -le $max_attempts ]]; do
            if ! gcloud sql instances describe "${DB_INSTANCE}" &>/dev/null; then
                log "Cloud SQL instance deletion confirmed"
                break
            fi
            
            info "Waiting for deletion... (attempt $attempt/$max_attempts)"
            sleep 10
            ((attempt++))
        done
        
        if [[ $attempt -gt $max_attempts ]]; then
            warn "Cloud SQL instance deletion may still be in progress"
        fi
    else
        info "Cloud SQL instance ${DB_INSTANCE} not found or already deleted"
    fi
}

# Function to delete Cloud Storage bucket
delete_storage_bucket() {
    log "Deleting Cloud Storage bucket..."
    
    if [[ -z "${BUCKET_NAME:-}" ]]; then
        warn "BUCKET_NAME not set, skipping bucket deletion"
        return
    fi
    
    # Check if bucket exists
    if gsutil ls "gs://${BUCKET_NAME}" &>/dev/null; then
        info "Deleting all objects in bucket: ${BUCKET_NAME}"
        
        # Delete all objects in bucket (including versioned objects)
        gsutil -m rm -r "gs://${BUCKET_NAME}/**" || {
            warn "Some objects may have failed to delete"
        }
        
        # Delete the bucket itself
        info "Deleting bucket: ${BUCKET_NAME}"
        gsutil rb "gs://${BUCKET_NAME}" || {
            error "Failed to delete bucket: ${BUCKET_NAME}"
            return 1
        }
        
        log "Cloud Storage bucket ${BUCKET_NAME} deleted successfully"
    else
        info "Cloud Storage bucket ${BUCKET_NAME} not found or already deleted"
    fi
}

# Function to delete IAM service account
delete_iam_resources() {
    log "Deleting IAM resources..."
    
    if [[ -z "${PROJECT_ID:-}" ]]; then
        warn "PROJECT_ID not set, skipping IAM cleanup"
        return
    fi
    
    local service_account="voice-synthesis-sa@${PROJECT_ID}.iam.gserviceaccount.com"
    
    # Check if service account exists
    if gcloud iam service-accounts describe "${service_account}" &>/dev/null; then
        info "Removing IAM policy bindings..."
        
        # Remove policy bindings (ignore errors if bindings don't exist)
        gcloud projects remove-iam-policy-binding "${PROJECT_ID}" \
            --member="serviceAccount:${service_account}" \
            --role="roles/cloudsql.client" &>/dev/null || true
        
        gcloud projects remove-iam-policy-binding "${PROJECT_ID}" \
            --member="serviceAccount:${service_account}" \
            --role="roles/storage.objectAdmin" &>/dev/null || true
        
        gcloud projects remove-iam-policy-binding "${PROJECT_ID}" \
            --member="serviceAccount:${service_account}" \
            --role="roles/cloudtts.user" &>/dev/null || true
        
        # Delete service account
        info "Deleting service account: voice-synthesis-sa"
        gcloud iam service-accounts delete "${service_account}" \
            --quiet || {
            warn "Failed to delete service account"
        }
        
        log "IAM resources cleaned up successfully"
    else
        info "Service account voice-synthesis-sa not found or already deleted"
    fi
}

# Function to clean up local files
cleanup_local_files() {
    log "Cleaning up local files..."
    
    # Remove function source code directory
    if [[ -d "voice-functions" ]]; then
        info "Removing function source code directory..."
        rm -rf voice-functions
        log "Function source code directory removed"
    fi
    
    # Remove environment file
    if [[ -f ".env.deploy" ]]; then
        info "Removing deployment environment file..."
        rm -f .env.deploy
        log "Environment file removed"
    fi
    
    # Remove any temporary files
    rm -f .voice-deploy-* 2>/dev/null || true
    
    log "Local files cleanup completed"
}

# Function to verify resource deletion
verify_deletion() {
    log "Verifying resource deletion..."
    
    local issues_found=false
    
    # Check Cloud Functions
    if [[ -n "${REGION:-}" ]]; then
        local remaining_functions
        remaining_functions=$(gcloud functions list \
            --filter="name:(profile-manager OR voice-synthesis)" \
            --format="value(name)" 2>/dev/null || true)
        
        if [[ -n "$remaining_functions" ]]; then
            warn "Some Cloud Functions may still exist: $remaining_functions"
            issues_found=true
        fi
    fi
    
    # Check Cloud SQL
    if [[ -n "${DB_INSTANCE:-}" ]]; then
        if gcloud sql instances describe "${DB_INSTANCE}" &>/dev/null; then
            warn "Cloud SQL instance ${DB_INSTANCE} may still exist"
            issues_found=true
        fi
    fi
    
    # Check Cloud Storage
    if [[ -n "${BUCKET_NAME:-}" ]]; then
        if gsutil ls "gs://${BUCKET_NAME}" &>/dev/null; then
            warn "Cloud Storage bucket ${BUCKET_NAME} may still exist"
            issues_found=true
        fi
    fi
    
    # Check Service Account
    if [[ -n "${PROJECT_ID:-}" ]]; then
        local service_account="voice-synthesis-sa@${PROJECT_ID}.iam.gserviceaccount.com"
        if gcloud iam service-accounts describe "${service_account}" &>/dev/null; then
            warn "Service account voice-synthesis-sa may still exist"
            issues_found=true
        fi
    fi
    
    if [[ "$issues_found" == true ]]; then
        warn "Some resources may not have been fully deleted. Please check manually."
        info "You can run this script again or delete remaining resources manually."
    else
        log "All resources appear to have been deleted successfully"
    fi
}

# Function to display cleanup summary
display_summary() {
    log "Cleanup Summary"
    echo "==============="
    
    echo "The following resources have been processed for deletion:"
    echo "- Cloud Functions (profile-manager, voice-synthesis)"
    echo "- Cloud SQL instance (${DB_INSTANCE:-'N/A'})"
    echo "- Cloud Storage bucket (${BUCKET_NAME:-'N/A'})"
    echo "- IAM service account (voice-synthesis-sa)"
    echo "- Local files (voice-functions/, .env.deploy)"
    echo ""
    
    if [[ -n "${PROJECT_ID:-}" ]]; then
        info "To verify no resources remain, you can check the Google Cloud Console:"
        echo "https://console.cloud.google.com/home/dashboard?project=${PROJECT_ID}"
    fi
    
    echo ""
    info "If you plan to redeploy, you can run: ./deploy.sh"
}

# Function to handle errors and partial cleanup
handle_cleanup_errors() {
    warn "Some errors occurred during cleanup. Attempting to continue..."
    
    # Try to clean up what we can
    cleanup_local_files || true
    
    echo ""
    warn "Manual cleanup may be required for some resources."
    info "Please check the Google Cloud Console for any remaining resources."
    
    if [[ -n "${PROJECT_ID:-}" ]]; then
        echo "Project: ${PROJECT_ID}"
        echo "Console: https://console.cloud.google.com/home/dashboard?project=${PROJECT_ID}"
    fi
}

# Main cleanup function
main() {
    log "Starting cleanup of Custom Voice Generation with Chirp 3 and Functions"
    
    # Set up error handling
    trap 'handle_cleanup_errors' ERR
    
    load_environment
    confirm_destruction
    check_prerequisites
    
    # Perform cleanup in reverse order of creation
    delete_functions
    delete_cloud_sql
    delete_storage_bucket
    delete_iam_resources
    cleanup_local_files
    verify_deletion
    display_summary
    
    log "Cleanup completed successfully!"
    info "All resources have been removed to avoid ongoing charges."
}

# Show help message
show_help() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -h, --help          Show this help message"
    echo "  -f, --force         Skip confirmation prompts (use with caution)"
    echo "  --keep-local        Keep local files (voice-functions/, .env.deploy)"
    echo ""
    echo "Environment Variables:"
    echo "  PROJECT_ID          GCP Project ID"
    echo "  BUCKET_NAME         Cloud Storage bucket name"
    echo "  DB_INSTANCE         Cloud SQL instance name"
    echo "  REGION              GCP region (default: us-central1)"
    echo ""
    echo "This script will:"
    echo "  1. Delete Cloud Functions (profile-manager, voice-synthesis)"
    echo "  2. Delete Cloud SQL instance and database"
    echo "  3. Delete Cloud Storage bucket and all contents"
    echo "  4. Remove IAM service account and policy bindings"
    echo "  5. Clean up local files and directories"
    echo ""
    echo "The script loads environment variables from .env.deploy if available."
}

# Parse command line arguments
FORCE_MODE=false
KEEP_LOCAL=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        -f|--force)
            FORCE_MODE=true
            shift
            ;;
        --keep-local)
            KEEP_LOCAL=true
            shift
            ;;
        *)
            error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Override confirmation function if force mode is enabled
if [[ "$FORCE_MODE" == true ]]; then
    confirm_destruction() {
        warn "Force mode enabled - skipping confirmation prompts"
        log "Proceeding with resource cleanup..."
    }
fi

# Override local cleanup if keep-local flag is set
if [[ "$KEEP_LOCAL" == true ]]; then
    cleanup_local_files() {
        info "Keeping local files as requested"
    }
fi

# Run main function
main "$@"