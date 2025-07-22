#!/bin/bash

# Real-Time Analytics Dashboards with Datastream and Looker Studio
# Cleanup script for GCP recipe: real-time-analytics-dashboards-datastream-looker-studio
# Recipe ID: 7a8b9c2d

set -euo pipefail

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/destroy.log"
ENV_FILE="${SCRIPT_DIR}/.env"
RECIPE_NAME="real-time-analytics-dashboards-datastream-looker-studio"

# Logging functions
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a "${LOG_FILE}"
}

log_error() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1" | tee -a "${LOG_FILE}" >&2
}

log_success() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] ✅ $1" | tee -a "${LOG_FILE}"
}

log_warning() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️  $1" | tee -a "${LOG_FILE}"
}

# Help function
show_help() {
    cat << EOF
Usage: $0 [OPTIONS]

Clean up real-time analytics dashboards infrastructure

OPTIONS:
    --project-id PROJECT_ID     Google Cloud project ID (required if no .env file)
    --region REGION            GCP region (required if no .env file)
    --force                    Skip confirmation prompts
    --keep-bigquery           Keep BigQuery dataset and data
    --dry-run                 Show what would be deleted without executing
    --help                    Show this help message

EXAMPLES:
    # Normal cleanup (with confirmation)
    $0

    # Force cleanup without prompts
    $0 --force

    # Cleanup but keep BigQuery data
    $0 --keep-bigquery

    # Manual cleanup when .env file is missing
    $0 --project-id my-project --region us-central1 --force

NOTES:
    - This script reads configuration from .env file created during deployment
    - Use --force to skip confirmation prompts (useful for automated cleanup)
    - Use --keep-bigquery to preserve analytics data and views
    - Looker Studio dashboards must be deleted manually

EOF
}

# Default values
FORCE=false
KEEP_BIGQUERY=false
DRY_RUN=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --project-id)
            PROJECT_ID="$2"
            shift 2
            ;;
        --region)
            REGION="$2"
            shift 2
            ;;
        --force)
            FORCE=true
            shift
            ;;
        --keep-bigquery)
            KEEP_BIGQUERY=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --help)
            show_help
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Load environment variables from .env file if it exists
load_environment() {
    if [[ -f "${ENV_FILE}" ]]; then
        log "Loading environment variables from ${ENV_FILE}"
        # shellcheck source=/dev/null
        source "${ENV_FILE}"
        log_success "Environment variables loaded"
    else
        log_warning "Environment file not found: ${ENV_FILE}"
        
        # Check if required variables are provided via command line
        if [[ -z "${PROJECT_ID:-}" ]] || [[ -z "${REGION:-}" ]]; then
            log_error "Missing required parameters. Either provide .env file or use --project-id and --region options."
            show_help
            exit 1
        fi
        
        # Set default values when .env file is missing
        DATASET_NAME="${DATASET_NAME:-ecommerce_analytics}"
        STREAM_NAME="${STREAM_NAME:-sales-stream}"
        CONNECTION_PROFILE_NAME="${CONNECTION_PROFILE_NAME:-source-db-*}"
        BQ_CONNECTION_PROFILE_NAME="${BQ_CONNECTION_PROFILE_NAME:-bigquery-*}"
        
        log_warning "Using default/provided values for cleanup"
    fi
}

# Initialize logging and environment
log "Starting cleanup of ${RECIPE_NAME}"
load_environment

log "Project ID: ${PROJECT_ID}"
log "Region: ${REGION}"
log "Force mode: ${FORCE}"
log "Keep BigQuery: ${KEEP_BIGQUERY}"
log "Dry Run: ${DRY_RUN}"

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "Google Cloud CLI is not installed. Please install it from https://cloud.google.com/sdk/docs/install"
        exit 1
    fi
    
    # Check if bq is installed (only if not keeping BigQuery)
    if [[ "${KEEP_BIGQUERY}" == "false" ]] && ! command -v bq &> /dev/null; then
        log_error "BigQuery CLI is not installed. Please install Google Cloud SDK with BigQuery components."
        exit 1
    fi
    
    # Check if user is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        log_error "No active Google Cloud authentication found. Please run: gcloud auth login"
        exit 1
    fi
    
    # Check if project exists and user has access
    if ! gcloud projects describe "${PROJECT_ID}" &>/dev/null; then
        log_error "Cannot access project ${PROJECT_ID}. Please check project ID and permissions."
        exit 1
    fi
    
    # Set default project and region
    gcloud config set project "${PROJECT_ID}"
    gcloud config set compute/region "${REGION}"
    
    log_success "Prerequisites check completed"
}

# Confirmation prompt
confirm_cleanup() {
    if [[ "${FORCE}" == "true" ]] || [[ "${DRY_RUN}" == "true" ]]; then
        return 0
    fi
    
    echo ""
    echo "⚠️  WARNING: This will delete the following resources:"
    echo ""
    echo "   • Datastream: ${STREAM_NAME}"
    echo "   • Connection Profiles: ${CONNECTION_PROFILE_NAME}, ${BQ_CONNECTION_PROFILE_NAME}"
    
    if [[ "${KEEP_BIGQUERY}" == "false" ]]; then
        echo "   • BigQuery Dataset: ${DATASET_NAME} (including all tables and views)"
    else
        echo "   • BigQuery Dataset: WILL BE PRESERVED"
    fi
    
    echo ""
    echo "   Note: Looker Studio dashboards must be deleted manually"
    echo ""
    
    read -r -p "Are you sure you want to continue? (yes/no): " response
    case "$response" in
        [yY][eE][sS]|[yY])
            log "User confirmed cleanup"
            ;;
        *)
            log "Cleanup cancelled by user"
            exit 0
            ;;
    esac
}

# Stop and delete Datastream
cleanup_datastream() {
    log "Cleaning up Datastream resources..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log "DRY RUN: Would stop and delete Datastream: ${STREAM_NAME}"
        return
    fi
    
    # Check if stream exists
    if ! gcloud datastream streams describe "${STREAM_NAME}" \
        --location="${REGION}" &>/dev/null; then
        log_warning "Datastream ${STREAM_NAME} not found or already deleted"
        return
    fi
    
    # Get current stream state
    local stream_state
    stream_state=$(gcloud datastream streams describe "${STREAM_NAME}" \
        --location="${REGION}" \
        --format="value(state)" 2>/dev/null || echo "UNKNOWN")
    
    log "Current stream state: ${stream_state}"
    
    # Stop the stream if it's running
    if [[ "${stream_state}" == "RUNNING" ]] || [[ "${stream_state}" == "STARTING" ]]; then
        log "Stopping Datastream..."
        if gcloud datastream streams stop "${STREAM_NAME}" \
            --location="${REGION}" \
            --quiet; then
            log_success "Datastream stopped"
            
            # Wait for stream to stop
            log "Waiting for stream to stop completely..."
            local max_attempts=20
            local attempt=1
            
            while [[ ${attempt} -le ${max_attempts} ]]; do
                stream_state=$(gcloud datastream streams describe "${STREAM_NAME}" \
                    --location="${REGION}" \
                    --format="value(state)" 2>/dev/null || echo "UNKNOWN")
                
                if [[ "${stream_state}" == "NOT_STARTED" ]] || [[ "${stream_state}" == "STOPPED" ]]; then
                    log_success "Stream stopped successfully"
                    break
                else
                    log "Stream state: ${stream_state}. Waiting... (${attempt}/${max_attempts})"
                    sleep 15
                    ((attempt++))
                fi
            done
            
            if [[ ${attempt} -gt ${max_attempts} ]]; then
                log_warning "Stream did not stop within expected time, proceeding with deletion"
            fi
        else
            log_warning "Failed to stop Datastream, attempting deletion anyway"
        fi
    fi
    
    # Delete the stream
    log "Deleting Datastream..."
    if gcloud datastream streams delete "${STREAM_NAME}" \
        --location="${REGION}" \
        --quiet; then
        log_success "Datastream deleted successfully"
    else
        log_error "Failed to delete Datastream"
        return 1
    fi
}

# Delete connection profiles
cleanup_connection_profiles() {
    log "Cleaning up connection profiles..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log "DRY RUN: Would delete connection profiles matching: ${CONNECTION_PROFILE_NAME}, ${BQ_CONNECTION_PROFILE_NAME}"
        return
    fi
    
    # Get list of all connection profiles in the region
    local profiles
    profiles=$(gcloud datastream connection-profiles list \
        --location="${REGION}" \
        --format="value(name)" 2>/dev/null || echo "")
    
    if [[ -z "${profiles}" ]]; then
        log_warning "No connection profiles found in region ${REGION}"
        return
    fi
    
    # Delete source connection profiles (handle wildcard pattern)
    log "Looking for source connection profiles..."
    local source_pattern="${CONNECTION_PROFILE_NAME//\*/.*}"
    
    while IFS= read -r profile; do
        if [[ -n "${profile}" ]]; then
            local profile_name
            profile_name=$(basename "${profile}")
            
            # Check if profile matches our pattern or exact name
            if [[ "${profile_name}" =~ ${source_pattern} ]] || [[ "${profile_name}" == "${CONNECTION_PROFILE_NAME}" ]]; then
                log "Deleting source connection profile: ${profile_name}"
                if gcloud datastream connection-profiles delete "${profile_name}" \
                    --location="${REGION}" \
                    --quiet; then
                    log_success "Deleted source connection profile: ${profile_name}"
                else
                    log_warning "Failed to delete source connection profile: ${profile_name}"
                fi
            fi
        fi
    done <<< "${profiles}"
    
    # Delete BigQuery connection profiles (handle wildcard pattern)
    log "Looking for BigQuery connection profiles..."
    local bq_pattern="${BQ_CONNECTION_PROFILE_NAME//\*/.*}"
    
    while IFS= read -r profile; do
        if [[ -n "${profile}" ]]; then
            local profile_name
            profile_name=$(basename "${profile}")
            
            # Check if profile matches our pattern or exact name
            if [[ "${profile_name}" =~ ${bq_pattern} ]] || [[ "${profile_name}" == "${BQ_CONNECTION_PROFILE_NAME}" ]]; then
                log "Deleting BigQuery connection profile: ${profile_name}"
                if gcloud datastream connection-profiles delete "${profile_name}" \
                    --location="${REGION}" \
                    --quiet; then
                    log_success "Deleted BigQuery connection profile: ${profile_name}"
                else
                    log_warning "Failed to delete BigQuery connection profile: ${profile_name}"
                fi
            fi
        fi
    done <<< "${profiles}"
}

