#!/bin/bash

# Real-Time IoT Data Processing Pipeline - Cleanup Script
# This script safely removes all resources created by the deployment script:
# - Cloud IoT Core devices and registries
# - Cloud Pub/Sub topics and subscriptions
# - BigQuery datasets and tables
# - Cloud Storage buckets
# - Service accounts and IAM policies
# - Monitoring dashboards

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

# Configuration variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/deployment_config.env"

# Function to load configuration from deployment
load_configuration() {
    log_info "Loading deployment configuration..."
    
    if [[ -f "$CONFIG_FILE" ]]; then
        # Source the configuration file
        source "$CONFIG_FILE"
        log_success "Configuration loaded successfully"
        
        # Validate required variables
        if [[ -z "${PROJECT_ID:-}" || -z "${REGION:-}" ]]; then
            log_error "Configuration file is missing required variables"
            exit 1
        fi
    else
        log_error "Configuration file not found: $CONFIG_FILE"
        echo "Please ensure you have run the deployment script first."
        exit 1
    fi
}

# Function to confirm destructive action
confirm_cleanup() {
    log_warning "This will DELETE ALL RESOURCES in project: $PROJECT_ID"
    echo ""
    echo "Resources to be deleted:"
    echo "- IoT Core registries and devices"
    echo "- Pub/Sub topics and subscriptions"
    echo "- BigQuery datasets and tables"
    echo "- Cloud Storage buckets"
    echo "- Service accounts and IAM policies"
    echo "- Monitoring dashboards"
    echo "- The entire Google Cloud project (optional)"
    echo ""
    read -p "Are you sure you want to proceed? (type 'DELETE' to confirm): " -r
    
    if [[ ! "$REPLY" == "DELETE" ]]; then
        log_info "Cleanup cancelled by user"
        exit 0
    fi
    
    log_info "Cleanup confirmed. Proceeding with resource deletion..."
}

# Function to stop running processes
stop_processes() {
    log_info "Stopping any running IoT simulator processes..."
    
    # Find and kill IoT simulator processes
    SIMULATOR_PIDS=$(pgrep -f "iot_simulator.py" || true)
    if [[ -n "$SIMULATOR_PIDS" ]]; then
        echo "$SIMULATOR_PIDS" | xargs kill -TERM 2>/dev/null || true
        sleep 2
        # Force kill if still running
        SIMULATOR_PIDS=$(pgrep -f "iot_simulator.py" || true)
        if [[ -n "$SIMULATOR_PIDS" ]]; then
            echo "$SIMULATOR_PIDS" | xargs kill -KILL 2>/dev/null || true
        fi
        log_success "IoT simulator processes stopped"
    else
        log_info "No IoT simulator processes found"
    fi
}

# Function to delete IoT Core resources
delete_iot_core_resources() {
    log_info "Deleting IoT Core resources..."
    
    # Set project context
    gcloud config set project "$PROJECT_ID" --quiet
    
    # Delete IoT device if it exists
    if gcloud iot devices describe "$DEVICE_ID" --region="$REGION" --registry="$IOT_REGISTRY_ID" --quiet > /dev/null 2>&1; then
        gcloud iot devices delete "$DEVICE_ID" \
            --region="$REGION" \
            --registry="$IOT_REGISTRY_ID" \
            --quiet
        log_success "IoT device deleted: $DEVICE_ID"
    else
        log_info "IoT device not found or already deleted: $DEVICE_ID"
    fi
    
    # Delete IoT registry if it exists
    if gcloud iot registries describe "$IOT_REGISTRY_ID" --region="$REGION" --quiet > /dev/null 2>&1; then
        gcloud iot registries delete "$IOT_REGISTRY_ID" \
            --region="$REGION" \
            --quiet
        log_success "IoT registry deleted: $IOT_REGISTRY_ID"
    else
        log_info "IoT registry not found or already deleted: $IOT_REGISTRY_ID"
    fi
}

# Function to delete Pub/Sub resources
delete_pubsub_resources() {
    log_info "Deleting Pub/Sub resources..."
    
    # Delete subscription if it exists
    if gcloud pubsub subscriptions describe "$PUBSUB_SUBSCRIPTION" --quiet > /dev/null 2>&1; then
        gcloud pubsub subscriptions delete "$PUBSUB_SUBSCRIPTION" --quiet
        log_success "Pub/Sub subscription deleted: $PUBSUB_SUBSCRIPTION"
    else
        log_info "Pub/Sub subscription not found or already deleted: $PUBSUB_SUBSCRIPTION"
    fi
    
    # Delete topic if it exists
    if gcloud pubsub topics describe "$PUBSUB_TOPIC" --quiet > /dev/null 2>&1; then
        gcloud pubsub topics delete "$PUBSUB_TOPIC" --quiet
        log_success "Pub/Sub topic deleted: $PUBSUB_TOPIC"
    else
        log_info "Pub/Sub topic not found or already deleted: $PUBSUB_TOPIC"
    fi
}

# Function to delete BigQuery resources
delete_bigquery_resources() {
    log_info "Deleting BigQuery resources..."
    
    # Delete BigQuery dataset if it exists
    if bq show "${PROJECT_ID}:${BIGQUERY_DATASET}" > /dev/null 2>&1; then
        bq rm -r -f "${PROJECT_ID}:${BIGQUERY_DATASET}"
        log_success "BigQuery dataset deleted: $BIGQUERY_DATASET"
    else
        log_info "BigQuery dataset not found or already deleted: $BIGQUERY_DATASET"
    fi
}

# Function to delete Cloud Storage resources
delete_storage_resources() {
    log_info "Deleting Cloud Storage resources..."
    
    # Delete storage bucket if it exists
    if gsutil ls "gs://${STORAGE_BUCKET}" > /dev/null 2>&1; then
        gsutil rm -r "gs://${STORAGE_BUCKET}"
        log_success "Cloud Storage bucket deleted: $STORAGE_BUCKET"
    else
        log_info "Cloud Storage bucket not found or already deleted: $STORAGE_BUCKET"
    fi
}

# Function to delete service accounts
delete_service_accounts() {
    log_info "Deleting service accounts..."
    
    # Delete Dataprep service account if it exists
    SERVICE_ACCOUNT_EMAIL="dataprep-pipeline@${PROJECT_ID}.iam.gserviceaccount.com"
    
    if gcloud iam service-accounts describe "$SERVICE_ACCOUNT_EMAIL" --quiet > /dev/null 2>&1; then
        gcloud iam service-accounts delete "$SERVICE_ACCOUNT_EMAIL" --quiet
        log_success "Service account deleted: $SERVICE_ACCOUNT_EMAIL"
    else
        log_info "Service account not found or already deleted: $SERVICE_ACCOUNT_EMAIL"
    fi
}

# Function to delete monitoring resources
delete_monitoring_resources() {
    log_info "Deleting monitoring resources..."
    
    # List and delete monitoring dashboards
    DASHBOARD_IDS=$(gcloud monitoring dashboards list --format="value(name)" --filter="displayName:'IoT Data Pipeline Dashboard'" 2>/dev/null || true)
    
    if [[ -n "$DASHBOARD_IDS" ]]; then
        for dashboard_id in $DASHBOARD_IDS; do
            gcloud monitoring dashboards delete "$dashboard_id" --quiet
            log_success "Monitoring dashboard deleted: $dashboard_id"
        done
    else
        log_info "No monitoring dashboards found to delete"
    fi
    
    # Delete alerting policies
    POLICY_IDS=$(gcloud alpha monitoring policies list --format="value(name)" --filter="displayName:'IoT Pipeline Low Throughput Alert'" 2>/dev/null || true)
    
    if [[ -n "$POLICY_IDS" ]]; then
        for policy_id in $POLICY_IDS; do
            gcloud alpha monitoring policies delete "$policy_id" --quiet
            log_success "Alerting policy deleted: $policy_id"
        done
    else
        log_info "No alerting policies found to delete"
    fi
}

# Function to clean up local files
cleanup_local_files() {
    log_info "Cleaning up local files..."
    
    # Remove generated files
    local files_to_remove=(
        "${SCRIPT_DIR}/device-private.pem"
        "${SCRIPT_DIR}/device-cert.pem"
        "${SCRIPT_DIR}/iot_simulator.py"
        "${SCRIPT_DIR}/sample_iot_data.json"
        "${SCRIPT_DIR}/iot_dashboard.json"
        "${SCRIPT_DIR}/deployment_config.env"
    )
    
    for file in "${files_to_remove[@]}"; do
        if [[ -f "$file" ]]; then
            rm -f "$file"
            log_success "Removed local file: $(basename "$file")"
        fi
    done
    
    # Remove any additional generated files
    find "$SCRIPT_DIR" -name "received_messages.json" -delete 2>/dev/null || true
    find "$SCRIPT_DIR" -name "*.log" -delete 2>/dev/null || true
    
    log_success "Local files cleaned up"
}

# Function to delete the entire project
delete_project() {
    log_info "Checking if project should be deleted..."
    
    echo ""
    read -p "Do you want to delete the entire project '$PROJECT_ID'? (y/N): " -r
    
    if [[ "$REPLY" =~ ^[Yy]$ ]]; then
        log_info "Deleting project: $PROJECT_ID"
        gcloud projects delete "$PROJECT_ID" --quiet
        log_success "Project deletion initiated (may take several minutes to complete)"
        log_info "Note: Project deletion is irreversible and will remove all resources"
    else
        log_info "Project deletion skipped"
        log_warning "Note: Some resources may still incur charges. Please verify all resources are deleted."
    fi
}

# Function to validate cleanup
validate_cleanup() {
    log_info "Validating resource cleanup..."
    
    local validation_failed=false
    
    # Check IoT Core resources
    if gcloud iot registries describe "$IOT_REGISTRY_ID" --region="$REGION" --quiet > /dev/null 2>&1; then
        log_error "IoT Core registry still exists: $IOT_REGISTRY_ID"
        validation_failed=true
    fi
    
    # Check Pub/Sub resources
    if gcloud pubsub topics describe "$PUBSUB_TOPIC" --quiet > /dev/null 2>&1; then
        log_error "Pub/Sub topic still exists: $PUBSUB_TOPIC"
        validation_failed=true
    fi
    
    # Check BigQuery resources
    if bq show "${PROJECT_ID}:${BIGQUERY_DATASET}" > /dev/null 2>&1; then
        log_error "BigQuery dataset still exists: $BIGQUERY_DATASET"
        validation_failed=true
    fi
    
    # Check Cloud Storage resources
    if gsutil ls "gs://${STORAGE_BUCKET}" > /dev/null 2>&1; then
        log_error "Cloud Storage bucket still exists: $STORAGE_BUCKET"
        validation_failed=true
    fi
    
    if [[ "$validation_failed" == true ]]; then
        log_error "Cleanup validation failed. Some resources may still exist."
        log_info "Please check the Google Cloud Console for any remaining resources."
        return 1
    else
        log_success "Cleanup validation passed. All resources have been removed."
        return 0
    fi
}

# Function to display final summary
display_cleanup_summary() {
    log_info "Cleanup completed!"
    echo ""
    echo "Summary of deleted resources:"
    echo "- Project: $PROJECT_ID"
    echo "- IoT Core registry: $IOT_REGISTRY_ID"
    echo "- IoT device: $DEVICE_ID"
    echo "- Pub/Sub topic: $PUBSUB_TOPIC"
    echo "- Pub/Sub subscription: $PUBSUB_SUBSCRIPTION"
    echo "- BigQuery dataset: $BIGQUERY_DATASET"
    echo "- Storage bucket: $STORAGE_BUCKET"
    echo "- Service accounts and IAM policies"
    echo "- Monitoring dashboards and alerts"
    echo "- Local configuration files"
    echo ""
    echo "💰 Note: Please verify in the Google Cloud Console that all resources"
    echo "   have been removed to avoid any unexpected charges."
    echo ""
    echo "If you deleted the entire project, it may take several minutes for"
    echo "the deletion to complete fully."
}

# Function to handle cleanup errors
handle_cleanup_errors() {
    log_error "An error occurred during cleanup. Some resources may still exist."
    echo ""
    echo "To manually clean up remaining resources:"
    echo "1. Check Google Cloud Console for any remaining resources"
    echo "2. Delete resources manually if needed"
    echo "3. Consider deleting the entire project if it was created for this recipe"
    echo ""
    echo "Project ID: $PROJECT_ID"
    echo "Region: $REGION"
    exit 1
}

# Error handling for cleanup
trap handle_cleanup_errors ERR

# Main cleanup function
main() {
    log_info "Starting IoT Data Processing Pipeline cleanup..."
    
    load_configuration
    confirm_cleanup
    stop_processes
    
    # Delete resources in reverse order of creation
    delete_monitoring_resources
    delete_service_accounts
    delete_storage_resources
    delete_bigquery_resources
    delete_pubsub_resources
    delete_iot_core_resources
    cleanup_local_files
    
    # Validate cleanup
    if validate_cleanup; then
        delete_project
        display_cleanup_summary
        log_success "Cleanup completed successfully!"
    else
        log_error "Cleanup validation failed. Please check remaining resources manually."
        exit 1
    fi
}

# Check if script is being run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi