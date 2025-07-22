#!/bin/bash

# Infrastructure Health Assessment with Cloud Workload Manager and Cloud Deploy - Cleanup Script
# This script removes all resources created by the deployment script
# including Cloud Workload Manager, Cloud Deploy, monitoring, and serverless components

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Colors for output
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
    log_info "Checking prerequisites for cleanup..."
    
    # Check if gcloud CLI is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "gcloud CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if gcloud is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        log_error "gcloud is not authenticated. Please run 'gcloud auth login' first."
        exit 1
    fi
    
    # Check if gsutil is available
    if ! command -v gsutil &> /dev/null; then
        log_error "gsutil is not available. Please ensure Google Cloud SDK is properly installed."
        exit 1
    fi
    
    log_success "Prerequisites check passed"
}

# Function to load environment variables
load_environment() {
    log_info "Loading environment variables..."
    
    # Try to load from .env_vars file first
    if [ -f ".env_vars" ]; then
        log_info "Loading variables from .env_vars file..."
        source .env_vars
        log_success "Environment variables loaded from file"
    else
        log_warning ".env_vars file not found, using manual setup..."
        
        # Prompt for required variables
        if [ -z "${PROJECT_ID:-}" ]; then
            read -p "Enter PROJECT_ID: " PROJECT_ID
            export PROJECT_ID
        fi
        
        if [ -z "${REGION:-}" ]; then
            export REGION="${REGION:-us-central1}"
        fi
        
        if [ -z "${ZONE:-}" ]; then
            export ZONE="${ZONE:-us-central1-a}"
        fi
        
        if [ -z "${CLUSTER_NAME:-}" ]; then
            read -p "Enter CLUSTER_NAME: " CLUSTER_NAME
            export CLUSTER_NAME
        fi
        
        if [ -z "${DEPLOYMENT_PIPELINE:-}" ]; then
            read -p "Enter DEPLOYMENT_PIPELINE: " DEPLOYMENT_PIPELINE
            export DEPLOYMENT_PIPELINE
        fi
        
        if [ -z "${FUNCTION_NAME:-}" ]; then
            read -p "Enter FUNCTION_NAME: " FUNCTION_NAME
            export FUNCTION_NAME
        fi
    fi
    
    # Set gcloud configuration
    gcloud config set project ${PROJECT_ID}
    gcloud config set compute/region ${REGION}
    gcloud config set compute/zone ${ZONE}
    
    log_info "Using PROJECT_ID: ${PROJECT_ID}"
    log_info "Using REGION: ${REGION}"
    log_info "Using ZONE: ${ZONE}"
}

# Function to confirm destructive actions
confirm_destruction() {
    echo
    log_warning "This script will DELETE the following resources:"
    echo "  - GKE cluster: ${CLUSTER_NAME}"
    echo "  - Cloud Function: ${FUNCTION_NAME}"
    echo "  - Cloud Deploy pipeline: ${DEPLOYMENT_PIPELINE}"
    echo "  - Cloud Storage bucket: ${PROJECT_ID}-health-assessments"
    echo "  - Pub/Sub topics and subscriptions"
    echo "  - Monitoring alert policies and custom metrics"
    echo "  - All local configuration files"
    echo
    
    # Skip confirmation if --yes flag is provided
    if [[ "${1:-}" == "--yes" ]] || [[ "${1:-}" == "-y" ]]; then
        log_warning "Auto-confirmation enabled, proceeding with cleanup..."
        return 0
    fi
    
    read -p "Are you sure you want to proceed? (yes/no): " confirmation
    
    case $confirmation in
        [Yy]|[Yy][Ee][Ss])
            log_info "Proceeding with resource cleanup..."
            ;;
        *)
            log_info "Cleanup cancelled by user"
            exit 0
            ;;
    esac
}

# Function to delete Cloud Deploy resources
delete_cloud_deploy_resources() {
    log_info "Deleting Cloud Deploy resources..."
    
    # Delete delivery pipeline
    if gcloud deploy delivery-pipelines describe ${DEPLOYMENT_PIPELINE} --region=${REGION} >/dev/null 2>&1; then
        if gcloud deploy delivery-pipelines delete ${DEPLOYMENT_PIPELINE} \
            --region=${REGION} \
            --quiet; then
            log_success "Cloud Deploy pipeline deleted: ${DEPLOYMENT_PIPELINE}"
        else
            log_error "Failed to delete Cloud Deploy pipeline"
        fi
    else
        log_warning "Cloud Deploy pipeline not found: ${DEPLOYMENT_PIPELINE}"
    fi
    
    # Delete targets (they should be deleted with the pipeline, but check anyway)
    for target in staging-target production-target; do
        if gcloud deploy targets describe ${target} --region=${REGION} >/dev/null 2>&1; then
            if gcloud deploy targets delete ${target} --region=${REGION} --quiet; then
                log_success "Cloud Deploy target deleted: ${target}"
            else
                log_warning "Failed to delete Cloud Deploy target: ${target}"
            fi
        fi
    done
}

# Function to delete Cloud Function and dependencies
delete_cloud_function() {
    log_info "Deleting Cloud Function and dependencies..."
    
    # Delete Cloud Function
    if gcloud functions describe ${FUNCTION_NAME} >/dev/null 2>&1; then
        if gcloud functions delete ${FUNCTION_NAME} --quiet; then
            log_success "Cloud Function deleted: ${FUNCTION_NAME}"
        else
            log_error "Failed to delete Cloud Function"
        fi
    else
        log_warning "Cloud Function not found: ${FUNCTION_NAME}"
    fi
    
    # Clean up function source directory
    if [ -d "health-function" ]; then
        rm -rf health-function/
        log_success "Cloud Function source directory cleaned up"
    fi
}

# Function to delete Pub/Sub resources
delete_pubsub_resources() {
    log_info "Deleting Pub/Sub topics and subscriptions..."
    
    # Delete subscriptions first
    local subscriptions=("health-deployment-trigger")
    for subscription in "${subscriptions[@]}"; do
        if gcloud pubsub subscriptions describe ${subscription} >/dev/null 2>&1; then
            if gcloud pubsub subscriptions delete ${subscription} --quiet; then
                log_success "Subscription deleted: ${subscription}"
            else
                log_warning "Failed to delete subscription: ${subscription}"
            fi
        else
            log_warning "Subscription not found: ${subscription}"
        fi
    done
    
    # Delete topics
    local topics=("health-assessment-events" "health-monitoring-alerts")
    for topic in "${topics[@]}"; do
        if gcloud pubsub topics describe ${topic} >/dev/null 2>&1; then
            if gcloud pubsub topics delete ${topic} --quiet; then
                log_success "Topic deleted: ${topic}"
            else
                log_warning "Failed to delete topic: ${topic}"
            fi
        else
            log_warning "Topic not found: ${topic}"
        fi
    done
}

# Function to delete GKE cluster
delete_gke_cluster() {
    log_info "Deleting GKE cluster..."
    
    if gcloud container clusters describe ${CLUSTER_NAME} --zone=${ZONE} >/dev/null 2>&1; then
        log_info "This may take several minutes..."
        if gcloud container clusters delete ${CLUSTER_NAME} \
            --zone=${ZONE} \
            --quiet; then
            log_success "GKE cluster deleted: ${CLUSTER_NAME}"
        else
            log_error "Failed to delete GKE cluster"
        fi
    else
        log_warning "GKE cluster not found: ${CLUSTER_NAME}"
    fi
}

# Function to delete storage resources
delete_storage_resources() {
    log_info "Deleting Cloud Storage resources..."
    
    local bucket_name="${PROJECT_ID}-health-assessments"
    
    if gsutil ls gs://${bucket_name} >/dev/null 2>&1; then
        log_info "Removing all objects from bucket..."
        if gsutil -m rm -r gs://${bucket_name} 2>/dev/null; then
            log_success "Storage bucket and contents deleted: gs://${bucket_name}"
        else
            log_error "Failed to delete storage bucket"
        fi
    else
        log_warning "Storage bucket not found: gs://${bucket_name}"
    fi
}

# Function to delete monitoring resources
delete_monitoring_resources() {
    log_info "Deleting monitoring and alerting resources..."
    
    # Delete custom metrics
    if gcloud logging metrics describe deployment_success >/dev/null 2>&1; then
        if gcloud logging metrics delete deployment_success --quiet; then
            log_success "Custom metric deleted: deployment_success"
        else
            log_warning "Failed to delete custom metric: deployment_success"
        fi
    else
        log_warning "Custom metric not found: deployment_success"
    fi
    
    # Delete alert policies (this is more complex as we need to find them by name)
    log_info "Searching for alert policies to delete..."
    local policy_ids=$(gcloud alpha monitoring policies list \
        --filter="displayName:'Infrastructure Health Critical Issues'" \
        --format="value(name)" 2>/dev/null || true)
    
    if [ -n "$policy_ids" ]; then
        for policy_id in $policy_ids; do
            if gcloud alpha monitoring policies delete ${policy_id} --quiet 2>/dev/null; then
                log_success "Alert policy deleted: ${policy_id}"
            else
                log_warning "Failed to delete alert policy: ${policy_id}"
            fi
        done
    else
        log_warning "No matching alert policies found to delete"
    fi
}

# Function to delete Workload Manager resources
delete_workload_manager_resources() {
    log_info "Cleaning up Workload Manager assessment configurations..."
    
    # Workload Manager evaluations are typically managed by the service
    # We don't need to explicitly delete them, but we can remove our config files
    log_info "Workload Manager evaluations will be automatically cleaned up by the service"
    log_success "Workload Manager cleanup completed"
}

# Function to clean up local files
cleanup_local_files() {
    log_info "Cleaning up local configuration files..."
    
    local files_to_remove=(
        ".env_vars"
        "workload-assessment.yaml"
        "clouddeploy.yaml"
        "health-alert-policy.json"
        "lifecycle.json"
        "test-assessment.json"
        "remediation-templates/"
    )
    
    for file in "${files_to_remove[@]}"; do
        if [ -e "$file" ]; then
            rm -rf "$file"
            log_success "Removed: $file"
        fi
    done
    
    log_success "Local files cleaned up"
}

# Function to run cleanup validation
run_cleanup_validation() {
    log_info "Running cleanup validation..."
    
    local cleanup_errors=0
    
    # Check if GKE cluster is gone
    if gcloud container clusters describe ${CLUSTER_NAME} --zone=${ZONE} >/dev/null 2>&1; then
        log_warning "GKE cluster still exists: ${CLUSTER_NAME}"
        ((cleanup_errors++))
    else
        log_success "GKE cluster successfully removed"
    fi
    
    # Check if Cloud Function is gone
    if gcloud functions describe ${FUNCTION_NAME} >/dev/null 2>&1; then
        log_warning "Cloud Function still exists: ${FUNCTION_NAME}"
        ((cleanup_errors++))
    else
        log_success "Cloud Function successfully removed"
    fi
    
    # Check if storage bucket is gone
    if gsutil ls gs://${PROJECT_ID}-health-assessments >/dev/null 2>&1; then
        log_warning "Storage bucket still exists: gs://${PROJECT_ID}-health-assessments"
        ((cleanup_errors++))
    else
        log_success "Storage bucket successfully removed"
    fi
    
    # Check if Cloud Deploy pipeline is gone
    if gcloud deploy delivery-pipelines describe ${DEPLOYMENT_PIPELINE} --region=${REGION} >/dev/null 2>&1; then
        log_warning "Cloud Deploy pipeline still exists: ${DEPLOYMENT_PIPELINE}"
        ((cleanup_errors++))
    else
        log_success "Cloud Deploy pipeline successfully removed"
    fi
    
    # Check Pub/Sub topics
    if gcloud pubsub topics describe health-assessment-events >/dev/null 2>&1; then
        log_warning "Pub/Sub topic still exists: health-assessment-events"
        ((cleanup_errors++))
    else
        log_success "Pub/Sub topics successfully removed"
    fi
    
    if [ $cleanup_errors -eq 0 ]; then
        log_success "All resources successfully cleaned up!"
    else
        log_warning "Cleanup completed with ${cleanup_errors} warnings. Some resources may need manual cleanup."
    fi
}

# Function to display cleanup summary
display_cleanup_summary() {
    log_success "Infrastructure Health Assessment Pipeline Cleanup Completed!"
    echo
    echo "=== Cleanup Summary ==="
    echo "Project ID: ${PROJECT_ID}"
    echo "Region: ${REGION}"
    echo "Zone: ${ZONE}"
    echo
    echo "=== Resources Removed ==="
    echo "✓ GKE Cluster: ${CLUSTER_NAME}"
    echo "✓ Cloud Function: ${FUNCTION_NAME}"
    echo "✓ Cloud Deploy Pipeline: ${DEPLOYMENT_PIPELINE}"
    echo "✓ Storage Bucket: gs://${PROJECT_ID}-health-assessments"
    echo "✓ Pub/Sub topics and subscriptions"
    echo "✓ Monitoring alert policies and custom metrics"
    echo "✓ Local configuration files"
    echo
    echo "=== Important Notes ==="
    echo "• Some Google Cloud APIs remain enabled (you can disable them manually if desired)"
    echo "• IAM roles and service accounts were not modified"
    echo "• Project-level configurations remain unchanged"
    echo "• Billing will stop for the deleted resources"
    echo
    log_info "Cleanup process completed successfully!"
}

# Function to handle partial cleanup on script failure
cleanup_on_error() {
    log_error "Cleanup script failed on line $LINENO"
    log_warning "Some resources may not have been fully cleaned up"
    log_info "You can re-run this script to continue cleanup, or manually remove remaining resources"
    exit 1
}

# Main cleanup function
main() {
    echo "=== Infrastructure Health Assessment Cleanup ==="
    echo "Starting cleanup of infrastructure health assessment pipeline..."
    echo
    
    # Run cleanup steps
    check_prerequisites
    load_environment
    confirm_destruction "$@"
    
    log_info "Beginning resource deletion..."
    
    # Delete resources in reverse order of creation
    delete_cloud_deploy_resources
    delete_cloud_function
    delete_pubsub_resources
    delete_monitoring_resources
    delete_workload_manager_resources
    delete_gke_cluster
    delete_storage_resources
    cleanup_local_files
    
    # Validate cleanup
    run_cleanup_validation
    display_cleanup_summary
    
    log_success "Cleanup completed successfully!"
}

# Error handling
trap cleanup_on_error ERR

# Run main function with all arguments
main "$@"