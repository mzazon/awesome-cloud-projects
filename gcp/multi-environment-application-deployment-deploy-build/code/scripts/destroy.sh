#!/bin/bash

# Destroy script for Multi-Environment Application Deployment with Cloud Deploy and Cloud Build
# This script cleans up all resources created during the deployment process

set -e  # Exit on any error
set -o pipefail  # Exit on pipe failures

# Color codes for output
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

# Global variables
FORCE_DELETE=false
DELETE_PROJECT=false

# Parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --force)
                FORCE_DELETE=true
                shift
                ;;
            --delete-project)
                DELETE_PROJECT=true
                shift
                ;;
            --help)
                show_help
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

# Show help information
show_help() {
    cat << EOF
Usage: $0 [OPTIONS]

Options:
    --force             Skip confirmation prompts
    --delete-project    Delete the entire GCP project (use with caution)
    --help              Show this help message

Examples:
    $0                  # Interactive cleanup with confirmations
    $0 --force          # Force cleanup without confirmations
    $0 --delete-project # Delete the entire project
EOF
}

# Confirmation prompt
confirm_action() {
    local message="$1"
    local default_response="${2:-n}"
    
    if [ "$FORCE_DELETE" = true ]; then
        log_info "Force mode enabled, skipping confirmation for: $message"
        return 0
    fi
    
    read -p "$message (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        return 0
    else
        return 1
    fi
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    if ! command -v gcloud &> /dev/null; then
        log_error "gcloud CLI is not installed. Please install it first."
        exit 1
    fi
    
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl is not installed. Please install it first."
        exit 1
    fi
    
    # Check if user is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        log_error "No active gcloud authentication found. Please run 'gcloud auth login'"
        exit 1
    fi
    
    log_success "Prerequisites check passed"
}

# Load environment variables
load_environment() {
    log_info "Loading environment variables..."
    
    # Check if environment variables are set
    if [[ -z "${PROJECT_ID:-}" ]]; then
        log_error "PROJECT_ID environment variable is not set"
        log_info "Please set the PROJECT_ID environment variable to the project you want to clean up"
        exit 1
    fi
    
    # Set default values for other variables
    export REGION="${REGION:-us-central1}"
    export ZONE="${ZONE:-us-central1-a}"
    export CLUSTER_PREFIX="${CLUSTER_PREFIX:-deploy-demo}"
    export PIPELINE_NAME="${PIPELINE_NAME:-sample-app-pipeline}"
    export APP_NAME="${APP_NAME:-sample-webapp}"
    
    log_info "Project ID: ${PROJECT_ID}"
    log_info "Region: ${REGION}"
    log_info "Zone: ${ZONE}"
    log_info "Cluster Prefix: ${CLUSTER_PREFIX}"
    log_info "Pipeline Name: ${PIPELINE_NAME}"
    log_info "App Name: ${APP_NAME}"
    
    # Set current project
    gcloud config set project "${PROJECT_ID}"
    
    log_success "Environment variables loaded"
}

# Delete Cloud Deploy pipeline and targets
delete_cloud_deploy_pipeline() {
    log_info "Deleting Cloud Deploy pipeline and targets..."
    
    # List existing pipelines
    local pipelines
    pipelines=$(gcloud deploy delivery-pipelines list --region="${REGION}" --format="value(name)" 2>/dev/null || echo "")
    
    if [[ -n "$pipelines" ]]; then
        if confirm_action "Delete Cloud Deploy pipeline '${PIPELINE_NAME}' and all its resources?"; then
            # Delete the delivery pipeline (this will also delete associated targets)
            if gcloud deploy delivery-pipelines describe "${PIPELINE_NAME}" --region="${REGION}" &> /dev/null; then
                gcloud deploy delivery-pipelines delete "${PIPELINE_NAME}" \
                    --region="${REGION}" \
                    --quiet
                log_success "Cloud Deploy pipeline deleted: ${PIPELINE_NAME}"
            else
                log_warning "Cloud Deploy pipeline not found: ${PIPELINE_NAME}"
            fi
            
            # Wait for pipeline deletion to complete
            log_info "Waiting for pipeline deletion to complete..."
            local timeout=300
            local elapsed=0
            while gcloud deploy delivery-pipelines describe "${PIPELINE_NAME}" --region="${REGION}" &> /dev/null; do
                if [ $elapsed -ge $timeout ]; then
                    log_warning "Timeout waiting for pipeline deletion"
                    break
                fi
                sleep 10
                elapsed=$((elapsed + 10))
            done
        else
            log_info "Skipping Cloud Deploy pipeline deletion"
        fi
    else
        log_info "No Cloud Deploy pipelines found"
    fi
}

