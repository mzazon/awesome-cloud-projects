#!/bin/bash

# API Rate Limiting and Analytics with Cloud Run and Firestore - Cleanup Script
# This script safely removes all resources created by the deployment script

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✅ $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️  $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ❌ $1${NC}"
}

# Configuration flags
DRY_RUN=false
FORCE_DELETE=false
SKIP_CONFIRMATION=false
KEEP_PROJECT=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --force)
            FORCE_DELETE=true
            shift
            ;;
        --yes)
            SKIP_CONFIRMATION=true
            shift
            ;;
        --keep-project)
            KEEP_PROJECT=true
            shift
            ;;
        --project-id)
            PROJECT_ID_OVERRIDE="$2"
            shift 2
            ;;
        --help)
            echo "Usage: $0 [--dry-run] [--force] [--yes] [--keep-project] [--project-id PROJECT_ID]"
            echo "  --dry-run: Show what would be deleted without making changes"
            echo "  --force: Force deletion without additional safety checks"
            echo "  --yes: Skip confirmation prompts"
            echo "  --keep-project: Keep the GCP project (only delete resources within it)"
            echo "  --project-id: Override project ID (instead of reading from .env.deploy)"
            exit 0
            ;;
        *)
            error "Unknown option $1"
            exit 1
            ;;
    esac
done

log "Starting cleanup of API Rate Limiting and Analytics solution..."

# Load environment variables from deployment
load_environment() {
    log "Loading deployment environment..."
    
    if [[ -n "${PROJECT_ID_OVERRIDE:-}" ]]; then
        export PROJECT_ID="${PROJECT_ID_OVERRIDE}"
        log "Using override project ID: ${PROJECT_ID}"
    elif [[ -f ".env.deploy" ]]; then
        log "Loading environment from .env.deploy file..."
        # Source the environment file safely
        while IFS='=' read -r key value; do
            # Skip empty lines and comments
            [[ -z "$key" || "$key" =~ ^#.*$ ]] && continue
            # Export the variable
            export "$key=$value"
            log "  $key=$value"
        done < .env.deploy
    else
        error "No .env.deploy file found and no project ID override provided."
        error "Please run from the same directory as the deploy script or use --project-id."
        exit 1
    fi
    
    # Set defaults for missing variables
    export REGION="${REGION:-us-central1}"
    export SERVICE_NAME="${SERVICE_NAME:-api-rate-limiter}"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        warn "DRY RUN MODE - No actual resources will be deleted"
    fi
    
    success "Environment loaded successfully"
}

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        error "gcloud CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if user is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 > /dev/null; then
        error "Not authenticated with gcloud. Run 'gcloud auth login' first."
        exit 1
    fi
    
    # Verify project exists
    if ! gcloud projects describe "${PROJECT_ID}" &>/dev/null; then
        error "Project ${PROJECT_ID} does not exist or is not accessible."
        exit 1
    fi
    
    success "Prerequisites check completed"
}

# Display resources to be deleted
show_resources() {
    log "Scanning for resources to be deleted..."
    
    # Set project context
    gcloud config set project "${PROJECT_ID}" 2>/dev/null
    
    log "=== RESOURCES TO BE DELETED ==="
    
    # Check Cloud Run services
    log "Cloud Run Services:"
    if gcloud run services list --region="${REGION}" --format="value(metadata.name)" 2>/dev/null | grep -q "${SERVICE_NAME}"; then
        log "  ✓ Cloud Run service: ${SERVICE_NAME} (region: ${REGION})"
    else
        log "  - No Cloud Run service found"
    fi
    
    # Check Container Registry images
    log "Container Registry Images:"
    if gcloud container images list --repository="gcr.io/${PROJECT_ID}" --format="value(name)" 2>/dev/null | grep -q "${SERVICE_NAME}"; then
        log "  ✓ Container image: gcr.io/${PROJECT_ID}/${SERVICE_NAME}"
    else
        log "  - No container images found"
    fi
    
    # Check Firestore database
    log "Firestore Database:"
    if gcloud firestore databases describe --region="${REGION}" --format="value(name)" &>/dev/null; then
        log "  ✓ Firestore database (region: ${REGION})"
        log "    - Collections: rate_limits, api_analytics"
    else
        log "  - No Firestore database found"
    fi
    
    # Check Cloud Build history
    log "Cloud Build History:"
    local build_count=$(gcloud builds list --filter="substitutions.REPO_NAME~${SERVICE_NAME}" --limit=5 --format="value(id)" 2>/dev/null | wc -l)
    if [[ $build_count -gt 0 ]]; then
        log "  ✓ ${build_count} Cloud Build entries"
    else
        log "  - No Cloud Build history found"
    fi
    
    # Local files
    log "Local Files:"
    local files_to_delete=()
    [[ -d "api-gateway" ]] && files_to_delete+=("api-gateway/")
    [[ -f ".env.deploy" ]] && files_to_delete+=(".env.deploy")
    [[ -f "firestore.rules" ]] && files_to_delete+=("firestore.rules")
    [[ -f "monitoring-dashboard.json" ]] && files_to_delete+=("monitoring-dashboard.json")
    
    if [[ ${#files_to_delete[@]} -gt 0 ]]; then
        for file in "${files_to_delete[@]}"; do
            log "  ✓ ${file}"
        done
    else
        log "  - No local files found"
    fi
    
    if [[ "$KEEP_PROJECT" != "true" ]]; then
        log "GCP Project:"
        log "  ✓ Project: ${PROJECT_ID} (COMPLETE DELETION)"
    fi
    
    log "========================="
}

# Confirmation prompt
confirm_deletion() {
    if [[ "$SKIP_CONFIRMATION" == "true" ]]; then
        log "Skipping confirmation prompt (--yes flag provided)"
        return 0
    fi
    
    log ""
    warn "This will permanently delete the resources listed above."
    
    if [[ "$KEEP_PROJECT" != "true" ]]; then
        warn "This includes COMPLETE PROJECT DELETION which cannot be undone!"
    fi
    
    echo -n "Are you sure you want to continue? [y/N]: "
    read -r response
    
    case "$response" in
        [yY][eE][sS]|[yY])
            log "Proceeding with deletion..."
            return 0
            ;;
        *)
            log "Deletion cancelled by user."
            exit 0
            ;;
    esac
}

# Delete Cloud Run service
delete_cloud_run() {
    log "Deleting Cloud Run service..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "Would delete Cloud Run service: ${SERVICE_NAME}"
        return 0
    fi
    
    # Check if service exists
    if gcloud run services describe "${SERVICE_NAME}" --region="${REGION}" &>/dev/null; then
        log "Deleting Cloud Run service: ${SERVICE_NAME}..."
        gcloud run services delete "${SERVICE_NAME}" \
            --region="${REGION}" \
            --quiet || {
            if [[ "$FORCE_DELETE" == "true" ]]; then
                warn "Failed to delete Cloud Run service, continuing with force flag"
            else
                error "Failed to delete Cloud Run service"
                exit 1
            fi
        }
        success "Cloud Run service deleted"
    else
        log "Cloud Run service not found, skipping"
    fi
}

# Delete Container Registry images
delete_container_images() {
    log "Deleting container images..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "Would delete container images for: gcr.io/${PROJECT_ID}/${SERVICE_NAME}"
        return 0
    fi
    
    # List and delete all tags for the service
    local image_name="gcr.io/${PROJECT_ID}/${SERVICE_NAME}"
    
    if gcloud container images list --repository="gcr.io/${PROJECT_ID}" --format="value(name)" 2>/dev/null | grep -q "${SERVICE_NAME}"; then
        log "Deleting container images for ${image_name}..."
        gcloud container images delete "${image_name}" \
            --force-delete-tags \
            --quiet || {
            if [[ "$FORCE_DELETE" == "true" ]]; then
                warn "Failed to delete container images, continuing with force flag"
            else
                warn "Failed to delete container images, but continuing cleanup"
            fi
        }
        success "Container images deleted"
    else
        log "No container images found, skipping"
    fi
}

# Clean up Firestore data
cleanup_firestore() {
    log "Cleaning up Firestore data..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "Would clean up Firestore collections: rate_limits, api_analytics"
        return 0
    fi
    
    # Note: Firestore data deletion is manual in this script
    # For production, you might want to implement programmatic deletion
    warn "Firestore data cleanup requires manual action:"
    log "1. Go to https://console.cloud.google.com/firestore/data?project=${PROJECT_ID}"
    log "2. Delete collections: rate_limits, api_analytics"
    log "3. Optionally delete the entire Firestore database"
    
    # If keeping project, provide more specific guidance
    if [[ "$KEEP_PROJECT" == "true" ]]; then
        log ""
        log "To programmatically delete Firestore collections, run:"
        log "gcloud firestore databases delete --region=${REGION} --quiet"
        log "(This will delete the entire Firestore database)"
    fi
}

# Delete local files
delete_local_files() {
    log "Deleting local files..."
    
    local files_to_delete=(
        "api-gateway"
        ".env.deploy"
        "firestore.rules"
        "monitoring-dashboard.json"
    )
    
    for file in "${files_to_delete[@]}"; do
        if [[ -e "$file" ]]; then
            if [[ "$DRY_RUN" == "true" ]]; then
                log "Would delete: $file"
            else
                log "Deleting: $file"
                rm -rf "$file"
            fi
        fi
    done
    
    # Clean up environment variables
    if [[ "$DRY_RUN" != "true" ]]; then
        unset PROJECT_ID REGION SERVICE_NAME RANDOM_SUFFIX
        unset SERVICE_URL TEST_API_KEY_1 TEST_API_KEY_2 DEPLOY_TIMESTAMP
    fi
    
    success "Local files cleaned up"
}

# Delete the entire project (if not keeping it)
delete_project() {
    if [[ "$KEEP_PROJECT" == "true" ]]; then
        log "Keeping project ${PROJECT_ID} as requested"
        return 0
    fi
    
    log "Deleting GCP project..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "Would delete project: ${PROJECT_ID}"
        return 0
    fi
    
    log "Deleting project: ${PROJECT_ID}..."
    warn "This operation cannot be undone!"
    
    gcloud projects delete "${PROJECT_ID}" --quiet || {
        if [[ "$FORCE_DELETE" == "true" ]]; then
            warn "Failed to delete project, continuing with force flag"
        else
            error "Failed to delete project ${PROJECT_ID}"
            exit 1
        fi
    }
    
    success "Project ${PROJECT_ID} scheduled for deletion"
    log "Note: Project deletion may take several minutes to complete"
}

# Verify cleanup completion
verify_cleanup() {
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY RUN completed - no actual resources were deleted"
        return 0
    fi
    
    log "Verifying cleanup completion..."
    
    if [[ "$KEEP_PROJECT" == "true" ]]; then
        # Check if Cloud Run service is gone
        if gcloud run services describe "${SERVICE_NAME}" --region="${REGION}" &>/dev/null; then
            warn "Cloud Run service still exists"
        else
            success "Cloud Run service successfully deleted"
        fi
        
        # Note about other resources
        log "Manual verification recommended for:"
        log "  - Firestore collections"
        log "  - Container Registry images"
        log "  - Cloud Build history"
    else
        # Project deletion - check if project still exists
        if gcloud projects describe "${PROJECT_ID}" &>/dev/null; then
            log "Project deletion initiated - may take several minutes"
        else
            success "Project successfully deleted"
        fi
    fi
    
    # Check local files
    local remaining_files=()
    [[ -d "api-gateway" ]] && remaining_files+=("api-gateway/")
    [[ -f ".env.deploy" ]] && remaining_files+=(".env.deploy")
    [[ -f "firestore.rules" ]] && remaining_files+=("firestore.rules")
    [[ -f "monitoring-dashboard.json" ]] && remaining_files+=("monitoring-dashboard.json")
    
    if [[ ${#remaining_files[@]} -eq 0 ]]; then
        success "All local files cleaned up"
    else
        warn "Some local files remain: ${remaining_files[*]}"
    fi
}

# Main cleanup function
main() {
    log "Starting cleanup of API Rate Limiting and Analytics solution"
    
    load_environment
    check_prerequisites
    show_resources
    
    if [[ "$DRY_RUN" != "true" ]]; then
        confirm_deletion
    fi
    
    # Perform cleanup in reverse order of creation
    delete_cloud_run
    delete_container_images
    cleanup_firestore
    delete_local_files
    delete_project
    verify_cleanup
    
    if [[ "$DRY_RUN" == "true" ]]; then
        success "DRY RUN completed - no resources were actually deleted"
        log "To perform actual cleanup, run: $0 without --dry-run flag"
    else
        success "🧹 Cleanup completed successfully!"
        log ""
        if [[ "$KEEP_PROJECT" == "true" ]]; then
            log "Project ${PROJECT_ID} has been preserved"
            log "Manual cleanup may be required for Firestore data"
        else
            log "Project ${PROJECT_ID} has been scheduled for deletion"
            log "All resources and data will be permanently removed"
        fi
        log ""
        log "Thank you for using the API Rate Limiting and Analytics recipe!"
    fi
}

# Run main function
main "$@"