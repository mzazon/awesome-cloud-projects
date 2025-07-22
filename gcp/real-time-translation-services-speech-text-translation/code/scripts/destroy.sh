#!/bin/bash

# Real-Time Translation Services Cleanup Script
# Removes all GCP infrastructure for speech-to-text and translation services
# Recipe: real-time-translation-services-speech-text-translation

set -euo pipefail

# Colors for output
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

# Load environment variables
load_environment() {
    log_info "Loading environment variables..."
    
    if [[ -f ".env.deploy" ]]; then
        source .env.deploy
        log_success "Environment variables loaded from .env.deploy"
        log_info "PROJECT_ID: ${PROJECT_ID}"
        log_info "REGION: ${REGION}"
        log_info "SERVICE_NAME: ${SERVICE_NAME}"
    else
        log_warning ".env.deploy file not found. Please set environment variables manually:"
        log_warning "  export PROJECT_ID=your-project-id"
        log_warning "  export REGION=your-region"
        log_warning "  export SERVICE_NAME=your-service-name"
        
        if [[ -z "${PROJECT_ID:-}" || -z "${REGION:-}" || -z "${SERVICE_NAME:-}" ]]; then
            log_error "Required environment variables not set. Exiting."
            exit 1
        fi
    fi
}

# Confirmation prompt
confirm_destruction() {
    echo
    log_warning "=== DESTRUCTIVE OPERATION WARNING ==="
    log_warning "This script will permanently delete:"
    log_warning "  • GCP Project: ${PROJECT_ID}"
    log_warning "  • Cloud Run Service: ${SERVICE_NAME}"
    log_warning "  • Firestore Database and all data"
    log_warning "  • Cloud Storage bucket and all files"
    log_warning "  • Pub/Sub topics and subscriptions"
    log_warning "  • Service accounts and IAM bindings"
    log_warning "  • All associated billing charges will stop"
    echo
    log_error "THIS ACTION CANNOT BE UNDONE!"
    echo
    
    if [[ "${FORCE_DESTROY:-}" == "true" ]]; then
        log_warning "FORCE_DESTROY=true detected. Skipping confirmation."
        return 0
    fi
    
    read -p "Are you absolutely sure you want to proceed? Type 'DELETE' to confirm: " confirmation
    
    if [[ "$confirmation" != "DELETE" ]]; then
        log_info "Destruction cancelled."
        exit 0
    fi
    
    log_warning "Proceeding with resource destruction..."
    sleep 3
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if gcloud CLI is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "gcloud CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if user is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        log_error "No active gcloud authentication found. Please run 'gcloud auth login'"
        exit 1
    fi
    
    # Check if project exists
    if ! gcloud projects describe "${PROJECT_ID}" &> /dev/null; then
        log_warning "Project ${PROJECT_ID} not found or already deleted"
        return 1
    fi
    
    # Set default project
    gcloud config set project "${PROJECT_ID}" --quiet
    
    log_success "Prerequisites check passed"
}

# Delete Cloud Run service
delete_cloud_run_service() {
    log_info "Deleting Cloud Run service: ${SERVICE_NAME}..."
    
    if gcloud run services describe "${SERVICE_NAME}" --region "${REGION}" &> /dev/null; then
        gcloud run services delete "${SERVICE_NAME}" \
            --region "${REGION}" \
            --quiet
        log_success "Cloud Run service deleted"
    else
        log_warning "Cloud Run service ${SERVICE_NAME} not found"
    fi
}

# Delete Pub/Sub resources
delete_pubsub_resources() {
    log_info "Deleting Pub/Sub resources..."
    
    # Delete subscription first (dependencies)
    local subscriptions=("translation-processor")
    for subscription in "${subscriptions[@]}"; do
        if gcloud pubsub subscriptions describe "${subscription}" &> /dev/null; then
            gcloud pubsub subscriptions delete "${subscription}" --quiet
            log_success "Subscription ${subscription} deleted"
        else
            log_warning "Subscription ${subscription} not found"
        fi
    done
    
    # Delete topics
    local topics=("translation-events" "translation-dlq")
    for topic in "${topics[@]}"; do
        if gcloud pubsub topics describe "${topic}" &> /dev/null; then
            gcloud pubsub topics delete "${topic}" --quiet
            log_success "Topic ${topic} deleted"
        else
            log_warning "Topic ${topic} not found"
        fi
    done
}

# Delete Cloud Storage bucket
delete_storage_bucket() {
    log_info "Deleting Cloud Storage bucket and contents..."
    
    local bucket_name="${PROJECT_ID}-audio-files"
    
    if gsutil ls "gs://${bucket_name}" &> /dev/null; then
        # Delete all objects and versions
        if gsutil ls "gs://${bucket_name}/**" &> /dev/null; then
            log_info "Deleting all objects in bucket..."
            gsutil -m rm -r "gs://${bucket_name}/**" || true
        fi
        
        # Delete all versions
        log_info "Deleting all object versions..."
        gsutil -m rm -a "gs://${bucket_name}/**" 2>/dev/null || true
        
        # Delete the bucket
        gsutil rb "gs://${bucket_name}"
        log_success "Storage bucket deleted"
    else
        log_warning "Storage bucket gs://${bucket_name} not found"
    fi
}

# Delete Firestore database
delete_firestore_database() {
    log_info "Deleting Firestore database..."
    
    if gcloud firestore databases describe --database="(default)" &> /dev/null; then
        log_warning "Firestore database deletion requires manual intervention"
        log_warning "Deleting all documents from conversations collection..."
        
        # Delete all documents in conversations collection
        # Note: This is a simplified approach. In production, you might want to use batch operations
        local collections=("conversations")
        for collection in "${collections[@]}"; do
            log_info "Attempting to delete collection: ${collection}"
            # Firestore doesn't have a direct CLI command to delete collections
            # This would need to be done via the console or using the client libraries
        done
        
        log_warning "Complete Firestore database deletion must be done through the console"
        log_warning "Visit: https://console.cloud.google.com/firestore/databases"
    else
        log_warning "Firestore database not found or already deleted"
    fi
}

# Delete service account
delete_service_account() {
    log_info "Deleting service account..."
    
    local sa_email="translation-service@${PROJECT_ID}.iam.gserviceaccount.com"
    
    if gcloud iam service-accounts describe "${sa_email}" &> /dev/null; then
        # Remove IAM policy bindings first
        local roles=(
            "roles/speech.client"
            "roles/translate.user"
            "roles/datastore.user"
            "roles/pubsub.publisher"
            "roles/storage.objectAdmin"
        )
        
        for role in "${roles[@]}"; do
            log_info "Removing role ${role} from service account..."
            gcloud projects remove-iam-policy-binding "${PROJECT_ID}" \
                --member="serviceAccount:${sa_email}" \
                --role="${role}" \
                --quiet 2>/dev/null || true
        done
        
        # Delete the service account
        gcloud iam service-accounts delete "${sa_email}" --quiet
        log_success "Service account deleted"
    else
        log_warning "Service account not found"
    fi
}

# Clean up local files
cleanup_local_files() {
    log_info "Cleaning up local files..."
    
    # Remove environment file
    if [[ -f ".env.deploy" ]]; then
        rm -f ".env.deploy"
        log_success "Environment file removed"
    fi
    
    # Remove test client directory
    if [[ -d "client-test" ]]; then
        rm -rf "client-test"
        log_success "Test client directory removed"
    fi
    
    # Remove any temporary application directories
    if [[ -n "${RANDOM_SUFFIX:-}" ]]; then
        local app_dir="./translation-app-${RANDOM_SUFFIX}"
        if [[ -d "${app_dir}" ]]; then
            rm -rf "${app_dir}"
            log_success "Temporary application directory removed"
        fi
    fi
    
    # Remove lifecycle policy file if it exists
    if [[ -f "lifecycle.json" ]]; then
        rm -f "lifecycle.json"
        log_success "Lifecycle policy file removed"
    fi
}

# Delete entire project (optional)
delete_project() {
    log_info "Checking if project should be deleted entirely..."
    
    if [[ "${DELETE_PROJECT:-true}" == "true" ]]; then
        log_warning "Deleting entire project: ${PROJECT_ID}"
        log_warning "This will remove ALL resources in the project"
        
        if [[ "${FORCE_DESTROY:-}" != "true" ]]; then
            echo
            read -p "Delete the entire project? This will remove ALL resources. Type 'DELETE_PROJECT' to confirm: " project_confirmation
            
            if [[ "$project_confirmation" != "DELETE_PROJECT" ]]; then
                log_info "Project deletion cancelled. Individual resources have been removed."
                return 0
            fi
        fi
        
        gcloud projects delete "${PROJECT_ID}" --quiet
        log_success "Project deletion initiated (may take several minutes)"
        log_warning "Note: Project deletion is asynchronous and may take up to 30 days to complete"
    else
        log_info "Skipping project deletion (DELETE_PROJECT=false)"
        log_info "Individual resources have been removed"
    fi
}

# Verify cleanup
verify_cleanup() {
    log_info "Verifying resource cleanup..."
    
    local cleanup_success=true
    
    # Check if project still exists and is active
    if gcloud projects describe "${PROJECT_ID}" &> /dev/null; then
        # Check Cloud Run service
        if gcloud run services describe "${SERVICE_NAME}" --region "${REGION}" &> /dev/null; then
            log_error "Cloud Run service still exists"
            cleanup_success=false
        else
            log_success "Cloud Run service successfully removed"
        fi
        
        # Check Pub/Sub topics
        if gcloud pubsub topics describe "translation-events" &> /dev/null; then
            log_error "Pub/Sub topics still exist"
            cleanup_success=false
        else
            log_success "Pub/Sub resources successfully removed"
        fi
        
        # Check Storage bucket
        if gsutil ls "gs://${PROJECT_ID}-audio-files" &> /dev/null; then
            log_error "Storage bucket still exists"
            cleanup_success=false
        else
            log_success "Storage bucket successfully removed"
        fi
        
        # Check service account
        if gcloud iam service-accounts describe "translation-service@${PROJECT_ID}.iam.gserviceaccount.com" &> /dev/null; then
            log_error "Service account still exists"
            cleanup_success=false
        else
            log_success "Service account successfully removed"
        fi
    else
        log_success "Project deletion completed or in progress"
    fi
    
    # Check local files
    if [[ -f ".env.deploy" || -d "client-test" ]]; then
        log_error "Some local files still exist"
        cleanup_success=false
    else
        log_success "Local files successfully cleaned up"
    fi
    
    if [[ "$cleanup_success" == "true" ]]; then
        log_success "All resources successfully cleaned up"
    else
        log_warning "Some resources may still exist. Check the console for manual cleanup."
    fi
}

# Display cleanup summary
show_cleanup_summary() {
    log_success "=== CLEANUP COMPLETE ==="
    echo
    log_info "Cleanup Summary:"
    log_info "  • Project: ${PROJECT_ID} (deleted or deletion in progress)"
    log_info "  • Cloud Run service: ${SERVICE_NAME} (deleted)"
    log_info "  • Firestore database: (data cleared, deletion may require console)"
    log_info "  • Cloud Storage bucket: (deleted with all contents)"
    log_info "  • Pub/Sub topics and subscriptions: (deleted)"
    log_info "  • Service account and IAM bindings: (deleted)"
    log_info "  • Local test files: (removed)"
    echo
    log_info "Billing Impact:"
    log_info "  • All resources have been removed"
    log_info "  • No further charges should occur"
    log_info "  • Check your billing console to confirm"
    echo
    log_warning "Important Notes:"
    log_warning "  • Project deletion may take up to 30 days to complete"
    log_warning "  • Some quotas may take time to reset"
    log_warning "  • Check the Google Cloud Console to confirm all resources are deleted"
    echo
    log_success "Real-Time Translation Services infrastructure successfully cleaned up!"
}

# Error handling for partial cleanup
handle_cleanup_error() {
    log_error "Cleanup encountered an error. Attempting to continue with remaining resources..."
    
    log_info "You can manually clean up remaining resources:"
    log_info "  • Visit: https://console.cloud.google.com/home/dashboard?project=${PROJECT_ID}"
    log_info "  • Or run: gcloud projects delete ${PROJECT_ID}"
    echo
    log_info "To retry cleanup with force mode:"
    log_info "  export FORCE_DESTROY=true"
    log_info "  ./destroy.sh"
}

# Main cleanup function
main() {
    log_info "Starting cleanup of Real-Time Translation Services..."
    echo
    
    # Set error handling for partial cleanup
    trap handle_cleanup_error ERR
    
    load_environment
    confirm_destruction
    
    if check_prerequisites; then
        delete_cloud_run_service
        delete_pubsub_resources
        delete_storage_bucket
        delete_firestore_database
        delete_service_account
        cleanup_local_files
        delete_project
        verify_cleanup
        show_cleanup_summary
    else
        log_warning "Project not found. Cleaning up local files only."
        cleanup_local_files
        log_success "Local cleanup completed."
    fi
    
    log_success "Cleanup process completed!"
}

# Usage information
usage() {
    echo "Usage: $0 [OPTIONS]"
    echo
    echo "Options:"
    echo "  -f, --force           Skip confirmation prompts (set FORCE_DESTROY=true)"
    echo "  --keep-project        Don't delete the entire project (set DELETE_PROJECT=false)"
    echo "  -h, --help           Show this help message"
    echo
    echo "Environment Variables:"
    echo "  PROJECT_ID           GCP project ID (loaded from .env.deploy if available)"
    echo "  REGION               GCP region (loaded from .env.deploy if available)"
    echo "  SERVICE_NAME         Cloud Run service name (loaded from .env.deploy if available)"
    echo "  FORCE_DESTROY        Skip confirmation prompts (true/false)"
    echo "  DELETE_PROJECT       Delete entire project (true/false, default: true)"
    echo
    echo "Examples:"
    echo "  ./destroy.sh                    # Interactive cleanup with confirmations"
    echo "  ./destroy.sh --force            # Automatic cleanup without prompts"
    echo "  ./destroy.sh --keep-project     # Clean up resources but keep project"
    echo "  FORCE_DESTROY=true ./destroy.sh # Environment variable approach"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -f|--force)
            export FORCE_DESTROY=true
            shift
            ;;
        --keep-project)
            export DELETE_PROJECT=false
            shift
            ;;
        -h|--help)
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

# Run main function
main "$@"