# Delete BigQuery resources
cleanup_bigquery() {
    if [[ "${KEEP_BIGQUERY}" == "true" ]]; then
        log "Skipping BigQuery cleanup (--keep-bigquery flag specified)"
        return
    fi
    
    log "Cleaning up BigQuery resources..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log "DRY RUN: Would delete BigQuery dataset: ${DATASET_NAME}"
        return
    fi
    
    # Check if dataset exists
    if ! bq ls -d "${PROJECT_ID}:${DATASET_NAME}" &>/dev/null; then
        log_warning "BigQuery dataset ${DATASET_NAME} not found or already deleted"
        return
    fi
    
    # Show dataset contents before deletion
    log "Dataset contents before deletion:"
    if bq ls "${DATASET_NAME}"; then
        local table_count
        table_count=$(bq ls "${DATASET_NAME}" | grep -c "TABLE\|VIEW" || echo "0")
        log "Found ${table_count} tables/views in dataset"
    fi
    
    # Delete BigQuery dataset and all tables/views
    log "Deleting BigQuery dataset and all contents..."
    if bq rm -r -f "${PROJECT_ID}:${DATASET_NAME}"; then
        log_success "BigQuery dataset deleted successfully"
    else
        log_error "Failed to delete BigQuery dataset"
        return 1
    fi
}

# Display manual cleanup instructions
display_manual_cleanup() {
    cat << EOF

==================================================
MANUAL CLEANUP REQUIRED
==================================================

The following resources need to be cleaned up manually:

1. LOOKER STUDIO DASHBOARDS:
   - Navigate to: https://lookerstudio.google.com/
   - Find and delete any reports created for this analytics solution
   - Look for reports connected to dataset: ${DATASET_NAME}

2. SOURCE DATABASE CONFIGURATION:
   - Review database binary logging settings
   - Remove Datastream user if no longer needed
   - Review database firewall rules for GCP access

3. NETWORK CONNECTIVITY:
   - Review VPN or private connectivity configurations
   - Clean up firewall rules if created specifically for this solution

4. MONITORING AND ALERTS:
   - Remove any custom monitoring dashboards
   - Clean up alerting policies related to Datastream

==================================================
VERIFICATION COMMANDS
==================================================

Verify cleanup completion:

# Check for remaining Datastream resources
gcloud datastream streams list --location=${REGION}
gcloud datastream connection-profiles list --location=${REGION}

# Check BigQuery datasets (if not using --keep-bigquery)
bq ls -d

# Check for remaining resources in project
gcloud projects get-iam-policy ${PROJECT_ID}

==================================================

EOF
}

# Clean up environment file
cleanup_environment_file() {
    if [[ "${DRY_RUN}" == "true" ]]; then
        log "DRY RUN: Would remove environment file: ${ENV_FILE}"
        return
    fi
    
    if [[ -f "${ENV_FILE}" ]]; then
        log "Removing environment file..."
        if rm -f "${ENV_FILE}"; then
            log_success "Environment file removed"
        else
            log_warning "Failed to remove environment file"
        fi
    fi
}

# Main cleanup function
main() {
    log "=== Starting Real-Time Analytics Dashboard Cleanup ==="
    
    check_prerequisites
    confirm_cleanup
    
    # Perform cleanup in reverse order of creation
    cleanup_datastream
    cleanup_connection_profiles
    cleanup_bigquery
    cleanup_environment_file
    
    display_manual_cleanup
    
    log_success "=== Automated cleanup completed! ==="
    log "Log file: ${LOG_FILE}"
    
    if [[ "${KEEP_BIGQUERY}" == "true" ]]; then
        log "BigQuery dataset preserved: ${DATASET_NAME}"
    fi
    
    log "Please complete manual cleanup steps shown above"
}

# Run main function
main "$@"