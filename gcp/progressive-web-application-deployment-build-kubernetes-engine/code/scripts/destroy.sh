#!/bin/bash
# Progressive Web Application Cleanup Script for GCP
# This script removes all resources created by the PWA deployment

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

# Check if running in dry-run mode
DRY_RUN=false
if [[ "${1:-}" == "--dry-run" ]]; then
    DRY_RUN=true
    log_info "Running in dry-run mode - no resources will be deleted"
fi

# Function to execute command with dry-run support
execute_command() {
    local command="$1"
    local description="$2"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would execute: $command"
        log_info "[DRY-RUN] Description: $description"
        return 0
    fi
    
    log_info "$description"
    eval "$command"
    return $?
}

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "Google Cloud CLI (gcloud) is not installed. Please install it first."
        exit 1
    fi
    
    # Check if kubectl is installed
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl is not installed. Please install it first."
        exit 1
    fi
    
    # Check if user is authenticated with gcloud
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q "@"; then
        log_error "You are not authenticated with Google Cloud. Please run 'gcloud auth login' first."
        exit 1
    fi
    
    log_success "Prerequisites check completed"
}

# Function to set up environment variables
setup_environment() {
    log_info "Setting up environment variables..."
    
    # Set project ID (use current project if not specified)
    if [[ -z "${PROJECT_ID:-}" ]]; then
        export PROJECT_ID=$(gcloud config get-value project 2>/dev/null)
        if [[ -z "$PROJECT_ID" ]]; then
            log_error "No project ID found. Please set PROJECT_ID environment variable or run 'gcloud config set project PROJECT_ID'"
            exit 1
        fi
    fi
    
    # Set default region and zone
    export REGION="${REGION:-us-central1}"
    export ZONE="${ZONE:-us-central1-a}"
    
    # Set cluster names
    export CLUSTER_NAME_BLUE="${CLUSTER_NAME_BLUE:-pwa-cluster-blue}"
    export CLUSTER_NAME_GREEN="${CLUSTER_NAME_GREEN:-pwa-cluster-green}"
    
    # Set resource names (try to detect from existing resources)
    export BUCKET_NAME="${BUCKET_NAME:-}"
    export REPO_NAME="${REPO_NAME:-pwa-demo-app}"
    
    # If bucket name not provided, try to find it
    if [[ -z "$BUCKET_NAME" ]]; then
        BUCKET_NAME=$(gsutil ls -p ${PROJECT_ID} | grep "pwa-assets-" | head -1 | sed 's|gs://||' | sed 's|/||' || echo "")
        if [[ -n "$BUCKET_NAME" ]]; then
            log_info "Found bucket: $BUCKET_NAME"
        fi
    fi
    
    log_success "Environment variables configured"
    log_info "Project ID: ${PROJECT_ID}"
    log_info "Region: ${REGION}"
    log_info "Blue Cluster: ${CLUSTER_NAME_BLUE}"
    log_info "Green Cluster: ${CLUSTER_NAME_GREEN}"
    log_info "Repository: ${REPO_NAME}"
    if [[ -n "$BUCKET_NAME" ]]; then
        log_info "Bucket: gs://${BUCKET_NAME}"
    fi
}

# Function to confirm deletion
confirm_deletion() {
    if [[ "$DRY_RUN" == "true" ]]; then
        return 0
    fi
    
    log_warning "This will delete the following resources:"
    echo "  - GKE Clusters: ${CLUSTER_NAME_BLUE}, ${CLUSTER_NAME_GREEN}"
    echo "  - Cloud Source Repository: ${REPO_NAME}"
    echo "  - Container Images in gcr.io/${PROJECT_ID}/pwa-demo"
    echo "  - Cloud Build Triggers"
    if [[ -n "$BUCKET_NAME" ]]; then
        echo "  - Cloud Storage Bucket: gs://${BUCKET_NAME}"
    fi
    echo "  - Local repository directory: ${REPO_NAME}"
    echo ""
    
    read -p "Are you sure you want to continue? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Cleanup cancelled by user"
        exit 0
    fi
    
    log_info "Proceeding with resource cleanup..."
}

# Function to delete GKE clusters
delete_gke_clusters() {
    log_info "Deleting GKE clusters..."
    
    # Delete blue cluster
    if gcloud container clusters describe ${CLUSTER_NAME_BLUE} --region=${REGION} &>/dev/null; then
        execute_command "gcloud container clusters delete ${CLUSTER_NAME_BLUE} --region=${REGION} --quiet" "Deleting blue cluster"
    else
        log_warning "Blue cluster ${CLUSTER_NAME_BLUE} not found, skipping deletion"
    fi
    
    # Delete green cluster
    if gcloud container clusters describe ${CLUSTER_NAME_GREEN} --region=${REGION} &>/dev/null; then
        execute_command "gcloud container clusters delete ${CLUSTER_NAME_GREEN} --region=${REGION} --quiet" "Deleting green cluster"
    else
        log_warning "Green cluster ${CLUSTER_NAME_GREEN} not found, skipping deletion"
    fi
    
    log_success "GKE clusters deleted"
}

# Function to delete Cloud Build resources
delete_cloud_build_resources() {
    log_info "Deleting Cloud Build resources..."
    
    # Delete build triggers
    local trigger_ids=$(gcloud builds triggers list --filter="description~'PWA deployment trigger'" --format="value(id)" 2>/dev/null || echo "")
    if [[ -n "$trigger_ids" ]]; then
        for trigger_id in $trigger_ids; do
            execute_command "gcloud builds triggers delete ${trigger_id} --quiet" "Deleting build trigger ${trigger_id}"
        done
    else
        log_warning "No build triggers found for PWA deployment"
    fi
    
    # Delete container images
    local images=$(gcloud container images list --repository=gcr.io/${PROJECT_ID}/pwa-demo --format="value(name)" 2>/dev/null || echo "")
    if [[ -n "$images" ]]; then
        for image in $images; do
            execute_command "gcloud container images delete ${image} --force-delete-tags --quiet" "Deleting container image ${image}"
        done
    else
        log_warning "No container images found for pwa-demo"
    fi
    
    log_success "Cloud Build resources deleted"
}

# Function to delete Cloud Storage bucket
delete_storage_bucket() {
    log_info "Deleting Cloud Storage bucket..."
    
    if [[ -z "$BUCKET_NAME" ]]; then
        log_warning "Bucket name not specified, skipping bucket deletion"
        return 0
    fi
    
    # Check if bucket exists
    if gsutil ls -b gs://${BUCKET_NAME} &>/dev/null; then
        execute_command "gsutil -m rm -r gs://${BUCKET_NAME}" "Deleting storage bucket gs://${BUCKET_NAME}"
    else
        log_warning "Bucket gs://${BUCKET_NAME} not found, skipping deletion"
    fi
    
    log_success "Cloud Storage bucket deleted"
}

# Function to delete Cloud Source Repository
delete_source_repository() {
    log_info "Deleting Cloud Source Repository..."
    
    # Check if repository exists
    if gcloud source repos describe ${REPO_NAME} &>/dev/null; then
        execute_command "gcloud source repos delete ${REPO_NAME} --quiet" "Deleting Cloud Source Repository ${REPO_NAME}"
    else
        log_warning "Repository ${REPO_NAME} not found, skipping deletion"
    fi
    
    log_success "Cloud Source Repository deleted"
}

# Function to clean up local files
cleanup_local_files() {
    log_info "Cleaning up local files..."
    
    # Remove local repository directory
    if [[ -d "${REPO_NAME}" ]]; then
        execute_command "rm -rf ${REPO_NAME}" "Removing local repository directory ${REPO_NAME}"
    else
        log_warning "Local repository directory ${REPO_NAME} not found"
    fi
    
    # Remove any temporary files
    if [[ -f "/tmp/cors.json" ]]; then
        execute_command "rm -f /tmp/cors.json" "Removing temporary CORS configuration file"
    fi
    
    log_success "Local files cleaned up"
}

# Function to revoke IAM permissions (optional)
revoke_iam_permissions() {
    log_info "Checking IAM permissions..."
    
    # Get Cloud Build service account
    local cloud_build_sa=$(gcloud projects describe ${PROJECT_ID} --format="value(projectNumber)" 2>/dev/null)@cloudbuild.gserviceaccount.com
    
    if [[ -n "$cloud_build_sa" ]]; then
        log_info "Cloud Build service account: ${cloud_build_sa}"
        log_info "IAM permissions will remain (they may be used by other Cloud Build projects)"
        log_info "To manually revoke permissions, run:"
        echo "  gcloud projects remove-iam-policy-binding ${PROJECT_ID} --member='serviceAccount:${cloud_build_sa}' --role='roles/container.developer'"
        echo "  gcloud projects remove-iam-policy-binding ${PROJECT_ID} --member='serviceAccount:${cloud_build_sa}' --role='roles/storage.objectViewer'"
        echo "  gcloud projects remove-iam-policy-binding ${PROJECT_ID} --member='serviceAccount:${cloud_build_sa}' --role='roles/source.reader'"
    else
        log_warning "Could not determine Cloud Build service account"
    fi
    
    log_success "IAM permissions check completed"
}

