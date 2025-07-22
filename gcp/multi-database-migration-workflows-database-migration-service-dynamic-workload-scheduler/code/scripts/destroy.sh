#!/bin/bash

# Multi-Database Migration Workflows Cleanup Script
# This script safely removes all resources created by the deployment script
# for the Database Migration Service and Dynamic Workload Scheduler solution

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
error_exit() {
    log_error "$1"
    exit 1
}

# Check if running in Google Cloud Shell or with gcloud authenticated
check_authentication() {
    log_info "Checking Google Cloud authentication..."
    
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        error_exit "Not authenticated with Google Cloud. Please run 'gcloud auth login' first."
    fi
    
    log_success "Google Cloud authentication verified"
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        error_exit "gcloud CLI is not installed. Please install it first."
    fi
    
    # Check if gsutil is available
    if ! command -v gsutil &> /dev/null; then
        error_exit "gsutil is not available. Please ensure it's installed with gcloud."
    fi
    
    log_success "All prerequisites are satisfied"
}

# Load environment variables or set defaults
setup_environment() {
    log_info "Setting up environment variables..."
    
    # Try to get current project if not set
    if [[ -z "${PROJECT_ID:-}" ]]; then
        PROJECT_ID=$(gcloud config get-value project 2>/dev/null || echo "")
        if [[ -z "$PROJECT_ID" ]]; then
            error_exit "PROJECT_ID not set and no default project configured. Please set PROJECT_ID environment variable."
        fi
    fi
    
    export REGION="${REGION:-us-central1}"
    export ZONE="${ZONE:-us-central1-a}"
    export NETWORK_NAME="${NETWORK_NAME:-migration-network}"
    
    # Try to detect resource names from existing resources
    if [[ -z "${INSTANCE_TEMPLATE:-}" ]]; then
        INSTANCE_TEMPLATE=$(gcloud compute instance-templates list --filter="name~migration-template-.*" --format="value(name)" --limit=1 2>/dev/null || echo "")
    fi
    
    if [[ -z "${CLOUD_SQL_INSTANCE:-}" ]]; then
        CLOUD_SQL_INSTANCE=$(gcloud sql instances list --filter="name~mysql-target-.*" --format="value(name)" --limit=1 2>/dev/null || echo "")
    fi
    
    if [[ -z "${ALLOYDB_CLUSTER:-}" ]]; then
        ALLOYDB_CLUSTER=$(gcloud alloydb clusters list --region="${REGION}" --filter="name~postgres-cluster-.*" --format="value(name)" --limit=1 2>/dev/null || echo "")
    fi
    
    log_info "Project ID: ${PROJECT_ID}"
    log_info "Region: ${REGION}"
    log_info "Zone: ${ZONE}"
    log_info "Network: ${NETWORK_NAME}"
    log_info "Instance Template: ${INSTANCE_TEMPLATE:-'Not found'}"
    log_info "Cloud SQL Instance: ${CLOUD_SQL_INSTANCE:-'Not found'}"
    log_info "AlloyDB Cluster: ${ALLOYDB_CLUSTER:-'Not found'}"
    
    log_success "Environment variables configured"
}

# Confirmation prompt
confirm_deletion() {
    echo
    log_warning "This script will permanently delete the following resources:"
    echo "  • Migration Jobs (if any)"
    echo "  • Database Migration Service connection profiles"
    echo "  • Cloud SQL instance: ${CLOUD_SQL_INSTANCE:-'Not found'}"
    echo "  • AlloyDB cluster: ${ALLOYDB_CLUSTER:-'Not found'}"
    echo "  • Compute Engine resources (instance groups, templates, reservations)"
    echo "  • Cloud Function: migration-orchestrator"
    echo "  • Cloud Storage bucket: gs://${PROJECT_ID}-migration-bucket"
    echo "  • VPC network: ${NETWORK_NAME}"
    echo "  • Monitoring dashboards and alerting policies"
    echo
    log_warning "This action cannot be undone!"
    echo
    
    if [[ "${FORCE_DELETE:-}" == "true" ]]; then
        log_info "Force delete enabled, skipping confirmation"
        return 0
    fi
    
    read -p "Are you sure you want to proceed? (type 'yes' to confirm): " confirmation
    if [[ "$confirmation" != "yes" ]]; then
        log_info "Cleanup cancelled by user"
        exit 0
    fi
    
    log_info "Proceeding with resource cleanup..."
}

