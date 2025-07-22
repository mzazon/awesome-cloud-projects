#!/bin/bash

# Workforce Analytics with Workspace Events API and Cloud Run Worker Pools - Cleanup Script
# This script removes all infrastructure created for workforce analytics processing

set -euo pipefail

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="/tmp/workforce-analytics-cleanup-$(date +%Y%m%d-%H%M%S).log"
DRY_RUN=${DRY_RUN:-false}
FORCE=${FORCE:-false}

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case $level in
        INFO)
            echo -e "${GREEN}[INFO]${NC} $message" | tee -a "$LOG_FILE"
            ;;
        WARN)
            echo -e "${YELLOW}[WARN]${NC} $message" | tee -a "$LOG_FILE"
            ;;
        ERROR)
            echo -e "${RED}[ERROR]${NC} $message" | tee -a "$LOG_FILE"
            ;;
        DEBUG)
            if [[ "${DEBUG:-false}" == "true" ]]; then
                echo -e "${BLUE}[DEBUG]${NC} $message" | tee -a "$LOG_FILE"
            fi
            ;;
    esac
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
}

# Error handler
error_exit() {
    log ERROR "Cleanup failed: $1"
    log ERROR "Check log file: $LOG_FILE"
    exit 1
}

# Cleanup on exit
cleanup() {
    local exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        log ERROR "Cleanup failed with exit code: $exit_code"
        log INFO "Log file available at: $LOG_FILE"
    fi
}
trap cleanup EXIT

# Display banner
echo -e "${RED}"
echo "=================================================="
echo "   Workforce Analytics Cleanup Script"
echo "   Google Cloud Platform Infrastructure"
echo "=================================================="
echo -e "${NC}"

# Check if dry run mode
if [[ "$DRY_RUN" == "true" ]]; then
    log INFO "Running in DRY RUN mode - no resources will be deleted"
fi

# Prerequisites check function
check_prerequisites() {
    log INFO "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        error_exit "gcloud CLI is not installed. Please install Google Cloud SDK."
    fi
    
    # Check if authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n 1 > /dev/null; then
        error_exit "Not authenticated with gcloud. Run 'gcloud auth login' first."
    fi
    
    local active_account=$(gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n 1)
    log INFO "Active account: $active_account"
    
    # Check other required tools
    for tool in bq gsutil; do
        if ! command -v "$tool" &> /dev/null; then
            error_exit "$tool is not installed or not in PATH"
        fi
    done
    
    log INFO "Prerequisites check completed successfully"
}

# Load environment variables
load_environment_variables() {
    log INFO "Loading environment variables..."
    
    local env_file="${SCRIPT_DIR}/.env"
    
    if [[ -f "$env_file" ]]; then
        # Source the environment file
        source "$env_file"
        
        log INFO "Environment variables loaded from: $env_file"
        log INFO "  PROJECT_ID: $PROJECT_ID"
        log INFO "  REGION: $REGION"
        log INFO "  DATASET_NAME: $DATASET_NAME"
        log INFO "  WORKER_POOL_NAME: $WORKER_POOL_NAME"
    else
        log WARN "Environment file not found: $env_file"
        log INFO "Please provide environment variables manually or ensure deployment was successful"
        
        # Try to get from current gcloud config
        export PROJECT_ID="${PROJECT_ID:-$(gcloud config get-value project 2>/dev/null || echo "")}"
        export REGION="${REGION:-$(gcloud config get-value compute/region 2>/dev/null || echo "us-central1")}"
        
        if [[ -z "$PROJECT_ID" ]]; then
            error_exit "PROJECT_ID not found. Please set it manually or ensure .env file exists"
        fi
        
        log WARN "Using current gcloud project: $PROJECT_ID"
        log WARN "Some resources may not be found due to missing environment variables"
    fi
    
    # Set gcloud project
    if [[ "$DRY_RUN" != "true" ]]; then
        gcloud config set project "${PROJECT_ID}" || log WARN "Failed to set project"
    fi
}