# Delete GKE clusters
delete_gke_clusters() {
    log_info "Deleting GKE clusters..."
    
    local environments=("dev" "staging" "prod")
    local clusters_to_delete=()
    
    # Find existing clusters
    for env in "${environments[@]}"; do
        local cluster_name="${CLUSTER_PREFIX}-${env}"
        if gcloud container clusters describe "${cluster_name}" --region="${REGION}" &> /dev/null; then
            clusters_to_delete+=("${cluster_name}")
        fi
    done
    
    if [ ${#clusters_to_delete[@]} -gt 0 ]; then
        if confirm_action "Delete ${#clusters_to_delete[@]} GKE clusters (${clusters_to_delete[*]})?"; then
            # Delete clusters in parallel
            for cluster in "${clusters_to_delete[@]}"; do
                log_info "Deleting cluster: ${cluster}"
                gcloud container clusters delete "${cluster}" \
                    --region="${REGION}" \
                    --quiet \
                    --async
            done
            
            # Wait for all clusters to be deleted
            log_info "Waiting for cluster deletion to complete..."
            for cluster in "${clusters_to_delete[@]}"; do
                while gcloud container clusters describe "${cluster}" --region="${REGION}" &> /dev/null; do
                    log_info "Waiting for ${cluster} to be deleted..."
                    sleep 30
                done
                log_success "Cluster deleted: ${cluster}"
            done
        else
            log_info "Skipping GKE cluster deletion"
        fi
    else
        log_info "No GKE clusters found with prefix: ${CLUSTER_PREFIX}"
    fi
}

# Delete Cloud Build triggers
delete_cloud_build_triggers() {
    log_info "Deleting Cloud Build triggers..."
    
    local trigger_name="${APP_NAME}-trigger"
    
    # Check if trigger exists
    if gcloud builds triggers describe "${trigger_name}" --region="${REGION}" &> /dev/null; then
        if confirm_action "Delete Cloud Build trigger '${trigger_name}'?"; then
            gcloud builds triggers delete "${trigger_name}" \
                --region="${REGION}" \
                --quiet
            log_success "Cloud Build trigger deleted: ${trigger_name}"
        else
            log_info "Skipping Cloud Build trigger deletion"
        fi
    else
        log_info "Cloud Build trigger not found: ${trigger_name}"
    fi
}

# Delete container images
delete_container_images() {
    log_info "Deleting container images..."
    
    local image_repo="gcr.io/${PROJECT_ID}/${APP_NAME}"
    
    # Check if images exist
    local images
    images=$(gcloud container images list-tags "${image_repo}" --format="get(digest)" 2>/dev/null || echo "")
    
    if [[ -n "$images" ]]; then
        local image_count
        image_count=$(echo "$images" | wc -l)
        
        if confirm_action "Delete ${image_count} container images from ${image_repo}?"; then
            # Delete all images
            echo "$images" | while read -r digest; do
                if [[ -n "$digest" ]]; then
                    gcloud container images delete "${image_repo}@${digest}" --quiet
                fi
            done
            log_success "Container images deleted from: ${image_repo}"
        else
            log_info "Skipping container image deletion"
        fi
    else
        log_info "No container images found for: ${image_repo}"
    fi
}

# Delete service accounts
delete_service_accounts() {
    log_info "Deleting service accounts..."
    
    local sa_name="clouddeploy-sa"
    local sa_email="${sa_name}@${PROJECT_ID}.iam.gserviceaccount.com"
    
    # Check if service account exists
    if gcloud iam service-accounts describe "${sa_email}" &> /dev/null; then
        if confirm_action "Delete service account '${sa_email}'?"; then
            gcloud iam service-accounts delete "${sa_email}" --quiet
            log_success "Service account deleted: ${sa_email}"
        else
            log_info "Skipping service account deletion"
        fi
    else
        log_info "Service account not found: ${sa_email}"
    fi
}

# Delete Cloud Storage buckets
delete_storage_buckets() {
    log_info "Deleting Cloud Storage buckets..."
    
    local bucket_name="${PROJECT_ID}-build-artifacts"
    
    # Check if bucket exists
    if gsutil ls gs://"${bucket_name}" &> /dev/null; then
        if confirm_action "Delete Cloud Storage bucket 'gs://${bucket_name}' and all its contents?"; then
            gsutil -m rm -r gs://"${bucket_name}"
            log_success "Storage bucket deleted: gs://${bucket_name}"
        else
            log_info "Skipping storage bucket deletion"
        fi
    else
        log_info "Storage bucket not found: gs://${bucket_name}"
    fi
}

# Clean up local files
cleanup_local_files() {
    log_info "Cleaning up local files..."
    
    if [ -d "${APP_NAME}" ]; then
        if confirm_action "Delete local application directory '${APP_NAME}'?"; then
            rm -rf "${APP_NAME}"
            log_success "Local application directory deleted: ${APP_NAME}"
        else
            log_info "Skipping local file cleanup"
        fi
    else
        log_info "Local application directory not found: ${APP_NAME}"
    fi
}

# Delete entire project
delete_project() {
    if [ "$DELETE_PROJECT" = true ]; then
        log_warning "About to delete the entire project: ${PROJECT_ID}"
        log_warning "This action is IRREVERSIBLE and will delete ALL resources in the project!"
        
        if confirm_action "Are you absolutely sure you want to delete the entire project '${PROJECT_ID}'?"; then
            log_info "Deleting project: ${PROJECT_ID}"
            gcloud projects delete "${PROJECT_ID}" --quiet
            log_success "Project deletion initiated: ${PROJECT_ID}"
            log_info "Project deletion may take several minutes to complete"
        else
            log_info "Project deletion cancelled"
        fi
    fi
}

# Verify cleanup
verify_cleanup() {
    log_info "Verifying cleanup..."
    
    local cleanup_successful=true
    
    # Check if Cloud Deploy pipeline still exists
    if gcloud deploy delivery-pipelines describe "${PIPELINE_NAME}" --region="${REGION}" &> /dev/null; then
        log_warning "Cloud Deploy pipeline still exists: ${PIPELINE_NAME}"
        cleanup_successful=false
    fi
    
    # Check if GKE clusters still exist
    local environments=("dev" "staging" "prod")
    for env in "${environments[@]}"; do
        local cluster_name="${CLUSTER_PREFIX}-${env}"
        if gcloud container clusters describe "${cluster_name}" --region="${REGION}" &> /dev/null; then
            log_warning "GKE cluster still exists: ${cluster_name}"
            cleanup_successful=false
        fi
    done
    
    # Check if Cloud Build trigger still exists
    if gcloud builds triggers describe "${APP_NAME}-trigger" --region="${REGION}" &> /dev/null; then
        log_warning "Cloud Build trigger still exists: ${APP_NAME}-trigger"
        cleanup_successful=false
    fi
    
    # Check if service account still exists
    local sa_email="clouddeploy-sa@${PROJECT_ID}.iam.gserviceaccount.com"
    if gcloud iam service-accounts describe "${sa_email}" &> /dev/null; then
        log_warning "Service account still exists: ${sa_email}"
        cleanup_successful=false
    fi
    
    # Check if storage bucket still exists
    local bucket_name="${PROJECT_ID}-build-artifacts"
    if gsutil ls gs://"${bucket_name}" &> /dev/null; then
        log_warning "Storage bucket still exists: gs://${bucket_name}"
        cleanup_successful=false
    fi
    
    if [ "$cleanup_successful" = true ]; then
        log_success "Cleanup verification passed - all resources have been removed"
    else
        log_warning "Some resources may still exist - manual cleanup may be required"
    fi
}

# Show cleanup summary
show_cleanup_summary() {
    log_info "Cleanup Summary:"
    log_info "=================="
    log_info "The following resources were targeted for deletion:"
    log_info "- Cloud Deploy pipeline: ${PIPELINE_NAME}"
    log_info "- GKE clusters: ${CLUSTER_PREFIX}-{dev,staging,prod}"
    log_info "- Cloud Build trigger: ${APP_NAME}-trigger"
    log_info "- Container images: gcr.io/${PROJECT_ID}/${APP_NAME}"
    log_info "- Service account: clouddeploy-sa@${PROJECT_ID}.iam.gserviceaccount.com"
    log_info "- Storage bucket: gs://${PROJECT_ID}-build-artifacts"
    log_info "- Local application directory: ${APP_NAME}"
    
    if [ "$DELETE_PROJECT" = true ]; then
        log_info "- Entire project: ${PROJECT_ID}"
    fi
    
    log_info ""
    log_info "To avoid future charges, verify that all resources have been deleted"
    log_info "in the Google Cloud Console: https://console.cloud.google.com"
}

# Main cleanup function
main() {
    log_info "Starting cleanup of multi-environment application deployment..."
    
    parse_arguments "$@"
    check_prerequisites
    load_environment
    
    log_warning "This will delete resources for project: ${PROJECT_ID}"
    if [ "$FORCE_DELETE" = false ]; then
        if ! confirm_action "Do you want to proceed with the cleanup?"; then
            log_info "Cleanup cancelled by user"
            exit 0
        fi
    fi
    
    # Perform cleanup in reverse order of creation
    delete_cloud_deploy_pipeline
    delete_gke_clusters
    delete_cloud_build_triggers
    delete_container_images
    delete_service_accounts
    delete_storage_buckets
    cleanup_local_files
    
    # Delete project if requested
    delete_project
    
    # Verify cleanup (skip if project was deleted)
    if [ "$DELETE_PROJECT" = false ]; then
        verify_cleanup
    fi
    
    show_cleanup_summary
    
    log_success "Multi-environment application deployment cleanup completed!"
}

# Run main function with all arguments
main "$@"