# Function to delete compute resources (load balancers, IPs, etc.)
delete_compute_resources() {
    log_info "Deleting compute resources..."
    
    # Delete global IP addresses
    local ip_addresses=$(gcloud compute addresses list --global --filter="name~'pwa-demo'" --format="value(name)" 2>/dev/null || echo "")
    if [[ -n "$ip_addresses" ]]; then
        for ip in $ip_addresses; do
            execute_command "gcloud compute addresses delete ${ip} --global --quiet" "Deleting global IP address ${ip}"
        done
    else
        log_info "No global IP addresses found with 'pwa-demo' prefix"
    fi
    
    # Delete SSL certificates
    local ssl_certs=$(gcloud compute ssl-certificates list --filter="name~'pwa-demo'" --format="value(name)" 2>/dev/null || echo "")
    if [[ -n "$ssl_certs" ]]; then
        for cert in $ssl_certs; do
            execute_command "gcloud compute ssl-certificates delete ${cert} --quiet" "Deleting SSL certificate ${cert}"
        done
    else
        log_info "No SSL certificates found with 'pwa-demo' prefix"
    fi
    
    # Delete URL maps
    local url_maps=$(gcloud compute url-maps list --filter="name~'pwa-demo'" --format="value(name)" 2>/dev/null || echo "")
    if [[ -n "$url_maps" ]]; then
        for map in $url_maps; do
            execute_command "gcloud compute url-maps delete ${map} --quiet" "Deleting URL map ${map}"
        done
    else
        log_info "No URL maps found with 'pwa-demo' prefix"
    fi
    
    # Delete backend services
    local backend_services=$(gcloud compute backend-services list --filter="name~'pwa-demo'" --format="value(name)" 2>/dev/null || echo "")
    if [[ -n "$backend_services" ]]; then
        for service in $backend_services; do
            execute_command "gcloud compute backend-services delete ${service} --global --quiet" "Deleting backend service ${service}"
        done
    else
        log_info "No backend services found with 'pwa-demo' prefix"
    fi
    
    log_success "Compute resources cleanup completed"
}

# Function to check for remaining resources
check_remaining_resources() {
    log_info "Checking for remaining resources..."
    
    # Check for remaining clusters
    local clusters=$(gcloud container clusters list --filter="name~'pwa-cluster'" --format="value(name)" 2>/dev/null || echo "")
    if [[ -n "$clusters" ]]; then
        log_warning "Remaining clusters found: $clusters"
    fi
    
    # Check for remaining repositories
    local repos=$(gcloud source repos list --filter="name~'pwa-demo'" --format="value(name)" 2>/dev/null || echo "")
    if [[ -n "$repos" ]]; then
        log_warning "Remaining repositories found: $repos"
    fi
    
    # Check for remaining buckets
    local buckets=$(gsutil ls -p ${PROJECT_ID} 2>/dev/null | grep "pwa-assets-" || echo "")
    if [[ -n "$buckets" ]]; then
        log_warning "Remaining buckets found: $buckets"
    fi
    
    # Check for remaining container images
    local images=$(gcloud container images list --repository=gcr.io/${PROJECT_ID} --filter="name~'pwa-demo'" --format="value(name)" 2>/dev/null || echo "")
    if [[ -n "$images" ]]; then
        log_warning "Remaining container images found: $images"
    fi
    
    # Check for remaining build triggers
    local triggers=$(gcloud builds triggers list --filter="description~'PWA'" --format="value(name)" 2>/dev/null || echo "")
    if [[ -n "$triggers" ]]; then
        log_warning "Remaining build triggers found: $triggers"
    fi
    
    log_success "Resource check completed"
}

# Function to display cleanup summary
display_summary() {
    log_info "Cleanup Summary:"
    echo "================"
    echo "Project ID: ${PROJECT_ID}"
    echo "Region: ${REGION}"
    echo ""
    echo "Deleted resources:"
    echo "- GKE Clusters: ${CLUSTER_NAME_BLUE}, ${CLUSTER_NAME_GREEN}"
    echo "- Cloud Source Repository: ${REPO_NAME}"
    echo "- Container Images: gcr.io/${PROJECT_ID}/pwa-demo"
    echo "- Cloud Build Triggers"
    if [[ -n "$BUCKET_NAME" ]]; then
        echo "- Cloud Storage Bucket: gs://${BUCKET_NAME}"
    fi
    echo "- Local repository directory: ${REPO_NAME}"
    echo ""
    echo "Note: Some resources may take a few minutes to be completely removed."
    echo ""
    echo "To verify complete cleanup, run:"
    echo "  gcloud container clusters list"
    echo "  gcloud source repos list"
    echo "  gsutil ls -p ${PROJECT_ID}"
    echo "  gcloud builds triggers list"
    echo "  gcloud container images list"
    echo ""
    log_success "Cleanup completed successfully!"
}

# Function to handle script interruption
cleanup_on_interrupt() {
    log_error "Script interrupted!"
    log_info "Some resources may not have been deleted completely."
    log_info "You can run this script again or manually delete remaining resources."
    exit 1
}

# Main cleanup function
main() {
    log_info "Starting Progressive Web Application resource cleanup..."
    
    # Execute cleanup steps
    check_prerequisites
    setup_environment
    confirm_deletion
    
    # Delete resources in reverse order of creation
    delete_compute_resources
    delete_gke_clusters
    delete_cloud_build_resources
    delete_storage_bucket
    delete_source_repository
    cleanup_local_files
    revoke_iam_permissions
    
    # Check for any remaining resources
    check_remaining_resources
    
    # Display summary
    display_summary
}

# Handle script interruption
trap cleanup_on_interrupt INT TERM

# Run main function
main "$@"