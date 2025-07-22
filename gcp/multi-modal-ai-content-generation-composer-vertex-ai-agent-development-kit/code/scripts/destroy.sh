#!/bin/bash

# Multi-Modal AI Content Generation Pipeline Cleanup Script
# This script safely removes all resources created by the deployment script
# to prevent ongoing charges and clean up the Google Cloud project.

set -euo pipefail

# Color codes for output formatting
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Configuration variables
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_FILE="${SCRIPT_DIR}/cleanup.log"
readonly CONFIG_FILE="${SCRIPT_DIR}/.env"

# Global variables for cleanup tracking
RESOURCES_TO_DELETE=()
FAILED_DELETIONS=()

# Functions for logging and output
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $*${NC}" | tee -a "${LOG_FILE}"
}

log_info() {
    echo -e "${BLUE}[INFO] $*${NC}" | tee -a "${LOG_FILE}"
}

log_warn() {
    echo -e "${YELLOW}[WARN] $*${NC}" | tee -a "${LOG_FILE}"
}

log_error() {
    echo -e "${RED}[ERROR] $*${NC}" | tee -a "${LOG_FILE}"
}

# Error handling function
handle_error() {
    local line_no=$1
    local error_code=$2
    log_error "An error occurred on line ${line_no}: exit code ${error_code}"
    log_warn "Continuing with cleanup of remaining resources..."
}

trap 'handle_error ${LINENO} $?' ERR

# Display banner
show_banner() {
    echo -e "${BLUE}"
    echo "=================================================================="
    echo "  Multi-Modal AI Content Generation Pipeline Cleanup"
    echo "  Google Cloud Platform - Resource Deletion"
    echo "=================================================================="
    echo -e "${NC}"
}

# Load configuration
load_configuration() {
    log_info "Loading configuration..."
    
    if [[ ! -f "${CONFIG_FILE}" ]]; then
        log_error "Configuration file not found: ${CONFIG_FILE}"
        log_error "Unable to proceed with cleanup without configuration."
        exit 1
    fi
    
    # shellcheck source=/dev/null
    source "${CONFIG_FILE}"
    
    # Validate required variables
    local required_vars=(
        "PROJECT_ID"
        "REGION"
        "COMPOSER_ENV_NAME"
        "STORAGE_BUCKET"
        "CLOUD_RUN_SERVICE"
    )
    
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            log_error "Required variable ${var} not found in configuration"
            exit 1
        fi
    done
    
    log_info "Configuration loaded successfully"
    log_info "  Project ID: ${PROJECT_ID}"
    log_info "  Region: ${REGION}"
    log_info "  Composer Environment: ${COMPOSER_ENV_NAME}"
    log_info "  Storage Bucket: ${STORAGE_BUCKET}"
    log_info "  Cloud Run Service: ${CLOUD_RUN_SERVICE}"
}

# Confirm cleanup operation
confirm_cleanup() {
    echo -e "${YELLOW}"
    echo "⚠️  WARNING: This will permanently delete the following resources:"
    echo "   - Cloud Composer environment: ${COMPOSER_ENV_NAME}"
    echo "   - Cloud Storage bucket: ${STORAGE_BUCKET} (and all contents)"
    echo "   - Cloud Run service: ${CLOUD_RUN_SERVICE}"
    echo "   - Container images in Container Registry"
    echo "   - All generated content and DAG files"
    echo ""
    echo "This action cannot be undone!"
    echo -e "${NC}"
    
    if [[ "${FORCE_DELETE:-false}" == "true" ]]; then
        log_warn "Force delete enabled, skipping confirmation"
        return 0
    fi
    
    read -p "Are you sure you want to proceed? Type 'DELETE' to confirm: " confirmation
    
    if [[ "${confirmation}" != "DELETE" ]]; then
        log_info "Cleanup cancelled by user"
        exit 0
    fi
    
    log "User confirmed cleanup operation"
}

# Set gcloud project context
configure_gcloud() {
    log_info "Configuring gcloud for cleanup..."
    
    # Set project context
    if gcloud config set project "${PROJECT_ID}" --quiet; then
        log "gcloud project set to ${PROJECT_ID}"
    else
        log_error "Failed to set gcloud project"
        exit 1
    fi
    
    # Set default region
    gcloud config set compute/region "${REGION}" --quiet
}

