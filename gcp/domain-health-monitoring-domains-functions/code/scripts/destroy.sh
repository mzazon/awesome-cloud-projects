#!/bin/bash

# Destroy script for Domain Health Monitoring with Cloud Domains and Cloud Functions
# This script safely removes all infrastructure created for the domain health monitoring solution

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "gcloud CLI is not installed. Please install Google Cloud SDK."
        exit 1
    fi
    
    # Check if gcloud is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        log_error "gcloud is not authenticated. Please run 'gcloud auth login'."
        exit 1
    fi
    
    # Check if gsutil is available
    if ! command -v gsutil &> /dev/null; then
        log_error "gsutil is not available. Please install Google Cloud SDK with gsutil."
        exit 1
    fi
    
    log_success "Prerequisites check completed"
}

# Function to load environment variables
load_environment() {
    log_info "Loading environment variables..."
    
    # Set default values or use existing environment variables
    export PROJECT_ID="${PROJECT_ID:-$(gcloud config get-value project)}"
    export REGION="${REGION:-us-central1}"
    export ZONE="${ZONE:-us-central1-a}"
    
    # Try to load from deployment if available
    if [[ -f ".env" ]]; then
        log_info "Loading environment from .env file..."
        source .env
    fi
    
    # Generate resource names based on pattern or use provided values
    if [[ -z "${RANDOM_SUFFIX:-}" ]]; then
        log_warning "RANDOM_SUFFIX not provided. Will attempt to find resources by pattern."
        export RANDOM_SUFFIX="*"
    fi
    
    export FUNCTION_NAME="${FUNCTION_NAME:-domain-health-monitor-${RANDOM_SUFFIX}}"
    export BUCKET_NAME="${BUCKET_NAME:-domain-monitor-storage-${RANDOM_SUFFIX}}"
    export TOPIC_NAME="${TOPIC_NAME:-domain-alerts-${RANDOM_SUFFIX}}"
    export SCHEDULER_JOB_NAME="${SCHEDULER_JOB_NAME:-domain-monitor-schedule}"
    
    # Set gcloud defaults
    gcloud config set project "${PROJECT_ID}" --quiet
    gcloud config set compute/region "${REGION}" --quiet
    gcloud config set compute/zone "${ZONE}" --quiet
    
    log_success "Environment variables loaded"
    log_info "Project ID: ${PROJECT_ID}"
    log_info "Region: ${REGION}"
}

# Function to confirm destruction
confirm_destruction() {
    log_warning "This will permanently delete the following resources:"
    echo "  - Cloud Function: ${FUNCTION_NAME}"
    echo "  - Cloud Storage Bucket: ${BUCKET_NAME} (and all contents)"
    echo "  - Pub/Sub Topic: ${TOPIC_NAME}"
    echo "  - Cloud Scheduler Job: ${SCHEDULER_JOB_NAME}"
    echo "  - Monitoring Alert Policies"
    echo "  - Notification Channels"
    echo ""
    
    if [[ "${FORCE_DESTROY:-false}" == "true" ]]; then
        log_warning "FORCE_DESTROY is set to true, skipping confirmation"
        return 0
    fi
    
    read -p "Are you sure you want to proceed? (yes/no): " -r
    echo
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        log_info "Operation cancelled by user"
        exit 0
    fi
    
    log_info "Proceeding with resource destruction..."
}

# Function to delete Cloud Scheduler job
delete_scheduler_job() {
    log_info "Deleting Cloud Scheduler job..."
    
    # Handle wildcard pattern for RANDOM_SUFFIX
    if [[ "${RANDOM_SUFFIX}" == "*" ]]; then
        local jobs=$(gcloud scheduler jobs list --location="${REGION}" \
            --filter="name:domain-monitor-schedule*" \
            --format="value(name)" 2>/dev/null || echo "")
        
        if [[ -n "$jobs" ]]; then
            while IFS= read -r job_name; do
                local job_id=$(basename "$job_name")
                log_info "Found scheduler job: $job_id"
                if gcloud scheduler jobs delete "$job_id" --location="${REGION}" --quiet; then
                    log_success "Deleted scheduler job: $job_id"
                else
                    log_warning "Failed to delete scheduler job: $job_id"
                fi
            done <<< "$jobs"
        else
            log_info "No scheduler jobs found matching pattern"
        fi
    else
        # Delete specific scheduler job
        if gcloud scheduler jobs describe "${SCHEDULER_JOB_NAME}" --location="${REGION}" &>/dev/null; then
            if gcloud scheduler jobs delete "${SCHEDULER_JOB_NAME}" --location="${REGION}" --quiet; then
                log_success "Deleted Cloud Scheduler job: ${SCHEDULER_JOB_NAME}"
            else
                log_error "Failed to delete Cloud Scheduler job: ${SCHEDULER_JOB_NAME}"
            fi
        else
            log_info "Cloud Scheduler job not found: ${SCHEDULER_JOB_NAME}"
        fi
    fi
}

# Function to delete Cloud Function
delete_cloud_function() {
    log_info "Deleting Cloud Function..."
    
    # Handle wildcard pattern for RANDOM_SUFFIX
    if [[ "${RANDOM_SUFFIX}" == "*" ]]; then
        local functions=$(gcloud functions list --regions="${REGION}" \
            --filter="name:domain-health-monitor-*" \
            --format="value(name)" 2>/dev/null || echo "")
        
        if [[ -n "$functions" ]]; then
            while IFS= read -r function_name; do
                local function_id=$(basename "$function_name")
                log_info "Found function: $function_id"
                if gcloud functions delete "$function_id" --region="${REGION}" --quiet; then
                    log_success "Deleted function: $function_id"
                else
                    log_warning "Failed to delete function: $function_id"
                fi
            done <<< "$functions"
        else
            log_info "No functions found matching pattern"
        fi
    else
        # Delete specific function
        if gcloud functions describe "${FUNCTION_NAME}" --region="${REGION}" &>/dev/null; then
            if gcloud functions delete "${FUNCTION_NAME}" --region="${REGION}" --quiet; then
                log_success "Deleted Cloud Function: ${FUNCTION_NAME}"
            else
                log_error "Failed to delete Cloud Function: ${FUNCTION_NAME}"
            fi
        else
            log_info "Cloud Function not found: ${FUNCTION_NAME}"
        fi
    fi
}

# Function to delete monitoring resources
delete_monitoring_resources() {
    log_info "Deleting Cloud Monitoring resources..."
    
    # Delete alerting policies
    log_info "Deleting alerting policies..."
    if [[ "${RANDOM_SUFFIX}" == "*" ]]; then
        local policies=$(gcloud alpha monitoring policies list \
            --filter="displayName:('Domain Health Alert Policy')" \
            --format="value(name)" 2>/dev/null || echo "")
        
        if [[ -n "$policies" ]]; then
            while IFS= read -r policy_name; do
                if [[ -n "$policy_name" ]]; then
                    log_info "Found alert policy: $(basename $policy_name)"
                    if gcloud alpha monitoring policies delete "$policy_name" --quiet; then
                        log_success "Deleted alert policy: $(basename $policy_name)"
                    else
                        log_warning "Failed to delete alert policy: $(basename $policy_name)"
                    fi
                fi
            done <<< "$policies"
        else
            log_info "No alert policies found"
        fi
    else
        local policy_filter="displayName:'Domain Health Alert Policy - ${RANDOM_SUFFIX}'"
        local policy_id=$(gcloud alpha monitoring policies list \
            --filter="$policy_filter" \
            --format="value(name)" 2>/dev/null || echo "")
        
        if [[ -n "$policy_id" ]]; then
            if gcloud alpha monitoring policies delete "$policy_id" --quiet; then
                log_success "Deleted alert policy"
            else
                log_warning "Failed to delete alert policy"
            fi
        else
            log_info "No alert policy found with suffix: ${RANDOM_SUFFIX}"
        fi
    fi
    
    # Delete notification channels
    log_info "Deleting notification channels..."
    if [[ "${RANDOM_SUFFIX}" == "*" ]]; then
        local channels=$(gcloud alpha monitoring channels list \
            --filter="displayName:('Domain Alerts Email')" \
            --format="value(name)" 2>/dev/null || echo "")
        
        if [[ -n "$channels" ]]; then
            while IFS= read -r channel_name; do
                if [[ -n "$channel_name" ]]; then
                    log_info "Found notification channel: $(basename $channel_name)"
                    if gcloud alpha monitoring channels delete "$channel_name" --quiet; then
                        log_success "Deleted notification channel: $(basename $channel_name)"
                    else
                        log_warning "Failed to delete notification channel: $(basename $channel_name)"
                    fi
                fi
            done <<< "$channels"
        else
            log_info "No notification channels found"
        fi
    else
        local channel_filter="displayName:'Domain Alerts Email - ${RANDOM_SUFFIX}'"
        local channel_id=$(gcloud alpha monitoring channels list \
            --filter="$channel_filter" \
            --format="value(name)" 2>/dev/null || echo "")
        
        if [[ -n "$channel_id" ]]; then
            if gcloud alpha monitoring channels delete "$channel_id" --quiet; then
                log_success "Deleted notification channel"
            else
                log_warning "Failed to delete notification channel"
            fi
        else
            log_info "No notification channel found with suffix: ${RANDOM_SUFFIX}"
        fi
    fi
}

# Function to delete Pub/Sub resources
delete_pubsub_resources() {
    log_info "Deleting Pub/Sub resources..."
    
    # Handle wildcard pattern for RANDOM_SUFFIX
    if [[ "${RANDOM_SUFFIX}" == "*" ]]; then
        # Delete subscriptions first
        local subscriptions=$(gcloud pubsub subscriptions list \
            --filter="name:domain-alerts-*-sub" \
            --format="value(name)" 2>/dev/null || echo "")
        
        if [[ -n "$subscriptions" ]]; then
            while IFS= read -r subscription_name; do
                local subscription_id=$(basename "$subscription_name")
                log_info "Found subscription: $subscription_id"
                if gcloud pubsub subscriptions delete "$subscription_id" --quiet; then
                    log_success "Deleted subscription: $subscription_id"
                else
                    log_warning "Failed to delete subscription: $subscription_id"
                fi
            done <<< "$subscriptions"
        fi
        
        # Delete topics
        local topics=$(gcloud pubsub topics list \
            --filter="name:domain-alerts-*" \
            --format="value(name)" 2>/dev/null || echo "")
        
        if [[ -n "$topics" ]]; then
            while IFS= read -r topic_name; do
                local topic_id=$(basename "$topic_name")
                log_info "Found topic: $topic_id"
                if gcloud pubsub topics delete "$topic_id" --quiet; then
                    log_success "Deleted topic: $topic_id"
                else
                    log_warning "Failed to delete topic: $topic_id"
                fi
            done <<< "$topics"
        fi
    else
        # Delete specific subscription first
        local subscription_name="${TOPIC_NAME}-sub"
        if gcloud pubsub subscriptions describe "$subscription_name" &>/dev/null; then
            if gcloud pubsub subscriptions delete "$subscription_name" --quiet; then
                log_success "Deleted Pub/Sub subscription: $subscription_name"
            else
                log_error "Failed to delete Pub/Sub subscription: $subscription_name"
            fi
        else
            log_info "Pub/Sub subscription not found: $subscription_name"
        fi
        
        # Delete topic
        if gcloud pubsub topics describe "${TOPIC_NAME}" &>/dev/null; then
            if gcloud pubsub topics delete "${TOPIC_NAME}" --quiet; then
                log_success "Deleted Pub/Sub topic: ${TOPIC_NAME}"
            else
                log_error "Failed to delete Pub/Sub topic: ${TOPIC_NAME}"
            fi
        else
            log_info "Pub/Sub topic not found: ${TOPIC_NAME}"
        fi
    fi
}

# Function to delete Cloud Storage bucket
delete_storage_bucket() {
    log_info "Deleting Cloud Storage bucket and contents..."
    
    # Handle wildcard pattern for RANDOM_SUFFIX
    if [[ "${RANDOM_SUFFIX}" == "*" ]]; then
        local buckets=$(gsutil ls -p "${PROJECT_ID}" | grep "domain-monitor-storage-" | sed 's|gs://||' | sed 's|/||' 2>/dev/null || echo "")
        
        if [[ -n "$buckets" ]]; then
            while IFS= read -r bucket_name; do
                if [[ -n "$bucket_name" ]]; then
                    log_info "Found bucket: $bucket_name"
                    if gsutil -m rm -r "gs://$bucket_name" 2>/dev/null; then
                        log_success "Deleted bucket and contents: $bucket_name"
                    else
                        log_warning "Failed to delete bucket: $bucket_name"
                    fi
                fi
            done <<< "$buckets"
        else
            log_info "No storage buckets found matching pattern"
        fi
    else
        # Delete specific bucket
        if gsutil ls -b "gs://${BUCKET_NAME}" &>/dev/null; then
            log_info "Removing all contents from bucket: ${BUCKET_NAME}"
            if gsutil -m rm -r "gs://${BUCKET_NAME}"; then
                log_success "Deleted Cloud Storage bucket and contents: ${BUCKET_NAME}"
            else
                log_error "Failed to delete Cloud Storage bucket: ${BUCKET_NAME}"
            fi
        else
            log_info "Cloud Storage bucket not found: ${BUCKET_NAME}"
        fi
    fi
}

# Function to clean up local files
cleanup_local_files() {
    log_info "Cleaning up local files..."
    
    # Remove function source directory
    if [[ -d "domain-monitor-function" ]]; then
        rm -rf domain-monitor-function
        log_success "Removed local function directory"
    fi
    
    # Remove temporary files
    local temp_files=("alert-policy.json" ".env")
    for file in "${temp_files[@]}"; do
        if [[ -f "$file" ]]; then
            rm -f "$file"
            log_success "Removed temporary file: $file"
        fi
    done
    
    log_success "Local cleanup completed"
}

# Function to save environment for potential recovery
save_environment() {
    if [[ "${RANDOM_SUFFIX}" != "*" ]] && [[ "${SAVE_ENV:-false}" == "true" ]]; then
        log_info "Saving environment variables for potential recovery..."
        
        cat > .env.backup << EOF
# Environment variables from destroyed deployment
# Use these values if you need to recreate resources with the same names
export PROJECT_ID="${PROJECT_ID}"
export REGION="${REGION}"
export ZONE="${ZONE}"
export RANDOM_SUFFIX="${RANDOM_SUFFIX}"
export FUNCTION_NAME="${FUNCTION_NAME}"
export BUCKET_NAME="${BUCKET_NAME}"
export TOPIC_NAME="${TOPIC_NAME}"
export SCHEDULER_JOB_NAME="${SCHEDULER_JOB_NAME}"
EOF
        
        log_success "Environment variables saved to .env.backup"
    fi
}

# Function to validate destruction
validate_destruction() {
    log_info "Validating resource destruction..."
    
    local errors=0
    
    # Check Cloud Function
    if [[ "${RANDOM_SUFFIX}" != "*" ]]; then
        if gcloud functions describe "${FUNCTION_NAME}" --region="${REGION}" &>/dev/null; then
            log_error "Cloud Function still exists: ${FUNCTION_NAME}"
            ((errors++))
        else
            log_success "Cloud Function successfully deleted"
        fi
        
        # Check Cloud Storage bucket
        if gsutil ls -b "gs://${BUCKET_NAME}" &>/dev/null; then
            log_error "Cloud Storage bucket still exists: ${BUCKET_NAME}"
            ((errors++))
        else
            log_success "Cloud Storage bucket successfully deleted"
        fi
        
        # Check Pub/Sub topic
        if gcloud pubsub topics describe "${TOPIC_NAME}" &>/dev/null; then
            log_error "Pub/Sub topic still exists: ${TOPIC_NAME}"
            ((errors++))
        else
            log_success "Pub/Sub topic successfully deleted"
        fi
        
        # Check Cloud Scheduler job
        if gcloud scheduler jobs describe "${SCHEDULER_JOB_NAME}" --location="${REGION}" &>/dev/null; then
            log_error "Cloud Scheduler job still exists: ${SCHEDULER_JOB_NAME}"
            ((errors++))
        else
            log_success "Cloud Scheduler job successfully deleted"
        fi
    else
        log_info "Wildcard pattern used - skipping specific resource validation"
    fi
    
    if [[ $errors -eq 0 ]]; then
        log_success "All resources successfully destroyed"
    else
        log_warning "$errors resources may still exist. Please check manually."
    fi
    
    return $errors
}

# Function to display destruction summary
display_summary() {
    log_success "=== Destruction Summary ==="
    echo "Project ID: ${PROJECT_ID}"
    echo "Region: ${REGION}"
    echo ""
    echo "Destroyed resources:"
    echo "✓ Cloud Function: ${FUNCTION_NAME}"
    echo "✓ Cloud Storage Bucket: ${BUCKET_NAME}"
    echo "✓ Pub/Sub Topic: ${TOPIC_NAME}"
    echo "✓ Cloud Scheduler Job: ${SCHEDULER_JOB_NAME}"
    echo "✓ Monitoring Alert Policies"
    echo "✓ Notification Channels"
    echo ""
    
    if [[ -f ".env.backup" ]]; then
        echo "Environment backup saved to: .env.backup"
        echo ""
    fi
    
    echo "Note: Some Google Cloud APIs remain enabled."
    echo "You can disable them manually if no longer needed:"
    echo "  gcloud services disable cloudfunctions.googleapis.com"
    echo "  gcloud services disable cloudscheduler.googleapis.com"
    echo "  gcloud services disable monitoring.googleapis.com"
    echo "  gcloud services disable domains.googleapis.com"
    echo "  gcloud services disable storage.googleapis.com"
    echo "  gcloud services disable pubsub.googleapis.com"
}

# Main destruction function
main() {
    log_info "Starting Domain Health Monitoring destruction..."
    
    check_prerequisites
    load_environment
    confirm_destruction
    save_environment
    
    # Delete resources in reverse order of creation
    delete_scheduler_job
    delete_cloud_function
    delete_monitoring_resources
    delete_pubsub_resources
    delete_storage_bucket
    cleanup_local_files
    
    validate_destruction
    display_summary
    
    log_success "Domain Health Monitoring destruction completed!"
}

# Handle script interruption
trap 'log_error "Script interrupted"; exit 1' INT TERM

# Check if script is being sourced or executed
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi