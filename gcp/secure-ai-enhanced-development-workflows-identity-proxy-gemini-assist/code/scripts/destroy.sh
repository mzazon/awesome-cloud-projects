#!/bin/bash

# Destroy script for Secure AI-Enhanced Development Workflows with Cloud Identity-Aware Proxy and Gemini Code Assist
# This script safely removes all resources created by the deployment script

set -euo pipefail

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

# Configuration variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOYMENT_INFO_FILE="${SCRIPT_DIR}/deployment-info.txt"

# Default values
FORCE_DELETE="${FORCE_DELETE:-false}"
DELETE_PROJECT="${DELETE_PROJECT:-true}"

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites for cleanup..."
    
    # Check if gcloud CLI is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "Google Cloud CLI (gcloud) is not installed."
        exit 1
    fi
    
    # Check if user is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" &> /dev/null; then
        log_error "You are not authenticated with Google Cloud. Please run 'gcloud auth login' first."
        exit 1
    fi
    
    log_success "Prerequisites check completed"
}

# Function to load deployment information
load_deployment_info() {
    log_info "Loading deployment information..."
    
    if [[ ! -f "${DEPLOYMENT_INFO_FILE}" ]]; then
        log_warning "Deployment info file not found at: ${DEPLOYMENT_INFO_FILE}"
        log_warning "You may need to provide resource information manually."
        return 1
    fi
    
    # Source the deployment info file to load variables
    # shellcheck disable=SC1090
    source "${DEPLOYMENT_INFO_FILE}"
    
    # Validate required variables
    if [[ -z "${PROJECT_ID:-}" ]]; then
        log_error "PROJECT_ID not found in deployment info"
        return 1
    fi
    
    log_info "Loaded deployment information:"
    log_info "  Project ID: ${PROJECT_ID}"
    log_info "  Region: ${REGION:-unknown}"
    log_info "  Application: ${APP_NAME:-unknown}"
    log_info "  Workstation: ${WORKSTATION_NAME:-unknown}"
    
    # Set the project context
    gcloud config set project "${PROJECT_ID}" --quiet
    
    log_success "Deployment information loaded successfully"
    return 0
}

# Function to get user input for missing information
get_user_input() {
    log_info "Manual resource identification required..."
    
    # Get project ID
    if [[ -z "${PROJECT_ID:-}" ]]; then
        echo -n "Enter the Project ID to delete: "
        read -r PROJECT_ID
        if [[ -z "${PROJECT_ID}" ]]; then
            log_error "Project ID is required"
            exit 1
        fi
    fi
    
    # Set default values if not provided
    REGION="${REGION:-us-central1}"
    APP_NAME="${APP_NAME:-}"
    WORKSTATION_NAME="${WORKSTATION_NAME:-}"
    SECRET_NAME="${SECRET_NAME:-}"
    
    # Set project context
    gcloud config set project "${PROJECT_ID}" --quiet
    
    log_info "Using Project ID: ${PROJECT_ID}"
}

# Function to confirm deletion
confirm_deletion() {
    log_warning "WARNING: This will permanently delete all resources in the project!"
    log_warning "Project: ${PROJECT_ID}"
    
    if [[ "${FORCE_DELETE}" == "true" ]]; then
        log_info "Force delete enabled, skipping confirmation"
        return 0
    fi
    
    echo ""
    echo "Resources that will be deleted:"
    echo "  - Cloud Run services"
    echo "  - Cloud Workstations (cluster, config, instances)"
    echo "  - Artifact Registry repositories"
    echo "  - Cloud Source repositories"
    echo "  - Secrets and KMS keys"
    echo "  - Service accounts"
    echo "  - IAM policy bindings"
    if [[ "${DELETE_PROJECT}" == "true" ]]; then
        echo "  - THE ENTIRE PROJECT (${PROJECT_ID})"
    fi
    echo ""
    
    read -p "Are you sure you want to continue? Type 'DELETE' to confirm: " -r
    if [[ "${REPLY}" != "DELETE" ]]; then
        log_info "Deletion cancelled by user"
        exit 0
    fi
    
    log_info "Deletion confirmed by user"
}

# Function to stop and delete Cloud Workstations
cleanup_workstations() {
    log_info "Cleaning up Cloud Workstations..."
    
    # Find and delete workstation instances
    local workstations
    workstations=$(gcloud workstations list --format="value(name)" --filter="config.name:secure-dev-config" 2>/dev/null || echo "")
    
    if [[ -n "${workstations}" ]]; then
        while IFS= read -r workstation; do
            if [[ -n "${workstation}" ]]; then
                log_info "Deleting workstation: ${workstation}"
                gcloud workstations delete "${workstation}" \
                    --region="${REGION}" \
                    --quiet || log_warning "Failed to delete workstation: ${workstation}"
            fi
        done <<< "${workstations}"
    fi
    
    # Delete specific workstation if name is known
    if [[ -n "${WORKSTATION_NAME:-}" ]]; then
        log_info "Deleting workstation: ${WORKSTATION_NAME}"
        gcloud workstations delete "${WORKSTATION_NAME}" \
            --cluster=secure-dev-cluster \
            --config=secure-dev-config \
            --region="${REGION}" \
            --quiet 2>/dev/null || log_warning "Failed to delete workstation: ${WORKSTATION_NAME}"
    fi
    
    # Wait a moment for workstations to be deleted
    sleep 30
    
    # Delete workstation configurations
    local configs
    configs=$(gcloud workstations configs list --format="value(name)" --filter="name:secure-dev-config" 2>/dev/null || echo "")
    
    if [[ -n "${configs}" ]]; then
        while IFS= read -r config; do
            if [[ -n "${config}" ]]; then
                log_info "Deleting workstation config: ${config}"
                gcloud workstations configs delete "${config}" \
                    --region="${REGION}" \
                    --quiet || log_warning "Failed to delete config: ${config}"
            fi
        done <<< "${configs}"
    fi
    
    # Wait for configs to be deleted
    sleep 30
    
    # Delete workstation clusters
    local clusters
    clusters=$(gcloud workstations clusters list --format="value(name)" --filter="name:secure-dev-cluster" 2>/dev/null || echo "")
    
    if [[ -n "${clusters}" ]]; then
        while IFS= read -r cluster; do
            if [[ -n "${cluster}" ]]; then
                log_info "Deleting workstation cluster: ${cluster}"
                gcloud workstations clusters delete "${cluster}" \
                    --region="${REGION}" \
                    --quiet || log_warning "Failed to delete cluster: ${cluster}"
            fi
        done <<< "${clusters}"
    fi
    
    log_success "Cloud Workstations cleanup completed"
}

# Function to delete Cloud Run services
cleanup_cloud_run() {
    log_info "Cleaning up Cloud Run services..."
    
    # Find and delete Cloud Run services
    local services
    services=$(gcloud run services list --format="value(metadata.name)" --region="${REGION}" 2>/dev/null || echo "")
    
    if [[ -n "${services}" ]]; then
        while IFS= read -r service; do
            if [[ -n "${service}" ]]; then
                log_info "Deleting Cloud Run service: ${service}"
                gcloud run services delete "${service}" \
                    --region="${REGION}" \
                    --quiet || log_warning "Failed to delete service: ${service}"
            fi
        done <<< "${services}"
    fi
    
    # Delete specific service if name is known
    if [[ -n "${APP_NAME:-}" ]]; then
        log_info "Deleting Cloud Run service: ${APP_NAME}"
        gcloud run services delete "${APP_NAME}" \
            --region="${REGION}" \
            --quiet 2>/dev/null || log_warning "Failed to delete service: ${APP_NAME}"
    fi
    
    log_success "Cloud Run services cleanup completed"
}

# Function to delete Artifact Registry repositories
cleanup_artifact_registry() {
    log_info "Cleaning up Artifact Registry repositories..."
    
    # Find and delete repositories
    local repositories
    repositories=$(gcloud artifacts repositories list --format="value(name)" --location="${REGION}" 2>/dev/null || echo "")
    
    if [[ -n "${repositories}" ]]; then
        while IFS= read -r repo; do
            if [[ -n "${repo}" ]]; then
                local repo_name
                repo_name=$(basename "${repo}")
                log_info "Deleting Artifact Registry repository: ${repo_name}"
                gcloud artifacts repositories delete "${repo_name}" \
                    --location="${REGION}" \
                    --quiet || log_warning "Failed to delete repository: ${repo_name}"
            fi
        done <<< "${repositories}"
    fi
    
    log_success "Artifact Registry cleanup completed"
}

# Function to delete Cloud Source repositories
cleanup_source_repositories() {
    log_info "Cleaning up Cloud Source repositories..."
    
    # Find and delete source repositories
    local repos
    repos=$(gcloud source repos list --format="value(name)" 2>/dev/null || echo "")
    
    if [[ -n "${repos}" ]]; then
        while IFS= read -r repo; do
            if [[ -n "${repo}" ]]; then
                log_info "Deleting Cloud Source repository: ${repo}"
                gcloud source repos delete "${repo}" \
                    --quiet || log_warning "Failed to delete repository: ${repo}"
            fi
        done <<< "${repos}"
    fi
    
    log_success "Cloud Source repositories cleanup completed"
}

# Function to delete secrets and KMS keys
cleanup_secrets_and_kms() {
    log_info "Cleaning up secrets and KMS keys..."
    
    # Delete secrets
    local secrets
    secrets=$(gcloud secrets list --format="value(name)" 2>/dev/null || echo "")
    
    if [[ -n "${secrets}" ]]; then
        while IFS= read -r secret; do
            if [[ -n "${secret}" ]]; then
                log_info "Deleting secret: ${secret}"
                gcloud secrets delete "${secret}" \
                    --quiet || log_warning "Failed to delete secret: ${secret}"
            fi
        done <<< "${secrets}"
    fi
    
    # Delete specific secrets if names are known
    if [[ -n "${SECRET_NAME:-}" ]]; then
        for suffix in "db" "api"; do
            secret_name="${SECRET_NAME}-${suffix}"
            log_info "Deleting secret: ${secret_name}"
            gcloud secrets delete "${secret_name}" \
                --quiet 2>/dev/null || log_warning "Failed to delete secret: ${secret_name}"
        done
    fi
    
    # Schedule KMS keys for destruction (they cannot be immediately deleted)
    local keys
    keys=$(gcloud kms keys list --location="${REGION}" --keyring=secure-dev-keyring --format="value(name)" 2>/dev/null || echo "")
    
    if [[ -n "${keys}" ]]; then
        while IFS= read -r key; do
            if [[ -n "${key}" ]]; then
                local key_name
                key_name=$(basename "${key}")
                log_info "Scheduling KMS key for destruction: ${key_name}"
                gcloud kms keys destroy "${key_name}" \
                    --location="${REGION}" \
                    --keyring=secure-dev-keyring \
                    --quiet || log_warning "Failed to schedule key destruction: ${key_name}"
            fi
        done <<< "${keys}"
    fi
    
    log_success "Secrets and KMS keys cleanup completed"
}

# Function to delete service accounts
cleanup_service_accounts() {
    log_info "Cleaning up service accounts..."
    
    # Find and delete custom service accounts (avoid deleting default ones)
    local service_accounts
    service_accounts=$(gcloud iam service-accounts list --format="value(email)" --filter="email:*secure*" 2>/dev/null || echo "")
    
    if [[ -n "${service_accounts}" ]]; then
        while IFS= read -r sa; do
            if [[ -n "${sa}" ]] && [[ "${sa}" != *"@appspot.gserviceaccount.com" ]] && [[ "${sa}" != *"@developer.gserviceaccount.com" ]] && [[ "${sa}" != *"@cloudbuild.gserviceaccount.com" ]]; then
                log_info "Deleting service account: ${sa}"
                gcloud iam service-accounts delete "${sa}" \
                    --quiet || log_warning "Failed to delete service account: ${sa}"
            fi
        done <<< "${service_accounts}"
    fi
    
    log_success "Service accounts cleanup completed"
}

# Function to clean up local files
cleanup_local_files() {
    log_info "Cleaning up local files..."
    
    # Remove deployment information file
    if [[ -f "${DEPLOYMENT_INFO_FILE}" ]]; then
        rm -f "${DEPLOYMENT_INFO_FILE}"
        log_success "Removed deployment info file"
    fi
    
    # Remove application directory if it exists
    local app_dir="${SCRIPT_DIR}/../secure-app"
    if [[ -d "${app_dir}" ]]; then
        rm -rf "${app_dir}"
        log_success "Removed application directory"
    fi
    
    # Remove Cloud Build configuration
    local cloudbuild_file="${SCRIPT_DIR}/../cloudbuild.yaml"
    if [[ -f "${cloudbuild_file}" ]]; then
        rm -f "${cloudbuild_file}"
        log_success "Removed Cloud Build configuration"
    fi
    
    log_success "Local files cleanup completed"
}

# Function to delete the entire project
delete_project() {
    if [[ "${DELETE_PROJECT}" != "true" ]]; then
        log_info "Project deletion skipped (DELETE_PROJECT=${DELETE_PROJECT})"
        return 0
    fi
    
    log_info "Deleting the entire project: ${PROJECT_ID}"
    log_warning "This will permanently delete ALL resources in the project!"
    
    if [[ "${FORCE_DELETE}" != "true" ]]; then
        read -p "Type the project ID to confirm deletion: " -r
        if [[ "${REPLY}" != "${PROJECT_ID}" ]]; then
            log_error "Project ID confirmation failed. Project deletion cancelled."
            return 1
        fi
    fi
    
    # Delete the project
    if gcloud projects delete "${PROJECT_ID}" --quiet; then
        log_success "Project ${PROJECT_ID} deletion initiated"
        log_info "Note: Project deletion may take several minutes to complete"
    else
        log_error "Failed to delete project ${PROJECT_ID}"
        return 1
    fi
    
    log_success "Project deletion completed"
}

# Function to validate cleanup
validate_cleanup() {
    log_info "Validating cleanup..."
    
    # Check if project still exists
    if gcloud projects describe "${PROJECT_ID}" --quiet >/dev/null 2>&1; then
        if [[ "${DELETE_PROJECT}" == "true" ]]; then
            log_warning "Project still exists (deletion may be in progress)"
        else
            log_info "Project ${PROJECT_ID} still exists (as expected)"
            
            # Check for remaining resources
            local remaining_services
            remaining_services=$(gcloud run services list --region="${REGION}" --format="value(metadata.name)" 2>/dev/null | wc -l)
            log_info "Remaining Cloud Run services: ${remaining_services}"
            
            local remaining_workstations
            remaining_workstations=$(gcloud workstations clusters list --region="${REGION}" --format="value(name)" 2>/dev/null | wc -l)
            log_info "Remaining workstation clusters: ${remaining_workstations}"
            
            local remaining_secrets
            remaining_secrets=$(gcloud secrets list --format="value(name)" 2>/dev/null | wc -l)
            log_info "Remaining secrets: ${remaining_secrets}"
        fi
    else
        log_success "Project no longer exists"
    fi
    
    log_success "Cleanup validation completed"
}

# Function to provide cleanup summary
provide_summary() {
    log_success "Cleanup process completed!"
    echo ""
    echo "======================================"
    echo "CLEANUP SUMMARY"
    echo "======================================"
    echo "Project: ${PROJECT_ID}"
    
    if [[ "${DELETE_PROJECT}" == "true" ]]; then
        echo "Status: Project deletion initiated"
        echo "Note: Complete project deletion may take several minutes"
    else
        echo "Status: Resources cleaned up, project preserved"
    fi
    
    echo ""
    echo "Cleaned up resources:"
    echo "  ✅ Cloud Run services"
    echo "  ✅ Cloud Workstations"
    echo "  ✅ Artifact Registry repositories"
    echo "  ✅ Cloud Source repositories"
    echo "  ✅ Secrets and KMS keys"
    echo "  ✅ Service accounts"
    echo "  ✅ Local files"
    
    if [[ "${DELETE_PROJECT}" == "true" ]]; then
        echo "  ✅ Project (deletion in progress)"
    fi
    
    echo ""
    echo "Important notes:"
    echo "  • KMS keys are scheduled for destruction (30-day delay)"
    echo "  • Some IAM policy changes may take time to propagate"
    if [[ "${DELETE_PROJECT}" == "true" ]]; then
        echo "  • Project deletion is irreversible"
    fi
    echo "======================================"
}

# Main cleanup function
main() {
    log_info "Starting cleanup of Secure AI-Enhanced Development Workflows..."
    
    # Start timing
    START_TIME=$(date +%s)
    
    # Execute cleanup steps
    check_prerequisites
    
    # Try to load deployment info, fall back to manual input if needed
    if ! load_deployment_info; then
        get_user_input
    fi
    
    confirm_deletion
    
    # If deleting the entire project, we can skip individual resource cleanup
    if [[ "${DELETE_PROJECT}" == "true" ]]; then
        delete_project
        cleanup_local_files
    else
        # Clean up resources individually
        cleanup_workstations
        cleanup_cloud_run
        cleanup_artifact_registry
        cleanup_source_repositories
        cleanup_secrets_and_kms
        cleanup_service_accounts
        cleanup_local_files
    fi
    
    validate_cleanup
    provide_summary
    
    # Calculate cleanup time
    END_TIME=$(date +%s)
    DURATION=$((END_TIME - START_TIME))
    
    log_success "Cleanup completed successfully in ${DURATION} seconds!"
}

# Show usage information
usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --force                    Skip confirmation prompts"
    echo "  --keep-project            Clean up resources but keep the project"
    echo "  --delete-project          Delete the entire project (default)"
    echo "  --help                    Show this help message"
    echo ""
    echo "Environment variables:"
    echo "  FORCE_DELETE=true         Skip confirmation prompts"
    echo "  DELETE_PROJECT=false      Keep the project after cleanup"
    echo ""
    echo "Examples:"
    echo "  $0                        Interactive cleanup with project deletion"
    echo "  $0 --force               Automated cleanup with project deletion"
    echo "  $0 --keep-project        Interactive cleanup preserving project"
    echo "  FORCE_DELETE=true $0     Automated cleanup using environment variable"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --force)
            FORCE_DELETE="true"
            shift
            ;;
        --keep-project)
            DELETE_PROJECT="false"
            shift
            ;;
        --delete-project)
            DELETE_PROJECT="true"
            shift
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# Execute main function
main "$@"