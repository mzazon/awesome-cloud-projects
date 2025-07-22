#!/bin/bash

# Code Quality Gates with Cloud Build Triggers and Cloud Deploy - Cleanup Script
# This script removes all resources created by the deployment script

set -euo pipefail

# Color codes for output formatting
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

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
cleanup_on_error() {
    log_error "Cleanup script encountered an error!"
    log_warning "Some resources may not have been deleted. Please check the GCP console."
    exit 1
}

trap cleanup_on_error ERR

# Load environment variables from .env file
load_environment() {
    if [ -f ".env" ]; then
        log_info "Loading environment variables from .env file..."
        source .env
        log_success "Environment variables loaded successfully"
        log_info "Project ID: ${PROJECT_ID:-'Not Set'}"
        log_info "Repository: ${REPO_NAME:-'Not Set'}"
        log_info "Cluster: ${CLUSTER_NAME:-'Not Set'}"
        log_info "Pipeline: ${PIPELINE_NAME:-'Not Set'}"
    else
        log_error ".env file not found!"
        log_error "Please ensure you're running this script from the same directory as deploy.sh"
        log_error "Or manually set the required environment variables:"
        log_error "  PROJECT_ID, REGION, ZONE, REPO_NAME, CLUSTER_NAME, PIPELINE_NAME"
        exit 1
    fi
    
    # Validate required variables
    local required_vars=("PROJECT_ID" "REGION" "ZONE" "REPO_NAME" "CLUSTER_NAME" "PIPELINE_NAME")
    for var in "${required_vars[@]}"; do
        if [ -z "${!var:-}" ]; then
            log_error "Required environment variable ${var} is not set!"
            exit 1
        fi
    done
}

# Confirm destruction
confirm_destruction() {
    log_warning "This will permanently delete all resources created by the deployment script!"
    log_warning "Project: ${PROJECT_ID}"
    log_warning "This action cannot be undone!"
    echo ""
    
    # Double confirmation for safety
    read -p "Are you sure you want to proceed? (yes/no): " confirm1
    if [ "${confirm1}" != "yes" ]; then
        log_info "Cleanup cancelled by user."
        exit 0
    fi
    
    read -p "Type 'DELETE' to confirm resource destruction: " confirm2
    if [ "${confirm2}" != "DELETE" ]; then
        log_info "Cleanup cancelled by user."
        exit 0
    fi
    
    log_info "Proceeding with resource cleanup..."
}

# Set up gcloud configuration
setup_gcloud() {
    log_info "Setting up gcloud configuration..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "gcloud CLI is not installed!"
        exit 1
    fi
    
    # Set project configuration
    gcloud config set project ${PROJECT_ID}
    gcloud config set compute/region ${REGION}
    gcloud config set compute/zone ${ZONE}
    
    log_success "gcloud configuration set"
}

# Delete Cloud Deploy resources
cleanup_cloud_deploy() {
    log_info "Cleaning up Cloud Deploy resources..."
    
    # Delete delivery pipeline
    if gcloud deploy delivery-pipelines describe ${PIPELINE_NAME} --region=${REGION} &>/dev/null; then
        log_info "Deleting Cloud Deploy pipeline: ${PIPELINE_NAME}"
        gcloud deploy delivery-pipelines delete ${PIPELINE_NAME} \
            --region=${REGION} \
            --quiet 2>/dev/null || log_warning "Failed to delete Cloud Deploy pipeline"
        log_success "Cloud Deploy pipeline deleted"
    else
        log_warning "Cloud Deploy pipeline ${PIPELINE_NAME} not found"
    fi
    
    # Delete targets (they should be deleted with the pipeline, but check anyway)
    local targets=("development" "staging" "production")
    for target in "${targets[@]}"; do
        if gcloud deploy targets describe ${target} --region=${REGION} &>/dev/null; then
            log_info "Deleting Cloud Deploy target: ${target}"
            gcloud deploy targets delete ${target} \
                --region=${REGION} \
                --quiet 2>/dev/null || log_warning "Failed to delete target ${target}"
        fi
    done
    
    log_success "Cloud Deploy resources cleanup completed"
}

