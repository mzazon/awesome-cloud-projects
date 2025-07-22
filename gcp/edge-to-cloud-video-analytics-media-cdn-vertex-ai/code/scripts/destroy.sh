#!/bin/bash

# Edge-to-Cloud Video Analytics with Media CDN and Vertex AI - Cleanup Script
# This script removes all resources created by the deployment script

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

# Configuration variables
DEPLOYMENT_CONFIG=".deployment_config"
FORCE_DELETE=false
SKIP_CONFIRMATION=false

# Parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --force)
                FORCE_DELETE=true
                shift
                ;;
            --yes|-y)
                SKIP_CONFIRMATION=true
                shift
                ;;
            --config)
                DEPLOYMENT_CONFIG="$2"
                shift 2
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            *)
                error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

# Show help information
show_help() {
    echo "Edge-to-Cloud Video Analytics Cleanup Script"
    echo ""
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --force         Force deletion without checking dependencies"
    echo "  --yes, -y       Skip confirmation prompts"
    echo "  --config FILE   Use specific deployment config file (default: .deployment_config)"
    echo "  --help, -h      Show this help message"
    echo ""
    echo "This script will remove all resources created by the deployment script."
    echo "It uses the .deployment_config file to identify resources to delete."
}

# Load deployment configuration
load_configuration() {
    log "Loading deployment configuration..."
    
    if [[ ! -f "${DEPLOYMENT_CONFIG}" ]]; then
        error "Deployment configuration file not found: ${DEPLOYMENT_CONFIG}"
        error "Please ensure you're running this script from the same directory as the deployment."
        exit 1
    fi
    
    # Source the configuration file
    source "${DEPLOYMENT_CONFIG}"
    
    # Verify required variables are set
    local required_vars=("PROJECT_ID" "REGION" "BUCKET_NAME" "RESULTS_BUCKET" "FUNCTION_NAME")
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            error "Required variable ${var} not found in configuration file"
            exit 1
        fi
    done
    
    log "Configuration loaded successfully"
    info "  Project ID: ${PROJECT_ID}"
    info "  Region: ${REGION}"
    info "  Random Suffix: ${RANDOM_SUFFIX:-unknown}"
}

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        error "Google Cloud CLI (gcloud) is not installed."
        exit 1
    fi
    
    # Check if gsutil is available
    if ! command -v gsutil &> /dev/null; then
        error "gsutil is not available."
        exit 1
    fi
    
    # Check if user is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 > /dev/null; then
        error "No active Google Cloud authentication found. Please run 'gcloud auth login' first."
        exit 1
    fi
    
    # Set the project context
    gcloud config set project "${PROJECT_ID}" --quiet
    
    log "Prerequisites check completed successfully"
}

# Confirm destruction
confirm_destruction() {
    if [[ "${SKIP_CONFIRMATION}" == "true" ]]; then
        return 0
    fi
    
    echo ""
    warn "⚠️  DESTRUCTIVE OPERATION WARNING ⚠️"
    echo ""
    error "This will permanently delete the following resources:"
    echo ""
    info "  📦 Cloud Storage Buckets:"
    info "     - gs://${BUCKET_NAME} (and all contents)"
    info "     - gs://${RESULTS_BUCKET} (and all contents)"
    echo ""
    info "  ⚡ Cloud Functions:"
    info "     - ${FUNCTION_NAME}"
    [[ -n "${ADVANCED_FUNCTION_NAME:-}" ]] && info "     - ${ADVANCED_FUNCTION_NAME}"
    [[ -n "${RESULTS_FUNCTION_NAME:-}" ]] && info "     - ${RESULTS_FUNCTION_NAME}"
    echo ""
    info "  🤖 Vertex AI Resources:"
    [[ -n "${DATASET_ID:-}" ]] && info "     - Dataset ID: ${DATASET_ID}"
    echo ""
    info "  🌐 Media CDN Resources:"
    info "     - EdgeCacheOrigin: ${CDN_SERVICE_NAME}-origin"
    echo ""
    
    echo -n "Are you absolutely sure you want to proceed? (type 'yes' to confirm): "
    read -r confirmation
    
    if [[ "${confirmation}" != "yes" ]]; then
        info "Cleanup cancelled by user"
        exit 0
    fi
    
    echo ""
    log "Confirmation received. Proceeding with resource deletion..."
}

