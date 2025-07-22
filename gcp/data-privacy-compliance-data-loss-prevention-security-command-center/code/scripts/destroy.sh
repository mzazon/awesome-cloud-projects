#!/bin/bash

# Destroy script for Data Privacy Compliance with Cloud DLP and Security Command Center
# This script removes all resources created by the deployment script

set -e

# Color codes for output
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
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to load environment variables
load_environment() {
    log "Loading environment variables..."
    
    if [[ -f ".env.deploy" ]]; then
        source .env.deploy
        success "Environment variables loaded from .env.deploy"
    else
        warning ".env.deploy file not found. You may need to provide variables manually."
        
        # Prompt for required variables if not set
        if [[ -z "${PROJECT_ID}" ]]; then
            read -p "Enter Project ID: " PROJECT_ID
            export PROJECT_ID
        fi
        
        if [[ -z "${REGION}" ]]; then
            read -p "Enter Region (default: us-central1): " REGION
            export REGION="${REGION:-us-central1}"
        fi
        
        if [[ -z "${FUNCTION_NAME}" ]]; then
            read -p "Enter Cloud Function name: " FUNCTION_NAME
            export FUNCTION_NAME
        fi
        
        if [[ -z "${TOPIC_NAME}" ]]; then
            read -p "Enter Pub/Sub topic name: " TOPIC_NAME
            export TOPIC_NAME
        fi
        
        if [[ -z "${BUCKET_NAME}" ]]; then
            read -p "Enter Storage bucket name: " BUCKET_NAME
            export BUCKET_NAME
        fi
        
        # Set default values for other variables
        export SERVICE_ACCOUNT_NAME="${SERVICE_ACCOUNT_NAME:-privacy-compliance-sa}"
        export DLP_TEMPLATE_NAME="${DLP_TEMPLATE_NAME:-privacy-compliance-template}"
    fi
    
    log "Using Project ID: ${PROJECT_ID}"
    log "Using Region: ${REGION}"
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        error "gcloud CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if user is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 &> /dev/null; then
        error "No active gcloud authentication found. Please run 'gcloud auth login'"
        exit 1
    fi
    
    # Set gcloud configuration
    gcloud config set project "${PROJECT_ID}" 2>/dev/null || true
    gcloud config set compute/region "${REGION}" 2>/dev/null || true
    
    success "Prerequisites check completed"
}

# Function to confirm destruction
confirm_destruction() {
    log "This will permanently delete the following resources:"
    echo "  - Project: ${PROJECT_ID}"
    echo "  - Cloud Function: ${FUNCTION_NAME}"
    echo "  - Pub/Sub Topic: ${TOPIC_NAME}"
    echo "  - Storage Bucket: ${BUCKET_NAME} (and all contents)"
    echo "  - Service Account: ${SERVICE_ACCOUNT_NAME}"
    echo "  - DLP Inspection Template: ${DLP_TEMPLATE_NAME}"
    echo "  - All monitoring and logging resources"
    echo ""
    
    read -p "Are you sure you want to proceed? (yes/no): " confirm
    if [[ "${confirm,,}" != "yes" ]]; then
        log "Destruction cancelled by user"
        exit 0
    fi
    
    # Additional confirmation for project deletion
    read -p "Do you want to delete the entire project '${PROJECT_ID}'? (yes/no): " delete_project
    if [[ "${delete_project,,}" == "yes" ]]; then
        export DELETE_PROJECT=true
    else
        export DELETE_PROJECT=false
        log "Will delete individual resources but keep the project"
    fi
}

# Function to cancel running DLP jobs
cancel_dlp_jobs() {
    log "Cancelling running DLP jobs..."
    
    # Get list of running jobs
    local running_jobs
    running_jobs=$(gcloud dlp jobs list --location="${REGION}" --filter="state:RUNNING" --format="value(name)" 2>/dev/null || echo "")
    
    if [[ -n "${running_jobs}" ]]; then
        while IFS= read -r job_name; do
            if [[ -n "${job_name}" ]]; then
                log "Cancelling DLP job: ${job_name}"
                gcloud dlp jobs cancel "${job_name}" --quiet 2>/dev/null || warning "Failed to cancel job: ${job_name}"
            fi
        done <<< "${running_jobs}"
        success "DLP jobs cancelled"
    else
        log "No running DLP jobs found"
    fi
    
    # Wait for jobs to finish cancelling
    sleep 10
}

# Function to delete Cloud Function
delete_cloud_function() {
    log "Deleting Cloud Function..."
    
    if gcloud functions describe "${FUNCTION_NAME}" --region="${REGION}" &> /dev/null; then
        if gcloud functions delete "${FUNCTION_NAME}" --region="${REGION}" --quiet; then
            success "Cloud Function deleted: ${FUNCTION_NAME}"
        else
            warning "Failed to delete Cloud Function: ${FUNCTION_NAME}"
        fi
    else
        log "Cloud Function not found: ${FUNCTION_NAME}"
    fi
}

# Function to delete Cloud Scheduler jobs
delete_scheduler_jobs() {
    log "Deleting Cloud Scheduler jobs..."
    
    # Delete privacy scan schedule
    if gcloud scheduler jobs describe privacy-scan-schedule --location="${REGION}" &> /dev/null; then
        if gcloud scheduler jobs delete privacy-scan-schedule --location="${REGION}" --quiet; then
            success "Scheduler job deleted: privacy-scan-schedule"
        else
            warning "Failed to delete scheduler job: privacy-scan-schedule"
        fi
    else
        log "Scheduler job not found: privacy-scan-schedule"
    fi
}

# Function to delete Pub/Sub resources
delete_pubsub() {
    log "Deleting Pub/Sub resources..."
    
    # Delete subscription first
    if gcloud pubsub subscriptions describe "${TOPIC_NAME}-subscription" &> /dev/null; then
        if gcloud pubsub subscriptions delete "${TOPIC_NAME}-subscription" --quiet; then
            success "Pub/Sub subscription deleted"
        else
            warning "Failed to delete Pub/Sub subscription"
        fi
    else
        log "Pub/Sub subscription not found"
    fi
    
    # Delete topic
    if gcloud pubsub topics describe "${TOPIC_NAME}" &> /dev/null; then
        if gcloud pubsub topics delete "${TOPIC_NAME}" --quiet; then
            success "Pub/Sub topic deleted: ${TOPIC_NAME}"
        else
            warning "Failed to delete Pub/Sub topic: ${TOPIC_NAME}"
        fi
    else
        log "Pub/Sub topic not found: ${TOPIC_NAME}"
    fi
}

# Function to delete DLP resources
delete_dlp_resources() {
    log "Deleting DLP resources..."
    
    # Delete DLP inspection template
    if gcloud dlp inspect-templates describe "${DLP_TEMPLATE_NAME}" --location="${REGION}" &> /dev/null; then
        if gcloud dlp inspect-templates delete "projects/${PROJECT_ID}/locations/${REGION}/inspectTemplates/${DLP_TEMPLATE_NAME}" --quiet; then
            success "DLP inspection template deleted"
        else
            warning "Failed to delete DLP inspection template"
        fi
    else
        log "DLP inspection template not found"
    fi
}

# Function to delete monitoring resources
delete_monitoring() {
    log "Deleting monitoring resources..."
    
    # Delete alerting policies
    local policies
    policies=$(gcloud alpha monitoring policies list --filter='displayName:"High Severity Privacy Violations"' --format="value(name)" 2>/dev/null || echo "")
    
    if [[ -n "${policies}" ]]; then
        while IFS= read -r policy_name; do
            if [[ -n "${policy_name}" ]]; then
                log "Deleting alerting policy: ${policy_name}"
                gcloud alpha monitoring policies delete "${policy_name}" --quiet 2>/dev/null || warning "Failed to delete policy: ${policy_name}"
            fi
        done <<< "${policies}"
        success "Alerting policies deleted"
    else
        log "No alerting policies found"
    fi
    
    # Delete logging metrics
    if gcloud logging metrics describe dlp-findings-metric &> /dev/null; then
        if gcloud logging metrics delete dlp-findings-metric --quiet; then
            success "Logging metric deleted"
        else
            warning "Failed to delete logging metric"
        fi
    else
        log "Logging metric not found"
    fi
}

# Function to delete Security Command Center resources
delete_scc_resources() {
    log "Deleting Security Command Center resources..."
    
    # Get organization ID if available
    local org_id
    org_id=$(gcloud organizations list --format="value(name)" --limit=1 2>/dev/null || echo "")
    
    if [[ -n "${org_id}" ]]; then
        # Delete SCC source
        local sources
        sources=$(gcloud scc sources list --organization="${org_id}" --filter='displayName:"Privacy Compliance Scanner"' --format="value(name)" 2>/dev/null || echo "")
        
        if [[ -n "${sources}" ]]; then
            while IFS= read -r source_name; do
                if [[ -n "${source_name}" ]]; then
                    log "Deleting SCC source: ${source_name}"
                    gcloud scc sources delete "${source_name}" --quiet 2>/dev/null || warning "Failed to delete SCC source: ${source_name}"
                fi
            done <<< "${sources}"
            success "SCC sources deleted"
        else
            log "No SCC sources found"
        fi
        
        # Delete SCC notifications
        local notifications
        notifications=$(gcloud scc notifications list --organization="${org_id}" --filter='name:"privacy-critical-alerts"' --format="value(name)" 2>/dev/null || echo "")
        
        if [[ -n "${notifications}" ]]; then
            while IFS= read -r notification_name; do
                if [[ -n "${notification_name}" ]]; then
                    log "Deleting SCC notification: ${notification_name}"
                    gcloud scc notifications delete "${notification_name}" --quiet 2>/dev/null || warning "Failed to delete SCC notification: ${notification_name}"
                fi
            done <<< "${notifications}"
            success "SCC notifications deleted"
        else
            log "No SCC notifications found"
        fi
    else
        log "No organization access found, skipping SCC cleanup"
    fi
}

# Function to delete Storage bucket
delete_storage() {
    log "Deleting Cloud Storage bucket..."
    
    if gsutil ls "gs://${BUCKET_NAME}" &> /dev/null; then
        if gsutil -m rm -r "gs://${BUCKET_NAME}"; then
            success "Storage bucket deleted: ${BUCKET_NAME}"
        else
            warning "Failed to delete storage bucket: ${BUCKET_NAME}"
        fi
    else
        log "Storage bucket not found: ${BUCKET_NAME}"
    fi
}

# Function to delete service account
delete_service_account() {
    log "Deleting service account..."
    
    local sa_email="${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
    
    if gcloud iam service-accounts describe "${sa_email}" &> /dev/null; then
        if gcloud iam service-accounts delete "${sa_email}" --quiet; then
            success "Service account deleted: ${sa_email}"
        else
            warning "Failed to delete service account: ${sa_email}"
        fi
    else
        log "Service account not found: ${sa_email}"
    fi
}

# Function to delete the entire project
delete_project() {
    if [[ "${DELETE_PROJECT}" == "true" ]]; then
        log "Deleting entire project..."
        
        warning "This will permanently delete the project and all its resources!"
        read -p "Type 'DELETE' to confirm project deletion: " final_confirm
        
        if [[ "${final_confirm}" == "DELETE" ]]; then
            if gcloud projects delete "${PROJECT_ID}" --quiet; then
                success "Project deleted: ${PROJECT_ID}"
                log "All resources have been removed"
                return 0
            else
                error "Failed to delete project: ${PROJECT_ID}"
                return 1
            fi
        else
            log "Project deletion cancelled"
            return 1
        fi
    fi
    
    return 1
}

# Function to clean up local files
cleanup_local_files() {
    log "Cleaning up local files..."
    
    # Remove environment file
    if [[ -f ".env.deploy" ]]; then
        rm -f .env.deploy
        success "Environment file removed"
    fi
    
    # Remove any temporary files that might exist
    rm -f dlp-template.json dlp-job.json metric-descriptor.json alert-policy.json sample_data.txt
    rm -rf privacy-function/
    
    success "Local files cleaned up"
}

# Function to validate cleanup
validate_cleanup() {
    log "Validating resource cleanup..."
    
    # Only validate if project still exists
    if gcloud projects describe "${PROJECT_ID}" &> /dev/null; then
        local remaining_resources=0
        
        # Check Cloud Function
        if gcloud functions describe "${FUNCTION_NAME}" --region="${REGION}" &> /dev/null; then
            warning "Cloud Function still exists: ${FUNCTION_NAME}"
            ((remaining_resources++))
        fi
        
        # Check Pub/Sub topic
        if gcloud pubsub topics describe "${TOPIC_NAME}" &> /dev/null; then
            warning "Pub/Sub topic still exists: ${TOPIC_NAME}"
            ((remaining_resources++))
        fi
        
        # Check Storage bucket
        if gsutil ls "gs://${BUCKET_NAME}" &> /dev/null; then
            warning "Storage bucket still exists: ${BUCKET_NAME}"
            ((remaining_resources++))
        fi
        
        # Check service account
        if gcloud iam service-accounts describe "${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com" &> /dev/null; then
            warning "Service account still exists: ${SERVICE_ACCOUNT_NAME}"
            ((remaining_resources++))
        fi
        
        if [[ ${remaining_resources} -eq 0 ]]; then
            success "All resources successfully cleaned up"
        else
            warning "${remaining_resources} resources may still exist"
        fi
    else
        success "Project no longer exists - all resources cleaned up"
    fi
}

# Function to display cleanup summary
display_summary() {
    log "Cleanup Summary"
    echo "==============="
    
    if [[ "${DELETE_PROJECT}" == "true" ]]; then
        echo "✅ Project '${PROJECT_ID}' and all resources deleted"
    else
        echo "✅ Individual resources deleted from project '${PROJECT_ID}'"
        echo "   - Cloud Function: ${FUNCTION_NAME}"
        echo "   - Pub/Sub Topic: ${TOPIC_NAME}"
        echo "   - Storage Bucket: ${BUCKET_NAME}"
        echo "   - Service Account: ${SERVICE_ACCOUNT_NAME}"
        echo "   - DLP Template: ${DLP_TEMPLATE_NAME}"
        echo "   - Monitoring and logging resources"
    fi
    
    echo ""
    echo "Note: Some resources may take a few minutes to be fully removed."
    echo "If you encounter billing charges, verify all resources are deleted in the Cloud Console."
    echo ""
}

# Main cleanup function
main() {
    log "Starting Data Privacy Compliance resource cleanup..."
    
    load_environment
    check_prerequisites
    confirm_destruction
    
    # If deleting the entire project, skip individual resource deletion
    if delete_project; then
        cleanup_local_files
        display_summary
        success "Data Privacy Compliance cleanup completed!"
        return 0
    fi
    
    # Delete individual resources
    cancel_dlp_jobs
    delete_cloud_function
    delete_scheduler_jobs
    delete_pubsub
    delete_dlp_resources
    delete_monitoring
    delete_scc_resources
    delete_storage
    delete_service_account
    cleanup_local_files
    validate_cleanup
    display_summary
    
    success "Data Privacy Compliance cleanup completed!"
}

# Run main function
main "$@"