# Stop and delete migration jobs
cleanup_migration_jobs() {
    log_info "Cleaning up Database Migration Service jobs..."
    
    # List and stop migration jobs
    local migration_jobs=$(gcloud database-migration migration-jobs list --region="${REGION}" --format="value(name)" 2>/dev/null || echo "")
    
    if [[ -n "$migration_jobs" ]]; then
        for job in $migration_jobs; do
            log_info "Stopping migration job: $job"
            gcloud database-migration migration-jobs stop "$job" --region="${REGION}" --quiet || log_warning "Failed to stop migration job: $job"
            
            log_info "Deleting migration job: $job"
            gcloud database-migration migration-jobs delete "$job" --region="${REGION}" --quiet || log_warning "Failed to delete migration job: $job"
        done
        log_success "Migration jobs cleaned up"
    else
        log_info "No migration jobs found"
    fi
}

# Delete Database Migration Service connection profiles
cleanup_connection_profiles() {
    log_info "Cleaning up Database Migration Service connection profiles..."
    
    local profiles=("source-mysql" "dest-cloudsql" "source-postgres" "dest-alloydb")
    
    for profile in "${profiles[@]}"; do
        if gcloud database-migration connection-profiles describe "$profile" --region="${REGION}" &>/dev/null; then
            log_info "Deleting connection profile: $profile"
            gcloud database-migration connection-profiles delete "$profile" --region="${REGION}" --quiet || log_warning "Failed to delete connection profile: $profile"
        else
            log_info "Connection profile $profile not found"
        fi
    done
    
    log_success "Connection profiles cleaned up"
}

# Delete Cloud SQL instance
cleanup_cloud_sql() {
    if [[ -n "${CLOUD_SQL_INSTANCE:-}" ]]; then
        log_info "Deleting Cloud SQL instance: ${CLOUD_SQL_INSTANCE}..."
        
        # Disable deletion protection first
        gcloud sql instances patch "${CLOUD_SQL_INSTANCE}" --no-deletion-protection --quiet || log_warning "Failed to disable deletion protection"
        
        # Delete the instance
        gcloud sql instances delete "${CLOUD_SQL_INSTANCE}" --quiet || log_warning "Failed to delete Cloud SQL instance: ${CLOUD_SQL_INSTANCE}"
        
        log_success "Cloud SQL instance deleted: ${CLOUD_SQL_INSTANCE}"
    else
        log_info "No Cloud SQL instance found to delete"
    fi
}

# Delete AlloyDB cluster
cleanup_alloydb() {
    if [[ -n "${ALLOYDB_CLUSTER:-}" ]]; then
        log_info "Deleting AlloyDB cluster: ${ALLOYDB_CLUSTER}..."
        
        # First delete all instances in the cluster
        local instances=$(gcloud alloydb instances list --cluster="${ALLOYDB_CLUSTER}" --region="${REGION}" --format="value(name)" 2>/dev/null || echo "")
        
        if [[ -n "$instances" ]]; then
            for instance in $instances; do
                log_info "Deleting AlloyDB instance: $instance"
                gcloud alloydb instances delete "$instance" --cluster="${ALLOYDB_CLUSTER}" --region="${REGION}" --quiet || log_warning "Failed to delete AlloyDB instance: $instance"
            done
        fi
        
        # Then delete the cluster
        gcloud alloydb clusters delete "${ALLOYDB_CLUSTER}" --region="${REGION}" --quiet || log_warning "Failed to delete AlloyDB cluster: ${ALLOYDB_CLUSTER}"
        
        log_success "AlloyDB cluster deleted: ${ALLOYDB_CLUSTER}"
    else
        log_info "No AlloyDB cluster found to delete"
    fi
}

# Delete Cloud Function
cleanup_cloud_function() {
    log_info "Deleting Cloud Function: migration-orchestrator..."
    
    if gcloud functions describe migration-orchestrator --region="${REGION}" &>/dev/null; then
        gcloud functions delete migration-orchestrator --region="${REGION}" --quiet || log_warning "Failed to delete Cloud Function: migration-orchestrator"
        log_success "Cloud Function deleted: migration-orchestrator"
    else
        log_info "Cloud Function migration-orchestrator not found"
    fi
}

# Delete Compute Engine resources
cleanup_compute_resources() {
    log_info "Cleaning up Compute Engine resources..."
    
    # Delete managed instance group
    if gcloud compute instance-groups managed describe migration-workers --region="${REGION}" &>/dev/null; then
        log_info "Deleting managed instance group: migration-workers"
        
        # First scale down to 0
        gcloud compute instance-groups managed resize migration-workers --size=0 --region="${REGION}" --quiet || log_warning "Failed to scale down instance group"
        
        # Wait for instances to be deleted
        sleep 30
        
        # Delete the instance group
        gcloud compute instance-groups managed delete migration-workers --region="${REGION}" --quiet || log_warning "Failed to delete instance group: migration-workers"
        
        log_success "Managed instance group deleted: migration-workers"
    else
        log_info "Managed instance group migration-workers not found"
    fi
    
    # Delete instance template
    if [[ -n "${INSTANCE_TEMPLATE:-}" ]] && gcloud compute instance-templates describe "${INSTANCE_TEMPLATE}" &>/dev/null; then
        log_info "Deleting instance template: ${INSTANCE_TEMPLATE}"
        gcloud compute instance-templates delete "${INSTANCE_TEMPLATE}" --quiet || log_warning "Failed to delete instance template: ${INSTANCE_TEMPLATE}"
        log_success "Instance template deleted: ${INSTANCE_TEMPLATE}"
    else
        log_info "Instance template not found"
    fi
    
    # Delete future reservations
    if gcloud compute future-reservations describe migration-flex-capacity --zone="${ZONE}" &>/dev/null; then
        log_info "Deleting future reservation: migration-flex-capacity"
        gcloud compute future-reservations delete migration-flex-capacity --zone="${ZONE}" --quiet || log_warning "Failed to delete future reservation: migration-flex-capacity"
        log_success "Future reservation deleted: migration-flex-capacity"
    else
        log_info "Future reservation migration-flex-capacity not found"
    fi
}

# Delete Cloud Storage bucket
cleanup_storage_bucket() {
    local bucket_name="${PROJECT_ID}-migration-bucket"
    
    log_info "Deleting Cloud Storage bucket: gs://${bucket_name}..."
    
    if gsutil ls -b "gs://${bucket_name}" &>/dev/null; then
        # Delete all objects in the bucket first
        gsutil -m rm -r "gs://${bucket_name}/**" || log_warning "Failed to delete bucket contents"
        
        # Delete the bucket
        gsutil rb "gs://${bucket_name}" || log_warning "Failed to delete bucket: gs://${bucket_name}"
        
        log_success "Cloud Storage bucket deleted: gs://${bucket_name}"
    else
        log_info "Cloud Storage bucket not found: gs://${bucket_name}"
    fi
}

# Delete monitoring resources
cleanup_monitoring() {
    log_info "Cleaning up monitoring and alerting resources..."
    
    # Delete monitoring dashboards
    local dashboards=$(gcloud monitoring dashboards list --filter="displayName:'Database Migration Dashboard'" --format="value(name)" 2>/dev/null || echo "")
    
    if [[ -n "$dashboards" ]]; then
        for dashboard in $dashboards; do
            log_info "Deleting monitoring dashboard: $dashboard"
            gcloud monitoring dashboards delete "$dashboard" --quiet || log_warning "Failed to delete dashboard: $dashboard"
        done
        log_success "Monitoring dashboards deleted"
    else
        log_info "No monitoring dashboards found"
    fi
    
    # Delete alerting policies
    local policies=$(gcloud alpha monitoring policies list --filter="displayName:'Migration Worker Failure Alert'" --format="value(name)" 2>/dev/null || echo "")
    
    if [[ -n "$policies" ]]; then
        for policy in $policies; do
            log_info "Deleting alerting policy: $policy"
            gcloud alpha monitoring policies delete "$policy" --quiet || log_warning "Failed to delete alerting policy: $policy"
        done
        log_success "Alerting policies deleted"
    else
        log_info "No alerting policies found"
    fi
}

# Delete VPC network
cleanup_network() {
    log_info "Cleaning up VPC network and subnet..."
    
    # Delete subnet first
    if gcloud compute networks subnets describe "${NETWORK_NAME}-subnet" --region="${REGION}" &>/dev/null; then
        log_info "Deleting subnet: ${NETWORK_NAME}-subnet"
        gcloud compute networks subnets delete "${NETWORK_NAME}-subnet" --region="${REGION}" --quiet || log_warning "Failed to delete subnet: ${NETWORK_NAME}-subnet"
        log_success "Subnet deleted: ${NETWORK_NAME}-subnet"
    else
        log_info "Subnet ${NETWORK_NAME}-subnet not found"
    fi
    
    # Delete VPC network
    if gcloud compute networks describe "${NETWORK_NAME}" &>/dev/null; then
        log_info "Deleting VPC network: ${NETWORK_NAME}"
        gcloud compute networks delete "${NETWORK_NAME}" --quiet || log_warning "Failed to delete VPC network: ${NETWORK_NAME}"
        log_success "VPC network deleted: ${NETWORK_NAME}"
    else
        log_info "VPC network ${NETWORK_NAME} not found"
    fi
}

# Wait for operations to complete
wait_for_operations() {
    log_info "Waiting for cleanup operations to complete..."
    
    # Wait for any running operations to complete
    local operations=$(gcloud compute operations list --filter="status:RUNNING" --format="value(name)" 2>/dev/null || echo "")
    
    if [[ -n "$operations" ]]; then
        log_info "Waiting for running operations to complete..."
        for operation in $operations; do
            echo "Waiting for operation: $operation"
        done
        sleep 30
    fi
}

# Display cleanup summary
display_summary() {
    log_success "=== CLEANUP COMPLETED ==="
    echo
    log_info "The following resources have been removed:"
    echo "  • Database Migration Service jobs and connection profiles"
    echo "  • Cloud SQL instance: ${CLOUD_SQL_INSTANCE:-'Not found'}"
    echo "  • AlloyDB cluster: ${ALLOYDB_CLUSTER:-'Not found'}"
    echo "  • Compute Engine resources (instance groups, templates, reservations)"
    echo "  • Cloud Function: migration-orchestrator"
    echo "  • Cloud Storage bucket: gs://${PROJECT_ID}-migration-bucket"
    echo "  • VPC network: ${NETWORK_NAME}"
    echo "  • Monitoring dashboards and alerting policies"
    echo
    log_info "Project cleanup completed successfully"
    echo
    log_warning "Note: Some operations may still be running in the background."
    log_warning "Check the Google Cloud Console to verify all resources have been deleted."
    echo
    log_info "To verify cleanup, run:"
    echo "  gcloud compute instances list"
    echo "  gcloud sql instances list"
    echo "  gcloud alloydb clusters list --region=${REGION}"
    echo "  gcloud functions list"
}

# Main execution flow
main() {
    log_info "Starting Multi-Database Migration Workflows cleanup..."
    echo
    
    check_authentication
    check_prerequisites
    setup_environment
    confirm_deletion
    
    # Clean up resources in reverse order of creation
    cleanup_migration_jobs
    cleanup_connection_profiles
    cleanup_cloud_function
    cleanup_monitoring
    cleanup_alloydb
    cleanup_cloud_sql
    cleanup_compute_resources
    cleanup_storage_bucket
    cleanup_network
    
    wait_for_operations
    display_summary
}

# Handle script interruption
trap 'log_error "Cleanup interrupted. Some resources may still exist."; exit 1' INT TERM

# Check for force delete flag
if [[ "${1:-}" == "--force" ]]; then
    export FORCE_DELETE="true"
    log_warning "Force delete enabled - skipping confirmation prompts"
fi

# Execute main function
main "$@"