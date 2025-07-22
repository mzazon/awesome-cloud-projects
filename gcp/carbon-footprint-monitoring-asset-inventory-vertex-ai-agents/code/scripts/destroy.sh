#!/bin/bash

# Carbon Footprint Monitoring with Cloud Asset Inventory and Vertex AI Agents
# Cleanup/Destroy Script for GCP Recipe
# Version: 1.0
# Author: Generated for recipes repository

set -euo pipefail  # Exit on any error, undefined variable, or pipe failure

# Color codes for output formatting
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Script configuration
readonly SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_FILE="${SCRIPT_DIR}/destroy.log"
readonly DRY_RUN=${DRY_RUN:-false}

# Cleanup configuration
readonly DEFAULT_REGION="us-central1"

# Initialize logging
exec 1> >(tee -a "${LOG_FILE}")
exec 2> >(tee -a "${LOG_FILE}" >&2)

# Utility functions
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $*${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARN: $*${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $*${NC}"
}

debug() {
    if [[ "${DEBUG:-false}" == "true" ]]; then
        echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] DEBUG: $*${NC}"
    fi
}

# Print usage information
usage() {
    cat << EOF
Usage: ${SCRIPT_NAME} [OPTIONS]

Clean up carbon footprint monitoring infrastructure created by the deployment script.

OPTIONS:
    -p, --project-id PROJECT_ID    Google Cloud project ID (required)
    -r, --region REGION           Deployment region (default: ${DEFAULT_REGION})
    -n, --dry-run                 Show what would be deleted without making changes
    -d, --debug                   Enable debug logging
    -h, --help                    Show this help message
    -f, --force                   Skip confirmation prompts
    --keep-data                   Keep BigQuery datasets and Cloud Storage buckets
    --keep-apis                   Keep enabled APIs (recommended for shared projects)

EXAMPLES:
    ${SCRIPT_NAME} --project-id my-carbon-project
    ${SCRIPT_NAME} --project-id my-project --region europe-west1 --dry-run
    ${SCRIPT_NAME} -p my-project -f --keep-data

ENVIRONMENT VARIABLES:
    GOOGLE_CLOUD_PROJECT          Default project ID if not specified
    DRY_RUN                       Set to 'true' for dry-run mode
    DEBUG                         Set to 'true' for debug logging

WARNING: This script will permanently delete resources and data. 
         Use --dry-run to preview changes before execution.

EOF
}

# Cleanup function for graceful exit
cleanup() {
    local exit_code=$?
    if [[ ${exit_code} -ne 0 ]]; then
        error "Cleanup failed with exit code ${exit_code}"
        error "Check ${LOG_FILE} for details"
    fi
    exit ${exit_code}
}

# Set up signal handlers
trap cleanup EXIT
trap 'error "Cleanup interrupted by user"; exit 130' INT TERM

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if gcloud CLI is installed
    if ! command -v gcloud &> /dev/null; then
        error "gcloud CLI is not installed. Please install it from https://cloud.google.com/sdk/docs/install"
        return 1
    fi
    
    # Check if bq CLI is available
    if ! command -v bq &> /dev/null; then
        error "BigQuery CLI (bq) is not available. Please ensure it's installed with gcloud components"
        return 1
    fi
    
    # Check if gsutil is available
    if ! command -v gsutil &> /dev/null; then
        error "Cloud Storage CLI (gsutil) is not available. Please ensure it's installed with gcloud components"
        return 1
    fi
    
    # Check authentication
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" &> /dev/null; then
        error "No active gcloud authentication found. Please run 'gcloud auth login'"
        return 1
    fi
    
    local active_account
    active_account=$(gcloud auth list --filter=status:ACTIVE --format="value(account)" 2>/dev/null | head -n1)
    log "Authenticated as: ${active_account}"
    
    log "Prerequisites check completed successfully"
}

# Validate project and set configuration
validate_project() {
    local project_id="$1"
    
    log "Validating project: ${project_id}"
    
    # Check if project exists and user has access
    if ! gcloud projects describe "${project_id}" &> /dev/null; then
        error "Project '${project_id}' not found or access denied"
        return 1
    fi
    
    # Set project configuration
    if [[ "${DRY_RUN}" != "true" ]]; then
        gcloud config set project "${project_id}"
        gcloud config set compute/region "${REGION}"
    fi
    
    log "Project validation successful"
}

