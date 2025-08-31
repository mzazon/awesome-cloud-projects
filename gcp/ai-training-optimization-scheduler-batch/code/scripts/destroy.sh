#!/bin/bash

# AI Training Optimization with Dynamic Workload Scheduler and Batch - Cleanup Script
# This script removes all resources created by the deployment script

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

success() {
    echo -e "${GREEN}✅ $1${NC}"
}

warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

error() {
    echo -e "${RED}❌ $1${NC}"
}

info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

# Script metadata
SCRIPT_VERSION="1.0"
RECIPE_NAME="AI Training Optimization with Dynamic Workload Scheduler and Batch"

log "Starting cleanup of $RECIPE_NAME resources"
log "Script version: $SCRIPT_VERSION"

# Configuration variables
CONFIG_FILE=""
FORCE_DELETE=false
DRY_RUN=false

# Load configuration from file
load_config() {
    if [[ -n "$CONFIG_FILE" && -f "$CONFIG_FILE" ]]; then
        log "Loading configuration from: $CONFIG_FILE"
        # shellcheck source=/dev/null
        source "$CONFIG_FILE"
        success "Configuration loaded successfully"
    else
        warning "No configuration file provided or file not found"
        log "Using environment variables or prompting for required values"
    fi
}

# Prompt for missing configuration
prompt_for_config() {
    if [[ -z "${PROJECT_ID:-}" ]]; then
        read -p "Enter your Google Cloud Project ID: " PROJECT_ID
        if [[ -z "$PROJECT_ID" ]]; then
            error "Project ID cannot be empty"
        fi
    fi
    
    if [[ -z "${REGION:-}" ]]; then
        REGION="us-central1"
        warning "Region not specified, using default: $REGION"
    fi
    
    if [[ -z "${RANDOM_SUFFIX:-}" ]]; then
        read -p "Enter the random suffix used during deployment (6 characters): " RANDOM_SUFFIX
        if [[ -z "$RANDOM_SUFFIX" ]]; then
            error "Random suffix cannot be empty"
        fi
    fi
    
    # Set derived variables
    export PROJECT_ID REGION RANDOM_SUFFIX
    export SERVICE_ACCOUNT="${SERVICE_ACCOUNT:-batch-training-sa-${RANDOM_SUFFIX}@${PROJECT_ID}.iam.gserviceaccount.com}"
    export BUCKET_NAME="${BUCKET_NAME:-ai-training-data-${RANDOM_SUFFIX}}"
    export TEMPLATE_NAME="${TEMPLATE_NAME:-ai-training-template-${RANDOM_SUFFIX}}"
    export JOB_NAME="${JOB_NAME:-ai-training-job-${RANDOM_SUFFIX}}"
    
    log "Configuration summary:"
    log "  Project ID: $PROJECT_ID"
    log "  Region: $REGION"
    log "  Random suffix: $RANDOM_SUFFIX"
}

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        error "Google Cloud CLI (gcloud) is not installed. Please install it first."
    fi
    
    # Check if gsutil is installed
    if ! command -v gsutil &> /dev/null; then
        error "gsutil is not installed. Please install Google Cloud SDK."
    fi
    
    # Check gcloud authentication
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        error "No active gcloud authentication found. Please run 'gcloud auth login'."
    fi
    
    # Set project
    gcloud config set project "$PROJECT_ID" || error "Failed to set project"
    
    success "Prerequisites check completed"
}

# Confirmation prompt
confirm_deletion() {
    if [[ "$FORCE_DELETE" == "true" ]]; then
        warning "Force delete enabled - skipping confirmation"
        return 0
    fi
    
    echo "======================================================"
    echo "⚠️  DESTRUCTIVE OPERATION WARNING ⚠️"
    echo "======================================================"
    echo "This script will permanently delete the following resources:"
    echo "  • Batch Job: $JOB_NAME"
    echo "  • Instance Template: $TEMPLATE_NAME"
    echo "  • Storage Bucket: gs://$BUCKET_NAME (and all contents)"
    echo "  • Service Account: $SERVICE_ACCOUNT"
    echo "  • Monitoring dashboards and alert policies"
    echo "======================================================"
    echo "Project: $PROJECT_ID"
    echo "Region: $REGION"
    echo "======================================================"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "DRY RUN MODE - No resources will be deleted"
        return 0
    fi
    
    read -p "Are you sure you want to delete these resources? (type 'yes' to confirm): " confirmation
    if [[ "$confirmation" != "yes" ]]; then
        info "Cleanup cancelled by user"
        exit 0
    fi
    
    log "Confirmation received - proceeding with cleanup"
}

# Delete batch job
delete_batch_job() {
    log "Deleting batch job: $JOB_NAME"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY RUN] Would delete batch job: $JOB_NAME"
        return 0
    fi
    
    # Check if job exists
    if gcloud batch jobs describe "$JOB_NAME" --location="$REGION" &>/dev/null; then
        # Check job status first
        local job_status
        job_status=$(gcloud batch jobs describe "$JOB_NAME" \
            --location="$REGION" \
            --format="value(state)" 2>/dev/null || echo "UNKNOWN")
        
        log "Current job status: $job_status"
        
        # Delete the job
        if gcloud batch jobs delete "$JOB_NAME" \
            --location="$REGION" \
            --quiet; then
            success "Batch job deleted: $JOB_NAME"
        else
            warning "Failed to delete batch job: $JOB_NAME (may not exist or already deleted)"
        fi
        
        # Wait for job deletion to complete
        log "Waiting for job deletion to complete..."
        local timeout=300  # 5 minutes
        local elapsed=0
        while [[ $elapsed -lt $timeout ]]; do
            if ! gcloud batch jobs describe "$JOB_NAME" --location="$REGION" &>/dev/null; then
                success "Job deletion confirmed"
                break
            fi
            sleep 10
            elapsed=$((elapsed + 10))
            log "Waiting for job deletion... ($elapsed/$timeout seconds)"
        done
    else
        info "Batch job not found: $JOB_NAME"
    fi
}

# Delete instance template
delete_instance_template() {
    log "Deleting instance template: $TEMPLATE_NAME"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY RUN] Would delete instance template: $TEMPLATE_NAME"
        return 0
    fi
    
    if gcloud compute instance-templates describe "$TEMPLATE_NAME" &>/dev/null; then
        if gcloud compute instance-templates delete "$TEMPLATE_NAME" --quiet; then
            success "Instance template deleted: $TEMPLATE_NAME"
        else
            warning "Failed to delete instance template: $TEMPLATE_NAME"
        fi
    else
        info "Instance template not found: $TEMPLATE_NAME"
    fi
}

# Delete storage bucket
delete_storage_bucket() {
    log "Deleting storage bucket: gs://$BUCKET_NAME"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY RUN] Would delete storage bucket: gs://$BUCKET_NAME"
        return 0
    fi
    
    # Check if bucket exists
    if gsutil ls "gs://$BUCKET_NAME" &>/dev/null; then
        log "Removing all objects from bucket..."
        if gsutil -m rm -r "gs://$BUCKET_NAME/*" 2>/dev/null || true; then
            log "Bucket contents cleared"
        fi
        
        log "Removing bucket..."
        if gsutil rb "gs://$BUCKET_NAME"; then
            success "Storage bucket deleted: gs://$BUCKET_NAME"
        else
            warning "Failed to delete storage bucket: gs://$BUCKET_NAME"
        fi
    else
        info "Storage bucket not found: gs://$BUCKET_NAME"
    fi
}

# Delete service account
delete_service_account() {
    log "Deleting service account: $SERVICE_ACCOUNT"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY RUN] Would delete service account: $SERVICE_ACCOUNT"
        return 0
    fi
    
    # Extract service account name from email
    local sa_name="${SERVICE_ACCOUNT%%@*}"
    
    if gcloud iam service-accounts describe "$SERVICE_ACCOUNT" &>/dev/null; then
        # Remove IAM policy bindings first
        log "Removing IAM policy bindings..."
        local roles=(
            "roles/storage.objectViewer"
            "roles/monitoring.metricWriter"
            "roles/logging.logWriter"
        )
        
        for role in "${roles[@]}"; do
            if gcloud projects remove-iam-policy-binding "$PROJECT_ID" \
                --member="serviceAccount:$SERVICE_ACCOUNT" \
                --role="$role" \
                --quiet 2>/dev/null; then
                log "Removed role: $role"
            else
                log "Role not found or already removed: $role"
            fi
        done
        
        # Delete service account
        if gcloud iam service-accounts delete "$SERVICE_ACCOUNT" --quiet; then
            success "Service account deleted: $SERVICE_ACCOUNT"
        else
            warning "Failed to delete service account: $SERVICE_ACCOUNT"
        fi
    else
        info "Service account not found: $SERVICE_ACCOUNT"
    fi
}

# Delete monitoring resources
delete_monitoring_resources() {
    log "Cleaning up monitoring resources..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY RUN] Would delete monitoring dashboards and alert policies"
        return 0
    fi
    
    # Delete dashboards with "AI Training" in the name
    log "Searching for AI Training dashboards..."
    local dashboards
    dashboards=$(gcloud monitoring dashboards list \
        --filter="displayName:('AI Training')" \
        --format="value(name)" 2>/dev/null || true)
    
    if [[ -n "$dashboards" ]]; then
        while IFS= read -r dashboard; do
            if [[ -n "$dashboard" ]]; then
                log "Deleting dashboard: $dashboard"
                if gcloud monitoring dashboards delete "$dashboard" --quiet; then
                    success "Dashboard deleted: $dashboard"
                else
                    warning "Failed to delete dashboard: $dashboard"
                fi
            fi
        done <<< "$dashboards"
    else
        info "No AI Training dashboards found"
    fi
    
    # Delete alert policies with "AI Training" in the name
    log "Searching for AI Training alert policies..."
    local policies
    policies=$(gcloud alpha monitoring policies list \
        --filter="displayName:('AI Training')" \
        --format="value(name)" 2>/dev/null || true)
    
    if [[ -n "$policies" ]]; then
        while IFS= read -r policy; do
            if [[ -n "$policy" ]]; then
                log "Deleting alert policy: $policy"
                if gcloud alpha monitoring policies delete "$policy" --quiet; then
                    success "Alert policy deleted: $policy"
                else
                    warning "Failed to delete alert policy: $policy"
                fi
            fi
        done <<< "$policies"
    else
        info "No AI Training alert policies found"
    fi
    
    success "Monitoring resources cleanup completed"
}

# Clean up local files
cleanup_local_files() {
    log "Cleaning up local files..."
    
    local files_to_clean=(
        "deployment-config-${RANDOM_SUFFIX}.env"
        "training_script.py"
        "batch-job.json"
        "dashboard-config.json"
        "alert-policy.json"
        "cost-query.sql"
        "training_logs.txt"
    )
    
    for file in "${files_to_clean[@]}"; do
        if [[ -f "$file" ]]; then
            if [[ "$DRY_RUN" == "true" ]]; then
                info "[DRY RUN] Would delete local file: $file"
            else
                rm -f "$file"
                success "Deleted local file: $file"
            fi
        fi
    done
    
    success "Local files cleanup completed"
}

# Verify cleanup completion
verify_cleanup() {
    log "Verifying cleanup completion..."
    
    local cleanup_issues=0
    
    # Check batch job
    if gcloud batch jobs describe "$JOB_NAME" --location="$REGION" &>/dev/null; then
        warning "Batch job still exists: $JOB_NAME"
        cleanup_issues=$((cleanup_issues + 1))
    fi
    
    # Check instance template
    if gcloud compute instance-templates describe "$TEMPLATE_NAME" &>/dev/null; then
        warning "Instance template still exists: $TEMPLATE_NAME"
        cleanup_issues=$((cleanup_issues + 1))
    fi
    
    # Check storage bucket
    if gsutil ls "gs://$BUCKET_NAME" &>/dev/null; then
        warning "Storage bucket still exists: gs://$BUCKET_NAME"
        cleanup_issues=$((cleanup_issues + 1))
    fi
    
    # Check service account
    if gcloud iam service-accounts describe "$SERVICE_ACCOUNT" &>/dev/null; then
        warning "Service account still exists: $SERVICE_ACCOUNT"
        cleanup_issues=$((cleanup_issues + 1))
    fi
    
    if [[ $cleanup_issues -eq 0 ]]; then
        success "All resources have been successfully deleted"
    else
        warning "$cleanup_issues resource(s) may still exist. Manual cleanup may be required."
    fi
    
    return $cleanup_issues
}

# Display cleanup summary
display_summary() {
    log "Cleanup Summary"
    echo "======================================================"
    echo "Recipe: $RECIPE_NAME"
    echo "Project ID: $PROJECT_ID"
    echo "Region: $REGION"
    echo "Random Suffix: $RANDOM_SUFFIX"
    echo "======================================================"
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "DRY RUN COMPLETED - No resources were actually deleted"
    else
        echo "Resources Deleted:"
        echo "  • Batch Job: $JOB_NAME"
        echo "  • Instance Template: $TEMPLATE_NAME"
        echo "  • Storage Bucket: gs://$BUCKET_NAME"
        echo "  • Service Account: $SERVICE_ACCOUNT"
        echo "  • Monitoring dashboards and alert policies"
        echo "  • Local configuration files"
    fi
    echo "======================================================"
}

# Main cleanup function
main() {
    log "Starting AI Training Optimization cleanup..."
    
    load_config
    prompt_for_config
    check_prerequisites
    confirm_deletion
    
    delete_batch_job
    delete_instance_template
    delete_storage_bucket
    delete_service_account
    delete_monitoring_resources
    cleanup_local_files
    
    if [[ "$DRY_RUN" != "true" ]]; then
        verify_cleanup
    fi
    
    display_summary
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "Dry run completed - run without --dry-run to perform actual cleanup"
    else
        success "Cleanup completed successfully!"
        log "Total cleanup time: $((SECONDS / 60)) minutes and $((SECONDS % 60)) seconds"
    fi
}

# Handle script interruption
cleanup_on_exit() {
    local exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        error "Cleanup script interrupted or failed with exit code $exit_code"
        log "Some resources may not have been deleted. Please check manually."
    fi
    exit $exit_code
}

trap cleanup_on_exit EXIT

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --config)
            CONFIG_FILE="$2"
            shift 2
            ;;
        --project-id)
            PROJECT_ID="$2"
            shift 2
            ;;
        --region)
            REGION="$2"
            shift 2
            ;;
        --random-suffix)
            RANDOM_SUFFIX="$2"
            shift 2
            ;;
        --force)
            FORCE_DELETE=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo "Options:"
            echo "  --config FILE              Load configuration from file"
            echo "  --project-id PROJECT_ID    Google Cloud Project ID"
            echo "  --region REGION            Deployment region"
            echo "  --random-suffix SUFFIX     Random suffix used during deployment"
            echo "  --force                    Skip confirmation prompt"
            echo "  --dry-run                  Show what would be deleted without deleting"
            echo "  --help, -h                 Show this help message"
            echo ""
            echo "Examples:"
            echo "  $0 --config deployment-config-abc123.env"
            echo "  $0 --project-id my-project --random-suffix abc123"
            echo "  $0 --dry-run --config deployment-config-abc123.env"
            exit 0
            ;;
        *)
            error "Unknown option: $1"
            ;;
    esac
done

# Execute main function
main "$@"