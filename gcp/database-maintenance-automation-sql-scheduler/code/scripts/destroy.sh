#!/bin/bash

# Database Maintenance Automation with Cloud SQL and Cloud Scheduler - Cleanup Script
# This script safely removes all resources created by the database maintenance automation solution

set -euo pipefail

# Color codes for output formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        error "gcloud CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if gsutil is installed
    if ! command -v gsutil &> /dev/null; then
        error "gsutil is not installed. Please install Google Cloud SDK."
        exit 1
    fi
    
    # Check if user is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        error "No active gcloud authentication found. Please run 'gcloud auth login'"
        exit 1
    fi
    
    # Check if project is set
    if ! gcloud config get-value project &> /dev/null; then
        error "No default project set. Please run 'gcloud config set project PROJECT_ID'"
        exit 1
    fi
    
    success "Prerequisites check passed"
}

# Function to load deployment configuration
load_deployment_config() {
    log "Loading deployment configuration..."
    
    local config_file="deployment-config.json"
    
    if [ -f "${config_file}" ]; then
        log "Found deployment configuration file: ${config_file}"
        
        # Extract configuration using jq if available, otherwise use basic parsing
        if command -v jq &> /dev/null; then
            export PROJECT_ID=$(jq -r '.project_id' "${config_file}")
            export REGION=$(jq -r '.region' "${config_file}")
            export DB_INSTANCE_NAME=$(jq -r '.resources.db_instance_name' "${config_file}")
            export FUNCTION_NAME=$(jq -r '.resources.function_name' "${config_file}")
            export SCHEDULER_JOB_NAME=$(jq -r '.resources.scheduler_job_name' "${config_file}")
            export BUCKET_NAME=$(jq -r '.resources.bucket_name' "${config_file}")
        else
            # Fallback parsing without jq
            export PROJECT_ID=$(grep '"project_id"' "${config_file}" | cut -d'"' -f4)
            export REGION=$(grep '"region"' "${config_file}" | cut -d'"' -f4)
            export DB_INSTANCE_NAME=$(grep '"db_instance_name"' "${config_file}" | cut -d'"' -f4)
            export FUNCTION_NAME=$(grep '"function_name"' "${config_file}" | cut -d'"' -f4)
            export SCHEDULER_JOB_NAME=$(grep '"scheduler_job_name"' "${config_file}" | cut -d'"' -f4)
            export BUCKET_NAME=$(grep '"bucket_name"' "${config_file}" | cut -d'"' -f4)
        fi
        
        success "Configuration loaded from file"
    else
        warning "No deployment configuration file found. Using manual input or environment variables."
        setup_manual_config
    fi
}

# Function to setup configuration manually or from environment
setup_manual_config() {
    log "Setting up configuration manually..."
    
    export PROJECT_ID="${PROJECT_ID:-$(gcloud config get-value project)}"
    export REGION="${REGION:-us-central1}"
    
    # Prompt for resource names if not provided
    if [ -z "${DB_INSTANCE_NAME:-}" ]; then
        echo -n "Enter Cloud SQL instance name: "
        read -r DB_INSTANCE_NAME
        export DB_INSTANCE_NAME
    fi
    
    if [ -z "${FUNCTION_NAME:-}" ]; then
        echo -n "Enter Cloud Function name: "
        read -r FUNCTION_NAME
        export FUNCTION_NAME
    fi
    
    if [ -z "${SCHEDULER_JOB_NAME:-}" ]; then
        echo -n "Enter Scheduler job name prefix: "
        read -r SCHEDULER_JOB_NAME
        export SCHEDULER_JOB_NAME
    fi
    
    if [ -z "${BUCKET_NAME:-}" ]; then
        echo -n "Enter Storage bucket name: "
        read -r BUCKET_NAME
        export BUCKET_NAME
    fi
}

# Function to display resources to be deleted
display_cleanup_plan() {
    echo
    warning "=== CLEANUP PLAN ==="
    log "The following resources will be PERMANENTLY DELETED:"
    echo
    log "  • Cloud SQL Instance: ${DB_INSTANCE_NAME}"
    log "  • Cloud Function: ${FUNCTION_NAME}"
    log "  • Storage Bucket: gs://${BUCKET_NAME} (including all data)"
    log "  • Scheduler Jobs: ${SCHEDULER_JOB_NAME}*"
    log "  • Monitoring Alerts: Database maintenance related policies"
    log "  • Monitoring Dashboard: Database Maintenance Dashboard"
    echo
    warning "This action CANNOT be undone!"
    warning "All data in the Cloud SQL database and Storage bucket will be lost!"
    echo
}

# Function to confirm deletion with user
confirm_deletion() {
    display_cleanup_plan
    
    # Check for force flag
    if [ "${FORCE:-false}" = "true" ]; then
        warning "Force flag detected. Skipping confirmation."
        return 0
    fi
    
    echo -n "Are you sure you want to proceed? Type 'DELETE' to confirm: "
    read -r confirmation
    
    if [ "$confirmation" != "DELETE" ]; then
        log "Cleanup cancelled by user."
        exit 0
    fi
    
    echo -n "Final confirmation - enter the project ID (${PROJECT_ID}) to proceed: "
    read -r project_confirmation
    
    if [ "$project_confirmation" != "$PROJECT_ID" ]; then
        error "Project ID confirmation failed. Cleanup cancelled."
        exit 1
    fi
    
    success "Deletion confirmed. Proceeding with cleanup..."
}

# Function to delete Cloud Scheduler jobs
delete_scheduler_jobs() {
    log "Deleting Cloud Scheduler jobs..."
    
    # List and delete all scheduler jobs matching our pattern
    local jobs=$(gcloud scheduler jobs list --location="${REGION}" --filter="name~${SCHEDULER_JOB_NAME}" --format="value(name)" 2>/dev/null || true)
    
    if [ -n "$jobs" ]; then
        while IFS= read -r job; do
            local job_name=$(basename "$job")
            log "Deleting scheduler job: ${job_name}"
            
            if gcloud scheduler jobs delete "${job_name}" --location="${REGION}" --quiet; then
                success "Deleted scheduler job: ${job_name}"
            else
                warning "Failed to delete scheduler job: ${job_name}"
            fi
        done <<< "$jobs"
    else
        log "No scheduler jobs found matching pattern: ${SCHEDULER_JOB_NAME}"
    fi
}

# Function to delete Cloud Function
delete_function() {
    log "Deleting Cloud Function..."
    
    # Check if function exists
    if gcloud functions describe "${FUNCTION_NAME}" --region="${REGION}" &>/dev/null; then
        if gcloud functions delete "${FUNCTION_NAME}" --region="${REGION}" --quiet; then
            success "Cloud Function deleted: ${FUNCTION_NAME}"
        else
            error "Failed to delete Cloud Function: ${FUNCTION_NAME}"
            return 1
        fi
    else
        log "Cloud Function not found: ${FUNCTION_NAME}"
    fi
}

# Function to delete monitoring resources
delete_monitoring_resources() {
    log "Deleting monitoring resources..."
    
    # Delete alerting policies
    local policies=$(gcloud alpha monitoring policies list \
        --filter="displayName:('Cloud SQL High CPU Usage' OR 'Cloud SQL High Connection Count')" \
        --format="value(name)" 2>/dev/null || true)
    
    if [ -n "$policies" ]; then
        while IFS= read -r policy; do
            if [ -n "$policy" ]; then
                log "Deleting alerting policy: $(basename $policy)"
                if gcloud alpha monitoring policies delete "$policy" --quiet; then
                    success "Deleted alerting policy"
                else
                    warning "Failed to delete alerting policy: $policy"
                fi
            fi
        done <<< "$policies"
    else
        log "No matching alerting policies found"
    fi
    
    # Delete dashboard
    local dashboard=$(gcloud monitoring dashboards list \
        --filter="displayName:'Database Maintenance Dashboard'" \
        --format="value(name)" 2>/dev/null || true)
    
    if [ -n "$dashboard" ]; then
        log "Deleting monitoring dashboard"
        if gcloud monitoring dashboards delete "$dashboard" --quiet; then
            success "Monitoring dashboard deleted"
        else
            warning "Failed to delete monitoring dashboard"
        fi
    else
        log "No matching monitoring dashboard found"
    fi
}

