#!/bin/bash

# Customer Service Automation with Contact Center AI and Vertex AI Search
# Cleanup/Destroy Script for GCP Recipe
#
# This script safely removes all resources created by the deployment script:
# - Cloud Run services
# - Vertex AI Search engines and data stores
# - Cloud Storage buckets and contents
# - IAM permissions (optional)

set -euo pipefail

# Configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_FILE="${SCRIPT_DIR}/destroy.log"
readonly DEPLOYMENT_INFO_FILE="${SCRIPT_DIR}/deployment-info.txt"

# Logging functions
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" | tee -a "${LOG_FILE}"
}

log_info() {
    log "INFO: $*"
}

log_warn() {
    log "WARN: $*"
}

log_error() {
    log "ERROR: $*"
}

log_success() {
    log "SUCCESS: $*"
}

# Error handling
cleanup_on_error() {
    local exit_code=$?
    log_error "Cleanup failed with exit code ${exit_code}"
    log_error "Some resources may still exist. Please check manually in the Google Cloud Console."
    exit $exit_code
}

trap cleanup_on_error ERR

# Helper functions
check_prerequisites() {
    log_info "Checking prerequisites for cleanup..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "gcloud CLI is not installed"
        exit 1
    fi
    
    # Check if user is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 > /dev/null; then
        log_error "No active gcloud authentication found. Please run: gcloud auth login"
        exit 1
    fi
    
    # Check if project is set
    if ! gcloud config get-value project > /dev/null 2>&1; then
        log_error "No default project set. Please run: gcloud config set project YOUR_PROJECT_ID"
        exit 1
    fi
    
    log_success "Prerequisites check completed"
}

load_deployment_info() {
    log_info "Loading deployment information..."
    
    # Try to load from deployment info file
    if [[ -f "$DEPLOYMENT_INFO_FILE" ]]; then
        log_info "Found deployment info file: $DEPLOYMENT_INFO_FILE"
        
        # Source the environment variables from the file
        while IFS= read -r line; do
            if [[ "$line" =~ ^[A-Z_]+=.* ]]; then
                export "$line"
                log_info "Loaded: $line"
            fi
        done < "$DEPLOYMENT_INFO_FILE"
    else
        log_warn "Deployment info file not found. Using environment variables or prompting for input."
    fi
    
    # Get project ID
    export PROJECT_ID
    PROJECT_ID=$(gcloud config get-value project)
    
    # Prompt for missing variables if not found
    if [[ -z "${BUCKET_NAME:-}" ]]; then
        read -p "Enter Storage Bucket Name (e.g., customer-service-kb-abc123): " BUCKET_NAME
        export BUCKET_NAME
    fi
    
    if [[ -z "${SEARCH_ENGINE_ID:-}" ]]; then
        read -p "Enter Search Engine ID (e.g., customer-service-search-abc123): " SEARCH_ENGINE_ID
        export SEARCH_ENGINE_ID
    fi
    
    if [[ -z "${CLOUD_RUN_SERVICE:-}" ]]; then
        read -p "Enter Cloud Run Service Name (e.g., customer-service-api-abc123): " CLOUD_RUN_SERVICE
        export CLOUD_RUN_SERVICE
    fi
    
    if [[ -z "${REGION:-}" ]]; then
        export REGION="${REGION:-us-central1}"
    fi
    
    log_success "Deployment information loaded:"
    log_info "  PROJECT_ID: ${PROJECT_ID}"
    log_info "  REGION: ${REGION}"
    log_info "  BUCKET_NAME: ${BUCKET_NAME}"
    log_info "  SEARCH_ENGINE_ID: ${SEARCH_ENGINE_ID}"
    log_info "  CLOUD_RUN_SERVICE: ${CLOUD_RUN_SERVICE}"
}