# Delete Cloud Functions
delete_cloud_functions() {
    log "Deleting Cloud Functions..."
    
    # Delete basic video processor function
    if gcloud functions describe "${FUNCTION_NAME}" --region="${REGION}" >/dev/null 2>&1; then
        info "Deleting function: ${FUNCTION_NAME}"
        gcloud functions delete "${FUNCTION_NAME}" \
            --region="${REGION}" \
            --quiet
        log "Deleted function: ${FUNCTION_NAME}"
    else
        warn "Function ${FUNCTION_NAME} not found or already deleted"
    fi
    
    # Delete advanced video analytics function
    if [[ -n "${ADVANCED_FUNCTION_NAME:-}" ]]; then
        if gcloud functions describe "${ADVANCED_FUNCTION_NAME}" --region="${REGION}" >/dev/null 2>&1; then
            info "Deleting function: ${ADVANCED_FUNCTION_NAME}"
            gcloud functions delete "${ADVANCED_FUNCTION_NAME}" \
                --region="${REGION}" \
                --quiet
            log "Deleted function: ${ADVANCED_FUNCTION_NAME}"
        else
            warn "Function ${ADVANCED_FUNCTION_NAME} not found or already deleted"
        fi
    fi
    
    # Delete results processor function
    if [[ -n "${RESULTS_FUNCTION_NAME:-}" ]]; then
        if gcloud functions describe "${RESULTS_FUNCTION_NAME}" --region="${REGION}" >/dev/null 2>&1; then
            info "Deleting function: ${RESULTS_FUNCTION_NAME}"
            gcloud functions delete "${RESULTS_FUNCTION_NAME}" \
                --region="${REGION}" \
                --quiet
            log "Deleted function: ${RESULTS_FUNCTION_NAME}"
        else
            warn "Function ${RESULTS_FUNCTION_NAME} not found or already deleted"
        fi
    fi
    
    log "Cloud Functions cleanup completed"
}

# Delete Vertex AI resources
delete_vertex_ai_resources() {
    log "Deleting Vertex AI resources..."
    
    if [[ -n "${DATASET_ID:-}" ]]; then
        if gcloud ai datasets describe "${DATASET_ID}" --region="${REGION}" >/dev/null 2>&1; then
            info "Deleting Vertex AI dataset: ${DATASET_ID}"
            gcloud ai datasets delete "${DATASET_ID}" \
                --region="${REGION}" \
                --quiet
            log "Deleted Vertex AI dataset: ${DATASET_ID}"
        else
            warn "Vertex AI dataset ${DATASET_ID} not found or already deleted"
        fi
    else
        warn "No Vertex AI dataset ID found in configuration"
    fi
    
    log "Vertex AI resources cleanup completed"
}

# Delete Media CDN resources
delete_media_cdn_resources() {
    log "Deleting Media CDN resources..."
    
    # Delete EdgeCacheOrigin
    if gcloud compute network-edge-security-services describe "${CDN_SERVICE_NAME}-origin" --region="${REGION}" >/dev/null 2>&1; then
        info "Deleting EdgeCacheOrigin: ${CDN_SERVICE_NAME}-origin"
        gcloud compute network-edge-security-services delete "${CDN_SERVICE_NAME}-origin" \
            --region="${REGION}" \
            --quiet
        log "Deleted EdgeCacheOrigin: ${CDN_SERVICE_NAME}-origin"
    else
        warn "EdgeCacheOrigin ${CDN_SERVICE_NAME}-origin not found or already deleted"
    fi
    
    log "Media CDN resources cleanup completed"
}

# Delete Cloud Storage buckets
delete_storage_buckets() {
    log "Deleting Cloud Storage buckets..."
    
    # Delete video content bucket
    if gsutil ls "gs://${BUCKET_NAME}" >/dev/null 2>&1; then
        info "Deleting video content bucket and all contents: gs://${BUCKET_NAME}"
        
        # Remove all objects first (including versioned objects)
        gsutil -m rm -r "gs://${BUCKET_NAME}/**" 2>/dev/null || true
        
        # Remove the bucket
        gsutil rb "gs://${BUCKET_NAME}"
        log "Deleted bucket: gs://${BUCKET_NAME}"
    else
        warn "Bucket gs://${BUCKET_NAME} not found or already deleted"
    fi
    
    # Delete analytics results bucket
    if gsutil ls "gs://${RESULTS_BUCKET}" >/dev/null 2>&1; then
        info "Deleting analytics results bucket and all contents: gs://${RESULTS_BUCKET}"
        
        # Remove all objects first (including versioned objects)
        gsutil -m rm -r "gs://${RESULTS_BUCKET}/**" 2>/dev/null || true
        
        # Remove the bucket
        gsutil rb "gs://${RESULTS_BUCKET}"
        log "Deleted bucket: gs://${RESULTS_BUCKET}"
    else
        warn "Bucket gs://${RESULTS_BUCKET} not found or already deleted"
    fi
    
    log "Cloud Storage buckets cleanup completed"
}

# Clean up local files
cleanup_local_files() {
    log "Cleaning up local files..."
    
    local cleanup_dirs=(
        "video-processor-function"
        "advanced-video-analytics"
        "results-processor"
    )
    
    local cleanup_files=(
        "media-cdn-config.yaml"
        "video-analysis-config.json"
        "${DEPLOYMENT_CONFIG}"
    )
    
    # Remove directories
    for dir in "${cleanup_dirs[@]}"; do
        if [[ -d "${dir}" ]]; then
            info "Removing directory: ${dir}"
            rm -rf "${dir}"
        fi
    done
    
    # Remove files
    for file in "${cleanup_files[@]}"; do
        if [[ -f "${file}" ]]; then
            info "Removing file: ${file}"
            rm -f "${file}"
        fi
    done
    
    log "Local files cleanup completed"
}

# Verify cleanup completion
verify_cleanup() {
    log "Verifying cleanup completion..."
    
    local cleanup_errors=0
    
    # Check Cloud Functions
    if gcloud functions describe "${FUNCTION_NAME}" --region="${REGION}" >/dev/null 2>&1; then
        error "❌ Function still exists: ${FUNCTION_NAME}"
        ((cleanup_errors++))
    else
        info "✅ Function deleted: ${FUNCTION_NAME}"
    fi
    
    # Check advanced function if it existed
    if [[ -n "${ADVANCED_FUNCTION_NAME:-}" ]]; then
        if gcloud functions describe "${ADVANCED_FUNCTION_NAME}" --region="${REGION}" >/dev/null 2>&1; then
            error "❌ Function still exists: ${ADVANCED_FUNCTION_NAME}"
            ((cleanup_errors++))
        else
            info "✅ Function deleted: ${ADVANCED_FUNCTION_NAME}"
        fi
    fi
    
    # Check results function if it existed
    if [[ -n "${RESULTS_FUNCTION_NAME:-}" ]]; then
        if gcloud functions describe "${RESULTS_FUNCTION_NAME}" --region="${REGION}" >/dev/null 2>&1; then
            error "❌ Function still exists: ${RESULTS_FUNCTION_NAME}"
            ((cleanup_errors++))
        else
            info "✅ Function deleted: ${RESULTS_FUNCTION_NAME}"
        fi
    fi
    
    # Check buckets
    if gsutil ls "gs://${BUCKET_NAME}" >/dev/null 2>&1; then
        error "❌ Bucket still exists: gs://${BUCKET_NAME}"
        ((cleanup_errors++))
    else
        info "✅ Bucket deleted: gs://${BUCKET_NAME}"
    fi
    
    if gsutil ls "gs://${RESULTS_BUCKET}" >/dev/null 2>&1; then
        error "❌ Bucket still exists: gs://${RESULTS_BUCKET}"
        ((cleanup_errors++))
    else
        info "✅ Bucket deleted: gs://${RESULTS_BUCKET}"
    fi
    
    # Check Vertex AI dataset
    if [[ -n "${DATASET_ID:-}" ]]; then
        if gcloud ai datasets describe "${DATASET_ID}" --region="${REGION}" >/dev/null 2>&1; then
            error "❌ Dataset still exists: ${DATASET_ID}"
            ((cleanup_errors++))
        else
            info "✅ Dataset deleted: ${DATASET_ID}"
        fi
    fi
    
    if [[ ${cleanup_errors} -eq 0 ]]; then
        log "Cleanup verification completed successfully"
    else
        error "Cleanup verification found ${cleanup_errors} remaining resources"
        error "Manual cleanup may be required for remaining resources"
        return 1
    fi
}

# Display cleanup summary
display_summary() {
    log "Cleanup Summary"
    echo ""
    info "🧹 Edge-to-Cloud Video Analytics Pipeline Cleanup Completed!"
    echo ""
    info "Resources Removed:"
    info "  📦 Cloud Storage Buckets: gs://${BUCKET_NAME}, gs://${RESULTS_BUCKET}"
    info "  ⚡ Cloud Functions: ${FUNCTION_NAME}"
    [[ -n "${ADVANCED_FUNCTION_NAME:-}" ]] && info "                      ${ADVANCED_FUNCTION_NAME}"
    [[ -n "${RESULTS_FUNCTION_NAME:-}" ]] && info "                      ${RESULTS_FUNCTION_NAME}"
    [[ -n "${DATASET_ID:-}" ]] && info "  🤖 Vertex AI Dataset: ${DATASET_ID}"
    info "  🌐 Media CDN Origin: ${CDN_SERVICE_NAME}-origin"
    info "  📁 Local Files: Configuration and function code"
    echo ""
    info "💰 All resources have been deleted. No further charges should be incurred."
    echo ""
    warn "Note: It may take a few minutes for all deletions to be reflected in the console."
}

# Handle cleanup errors
handle_cleanup_error() {
    error "Cleanup encountered an error. Some resources may still exist."
    error "Please check the Google Cloud Console and manually delete any remaining resources:"
    echo ""
    info "  Project: ${PROJECT_ID}"
    info "  Region: ${REGION}"
    echo ""
    info "You may also try running this script again with --force flag"
    exit 1
}

# Set up error handling
trap handle_cleanup_error ERR

# Main cleanup flow
main() {
    log "Starting Edge-to-Cloud Video Analytics Pipeline Cleanup"
    
    parse_arguments "$@"
    load_configuration
    check_prerequisites
    confirm_destruction
    
    # Execute cleanup in reverse order of creation
    delete_cloud_functions
    delete_vertex_ai_resources
    delete_media_cdn_resources
    delete_storage_buckets
    cleanup_local_files
    
    # Verify cleanup
    if ! verify_cleanup; then
        if [[ "${FORCE_DELETE}" == "true" ]]; then
            warn "Verification failed but continuing due to --force flag"
        else
            exit 1
        fi
    fi
    
    display_summary
    
    log "Cleanup completed successfully! 🎉"
}

# Run main function
main "$@"