# Delete Cloud Run service and container images
cleanup_cloud_run() {
    log_info "Cleaning up Cloud Run service and container images..."
    
    # Delete Cloud Run service
    if gcloud run services describe "${CLOUD_RUN_SERVICE}" \
        --region "${REGION}" &> /dev/null; then
        
        log_info "Deleting Cloud Run service: ${CLOUD_RUN_SERVICE}"
        if gcloud run services delete "${CLOUD_RUN_SERVICE}" \
            --region "${REGION}" \
            --quiet; then
            log "✅ Cloud Run service deleted successfully"
        else
            log_error "❌ Failed to delete Cloud Run service"
            FAILED_DELETIONS+=("Cloud Run service: ${CLOUD_RUN_SERVICE}")
        fi
    else
        log_warn "Cloud Run service ${CLOUD_RUN_SERVICE} not found"
    fi
    
    # Delete container images
    local image_name="gcr.io/${PROJECT_ID}/${CLOUD_RUN_SERVICE}"
    log_info "Checking for container images: ${image_name}"
    
    if gcloud container images list --repository="gcr.io/${PROJECT_ID}" \
        --filter="name:${CLOUD_RUN_SERVICE}" --format="value(name)" | grep -q "${CLOUD_RUN_SERVICE}"; then
        
        log_info "Deleting container images..."
        if gcloud container images delete "${image_name}" \
            --force-delete-tags \
            --quiet; then
            log "✅ Container images deleted successfully"
        else
            log_error "❌ Failed to delete container images"
            FAILED_DELETIONS+=("Container images: ${image_name}")
        fi
    else
        log_warn "No container images found for ${CLOUD_RUN_SERVICE}"
    fi
}

# Delete Cloud Composer environment
cleanup_composer() {
    log_info "Cleaning up Cloud Composer environment..."
    
    # Check if environment exists
    if gcloud composer environments describe "${COMPOSER_ENV_NAME}" \
        --location "${REGION}" &> /dev/null; then
        
        log_info "Deleting Composer environment: ${COMPOSER_ENV_NAME}"
        log_warn "This may take 10-15 minutes..."
        
        if gcloud composer environments delete "${COMPOSER_ENV_NAME}" \
            --location "${REGION}" \
            --quiet; then
            log "✅ Composer environment deletion initiated"
            
            # Wait for deletion to complete
            log_info "Waiting for Composer environment deletion to complete..."
            local wait_time=0
            local max_wait=1200  # 20 minutes
            
            while [[ $wait_time -lt $max_wait ]]; do
                if ! gcloud composer environments describe "${COMPOSER_ENV_NAME}" \
                    --location "${REGION}" &> /dev/null; then
                    log "✅ Composer environment deleted successfully"
                    break
                fi
                
                sleep 30
                wait_time=$((wait_time + 30))
                log_info "Still waiting... (${wait_time}s elapsed)"
            done
            
            if [[ $wait_time -ge $max_wait ]]; then
                log_warn "⚠️  Composer environment deletion timeout, but process is likely still running"
            fi
        else
            log_error "❌ Failed to delete Composer environment"
            FAILED_DELETIONS+=("Composer environment: ${COMPOSER_ENV_NAME}")
        fi
    else
        log_warn "Composer environment ${COMPOSER_ENV_NAME} not found"
    fi
}

# Delete Cloud Storage bucket and contents
cleanup_storage() {
    log_info "Cleaning up Cloud Storage bucket..."
    
    # Check if bucket exists
    if gsutil ls -b "gs://${STORAGE_BUCKET}" &> /dev/null; then
        log_info "Deleting storage bucket and all contents: gs://${STORAGE_BUCKET}"
        
        # Remove all objects and versions
        if gsutil -m rm -r "gs://${STORAGE_BUCKET}"; then
            log "✅ Storage bucket deleted successfully"
        else
            log_error "❌ Failed to delete storage bucket"
            FAILED_DELETIONS+=("Storage bucket: ${STORAGE_BUCKET}")
        fi
    else
        log_warn "Storage bucket gs://${STORAGE_BUCKET} not found"
    fi
}

# Clean up any remaining GCS objects
cleanup_orphaned_storage() {
    log_info "Checking for orphaned storage objects..."
    
    # Look for any buckets with our naming pattern
    local orphaned_buckets
    orphaned_buckets=$(gsutil ls -b -p "${PROJECT_ID}" | grep "content-pipeline" || true)
    
    if [[ -n "${orphaned_buckets}" ]]; then
        log_warn "Found potential orphaned buckets:"
        echo "${orphaned_buckets}"
        
        if [[ "${FORCE_DELETE:-false}" == "true" ]]; then
            log_info "Force delete enabled, removing orphaned buckets..."
            echo "${orphaned_buckets}" | while read -r bucket; do
                if [[ -n "${bucket}" ]]; then
                    log_info "Deleting orphaned bucket: ${bucket}"
                    gsutil -m rm -r "${bucket}" || log_warn "Failed to delete ${bucket}"
                fi
            done
        else
            log_info "Skipping orphaned buckets (use FORCE_DELETE=true to remove)"
        fi
    else
        log "No orphaned storage buckets found"
    fi
}

# Clean up build artifacts and logs
cleanup_build_artifacts() {
    log_info "Cleaning up build artifacts..."
    
    # Clean up Cloud Build history for our images
    local build_ids
    build_ids=$(gcloud builds list \
        --filter="images:gcr.io/${PROJECT_ID}/${CLOUD_RUN_SERVICE}" \
        --format="value(id)" \
        --limit=50 2>/dev/null || true)
    
    if [[ -n "${build_ids}" ]]; then
        log_info "Found ${build_ids} build artifacts"
        # Note: We don't delete build history as it's useful for auditing
        log_info "Build history preserved for auditing purposes"
    fi
    
    # Clean up local temporary files
    local temp_files=(
        "${SCRIPT_DIR}/requirements.txt"
        "${SCRIPT_DIR}/content_api.py"
        "${SCRIPT_DIR}/Dockerfile"
        "${SCRIPT_DIR}/content_generation_dag.py"
    )
    
    for file in "${temp_files[@]}"; do
        if [[ -f "${file}" ]]; then
            rm -f "${file}"
            log_info "Removed temporary file: $(basename "${file}")"
        fi
    done
}

# Validate cleanup completion
validate_cleanup() {
    log_info "Validating cleanup completion..."
    
    local validation_errors=0
    
    # Check Composer environment
    if gcloud composer environments describe "${COMPOSER_ENV_NAME}" \
        --location "${REGION}" &> /dev/null; then
        log_warn "⚠️  Composer environment still exists (may still be deleting)"
        validation_errors=$((validation_errors + 1))
    else
        log "✅ Composer environment successfully removed"
    fi
    
    # Check storage bucket
    if gsutil ls -b "gs://${STORAGE_BUCKET}" &> /dev/null; then
        log_warn "⚠️  Storage bucket still exists"
        validation_errors=$((validation_errors + 1))
    else
        log "✅ Storage bucket successfully removed"
    fi
    
    # Check Cloud Run service
    if gcloud run services describe "${CLOUD_RUN_SERVICE}" \
        --region "${REGION}" &> /dev/null; then
        log_warn "⚠️  Cloud Run service still exists"
        validation_errors=$((validation_errors + 1))
    else
        log "✅ Cloud Run service successfully removed"
    fi
    
    # Check container images
    if gcloud container images list --repository="gcr.io/${PROJECT_ID}" \
        --filter="name:${CLOUD_RUN_SERVICE}" --format="value(name)" | grep -q "${CLOUD_RUN_SERVICE}"; then
        log_warn "⚠️  Container images still exist"
        validation_errors=$((validation_errors + 1))
    else
        log "✅ Container images successfully removed"
    fi
    
    if [[ $validation_errors -eq 0 ]]; then
        log "✅ All resources successfully cleaned up"
    else
        log_warn "⚠️  Some resources may still be in the process of deletion"
    fi
    
    return $validation_errors
}