# Discover existing resources
discover_resources() {
    log "Discovering existing carbon footprint monitoring resources..."
    
    # Find BigQuery datasets
    local datasets
    datasets=$(bq ls --filter="datasetId:carbon*" --format="value(datasetId)" 2>/dev/null || echo "")
    if [[ -n "${datasets}" ]]; then
        log "Found BigQuery datasets: ${datasets}"
        DATASETS_TO_DELETE="${datasets}"
    else
        log "No carbon footprint BigQuery datasets found"
        DATASETS_TO_DELETE=""
    fi
    
    # Find storage buckets
    local buckets
    buckets=$(gsutil ls -p "${PROJECT_ID}" 2>/dev/null | grep "gs://carbon-data-" | sed 's|gs://||g' | sed 's|/||g' || echo "")
    if [[ -n "${buckets}" ]]; then
        log "Found storage buckets: ${buckets}"
        BUCKETS_TO_DELETE="${buckets}"
    else
        log "No carbon footprint storage buckets found"
        BUCKETS_TO_DELETE=""
    fi
    
    # Find Pub/Sub topics
    local topics
    topics=$(gcloud pubsub topics list --filter="name:asset-changes" --format="value(name)" 2>/dev/null || echo "")
    if [[ -n "${topics}" ]]; then
        log "Found Pub/Sub topics: ${topics}"
        TOPICS_TO_DELETE="${topics}"
    else
        log "No carbon footprint Pub/Sub topics found"
        TOPICS_TO_DELETE=""
    fi
    
    # Find asset feeds
    local feeds
    feeds=$(gcloud asset feeds list --project="${PROJECT_ID}" --filter="name:carbon-monitoring" --format="value(name)" 2>/dev/null || echo "")
    if [[ -n "${feeds}" ]]; then
        log "Found asset feeds: ${feeds}"
        FEEDS_TO_DELETE="${feeds}"
    else
        log "No carbon footprint asset feeds found"
        FEEDS_TO_DELETE=""
    fi
    
    log "Resource discovery completed"
}

# Remove monitoring and alerting resources
remove_monitoring() {
    log "Removing monitoring and alerting resources..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log "DRY RUN: Would remove monitoring policies and custom metrics"
        return 0
    fi
    
    # List and delete alerting policies related to carbon monitoring
    local policies
    policies=$(gcloud alpha monitoring policies list --filter="displayName:'High Carbon Emissions Alert'" --format="value(name)" 2>/dev/null || echo "")
    
    for policy in ${policies}; do
        if [[ -n "${policy}" ]]; then
            log "Removing alerting policy: ${policy}"
            gcloud alpha monitoring policies delete "${policy}" --quiet || warn "Failed to delete policy: ${policy}"
        fi
    done
    
    # Remove custom metrics (this may not be possible via CLI, typically requires API calls)
    local metric_type="custom.googleapis.com/carbon/emissions_per_service"
    log "Attempting to remove custom metric: ${metric_type}"
    
    # Try to delete via API
    curl -X DELETE \
        -H "Authorization: Bearer $(gcloud auth print-access-token)" \
        "https://monitoring.googleapis.com/v1/projects/${PROJECT_ID}/metricDescriptors/${metric_type}" 2>/dev/null || warn "Custom metric deletion failed or not found"
    
    log "Monitoring resources cleanup completed"
}

