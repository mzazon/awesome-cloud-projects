#!/bin/bash

# Network Performance Optimization with Cloud WAN and Network Intelligence Center
# Cleanup/Destroy Script for GCP
# Recipe: network-performance-optimization-wan-network-intelligence-center

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING:${NC} $1"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1" >&2
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO:${NC} $1"
}

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites for cleanup..."
    
    # Check if gcloud CLI is installed
    if ! command_exists gcloud; then
        error "Google Cloud CLI (gcloud) is not installed. Cannot perform cleanup."
        exit 1
    fi
    
    # Check if user is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 > /dev/null; then
        error "No active Google Cloud authentication found."
        error "Please run: gcloud auth login"
        exit 1
    fi
    
    # Check if gsutil is available
    if ! command_exists gsutil; then
        error "gsutil is not available. Please ensure Google Cloud SDK is properly installed."
        exit 1
    fi
    
    log "✅ Prerequisites check completed successfully"
}

# Function to detect environment variables from deployment
detect_environment() {
    log "Detecting deployment environment..."
    
    # Try to get project from gcloud config
    if [[ -z "${PROJECT_ID:-}" ]]; then
        PROJECT_ID=$(gcloud config get-value project 2>/dev/null || echo "")
        if [[ -z "$PROJECT_ID" ]]; then
            read -p "Enter your Google Cloud Project ID: " PROJECT_ID
            if [[ -z "$PROJECT_ID" ]]; then
                error "Project ID cannot be empty"
                exit 1
            fi
        fi
    fi
    
    # Set default values
    export PROJECT_ID="${PROJECT_ID}"
    export REGION="${REGION:-us-central1}"
    export ZONE="${ZONE:-us-central1-a}"
    
    # Set gcloud defaults
    gcloud config set project "${PROJECT_ID}" --quiet
    gcloud config set compute/region "${REGION}" --quiet
    gcloud config set compute/zone "${ZONE}" --quiet
    
    log "✅ Environment detected:"
    info "  Project ID: ${PROJECT_ID}"
    info "  Region: ${REGION}"
    info "  Zone: ${ZONE}"
}

# Function to confirm destruction
confirm_destruction() {
    warn "This script will permanently delete all Network Performance Optimization resources."
    warn "This action cannot be undone!"
    echo ""
    info "Resources that will be deleted:"
    info "  • All Cloud Functions (network-optimizer-*, flow-analyzer-*, firewall-optimizer-*)"
    info "  • Cloud Scheduler jobs (periodic-network-optimization, daily-network-report)"
    info "  • Pub/Sub topics and subscriptions (network-alerts-*)"
    info "  • Network Intelligence Center connectivity tests"
    info "  • Cloud Monitoring policies"
    info "  • Cloud Storage buckets (network-ops-data-*)"
    info "  • VPC Flow Logs configuration"
    echo ""
    
    # Skip confirmation if in non-interactive mode
    if [[ "${FORCE_DESTROY:-false}" == "true" ]]; then
        warn "Force destroy mode enabled, skipping confirmation"
        return 0
    fi
    
    read -p "Are you sure you want to proceed? (yes/no): " confirm
    if [[ "$confirm" != "yes" ]]; then
        info "Cleanup cancelled by user"
        exit 0
    fi
    
    echo ""
    read -p "Type 'DELETE' to confirm permanent resource deletion: " double_confirm
    if [[ "$double_confirm" != "DELETE" ]]; then
        info "Cleanup cancelled - confirmation failed"
        exit 0
    fi
    
    log "✅ Destruction confirmed by user"
}

# Function to delete Cloud Scheduler jobs
delete_scheduler_jobs() {
    log "Deleting Cloud Scheduler jobs..."
    
    # List and delete all scheduler jobs for this deployment
    local jobs=(
        "periodic-network-optimization"
        "daily-network-report"
    )
    
    for job in "${jobs[@]}"; do
        info "Deleting scheduler job: ${job}"
        if gcloud scheduler jobs delete "${job}" --location="${REGION}" --quiet 2>/dev/null; then
            log "✅ Deleted scheduler job: ${job}"
        else
            warn "Scheduler job ${job} not found or already deleted"
        fi
    done
    
    # Also delete any jobs with our pattern
    local job_list
    job_list=$(gcloud scheduler jobs list --location="${REGION}" --format="value(name)" --filter="name:network" 2>/dev/null || echo "")
    
    if [[ -n "$job_list" ]]; then
        while IFS= read -r job_name; do
            if [[ -n "$job_name" ]]; then
                info "Deleting additional scheduler job: $(basename "${job_name}")"
                gcloud scheduler jobs delete "$(basename "${job_name}")" --location="${REGION}" --quiet 2>/dev/null || true
            fi
        done <<< "$job_list"
    fi
    
    log "✅ Cloud Scheduler jobs cleanup completed"
}

# Function to delete Cloud Functions
delete_cloud_functions() {
    log "Deleting Cloud Functions..."
    
    # Get list of all functions in the region
    local functions_list
    functions_list=$(gcloud functions list --region="${REGION}" --format="value(name)" 2>/dev/null || echo "")
    
    if [[ -n "$functions_list" ]]; then
        while IFS= read -r function_name; do
            if [[ -n "$function_name" ]]; then
                local base_name
                base_name=$(basename "${function_name}")
                
                # Delete functions that match our patterns
                if [[ "$base_name" =~ ^(network-optimizer-|flow-analyzer-|firewall-optimizer-) ]]; then
                    info "Deleting Cloud Function: ${base_name}"
                    if gcloud functions delete "${base_name}" --region="${REGION}" --quiet 2>/dev/null; then
                        log "✅ Deleted function: ${base_name}"
                    else
                        warn "Failed to delete function: ${base_name}"
                    fi
                fi
            fi
        done <<< "$functions_list"
    else
        info "No Cloud Functions found in region ${REGION}"
    fi
    
    log "✅ Cloud Functions cleanup completed"
}

# Function to delete Network Intelligence Center resources
delete_network_intelligence_resources() {
    log "Deleting Network Intelligence Center resources..."
    
    # Delete connectivity tests
    local tests=(
        "regional-connectivity-test"
        "external-connectivity-test"
    )
    
    for test in "${tests[@]}"; do
        info "Deleting connectivity test: ${test}"
        if gcloud network-management connectivity-tests delete "${test}" --quiet 2>/dev/null; then
            log "✅ Deleted connectivity test: ${test}"
        else
            warn "Connectivity test ${test} not found or already deleted"
        fi
    done
    
    # Disable VPC Flow Logs on default subnet
    info "Disabling VPC Flow Logs..."
    if gcloud compute networks subnets update default \
        --region="${REGION}" \
        --no-enable-flow-logs \
        --quiet 2>/dev/null; then
        log "✅ VPC Flow Logs disabled"
    else
        warn "Failed to disable VPC Flow Logs or already disabled"
    fi
    
    log "✅ Network Intelligence Center resources cleanup completed"
}

# Function to delete monitoring policies
delete_monitoring_policies() {
    log "Deleting Cloud Monitoring policies..."
    
    # Get list of all monitoring policies
    local policies_list
    policies_list=$(gcloud alpha monitoring policies list --format="value(name)" 2>/dev/null || echo "")
    
    if [[ -n "$policies_list" ]]; then
        while IFS= read -r policy_name; do
            if [[ -n "$policy_name" ]]; then
                # Delete policies that match our patterns
                local policy_display_name
                policy_display_name=$(gcloud alpha monitoring policies describe "${policy_name}" --format="value(displayName)" 2>/dev/null || echo "")
                
                if [[ "$policy_display_name" =~ (Network|network) ]]; then
                    info "Deleting monitoring policy: ${policy_display_name}"
                    if gcloud alpha monitoring policies delete "${policy_name}" --quiet 2>/dev/null; then
                        log "✅ Deleted monitoring policy: ${policy_display_name}"
                    else
                        warn "Failed to delete monitoring policy: ${policy_display_name}"
                    fi
                fi
            fi
        done <<< "$policies_list"
    else
        info "No monitoring policies found"
    fi
    
    log "✅ Monitoring policies cleanup completed"
}