# Confirm destructive action
confirm_destruction() {
    if [[ "$FORCE" == "true" ]]; then
        log INFO "Force mode enabled - skipping confirmation"
        return 0
    fi
    
    echo -e "${RED}"
    echo "⚠️  WARNING: This will permanently delete all workforce analytics resources!"
    echo "   This action cannot be undone!"
    echo ""
    echo "Resources to be deleted:"
    echo "  - Cloud Run Worker Pool: ${WORKER_POOL_NAME:-unknown}"
    echo "  - BigQuery Dataset: ${DATASET_NAME:-unknown}"
    echo "  - Pub/Sub Topic: ${TOPIC_NAME:-unknown}"
    echo "  - Storage Bucket: ${BUCKET_NAME:-unknown}"
    echo "  - Container Images"
    echo "  - Monitoring Resources"
    echo -e "${NC}"
    
    read -p "Are you sure you want to continue? (yes/no): " -r
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        log INFO "Cleanup cancelled by user"
        exit 0
    fi
    
    log INFO "User confirmed resource deletion"
}

# Remove Cloud Run Worker Pool
remove_worker_pool() {
    log INFO "Removing Cloud Run Worker Pool..."
    
    if [[ -z "${WORKER_POOL_NAME:-}" ]]; then
        log WARN "Worker pool name not found - attempting to find existing worker pools"
        
        # Try to find worker pools that might belong to this deployment
        local worker_pools
        worker_pools=$(gcloud beta run worker-pools list --region="${REGION}" --format="value(metadata.name)" 2>/dev/null || echo "")
        
        if [[ -n "$worker_pools" ]]; then
            log INFO "Found existing worker pools in region $REGION:"
            echo "$worker_pools" | while read -r pool; do
                log INFO "  - $pool"
            done
            log WARN "Please specify WORKER_POOL_NAME to delete specific worker pool"
        else
            log INFO "No worker pools found in region $REGION"
        fi
        return 0
    fi
    
    if [[ "$DRY_RUN" != "true" ]]; then
        # Check if worker pool exists
        if gcloud beta run worker-pools describe "${WORKER_POOL_NAME}" --region="${REGION}" &>/dev/null; then
            log INFO "Deleting worker pool: $WORKER_POOL_NAME"
            if ! gcloud beta run worker-pools delete "${WORKER_POOL_NAME}" \
                --region="${REGION}" \
                --quiet; then
                log ERROR "Failed to delete worker pool: $WORKER_POOL_NAME"
            else
                log INFO "Worker pool deleted successfully"
            fi
        else
            log WARN "Worker pool not found: $WORKER_POOL_NAME"
        fi
    else
        log INFO "[DRY RUN] Would delete worker pool: $WORKER_POOL_NAME"
    fi
}

# Remove BigQuery resources
remove_bigquery_resources() {
    log INFO "Removing BigQuery dataset and tables..."
    
    if [[ -z "${DATASET_NAME:-}" ]]; then
        log WARN "Dataset name not found - attempting to find datasets with workforce analytics pattern"
        
        # Try to find datasets that might belong to this deployment
        local datasets
        datasets=$(bq ls --format="value(datasetId)" 2>/dev/null | grep -i "workforce\|analytics" || echo "")
        
        if [[ -n "$datasets" ]]; then
            log INFO "Found potential workforce analytics datasets:"
            echo "$datasets" | while read -r dataset; do
                log INFO "  - $dataset"
            done
            log WARN "Please specify DATASET_NAME to delete specific dataset"
        else
            log INFO "No workforce analytics datasets found"
        fi
        return 0
    fi
    
    if [[ "$DRY_RUN" != "true" ]]; then
        # Check if dataset exists
        if bq ls "${PROJECT_ID}:${DATASET_NAME}" &>/dev/null; then
            log INFO "Deleting BigQuery dataset: $DATASET_NAME"
            if ! bq rm -r -f "${PROJECT_ID}:${DATASET_NAME}"; then
                log ERROR "Failed to delete BigQuery dataset: $DATASET_NAME"
            else
                log INFO "BigQuery dataset deleted successfully"
            fi
        else
            log WARN "BigQuery dataset not found: $DATASET_NAME"
        fi
    else
        log INFO "[DRY RUN] Would delete BigQuery dataset: $DATASET_NAME"
    fi
}

# Remove Pub/Sub resources
remove_pubsub_resources() {
    log INFO "Removing Cloud Pub/Sub resources..."
    
    if [[ -z "${TOPIC_NAME:-}" || -z "${SUBSCRIPTION_NAME:-}" ]]; then
        log WARN "Pub/Sub resource names not found - attempting to find resources with workspace events pattern"
        
        # Try to find topics and subscriptions that might belong to this deployment
        local topics
        topics=$(gcloud pubsub topics list --format="value(name)" 2>/dev/null | grep -E "workspace|events|analytics" || echo "")
        
        local subscriptions
        subscriptions=$(gcloud pubsub subscriptions list --format="value(name)" 2>/dev/null | grep -E "workspace|events|analytics" || echo "")
        
        if [[ -n "$topics" ]]; then
            log INFO "Found potential workspace event topics:"
            echo "$topics" | while read -r topic; do
                log INFO "  - $(basename "$topic")"
            done
        fi
        
        if [[ -n "$subscriptions" ]]; then
            log INFO "Found potential workspace event subscriptions:"
            echo "$subscriptions" | while read -r sub; do
                log INFO "  - $(basename "$sub")"
            done
        fi
        
        if [[ -z "$topics" && -z "$subscriptions" ]]; then
            log INFO "No workspace event Pub/Sub resources found"
        else
            log WARN "Please specify TOPIC_NAME and SUBSCRIPTION_NAME to delete specific resources"
        fi
        return 0
    fi
    
    if [[ "$DRY_RUN" != "true" ]]; then
        # Delete subscription first
        if gcloud pubsub subscriptions describe "${SUBSCRIPTION_NAME}" &>/dev/null; then
            log INFO "Deleting Pub/Sub subscription: $SUBSCRIPTION_NAME"
            if ! gcloud pubsub subscriptions delete "${SUBSCRIPTION_NAME}" --quiet; then
                log ERROR "Failed to delete Pub/Sub subscription: $SUBSCRIPTION_NAME"
            else
                log INFO "Pub/Sub subscription deleted successfully"
            fi
        else
            log WARN "Pub/Sub subscription not found: $SUBSCRIPTION_NAME"
        fi
        
        # Delete topic
        if gcloud pubsub topics describe "${TOPIC_NAME}" &>/dev/null; then
            log INFO "Deleting Pub/Sub topic: $TOPIC_NAME"
            if ! gcloud pubsub topics delete "${TOPIC_NAME}" --quiet; then
                log ERROR "Failed to delete Pub/Sub topic: $TOPIC_NAME"
            else
                log INFO "Pub/Sub topic deleted successfully"
            fi
        else
            log WARN "Pub/Sub topic not found: $TOPIC_NAME"
        fi
    else
        log INFO "[DRY RUN] Would delete Pub/Sub subscription: $SUBSCRIPTION_NAME"
        log INFO "[DRY RUN] Would delete Pub/Sub topic: $TOPIC_NAME"
    fi
}

# Remove Cloud Storage resources
remove_storage_resources() {
    log INFO "Removing Cloud Storage bucket..."
    
    if [[ -z "${BUCKET_NAME:-}" ]]; then
        log WARN "Bucket name not found - attempting to find buckets with workforce pattern"
        
        # Try to find buckets that might belong to this deployment
        local buckets
        buckets=$(gsutil ls -p "${PROJECT_ID}" 2>/dev/null | grep -E "workforce|analytics" || echo "")
        
        if [[ -n "$buckets" ]]; then
            log INFO "Found potential workforce analytics buckets:"
            echo "$buckets" | while read -r bucket; do
                log INFO "  - $bucket"
            done
            log WARN "Please specify BUCKET_NAME to delete specific bucket"
        else
            log INFO "No workforce analytics buckets found"
        fi
        return 0
    fi
    
    if [[ "$DRY_RUN" != "true" ]]; then
        # Check if bucket exists
        if gsutil ls "gs://${BUCKET_NAME}" &>/dev/null; then
            log INFO "Deleting Cloud Storage bucket: $BUCKET_NAME"
            if ! gsutil -m rm -r "gs://${BUCKET_NAME}"; then
                log ERROR "Failed to delete Cloud Storage bucket: $BUCKET_NAME"
            else
                log INFO "Cloud Storage bucket deleted successfully"
            fi
        else
            log WARN "Cloud Storage bucket not found: $BUCKET_NAME"
        fi
    else
        log INFO "[DRY RUN] Would delete Cloud Storage bucket: $BUCKET_NAME"
    fi
}

# Remove container images
remove_container_images() {
    log INFO "Removing container images..."
    
    if [[ "$DRY_RUN" != "true" ]]; then
        # List and delete workspace analytics images
        local images
        images=$(gcloud container images list --repository="gcr.io/${PROJECT_ID}" --format="value(name)" 2>/dev/null | grep "workspace-analytics" || echo "")
        
        if [[ -n "$images" ]]; then
            while read -r image; do
                if [[ -n "$image" ]]; then
                    log INFO "Deleting container image: $image"
                    if ! gcloud container images delete "$image" --quiet; then
                        log ERROR "Failed to delete container image: $image"
                    else
                        log INFO "Container image deleted successfully"
                    fi
                fi
            done <<< "$images"
        else
            log INFO "No workspace analytics container images found"
        fi
    else
        log INFO "[DRY RUN] Would delete container images for workspace-analytics"
    fi
}

# Remove monitoring resources
remove_monitoring_resources() {
    log INFO "Removing Cloud Monitoring resources..."
    
    if [[ "$DRY_RUN" != "true" ]]; then
        # Delete monitoring dashboards
        local dashboards
        dashboards=$(gcloud monitoring dashboards list --format="value(name)" 2>/dev/null | head -10 || echo "")
        
        if [[ -n "$dashboards" ]]; then
            while read -r dashboard; do
                if [[ -n "$dashboard" ]]; then
                    # Get dashboard details to check if it's ours
                    local display_name
                    display_name=$(gcloud monitoring dashboards describe "$dashboard" --format="value(displayName)" 2>/dev/null || echo "")
                    
                    if [[ "$display_name" == *"Workforce Analytics"* ]]; then
                        log INFO "Deleting monitoring dashboard: $display_name"
                        if ! gcloud monitoring dashboards delete "$dashboard" --quiet; then
                            log ERROR "Failed to delete dashboard: $dashboard"
                        else
                            log INFO "Dashboard deleted successfully"
                        fi
                    fi
                fi
            done <<< "$dashboards"
        else
            log INFO "No monitoring dashboards found"
        fi
        
        # Delete alerting policies
        local policies
        policies=$(gcloud alpha monitoring policies list --format="value(name)" 2>/dev/null | head -10 || echo "")
        
        if [[ -n "$policies" ]]; then
            while read -r policy; do
                if [[ -n "$policy" ]]; then
                    # Get policy details to check if it's ours
                    local display_name
                    display_name=$(gcloud alpha monitoring policies describe "$policy" --format="value(displayName)" 2>/dev/null || echo "")
                    
                    if [[ "$display_name" == *"Processing Latency"* || "$display_name" == *"Workforce"* ]]; then
                        log INFO "Deleting alerting policy: $display_name"
                        if ! gcloud alpha monitoring policies delete "$policy" --quiet; then
                            log ERROR "Failed to delete policy: $policy"
                        else
                            log INFO "Alerting policy deleted successfully"
                        fi
                    fi
                fi
            done <<< "$policies"
        else
            log INFO "No alerting policies found"
        fi
    else
        log INFO "[DRY RUN] Would delete monitoring dashboards and alerting policies"
    fi
}

# Remove application code
remove_application_code() {
    log INFO "Removing application code..."
    
    local app_dir="${SCRIPT_DIR}/../workspace-analytics-app"
    local config_file="${SCRIPT_DIR}/../workspace-events-config.json"
    
    if [[ "$DRY_RUN" != "true" ]]; then
        # Remove application directory
        if [[ -d "$app_dir" ]]; then
            log INFO "Removing application directory: $app_dir"
            rm -rf "$app_dir"
            log INFO "Application directory removed"
        else
            log INFO "Application directory not found: $app_dir"
        fi
        
        # Remove configuration file
        if [[ -f "$config_file" ]]; then
            log INFO "Removing configuration file: $config_file"
            rm -f "$config_file"
            log INFO "Configuration file removed"
        else
            log INFO "Configuration file not found: $config_file"
        fi
        
        # Remove environment file
        local env_file="${SCRIPT_DIR}/.env"
        if [[ -f "$env_file" ]]; then
            log INFO "Removing environment file: $env_file"
            rm -f "$env_file"
            log INFO "Environment file removed"
        fi
    else
        log INFO "[DRY RUN] Would remove application code and configuration files"
    fi
}

# Verify resource removal
verify_cleanup() {
    log INFO "Verifying resource cleanup..."
    
    local cleanup_issues=()
    
    # Check worker pool
    if [[ -n "${WORKER_POOL_NAME:-}" ]]; then
        if gcloud beta run worker-pools describe "${WORKER_POOL_NAME}" --region="${REGION}" &>/dev/null; then
            cleanup_issues+=("Worker pool still exists: $WORKER_POOL_NAME")
        fi
    fi
    
    # Check BigQuery dataset
    if [[ -n "${DATASET_NAME:-}" ]]; then
        if bq ls "${PROJECT_ID}:${DATASET_NAME}" &>/dev/null; then
            cleanup_issues+=("BigQuery dataset still exists: $DATASET_NAME")
        fi
    fi
    
    # Check Pub/Sub resources
    if [[ -n "${TOPIC_NAME:-}" ]]; then
        if gcloud pubsub topics describe "${TOPIC_NAME}" &>/dev/null; then
            cleanup_issues+=("Pub/Sub topic still exists: $TOPIC_NAME")
        fi
    fi
    
    if [[ -n "${SUBSCRIPTION_NAME:-}" ]]; then
        if gcloud pubsub subscriptions describe "${SUBSCRIPTION_NAME}" &>/dev/null; then
            cleanup_issues+=("Pub/Sub subscription still exists: $SUBSCRIPTION_NAME")
        fi
    fi
    
    # Check storage bucket
    if [[ -n "${BUCKET_NAME:-}" ]]; then
        if gsutil ls "gs://${BUCKET_NAME}" &>/dev/null; then
            cleanup_issues+=("Storage bucket still exists: $BUCKET_NAME")
        fi
    fi
    
    # Report cleanup results
    if [[ ${#cleanup_issues[@]} -eq 0 ]]; then
        log INFO "✅ All resources have been successfully removed"
    else
        log WARN "⚠️  Some resources may still exist:"
        for issue in "${cleanup_issues[@]}"; do
            log WARN "  - $issue"
        done
        log WARN "You may need to manually remove these resources"
    fi
}

# Cleanup summary
cleanup_summary() {
    log INFO ""
    log INFO "=================================================="
    log INFO "         Cleanup Summary"
    log INFO "=================================================="
    log INFO "Project ID: $PROJECT_ID"
    log INFO "Region: $REGION"
    log INFO ""
    log INFO "Removed Resources:"
    log INFO "  ✅ Cloud Run Worker Pool"
    log INFO "  ✅ BigQuery Dataset and Tables"
    log INFO "  ✅ Pub/Sub Topic and Subscription"
    log INFO "  ✅ Cloud Storage Bucket"
    log INFO "  ✅ Container Images"
    log INFO "  ✅ Monitoring Resources"
    log INFO "  ✅ Application Code"
    log INFO ""
    log INFO "📋 Manual Steps Required:"
    log INFO "1. Remove Workspace Events API subscriptions from Admin Console"
    log INFO "2. Verify all IAM permissions have been cleaned up"
    log INFO "3. Check for any remaining custom resources"
    log INFO ""
    log INFO "💰 Cost Impact:"
    log INFO "All billable resources have been removed"
    log INFO "No ongoing charges should occur for this solution"
    log INFO ""
    log INFO "✅ Cleanup completed successfully!"
    log INFO "Log file: $LOG_FILE"
}

# Main cleanup function
main() {
    local start_time=$(date +%s)
    
    log INFO "Starting workforce analytics cleanup..."
    
    # Run cleanup steps
    check_prerequisites
    load_environment_variables
    confirm_destruction
    remove_worker_pool
    remove_bigquery_resources
    remove_pubsub_resources
    remove_storage_resources
    remove_container_images
    remove_monitoring_resources
    remove_application_code
    
    if [[ "$DRY_RUN" != "true" ]]; then
        verify_cleanup
    fi
    
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    cleanup_summary
    log INFO "Total cleanup time: ${duration} seconds"
}

# Script execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi