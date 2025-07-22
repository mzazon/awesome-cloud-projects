#!/bin/bash

# Real-Time Streaming Analytics with Cloud Media CDN and Live Stream API - Cleanup Script
# This script safely removes all infrastructure resources created for the streaming analytics solution

set -euo pipefail  # Exit on error, undefined vars, pipe failures

# Script configuration
readonly SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_FILE="/tmp/${SCRIPT_NAME%.*}_$(date +%Y%m%d_%H%M%S).log"

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Logging function
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${timestamp} [${level}] ${message}" | tee -a "${LOG_FILE}"
}

info() { log "INFO" "$*"; }
warn() { log "WARN" "${YELLOW}$*${NC}"; }
error() { log "ERROR" "${RED}$*${NC}"; }
success() { log "SUCCESS" "${GREEN}$*${NC}"; }

# Error handler
cleanup_on_error() {
    local exit_code=$?
    error "Cleanup failed with exit code ${exit_code}"
    error "Check log file: ${LOG_FILE}"
    info "Some resources may still exist. You can re-run this script or clean up manually."
    exit ${exit_code}
}

trap cleanup_on_error ERR

# Print banner
print_banner() {
    echo -e "${BLUE}"
    echo "=================================================================="
    echo "  Real-Time Streaming Analytics Infrastructure Cleanup"
    echo "  GCP Recipe: real-time-streaming-analytics-media-cdn-live-stream-api"
    echo "=================================================================="
    echo -e "${NC}"
}

# Load environment variables
load_environment() {
    info "Loading environment variables..."
    
    # Try to load from .env file created by deploy script
    if [[ -f "${SCRIPT_DIR}/.env" ]]; then
        # shellcheck source=/dev/null
        source "${SCRIPT_DIR}/.env"
        info "Loaded environment from ${SCRIPT_DIR}/.env"
    else
        warn "Environment file not found. Using defaults or environment variables."
        
        # Set defaults if not provided
        export PROJECT_ID="${PROJECT_ID:-}"
        export REGION="${REGION:-us-central1}"
        export ZONE="${ZONE:-us-central1-a}"
        
        # Generate a fallback suffix for resource cleanup
        RANDOM_SUFFIX="${RANDOM_SUFFIX:-$(date +%s | tail -c 6)}"
        export BUCKET_NAME="${BUCKET_NAME:-streaming-content-${RANDOM_SUFFIX}}"
        export FUNCTION_NAME="${FUNCTION_NAME:-stream-analytics-processor}"
        export DATASET_NAME="${DATASET_NAME:-streaming_analytics}"
        export PUBSUB_TOPIC="${PUBSUB_TOPIC:-stream-events}"
        export LIVE_INPUT_NAME="${LIVE_INPUT_NAME:-live-input-${RANDOM_SUFFIX}}"
        export LIVE_CHANNEL_NAME="${LIVE_CHANNEL_NAME:-live-channel-${RANDOM_SUFFIX}}"
        export CDN_ORIGIN_NAME="${CDN_ORIGIN_NAME:-streaming-origin-${RANDOM_SUFFIX}}"
        export CDN_SERVICE_NAME="${CDN_SERVICE_NAME:-streaming-service-${RANDOM_SUFFIX}}"
    fi
    
    # Validate required variables
    if [[ -z "${PROJECT_ID}" ]]; then
        error "PROJECT_ID is not set. Please set it as an environment variable or ensure .env file exists."
        exit 1
    fi
    
    info "Environment configured for cleanup:"
    info "  PROJECT_ID: ${PROJECT_ID}"
    info "  REGION: ${REGION}"
    info "  BUCKET_NAME: ${BUCKET_NAME}"
    info "  FUNCTION_NAME: ${FUNCTION_NAME}"
    info "  DATASET_NAME: ${DATASET_NAME}"
    
    # Set gcloud defaults
    gcloud config set project "${PROJECT_ID}" --quiet
    gcloud config set compute/region "${REGION}" --quiet
    gcloud config set compute/zone "${ZONE}" --quiet
}

# Check prerequisites
check_prerequisites() {
    info "Checking prerequisites for cleanup..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        error "gcloud CLI is not installed. Please install Google Cloud SDK."
        exit 1
    fi
    
    # Check if gsutil is installed
    if ! command -v gsutil &> /dev/null; then
        error "gsutil is not installed. Please install Google Cloud SDK."
        exit 1
    fi
    
    # Check if bq is installed
    if ! command -v bq &> /dev/null; then
        error "bq CLI is not installed. Please install Google Cloud SDK."
        exit 1
    fi
    
    # Check if user is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -1 &> /dev/null; then
        error "No active gcloud authentication found. Please run 'gcloud auth login'"
        exit 1
    fi
    
    # Verify project exists and is accessible
    if ! gcloud projects describe "${PROJECT_ID}" &>/dev/null; then
        error "Project ${PROJECT_ID} does not exist or is not accessible"
        exit 1
    fi
    
    success "All prerequisites satisfied"
}

# Confirmation prompt
confirm_destruction() {
    echo -e "\n${YELLOW}⚠️  WARNING: This will permanently delete the following resources:${NC}"
    echo "  • Project: ${PROJECT_ID}"
    echo "  • Storage Bucket: gs://${BUCKET_NAME} (and all contents)"
    echo "  • BigQuery Dataset: ${DATASET_NAME} (and all tables/views)"
    echo "  • Pub/Sub Topic: ${PUBSUB_TOPIC}"
    echo "  • Cloud Function: ${FUNCTION_NAME}"
    echo "  • Live Stream Input: ${LIVE_INPUT_NAME}"
    echo "  • Live Stream Channel: ${LIVE_CHANNEL_NAME}"
    echo "  • CDN Origin: ${CDN_ORIGIN_NAME}"
    echo
    
    if [[ "${FORCE_DESTROY:-false}" == "true" ]]; then
        warn "FORCE_DESTROY is set, skipping confirmation"
        return 0
    fi
    
    read -p "Are you sure you want to proceed? Type 'yes' to continue: " -r
    if [[ ! $REPLY == "yes" ]]; then
        info "Cleanup cancelled by user"
        exit 0
    fi
    
    info "User confirmed destruction, proceeding with cleanup..."
}

# Stop Live Stream channel
stop_live_stream() {
    info "Stopping Live Stream channel..."
    
    # Check if channel exists and is running
    if gcloud livestream channels describe "${LIVE_CHANNEL_NAME}" --location="${REGION}" &>/dev/null; then
        local status=$(gcloud livestream channels describe "${LIVE_CHANNEL_NAME}" \
            --location="${REGION}" \
            --format="value(state)" 2>/dev/null || echo "UNKNOWN")
        
        if [[ "${status}" == "RUNNING" ]]; then
            info "Stopping live stream channel..."
            gcloud livestream channels stop "${LIVE_CHANNEL_NAME}" \
                --location="${REGION}" || true
            
            # Wait for channel to stop
            info "Waiting for channel to stop..."
            local max_attempts=15
            local attempt=0
            
            while [[ ${attempt} -lt ${max_attempts} ]]; do
                local current_status=$(gcloud livestream channels describe "${LIVE_CHANNEL_NAME}" \
                    --location="${REGION}" \
                    --format="value(state)" 2>/dev/null || echo "UNKNOWN")
                
                if [[ "${current_status}" == "IDLE" ]]; then
                    success "Live Stream channel stopped"
                    break
                else
                    info "Channel status: ${current_status} (attempt $((attempt + 1))/${max_attempts})"
                    sleep 5
                    ((attempt++))
                fi
            done
            
            if [[ ${attempt} -eq ${max_attempts} ]]; then
                warn "Channel stop verification timed out, proceeding with deletion"
            fi
        else
            info "Channel is not running, status: ${status}"
        fi
    else
        info "Live Stream channel ${LIVE_CHANNEL_NAME} not found, skipping stop"
    fi
}

# Delete Live Stream resources
delete_live_stream_resources() {
    info "Deleting Live Stream resources..."
    
    # Delete channel
    if gcloud livestream channels describe "${LIVE_CHANNEL_NAME}" --location="${REGION}" &>/dev/null; then
        info "Deleting Live Stream channel: ${LIVE_CHANNEL_NAME}"
        gcloud livestream channels delete "${LIVE_CHANNEL_NAME}" \
            --location="${REGION}" \
            --quiet || warn "Failed to delete channel ${LIVE_CHANNEL_NAME}"
        success "Live Stream channel deleted"
    else
        info "Live Stream channel ${LIVE_CHANNEL_NAME} not found, skipping deletion"
    fi
    
    # Delete input
    if gcloud livestream inputs describe "${LIVE_INPUT_NAME}" --location="${REGION}" &>/dev/null; then
        info "Deleting Live Stream input: ${LIVE_INPUT_NAME}"
        gcloud livestream inputs delete "${LIVE_INPUT_NAME}" \
            --location="${REGION}" \
            --quiet || warn "Failed to delete input ${LIVE_INPUT_NAME}"
        success "Live Stream input deleted"
    else
        info "Live Stream input ${LIVE_INPUT_NAME} not found, skipping deletion"
    fi
}

# Remove Media CDN configuration
remove_media_cdn() {
    info "Removing Media CDN configuration..."
    
    # Delete CDN service (if it exists)
    if gcloud network-services edge-cache-services describe "${CDN_SERVICE_NAME}" &>/dev/null; then
        info "Deleting CDN service: ${CDN_SERVICE_NAME}"
        gcloud network-services edge-cache-services delete "${CDN_SERVICE_NAME}" \
            --quiet || warn "Failed to delete CDN service ${CDN_SERVICE_NAME}"
        success "CDN service deleted"
    else
        info "CDN service ${CDN_SERVICE_NAME} not found, skipping deletion"
    fi
    
    # Delete CDN origin
    if gcloud network-services edge-cache-origins describe "${CDN_ORIGIN_NAME}" &>/dev/null; then
        info "Deleting CDN origin: ${CDN_ORIGIN_NAME}"
        gcloud network-services edge-cache-origins delete "${CDN_ORIGIN_NAME}" \
            --quiet || warn "Failed to delete CDN origin ${CDN_ORIGIN_NAME}"
        success "CDN origin deleted"
    else
        info "CDN origin ${CDN_ORIGIN_NAME} not found, skipping deletion"
    fi
}

# Delete Cloud Function
delete_cloud_function() {
    info "Deleting Cloud Function..."
    
    if gcloud functions describe "${FUNCTION_NAME}" --region="${REGION}" &>/dev/null; then
        info "Deleting Cloud Function: ${FUNCTION_NAME}"
        gcloud functions delete "${FUNCTION_NAME}" \
            --region="${REGION}" \
            --quiet || warn "Failed to delete function ${FUNCTION_NAME}"
        success "Cloud Function deleted"
    else
        info "Cloud Function ${FUNCTION_NAME} not found, skipping deletion"
    fi
}

# Delete Pub/Sub resources
delete_pubsub_resources() {
    info "Deleting Pub/Sub resources..."
    
    # Delete subscription
    if gcloud pubsub subscriptions describe "${PUBSUB_TOPIC}-bq-subscription" &>/dev/null; then
        info "Deleting Pub/Sub subscription: ${PUBSUB_TOPIC}-bq-subscription"
        gcloud pubsub subscriptions delete "${PUBSUB_TOPIC}-bq-subscription" \
            --quiet || warn "Failed to delete subscription ${PUBSUB_TOPIC}-bq-subscription"
        success "Pub/Sub subscription deleted"
    else
        info "Pub/Sub subscription ${PUBSUB_TOPIC}-bq-subscription not found, skipping deletion"
    fi
    
    # Delete topic
    if gcloud pubsub topics describe "${PUBSUB_TOPIC}" &>/dev/null; then
        info "Deleting Pub/Sub topic: ${PUBSUB_TOPIC}"
        gcloud pubsub topics delete "${PUBSUB_TOPIC}" \
            --quiet || warn "Failed to delete topic ${PUBSUB_TOPIC}"
        success "Pub/Sub topic deleted"
    else
        info "Pub/Sub topic ${PUBSUB_TOPIC} not found, skipping deletion"
    fi
}