# Function to delete Pub/Sub resources
delete_pubsub_resources() {
    log "Deleting Pub/Sub resources..."
    
    # Get list of all topics
    local topics_list
    topics_list=$(gcloud pubsub topics list --format="value(name)" 2>/dev/null || echo "")
    
    if [[ -n "$topics_list" ]]; then
        while IFS= read -r topic_name; do
            if [[ -n "$topic_name" ]]; then
                local base_topic_name
                base_topic_name=$(basename "${topic_name}")
                
                # Delete topics that match our pattern
                if [[ "$base_topic_name" =~ ^network-alerts- ]]; then
                    info "Deleting Pub/Sub topic: ${base_topic_name}"
                    
                    # First delete all subscriptions for this topic
                    local subscriptions_list
                    subscriptions_list=$(gcloud pubsub subscriptions list --format="value(name)" --filter="topicId:${base_topic_name}" 2>/dev/null || echo "")
                    
                    if [[ -n "$subscriptions_list" ]]; then
                        while IFS= read -r sub_name; do
                            if [[ -n "$sub_name" ]]; then
                                local base_sub_name
                                base_sub_name=$(basename "${sub_name}")
                                info "Deleting subscription: ${base_sub_name}"
                                gcloud pubsub subscriptions delete "${base_sub_name}" --quiet 2>/dev/null || true
                            fi
                        done <<< "$subscriptions_list"
                    fi
                    
                    # Then delete the topic
                    if gcloud pubsub topics delete "${base_topic_name}" --quiet 2>/dev/null; then
                        log "✅ Deleted Pub/Sub topic: ${base_topic_name}"
                    else
                        warn "Failed to delete Pub/Sub topic: ${base_topic_name}"
                    fi
                fi
            fi
        done <<< "$topics_list"
    else
        info "No Pub/Sub topics found"
    fi
    
    log "✅ Pub/Sub resources cleanup completed"
}

# Function to delete Cloud Storage buckets
delete_storage_buckets() {
    log "Deleting Cloud Storage buckets..."
    
    # Get list of all buckets in the project
    local buckets_list
    buckets_list=$(gsutil ls -p "${PROJECT_ID}" 2>/dev/null | sed 's|gs://||' | sed 's|/||' || echo "")
    
    if [[ -n "$buckets_list" ]]; then
        while IFS= read -r bucket_name; do
            if [[ -n "$bucket_name" ]]; then
                # Delete buckets that match our pattern
                if [[ "$bucket_name" =~ ^network-ops-data- ]]; then
                    info "Deleting storage bucket: ${bucket_name}"
                    
                    # Remove all objects first
                    if gsutil -m rm -r "gs://${bucket_name}/**" 2>/dev/null || true; then
                        log "Bucket contents removed"
                    fi
                    
                    # Delete the bucket
                    if gsutil rb "gs://${bucket_name}" 2>/dev/null; then
                        log "✅ Deleted storage bucket: ${bucket_name}"
                    else
                        warn "Failed to delete storage bucket: ${bucket_name}"
                    fi
                fi
            fi
        done <<< "$buckets_list"
    else
        info "No storage buckets found"
    fi
    
    log "✅ Storage buckets cleanup completed"
}

# Function to clean up local files
cleanup_local_files() {
    log "Cleaning up local files..."
    
    # Remove deployment info files
    if ls deployment-info-*.txt >/dev/null 2>&1; then
        info "Removing deployment info files..."
        rm -f deployment-info-*.txt
        log "✅ Deployment info files removed"
    fi
    
    # Remove any temporary files
    if ls network_*.yaml >/dev/null 2>&1; then
        info "Removing temporary configuration files..."
        rm -f network_*.yaml
        log "✅ Temporary files removed"
    fi
    
    log "✅ Local files cleanup completed"
}

# Function to verify cleanup
verify_cleanup() {
    log "Verifying cleanup completion..."
    
    local cleanup_issues=()
    
    # Check for remaining Cloud Functions
    local remaining_functions
    remaining_functions=$(gcloud functions list --region="${REGION}" --format="value(name)" --filter="name:network-optimizer OR name:flow-analyzer OR name:firewall-optimizer" 2>/dev/null || echo "")
    if [[ -n "$remaining_functions" ]]; then
        cleanup_issues+=("Some Cloud Functions may still exist")
    fi
    
    # Check for remaining Pub/Sub topics
    local remaining_topics
    remaining_topics=$(gcloud pubsub topics list --format="value(name)" --filter="name:network-alerts" 2>/dev/null || echo "")
    if [[ -n "$remaining_topics" ]]; then
        cleanup_issues+=("Some Pub/Sub topics may still exist")
    fi
    
    # Check for remaining connectivity tests
    local remaining_tests
    remaining_tests=$(gcloud network-management connectivity-tests list --format="value(name)" 2>/dev/null || echo "")
    if [[ -n "$remaining_tests" ]]; then
        cleanup_issues+=("Some connectivity tests may still exist")
    fi
    
    # Check for remaining storage buckets
    local remaining_buckets
    remaining_buckets=$(gsutil ls -p "${PROJECT_ID}" 2>/dev/null | grep "network-ops-data" || echo "")
    if [[ -n "$remaining_buckets" ]]; then
        cleanup_issues+=("Some storage buckets may still exist")
    fi
    
    # Report verification results
    if [[ ${#cleanup_issues[@]} -eq 0 ]]; then
        log "✅ Cleanup verification passed - all resources appear to have been removed"
    else
        warn "Cleanup verification found potential issues:"
        for issue in "${cleanup_issues[@]}"; do
            warn "  • $issue"
        done
        warn "You may need to manually clean up remaining resources"
    fi
}

# Function to display post-cleanup information
display_cleanup_summary() {
    log "Cleanup completed!"
    echo ""
    info "Summary of actions taken:"
    info "  • Deleted Cloud Functions (network optimization, flow analyzer, firewall optimizer)"
    info "  • Removed Cloud Scheduler jobs (periodic optimization, daily reports)"
    info "  • Deleted Pub/Sub topics and subscriptions"
    info "  • Removed Network Intelligence Center connectivity tests"
    info "  • Disabled VPC Flow Logs"
    info "  • Deleted Cloud Monitoring policies"
    info "  • Removed Cloud Storage buckets"
    info "  • Cleaned up local files"
    echo ""
    info "Final notes:"
    info "  • Some resources may take a few minutes to be fully removed"
    info "  • Check Google Cloud Console to verify all resources are deleted"
    info "  • Billing for usage up to deletion time may still appear"
    echo ""
    
    # Check if there are any APIs that could be disabled
    warn "Consider disabling unused APIs to reduce security surface:"
    info "  • Network Management API (if not used elsewhere)"
    info "  • Cloud Functions API (if not used elsewhere)"
    info "  • Cloud Scheduler API (if not used elsewhere)"
    echo ""
    
    log "🎉 Network Performance Optimization infrastructure has been successfully destroyed!"
}

# Main cleanup function
main() {
    log "Starting Network Performance Optimization cleanup..."
    
    # Check if running in supported environment
    if [[ "${CLOUD_SHELL:-false}" != "true" ]] && [[ -z "${GOOGLE_CLOUD_PROJECT:-}" ]]; then
        info "Running outside of Cloud Shell environment"
    fi
    
    # Run cleanup steps
    check_prerequisites
    detect_environment
    confirm_destruction
    
    log "Beginning resource deletion..."
    
    # Delete resources in reverse order of creation to handle dependencies
    delete_scheduler_jobs
    delete_cloud_functions
    delete_network_intelligence_resources
    delete_monitoring_policies
    delete_pubsub_resources
    delete_storage_buckets
    cleanup_local_files
    
    # Verify cleanup and display summary
    verify_cleanup
    display_cleanup_summary
    
    log "✅ Cleanup process completed successfully!"
}

# Function to handle script interruption
cleanup_on_interrupt() {
    error "Cleanup interrupted! Some resources may still exist."
    error "Please run the script again or manually clean up remaining resources."
    exit 1
}

# Handle script interruption
trap cleanup_on_interrupt INT TERM

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --force)
            export FORCE_DESTROY="true"
            shift
            ;;
        --project)
            export PROJECT_ID="$2"
            shift 2
            ;;
        --region)
            export REGION="$2"
            shift 2
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --force              Skip confirmation prompts"
            echo "  --project PROJECT    Specify project ID"
            echo "  --region REGION      Specify region (default: us-central1)"
            echo "  --help               Show this help message"
            echo ""
            echo "Examples:"
            echo "  $0                   Interactive cleanup"
            echo "  $0 --force           Non-interactive cleanup"
            echo "  $0 --project my-proj Cleanup specific project"
            exit 0
            ;;
        *)
            error "Unknown option: $1"
            error "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Run main function
main "$@"