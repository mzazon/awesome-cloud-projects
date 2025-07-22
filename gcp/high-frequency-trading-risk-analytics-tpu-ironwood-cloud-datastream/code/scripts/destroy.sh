#!/bin/bash

# High-Frequency Trading Risk Analytics Cleanup Script
# This script safely removes all TPU Ironwood, Cloud Datastream, BigQuery, and Cloud Run infrastructure
# for the high-frequency trading risk analytics solution

set -euo pipefail

# Color codes for output formatting
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Global variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="/tmp/hft-risk-analytics-destroy-$(date +%Y%m%d-%H%M%S).log"
DRY_RUN=false
SKIP_CONFIRMATION=false
DELETE_PROJECT=false
FORCE_DELETE=false

# Logging functions
log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] INFO: $1${NC}" | tee -a "${LOG_FILE}"
}

warn() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] WARN: $1${NC}" | tee -a "${LOG_FILE}"
}

error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}" | tee -a "${LOG_FILE}"
}

debug() {
    if [[ "${DEBUG:-false}" == "true" ]]; then
        echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')] DEBUG: $1${NC}" | tee -a "${LOG_FILE}"
    fi
}

# Cleanup function for error handling
cleanup() {
    local exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        error "Cleanup failed with exit code $exit_code"
        error "Check log file: ${LOG_FILE}"
        error "Some resources may still exist and incur charges"
    fi
    exit $exit_code
}

trap cleanup EXIT

# Help function
show_help() {
    cat << EOF
High-Frequency Trading Risk Analytics Cleanup Script

USAGE:
    $0 [OPTIONS]

OPTIONS:
    -h, --help              Show this help message
    -d, --dry-run           Show what would be deleted without removing resources
    -y, --yes               Skip confirmation prompts
    -p, --project PROJECT   Specify GCP project ID to clean up
    -r, --region REGION     Specify GCP region (default: us-central1)
    --delete-project        Delete the entire project (DESTRUCTIVE)
    --force                 Force deletion without safety checks
    --debug                 Enable debug logging

EXAMPLES:
    $0                      Interactive cleanup with prompts
    $0 -y -p my-project     Clean up specific project without prompts
    $0 -d                   Dry run to see what would be deleted
    $0 --delete-project     Delete entire project (requires confirmation)
    $0 --force --delete-project  Force delete project without safety checks

SAFETY FEATURES:
    - Confirmation prompts for destructive operations
    - Dry run mode to preview deletions
    - Detailed logging of all operations
    - Resource dependency validation
    - Billing verification before project deletion

WARNING: This script will delete expensive infrastructure that may have data.
Ensure you have backups of any important data before proceeding.
EOF
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
                ;;
            -d|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -y|--yes)
                SKIP_CONFIRMATION=true
                shift
                ;;
            -p|--project)
                PROJECT_ID="$2"
                shift 2
                ;;
            -r|--region)
                REGION="$2"
                shift 2
                ;;
            --delete-project)
                DELETE_PROJECT=true
                shift
                ;;
            --force)
                FORCE_DELETE=true
                shift
                ;;
            --debug)
                DEBUG=true
                shift
                ;;
            *)
                error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if gcloud is installed and authenticated
    if ! command -v gcloud &> /dev/null; then
        error "Google Cloud CLI (gcloud) is not installed"
        exit 1
    fi
    
    # Check authentication
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 &> /dev/null; then
        error "Not authenticated with Google Cloud"
        error "Run: gcloud auth login"
        exit 1
    fi
    
    local active_account
    active_account=$(gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1)
    log "Authenticated as: ${active_account}"
    
    # Check if bq CLI is available
    if ! command -v bq &> /dev/null; then
        warn "BigQuery CLI (bq) is not installed - some cleanup may be skipped"
    fi
    
    # Check if gsutil is available
    if ! command -v gsutil &> /dev/null; then
        warn "Google Cloud Storage CLI (gsutil) is not installed - some cleanup may be skipped"
    fi
    
    log "✅ Prerequisites check completed"
}

# Detect existing resources
detect_resources() {
    log "Detecting existing resources in project: ${PROJECT_ID}"
    
    # Check if project exists
    if ! gcloud projects describe "${PROJECT_ID}" &> /dev/null; then
        error "Project ${PROJECT_ID} does not exist or is not accessible"
        exit 1
    fi
    
    # Set project context
    gcloud config set project "${PROJECT_ID}" --quiet
    
    # Detect TPU instances
    local tpu_instances
    tpu_instances=$(gcloud compute tpus tpu-vm list --zone="${ZONE}" --filter="name~ironwood-risk-tpu" --format="value(name)" 2>/dev/null || echo "")
    if [[ -n "${tpu_instances}" ]]; then
        log "Found TPU instances: ${tpu_instances}"
        TPU_INSTANCES="${tpu_instances}"
    else
        debug "No TPU instances found"
        TPU_INSTANCES=""
    fi
    
    # Detect Cloud Run services
    local cloud_run_services
    cloud_run_services=$(gcloud run services list --region="${REGION}" --filter="metadata.name~risk-analytics-api" --format="value(metadata.name)" 2>/dev/null || echo "")
    if [[ -n "${cloud_run_services}" ]]; then
        log "Found Cloud Run services: ${cloud_run_services}"
        CLOUD_RUN_SERVICES="${cloud_run_services}"
    else
        debug "No Cloud Run services found"
        CLOUD_RUN_SERVICES=""
    fi
    
    # Detect BigQuery datasets
    local bq_datasets
    if command -v bq &> /dev/null; then
        bq_datasets=$(bq ls --format=prettyjson 2>/dev/null | grep -o '"datasetId": "[^"]*trading_analytics[^"]*"' | cut -d'"' -f4 || echo "")
        if [[ -n "${bq_datasets}" ]]; then
            log "Found BigQuery datasets: ${bq_datasets}"
            BQ_DATASETS="${bq_datasets}"
        else
            debug "No BigQuery datasets found"
            BQ_DATASETS=""
        fi
    else
        warn "BigQuery CLI not available - skipping dataset detection"
        BQ_DATASETS=""
    fi
    
    # Detect Cloud Storage buckets
    local storage_buckets
    if command -v gsutil &> /dev/null; then
        storage_buckets=$(gsutil ls -p "${PROJECT_ID}" 2>/dev/null | grep "hft-risk-data" | sed 's|gs://||g' | sed 's|/||g' || echo "")
        if [[ -n "${storage_buckets}" ]]; then
            log "Found storage buckets: ${storage_buckets}"
            STORAGE_BUCKETS="${storage_buckets}"
        else
            debug "No storage buckets found"
            STORAGE_BUCKETS=""
        fi
    else
        warn "gsutil not available - skipping bucket detection"
        STORAGE_BUCKETS=""
    fi
    
    # Detect Datastream resources
    local datastream_streams
    datastream_streams=$(gcloud datastream streams list --location="${REGION}" --filter="name~trading-data-stream" --format="value(name)" 2>/dev/null || echo "")
    if [[ -n "${datastream_streams}" ]]; then
        log "Found Datastream streams: ${datastream_streams}"
        DATASTREAM_STREAMS="${datastream_streams}"
    else
        debug "No Datastream streams found"
        DATASTREAM_STREAMS=""
    fi
    
    # Detect container images
    local container_images
    container_images=$(gcloud container images list --repository="gcr.io/${PROJECT_ID}" --filter="name~risk-analytics-api" --format="value(name)" 2>/dev/null || echo "")
    if [[ -n "${container_images}" ]]; then
        log "Found container images: ${container_images}"
        CONTAINER_IMAGES="${container_images}"
    else
        debug "No container images found"
        CONTAINER_IMAGES=""
    fi
    
    log "✅ Resource detection completed"
}

# Set environment variables
set_environment() {
    log "Setting up environment variables..."
    
    # Set default values
    PROJECT_ID="${PROJECT_ID:-$(gcloud config get-value project 2>/dev/null || echo "")}"
    REGION="${REGION:-us-central1}"
    ZONE="${ZONE:-us-central1-a}"
    
    if [[ -z "${PROJECT_ID}" ]]; then
        error "No project ID specified and no default project configured"
        error "Use -p PROJECT_ID or run: gcloud config set project PROJECT_ID"
        exit 1
    fi
    
    export PROJECT_ID
    export REGION
    export ZONE
    export DATASET_ID="trading_analytics"
    export DATASTREAM_NAME="trading-data-stream"
    
    debug "PROJECT_ID: ${PROJECT_ID}"
    debug "REGION: ${REGION}"
    debug "ZONE: ${ZONE}"
    
    log "✅ Environment variables configured"
}

# Delete TPU instances
delete_tpu_instances() {
    if [[ -z "${TPU_INSTANCES}" ]]; then
        log "No TPU instances to delete"
        return 0
    fi
    
    log "Deleting TPU Ironwood instances..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log "[DRY RUN] Would delete TPU instances: ${TPU_INSTANCES}"
        return 0
    fi
    
    for tpu_name in ${TPU_INSTANCES}; do
        log "Deleting TPU instance: ${tpu_name}"
        
        # Check TPU state before deletion
        local tpu_state
        tpu_state=$(gcloud compute tpus tpu-vm describe "${tpu_name}" --zone="${ZONE}" --format="value(state)" 2>/dev/null || echo "NOT_FOUND")
        
        if [[ "${tpu_state}" == "NOT_FOUND" ]]; then
            warn "TPU ${tpu_name} not found - may already be deleted"
            continue
        fi
        
        # Delete TPU instance
        if gcloud compute tpus tpu-vm delete "${tpu_name}" --zone="${ZONE}" --quiet; then
            log "✅ Deleted TPU instance: ${tpu_name}"
        else
            error "Failed to delete TPU instance: ${tpu_name}"
        fi
        
        # Wait for deletion to complete
        log "Waiting for TPU deletion to complete..."
        local max_attempts=20
        local attempt=1
        
        while [[ $attempt -le $max_attempts ]]; do
            if ! gcloud compute tpus tpu-vm describe "${tpu_name}" --zone="${ZONE}" &> /dev/null; then
                log "TPU ${tpu_name} deletion confirmed"
                break
            fi
            
            debug "TPU still exists, attempt ${attempt}/${max_attempts}"
            sleep 15
            ((attempt++))
        done
        
        if [[ $attempt -gt $max_attempts ]]; then
            warn "TPU ${tpu_name} deletion timed out - may still exist"
        fi
    done
    
    log "✅ TPU instances cleanup completed"
}

# Delete Cloud Run services
delete_cloud_run_services() {
    if [[ -z "${CLOUD_RUN_SERVICES}" ]]; then
        log "No Cloud Run services to delete"
        return 0
    fi
    
    log "Deleting Cloud Run services..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log "[DRY RUN] Would delete Cloud Run services: ${CLOUD_RUN_SERVICES}"
        return 0
    fi
    
    for service_name in ${CLOUD_RUN_SERVICES}; do
        log "Deleting Cloud Run service: ${service_name}"
        
        if gcloud run services delete "${service_name}" --region="${REGION}" --quiet; then
            log "✅ Deleted Cloud Run service: ${service_name}"
        else
            error "Failed to delete Cloud Run service: ${service_name}"
        fi
    done
    
    log "✅ Cloud Run services cleanup completed"
}

# Delete container images
delete_container_images() {
    if [[ -z "${CONTAINER_IMAGES}" ]]; then
        log "No container images to delete"
        return 0
    fi
    
    log "Deleting container images..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log "[DRY RUN] Would delete container images: ${CONTAINER_IMAGES}"
        return 0
    fi
    
    for image_name in ${CONTAINER_IMAGES}; do
        log "Deleting container image: ${image_name}"
        
        # Get all tags for this image
        local image_tags
        image_tags=$(gcloud container images list-tags "${image_name}" --format="value(tags)" 2>/dev/null || echo "")
        
        if [[ -n "${image_tags}" ]]; then
            for tag in ${image_tags}; do
                if [[ "${tag}" != "null" ]] && [[ -n "${tag}" ]]; then
                    log "Deleting image tag: ${image_name}:${tag}"
                    gcloud container images delete "${image_name}:${tag}" --quiet || warn "Failed to delete ${image_name}:${tag}"
                fi
            done
        fi
        
        # Delete untagged images
        local untagged_images
        untagged_images=$(gcloud container images list-tags "${image_name}" --filter='-tags:*' --format="value(digest)" 2>/dev/null || echo "")
        
        for digest in ${untagged_images}; do
            if [[ -n "${digest}" ]]; then
                log "Deleting untagged image: ${image_name}@${digest}"
                gcloud container images delete "${image_name}@${digest}" --quiet || warn "Failed to delete ${image_name}@${digest}"
            fi
        done
    done
    
    log "✅ Container images cleanup completed"
}

# Delete Datastream resources
delete_datastream_resources() {
    if [[ -z "${DATASTREAM_STREAMS}" ]]; then
        log "No Datastream resources to delete"
        return 0
    fi
    
    log "Deleting Datastream resources..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log "[DRY RUN] Would delete Datastream streams: ${DATASTREAM_STREAMS}"
        return 0
    fi
    
    for stream_name in ${DATASTREAM_STREAMS}; do
        log "Deleting Datastream stream: ${stream_name}"
        
        # Stop stream first if running
        local stream_state
        stream_state=$(gcloud datastream streams describe "${stream_name}" --location="${REGION}" --format="value(state)" 2>/dev/null || echo "NOT_FOUND")
        
        if [[ "${stream_state}" == "RUNNING" ]]; then
            log "Stopping Datastream stream: ${stream_name}"
            gcloud datastream streams stop "${stream_name}" --location="${REGION}" --quiet || warn "Failed to stop stream"
            
            # Wait for stream to stop
            sleep 30
        fi
        
        # Delete stream
        if gcloud datastream streams delete "${stream_name}" --location="${REGION}" --quiet; then
            log "✅ Deleted Datastream stream: ${stream_name}"
        else
            error "Failed to delete Datastream stream: ${stream_name}"
        fi
    done
    
    # Delete connection profiles
    local connection_profiles
    connection_profiles=$(gcloud datastream connection-profiles list --location="${REGION}" --filter="name~trading-data-stream" --format="value(name)" 2>/dev/null || echo "")
    
    for profile_name in ${connection_profiles}; do
        log "Deleting connection profile: ${profile_name}"
        gcloud datastream connection-profiles delete "${profile_name}" --location="${REGION}" --quiet || warn "Failed to delete connection profile"
    done
    
    log "✅ Datastream resources cleanup completed"
}

# Delete BigQuery datasets
delete_bigquery_datasets() {
    if [[ -z "${BQ_DATASETS}" ]] || ! command -v bq &> /dev/null; then
        log "No BigQuery datasets to delete or bq CLI not available"
        return 0
    fi
    
    log "Deleting BigQuery datasets..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log "[DRY RUN] Would delete BigQuery datasets: ${BQ_DATASETS}"
        return 0
    fi
    
    for dataset_name in ${BQ_DATASETS}; do
        log "Deleting BigQuery dataset: ${dataset_name}"
        
        # List tables in dataset for logging
        local tables
        tables=$(bq ls "${PROJECT_ID}:${dataset_name}" --format=prettyjson 2>/dev/null | grep -o '"tableId": "[^"]*"' | cut -d'"' -f4 || echo "")
        
        if [[ -n "${tables}" ]]; then
            log "Dataset contains tables: ${tables}"
        fi
        
        # Delete dataset and all tables
        if bq rm -r -f "${PROJECT_ID}:${dataset_name}"; then
            log "✅ Deleted BigQuery dataset: ${dataset_name}"
        else
            error "Failed to delete BigQuery dataset: ${dataset_name}"
        fi
    done
    
    log "✅ BigQuery datasets cleanup completed"
}

# Delete Cloud Storage buckets
delete_storage_buckets() {
    if [[ -z "${STORAGE_BUCKETS}" ]] || ! command -v gsutil &> /dev/null; then
        log "No storage buckets to delete or gsutil not available"
        return 0
    fi
    
    log "Deleting Cloud Storage buckets..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log "[DRY RUN] Would delete storage buckets: ${STORAGE_BUCKETS}"
        return 0
    fi
    
    for bucket_name in ${STORAGE_BUCKETS}; do
        log "Deleting storage bucket: gs://${bucket_name}"
        
        # Check if bucket exists
        if ! gsutil ls -b "gs://${bucket_name}" &> /dev/null; then
            warn "Bucket gs://${bucket_name} not found - may already be deleted"
            continue
        fi
        
        # Get bucket size for logging
        local bucket_size
        bucket_size=$(gsutil du -s "gs://${bucket_name}" 2>/dev/null | awk '{print $1}' || echo "unknown")
        log "Bucket size: ${bucket_size} bytes"
        
        # Delete all objects in bucket
        log "Removing all objects from bucket..."
        if gsutil -m rm -r "gs://${bucket_name}/**" &> /dev/null; then
            log "All objects removed from bucket"
        else
            debug "No objects found in bucket or removal failed"
        fi
        
        # Delete bucket
        if gsutil rb "gs://${bucket_name}"; then
            log "✅ Deleted storage bucket: gs://${bucket_name}"
        else
            error "Failed to delete storage bucket: gs://${bucket_name}"
        fi
    done
    
    log "✅ Storage buckets cleanup completed"
}

# Delete monitoring resources
delete_monitoring_resources() {
    log "Deleting monitoring resources..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log "[DRY RUN] Would delete monitoring resources"
        return 0
    fi
    
    # Delete log-based metrics
    local log_metrics=("trading_error_rate" "tpu_inference_latency")
    
    for metric_name in "${log_metrics[@]}"; do
        log "Deleting log metric: ${metric_name}"
        if gcloud logging metrics delete "${metric_name}" --quiet 2>/dev/null; then
            log "✅ Deleted log metric: ${metric_name}"
        else
            debug "Log metric ${metric_name} not found or already deleted"
        fi
    done
    
    # Delete custom dashboards (if any exist)
    local dashboards
    dashboards=$(gcloud monitoring dashboards list --filter="displayName~'HFT Risk Analytics'" --format="value(name)" 2>/dev/null || echo "")
    
    for dashboard in ${dashboards}; do
        log "Deleting monitoring dashboard: ${dashboard}"
        if gcloud monitoring dashboards delete "${dashboard}" --quiet; then
            log "✅ Deleted monitoring dashboard"
        else
            warn "Failed to delete monitoring dashboard"
        fi
    done
    
    log "✅ Monitoring resources cleanup completed"
}

# Delete entire project
delete_project() {
    if [[ "${DELETE_PROJECT}" != "true" ]]; then
        return 0
    fi
    
    log "Preparing to delete entire project: ${PROJECT_ID}"
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log "[DRY RUN] Would delete project: ${PROJECT_ID}"
        return 0
    fi
    
    # Final safety check
    if [[ "${FORCE_DELETE}" != "true" ]]; then
        echo ""
        echo -e "${RED}⚠️  DESTRUCTIVE OPERATION WARNING ⚠️${NC}"
        echo ""
        echo "This will PERMANENTLY DELETE the entire project and ALL data:"
        echo "  Project: ${PROJECT_ID}"
        echo "  All resources, data, and configurations will be lost"
        echo "  This action CANNOT be undone"
        echo ""
        read -p "Type 'DELETE' in capital letters to confirm: " -r
        echo ""
        
        if [[ "$REPLY" != "DELETE" ]]; then
            log "Project deletion cancelled"
            return 0
        fi
        
        read -p "Are you absolutely sure? Type 'YES' to proceed: " -r
        echo ""
        
        if [[ "$REPLY" != "YES" ]]; then
            log "Project deletion cancelled"
            return 0
        fi
    fi
    
    # Check for active billing
    local billing_account
    billing_account=$(gcloud billing projects describe "${PROJECT_ID}" --format="value(billingAccountName)" 2>/dev/null || echo "")
    
    if [[ -n "${billing_account}" ]]; then
        log "Unlinking billing account: ${billing_account}"
        gcloud billing projects unlink "${PROJECT_ID}" --quiet || warn "Failed to unlink billing"
    fi
    
    # Delete project
    log "Deleting project: ${PROJECT_ID}"
    if gcloud projects delete "${PROJECT_ID}" --quiet; then
        log "✅ Project deletion initiated: ${PROJECT_ID}"
        log "Note: Project deletion may take several minutes to complete"
    else
        error "Failed to delete project: ${PROJECT_ID}"
    fi
}

# Verify cleanup completion
verify_cleanup() {
    if [[ "${DRY_RUN}" == "true" ]] || [[ "${DELETE_PROJECT}" == "true" ]]; then
        return 0
    fi
    
    log "Verifying cleanup completion..."
    
    # Re-detect resources to confirm deletion
    local remaining_resources=0
    
    # Check TPU instances
    local remaining_tpus
    remaining_tpus=$(gcloud compute tpus tpu-vm list --zone="${ZONE}" --filter="name~ironwood-risk-tpu" --format="value(name)" 2>/dev/null || echo "")
    if [[ -n "${remaining_tpus}" ]]; then
        warn "Remaining TPU instances: ${remaining_tpus}"
        ((remaining_resources++))
    fi
    
    # Check Cloud Run services
    local remaining_services
    remaining_services=$(gcloud run services list --region="${REGION}" --filter="metadata.name~risk-analytics-api" --format="value(metadata.name)" 2>/dev/null || echo "")
    if [[ -n "${remaining_services}" ]]; then
        warn "Remaining Cloud Run services: ${remaining_services}"
        ((remaining_resources++))
    fi
    
    # Check storage buckets
    if command -v gsutil &> /dev/null; then
        local remaining_buckets
        remaining_buckets=$(gsutil ls -p "${PROJECT_ID}" 2>/dev/null | grep "hft-risk-data" || echo "")
        if [[ -n "${remaining_buckets}" ]]; then
            warn "Remaining storage buckets: ${remaining_buckets}"
            ((remaining_resources++))
        fi
    fi
    
    if [[ $remaining_resources -eq 0 ]]; then
        log "✅ Cleanup verification successful - no remaining resources found"
    else
        warn "⚠️ Cleanup verification found ${remaining_resources} remaining resource types"
        warn "Some resources may still exist and incur charges"
        warn "Check the Google Cloud Console for manual cleanup: https://console.cloud.google.com/home/dashboard?project=${PROJECT_ID}"
    fi
}

# Display cleanup summary
display_summary() {
    log "=== CLEANUP SUMMARY ==="
    log "Project: ${PROJECT_ID}"
    log "Region: ${REGION}"
    log "Zone: ${ZONE}"
    log ""
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log "DRY RUN RESULTS:"
        log "The following resources would be deleted:"
    else
        log "DELETED RESOURCES:"
    fi
    
    # Show what was found and processed
    if [[ -n "${TPU_INSTANCES}" ]]; then
        log "  • TPU Instances: ${TPU_INSTANCES}"
    fi
    
    if [[ -n "${CLOUD_RUN_SERVICES}" ]]; then
        log "  • Cloud Run Services: ${CLOUD_RUN_SERVICES}"
    fi
    
    if [[ -n "${BQ_DATASETS}" ]]; then
        log "  • BigQuery Datasets: ${BQ_DATASETS}"
    fi
    
    if [[ -n "${STORAGE_BUCKETS}" ]]; then
        log "  • Storage Buckets: ${STORAGE_BUCKETS}"
    fi
    
    if [[ -n "${DATASTREAM_STREAMS}" ]]; then
        log "  • Datastream Streams: ${DATASTREAM_STREAMS}"
    fi
    
    if [[ -n "${CONTAINER_IMAGES}" ]]; then
        log "  • Container Images: ${CONTAINER_IMAGES}"
    fi
    
    if [[ "${DELETE_PROJECT}" == "true" ]]; then
        log "  • Entire Project: ${PROJECT_ID}"
    fi
    
    log ""
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log "To perform actual cleanup, run without --dry-run flag"
    elif [[ "${DELETE_PROJECT}" == "true" ]]; then
        log "Project deletion initiated - all resources will be removed"
    else
        log "Cleanup completed successfully!"
        log "Monitor billing to ensure all charges have stopped"
    fi
    
    log ""
    log "Log file: ${LOG_FILE}"
}

# Confirmation prompt
confirm_cleanup() {
    if [[ "${SKIP_CONFIRMATION}" == "true" ]] || [[ "${DRY_RUN}" == "true" ]]; then
        return 0
    fi
    
    echo ""
    echo -e "${YELLOW}⚠️  RESOURCE DELETION CONFIRMATION ⚠️${NC}"
    echo ""
    echo "This will delete the following infrastructure:"
    
    if [[ -n "${TPU_INSTANCES}" ]]; then
        echo "  • TPU Ironwood instances (expensive resources)"
    fi
    
    if [[ -n "${CLOUD_RUN_SERVICES}" ]]; then
        echo "  • Cloud Run services and container images"
    fi
    
    if [[ -n "${BQ_DATASETS}" ]]; then
        echo "  • BigQuery datasets and all data"
    fi
    
    if [[ -n "${STORAGE_BUCKETS}" ]]; then
        echo "  • Cloud Storage buckets and all data"
    fi
    
    if [[ -n "${DATASTREAM_STREAMS}" ]]; then
        echo "  • Datastream pipelines and configurations"
    fi
    
    echo ""
    echo "Project: ${PROJECT_ID}"
    
    if [[ "${DELETE_PROJECT}" == "true" ]]; then
        echo ""
        echo -e "${RED}ENTIRE PROJECT WILL BE DELETED${NC}"
        echo "This action cannot be undone!"
    fi
    
    echo ""
    read -p "Do you want to proceed with cleanup? (yes/no): " -r
    echo ""
    
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        log "Cleanup cancelled by user"
        exit 0
    fi
}

# Main cleanup function
main() {
    log "Starting High-Frequency Trading Risk Analytics cleanup"
    log "Script: $0"
    log "Arguments: $*"
    log "Log file: ${LOG_FILE}"
    
    # Parse arguments
    parse_args "$@"
    
    # Check prerequisites
    check_prerequisites
    
    # Set environment variables
    set_environment
    
    # Detect existing resources
    detect_resources
    
    # Show confirmation prompt
    confirm_cleanup
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log "=== DRY RUN MODE ==="
        log "This is a dry run. No resources will be deleted."
        log ""
    fi
    
    # Execute cleanup steps in safe order
    delete_cloud_run_services
    delete_container_images
    delete_datastream_resources
    delete_tpu_instances
    delete_bigquery_datasets
    delete_storage_buckets
    delete_monitoring_resources
    delete_project
    
    # Verify cleanup
    verify_cleanup
    
    # Display summary
    display_summary
}

# Run main function
main "$@"