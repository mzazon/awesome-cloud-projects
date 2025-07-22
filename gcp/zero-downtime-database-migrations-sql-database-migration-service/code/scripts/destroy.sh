#!/bin/bash

# Zero-Downtime Database Migration Cleanup Script for GCP
# Description: Safely removes all Database Migration Service infrastructure
# WARNING: This script will delete resources and may result in data loss

set -euo pipefail  # Exit on any error, undefined variable, or pipe failure

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/destroy.log"
DRY_RUN=false
FORCE=false
KEEP_CLOUDSQL=false

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a "${LOG_FILE}"
}

# Error handling function
error_exit() {
    echo -e "${RED}ERROR: $1${NC}" >&2
    log "ERROR: $1"
    exit 1
}

# Success message function
success() {
    echo -e "${GREEN}✅ $1${NC}"
    log "SUCCESS: $1"
}

# Warning message function
warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
    log "WARNING: $1"
}

# Info message function
info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
    log "INFO: $1"
}

# Usage function
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Safely destroy Zero-Downtime Database Migration infrastructure on GCP

OPTIONS:
    -h, --help              Show this help message
    -d, --dry-run          Show what would be destroyed without making changes
    -f, --force            Skip confirmation prompts (use with caution)
    -r, --region REGION    GCP region (default: us-central1)
    -p, --project PROJECT  GCP project ID (uses current gcloud config if not specified)
    --keep-cloudsql        Preserve Cloud SQL instance (only remove migration resources)
    --migration-job-id ID  Specific migration job ID to delete
    --instance-id ID       Specific Cloud SQL instance ID to delete
    --profile-id ID        Specific connection profile ID to delete

EXAMPLES:
    $0 --dry-run
    $0 --force --region us-west1
    $0 --keep-cloudsql --migration-job-id mysql-migration-abc123
    $0 --migration-job-id mysql-migration-abc123 --instance-id target-mysql-abc123

SAFETY:
    This script includes multiple confirmation prompts and safety checks.
    Use --force to skip prompts (not recommended for production).
    Use --dry-run to see what would be deleted without making changes.

EOF
}

# Check prerequisites
check_prerequisites() {
    info "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        error_exit "gcloud CLI is not installed. Please install it from https://cloud.google.com/sdk"
    fi
    
    # Check if gcloud is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        error_exit "gcloud is not authenticated. Please run 'gcloud auth login'"
    fi
    
    # Check if a project is configured
    if [[ -z "${PROJECT_ID:-}" ]]; then
        PROJECT_ID=$(gcloud config get-value project 2>/dev/null || echo "")
        if [[ -z "${PROJECT_ID}" ]]; then
            error_exit "No GCP project configured. Use --project flag or run 'gcloud config set project PROJECT_ID'"
        fi
    fi
    
    # Verify project exists and user has access
    if ! gcloud projects describe "${PROJECT_ID}" &>/dev/null; then
        error_exit "Cannot access project '${PROJECT_ID}'. Check project ID and permissions."
    fi
    
    success "Prerequisites check completed"
}

# Set environment variables
set_environment_variables() {
    info "Setting up environment variables..."
    
    # Project and region configuration
    export PROJECT_ID="${PROJECT_ID}"
    export REGION="${REGION}"
    export ZONE="${REGION}-a"
    
    # Set gcloud defaults
    gcloud config set project "${PROJECT_ID}" || error_exit "Failed to set project"
    gcloud config set compute/region "${REGION}" || error_exit "Failed to set region"
    gcloud config set compute/zone "${ZONE}" || error_exit "Failed to set zone"
    
    success "Environment variables configured"
    log "Project ID: ${PROJECT_ID}"
    log "Region: ${REGION}"
}