# Delete BigQuery resources
delete_bigquery_resources() {
    info "Deleting BigQuery resources..."
    
    # Check if dataset exists
    if bq ls -d "${PROJECT_ID}:${DATASET_NAME}" &>/dev/null; then
        info "Deleting BigQuery dataset: ${DATASET_NAME}"
        
        # List tables in the dataset for confirmation
        local tables=$(bq ls --format=csv "${PROJECT_ID}:${DATASET_NAME}" 2>/dev/null | tail -n +2 | wc -l)
        if [[ "${tables}" -gt 0 ]]; then
            info "Dataset contains ${tables} table(s), deleting all..."
        fi
        
        # Delete dataset and all tables
        bq rm -r -f "${PROJECT_ID}:${DATASET_NAME}" || warn "Failed to delete dataset ${DATASET_NAME}"
        success "BigQuery dataset and all tables deleted"
    else
        info "BigQuery dataset ${DATASET_NAME} not found, skipping deletion"
    fi
}

# Delete Storage bucket
delete_storage_bucket() {
    info "Deleting Cloud Storage bucket..."
    
    # Check if bucket exists
    if gsutil ls -b gs://"${BUCKET_NAME}" &>/dev/null; then
        info "Deleting storage bucket: gs://${BUCKET_NAME}"
        
        # Get object count for confirmation
        local object_count=$(gsutil ls gs://"${BUCKET_NAME}/**" 2>/dev/null | wc -l || echo "0")
        if [[ "${object_count}" -gt 0 ]]; then
            info "Bucket contains ${object_count} object(s), deleting all..."
        fi
        
        # Delete bucket and all contents
        gsutil -m rm -r gs://"${BUCKET_NAME}" || warn "Failed to delete bucket ${BUCKET_NAME}"
        success "Storage bucket and all contents deleted"
    else
        info "Storage bucket gs://${BUCKET_NAME} not found, skipping deletion"
    fi
}

# Clean up temporary files
cleanup_temp_files() {
    info "Cleaning up temporary files and environment..."
    
    # Remove environment file
    if [[ -f "${SCRIPT_DIR}/.env" ]]; then
        rm -f "${SCRIPT_DIR}/.env"
        info "Removed environment file: ${SCRIPT_DIR}/.env"
    fi
    
    # Clean up any temporary configuration files
    rm -f /tmp/channel-config-*.yaml
    rm -f /tmp/lifecycle-policy.json
    
    success "Temporary files cleaned up"
}

# List remaining resources for verification
verify_cleanup() {
    info "Verifying resource cleanup..."
    
    local remaining_resources=0
    
    # Check Live Stream resources
    if gcloud livestream channels list --location="${REGION}" --filter="name:${LIVE_CHANNEL_NAME}" --format="value(name)" 2>/dev/null | grep -q .; then
        warn "Live Stream channel ${LIVE_CHANNEL_NAME} still exists"
        ((remaining_resources++))
    fi
    
    if gcloud livestream inputs list --location="${REGION}" --filter="name:${LIVE_INPUT_NAME}" --format="value(name)" 2>/dev/null | grep -q .; then
        warn "Live Stream input ${LIVE_INPUT_NAME} still exists"
        ((remaining_resources++))
    fi
    
    # Check CDN resources
    if gcloud network-services edge-cache-origins list --filter="name:${CDN_ORIGIN_NAME}" --format="value(name)" 2>/dev/null | grep -q .; then
        warn "CDN origin ${CDN_ORIGIN_NAME} still exists"
        ((remaining_resources++))
    fi
    
    # Check Cloud Function
    if gcloud functions list --regions="${REGION}" --filter="name:${FUNCTION_NAME}" --format="value(name)" 2>/dev/null | grep -q .; then
        warn "Cloud Function ${FUNCTION_NAME} still exists"
        ((remaining_resources++))
    fi
    
    # Check Pub/Sub resources
    if gcloud pubsub topics list --filter="name:${PUBSUB_TOPIC}" --format="value(name)" 2>/dev/null | grep -q .; then
        warn "Pub/Sub topic ${PUBSUB_TOPIC} still exists"
        ((remaining_resources++))
    fi
    
    # Check BigQuery dataset
    if bq ls -d "${PROJECT_ID}:${DATASET_NAME}" &>/dev/null; then
        warn "BigQuery dataset ${DATASET_NAME} still exists"
        ((remaining_resources++))
    fi
    
    # Check Storage bucket
    if gsutil ls -b gs://"${BUCKET_NAME}" &>/dev/null; then
        warn "Storage bucket gs://${BUCKET_NAME} still exists"
        ((remaining_resources++))
    fi
    
    if [[ ${remaining_resources} -eq 0 ]]; then
        success "All resources successfully cleaned up"
    else
        warn "${remaining_resources} resource(s) may still exist. Check the Google Cloud Console for manual cleanup."
    fi
}

# Print cleanup summary
print_summary() {
    echo -e "\n${GREEN}=================================================================="
    echo "  Cleanup Summary"
    echo "==================================================================${NC}"
    echo
    echo "🧹 Cleanup completed for project: ${PROJECT_ID}"
    echo
    echo "✅ Resources processed for deletion:"
    echo "  • Live Stream Channel: ${LIVE_CHANNEL_NAME}"
    echo "  • Live Stream Input: ${LIVE_INPUT_NAME}"
    echo "  • CDN Origin: ${CDN_ORIGIN_NAME}"
    echo "  • Cloud Function: ${FUNCTION_NAME}"
    echo "  • Pub/Sub Topic: ${PUBSUB_TOPIC}"
    echo "  • BigQuery Dataset: ${DATASET_NAME}"
    echo "  • Storage Bucket: gs://${BUCKET_NAME}"
    echo
    echo "📋 Manual cleanup may be required for:"
    echo "  • SSL certificates (if created manually)"
    echo "  • Custom IAM roles or service accounts"
    echo "  • VPC networks or firewall rules (if created)"
    echo "  • Monitoring alerts or dashboards"
    echo
    echo "💰 Cost Impact:"
    echo "  • All billable resources have been deleted"
    echo "  • Check your billing dashboard to confirm charges have stopped"
    echo "  • Some services may have minimal charges for partial usage"
    echo
    echo "📝 Log File: ${LOG_FILE}"
    echo -e "${GREEN}==================================================================${NC}"
}

# Main cleanup function
main() {
    print_banner
    
    info "Starting cleanup at $(date)"
    info "Log file: ${LOG_FILE}"
    
    load_environment
    check_prerequisites
    confirm_destruction
    
    info "Beginning resource cleanup process..."
    
    stop_live_stream
    delete_live_stream_resources
    remove_media_cdn
    delete_cloud_function
    delete_pubsub_resources
    delete_bigquery_resources
    delete_storage_bucket
    cleanup_temp_files
    
    verify_cleanup
    print_summary
    
    success "Cleanup completed successfully at $(date)"
}

# Handle script arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --force)
            export FORCE_DESTROY="true"
            shift
            ;;
        --project)
            export PROJECT_ID="$2"
            shift 2
            ;;
        --region)
            export REGION="$2"
            shift 2
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo "Options:"
            echo "  --force          Skip confirmation prompt"
            echo "  --project ID     Override project ID"
            echo "  --region REGION  Override region"
            echo "  --help           Show this help message"
            exit 0
            ;;
        *)
            error "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Run main function
main "$@"