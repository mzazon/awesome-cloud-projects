#!/bin/bash

# Threat Detection Pipelines with Cloud IDS and BigQuery Data Canvas - Cleanup Script
# This script removes all resources created by the deployment script

set -euo pipefail

# Color codes for output formatting
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

# Error handling
error_continue() {
    log_error "$1 - continuing with cleanup"
}

# Parse command line arguments
FORCE_DELETE=false
CONFIRM_DELETE=true

while [[ $# -gt 0 ]]; do
    case $1 in
        --force)
            FORCE_DELETE=true
            CONFIRM_DELETE=false
            shift
            ;;
        --no-confirm)
            CONFIRM_DELETE=false
            shift
            ;;
        *)
            log_error "Unknown option: $1"
            echo "Usage: $0 [--force] [--no-confirm]"
            echo "  --force      Skip confirmation and force deletion"
            echo "  --no-confirm Skip confirmation prompt"
            exit 1
            ;;
    esac
done

# Display script banner
echo "=================================================="
echo "Threat Detection Pipelines Cleanup Script"
echo "=================================================="
echo ""

# Setup environment variables (same as deploy script)
setup_environment() {
    log_info "Setting up environment variables..."
    
    # Get current project
    export PROJECT_ID="${PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}"
    export REGION="${REGION:-$(gcloud config get-value compute/region 2>/dev/null || echo 'us-central1')}"
    export ZONE="${ZONE:-$(gcloud config get-value compute/zone 2>/dev/null || echo 'us-central1-a')}"
    
    # Resource names (must match deploy script)
    export VPC_NAME="threat-detection-vpc"
    export SUBNET_NAME="threat-detection-subnet"
    export IDS_ENDPOINT_NAME="threat-detection-endpoint"
    export MIRRORING_POLICY_NAME="threat-detection-mirroring"
    export DATASET_NAME="threat_detection"
    export PUBSUB_TOPIC="threat-detection-findings"
    export PUBSUB_SUBSCRIPTION="process-findings-sub"
    export ALERT_TOPIC="security-alerts"
    export PROCESSING_FUNCTION="process-threat-finding"
    export ALERT_FUNCTION="process-security-alert"
    
    if [[ -z "${PROJECT_ID}" ]]; then
        error_exit "PROJECT_ID not set and no default project configured"
    fi
    
    log_success "Environment configured for project: ${PROJECT_ID}"
}

# Confirmation prompt
confirm_deletion() {
    if [[ "${CONFIRM_DELETE}" == "true" ]]; then
        echo ""
        log_warning "This will DELETE ALL resources created for the threat detection pipeline!"
        echo ""
        echo "Project: ${PROJECT_ID}"
        echo "Region: ${REGION}"
        echo ""
        echo "Resources to be deleted:"
        echo "- Cloud IDS Endpoint: ${IDS_ENDPOINT_NAME}"
        echo "- Cloud Functions: ${PROCESSING_FUNCTION}, ${ALERT_FUNCTION}"
        echo "- BigQuery Dataset: ${DATASET_NAME} (ALL DATA WILL BE LOST)"
        echo "- Pub/Sub Topics and Subscriptions"
        echo "- Packet Mirroring Policy: ${MIRRORING_POLICY_NAME}"
        echo "- Test VMs and Network Infrastructure"
        echo "- VPC Network: ${VPC_NAME}"
        echo ""
        read -p "Are you sure you want to continue? [y/N]: " -n 1 -r
        echo ""
        
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Cleanup cancelled by user"
            exit 0
        fi
        
        echo ""
        log_warning "Starting resource deletion in 5 seconds... (Ctrl+C to cancel)"
        sleep 5
    fi
}

# Find and delete test VMs with random suffix
cleanup_test_vms() {
    log_info "Cleaning up test VMs..."
    
    # Find VMs with specific tags
    local vms=$(gcloud compute instances list \
        --filter="tags.items:mirrored-vm" \
        --format="value(name,zone)" 2>/dev/null || true)
    
    if [[ -n "${vms}" ]]; then
        while IFS=$'\t' read -r vm_name vm_zone; do
            log_info "Deleting VM: ${vm_name} in zone: ${vm_zone}"
            gcloud compute instances delete "${vm_name}" \
                --zone="${vm_zone}" \
                --quiet 2>/dev/null || error_continue "Failed to delete VM: ${vm_name}"
        done <<< "${vms}"
    else
        log_info "No test VMs found to delete"
    fi
    
    log_success "Test VMs cleanup completed"
}

# Remove Cloud IDS resources
cleanup_ids_resources() {
    log_info "Cleaning up Cloud IDS resources..."
    
    # Delete packet mirroring policy first
    log_info "Deleting packet mirroring policy: ${MIRRORING_POLICY_NAME}"
    gcloud compute packet-mirrorings delete "${MIRRORING_POLICY_NAME}" \
        --region "${REGION}" \
        --quiet 2>/dev/null || error_continue "Failed to delete packet mirroring policy"
    
    # Delete IDS endpoint (this takes time)
    log_info "Deleting IDS endpoint: ${IDS_ENDPOINT_NAME} (this may take 10-15 minutes)"
    gcloud ids endpoints delete "${IDS_ENDPOINT_NAME}" \
        --zone "${ZONE}" \
        --async \
        --quiet 2>/dev/null || error_continue "Failed to delete IDS endpoint"
    
    # Monitor deletion progress
    if gcloud ids endpoints describe "${IDS_ENDPOINT_NAME}" --zone "${ZONE}" &>/dev/null; then
        log_info "IDS endpoint deletion initiated. Monitoring progress..."
        local timeout=900  # 15 minutes timeout
        local elapsed=0
        local interval=30
        
        while [ $elapsed -lt $timeout ]; do
            if ! gcloud ids endpoints describe "${IDS_ENDPOINT_NAME}" --zone "${ZONE}" &>/dev/null; then
                log_success "IDS endpoint deleted successfully"
                break
            else
                log_info "IDS endpoint still deleting... waiting ${interval} seconds"
                sleep $interval
                elapsed=$((elapsed + interval))
            fi
        done
        
        if [ $elapsed -ge $timeout ]; then
            log_warning "Timeout waiting for IDS endpoint deletion. Deletion may continue in background."
        fi
    fi
    
    log_success "Cloud IDS resources cleanup completed"
}

# Remove Cloud Functions
cleanup_cloud_functions() {
    log_info "Cleaning up Cloud Functions..."
    
    # Delete threat processing function
    log_info "Deleting function: ${PROCESSING_FUNCTION}"
    gcloud functions delete "${PROCESSING_FUNCTION}" \
        --quiet 2>/dev/null || error_continue "Failed to delete function: ${PROCESSING_FUNCTION}"
    
    # Delete alert processing function
    log_info "Deleting function: ${ALERT_FUNCTION}"
    gcloud functions delete "${ALERT_FUNCTION}" \
        --quiet 2>/dev/null || error_continue "Failed to delete function: ${ALERT_FUNCTION}"
    
    # Clean up local function directories
    if [[ -d "threat-processor-function" ]]; then
        log_info "Removing local function directory: threat-processor-function"
        rm -rf threat-processor-function
    fi
    
    if [[ -d "alert-processor-function" ]]; then
        log_info "Removing local function directory: alert-processor-function"
        rm -rf alert-processor-function
    fi
    
    log_success "Cloud Functions cleanup completed"
}

# Remove Pub/Sub resources
cleanup_pubsub_resources() {
    log_info "Cleaning up Pub/Sub resources..."
    
    # Delete subscriptions first
    log_info "Deleting Pub/Sub subscription: ${PUBSUB_SUBSCRIPTION}"
    gcloud pubsub subscriptions delete "${PUBSUB_SUBSCRIPTION}" \
        --quiet 2>/dev/null || error_continue "Failed to delete subscription: ${PUBSUB_SUBSCRIPTION}"
    
    # Delete topics
    log_info "Deleting Pub/Sub topic: ${PUBSUB_TOPIC}"
    gcloud pubsub topics delete "${PUBSUB_TOPIC}" \
        --quiet 2>/dev/null || error_continue "Failed to delete topic: ${PUBSUB_TOPIC}"
    
    log_info "Deleting alert topic: ${ALERT_TOPIC}"
    gcloud pubsub topics delete "${ALERT_TOPIC}" \
        --quiet 2>/dev/null || error_continue "Failed to delete topic: ${ALERT_TOPIC}"
    
    log_success "Pub/Sub resources cleanup completed"
}

# Remove BigQuery resources
cleanup_bigquery_resources() {
    log_info "Cleaning up BigQuery resources..."
    
    log_warning "This will permanently delete ALL data in the threat detection dataset!"
    
    # Delete BigQuery dataset (removes all tables and data)
    log_info "Deleting BigQuery dataset: ${DATASET_NAME}"
    bq rm -r -f "${PROJECT_ID}:${DATASET_NAME}" 2>/dev/null || error_continue "Failed to delete BigQuery dataset"
    
    log_success "BigQuery resources cleanup completed"
}

# Remove network infrastructure
cleanup_network_infrastructure() {
    log_info "Cleaning up network infrastructure..."
    
    # Delete VPC peering connection
    log_info "Deleting VPC peering connection"
    gcloud services vpc-peerings delete \
        --service servicenetworking.googleapis.com \
        --network "${VPC_NAME}" \
        --quiet 2>/dev/null || error_continue "Failed to delete VPC peering"
    
    # Delete reserved IP range
    log_info "Deleting reserved IP range: google-managed-services-threat-detection"
    gcloud compute addresses delete google-managed-services-threat-detection \
        --global \
        --quiet 2>/dev/null || error_continue "Failed to delete reserved IP range"
    
    # Delete subnet
    log_info "Deleting subnet: ${SUBNET_NAME}"
    gcloud compute networks subnets delete "${SUBNET_NAME}" \
        --region "${REGION}" \
        --quiet 2>/dev/null || error_continue "Failed to delete subnet"
    
    # Delete VPC network
    log_info "Deleting VPC network: ${VPC_NAME}"
    gcloud compute networks delete "${VPC_NAME}" \
        --quiet 2>/dev/null || error_continue "Failed to delete VPC network"
    
    log_success "Network infrastructure cleanup completed"
}

# Clean up local files
cleanup_local_files() {
    log_info "Cleaning up local files..."
    
    # Remove any temporary files that might have been created
    local files_to_remove=(
        "alerting-policy.json"
        "dashboard-config.json"
    )
    
    for file in "${files_to_remove[@]}"; do
        if [[ -f "${file}" ]]; then
            log_info "Removing local file: ${file}"
            rm -f "${file}"
        fi
    done
    
    log_success "Local files cleanup completed"
}

# Verify resource deletion
verify_cleanup() {
    log_info "Verifying resource cleanup..."
    
    local issues_found=false
    
    # Check if IDS endpoint still exists
    if gcloud ids endpoints describe "${IDS_ENDPOINT_NAME}" --zone "${ZONE}" &>/dev/null; then
        log_warning "IDS endpoint still exists (deletion may be in progress)"
        issues_found=true
    fi
    
    # Check if Cloud Functions still exist
    if gcloud functions describe "${PROCESSING_FUNCTION}" &>/dev/null; then
        log_warning "Cloud Function still exists: ${PROCESSING_FUNCTION}"
        issues_found=true
    fi
    
    # Check if BigQuery dataset still exists
    if bq show "${PROJECT_ID}:${DATASET_NAME}" &>/dev/null; then
        log_warning "BigQuery dataset still exists: ${DATASET_NAME}"
        issues_found=true
    fi
    
    # Check if VPC network still exists
    if gcloud compute networks describe "${VPC_NAME}" &>/dev/null; then
        log_warning "VPC network still exists: ${VPC_NAME}"
        issues_found=true
    fi
    
    if [[ "${issues_found}" == "false" ]]; then
        log_success "All resources have been successfully removed"
    else
        log_warning "Some resources may still exist - check manually if needed"
    fi
}

# Display cleanup summary
display_cleanup_summary() {
    echo ""
    echo "=================================================="
    echo "CLEANUP COMPLETED"
    echo "=================================================="
    echo ""
    echo "Project ID: ${PROJECT_ID}"
    echo "Region: ${REGION}"
    echo ""
    echo "Resources Removed:"
    echo "- Cloud IDS Endpoint: ${IDS_ENDPOINT_NAME}"
    echo "- Cloud Functions: ${PROCESSING_FUNCTION}, ${ALERT_FUNCTION}"
    echo "- BigQuery Dataset: ${DATASET_NAME}"
    echo "- Pub/Sub Topics and Subscriptions"
    echo "- Packet Mirroring Policy: ${MIRRORING_POLICY_NAME}"
    echo "- Test VMs and Network Infrastructure"
    echo "- VPC Network: ${VPC_NAME}"
    echo ""
    
    if [[ "${FORCE_DELETE}" == "true" ]]; then
        echo "Note: Forced deletion was used - some resources may take time to fully delete"
    else
        echo "Note: Cloud IDS endpoint deletion may take up to 15 minutes to complete"
    fi
    
    echo ""
    echo "Cleanup completed. Check Google Cloud Console to verify all resources are removed."
    echo "=================================================="
}

# Main cleanup function
main() {
    log_info "Starting threat detection pipeline cleanup..."
    
    setup_environment
    confirm_deletion
    
    # Perform cleanup in reverse order of deployment
    cleanup_test_vms
    cleanup_ids_resources
    cleanup_cloud_functions
    cleanup_pubsub_resources
    cleanup_bigquery_resources
    cleanup_network_infrastructure
    cleanup_local_files
    
    verify_cleanup
    display_cleanup_summary
    
    log_success "Threat detection pipeline cleanup completed!"
}

# Run main function
main "$@"