# Delete GKE cluster
cleanup_gke_cluster() {
    log_info "Cleaning up GKE cluster..."
    
    if gcloud container clusters describe ${CLUSTER_NAME} --zone=${ZONE} &>/dev/null; then
        log_info "Deleting GKE cluster: ${CLUSTER_NAME}"
        log_warning "This may take several minutes..."
        
        # Delete the cluster
        gcloud container clusters delete ${CLUSTER_NAME} \
            --zone=${ZONE} \
            --quiet 2>/dev/null || log_warning "Failed to delete GKE cluster"
        
        log_success "GKE cluster deleted successfully"
    else
        log_warning "GKE cluster ${CLUSTER_NAME} not found"
    fi
}

# Delete Cloud Build resources
cleanup_cloud_build() {
    log_info "Cleaning up Cloud Build resources..."
    
    # Delete Cloud Build triggers
    local trigger_ids=$(gcloud builds triggers list \
        --filter="github.name:${REPO_NAME} OR triggerTemplate.repoName:${REPO_NAME}" \
        --format="value(id)" 2>/dev/null || echo "")
    
    if [ -n "${trigger_ids}" ]; then
        for trigger_id in ${trigger_ids}; do
            log_info "Deleting Cloud Build trigger: ${trigger_id}"
            gcloud builds triggers delete ${trigger_id} \
                --quiet 2>/dev/null || log_warning "Failed to delete trigger ${trigger_id}"
        done
        log_success "Cloud Build triggers deleted"
    else
        log_warning "No Cloud Build triggers found for repository ${REPO_NAME}"
    fi
    
    # Cancel any running builds
    local running_builds=$(gcloud builds list \
        --filter="status=WORKING AND source.repoSource.repoName:${REPO_NAME}" \
        --format="value(id)" 2>/dev/null || echo "")
    
    if [ -n "${running_builds}" ]; then
        for build_id in ${running_builds}; do
            log_info "Cancelling running build: ${build_id}"
            gcloud builds cancel ${build_id} \
                --quiet 2>/dev/null || log_warning "Failed to cancel build ${build_id}"
        done
        log_success "Running builds cancelled"
    fi
}

# Delete container images
cleanup_container_images() {
    log_info "Cleaning up container images..."
    
    # Delete container images from Container Registry
    local images=$(gcloud container images list \
        --repository=gcr.io/${PROJECT_ID} \
        --filter="name:code-quality-app" \
        --format="value(name)" 2>/dev/null || echo "")
    
    if [ -n "${images}" ]; then
        for image in ${images}; do
            log_info "Deleting container image: ${image}"
            gcloud container images delete ${image} \
                --force-delete-tags \
                --quiet 2>/dev/null || log_warning "Failed to delete image ${image}"
        done
        log_success "Container images deleted"
    else
        log_warning "No container images found for code-quality-app"
    fi
}

# Delete source repository
cleanup_source_repository() {
    log_info "Cleaning up Cloud Source Repository..."
    
    if gcloud source repos describe ${REPO_NAME} &>/dev/null; then
        log_info "Deleting Cloud Source Repository: ${REPO_NAME}"
        gcloud source repos delete ${REPO_NAME} \
            --quiet 2>/dev/null || log_warning "Failed to delete source repository"
        log_success "Cloud Source Repository deleted"
    else
        log_warning "Cloud Source Repository ${REPO_NAME} not found"
    fi
    
    # Remove local repository clone if it exists
    if [ -d "${REPO_NAME}" ]; then
        log_info "Removing local repository clone..."
        rm -rf ${REPO_NAME}
        log_success "Local repository clone removed"
    fi
}

# Reset Binary Authorization policy
cleanup_binary_authorization() {
    log_info "Resetting Binary Authorization policy..."
    
    # Reset to default policy (allow all)
    cat > /tmp/default-binauth-policy.yaml << 'EOF'
defaultAdmissionRule:
  enforcementMode: ALWAYS_ALLOW
  evaluationMode: ALWAYS_ALLOW
clusterAdmissionRules: {}
admissionWhitelistPatterns: []
EOF
    
    gcloud container binauthz policy import /tmp/default-binauth-policy.yaml \
        2>/dev/null || log_warning "Failed to reset Binary Authorization policy"
    
    # Clean up temporary file
    rm -f /tmp/default-binauth-policy.yaml
    
    log_success "Binary Authorization policy reset to default"
}

# Delete the entire project (optional)
cleanup_project() {
    log_warning "Final step: Delete the entire project"
    log_warning "This will delete ALL resources in project ${PROJECT_ID}"
    echo ""
    
    read -p "Do you want to delete the entire project? (yes/no): " delete_project
    if [ "${delete_project}" = "yes" ]; then
        read -p "Type the project ID '${PROJECT_ID}' to confirm: " confirm_project
        if [ "${confirm_project}" = "${PROJECT_ID}" ]; then
            log_info "Deleting project: ${PROJECT_ID}"
            gcloud projects delete ${PROJECT_ID} \
                --quiet 2>/dev/null || log_warning "Failed to delete project"
            log_success "Project deletion initiated (may take a few minutes to complete)"
        else
            log_warning "Project ID confirmation failed. Project not deleted."
        fi
    else
        log_info "Project ${PROJECT_ID} preserved"
        log_warning "Remember to manually delete the project later to avoid ongoing charges"
    fi
}

# Clean up local files
cleanup_local_files() {
    log_info "Cleaning up local files..."
    
    # Remove environment file
    if [ -f ".env" ]; then
        rm -f .env
        log_success "Environment file removed"
    fi
    
    # Remove any temporary files
    rm -f binauth-policy.yaml 2>/dev/null || true
    rm -f clouddeploy.yaml 2>/dev/null || true
    rm -f skaffold.yaml 2>/dev/null || true
    
    log_success "Local cleanup completed"
}

# Validate cleanup completion
validate_cleanup() {
    log_info "Validating cleanup completion..."
    
    local cleanup_errors=0
    
    # Check if GKE cluster is gone
    if gcloud container clusters describe ${CLUSTER_NAME} --zone=${ZONE} &>/dev/null; then
        log_warning "GKE cluster ${CLUSTER_NAME} still exists"
        ((cleanup_errors++))
    fi
    
    # Check if Cloud Deploy pipeline is gone
    if gcloud deploy delivery-pipelines describe ${PIPELINE_NAME} --region=${REGION} &>/dev/null; then
        log_warning "Cloud Deploy pipeline ${PIPELINE_NAME} still exists"
        ((cleanup_errors++))
    fi
    
    # Check if source repository is gone
    if gcloud source repos describe ${REPO_NAME} &>/dev/null; then
        log_warning "Source repository ${REPO_NAME} still exists"
        ((cleanup_errors++))
    fi
    
    if [ ${cleanup_errors} -eq 0 ]; then
        log_success "All resources successfully cleaned up!"
    else
        log_warning "${cleanup_errors} resources may not have been fully deleted"
        log_warning "Please check the GCP console and delete remaining resources manually"
    fi
}

# Display cleanup summary
display_cleanup_summary() {
    log_info "Cleanup Summary:"
    echo "===================="
    echo "Project ID: ${PROJECT_ID}"
    echo "Region: ${REGION}"
    echo "Zone: ${ZONE}"
    echo ""
    echo "Resources cleaned up:"
    echo "✓ Cloud Deploy pipeline and targets"
    echo "✓ GKE cluster and namespaces"
    echo "✓ Cloud Build triggers and builds"
    echo "✓ Container images"
    echo "✓ Cloud Source Repository"
    echo "✓ Binary Authorization policy reset"
    echo "✓ Local files and configurations"
    echo ""
    echo "If you deleted the entire project, all billing will stop."
    echo "If you kept the project, verify no billable resources remain."
    echo "===================="
}

# Main execution
main() {
    log_info "Starting Code Quality Gates cleanup..."
    
    load_environment
    confirm_destruction
    setup_gcloud
    cleanup_cloud_deploy
    cleanup_gke_cluster
    cleanup_cloud_build
    cleanup_container_images
    cleanup_source_repository
    cleanup_binary_authorization
    cleanup_project
    cleanup_local_files
    validate_cleanup
    display_cleanup_summary
    
    log_success "Code Quality Gates cleanup completed!"
}

# Run main function
main "$@"