# Display cleanup summary
show_cleanup_summary() {
    log_info "Cleanup Summary"
    echo -e "${BLUE}=================================================================="
    echo "  Multi-Modal AI Content Generation Pipeline"
    echo "  Cleanup completed!"
    echo "=================================================================="
    echo -e "${NC}"
    
    if [[ ${#FAILED_DELETIONS[@]} -eq 0 ]]; then
        echo -e "${GREEN}✅ All resources were successfully deleted${NC}"
    else
        echo -e "${YELLOW}⚠️  Some resources failed to delete:${NC}"
        for failure in "${FAILED_DELETIONS[@]}"; do
            echo "   - ${failure}"
        done
        echo ""
        echo "Please check these resources manually in the Google Cloud Console"
    fi
    
    echo ""
    echo "📋 Cleaned up resources:"
    echo "   - Cloud Composer environment: ${COMPOSER_ENV_NAME}"
    echo "   - Cloud Storage bucket: gs://${STORAGE_BUCKET}"
    echo "   - Cloud Run service: ${CLOUD_RUN_SERVICE}"
    echo "   - Container images and build artifacts"
    echo ""
    echo "📂 Configuration files:"
    echo "   - Config file: ${CONFIG_FILE} (preserved)"
    echo "   - Cleanup log: ${LOG_FILE}"
    echo ""
    
    if [[ ${#FAILED_DELETIONS[@]} -eq 0 ]]; then
        echo -e "${GREEN}💰 All billable resources have been removed!${NC}"
    else
        echo -e "${YELLOW}⚠️  Please verify all billable resources are removed to avoid charges${NC}"
    fi
    echo ""
}

# Optional: Complete project cleanup
cleanup_project() {
    if [[ "${DELETE_PROJECT:-false}" == "true" ]]; then
        log_warn "Project deletion requested"
        echo -e "${RED}"
        echo "⚠️  WARNING: This will delete the entire project: ${PROJECT_ID}"
        echo "This action is IRREVERSIBLE and will delete ALL resources in the project!"
        echo -e "${NC}"
        
        read -p "Type the project ID to confirm project deletion: " project_confirmation
        
        if [[ "${project_confirmation}" == "${PROJECT_ID}" ]]; then
            log_info "Deleting project: ${PROJECT_ID}"
            if gcloud projects delete "${PROJECT_ID}" --quiet; then
                log "✅ Project deleted successfully"
                echo "Note: Project deletion may take several minutes to complete"
            else
                log_error "❌ Failed to delete project"
            fi
        else
            log_info "Project deletion cancelled (ID mismatch)"
        fi
    fi
}

# Main cleanup function
main() {
    show_banner
    
    log "Starting cleanup of Multi-Modal AI Content Generation Pipeline"
    log "Cleanup started at $(date)"
    
    # Pre-cleanup setup
    load_configuration
    configure_gcloud
    confirm_cleanup
    
    # Execute cleanup operations
    cleanup_cloud_run
    cleanup_storage
    cleanup_composer
    cleanup_orphaned_storage
    cleanup_build_artifacts
    
    # Post-cleanup validation
    if validate_cleanup; then
        log "All resources successfully cleaned up"
    else
        log_warn "Some resources may still be in the process of deletion"
    fi
    
    # Optional complete project deletion
    cleanup_project
    
    show_cleanup_summary
    
    log "Cleanup completed at $(date)"
    log "Total cleanup time: $SECONDS seconds"
}

# Helper function for force cleanup
force_cleanup() {
    export FORCE_DELETE=true
    main "$@"
}

# Display help information
show_help() {
    echo "Multi-Modal AI Content Generation Pipeline Cleanup Script"
    echo ""
    echo "Usage:"
    echo "  $0                 - Interactive cleanup with confirmations"
    echo "  $0 --force         - Force cleanup without confirmations"
    echo "  $0 --delete-project - Also delete the entire project"
    echo "  $0 --help          - Show this help message"
    echo ""
    echo "Environment Variables:"
    echo "  FORCE_DELETE=true     - Skip all confirmations"
    echo "  DELETE_PROJECT=true   - Include project deletion"
    echo ""
    echo "Examples:"
    echo "  $0                                    # Interactive cleanup"
    echo "  $0 --force                           # Force cleanup"
    echo "  DELETE_PROJECT=true $0 --force       # Delete everything including project"
    echo ""
}

# Script entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    case "${1:-}" in
        --help|-h)
            show_help
            exit 0
            ;;
        --force)
            force_cleanup "${@:2}"
            ;;
        --delete-project)
            export DELETE_PROJECT=true
            main "${@:2}"
            ;;
        *)
            main "$@"
            ;;
    esac
fi