confirm_destruction() {
    local force_mode="${1:-false}"
    
    if [[ "$force_mode" != "true" ]]; then
        echo ""
        echo "⚠️  WARNING: This will permanently delete the following resources:"
        echo "  📦 Storage Bucket: gs://${BUCKET_NAME} (and all contents)"
        echo "  🔍 Vertex AI Search Engine: ${SEARCH_ENGINE_ID}"
        echo "  🚀 Cloud Run Service: ${CLOUD_RUN_SERVICE}"
        echo ""
        echo "This action cannot be undone!"
        echo ""
        
        read -p "Are you sure you want to continue? (type 'yes' to confirm): " confirmation
        
        if [[ "$confirmation" != "yes" ]]; then
            log_info "Cleanup cancelled by user"
            exit 0
        fi
    fi
    
    log_info "Proceeding with resource cleanup..."
}

list_resources() {
    log_info "Scanning for resources to cleanup..."
    
    # Check Cloud Run service
    if gcloud run services describe "${CLOUD_RUN_SERVICE}" --region="${REGION}" --quiet &>/dev/null; then
        log_info "✓ Found Cloud Run service: ${CLOUD_RUN_SERVICE}"
    else
        log_warn "✗ Cloud Run service not found: ${CLOUD_RUN_SERVICE}"
    fi
    
    # Check Storage bucket
    if gsutil ls "gs://${BUCKET_NAME}" &>/dev/null; then
        log_info "✓ Found Storage bucket: gs://${BUCKET_NAME}"
        local object_count
        object_count=$(gsutil ls -l "gs://${BUCKET_NAME}/**" 2>/dev/null | grep -c "^[0-9]" || echo "0")
        log_info "  Contains $object_count objects"
    else
        log_warn "✗ Storage bucket not found: gs://${BUCKET_NAME}"
    fi
    
    # Check Vertex AI Search resources
    local search_engines
    search_engines=$(curl -s -H "Authorization: Bearer $(gcloud auth print-access-token)" \
        "https://discoveryengine.googleapis.com/v1/projects/${PROJECT_ID}/locations/global/collections/default_collection/engines" \
        | grep -o "\"name\":\"[^\"]*${SEARCH_ENGINE_ID}[^\"]*\"" || echo "")
    
    if [[ -n "$search_engines" ]]; then
        log_info "✓ Found Vertex AI Search resources related to: ${SEARCH_ENGINE_ID}"
    else
        log_warn "✗ No Vertex AI Search resources found for: ${SEARCH_ENGINE_ID}"
    fi
}

remove_cloud_run_service() {
    log_info "Removing Cloud Run service..."
    
    if gcloud run services describe "${CLOUD_RUN_SERVICE}" --region="${REGION}" --quiet &>/dev/null; then
        if gcloud run services delete "${CLOUD_RUN_SERVICE}" \
            --region="${REGION}" \
            --quiet; then
            log_success "Cloud Run service deleted: ${CLOUD_RUN_SERVICE}"
        else
            log_error "Failed to delete Cloud Run service: ${CLOUD_RUN_SERVICE}"
            return 1
        fi
    else
        log_warn "Cloud Run service not found: ${CLOUD_RUN_SERVICE}"
    fi
}

remove_vertex_ai_search_resources() {
    log_info "Removing Vertex AI Search resources..."
    
    # Delete search application (engine) first
    log_info "Deleting search application..."
    local app_delete_response
    app_delete_response=$(curl -s -X DELETE \
        -H "Authorization: Bearer $(gcloud auth print-access-token)" \
        "https://discoveryengine.googleapis.com/v1/projects/${PROJECT_ID}/locations/global/collections/default_collection/engines/${SEARCH_ENGINE_ID}-app" 2>&1)
    
    if echo "$app_delete_response" | grep -q "error"; then
        if echo "$app_delete_response" | grep -q "404"; then
            log_warn "Search application not found (may have been already deleted)"
        else
            log_error "Failed to delete search application"
            log_error "Response: $app_delete_response"
        fi
    else
        log_success "Search application deletion initiated"
    fi
    
    # Wait a bit for the application to be deleted
    sleep 15
    
    # Delete data store
    log_info "Deleting data store..."
    local datastore_delete_response
    datastore_delete_response=$(curl -s -X DELETE \
        -H "Authorization: Bearer $(gcloud auth print-access-token)" \
        "https://discoveryengine.googleapis.com/v1/projects/${PROJECT_ID}/locations/global/collections/default_collection/dataStores/${SEARCH_ENGINE_ID}" 2>&1)
    
    if echo "$datastore_delete_response" | grep -q "error"; then
        if echo "$datastore_delete_response" | grep -q "404"; then
            log_warn "Data store not found (may have been already deleted)"
        else
            log_error "Failed to delete data store"
            log_error "Response: $datastore_delete_response"
        fi
    else
        log_success "Data store deletion initiated"
    fi
    
    # Wait for deletion to complete
    log_info "Waiting for Vertex AI Search resources to be fully deleted..."
    sleep 30
}

remove_storage_bucket() {
    log_info "Removing Cloud Storage bucket and contents..."
    
    if gsutil ls "gs://${BUCKET_NAME}" &>/dev/null; then
        # First, list what's being deleted for transparency
        log_info "Bucket contents to be deleted:"
        gsutil ls -l "gs://${BUCKET_NAME}/**" 2>/dev/null | head -20 || true
        
        # Remove all objects and bucket
        if gsutil -m rm -r "gs://${BUCKET_NAME}"; then
            log_success "Storage bucket and all contents deleted: gs://${BUCKET_NAME}"
        else
            log_error "Failed to delete storage bucket: gs://${BUCKET_NAME}"
            
            # Try to remove objects first, then bucket
            log_info "Attempting to remove objects first..."
            if gsutil -m rm "gs://${BUCKET_NAME}/**" 2>/dev/null; then
                log_info "Objects removed, now removing bucket..."
                if gsutil rb "gs://${BUCKET_NAME}"; then
                    log_success "Storage bucket deleted after removing objects"
                else
                    log_error "Failed to delete empty bucket"
                fi
            else
                log_error "Failed to remove bucket objects"
            fi
        fi
    else
        log_warn "Storage bucket not found: gs://${BUCKET_NAME}"
    fi
}

remove_iam_permissions() {
    local remove_iam="${1:-false}"
    
    if [[ "$remove_iam" == "true" ]]; then
        log_info "Removing IAM permissions..."
        
        # Get the default compute service account
        local service_account
        service_account="${PROJECT_ID}-compute@developer.gserviceaccount.com"
        
        # Remove granted permissions
        local roles=(
            "roles/contactcenteraiplatform.admin"
            "roles/discoveryengine.admin"
            "roles/storage.objectViewer"
        )
        
        for role in "${roles[@]}"; do
            if gcloud projects remove-iam-policy-binding "${PROJECT_ID}" \
                --member="serviceAccount:${service_account}" \
                --role="$role" \
                --quiet; then
                log_success "IAM role removed: $role"
            else
                log_warn "Failed to remove IAM role (may not exist): $role"
            fi
        done
    else
        log_info "Skipping IAM permission removal (use --remove-iam to include)"
    fi
}

cleanup_temporary_files() {
    log_info "Cleaning up temporary files..."
    
    # Remove deployment info file
    if [[ -f "$DEPLOYMENT_INFO_FILE" ]]; then
        rm -f "$DEPLOYMENT_INFO_FILE"
        log_success "Deployment info file removed"
    fi
    
    # Clean up any temporary directories that might still exist
    rm -rf /tmp/customer-service-api-* 2>/dev/null || true
    rm -rf /tmp/agent-dashboard-* 2>/dev/null || true
    rm -rf /tmp/knowledge-base-* 2>/dev/null || true
    
    log_success "Temporary files cleaned up"
}

verify_cleanup() {
    log_info "Verifying cleanup completion..."
    
    local issues_found=false
    
    # Verify Cloud Run service is gone
    if gcloud run services describe "${CLOUD_RUN_SERVICE}" --region="${REGION}" --quiet &>/dev/null; then
        log_warn "Cloud Run service still exists: ${CLOUD_RUN_SERVICE}"
        issues_found=true
    else
        log_success "✓ Cloud Run service removed"
    fi
    
    # Verify Storage bucket is gone
    if gsutil ls "gs://${BUCKET_NAME}" &>/dev/null; then
        log_warn "Storage bucket still exists: gs://${BUCKET_NAME}"
        issues_found=true
    else
        log_success "✓ Storage bucket removed"
    fi
    
    # Check for any remaining Vertex AI Search resources
    local remaining_engines
    remaining_engines=$(curl -s -H "Authorization: Bearer $(gcloud auth print-access-token)" \
        "https://discoveryengine.googleapis.com/v1/projects/${PROJECT_ID}/locations/global/collections/default_collection/engines" \
        | grep -c "${SEARCH_ENGINE_ID}" || echo "0")
    
    if [[ "$remaining_engines" -gt 0 ]]; then
        log_warn "Some Vertex AI Search resources may still exist"
        issues_found=true
    else
        log_success "✓ Vertex AI Search resources removed"
    fi
    
    if [[ "$issues_found" == "true" ]]; then
        log_warn "Some resources may still exist. Please check the Google Cloud Console."
        return 1
    else
        log_success "All resources successfully removed"
        return 0
    fi
}

print_cleanup_summary() {
    echo ""
    echo "🧹 Customer Service Automation Cleanup Completed"
    echo ""
    echo "Resources Removed:"
    echo "  🚀 Cloud Run Service: ${CLOUD_RUN_SERVICE}"
    echo "  🔍 Vertex AI Search Engine: ${SEARCH_ENGINE_ID}"
    echo "  📦 Storage Bucket: gs://${BUCKET_NAME}"
    echo ""
    echo "Notes:"
    echo "  - All knowledge base documents have been deleted"
    echo "  - Agent dashboard has been removed"
    echo "  - API endpoints are no longer accessible"
    echo ""
    echo "If you need to redeploy, run: ${SCRIPT_DIR}/deploy.sh"
    echo ""
}

print_help() {
    cat << EOF
Customer Service Automation Cleanup Script

Usage: $0 [OPTIONS]

Options:
  --help          Show this help message
  --force         Skip confirmation prompt
  --dry-run       Show what would be deleted without actually deleting
  --remove-iam    Also remove IAM permissions (default: skip)
  --list-only     Only list resources, don't delete anything

Examples:
  $0                    # Interactive cleanup with confirmation
  $0 --force            # Skip confirmation prompt
  $0 --dry-run          # Preview what would be deleted
  $0 --force --remove-iam  # Force cleanup including IAM permissions

EOF
}

# Main cleanup function
main() {
    local force_mode=false
    local dry_run_mode=false
    local list_only=false
    local remove_iam=false
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --help)
                print_help
                exit 0
                ;;
            --force)
                force_mode=true
                shift
                ;;
            --dry-run)
                dry_run_mode=true
                shift
                ;;
            --list-only)
                list_only=true
                shift
                ;;
            --remove-iam)
                remove_iam=true
                shift
                ;;
            *)
                log_error "Unknown option: $1"
                print_help
                exit 1
                ;;
        esac
    done
    
    log_info "Starting Customer Service Automation cleanup..."
    log_info "Script: $0"
    log_info "Working directory: $(pwd)"
    log_info "Log file: ${LOG_FILE}"
    
    # Initialize log file
    echo "Customer Service Automation Cleanup Log" > "${LOG_FILE}"
    echo "Started: $(date)" >> "${LOG_FILE}"
    echo "=======================================" >> "${LOG_FILE}"
    
    # Execute cleanup steps
    check_prerequisites
    load_deployment_info
    list_resources
    
    if [[ "$list_only" == "true" ]]; then
        log_info "List-only mode - no resources will be deleted"
        exit 0
    fi
    
    if [[ "$dry_run_mode" == "true" ]]; then
        log_info "DRY RUN MODE - No resources will be deleted"
        log_info "Would delete: Cloud Run service, Vertex AI Search resources, Storage bucket"
        exit 0
    fi
    
    confirm_destruction "$force_mode"
    
    # Remove resources in reverse order of creation
    remove_cloud_run_service
    remove_vertex_ai_search_resources
    remove_storage_bucket
    remove_iam_permissions "$remove_iam"
    cleanup_temporary_files
    
    if verify_cleanup; then
        print_cleanup_summary
        log_success "Cleanup completed successfully!"
    else
        log_warn "Cleanup completed with some issues. Please check manually."
        exit 1
    fi
}

# Execute main function with all arguments
main "$@"