# Function to delete Cloud SQL instance
delete_sql_instance() {
    log "Deleting Cloud SQL instance..."
    
    # Check if instance exists
    if gcloud sql instances describe "${DB_INSTANCE_NAME}" &>/dev/null; then
        warning "Deleting Cloud SQL instance will permanently delete all data!"
        
        # Additional confirmation for SQL instance
        if [ "${FORCE:-false}" != "true" ]; then
            echo -n "Type the instance name (${DB_INSTANCE_NAME}) to confirm SQL deletion: "
            read -r sql_confirmation
            
            if [ "$sql_confirmation" != "$DB_INSTANCE_NAME" ]; then
                error "Instance name confirmation failed. Skipping SQL deletion."
                return 1
            fi
        fi
        
        log "Initiating Cloud SQL instance deletion..."
        if gcloud sql instances delete "${DB_INSTANCE_NAME}" --quiet; then
            success "Cloud SQL instance deletion initiated: ${DB_INSTANCE_NAME}"
            log "Note: SQL instance deletion may take several minutes to complete"
        else
            error "Failed to delete Cloud SQL instance: ${DB_INSTANCE_NAME}"
            return 1
        fi
    else
        log "Cloud SQL instance not found: ${DB_INSTANCE_NAME}"
    fi
}

# Function to delete Cloud Storage bucket
delete_storage_bucket() {
    log "Deleting Cloud Storage bucket..."
    
    # Check if bucket exists
    if gsutil ls "gs://${BUCKET_NAME}" &>/dev/null; then
        warning "Deleting storage bucket will permanently delete all maintenance reports and logs!"
        
        # List bucket contents for user awareness
        local object_count=$(gsutil ls -r "gs://${BUCKET_NAME}" 2>/dev/null | wc -l || echo "0")
        log "Bucket contains approximately ${object_count} objects"
        
        # Additional confirmation for storage bucket
        if [ "${FORCE:-false}" != "true" ]; then
            echo -n "Type 'DELETE BUCKET' to confirm storage deletion: "
            read -r bucket_confirmation
            
            if [ "$bucket_confirmation" != "DELETE BUCKET" ]; then
                error "Bucket deletion confirmation failed. Skipping storage deletion."
                return 1
            fi
        fi
        
        log "Removing all objects from bucket..."
        if gsutil -m rm -r "gs://${BUCKET_NAME}/**" 2>/dev/null || true; then
            log "Bucket contents removed"
        fi
        
        log "Deleting storage bucket..."
        if gsutil rb "gs://${BUCKET_NAME}"; then
            success "Storage bucket deleted: ${BUCKET_NAME}"
        else
            error "Failed to delete storage bucket: ${BUCKET_NAME}"
            return 1
        fi
    else
        log "Storage bucket not found: ${BUCKET_NAME}"
    fi
}

# Function to clean up local files
cleanup_local_files() {
    log "Cleaning up local files..."
    
    # Remove deployment configuration file
    if [ -f "deployment-config.json" ]; then
        log "Removing deployment configuration file..."
        rm -f "deployment-config.json"
        success "Deployment configuration file removed"
    fi
    
    # Remove any temporary files
    rm -f /tmp/lifecycle.json /tmp/*-alert-policy.json /tmp/dashboard-config.json 2>/dev/null || true
    
    success "Local cleanup completed"
}

# Function to verify cleanup completion
verify_cleanup() {
    log "Verifying cleanup completion..."
    
    local cleanup_issues=0
    
    # Check Cloud SQL instance
    if gcloud sql instances describe "${DB_INSTANCE_NAME}" &>/dev/null; then
        warning "Cloud SQL instance still exists (deletion may be in progress): ${DB_INSTANCE_NAME}"
        cleanup_issues=$((cleanup_issues + 1))
    else
        success "Cloud SQL instance cleanup verified"
    fi
    
    # Check Cloud Function
    if gcloud functions describe "${FUNCTION_NAME}" --region="${REGION}" &>/dev/null; then
        warning "Cloud Function still exists: ${FUNCTION_NAME}"
        cleanup_issues=$((cleanup_issues + 1))
    else
        success "Cloud Function cleanup verified"
    fi
    
    # Check Storage bucket
    if gsutil ls "gs://${BUCKET_NAME}" &>/dev/null; then
        warning "Storage bucket still exists: ${BUCKET_NAME}"
        cleanup_issues=$((cleanup_issues + 1))
    else
        success "Storage bucket cleanup verified"
    fi
    
    # Check Scheduler jobs
    local remaining_jobs=$(gcloud scheduler jobs list --location="${REGION}" --filter="name~${SCHEDULER_JOB_NAME}" --format="value(name)" | wc -l)
    if [ "$remaining_jobs" -gt 0 ]; then
        warning "Some scheduler jobs may still exist"
        cleanup_issues=$((cleanup_issues + 1))
    else
        success "Scheduler jobs cleanup verified"
    fi
    
    if [ $cleanup_issues -eq 0 ]; then
        success "All resources successfully cleaned up"
    else
        warning "Cleanup completed with ${cleanup_issues} potential issues"
        log "Some resources may still be in the process of deletion"
    fi
}

# Function to display cleanup summary
display_cleanup_summary() {
    echo
    success "=== Database Maintenance Automation Cleanup Complete ==="
    echo
    log "Cleanup Actions Performed:"
    log "  ✓ Cloud Scheduler jobs removed"
    log "  ✓ Cloud Function deleted"
    log "  ✓ Monitoring alerts and dashboard removed"
    log "  ✓ Cloud SQL instance deletion initiated"
    log "  ✓ Storage bucket and contents deleted"
    log "  ✓ Local configuration files cleaned up"
    echo
    log "Important Notes:"
    log "  • Cloud SQL instance deletion may take several minutes"
    log "  • Billing may continue until resources are fully deleted"
    log "  • Monitor Cloud Console to confirm complete deletion"
    echo
    warning "If you encounter any remaining resources, manually delete them through Cloud Console"
    echo
}

# Function to handle dry run mode
dry_run() {
    log "=== DRY RUN MODE ==="
    log "This is a simulation. No resources will be deleted."
    echo
    
    display_cleanup_plan
    
    log "In actual cleanup, the following steps would be executed:"
    log "  1. Delete Cloud Scheduler jobs"
    log "  2. Delete Cloud Function"
    log "  3. Remove monitoring alerts and dashboards"
    log "  4. Delete Cloud SQL instance"
    log "  5. Delete Cloud Storage bucket and contents"
    log "  6. Clean up local configuration files"
    echo
    log "To execute actual cleanup, run: $0 --force"
    echo
}

# Main cleanup function
main() {
    log "Starting Database Maintenance Automation cleanup..."
    
    # Check for dry run mode
    if [ "${DRY_RUN:-false}" = "true" ]; then
        dry_run
        exit 0
    fi
    
    # Run cleanup steps
    check_prerequisites
    load_deployment_config
    confirm_deletion
    
    log "Beginning resource deletion..."
    
    # Delete resources in reverse order of creation
    delete_scheduler_jobs
    delete_function
    delete_monitoring_resources
    delete_sql_instance
    delete_storage_bucket
    cleanup_local_files
    
    verify_cleanup
    display_cleanup_summary
    
    success "Cleanup completed!"
}

# Function to show usage information
show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --force        Skip confirmation prompts"
    echo "  --dry-run      Show what would be deleted without actually deleting"
    echo "  --help         Show this help message"
    echo ""
    echo "Environment Variables:"
    echo "  PROJECT_ID           Google Cloud project ID"
    echo "  REGION              Google Cloud region (default: us-central1)"
    echo "  DB_INSTANCE_NAME    Cloud SQL instance name"
    echo "  FUNCTION_NAME       Cloud Function name"
    echo "  SCHEDULER_JOB_NAME  Scheduler job name prefix"
    echo "  BUCKET_NAME         Storage bucket name"
    echo ""
    echo "Examples:"
    echo "  $0                   # Interactive cleanup"
    echo "  $0 --dry-run         # Preview cleanup actions"
    echo "  $0 --force           # Cleanup without prompts"
    echo ""
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --force)
            export FORCE=true
            shift
            ;;
        --dry-run)
            export DRY_RUN=true
            shift
            ;;
        --help)
            show_usage
            exit 0
            ;;
        *)
            error "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
done

# Handle script interruption
trap 'error "Cleanup interrupted. Some resources may remain."; exit 1' INT TERM

# Run main function
main "$@"