# Confirmation prompt
confirm_destruction() {
    if [[ "${FORCE}" == "true" ]]; then
        warning "Force mode enabled - skipping confirmation prompts"
        return 0
    fi
    
    echo ""
    warning "DANGER: This script will delete Google Cloud resources!"
    echo "Project: ${PROJECT_ID}"
    echo "Region: ${REGION}"
    
    if [[ -n "${MIGRATION_JOB_ID:-}" ]]; then
        echo "Migration Job: ${MIGRATION_JOB_ID}"
    fi
    
    if [[ -n "${CLOUDSQL_INSTANCE_ID:-}" ]]; then
        echo "Cloud SQL Instance: ${CLOUDSQL_INSTANCE_ID}"
    fi
    
    if [[ "${KEEP_CLOUDSQL}" == "true" ]]; then
        echo ""
        info "Cloud SQL instances will be preserved (--keep-cloudsql flag set)"
    fi
    
    echo ""
    echo "Resources that will be deleted:"
    echo "- Database Migration Service jobs and connection profiles"
    echo "- Cloud Storage buckets used for migration"
    echo "- Monitoring alert policies and log-based metrics"
    
    if [[ "${KEEP_CLOUDSQL}" != "true" ]]; then
        echo "- Cloud SQL instances and all their data"
    fi
    
    echo ""
    warning "This action CANNOT be undone!"
    echo ""
    
    read -p "Are you sure you want to proceed? (type 'yes' to confirm): " confirmation
    
    if [[ "${confirmation}" != "yes" ]]; then
        info "Destruction cancelled by user"
        exit 0
    fi
    
    echo ""
    warning "Final confirmation required for destructive operations"
    read -p "Type 'DELETE' to confirm resource deletion: " final_confirmation
    
    if [[ "${final_confirmation}" != "DELETE" ]]; then
        info "Destruction cancelled by user"
        exit 0
    fi
    
    success "Destruction confirmed by user"
}

# List migration resources
list_migration_resources() {
    info "Discovering migration resources in project ${PROJECT_ID}..."
    
    # List migration jobs
    local migration_jobs
    migration_jobs=$(gcloud datamigration migration-jobs list \
        --region="${REGION}" \
        --format="value(name)" 2>/dev/null || echo "")
    
    if [[ -n "${migration_jobs}" ]]; then
        info "Found migration jobs:"
        echo "${migration_jobs}" | while read -r job; do
            if [[ -n "${job}" ]]; then
                echo "  - ${job}"
            fi
        done
    else
        info "No migration jobs found in region ${REGION}"
    fi
    
    # List connection profiles
    local connection_profiles
    connection_profiles=$(gcloud datamigration connection-profiles list \
        --region="${REGION}" \
        --format="value(name)" 2>/dev/null || echo "")
    
    if [[ -n "${connection_profiles}" ]]; then
        info "Found connection profiles:"
        echo "${connection_profiles}" | while read -r profile; do
            if [[ -n "${profile}" ]]; then
                echo "  - ${profile}"
            fi
        done
    else
        info "No connection profiles found in region ${REGION}"
    fi
    
    # List Cloud SQL instances
    if [[ "${KEEP_CLOUDSQL}" != "true" ]]; then
        local sql_instances
        sql_instances=$(gcloud sql instances list \
            --format="value(name)" 2>/dev/null || echo "")
        
        if [[ -n "${sql_instances}" ]]; then
            info "Found Cloud SQL instances:"
            echo "${sql_instances}" | while read -r instance; do
                if [[ -n "${instance}" ]]; then
                    echo "  - ${instance}"
                fi
            done
        else
            info "No Cloud SQL instances found"
        fi
    fi
}

# Stop and delete migration jobs
delete_migration_jobs() {
    info "Deleting Database Migration Service jobs..."
    
    local jobs_to_delete=()
    
    if [[ -n "${MIGRATION_JOB_ID:-}" ]]; then
        jobs_to_delete=("${MIGRATION_JOB_ID}")
    else
        # Get all migration jobs in the region
        local all_jobs
        all_jobs=$(gcloud datamigration migration-jobs list \
            --region="${REGION}" \
            --format="value(name)" 2>/dev/null || echo "")
        
        if [[ -n "${all_jobs}" ]]; then
            while IFS= read -r job; do
                if [[ -n "${job}" ]]; then
                    jobs_to_delete+=("$(basename "${job}")")
                fi
            done <<< "${all_jobs}"
        fi
    fi
    
    if [[ ${#jobs_to_delete[@]} -eq 0 ]]; then
        info "No migration jobs to delete"
        return 0
    fi
    
    for job_id in "${jobs_to_delete[@]}"; do
        if [[ "${DRY_RUN}" == "true" ]]; then
            info "[DRY RUN] Would delete migration job: ${job_id}"
            continue
        fi
        
        info "Processing migration job: ${job_id}"
        
        # Check if job exists
        if ! gcloud datamigration migration-jobs describe "${job_id}" \
            --region="${REGION}" &>/dev/null; then
            warning "Migration job ${job_id} not found. Skipping."
            continue
        fi
        
        # Get job state
        local job_state
        job_state=$(gcloud datamigration migration-jobs describe "${job_id}" \
            --region="${REGION}" \
            --format="value(state)" 2>/dev/null || echo "UNKNOWN")
        
        info "Migration job ${job_id} state: ${job_state}"
        
        # Stop job if it's running
        if [[ "${job_state}" == "RUNNING" || "${job_state}" == "STARTING" ]]; then
            info "Stopping migration job: ${job_id}"
            if ! gcloud datamigration migration-jobs stop "${job_id}" \
                --region="${REGION}" \
                --quiet; then
                warning "Failed to stop migration job ${job_id}. Attempting to delete anyway."
            else
                # Wait for job to stop
                info "Waiting for job to stop..."
                local timeout=120  # 2 minutes
                local elapsed=0
                
                while [[ $elapsed -lt $timeout ]]; do
                    local current_state
                    current_state=$(gcloud datamigration migration-jobs describe "${job_id}" \
                        --region="${REGION}" \
                        --format="value(state)" 2>/dev/null || echo "UNKNOWN")
                    
                    if [[ "$current_state" != "RUNNING" && "$current_state" != "STARTING" ]]; then
                        break
                    fi
                    
                    sleep 5
                    elapsed=$((elapsed + 5))
                done
            fi
        fi
        
        # Delete the migration job
        info "Deleting migration job: ${job_id}"
        if ! gcloud datamigration migration-jobs delete "${job_id}" \
            --region="${REGION}" \
            --quiet; then
            warning "Failed to delete migration job: ${job_id}"
        else
            success "Deleted migration job: ${job_id}"
        fi
    done
}

# Delete connection profiles
delete_connection_profiles() {
    info "Deleting Database Migration Service connection profiles..."
    
    local profiles_to_delete=()
    
    if [[ -n "${SOURCE_PROFILE_ID:-}" ]]; then
        profiles_to_delete=("${SOURCE_PROFILE_ID}")
    else
        # Get all connection profiles in the region
        local all_profiles
        all_profiles=$(gcloud datamigration connection-profiles list \
            --region="${REGION}" \
            --format="value(name)" 2>/dev/null || echo "")
        
        if [[ -n "${all_profiles}" ]]; then
            while IFS= read -r profile; do
                if [[ -n "${profile}" ]]; then
                    profiles_to_delete+=("$(basename "${profile}")")
                fi
            done <<< "${all_profiles}"
        fi
    fi
    
    if [[ ${#profiles_to_delete[@]} -eq 0 ]]; then
        info "No connection profiles to delete"
        return 0
    fi
    
    for profile_id in "${profiles_to_delete[@]}"; do
        if [[ "${DRY_RUN}" == "true" ]]; then
            info "[DRY RUN] Would delete connection profile: ${profile_id}"
            continue
        fi
        
        info "Deleting connection profile: ${profile_id}"
        
        if ! gcloud datamigration connection-profiles delete "${profile_id}" \
            --region="${REGION}" \
            --quiet; then
            warning "Failed to delete connection profile: ${profile_id}"
        else
            success "Deleted connection profile: ${profile_id}"
        fi
    done
}

# Delete Cloud SQL instances
delete_cloudsql_instances() {
    if [[ "${KEEP_CLOUDSQL}" == "true" ]]; then
        info "Preserving Cloud SQL instances (--keep-cloudsql flag set)"
        return 0
    fi
    
    info "Deleting Cloud SQL instances..."
    
    local instances_to_delete=()
    
    if [[ -n "${CLOUDSQL_INSTANCE_ID:-}" ]]; then
        instances_to_delete=("${CLOUDSQL_INSTANCE_ID}")
        # Also check for replica
        if gcloud sql instances describe "${CLOUDSQL_INSTANCE_ID}-replica" &>/dev/null; then
            instances_to_delete+=("${CLOUDSQL_INSTANCE_ID}-replica")
        fi
    else
        # Get all Cloud SQL instances
        local all_instances
        all_instances=$(gcloud sql instances list \
            --format="value(name)" 2>/dev/null || echo "")
        
        if [[ -n "${all_instances}" ]]; then
            while IFS= read -r instance; do
                if [[ -n "${instance}" ]]; then
                    instances_to_delete+=("${instance}")
                fi
            done <<< "${all_instances}"
        fi
    fi
    
    if [[ ${#instances_to_delete[@]} -eq 0 ]]; then
        info "No Cloud SQL instances to delete"
        return 0
    fi
    
    # Delete replicas first, then master instances
    for instance_id in "${instances_to_delete[@]}"; do
        if [[ "${instance_id}" == *"-replica" ]]; then
            if [[ "${DRY_RUN}" == "true" ]]; then
                info "[DRY RUN] Would delete Cloud SQL replica: ${instance_id}"
                continue
            fi
            
            info "Deleting Cloud SQL replica: ${instance_id}"
            if ! gcloud sql instances delete "${instance_id}" --quiet; then
                warning "Failed to delete Cloud SQL replica: ${instance_id}"
            else
                success "Deleted Cloud SQL replica: ${instance_id}"
            fi
        fi
    done
    
    # Delete master instances
    for instance_id in "${instances_to_delete[@]}"; do
        if [[ "${instance_id}" != *"-replica" ]]; then
            if [[ "${DRY_RUN}" == "true" ]]; then
                info "[DRY RUN] Would delete Cloud SQL instance: ${instance_id}"
                continue
            fi
            
            info "Deleting Cloud SQL instance: ${instance_id}"
            warning "This will permanently delete all data in the instance!"
            
            if ! gcloud sql instances delete "${instance_id}" --quiet; then
                warning "Failed to delete Cloud SQL instance: ${instance_id}"
            else
                success "Deleted Cloud SQL instance: ${instance_id}"
            fi
        fi
    done
}

# Clean up storage buckets
cleanup_storage_buckets() {
    info "Cleaning up migration storage buckets..."
    
    local bucket_name="${PROJECT_ID}-migration-dump"
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        info "[DRY RUN] Would check and delete storage bucket: gs://${bucket_name}"
        return
    fi
    
    # Check if bucket exists
    if gsutil ls "gs://${bucket_name}" &>/dev/null; then
        info "Deleting storage bucket: gs://${bucket_name}"
        
        # Remove all objects first
        if ! gsutil -m rm -r "gs://${bucket_name}/*" 2>/dev/null; then
            info "No objects found in bucket or already empty"
        fi
        
        # Delete the bucket
        if ! gsutil rb "gs://${bucket_name}"; then
            warning "Failed to delete storage bucket: gs://${bucket_name}"
        else
            success "Deleted storage bucket: gs://${bucket_name}"
        fi
    else
        info "Storage bucket gs://${bucket_name} not found"
    fi
}

# Clean up monitoring resources
cleanup_monitoring() {
    info "Cleaning up monitoring and alerting resources..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        info "[DRY RUN] Would delete alert policies and log-based metrics"
        return
    fi
    
    # Delete alert policies related to database migration
    local alert_policies
    alert_policies=$(gcloud alpha monitoring policies list \
        --filter="displayName:'Database Migration Alert'" \
        --format="value(name)" 2>/dev/null || echo "")
    
    if [[ -n "${alert_policies}" ]]; then
        while IFS= read -r policy; do
            if [[ -n "${policy}" ]]; then
                info "Deleting alert policy: ${policy}"
                if ! gcloud alpha monitoring policies delete "${policy}" --quiet 2>/dev/null; then
                    warning "Failed to delete alert policy: ${policy}"
                else
                    success "Deleted alert policy: ${policy}"
                fi
            fi
        done <<< "${alert_policies}"
    else
        info "No migration alert policies found"
    fi
    
    # Delete log-based metrics
    if gcloud logging metrics describe migration_errors &>/dev/null; then
        info "Deleting log-based metric: migration_errors"
        if ! gcloud logging metrics delete migration_errors --quiet; then
            warning "Failed to delete log-based metric: migration_errors"
        else
            success "Deleted log-based metric: migration_errors"
        fi
    else
        info "Log-based metric 'migration_errors' not found"
    fi
}

# Clean up temporary files
cleanup_temp_files() {
    info "Cleaning up temporary files..."
    
    local files_to_remove=(
        "${SCRIPT_DIR}/alert-policy.json"
        "${SCRIPT_DIR}/validate_migration.sql"
    )
    
    for file in "${files_to_remove[@]}"; do
        if [[ -f "${file}" ]]; then
            if [[ "${DRY_RUN}" == "true" ]]; then
                info "[DRY RUN] Would remove file: ${file}"
            else
                info "Removing file: ${file}"
                rm -f "${file}"
                success "Removed file: ${file}"
            fi
        fi
    done
}

# Display destruction summary
display_summary() {
    info "Destruction Summary"
    echo "==================="
    echo "Project ID: ${PROJECT_ID}"
    echo "Region: ${REGION}"
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        echo ""
        warning "This was a dry run. No resources were actually deleted."
        echo "Run without --dry-run to destroy the infrastructure."
    else
        echo ""
        success "All specified resources have been destroyed"
        
        if [[ "${KEEP_CLOUDSQL}" == "true" ]]; then
            info "Cloud SQL instances were preserved as requested"
        fi
        
        echo ""
        info "Cleanup completed. Check the log file for details: ${LOG_FILE}"
    fi
}

# Main destruction function
main() {
    # Initialize log file
    echo "Starting destruction at $(date)" > "${LOG_FILE}"
    
    info "Starting Zero-Downtime Database Migration infrastructure cleanup"
    
    check_prerequisites
    set_environment_variables
    
    if [[ "${DRY_RUN}" != "true" ]]; then
        confirm_destruction
    fi
    
    list_migration_resources
    delete_migration_jobs
    delete_connection_profiles
    delete_cloudsql_instances
    cleanup_storage_buckets
    cleanup_monitoring
    cleanup_temp_files
    
    success "Cleanup completed successfully!"
    display_summary
}

# Parse command line arguments
REGION="us-central1"
MIGRATION_JOB_ID=""
CLOUDSQL_INSTANCE_ID=""
SOURCE_PROFILE_ID=""

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            usage
            exit 0
            ;;
        -d|--dry-run)
            DRY_RUN=true
            shift
            ;;
        -f|--force)
            FORCE=true
            shift
            ;;
        --keep-cloudsql)
            KEEP_CLOUDSQL=true
            shift
            ;;
        -r|--region)
            REGION="$2"
            shift 2
            ;;
        -p|--project)
            PROJECT_ID="$2"
            shift 2
            ;;
        --migration-job-id)
            MIGRATION_JOB_ID="$2"
            shift 2
            ;;
        --instance-id)
            CLOUDSQL_INSTANCE_ID="$2"
            shift 2
            ;;
        --profile-id)
            SOURCE_PROFILE_ID="$2"
            shift 2
            ;;
        *)
            error_exit "Unknown option: $1. Use --help for usage information."
            ;;
    esac
done

# Execute main function
main

exit 0