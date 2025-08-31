#!/bin/bash

# Smart Product Catalog Management with Vertex AI Search and Cloud Run - Cleanup Script
# This script removes all infrastructure created for the AI-powered product catalog solution

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
    echo -e "${GREEN}✅ $1${NC}"
}

warning() {
    echo -e "${YELLOW}⚠️ $1${NC}"
}

error() {
    echo -e "${RED}❌ $1${NC}"
}

# Configuration variables
DRY_RUN="${DRY_RUN:-false}"
FORCE_DELETE="${FORCE_DELETE:-false}"
DELETE_PROJECT="${DELETE_PROJECT:-false}"

# Variables that will be loaded from deployment info
PROJECT_ID=""
REGION=""
ZONE=""
APP_NAME=""
SEARCH_APP_ID=""
DATASTORE_ID=""
BUCKET_NAME=""
SERVICE_URL=""

# Print banner
echo -e "${RED}================================================================================================${NC}"
echo -e "${RED}   Smart Product Catalog Management - CLEANUP SCRIPT${NC}"
echo -e "${RED}   ⚠️  WARNING: This will delete cloud resources and may result in data loss!${NC}"
echo -e "${RED}================================================================================================${NC}"
echo ""

# Load deployment information
load_deployment_info() {
    log "Loading deployment information..."
    
    if [[ ! -f "deployment_info.txt" ]]; then
        error "deployment_info.txt not found. Cannot determine what resources to delete."
    fi
    
    # Source the deployment info file
    while IFS='=' read -r key value; do
        # Skip comments and empty lines
        if [[ $key =~ ^#.*$ ]] || [[ -z "$key" ]]; then
            continue
        fi
        
        case $key in
            PROJECT_ID) PROJECT_ID="$value" ;;
            REGION) REGION="$value" ;;
            ZONE) ZONE="$value" ;;
            APP_NAME) APP_NAME="$value" ;;
            SEARCH_APP_ID) SEARCH_APP_ID="$value" ;;
            DATASTORE_ID) DATASTORE_ID="$value" ;;
            BUCKET_NAME) BUCKET_NAME="$value" ;;
            SERVICE_URL) SERVICE_URL="$value" ;;
        esac
    done < deployment_info.txt
    
    # Validate required variables
    if [[ -z "$PROJECT_ID" ]]; then
        error "PROJECT_ID not found in deployment_info.txt"
    fi
    
    success "Deployment information loaded"
    echo "  Project ID: ${PROJECT_ID}"
    echo "  Region: ${REGION}"
    echo "  App Name: ${APP_NAME}"
    echo "  Search App ID: ${SEARCH_APP_ID}"
    echo "  Datastore ID: ${DATASTORE_ID}"
    echo "  Bucket Name: ${BUCKET_NAME}"
    echo ""
}

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        error "gcloud CLI is not installed. Please install it from https://cloud.google.com/sdk"
    fi
    
    # Check if user is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        error "Not authenticated with gcloud. Please run 'gcloud auth login'"
    fi
    
    # Set the project
    if ! gcloud config set project "${PROJECT_ID}"; then
        error "Failed to set project: ${PROJECT_ID}"
    fi
    
    success "Prerequisites check completed"
}

# Confirmation prompt
confirm_deletion() {
    if [[ "${FORCE_DELETE}" == "true" ]]; then
        log "Force delete enabled, skipping confirmation"
        return
    fi
    
    echo -e "${YELLOW}You are about to delete the following resources:${NC}"
    echo "  ✗ Cloud Run service: ${APP_NAME}"
    echo "  ✗ Vertex AI Search engine: ${SEARCH_APP_ID}"
    echo "  ✗ Vertex AI Search data store: ${DATASTORE_ID}"
    echo "  ✗ Cloud Storage bucket: ${BUCKET_NAME}"
    echo "  ✗ Firestore products collection"
    
    if [[ "${DELETE_PROJECT}" == "true" ]]; then
        echo "  ✗ ENTIRE PROJECT: ${PROJECT_ID}"
    fi
    
    echo ""
    echo -e "${RED}⚠️  WARNING: This action cannot be undone!${NC}"
    echo ""
    
    read -p "Are you sure you want to proceed? Type 'DELETE' to confirm: " -r
    if [[ "$REPLY" != "DELETE" ]]; then
        log "Cleanup cancelled by user"
        exit 0
    fi
    
    if [[ "${DELETE_PROJECT}" == "true" ]]; then
        echo ""
        echo -e "${RED}⚠️  FINAL WARNING: You are about to delete the ENTIRE PROJECT!${NC}"
        read -p "Type the project ID '${PROJECT_ID}' to confirm project deletion: " -r
        if [[ "$REPLY" != "$PROJECT_ID" ]]; then
            log "Project deletion cancelled"
            DELETE_PROJECT="false"
        fi
    fi
}

# Delete Cloud Run service
delete_cloud_run() {
    log "Deleting Cloud Run service..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log "[DRY RUN] Would delete Cloud Run service: ${APP_NAME}"
        return
    fi
    
    if [[ -z "$APP_NAME" ]]; then
        warning "App name not specified, skipping Cloud Run deletion"
        return
    fi
    
    # Check if service exists
    if gcloud run services describe "${APP_NAME}" --region="${REGION}" &>/dev/null; then
        if gcloud run services delete "${APP_NAME}" --region="${REGION}" --quiet; then
            success "Cloud Run service deleted: ${APP_NAME}"
        else
            warning "Failed to delete Cloud Run service: ${APP_NAME}"
        fi
    else
        warning "Cloud Run service not found: ${APP_NAME}"
    fi
}

# Delete Vertex AI Search resources
delete_vertex_ai_search() {
    log "Deleting Vertex AI Search resources..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log "[DRY RUN] Would delete search engine: ${SEARCH_APP_ID}"
        log "[DRY RUN] Would delete data store: ${DATASTORE_ID}"
        return
    fi
    
    # Delete search engine
    if [[ -n "$SEARCH_APP_ID" ]]; then
        if gcloud alpha discovery-engine engines describe "${SEARCH_APP_ID}" --location=global &>/dev/null; then
            log "Deleting search engine: ${SEARCH_APP_ID}..."
            if gcloud alpha discovery-engine engines delete "${SEARCH_APP_ID}" --location=global --quiet; then
                success "Search engine deleted: ${SEARCH_APP_ID}"
            else
                warning "Failed to delete search engine: ${SEARCH_APP_ID}"
            fi
        else
            warning "Search engine not found: ${SEARCH_APP_ID}"
        fi
    fi
    
    # Wait a moment before deleting data store
    sleep 5
    
    # Delete data store
    if [[ -n "$DATASTORE_ID" ]]; then
        if gcloud alpha discovery-engine data-stores describe "${DATASTORE_ID}" --location=global &>/dev/null; then
            log "Deleting data store: ${DATASTORE_ID}..."
            if gcloud alpha discovery-engine data-stores delete "${DATASTORE_ID}" --location=global --quiet; then
                success "Data store deleted: ${DATASTORE_ID}"
            else
                warning "Failed to delete data store: ${DATASTORE_ID}"
            fi
        else
            warning "Data store not found: ${DATASTORE_ID}"
        fi
    fi
}

# Delete Cloud Storage bucket
delete_storage() {
    log "Deleting Cloud Storage bucket..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log "[DRY RUN] Would delete bucket: ${BUCKET_NAME}"
        return
    fi
    
    if [[ -z "$BUCKET_NAME" ]]; then
        warning "Bucket name not specified, skipping storage deletion"
        return
    fi
    
    # Check if bucket exists
    if gsutil ls -b "gs://${BUCKET_NAME}" &>/dev/null; then
        log "Removing all objects from bucket..."
        if gsutil -m rm -r "gs://${BUCKET_NAME}/**" 2>/dev/null || true; then
            log "Objects removed from bucket"
        fi
        
        log "Deleting bucket..."
        if gsutil rb "gs://${BUCKET_NAME}"; then
            success "Cloud Storage bucket deleted: ${BUCKET_NAME}"
        else
            warning "Failed to delete bucket: ${BUCKET_NAME}"
        fi
    else
        warning "Bucket not found: ${BUCKET_NAME}"
    fi
}

# Delete Firestore products collection
delete_firestore_products() {
    log "Deleting Firestore products collection..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log "[DRY RUN] Would delete Firestore products collection"
        return
    fi
    
    # Create Python script to delete products collection
    cat > delete_firestore_products.py << 'EOF'
from google.cloud import firestore
import sys

def delete_collection(db, coll_ref, batch_size=100):
    """Delete a collection in batches."""
    docs = coll_ref.limit(batch_size).stream()
    deleted = 0

    for doc in docs:
        doc.reference.delete()
        deleted += 1

    if deleted >= batch_size:
        return delete_collection(db, coll_ref, batch_size)
    
    return deleted

try:
    # Initialize Firestore client
    db = firestore.Client()
    
    # Delete products collection
    products_ref = db.collection('products')
    deleted_count = delete_collection(db, products_ref)
    
    print(f"✅ Deleted {deleted_count} products from Firestore")
    
except Exception as e:
    print(f"❌ Error deleting Firestore products: {str(e)}")
    sys.exit(1)
EOF
    
    # Install required package and run script
    if python3 -m pip install google-cloud-firestore --quiet && python3 delete_firestore_products.py; then
        success "Firestore products collection deleted"
    else
        warning "Failed to delete Firestore products collection"
    fi
    
    # Clean up script
    rm -f delete_firestore_products.py
}

# Delete project (if requested)
delete_project() {
    if [[ "${DELETE_PROJECT}" != "true" ]]; then
        return
    fi
    
    log "Deleting entire project..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log "[DRY RUN] Would delete project: ${PROJECT_ID}"
        return
    fi
    
    warning "Project deletion may take several minutes..."
    
    if gcloud projects delete "${PROJECT_ID}" --quiet; then
        success "Project deleted: ${PROJECT_ID}"
        success "All resources have been removed"
    else
        error "Failed to delete project: ${PROJECT_ID}"
    fi
}

# Clean up local files
cleanup_local_files() {
    log "Cleaning up local files..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log "[DRY RUN] Would clean up local files"
        return
    fi
    
    # Remove generated files
    local files_to_remove=(
        "deployment_info.txt"
        "products.jsonl"
        "add_products.py"
        "delete_firestore_products.py"
        "app/"
    )
    
    for file in "${files_to_remove[@]}"; do
        if [[ -e "$file" ]]; then
            rm -rf "$file"
            log "Removed: $file"
        fi
    done
    
    success "Local files cleaned up"
}

# Display final status
display_final_status() {
    echo ""
    echo -e "${GREEN}================================================================================================${NC}"
    echo -e "${GREEN}   🧹 Cleanup completed!${NC}"
    echo -e "${GREEN}================================================================================================${NC}"
    echo ""
    
    if [[ "${DELETE_PROJECT}" == "true" ]]; then
        echo "✅ Project and all resources have been deleted"
        echo "✅ No further action required"
    else
        echo "✅ Individual resources have been deleted"
        echo "✅ Project ${PROJECT_ID} remains (you may delete it manually if needed)"
        echo ""
        echo "To delete the project entirely:"
        echo "  gcloud projects delete ${PROJECT_ID}"
    fi
    
    echo ""
    echo "Cost Impact: Resource deletion stops all billing for these services"
    echo ""
}

# Check for any remaining resources
check_remaining_resources() {
    if [[ "${DELETE_PROJECT}" == "true" ]] || [[ "${DRY_RUN}" == "true" ]]; then
        return
    fi
    
    log "Checking for any remaining resources..."
    
    echo ""
    echo "Remaining resources check:"
    
    # Check Cloud Run
    if gcloud run services list --region="${REGION}" --format="value(metadata.name)" | grep -q .; then
        warning "Some Cloud Run services still exist"
        gcloud run services list --region="${REGION}" --format="table(metadata.name,status.url)"
    else
        success "No Cloud Run services found"
    fi
    
    # Check Cloud Storage
    if gsutil ls -p "${PROJECT_ID}" 2>/dev/null | grep -q .; then
        warning "Some Cloud Storage buckets still exist"
        gsutil ls -p "${PROJECT_ID}"
    else
        success "No Cloud Storage buckets found"
    fi
    
    echo ""
}

# Handle script interruption
handle_interrupt() {
    echo ""
    error "Cleanup interrupted by user"
    warning "Some resources may still exist. Re-run this script to complete cleanup."
    exit 1
}

# Usage information
usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --dry-run          Show what would be deleted without actually deleting"
    echo "  --force            Skip confirmation prompts"
    echo "  --delete-project   Delete the entire project (DESTRUCTIVE)"
    echo "  --help            Show this help message"
    echo ""
    echo "Environment Variables:"
    echo "  DRY_RUN=true          Same as --dry-run"
    echo "  FORCE_DELETE=true     Same as --force"
    echo "  DELETE_PROJECT=true   Same as --delete-project"
    echo ""
    echo "Examples:"
    echo "  $0                    # Interactive cleanup"
    echo "  $0 --dry-run         # Show what would be deleted"
    echo "  $0 --force           # Skip confirmations"
    echo "  $0 --delete-project  # Delete entire project"
}

# Parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --dry-run)
                DRY_RUN="true"
                shift
                ;;
            --force)
                FORCE_DELETE="true"
                shift
                ;;
            --delete-project)
                DELETE_PROJECT="true"
                shift
                ;;
            --help)
                usage
                exit 0
                ;;
            *)
                error "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done
}

# Main cleanup function
main() {
    parse_arguments "$@"
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log "DRY RUN MODE - No resources will be deleted"
        echo ""
    fi
    
    load_deployment_info
    check_prerequisites
    confirm_deletion
    
    # Perform cleanup in reverse order of creation
    delete_cloud_run
    delete_vertex_ai_search
    delete_storage
    delete_firestore_products
    delete_project
    
    if [[ "${DELETE_PROJECT}" != "true" ]]; then
        cleanup_local_files
        check_remaining_resources
    fi
    
    display_final_status
}

# Set up interrupt handler
trap handle_interrupt INT

# Run main function
main "$@"