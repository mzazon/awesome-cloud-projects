#!/bin/bash

# Real-Time Fleet Optimization Cleanup Script
# Removes all resources created by the deployment script
# Author: Generated for GCP Recipe
# Version: 1.0

set -euo pipefail

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

log_success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✅ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️  $1${NC}"
}

log_error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ❌ $1${NC}"
}

# Function to load deployment configuration
load_config() {
    log "Loading deployment configuration..."
    
    if [[ ! -f ".deployment_config" ]]; then
        log_error "Deployment configuration file not found!"
        log_error "Please ensure you're running this script from the same directory where deploy.sh was executed."
        log_error "If the deployment configuration is lost, you may need to manually clean up resources."
        exit 1
    fi
    
    # Source the configuration
    source .deployment_config
    
    log_success "Configuration loaded successfully"
    log "Project ID: ${PROJECT_ID}"
    log "Region: ${REGION}"
    log "Bigtable Instance: ${BIGTABLE_INSTANCE}"
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "gcloud CLI is not installed. Cannot proceed with cleanup."
        exit 1
    fi
    
    # Check if cbt is installed (for Bigtable cleanup)
    if ! command -v cbt &> /dev/null; then
        log_warning "cbt (Cloud Bigtable CLI) is not installed. Bigtable resources may need manual cleanup."
    fi
    
    # Check authentication
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" &> /dev/null; then
        log_error "Not authenticated with gcloud. Please run 'gcloud auth login'."
        exit 1
    fi
    
    # Set project context
    gcloud config set project ${PROJECT_ID}
    
    log_success "Prerequisites check passed"
}

# Function to confirm deletion
confirm_deletion() {
    echo
    log_warning "This script will permanently delete the following resources:"
    echo "  • Project: ${PROJECT_ID}"
    echo "  • Bigtable Instance: ${BIGTABLE_INSTANCE}"
    echo "  • Bigtable Table: ${BIGTABLE_TABLE}"
    echo "  • Pub/Sub Topic: ${PUBSUB_TOPIC}"
    echo "  • Cloud Function: ${FUNCTION_NAME}"
    echo "  • Dashboard Function: ${DASHBOARD_FUNCTION}"
    echo "  • All associated data and configurations"
    echo
    log_warning "This action cannot be undone!"
    echo
    
    # Prompt for confirmation
    read -p "Are you sure you want to proceed? (type 'yes' to confirm): " confirmation
    
    if [[ "${confirmation}" != "yes" ]]; then
        log "Cleanup cancelled by user"
        exit 0
    fi
    
    log "Proceeding with resource cleanup..."
}

# Function to delete Cloud Functions
delete_cloud_functions() {
    log "Deleting Cloud Functions..."
    
    # Delete main processing function
    if gcloud functions describe ${FUNCTION_NAME} --region=${REGION} &> /dev/null; then
        log "Deleting function: ${FUNCTION_NAME}"
        gcloud functions delete ${FUNCTION_NAME} --region=${REGION} --quiet
        log_success "Function ${FUNCTION_NAME} deleted"
    else
        log_warning "Function ${FUNCTION_NAME} not found"
    fi
    
    # Delete dashboard function
    if gcloud functions describe ${DASHBOARD_FUNCTION} --region=${REGION} &> /dev/null; then
        log "Deleting dashboard function: ${DASHBOARD_FUNCTION}"
        gcloud functions delete ${DASHBOARD_FUNCTION} --region=${REGION} --quiet
        log_success "Dashboard function ${DASHBOARD_FUNCTION} deleted"
    else
        log_warning "Dashboard function ${DASHBOARD_FUNCTION} not found"
    fi
}

# Function to delete Bigtable resources
delete_bigtable_resources() {
    log "Deleting Bigtable resources..."
    
    # Check if Bigtable instance exists
    if gcloud bigtable instances describe ${BIGTABLE_INSTANCE} &> /dev/null; then
        # Delete table first if cbt is available
        if command -v cbt &> /dev/null; then
            log "Deleting Bigtable table: ${BIGTABLE_TABLE}"
            if cbt -project=${PROJECT_ID} -instance=${BIGTABLE_INSTANCE} ls | grep -q ${BIGTABLE_TABLE}; then
                cbt -project=${PROJECT_ID} -instance=${BIGTABLE_INSTANCE} \
                    deletetable ${BIGTABLE_TABLE}
                log_success "Bigtable table ${BIGTABLE_TABLE} deleted"
            else
                log_warning "Bigtable table ${BIGTABLE_TABLE} not found"
            fi
        else
            log_warning "cbt not available. Table will be deleted with instance."
        fi
        
        # Delete Bigtable instance
        log "Deleting Bigtable instance: ${BIGTABLE_INSTANCE}"
        gcloud bigtable instances delete ${BIGTABLE_INSTANCE} --quiet
        log_success "Bigtable instance ${BIGTABLE_INSTANCE} deleted"
    else
        log_warning "Bigtable instance ${BIGTABLE_INSTANCE} not found"
    fi
}

# Function to delete Pub/Sub resources
delete_pubsub_resources() {
    log "Deleting Pub/Sub resources..."
    
    # Delete Pub/Sub topic
    if gcloud pubsub topics describe ${PUBSUB_TOPIC} &> /dev/null; then
        log "Deleting Pub/Sub topic: ${PUBSUB_TOPIC}"
        gcloud pubsub topics delete ${PUBSUB_TOPIC} --quiet
        log_success "Pub/Sub topic ${PUBSUB_TOPIC} deleted"
    else
        log_warning "Pub/Sub topic ${PUBSUB_TOPIC} not found"
    fi
    
    # Check for and delete any subscriptions (though our recipe doesn't create persistent ones)
    log "Checking for related subscriptions..."
    subscriptions=$(gcloud pubsub subscriptions list --filter="topic:${PUBSUB_TOPIC}" --format="value(name)" 2>/dev/null || true)
    
    if [[ -n "${subscriptions}" ]]; then
        log "Found related subscriptions, deleting..."
        echo "${subscriptions}" | while read -r subscription; do
            if [[ -n "${subscription}" ]]; then
                gcloud pubsub subscriptions delete "${subscription}" --quiet
                log_success "Subscription ${subscription} deleted"
            fi
        done
    else
        log "No related subscriptions found"
    fi
}

# Function to clean up local files
cleanup_local_files() {
    log "Cleaning up local files..."
    
    # Remove function source directories
    if [[ -d "cloud-function-source" ]]; then
        rm -rf cloud-function-source
        log_success "Removed cloud-function-source directory"
    fi
    
    if [[ -d "dashboard-function" ]]; then
        rm -rf dashboard-function
        log_success "Removed dashboard-function directory"
    fi
    
    # Remove optimization service directory
    if [[ -d "optimization-service" ]]; then
        rm -rf optimization-service
        log_success "Removed optimization-service directory"
    fi
    
    # Remove simulation script
    if [[ -f "simulate_traffic.py" ]]; then
        rm -f simulate_traffic.py
        log_success "Removed simulate_traffic.py"
    fi
    
    # Remove deployment configuration
    if [[ -f ".deployment_config" ]]; then
        rm -f .deployment_config
        log_success "Removed deployment configuration"
    fi
}

# Function to optionally delete the entire project
delete_project() {
    echo
    log "The project ${PROJECT_ID} still exists with potentially other resources."
    log_warning "Do you want to delete the entire project? This will remove ALL resources in the project."
    echo
    
    read -p "Delete entire project ${PROJECT_ID}? (type 'yes' to confirm): " project_confirmation
    
    if [[ "${project_confirmation}" == "yes" ]]; then
        log "Deleting project: ${PROJECT_ID}"
        gcloud projects delete ${PROJECT_ID} --quiet
        log_success "Project ${PROJECT_ID} deleted"
    else
        log "Project ${PROJECT_ID} preserved"
        log_warning "Note: You may still incur charges for remaining resources in the project"
        log "To manually delete the project later, run: gcloud projects delete ${PROJECT_ID}"
    fi
}

# Function to verify cleanup
verify_cleanup() {
    log "Verifying resource cleanup..."
    
    local errors=0
    
    # Check if Cloud Functions still exist
    if gcloud functions describe ${FUNCTION_NAME} --region=${REGION} &> /dev/null; then
        log_error "Function ${FUNCTION_NAME} still exists"
        ((errors++))
    fi
    
    if gcloud functions describe ${DASHBOARD_FUNCTION} --region=${REGION} &> /dev/null; then
        log_error "Dashboard function ${DASHBOARD_FUNCTION} still exists"
        ((errors++))
    fi
    
    # Check if Bigtable instance still exists
    if gcloud bigtable instances describe ${BIGTABLE_INSTANCE} &> /dev/null; then
        log_error "Bigtable instance ${BIGTABLE_INSTANCE} still exists"
        ((errors++))
    fi
    
    # Check if Pub/Sub topic still exists
    if gcloud pubsub topics describe ${PUBSUB_TOPIC} &> /dev/null; then
        log_error "Pub/Sub topic ${PUBSUB_TOPIC} still exists"
        ((errors++))
    fi
    
    if [[ ${errors} -eq 0 ]]; then
        log_success "All Fleet Optimization resources successfully cleaned up"
    else
        log_warning "Some resources may still exist. Please check manually."
        log_warning "This could be due to deletion delays or permission issues."
    fi
}

# Function to display cleanup summary
display_summary() {
    echo
    log "=== CLEANUP SUMMARY ==="
    log_success "Fleet Optimization Platform cleanup completed!"
    echo
    log "Cleaned up resources:"
    log "  ✅ Cloud Functions (processing and dashboard)"
    log "  ✅ Cloud Bigtable instance and tables"
    log "  ✅ Pub/Sub topics and subscriptions"
    log "  ✅ Local source code and configuration files"
    echo
    
    if gcloud projects describe ${PROJECT_ID} &> /dev/null; then
        log_warning "Project ${PROJECT_ID} still exists"
        log "You may want to review and clean up any remaining resources"
        log "To delete the entire project: gcloud projects delete ${PROJECT_ID}"
    else
        log_success "Project ${PROJECT_ID} has been deleted"
    fi
    
    echo
    log "Cleanup completed successfully!"
}

# Function to handle cleanup errors gracefully
cleanup_error_handler() {
    log_error "An error occurred during cleanup"
    log_warning "Some resources may not have been deleted"
    log "Please check the Google Cloud Console for any remaining resources"
    log "Manual cleanup may be required for:"
    log "  • Cloud Functions in region ${REGION}"
    log "  • Bigtable instance ${BIGTABLE_INSTANCE}"
    log "  • Pub/Sub topic ${PUBSUB_TOPIC}"
    echo
    log "To avoid ongoing charges, please verify all resources are deleted"
    exit 1
}

# Set error handler
trap cleanup_error_handler ERR

# Main cleanup function
main() {
    echo "=== Real-Time Fleet Optimization Cleanup ==="
    echo
    
    load_config
    check_prerequisites
    confirm_deletion
    
    log "Starting cleanup process..."
    echo
    
    delete_cloud_functions
    delete_bigtable_resources
    delete_pubsub_resources
    cleanup_local_files
    
    verify_cleanup
    
    # Ask about project deletion only if project still exists
    if gcloud projects describe ${PROJECT_ID} &> /dev/null; then
        delete_project
    fi
    
    display_summary
}

# Handle script interruption
cleanup_interrupted() {
    echo
    log_warning "Cleanup interrupted by user"
    log_warning "Some resources may not have been deleted"
    log "Please run this script again or manually clean up remaining resources"
    exit 1
}

trap cleanup_interrupted SIGINT SIGTERM

# Run main function
main "$@"