# Remove Vertex AI agent resources
remove_vertex_ai_agent() {
    log "Removing Vertex AI agent resources..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log "DRY RUN: Would remove Vertex AI agents and data stores"
        return 0
    fi
    
    # Note: Vertex AI Agent deletion typically requires Console or alpha commands
    log "Vertex AI agent cleanup:"
    log "  - Manual step required: Delete agents in Vertex AI Agent Builder Console"
    log "  - Look for agents with name pattern: sustainability-advisor*"
    log "  - Delete associated data stores and configurations"
    
    # Try to list and delete agents if alpha commands are available
    local agents
    agents=$(gcloud alpha ai agents list --region="${REGION}" --filter="displayName:sustainability-advisor" --format="value(name)" 2>/dev/null || echo "")
    
    for agent in ${agents}; do
        if [[ -n "${agent}" ]]; then
            log "Found agent to delete: ${agent}"
            # Delete data stores first
            local data_stores
            data_stores=$(gcloud alpha ai agents data-stores list --region="${REGION}" --agent="${agent}" --format="value(name)" 2>/dev/null || echo "")
            for store in ${data_stores}; do
                if [[ -n "${store}" ]]; then
                    log "Deleting data store: ${store}"
                    gcloud alpha ai agents data-stores delete "${store}" --region="${REGION}" --quiet || warn "Failed to delete data store: ${store}"
                fi
            done
            
            # Delete the agent
            log "Deleting agent: ${agent}"
            gcloud alpha ai agents delete "${agent}" --region="${REGION}" --quiet || warn "Failed to delete agent: ${agent}"
        fi
    done
    
    log "Vertex AI agent cleanup completed"
}

# Remove asset inventory feeds
remove_asset_feeds() {
    log "Removing asset inventory feeds..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log "DRY RUN: Would remove asset feeds: ${FEEDS_TO_DELETE}"
        return 0
    fi
    
    if [[ -z "${FEEDS_TO_DELETE}" ]]; then
        log "No asset feeds to remove"
        return 0
    fi
    
    # Parse feed names and delete them
    for feed_path in ${FEEDS_TO_DELETE}; do
        if [[ -n "${feed_path}" ]]; then
            # Extract feed name from full path
            local feed_name
            feed_name=$(basename "${feed_path}")
            log "Removing asset feed: ${feed_name}"
            gcloud asset feeds delete "${feed_name}" --project="${PROJECT_ID}" --quiet || warn "Failed to delete feed: ${feed_name}"
        fi
    done
    
    log "Asset inventory feeds cleanup completed"
}

# Remove Pub/Sub topics
remove_pubsub_topics() {
    log "Removing Pub/Sub topics..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log "DRY RUN: Would remove Pub/Sub topics: ${TOPICS_TO_DELETE}"
        return 0
    fi
    
    if [[ -z "${TOPICS_TO_DELETE}" ]]; then
        log "No Pub/Sub topics to remove"
        return 0
    fi
    
    # Parse topic names and delete them
    for topic_path in ${TOPICS_TO_DELETE}; do
        if [[ -n "${topic_path}" ]]; then
            # Extract topic name from full path
            local topic_name
            topic_name=$(basename "${topic_path}")
            log "Removing Pub/Sub topic: ${topic_name}"
            gcloud pubsub topics delete "${topic_name}" --quiet || warn "Failed to delete topic: ${topic_name}"
        fi
    done
    
    log "Pub/Sub topics cleanup completed"
}

# Remove storage buckets
remove_storage_buckets() {
    log "Removing storage buckets..."
    
    if [[ "${KEEP_DATA}" == "true" ]]; then
        log "Skipping storage bucket deletion (--keep-data specified)"
        return 0
    fi
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log "DRY RUN: Would remove storage buckets: ${BUCKETS_TO_DELETE}"
        return 0
    fi
    
    if [[ -z "${BUCKETS_TO_DELETE}" ]]; then
        log "No storage buckets to remove"
        return 0
    fi
    
    # Delete buckets and their contents
    for bucket in ${BUCKETS_TO_DELETE}; do
        if [[ -n "${bucket}" ]]; then
            log "Removing storage bucket and contents: gs://${bucket}"
            gsutil -m rm -r "gs://${bucket}" || warn "Failed to delete bucket: ${bucket}"
        fi
    done
    
    log "Storage buckets cleanup completed"
}

# Remove BigQuery datasets
remove_bigquery_datasets() {
    log "Removing BigQuery datasets..."
    
    if [[ "${KEEP_DATA}" == "true" ]]; then
        log "Skipping BigQuery dataset deletion (--keep-data specified)"
        return 0
    fi
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log "DRY RUN: Would remove BigQuery datasets: ${DATASETS_TO_DELETE}"
        return 0
    fi
    
    if [[ -z "${DATASETS_TO_DELETE}" ]]; then
        log "No BigQuery datasets to remove"
        return 0
    fi
    
    # Delete datasets and all tables
    for dataset in ${DATASETS_TO_DELETE}; do
        if [[ -n "${dataset}" ]]; then
            log "Removing BigQuery dataset: ${dataset}"
            bq rm -r -f "${PROJECT_ID}:${dataset}" || warn "Failed to delete dataset: ${dataset}"
        fi
    done
    
    log "BigQuery datasets cleanup completed"
}

# Disable APIs (optional)
disable_apis() {
    if [[ "${KEEP_APIS}" == "true" ]]; then
        log "Skipping API disabling (--keep-apis specified)"
        return 0
    fi
    
    log "Disabling APIs..."
    
    local apis_to_disable=(
        "carbonfootprint.googleapis.com"
        "aiplatform.googleapis.com"
    )
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log "DRY RUN: Would disable APIs: ${apis_to_disable[*]}"
        return 0
    fi
    
    warn "Disabling APIs may affect other services in this project"
    
    for api in "${apis_to_disable[@]}"; do
        debug "Checking API: ${api}"
        if gcloud services list --enabled --filter="name:${api}" --format="value(name)" | grep -q "${api}"; then
            log "Disabling API: ${api}"
            gcloud services disable "${api}" --quiet || warn "Failed to disable API: ${api}"
        else
            log "API not enabled: ${api}"
        fi
    done
    
    log "API disabling completed"
}

# Clean up temporary files
cleanup_temp_files() {
    log "Cleaning up temporary files..."
    
    local temp_files=(
        "${SCRIPT_DIR}/agent_instruction.txt"
        "/tmp/lifecycle.json"
        "/tmp/metric_descriptor.json"
        "/tmp/alert_policy.json"
    )
    
    for file in "${temp_files[@]}"; do
        if [[ -f "${file}" ]]; then
            if [[ "${DRY_RUN}" == "true" ]]; then
                log "DRY RUN: Would remove file: ${file}"
            else
                log "Removing temporary file: ${file}"
                rm -f "${file}"
            fi
        fi
    done
    
    log "Temporary files cleanup completed"
}

# Verify cleanup completion
verify_cleanup() {
    log "Verifying cleanup completion..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log "DRY RUN: Skipping cleanup verification"
        return 0
    fi
    
    local remaining_resources=0
    
    # Check for remaining datasets (if not keeping data)
    if [[ "${KEEP_DATA}" != "true" ]]; then
        local remaining_datasets
        remaining_datasets=$(bq ls --filter="datasetId:carbon*" --format="value(datasetId)" 2>/dev/null || echo "")
        if [[ -n "${remaining_datasets}" ]]; then
            warn "Remaining BigQuery datasets found: ${remaining_datasets}"
            ((remaining_resources++))
        fi
        
        # Check for remaining buckets
        local remaining_buckets
        remaining_buckets=$(gsutil ls -p "${PROJECT_ID}" 2>/dev/null | grep "gs://carbon-data-" || echo "")
        if [[ -n "${remaining_buckets}" ]]; then
            warn "Remaining storage buckets found: ${remaining_buckets}"
            ((remaining_resources++))
        fi
    fi
    
    # Check for remaining topics
    local remaining_topics
    remaining_topics=$(gcloud pubsub topics list --filter="name:asset-changes" --format="value(name)" 2>/dev/null || echo "")
    if [[ -n "${remaining_topics}" ]]; then
        warn "Remaining Pub/Sub topics found: ${remaining_topics}"
        ((remaining_resources++))
    fi
    
    # Check for remaining feeds
    local remaining_feeds
    remaining_feeds=$(gcloud asset feeds list --project="${PROJECT_ID}" --filter="name:carbon-monitoring" --format="value(name)" 2>/dev/null || echo "")
    if [[ -n "${remaining_feeds}" ]]; then
        warn "Remaining asset feeds found: ${remaining_feeds}"
        ((remaining_resources++))
    fi
    
    if [[ ${remaining_resources} -eq 0 ]]; then
        log "✓ Cleanup verification successful - no remaining resources found"
    else
        warn "⚠ Cleanup verification found ${remaining_resources} categories with remaining resources"
        warn "Some resources may require manual cleanup or additional permissions"
    fi
}

# Print cleanup summary
print_cleanup_summary() {
    log "Cleanup completed!"
    log ""
    log "Resources cleaned up:"
    
    if [[ "${KEEP_DATA}" != "true" ]]; then
        log "  ✓ BigQuery datasets and tables"
        log "  ✓ Cloud Storage buckets and contents"
    else
        log "  - BigQuery datasets (kept as requested)"
        log "  - Cloud Storage buckets (kept as requested)"
    fi
    
    log "  ✓ Pub/Sub topics"
    log "  ✓ Asset inventory feeds"
    log "  ✓ Monitoring policies and custom metrics"
    log "  ✓ Temporary files"
    
    if [[ "${KEEP_APIS}" != "true" ]]; then
        log "  ✓ Carbon Footprint and AI Platform APIs"
    else
        log "  - APIs (kept as requested)"
    fi
    
    log ""
    log "Manual cleanup still required:"
    log "  - Vertex AI agents in Agent Builder Console"
    log "  - Carbon Footprint export configurations"
    log "  - Custom monitoring dashboards"
    log ""
    log "Log file: ${LOG_FILE}"
}

# Main cleanup function
main() {
    local project_id=""
    local region="${DEFAULT_REGION}"
    local force=false
    local keep_data=false
    local keep_apis=false
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -p|--project-id)
                project_id="$2"
                shift 2
                ;;
            -r|--region)
                region="$2"
                shift 2
                ;;
            -n|--dry-run)
                export DRY_RUN=true
                shift
                ;;
            -d|--debug)
                export DEBUG=true
                shift
                ;;
            -f|--force)
                force=true
                shift
                ;;
            --keep-data)
                keep_data=true
                shift
                ;;
            --keep-apis)
                keep_apis=true
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                error "Unknown argument: $1"
                usage
                exit 1
                ;;
        esac
    done
    
    # Use environment variable if project not specified
    if [[ -z "${project_id}" ]]; then
        project_id="${GOOGLE_CLOUD_PROJECT:-}"
    fi
    
    # Validate required parameters
    if [[ -z "${project_id}" ]]; then
        error "Project ID is required. Use --project-id or set GOOGLE_CLOUD_PROJECT environment variable."
        usage
        exit 1
    fi
    
    # Export variables for use in functions
    export PROJECT_ID="${project_id}"
    export REGION="${region}"
    export KEEP_DATA="${keep_data}"
    export KEEP_APIS="${keep_apis}"
    
    log "Starting carbon footprint monitoring cleanup"
    log "Project: ${PROJECT_ID}"
    log "Region: ${REGION}"
    log "Dry run: ${DRY_RUN}"
    log "Keep data: ${KEEP_DATA}"
    log "Keep APIs: ${KEEP_APIS}"
    log "Log file: ${LOG_FILE}"
    
    # Confirmation prompt (unless forced or dry run)
    if [[ "${force}" != "true" && "${DRY_RUN}" != "true" ]]; then
        echo -e "${RED}WARNING: This will permanently delete carbon footprint monitoring resources in project '${PROJECT_ID}'.${NC}"
        if [[ "${keep_data}" != "true" ]]; then
            echo -e "${RED}This includes BigQuery datasets and Cloud Storage buckets with all data.${NC}"
        fi
        echo -e "${YELLOW}Do you want to continue? (y/N)${NC}"
        read -r response
        if [[ ! "${response}" =~ ^[Yy]$ ]]; then
            log "Cleanup cancelled by user"
            exit 0
        fi
    fi
    
    # Execute cleanup steps
    check_prerequisites
    validate_project "${PROJECT_ID}"
    discover_resources
    remove_monitoring
    remove_vertex_ai_agent
    remove_asset_feeds
    remove_pubsub_topics
    remove_storage_buckets
    remove_bigquery_datasets
    disable_apis
    cleanup_temp_files
    verify_cleanup
    print_cleanup_summary
    
    log "Carbon footprint monitoring cleanup completed successfully!"
}

# Script entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi