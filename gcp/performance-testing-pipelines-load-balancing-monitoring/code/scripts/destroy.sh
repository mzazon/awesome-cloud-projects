#!/bin/bash

# Performance Testing Pipelines Cleanup Script
# Removes all resources created by the deployment script

set -euo pipefail

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Configuration variables
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly DEPLOYMENT_INFO_FILE="${SCRIPT_DIR}/../deployment-info.json"

# Global variables for resource information
PROJECT_ID=""
REGION=""
ZONE=""
BUCKET_NAME=""
FUNCTION_NAME=""
SERVICE_ACCOUNT_EMAIL=""
INSTANCE_TEMPLATE=""
INSTANCE_GROUP=""
HEALTH_CHECK=""
BACKEND_SERVICE=""
URL_MAP=""
HTTP_PROXY=""
FORWARDING_RULE=""
FIREWALL_RULE=""
DAILY_JOB=""
HOURLY_JOB=""
DASHBOARD_ID=""

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "Google Cloud SDK (gcloud) is not installed. Please install it first."
        exit 1
    fi
    
    # Check if user is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q "@"; then
        log_error "Not authenticated with Google Cloud. Run 'gcloud auth login' first."
        exit 1
    fi
    
    # Check if jq is installed for JSON processing
    if ! command -v jq &> /dev/null; then
        log_error "jq is required for parsing deployment information. Please install it."
        exit 1
    fi
    
    log_info "Prerequisites check completed successfully"
}

# Function to load deployment information
load_deployment_info() {
    log_info "Loading deployment information..."
    
    if [[ ! -f "${DEPLOYMENT_INFO_FILE}" ]]; then
        log_warn "Deployment info file not found: ${DEPLOYMENT_INFO_FILE}"
        log_warn "You may need to manually specify resource names or use interactive mode"
        return 1
    fi
    
    # Parse deployment information from JSON file
    PROJECT_ID=$(jq -r '.project_id // empty' "${DEPLOYMENT_INFO_FILE}")
    REGION=$(jq -r '.region // empty' "${DEPLOYMENT_INFO_FILE}")
    ZONE=$(jq -r '.zone // empty' "${DEPLOYMENT_INFO_FILE}")
    BUCKET_NAME=$(jq -r '.bucket_name // empty' "${DEPLOYMENT_INFO_FILE}")
    DASHBOARD_ID=$(jq -r '.dashboard_id // empty' "${DEPLOYMENT_INFO_FILE}")
    
    # Load resource names
    FUNCTION_NAME=$(jq -r '.resources.function_name // empty' "${DEPLOYMENT_INFO_FILE}")
    SERVICE_ACCOUNT_EMAIL=$(jq -r '.resources.service_account // empty' "${DEPLOYMENT_INFO_FILE}")
    INSTANCE_TEMPLATE=$(jq -r '.resources.instance_template // empty' "${DEPLOYMENT_INFO_FILE}")
    INSTANCE_GROUP=$(jq -r '.resources.instance_group // empty' "${DEPLOYMENT_INFO_FILE}")
    HEALTH_CHECK=$(jq -r '.resources.health_check // empty' "${DEPLOYMENT_INFO_FILE}")
    BACKEND_SERVICE=$(jq -r '.resources.backend_service // empty' "${DEPLOYMENT_INFO_FILE}")
    URL_MAP=$(jq -r '.resources.url_map // empty' "${DEPLOYMENT_INFO_FILE}")
    HTTP_PROXY=$(jq -r '.resources.http_proxy // empty' "${DEPLOYMENT_INFO_FILE}")
    FORWARDING_RULE=$(jq -r '.resources.forwarding_rule // empty' "${DEPLOYMENT_INFO_FILE}")
    FIREWALL_RULE=$(jq -r '.resources.firewall_rule // empty' "${DEPLOYMENT_INFO_FILE}")
    DAILY_JOB=$(jq -r '.resources.daily_job // empty' "${DEPLOYMENT_INFO_FILE}")
    HOURLY_JOB=$(jq -r '.resources.hourly_job // empty' "${DEPLOYMENT_INFO_FILE}")
    
    # Validate required information
    if [[ -z "${PROJECT_ID}" ]]; then
        log_error "Project ID not found in deployment info"
        return 1
    fi
    
    log_info "Deployment information loaded successfully"
    log_info "Project ID: ${PROJECT_ID}"
    log_info "Region: ${REGION}"
    log_info "Zone: ${ZONE}"
    
    return 0
}

# Function to prompt for manual input if deployment info is missing
prompt_manual_input() {
    log_warn "Some deployment information is missing. Manual input required."
    
    if [[ -z "${PROJECT_ID}" ]]; then
        read -p "Enter Project ID: " PROJECT_ID
        if [[ -z "${PROJECT_ID}" ]]; then
            log_error "Project ID is required"
            exit 1
        fi
    fi
    
    if [[ -z "${REGION}" ]]; then
        read -p "Enter Region (default: us-central1): " REGION
        REGION=${REGION:-us-central1}
    fi
    
    if [[ -z "${ZONE}" ]]; then
        read -p "Enter Zone (default: us-central1-a): " ZONE
        ZONE=${ZONE:-us-central1-a}
    fi
}

# Function to configure gcloud
configure_gcloud() {
    log_info "Configuring Google Cloud project..."
    
    # Set default project and region
    gcloud config set project "${PROJECT_ID}"
    gcloud config set compute/region "${REGION}"
    gcloud config set compute/zone "${ZONE}"
    
    log_info "Google Cloud configuration completed"
}

# Function to confirm destructive action
confirm_destruction() {
    echo
    log_warn "This script will permanently delete the following resources:"
    echo "  - Project: ${PROJECT_ID}"
    echo "  - Cloud Functions: ${FUNCTION_NAME:-'<auto-detected>'}"
    echo "  - Storage Bucket: ${BUCKET_NAME:-'<auto-detected>'}"
    echo "  - Load Balancer and related resources"
    echo "  - Compute instances and instance groups"
    echo "  - Monitoring dashboards and alert policies"
    echo "  - Cloud Scheduler jobs"
    echo "  - Service account: ${SERVICE_ACCOUNT_EMAIL:-'<auto-detected>'}"
    echo
    
    read -p "Are you sure you want to proceed? (yes/NO): " confirm
    if [[ "${confirm}" != "yes" ]]; then
        log_info "Cleanup cancelled by user"
        exit 0
    fi
    
    log_warn "Proceeding with resource cleanup..."
}

# Function to delete Cloud Scheduler jobs
delete_scheduler_jobs() {
    log_info "Deleting Cloud Scheduler jobs..."
    
    # Delete jobs by name if we have them
    if [[ -n "${DAILY_JOB}" ]]; then
        log_info "Deleting daily job: ${DAILY_JOB}"
        if gcloud scheduler jobs delete "${DAILY_JOB}" --quiet 2>/dev/null; then
            log_info "✅ Deleted daily job: ${DAILY_JOB}"
        else
            log_warn "Failed to delete daily job or job doesn't exist: ${DAILY_JOB}"
        fi
    fi
    
    if [[ -n "${HOURLY_JOB}" ]]; then
        log_info "Deleting hourly job: ${HOURLY_JOB}"
        if gcloud scheduler jobs delete "${HOURLY_JOB}" --quiet 2>/dev/null; then
            log_info "✅ Deleted hourly job: ${HOURLY_JOB}"
        else
            log_warn "Failed to delete hourly job or job doesn't exist: ${HOURLY_JOB}"
        fi
    fi
    
    # Auto-detect and delete any remaining perf-test jobs
    log_info "Checking for additional performance test jobs..."
    local remaining_jobs
    remaining_jobs=$(gcloud scheduler jobs list --format="value(name)" --filter="name:perf-test" 2>/dev/null || true)
    
    if [[ -n "${remaining_jobs}" ]]; then
        while IFS= read -r job; do
            if [[ -n "${job}" ]]; then
                log_info "Deleting auto-detected job: ${job}"
                gcloud scheduler jobs delete "${job}" --quiet 2>/dev/null || log_warn "Failed to delete job: ${job}"
            fi
        done <<< "${remaining_jobs}"
    fi
    
    log_info "Cloud Scheduler jobs cleanup completed"
}

# Function to delete load balancer components
delete_load_balancer() {
    log_info "Deleting load balancer components..."
    
    # Delete forwarding rule
    if [[ -n "${FORWARDING_RULE}" ]]; then
        log_info "Deleting forwarding rule: ${FORWARDING_RULE}"
        if gcloud compute forwarding-rules delete "${FORWARDING_RULE}" --global --quiet 2>/dev/null; then
            log_info "✅ Deleted forwarding rule: ${FORWARDING_RULE}"
        else
            log_warn "Failed to delete forwarding rule or rule doesn't exist: ${FORWARDING_RULE}"
        fi
    fi
    
    # Delete HTTP proxy
    if [[ -n "${HTTP_PROXY}" ]]; then
        log_info "Deleting HTTP proxy: ${HTTP_PROXY}"
        if gcloud compute target-http-proxies delete "${HTTP_PROXY}" --quiet 2>/dev/null; then
            log_info "✅ Deleted HTTP proxy: ${HTTP_PROXY}"
        else
            log_warn "Failed to delete HTTP proxy or proxy doesn't exist: ${HTTP_PROXY}"
        fi
    fi
    
    # Delete URL map
    if [[ -n "${URL_MAP}" ]]; then
        log_info "Deleting URL map: ${URL_MAP}"
        if gcloud compute url-maps delete "${URL_MAP}" --quiet 2>/dev/null; then
            log_info "✅ Deleted URL map: ${URL_MAP}"
        else
            log_warn "Failed to delete URL map or map doesn't exist: ${URL_MAP}"
        fi
    fi
    
    # Delete backend service
    if [[ -n "${BACKEND_SERVICE}" ]]; then
        log_info "Deleting backend service: ${BACKEND_SERVICE}"
        if gcloud compute backend-services delete "${BACKEND_SERVICE}" --global --quiet 2>/dev/null; then
            log_info "✅ Deleted backend service: ${BACKEND_SERVICE}"
        else
            log_warn "Failed to delete backend service or service doesn't exist: ${BACKEND_SERVICE}"
        fi
    fi
    
    # Delete health check
    if [[ -n "${HEALTH_CHECK}" ]]; then
        log_info "Deleting health check: ${HEALTH_CHECK}"
        if gcloud compute health-checks delete "${HEALTH_CHECK}" --quiet 2>/dev/null; then
            log_info "✅ Deleted health check: ${HEALTH_CHECK}"
        else
            log_warn "Failed to delete health check or check doesn't exist: ${HEALTH_CHECK}"
        fi
    fi
    
    log_info "Load balancer components cleanup completed"
}

# Function to delete compute resources
delete_compute_resources() {
    log_info "Deleting compute resources..."
    
    # Delete managed instance group
    if [[ -n "${INSTANCE_GROUP}" && -n "${ZONE}" ]]; then
        log_info "Deleting managed instance group: ${INSTANCE_GROUP}"
        if gcloud compute instance-groups managed delete "${INSTANCE_GROUP}" --zone="${ZONE}" --quiet 2>/dev/null; then
            log_info "✅ Deleted instance group: ${INSTANCE_GROUP}"
        else
            log_warn "Failed to delete instance group or group doesn't exist: ${INSTANCE_GROUP}"
        fi
    fi
    
    # Delete instance template
    if [[ -n "${INSTANCE_TEMPLATE}" ]]; then
        log_info "Deleting instance template: ${INSTANCE_TEMPLATE}"
        if gcloud compute instance-templates delete "${INSTANCE_TEMPLATE}" --quiet 2>/dev/null; then
            log_info "✅ Deleted instance template: ${INSTANCE_TEMPLATE}"
        else
            log_warn "Failed to delete instance template or template doesn't exist: ${INSTANCE_TEMPLATE}"
        fi
    fi
    
    # Delete firewall rule
    if [[ -n "${FIREWALL_RULE}" ]]; then
        log_info "Deleting firewall rule: ${FIREWALL_RULE}"
        if gcloud compute firewall-rules delete "${FIREWALL_RULE}" --quiet 2>/dev/null; then
            log_info "✅ Deleted firewall rule: ${FIREWALL_RULE}"
        else
            log_warn "Failed to delete firewall rule or rule doesn't exist: ${FIREWALL_RULE}"
        fi
    fi
    
    log_info "Compute resources cleanup completed"
}

# Function to delete Cloud Functions
delete_cloud_functions() {
    log_info "Deleting Cloud Functions..."
    
    if [[ -n "${FUNCTION_NAME}" ]]; then
        log_info "Deleting function: ${FUNCTION_NAME}"
        if gcloud functions delete "${FUNCTION_NAME}" --quiet 2>/dev/null; then
            log_info "✅ Deleted function: ${FUNCTION_NAME}"
        else
            log_warn "Failed to delete function or function doesn't exist: ${FUNCTION_NAME}"
        fi
    fi
    
    # Auto-detect and delete any remaining perf-test functions
    log_info "Checking for additional performance test functions..."
    local remaining_functions
    remaining_functions=$(gcloud functions list --format="value(name)" --filter="name:perf-test" 2>/dev/null || true)
    
    if [[ -n "${remaining_functions}" ]]; then
        while IFS= read -r func; do
            if [[ -n "${func}" ]]; then
                log_info "Deleting auto-detected function: ${func}"
                gcloud functions delete "${func}" --quiet 2>/dev/null || log_warn "Failed to delete function: ${func}"
            fi
        done <<< "${remaining_functions}"
    fi
    
    log_info "Cloud Functions cleanup completed"
}

# Function to delete storage resources
delete_storage_resources() {
    log_info "Deleting storage resources..."
    
    if [[ -n "${BUCKET_NAME}" ]]; then
        log_info "Deleting storage bucket: ${BUCKET_NAME}"
        if gsutil ls -b "gs://${BUCKET_NAME}" &>/dev/null; then
            # Remove all objects first
            log_info "Removing all objects from bucket..."
            gsutil -m rm -r "gs://${BUCKET_NAME}/**" 2>/dev/null || true
            
            # Remove bucket
            if gsutil rb "gs://${BUCKET_NAME}" 2>/dev/null; then
                log_info "✅ Deleted storage bucket: ${BUCKET_NAME}"
            else
                log_warn "Failed to delete storage bucket: ${BUCKET_NAME}"
            fi
        else
            log_warn "Storage bucket doesn't exist or not accessible: ${BUCKET_NAME}"
        fi
    fi
    
    # Auto-detect and delete test result buckets
    log_info "Checking for additional test result buckets..."
    local test_buckets
    test_buckets=$(gsutil ls -p "${PROJECT_ID}" 2>/dev/null | grep "test-results" || true)
    
    if [[ -n "${test_buckets}" ]]; then
        while IFS= read -r bucket; do
            if [[ -n "${bucket}" ]]; then
                bucket_name=$(echo "${bucket}" | sed 's|gs://||' | sed 's|/||')
                log_info "Deleting auto-detected bucket: ${bucket_name}"
                gsutil -m rm -r "${bucket}**" 2>/dev/null || true
                gsutil rb "${bucket}" 2>/dev/null || log_warn "Failed to delete bucket: ${bucket_name}"
            fi
        done <<< "${test_buckets}"
    fi
    
    log_info "Storage resources cleanup completed"
}

# Function to delete monitoring resources
delete_monitoring_resources() {
    log_info "Deleting monitoring resources..."
    
    # Delete alert policies
    log_info "Deleting alert policies..."
    local alert_policies
    alert_policies=$(gcloud alpha monitoring policies list \
        --filter="displayName:(Performance Test)" \
        --format="value(name)" 2>/dev/null || true)
    
    if [[ -n "${alert_policies}" ]]; then
        while IFS= read -r policy; do
            if [[ -n "${policy}" ]]; then
                log_info "Deleting alert policy: ${policy}"
                gcloud alpha monitoring policies delete "${policy}" --quiet 2>/dev/null || log_warn "Failed to delete policy: ${policy}"
            fi
        done <<< "${alert_policies}"
    else
        log_info "No performance test alert policies found"
    fi
    
    # Delete dashboard
    if [[ -n "${DASHBOARD_ID}" ]]; then
        log_info "Deleting dashboard: ${DASHBOARD_ID}"
        if gcloud monitoring dashboards delete "${DASHBOARD_ID}" --quiet 2>/dev/null; then
            log_info "✅ Deleted dashboard: ${DASHBOARD_ID}"
        else
            log_warn "Failed to delete dashboard or dashboard doesn't exist: ${DASHBOARD_ID}"
        fi
    fi
    
    # Auto-detect and delete performance testing dashboards
    log_info "Checking for additional performance testing dashboards..."
    local dashboards
    dashboards=$(gcloud monitoring dashboards list \
        --filter="displayName:(Performance Testing)" \
        --format="value(name)" 2>/dev/null || true)
    
    if [[ -n "${dashboards}" ]]; then
        while IFS= read -r dashboard; do
            if [[ -n "${dashboard}" ]]; then
                dashboard_id=$(echo "${dashboard}" | sed 's|.*/||')
                log_info "Deleting auto-detected dashboard: ${dashboard_id}"
                gcloud monitoring dashboards delete "${dashboard_id}" --quiet 2>/dev/null || log_warn "Failed to delete dashboard: ${dashboard_id}"
            fi
        done <<< "${dashboards}"
    fi
    
    log_info "Monitoring resources cleanup completed"
}

# Function to delete service account
delete_service_account() {
    log_info "Deleting service account..."
    
    if [[ -n "${SERVICE_ACCOUNT_EMAIL}" ]]; then
        log_info "Deleting service account: ${SERVICE_ACCOUNT_EMAIL}"
        if gcloud iam service-accounts delete "${SERVICE_ACCOUNT_EMAIL}" --quiet 2>/dev/null; then
            log_info "✅ Deleted service account: ${SERVICE_ACCOUNT_EMAIL}"
        else
            log_warn "Failed to delete service account or account doesn't exist: ${SERVICE_ACCOUNT_EMAIL}"
        fi
    fi
    
    # Auto-detect and delete perf-test service accounts
    log_info "Checking for additional performance test service accounts..."
    local service_accounts
    service_accounts=$(gcloud iam service-accounts list \
        --filter="email:perf-test-sa@${PROJECT_ID}.iam.gserviceaccount.com" \
        --format="value(email)" 2>/dev/null || true)
    
    if [[ -n "${service_accounts}" ]]; then
        while IFS= read -r sa; do
            if [[ -n "${sa}" ]]; then
                log_info "Deleting auto-detected service account: ${sa}"
                gcloud iam service-accounts delete "${sa}" --quiet 2>/dev/null || log_warn "Failed to delete service account: ${sa}"
            fi
        done <<< "${service_accounts}"
    fi
    
    log_info "Service account cleanup completed"
}

# Function to clean up deployment info file
cleanup_deployment_info() {
    log_info "Cleaning up deployment information..."
    
    if [[ -f "${DEPLOYMENT_INFO_FILE}" ]]; then
        rm -f "${DEPLOYMENT_INFO_FILE}"
        log_info "✅ Removed deployment info file"
    fi
}

# Function to display cleanup summary
display_cleanup_summary() {
    log_info "=== Cleanup Summary ==="
    echo
    echo "Project ID: ${PROJECT_ID}"
    echo "Region: ${REGION}"
    echo "Zone: ${ZONE}"
    echo
    echo "The following resource types have been cleaned up:"
    echo "  ✅ Cloud Scheduler jobs"
    echo "  ✅ Load balancer components"
    echo "  ✅ Compute resources (instances, templates, firewall rules)"
    echo "  ✅ Cloud Functions"
    echo "  ✅ Storage buckets and objects"
    echo "  ✅ Monitoring dashboards and alert policies"
    echo "  ✅ Service accounts"
    echo "  ✅ Deployment information files"
    echo
    log_info "Cleanup completed successfully!"
    echo
    log_warn "Note: Some resources may take a few minutes to be fully removed."
    log_warn "Check the Google Cloud Console to verify all resources have been deleted."
}

# Function to handle errors gracefully
handle_error() {
    log_error "An error occurred during cleanup. Some resources may not have been deleted."
    log_error "Please check the Google Cloud Console and manually delete any remaining resources."
    log_error "You can also re-run this script to attempt cleanup again."
    exit 1
}

# Main cleanup function
main() {
    log_info "Starting Performance Testing Pipelines cleanup..."
    
    check_prerequisites
    
    # Try to load deployment info, but continue even if it fails
    if ! load_deployment_info; then
        prompt_manual_input
    fi
    
    configure_gcloud
    confirm_destruction
    
    # Execute cleanup in reverse order of creation
    delete_scheduler_jobs
    delete_load_balancer
    delete_compute_resources
    delete_cloud_functions
    delete_storage_resources
    delete_monitoring_resources
    delete_service_account
    cleanup_deployment_info
    
    display_cleanup_summary
}

# Handle script interruption and errors
trap 'handle_error' ERR
trap 'log_error "Script interrupted"; exit 1' INT TERM

# Run main function
main "$@"