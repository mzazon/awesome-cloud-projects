#!/bin/bash

# Security Posture Assessment with Security Command Center and Workload Manager - Cleanup Script
# This script removes all resources created by the security posture assessment solution

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Color codes for output formatting
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
        "INFO")
            echo -e "${BLUE}[INFO]${NC} ${timestamp} - ${message}"
            ;;
        "SUCCESS")
            echo -e "${GREEN}[SUCCESS]${NC} ${timestamp} - ${message}"
            ;;
        "WARNING")
            echo -e "${YELLOW}[WARNING]${NC} ${timestamp} - ${message}"
            ;;
        "ERROR")
            echo -e "${RED}[ERROR]${NC} ${timestamp} - ${message}"
            ;;
    esac
}

# Error handling function
error_exit() {
    log "ERROR" "$1"
    echo -e "${RED}Cleanup failed. Check logs above for details.${NC}"
    exit 1
}

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to prompt for confirmation
confirm_action() {
    local message="$1"
    local force="${FORCE:-false}"
    
    if [ "$force" = "true" ]; then
        return 0
    fi
    
    echo -e "${YELLOW}${message}${NC}"
    read -p "Are you sure you want to continue? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log "INFO" "Operation cancelled by user"
        exit 0
    fi
}

# Function to validate prerequisites
validate_prerequisites() {
    log "INFO" "Validating prerequisites..."
    
    # Check if gcloud CLI is installed
    if ! command_exists gcloud; then
        error_exit "gcloud CLI is not installed. Please install it first."
    fi
    
    # Check if user is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q "."; then
        error_exit "No active gcloud authentication found. Please run 'gcloud auth login'"
    fi
    
    log "SUCCESS" "Prerequisites validation completed"
}

# Function to load environment variables
load_environment() {
    log "INFO" "Loading environment variables..."
    
    # Try to load from existing deployment or use defaults
    export PROJECT_ID=${PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}
    export REGION=${REGION:-"us-central1"}
    export ZONE=${ZONE:-"us-central1-a"}
    
    # Try to get organization ID
    if [ -z "${ORGANIZATION_ID:-}" ]; then
        export ORGANIZATION_ID=$(gcloud organizations list --format="value(name)" --limit=1 2>/dev/null || echo "")
    fi
    
    # Check if we have required variables
    if [ -z "${PROJECT_ID:-}" ]; then
        error_exit "PROJECT_ID is not set. Please set it as an environment variable or configure gcloud."
    fi
    
    if [ -z "${ORGANIZATION_ID:-}" ]; then
        log "WARNING" "ORGANIZATION_ID is not set. Some organization-level resources may not be cleaned up."
    fi
    
    log "SUCCESS" "Environment loaded"
    log "INFO" "Project: ${PROJECT_ID}"
    log "INFO" "Region: ${REGION}"
    log "INFO" "Organization: ${ORGANIZATION_ID:-'Not Set'}"
}

# Function to find and delete Cloud Functions
delete_cloud_functions() {
    log "INFO" "Deleting Cloud Functions..."
    
    # Find functions with security-remediation prefix
    local functions=$(gcloud functions list --regions="${REGION}" \
        --format="value(name)" \
        --filter="name~security-remediation" 2>/dev/null || echo "")
    
    if [ -n "$functions" ]; then
        while IFS= read -r function_name; do
            if [ -n "$function_name" ]; then
                log "INFO" "Deleting Cloud Function: ${function_name}"
                gcloud functions delete "$function_name" \
                    --region="${REGION}" \
                    --quiet \
                    || log "WARNING" "Failed to delete function: ${function_name}"
            fi
        done <<< "$functions"
    else
        log "INFO" "No Cloud Functions found to delete"
    fi
    
    log "SUCCESS" "Cloud Functions cleanup completed"
}

# Function to delete Pub/Sub resources
delete_pubsub_resources() {
    log "INFO" "Deleting Pub/Sub resources..."
    
    # Find and delete subscriptions with security-events prefix
    local subscriptions=$(gcloud pubsub subscriptions list \
        --format="value(name)" \
        --filter="name~security-events" 2>/dev/null || echo "")
    
    if [ -n "$subscriptions" ]; then
        while IFS= read -r subscription; do
            if [ -n "$subscription" ]; then
                local sub_name=$(basename "$subscription")
                log "INFO" "Deleting Pub/Sub subscription: ${sub_name}"
                gcloud pubsub subscriptions delete "$sub_name" \
                    --quiet \
                    || log "WARNING" "Failed to delete subscription: ${sub_name}"
            fi
        done <<< "$subscriptions"
    fi
    
    # Find and delete topics with security-events prefix
    local topics=$(gcloud pubsub topics list \
        --format="value(name)" \
        --filter="name~security-events" 2>/dev/null || echo "")
    
    if [ -n "$topics" ]; then
        while IFS= read -r topic; do
            if [ -n "$topic" ]; then
                local topic_name=$(basename "$topic")
                log "INFO" "Deleting Pub/Sub topic: ${topic_name}"
                gcloud pubsub topics delete "$topic_name" \
                    --quiet \
                    || log "WARNING" "Failed to delete topic: ${topic_name}"
            fi
        done <<< "$topics"
    fi
    
    log "SUCCESS" "Pub/Sub resources cleanup completed"
}

# Function to delete Security Command Center configurations
delete_security_command_center() {
    log "INFO" "Deleting Security Command Center configurations..."
    
    if [ -n "${ORGANIZATION_ID:-}" ]; then
        # Delete Security Command Center notifications
        local notifications=$(gcloud scc notifications list \
            --organization="${ORGANIZATION_ID}" \
            --format="value(name)" \
            --filter="name~security-findings" 2>/dev/null || echo "")
        
        if [ -n "$notifications" ]; then
            while IFS= read -r notification; do
                if [ -n "$notification" ]; then
                    local notification_id=$(basename "$notification")
                    log "INFO" "Deleting Security Command Center notification: ${notification_id}"
                    gcloud scc notifications delete "$notification_id" \
                        --organization="${ORGANIZATION_ID}" \
                        --quiet \
                        || log "WARNING" "Failed to delete notification: ${notification_id}"
                fi
            done <<< "$notifications"
        fi
        
        # Delete posture deployments
        local deployments=$(gcloud scc posture-deployments list \
            --organization="${ORGANIZATION_ID}" \
            --location=global \
            --format="value(name)" \
            --filter="name~baseline-deployment" 2>/dev/null || echo "")
        
        if [ -n "$deployments" ]; then
            while IFS= read -r deployment; do
                if [ -n "$deployment" ]; then
                    local deployment_id=$(basename "$deployment")
                    log "INFO" "Deleting Security Command Center posture deployment: ${deployment_id}"
                    gcloud scc posture-deployments delete "$deployment_id" \
                        --organization="${ORGANIZATION_ID}" \
                        --location=global \
                        --quiet \
                        || log "WARNING" "Failed to delete posture deployment: ${deployment_id}"
                fi
            done <<< "$deployments"
        fi
        
        # Delete security postures
        local postures=$(gcloud scc postures list \
            --organization="${ORGANIZATION_ID}" \
            --location=global \
            --format="value(name)" \
            --filter="name~secure-baseline" 2>/dev/null || echo "")
        
        if [ -n "$postures" ]; then
            while IFS= read -r posture; do
                if [ -n "$posture" ]; then
                    local posture_id=$(basename "$posture")
                    log "INFO" "Deleting Security Command Center posture: ${posture_id}"
                    gcloud scc postures delete "$posture_id" \
                        --organization="${ORGANIZATION_ID}" \
                        --location=global \
                        --quiet \
                        || log "WARNING" "Failed to delete posture: ${posture_id}"
                fi
            done <<< "$postures"
        fi
    else
        log "WARNING" "Organization ID not set. Skipping Security Command Center cleanup."
    fi
    
    log "SUCCESS" "Security Command Center cleanup completed"
}

# Function to delete Workload Manager evaluations
delete_workload_manager() {
    log "INFO" "Deleting Workload Manager evaluations..."
    
    # Find and delete evaluations with security-compliance prefix
    local evaluations=$(gcloud workload-manager evaluations list \
        --location="${REGION}" \
        --format="value(name)" \
        --filter="name~security-compliance" 2>/dev/null || echo "")
    
    if [ -n "$evaluations" ]; then
        while IFS= read -r evaluation; do
            if [ -n "$evaluation" ]; then
                local eval_name=$(basename "$evaluation")
                log "INFO" "Deleting Workload Manager evaluation: ${eval_name}"
                gcloud workload-manager evaluations delete "$eval_name" \
                    --location="${REGION}" \
                    --quiet \
                    || log "WARNING" "Failed to delete evaluation: ${eval_name}"
            fi
        done <<< "$evaluations"
    else
        log "INFO" "No Workload Manager evaluations found to delete"
    fi
    
    log "SUCCESS" "Workload Manager cleanup completed"
}

# Function to delete Cloud Storage buckets
delete_storage_buckets() {
    log "INFO" "Deleting Cloud Storage buckets..."
    
    # Find buckets with security-logs prefix
    local buckets=$(gsutil ls -p "${PROJECT_ID}" 2>/dev/null | grep "security-logs" || echo "")
    
    if [ -n "$buckets" ]; then
        while IFS= read -r bucket; do
            if [ -n "$bucket" ]; then
                log "INFO" "Deleting storage bucket: ${bucket}"
                gsutil -m rm -r "$bucket" \
                    || log "WARNING" "Failed to delete bucket: ${bucket}"
            fi
        done <<< "$buckets"
    else
        log "INFO" "No storage buckets found to delete"
    fi
    
    log "SUCCESS" "Storage buckets cleanup completed"
}

# Function to delete monitoring dashboards
delete_monitoring_dashboards() {
    log "INFO" "Deleting monitoring dashboards..."
    
    # Find dashboards with Security Posture in the name
    local dashboards=$(gcloud monitoring dashboards list \
        --format="value(name)" \
        --filter="displayName~'Security Posture'" 2>/dev/null || echo "")
    
    if [ -n "$dashboards" ]; then
        while IFS= read -r dashboard; do
            if [ -n "$dashboard" ]; then
                local dashboard_id=$(basename "$dashboard")
                log "INFO" "Deleting monitoring dashboard: ${dashboard_id}"
                gcloud monitoring dashboards delete "$dashboard_id" \
                    --quiet \
                    || log "WARNING" "Failed to delete dashboard: ${dashboard_id}"
            fi
        done <<< "$dashboards"
    else
        log "INFO" "No monitoring dashboards found to delete"
    fi
    
    log "SUCCESS" "Monitoring dashboards cleanup completed"
}

# Function to delete scheduled jobs
delete_scheduled_jobs() {
    log "INFO" "Deleting scheduled jobs..."
    
    # Find jobs with security-posture prefix
    local jobs=$(gcloud scheduler jobs list \
        --location="${REGION}" \
        --format="value(name)" \
        --filter="name~security-posture" 2>/dev/null || echo "")
    
    if [ -n "$jobs" ]; then
        while IFS= read -r job; do
            if [ -n "$job" ]; then
                local job_name=$(basename "$job")
                log "INFO" "Deleting scheduled job: ${job_name}"
                gcloud scheduler jobs delete "$job_name" \
                    --location="${REGION}" \
                    --quiet \
                    || log "WARNING" "Failed to delete job: ${job_name}"
            fi
        done <<< "$jobs"
    else
        log "INFO" "No scheduled jobs found to delete"
    fi
    
    log "SUCCESS" "Scheduled jobs cleanup completed"
}

# Function to delete service accounts
delete_service_accounts() {
    log "INFO" "Deleting service accounts..."
    
    # Find service accounts with security-automation prefix
    local service_accounts=$(gcloud iam service-accounts list \
        --format="value(email)" \
        --filter="email~security-automation" 2>/dev/null || echo "")
    
    if [ -n "$service_accounts" ]; then
        while IFS= read -r sa_email; do
            if [ -n "$sa_email" ]; then
                log "INFO" "Deleting service account: ${sa_email}"
                gcloud iam service-accounts delete "$sa_email" \
                    --quiet \
                    || log "WARNING" "Failed to delete service account: ${sa_email}"
            fi
        done <<< "$service_accounts"
    else
        log "INFO" "No service accounts found to delete"
    fi
    
    log "SUCCESS" "Service accounts cleanup completed"
}

# Function to clean up temporary files
cleanup_temp_files() {
    log "INFO" "Cleaning up temporary files..."
    
    # Remove any temporary files that might have been created
    local temp_files=(
        "/tmp/security-validation-rules.yaml"
        "/tmp/security-dashboard.json"
        "/tmp/security-remediation-function"
    )
    
    for temp_file in "${temp_files[@]}"; do
        if [ -e "$temp_file" ]; then
            log "INFO" "Removing temporary file/directory: ${temp_file}"
            rm -rf "$temp_file" || log "WARNING" "Failed to remove: ${temp_file}"
        fi
    done
    
    log "SUCCESS" "Temporary files cleanup completed"
}

# Function to display cleanup summary
display_summary() {
    log "SUCCESS" "Security Posture Assessment cleanup completed!"
    echo
    echo "=== CLEANUP SUMMARY ==="
    echo "Project ID: ${PROJECT_ID}"
    echo "Region: ${REGION}"
    echo "Organization ID: ${ORGANIZATION_ID:-'Not Set'}"
    echo
    echo "Resources Cleaned Up:"
    echo "✓ Cloud Functions"
    echo "✓ Pub/Sub Topics and Subscriptions"
    echo "✓ Security Command Center Configurations"
    echo "✓ Workload Manager Evaluations"
    echo "✓ Cloud Storage Buckets"
    echo "✓ Monitoring Dashboards"
    echo "✓ Scheduled Jobs"
    echo "✓ Service Accounts"
    echo "✓ Temporary Files"
    echo
    echo "Notes:"
    echo "- Some organization-level Security Command Center settings may persist"
    echo "- API services were not disabled to avoid affecting other resources"
    echo "- The project itself was not deleted"
    echo
    echo "If you want to completely remove the project, run:"
    echo "gcloud projects delete ${PROJECT_ID}"
}

# Function to perform dry run
dry_run() {
    log "INFO" "Performing dry run - showing resources that would be deleted..."
    
    echo "=== DRY RUN - RESOURCES TO BE DELETED ==="
    echo
    
    # Show Cloud Functions
    echo "Cloud Functions:"
    gcloud functions list --regions="${REGION}" \
        --format="table(name,status,trigger)" \
        --filter="name~security-remediation" 2>/dev/null || echo "  None found"
    echo
    
    # Show Pub/Sub resources
    echo "Pub/Sub Topics:"
    gcloud pubsub topics list \
        --format="table(name)" \
        --filter="name~security-events" 2>/dev/null || echo "  None found"
    echo
    
    echo "Pub/Sub Subscriptions:"
    gcloud pubsub subscriptions list \
        --format="table(name)" \
        --filter="name~security-events" 2>/dev/null || echo "  None found"
    echo
    
    # Show Workload Manager evaluations
    echo "Workload Manager Evaluations:"
    gcloud workload-manager evaluations list \
        --location="${REGION}" \
        --format="table(name,state)" \
        --filter="name~security-compliance" 2>/dev/null || echo "  None found"
    echo
    
    # Show Storage buckets
    echo "Storage Buckets:"
    gsutil ls -p "${PROJECT_ID}" 2>/dev/null | grep "security-logs" || echo "  None found"
    echo
    
    # Show Service accounts
    echo "Service Accounts:"
    gcloud iam service-accounts list \
        --format="table(email,displayName)" \
        --filter="email~security-automation" 2>/dev/null || echo "  None found"
    echo
    
    # Show Scheduled jobs
    echo "Scheduled Jobs:"
    gcloud scheduler jobs list \
        --location="${REGION}" \
        --format="table(name,state)" \
        --filter="name~security-posture" 2>/dev/null || echo "  None found"
    echo
    
    if [ -n "${ORGANIZATION_ID:-}" ]; then
        # Show Security Command Center resources
        echo "Security Command Center Notifications:"
        gcloud scc notifications list \
            --organization="${ORGANIZATION_ID}" \
            --format="table(name,description)" \
            --filter="name~security-findings" 2>/dev/null || echo "  None found"
        echo
        
        echo "Security Command Center Postures:"
        gcloud scc postures list \
            --organization="${ORGANIZATION_ID}" \
            --location=global \
            --format="table(name,description)" \
            --filter="name~secure-baseline" 2>/dev/null || echo "  None found"
        echo
    fi
    
    log "INFO" "Dry run completed. Use --force to proceed with actual cleanup."
}

# Main cleanup function
main() {
    echo "=== Security Posture Assessment Cleanup ==="
    echo "This script will remove all resources created by the security posture assessment deployment."
    echo
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --force)
                export FORCE="true"
                shift
                ;;
            --dry-run)
                export DRY_RUN="true"
                shift
                ;;
            --help)
                echo "Usage: $0 [OPTIONS]"
                echo
                echo "Options:"
                echo "  --force     Skip confirmation prompts"
                echo "  --dry-run   Show what would be deleted without actually deleting"
                echo "  --help      Show this help message"
                echo
                echo "Environment Variables:"
                echo "  PROJECT_ID      Google Cloud project ID"
                echo "  REGION          Google Cloud region (default: us-central1)"
                echo "  ORGANIZATION_ID Google Cloud organization ID"
                exit 0
                ;;
            *)
                log "ERROR" "Unknown option: $1"
                exit 1
                ;;
        esac
    done
    
    # Run prerequisite checks
    validate_prerequisites
    load_environment
    
    # Perform dry run if requested
    if [ "${DRY_RUN:-false}" = "true" ]; then
        dry_run
        exit 0
    fi
    
    # Confirm destructive operation
    confirm_action "This will permanently delete all security posture assessment resources."
    
    # Run cleanup steps
    log "INFO" "Starting cleanup process..."
    
    delete_scheduled_jobs
    delete_cloud_functions
    delete_pubsub_resources
    delete_security_command_center
    delete_workload_manager
    delete_storage_buckets
    delete_monitoring_dashboards
    delete_service_accounts
    cleanup_temp_files
    
    display_summary
    
    log "SUCCESS" "Cleanup completed successfully!"
    exit 0
}

# Check if script is being run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi