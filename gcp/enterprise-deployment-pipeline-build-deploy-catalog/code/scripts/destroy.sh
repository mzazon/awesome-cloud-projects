#!/bin/bash

# Enterprise Deployment Pipeline Cleanup Script
# This script removes all resources created by the deployment pipeline

set -e  # Exit on any error
set -u  # Exit on undefined variables

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

# Function to check if required tools are installed
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "Google Cloud CLI (gcloud) is not installed. Please install it first."
        exit 1
    fi
    
    # Check if user is authenticated with gcloud
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        log_error "Not authenticated with Google Cloud. Please run 'gcloud auth login' first."
        exit 1
    fi
    
    log_success "Prerequisites check passed"
}

# Function to set up environment variables
setup_environment() {
    log_info "Setting up environment variables..."
    
    # Get current project if not set
    if [[ -z "${PROJECT_ID:-}" ]]; then
        export PROJECT_ID=$(gcloud config get-value project 2>/dev/null)
        if [[ -z "${PROJECT_ID}" ]]; then
            log_error "No Google Cloud project set. Please set PROJECT_ID environment variable or configure default project."
            exit 1
        fi
    fi
    
    # Set default values for environment variables
    export REGION="${REGION:-us-central1}"
    export ZONE="${ZONE:-us-central1-a}"
    export REPO_NAME="${REPO_NAME:-enterprise-apps}"
    
    # Set gcloud defaults
    gcloud config set project "${PROJECT_ID}"
    gcloud config set compute/region "${REGION}"
    gcloud config set compute/zone "${ZONE}"
    
    log_success "Environment configured for project: ${PROJECT_ID}"
    log_info "Using region: ${REGION}, zone: ${ZONE}"
}

# Function to get user confirmation
confirm_destruction() {
    log_warning "This script will permanently delete the following resources:"
    echo "  - All GKE clusters (dev, staging, prod)"
    echo "  - Cloud Deploy delivery pipeline and targets"
    echo "  - Artifact Registry repository and all images"
    echo "  - Cloud Build triggers"
    echo "  - Cloud Source repositories"
    echo "  - IAM service accounts and bindings"
    echo "  - Local repository directories"
    echo
    log_warning "This action CANNOT be undone!"
    echo
    
    if [[ "${FORCE_DELETE:-}" == "true" ]]; then
        log_info "FORCE_DELETE=true, skipping confirmation"
        return 0
    fi
    
    read -p "Are you sure you want to continue? (type 'yes' to confirm): " confirmation
    if [[ "${confirmation}" != "yes" ]]; then
        log_info "Destruction cancelled by user"
        exit 0
    fi
    
    log_info "Proceeding with resource destruction..."
}

# Function to find and delete GKE clusters
cleanup_gke_clusters() {
    log_info "Cleaning up GKE clusters..."
    
    # Find all clusters that match our naming pattern
    local clusters=$(gcloud container clusters list \
        --format="value(name)" \
        --filter="name~enterprise-gke-.*" 2>/dev/null || true)
    
    if [[ -z "${clusters}" ]]; then
        log_info "No GKE clusters found matching pattern 'enterprise-gke-*'"
        return 0
    fi
    
    # Delete each cluster
    while IFS= read -r cluster; do
        if [[ -n "${cluster}" ]]; then
            log_info "Deleting GKE cluster: ${cluster}"
            if gcloud container clusters delete "${cluster}" \
                --region="${REGION}" \
                --quiet 2>/dev/null; then
                log_success "Deleted GKE cluster: ${cluster}"
            else
                log_warning "Failed to delete or cluster not found: ${cluster}"
            fi
        fi
    done <<< "${clusters}"
    
    log_success "GKE cluster cleanup completed"
}

# Function to cleanup Cloud Deploy resources
cleanup_cloud_deploy() {
    log_info "Cleaning up Cloud Deploy resources..."
    
    # Delete delivery pipeline
    if gcloud deploy delivery-pipelines describe enterprise-pipeline \
        --region="${REGION}" &>/dev/null; then
        log_info "Deleting Cloud Deploy pipeline: enterprise-pipeline"
        if gcloud deploy delivery-pipelines delete enterprise-pipeline \
            --region="${REGION}" \
            --quiet; then
            log_success "Deleted Cloud Deploy pipeline: enterprise-pipeline"
        else
            log_warning "Failed to delete Cloud Deploy pipeline"
        fi
    else
        log_info "Cloud Deploy pipeline 'enterprise-pipeline' not found"
    fi
    
    log_success "Cloud Deploy cleanup completed"
}

# Function to cleanup Artifact Registry
cleanup_artifact_registry() {
    log_info "Cleaning up Artifact Registry..."
    
    # Check if repository exists
    if gcloud artifacts repositories describe "${REPO_NAME}" \
        --location="${REGION}" &>/dev/null; then
        log_info "Deleting Artifact Registry repository: ${REPO_NAME}"
        if gcloud artifacts repositories delete "${REPO_NAME}" \
            --location="${REGION}" \
            --quiet; then
            log_success "Deleted Artifact Registry repository: ${REPO_NAME}"
        else
            log_warning "Failed to delete Artifact Registry repository"
        fi
    else
        log_info "Artifact Registry repository '${REPO_NAME}' not found"
    fi
    
    log_success "Artifact Registry cleanup completed"
}

# Function to cleanup Cloud Build triggers
cleanup_build_triggers() {
    log_info "Cleaning up Cloud Build triggers..."
    
    # Get all triggers related to our repositories
    local triggers=$(gcloud builds triggers list \
        --format="value(id)" \
        --filter="github.name~sample-app OR \
                  github.name~pipeline-templates OR \
                  name~enterprise" 2>/dev/null || true)
    
    if [[ -z "${triggers}" ]]; then
        log_info "No Cloud Build triggers found"
        return 0
    fi
    
    # Delete each trigger
    while IFS= read -r trigger_id; do
        if [[ -n "${trigger_id}" ]]; then
            log_info "Deleting build trigger: ${trigger_id}"
            if gcloud builds triggers delete "${trigger_id}" --quiet; then
                log_success "Deleted build trigger: ${trigger_id}"
            else
                log_warning "Failed to delete build trigger: ${trigger_id}"
            fi
        fi
    done <<< "${triggers}"
    
    log_success "Build triggers cleanup completed"
}

# Function to cleanup Cloud Source repositories
cleanup_source_repositories() {
    log_info "Cleaning up Cloud Source repositories..."
    
    local repos=("pipeline-templates" "sample-app")
    
    for repo in "${repos[@]}"; do
        # Check if repository exists
        if gcloud source repos describe "${repo}" &>/dev/null; then
            log_info "Deleting source repository: ${repo}"
            if gcloud source repos delete "${repo}" --quiet; then
                log_success "Deleted source repository: ${repo}"
            else
                log_warning "Failed to delete source repository: ${repo}"
            fi
        else
            log_info "Source repository '${repo}' not found"
        fi
    done
    
    log_success "Source repositories cleanup completed"
}

# Function to cleanup IAM resources
cleanup_iam_resources() {
    log_info "Cleaning up IAM resources..."
    
    local service_account="cloudbuild-deploy@${PROJECT_ID}.iam.gserviceaccount.com"
    
    # Check if service account exists
    if gcloud iam service-accounts describe "${service_account}" &>/dev/null; then
        log_info "Removing IAM policy bindings for service account..."
        
        # Remove policy bindings
        local roles=(
            "roles/clouddeploy.operator"
            "roles/container.clusterAdmin"
            "roles/artifactregistry.writer"
        )
        
        for role in "${roles[@]}"; do
            log_info "Removing role ${role} from service account..."
            if gcloud projects remove-iam-policy-binding "${PROJECT_ID}" \
                --member="serviceAccount:${service_account}" \
                --role="${role}" \
                --quiet 2>/dev/null; then
                log_success "Removed role: ${role}"
            else
                log_warning "Failed to remove or role not found: ${role}"
            fi
        done
        
        # Remove service account user role from Cloud Build
        log_info "Removing service account user role from Cloud Build..."
        if gcloud projects remove-iam-policy-binding "${PROJECT_ID}" \
            --member="serviceAccount:${PROJECT_ID}@cloudbuild.gserviceaccount.com" \
            --role="roles/iam.serviceAccountUser" \
            --quiet 2>/dev/null; then
            log_success "Removed Cloud Build service account user role"
        else
            log_warning "Failed to remove Cloud Build service account user role"
        fi
        
        # Delete service account
        log_info "Deleting service account: ${service_account}"
        if gcloud iam service-accounts delete "${service_account}" --quiet; then
            log_success "Deleted service account: ${service_account}"
        else
            log_warning "Failed to delete service account"
        fi
    else
        log_info "Service account 'cloudbuild-deploy' not found"
    fi
    
    log_success "IAM resources cleanup completed"
}

# Function to cleanup local directories
cleanup_local_directories() {
    log_info "Cleaning up local directories..."
    
    local dirs=("pipeline-templates" "sample-app")
    
    for dir in "${dirs[@]}"; do
        if [[ -d "./${dir}" ]]; then
            log_info "Removing local directory: ${dir}"
            rm -rf "./${dir}"
            log_success "Removed local directory: ${dir}"
        else
            log_info "Local directory '${dir}' not found"
        fi
    done
    
    log_success "Local directories cleanup completed"
}

# Function to cleanup any remaining Cloud Build resources
cleanup_remaining_builds() {
    log_info "Cleaning up any remaining Cloud Build resources..."
    
    # Cancel any ongoing builds
    local ongoing_builds=$(gcloud builds list \
        --ongoing \
        --format="value(id)" 2>/dev/null || true)
    
    if [[ -n "${ongoing_builds}" ]]; then
        log_warning "Found ongoing builds, attempting to cancel..."
        while IFS= read -r build_id; do
            if [[ -n "${build_id}" ]]; then
                log_info "Cancelling build: ${build_id}"
                if gcloud builds cancel "${build_id}" --quiet; then
                    log_success "Cancelled build: ${build_id}"
                else
                    log_warning "Failed to cancel build: ${build_id}"
                fi
            fi
        done <<< "${ongoing_builds}"
    else
        log_info "No ongoing builds found"
    fi
    
    log_success "Cloud Build cleanup completed"
}

# Function to verify cleanup completion
verify_cleanup() {
    log_info "Verifying cleanup completion..."
    
    local cleanup_issues=0
    
    # Check for remaining GKE clusters
    local remaining_clusters=$(gcloud container clusters list \
        --format="value(name)" \
        --filter="name~enterprise-gke-.*" 2>/dev/null || true)
    if [[ -n "${remaining_clusters}" ]]; then
        log_warning "Remaining GKE clusters found: ${remaining_clusters}"
        cleanup_issues=$((cleanup_issues + 1))
    fi
    
    # Check for remaining Cloud Deploy pipelines
    if gcloud deploy delivery-pipelines describe enterprise-pipeline \
        --region="${REGION}" &>/dev/null; then
        log_warning "Cloud Deploy pipeline still exists"
        cleanup_issues=$((cleanup_issues + 1))
    fi
    
    # Check for remaining Artifact Registry repositories
    if gcloud artifacts repositories describe "${REPO_NAME}" \
        --location="${REGION}" &>/dev/null; then
        log_warning "Artifact Registry repository still exists"
        cleanup_issues=$((cleanup_issues + 1))
    fi
    
    # Check for remaining source repositories
    local repos=("pipeline-templates" "sample-app")
    for repo in "${repos[@]}"; do
        if gcloud source repos describe "${repo}" &>/dev/null; then
            log_warning "Source repository still exists: ${repo}"
            cleanup_issues=$((cleanup_issues + 1))
        fi
    done
    
    # Check for remaining service account
    if gcloud iam service-accounts describe "cloudbuild-deploy@${PROJECT_ID}.iam.gserviceaccount.com" &>/dev/null; then
        log_warning "Service account still exists"
        cleanup_issues=$((cleanup_issues + 1))
    fi
    
    if [[ ${cleanup_issues} -eq 0 ]]; then
        log_success "Cleanup verification passed - all resources removed"
    else
        log_warning "Cleanup verification found ${cleanup_issues} issues"
        log_info "Some resources may require manual deletion or may take time to fully remove"
    fi
}

# Function to display final cleanup summary
display_cleanup_summary() {
    log_success "Enterprise deployment pipeline cleanup completed!"
    echo
    log_info "Cleanup Summary:"
    echo "  ✓ GKE clusters removed"
    echo "  ✓ Cloud Deploy pipeline removed"
    echo "  ✓ Artifact Registry repository removed"
    echo "  ✓ Cloud Build triggers removed"
    echo "  ✓ Cloud Source repositories removed"
    echo "  ✓ IAM service accounts and bindings removed"
    echo "  ✓ Local directories cleaned up"
    echo
    log_info "Useful Commands for Manual Verification:"
    echo "  # Check for remaining clusters:"
    echo "  gcloud container clusters list"
    echo
    echo "  # Check for remaining repositories:"
    echo "  gcloud artifacts repositories list"
    echo "  gcloud source repos list"
    echo
    echo "  # Check for remaining build triggers:"
    echo "  gcloud builds triggers list"
    echo
    echo "  # Check for remaining Cloud Deploy resources:"
    echo "  gcloud deploy delivery-pipelines list --region=${REGION}"
    echo
    log_info "If you encounter any issues, you may need to manually delete remaining resources"
    log_success "Thank you for using the enterprise deployment pipeline!"
}

# Main cleanup function
main() {
    log_info "Starting enterprise deployment pipeline cleanup..."
    
    check_prerequisites
    setup_environment
    confirm_destruction
    
    # Cleanup in reverse order of creation to handle dependencies
    cleanup_remaining_builds
    cleanup_build_triggers
    cleanup_cloud_deploy
    cleanup_gke_clusters
    cleanup_artifact_registry
    cleanup_source_repositories
    cleanup_iam_resources
    cleanup_local_directories
    
    verify_cleanup
    display_cleanup_summary
    
    log_success "Cleanup completed successfully!"
}

# Handle script interruption
cleanup_on_exit() {
    log_warning "Script interrupted. Cleanup may be incomplete."
    log_info "You may need to manually delete remaining resources."
    exit 1
}

# Set up signal handlers
trap cleanup_on_exit INT TERM

# Show help if requested
if [[ "${1:-}" == "--help" ]] || [[ "${1:-}" == "-h" ]]; then
    echo "Enterprise Deployment Pipeline Cleanup Script"
    echo
    echo "Usage: $0 [options]"
    echo
    echo "Options:"
    echo "  --help, -h     Show this help message"
    echo
    echo "Environment Variables:"
    echo "  PROJECT_ID     Google Cloud project ID (optional, uses current project)"
    echo "  REGION         Google Cloud region (default: us-central1)"
    echo "  REPO_NAME      Artifact Registry repository name (default: enterprise-apps)"
    echo "  FORCE_DELETE   Skip confirmation prompt (default: false)"
    echo
    echo "Examples:"
    echo "  # Interactive cleanup:"
    echo "  ./destroy.sh"
    echo
    echo "  # Force cleanup without confirmation:"
    echo "  FORCE_DELETE=true ./destroy.sh"
    echo
    echo "  # Cleanup specific project:"
    echo "  PROJECT_ID=my-project ./destroy.sh"
    exit 0
fi

# Run main function
main "$@"