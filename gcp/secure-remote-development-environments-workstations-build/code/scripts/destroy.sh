#!/bin/bash

# Destroy script for Secure Remote Development Environments with Cloud Workstations and Cloud Build
# This script safely removes all resources created by the deployment script

set -euo pipefail

# Color codes for output formatting
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

# Error handling function
handle_error() {
    log_error "Script failed at line $1. Exit code: $2"
    log_error "Check the logs above for detailed error information."
    exit $2
}

# Set trap for error handling
trap 'handle_error $LINENO $?' ERR

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/destroy.log"

# Redirect all output to both console and log file
exec > >(tee -a "${LOG_FILE}")
exec 2>&1

log "Starting cleanup of Secure Remote Development Environment"
log "Log file: ${LOG_FILE}"

# Load environment variables from deployment
load_environment() {
    log "Loading environment variables from deployment..."
    
    local env_file="${SCRIPT_DIR}/.env"
    
    if [[ ! -f "${env_file}" ]]; then
        log_error "Environment file not found: ${env_file}"
        log_error "Please run this script from the same directory as the deployment"
        exit 1
    fi
    
    # Source environment variables
    source "${env_file}"
    
    # Validate required variables
    local required_vars=(
        "PROJECT_ID"
        "REGION"
        "WORKSTATION_CLUSTER"
        "WORKSTATION_CONFIG"
        "BUILD_POOL"
        "REPO_NAME"
        "RANDOM_SUFFIX"
    )
    
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            log_error "Required environment variable ${var} is not set"
            exit 1
        fi
    done
    
    log_success "Environment variables loaded successfully"
    log "Project: ${PROJECT_ID}"
    log "Region: ${REGION}"
    log "Resource suffix: ${RANDOM_SUFFIX}"
}

# Confirmation prompt for destructive actions
confirm_destruction() {
    log_warning "This script will permanently delete the following resources:"
    log "   • Project: ${PROJECT_ID}"
    log "   • Workstation Cluster: ${WORKSTATION_CLUSTER}"
    log "   • Source Repository: ${REPO_NAME}"
    log "   • Artifact Registry: ${REPO_NAME}-images"
    log "   • Build Pool: ${BUILD_POOL}"
    log "   • VPC Network: dev-vpc"
    log "   • Service Account: workstation-dev-sa"
    log ""
    
    if [[ "${FORCE_DELETE:-false}" != "true" ]]; then
        read -p "Are you sure you want to proceed? (yes/no): " confirmation
        if [[ "${confirmation}" != "yes" ]]; then
            log "Cleanup cancelled by user"
            exit 0
        fi
    fi
    
    log "Proceeding with resource cleanup..."
}

# Delete workstation instances and configurations
cleanup_workstations() {
    log "Cleaning up workstation instances and configurations..."
    
    # List and delete all workstation instances
    local workstation_instances
    workstation_instances=$(gcloud workstations list \
        --cluster="${WORKSTATION_CLUSTER}" \
        --region="${REGION}" \
        --format="value(name)" 2>/dev/null || echo "")
    
    if [[ -n "${workstation_instances}" ]]; then
        while IFS= read -r instance; do
            if [[ -n "${instance}" ]]; then
                log "Deleting workstation instance: ${instance}"
                gcloud workstations delete "${instance}" \
                    --cluster="${WORKSTATION_CLUSTER}" \
                    --config="${WORKSTATION_CONFIG}" \
                    --region="${REGION}" \
                    --quiet || log_warning "Failed to delete workstation: ${instance}"
            fi
        done <<< "${workstation_instances}"
        log_success "Workstation instances deleted"
    else
        log "No workstation instances found to delete"
    fi
    
    # Delete workstation configuration
    if gcloud workstations configs describe "${WORKSTATION_CONFIG}" \
        --cluster="${WORKSTATION_CLUSTER}" \
        --region="${REGION}" &>/dev/null; then
        log "Deleting workstation configuration: ${WORKSTATION_CONFIG}"
        gcloud workstations configs delete "${WORKSTATION_CONFIG}" \
            --cluster="${WORKSTATION_CLUSTER}" \
            --region="${REGION}" \
            --quiet || log_warning "Failed to delete workstation configuration"
        log_success "Workstation configuration deleted"
    else
        log "Workstation configuration not found"
    fi
}

# Delete Cloud Build resources
cleanup_cloud_build() {
    log "Cleaning up Cloud Build resources..."
    
    local trigger_name="secure-dev-trigger-${RANDOM_SUFFIX}"
    
    # Delete build trigger
    if gcloud builds triggers describe "${trigger_name}" --region="${REGION}" &>/dev/null; then
        log "Deleting Cloud Build trigger: ${trigger_name}"
        gcloud builds triggers delete "${trigger_name}" \
            --region="${REGION}" \
            --quiet || log_warning "Failed to delete build trigger"
        log_success "Cloud Build trigger deleted"
    else
        log "Cloud Build trigger not found"
    fi
    
    # Delete private build pool
    if gcloud builds worker-pools describe "${BUILD_POOL}" --region="${REGION}" &>/dev/null; then
        log "Deleting private Cloud Build pool: ${BUILD_POOL}"
        gcloud builds worker-pools delete "${BUILD_POOL}" \
            --region="${REGION}" \
            --quiet || log_warning "Failed to delete build pool"
        
        # Wait for deletion to complete
        local max_attempts=30
        local attempt=0
        
        while [[ ${attempt} -lt ${max_attempts} ]]; do
            if ! gcloud builds worker-pools describe "${BUILD_POOL}" --region="${REGION}" &>/dev/null; then
                log_success "Private Cloud Build pool deleted"
                break
            fi
            log "Waiting for build pool deletion... (attempt ${attempt}/${max_attempts})"
            sleep 10
            ((attempt++))
        done
        
        if [[ ${attempt} -eq ${max_attempts} ]]; then
            log_warning "Timeout waiting for build pool deletion"
        fi
    else
        log "Private Cloud Build pool not found"
    fi
}

# Delete workstation cluster
cleanup_workstation_cluster() {
    log "Cleaning up workstation cluster..."
    
    if gcloud workstations clusters describe "${WORKSTATION_CLUSTER}" --region="${REGION}" &>/dev/null; then
        log "Deleting workstation cluster: ${WORKSTATION_CLUSTER}"
        gcloud workstations clusters delete "${WORKSTATION_CLUSTER}" \
            --region="${REGION}" \
            --quiet || log_warning "Failed to delete workstation cluster"
        
        # Wait for deletion to complete
        local max_attempts=60
        local attempt=0
        
        while [[ ${attempt} -lt ${max_attempts} ]]; do
            if ! gcloud workstations clusters describe "${WORKSTATION_CLUSTER}" --region="${REGION}" &>/dev/null; then
                log_success "Workstation cluster deleted"
                break
            fi
            log "Waiting for cluster deletion... (attempt ${attempt}/${max_attempts})"
            sleep 30
            ((attempt++))
        done
        
        if [[ ${attempt} -eq ${max_attempts} ]]; then
            log_warning "Timeout waiting for cluster deletion"
        fi
    else
        log "Workstation cluster not found"
    fi
}

# Delete VPC network and subnets
cleanup_vpc_network() {
    log "Cleaning up VPC network and subnets..."
    
    # Delete subnet first
    if gcloud compute networks subnets describe dev-subnet --region="${REGION}" &>/dev/null; then
        log "Deleting subnet: dev-subnet"
        gcloud compute networks subnets delete dev-subnet \
            --region="${REGION}" \
            --quiet || log_warning "Failed to delete subnet"
        log_success "Subnet deleted"
    else
        log "Subnet dev-subnet not found"
    fi
    
    # Delete VPC network
    if gcloud compute networks describe dev-vpc &>/dev/null; then
        log "Deleting VPC network: dev-vpc"
        gcloud compute networks delete dev-vpc \
            --quiet || log_warning "Failed to delete VPC network"
        log_success "VPC network deleted"
    else
        log "VPC network dev-vpc not found"
    fi
}

# Delete source repository
cleanup_source_repository() {
    log "Cleaning up Cloud Source Repository..."
    
    if gcloud source repos describe "${REPO_NAME}" &>/dev/null; then
        log "Deleting source repository: ${REPO_NAME}"
        gcloud source repos delete "${REPO_NAME}" \
            --quiet || log_warning "Failed to delete source repository"
        log_success "Source repository deleted"
    else
        log "Source repository not found"
    fi
}

# Delete Artifact Registry
cleanup_artifact_registry() {
    log "Cleaning up Artifact Registry..."
    
    if gcloud artifacts repositories describe "${REPO_NAME}-images" --location="${REGION}" &>/dev/null; then
        log "Deleting Artifact Registry: ${REPO_NAME}-images"
        gcloud artifacts repositories delete "${REPO_NAME}-images" \
            --location="${REGION}" \
            --quiet || log_warning "Failed to delete Artifact Registry"
        log_success "Artifact Registry deleted"
    else
        log "Artifact Registry not found"
    fi
}

# Delete IAM service account and remove bindings
cleanup_iam() {
    log "Cleaning up IAM resources..."
    
    local service_account="workstation-dev-sa@${PROJECT_ID}.iam.gserviceaccount.com"
    
    # Remove IAM policy bindings
    local roles=(
        "roles/source.developer"
        "roles/artifactregistry.reader"
        "roles/cloudbuild.builds.viewer"
    )
    
    for role in "${roles[@]}"; do
        if gcloud projects get-iam-policy "${PROJECT_ID}" \
            --flatten="bindings[].members" \
            --format="table(bindings.role)" \
            --filter="bindings.members:serviceAccount:${service_account} AND bindings.role:${role}" \
            | grep -q "${role}" 2>/dev/null; then
            
            log "Removing IAM binding for role: ${role}"
            gcloud projects remove-iam-policy-binding "${PROJECT_ID}" \
                --member "serviceAccount:${service_account}" \
                --role "${role}" \
                --quiet || log_warning "Failed to remove IAM binding for ${role}"
        fi
    done
    
    # Delete service account
    if gcloud iam service-accounts describe "${service_account}" &>/dev/null; then
        log "Deleting service account: workstation-dev-sa"
        gcloud iam service-accounts delete "${service_account}" \
            --quiet || log_warning "Failed to delete service account"
        log_success "Service account deleted"
    else
        log "Service account not found"
    fi
    
    log_success "IAM resources cleaned up"
}

# Clean up temporary files
cleanup_temp_files() {
    log "Cleaning up temporary files..."
    
    local temp_files=(
        "${SCRIPT_DIR}/private-pool.yaml"
        "${SCRIPT_DIR}/.env"
    )
    
    for file in "${temp_files[@]}"; do
        if [[ -f "${file}" ]]; then
            rm -f "${file}"
            log "Removed temporary file: $(basename "${file}")"
        fi
    done
    
    log_success "Temporary files cleaned up"
}

# Verification function to check if resources are truly deleted
verify_cleanup() {
    log "Verifying resource cleanup..."
    
    local cleanup_issues=0
    
    # Check workstation cluster
    if gcloud workstations clusters describe "${WORKSTATION_CLUSTER}" --region="${REGION}" &>/dev/null; then
        log_warning "Workstation cluster still exists: ${WORKSTATION_CLUSTER}"
        ((cleanup_issues++))
    fi
    
    # Check source repository
    if gcloud source repos describe "${REPO_NAME}" &>/dev/null; then
        log_warning "Source repository still exists: ${REPO_NAME}"
        ((cleanup_issues++))
    fi
    
    # Check Artifact Registry
    if gcloud artifacts repositories describe "${REPO_NAME}-images" --location="${REGION}" &>/dev/null; then
        log_warning "Artifact Registry still exists: ${REPO_NAME}-images"
        ((cleanup_issues++))
    fi
    
    # Check build pool
    if gcloud builds worker-pools describe "${BUILD_POOL}" --region="${REGION}" &>/dev/null; then
        log_warning "Build pool still exists: ${BUILD_POOL}"
        ((cleanup_issues++))
    fi
    
    # Check VPC network
    if gcloud compute networks describe dev-vpc &>/dev/null; then
        log_warning "VPC network still exists: dev-vpc"
        ((cleanup_issues++))
    fi
    
    # Check service account
    local service_account="workstation-dev-sa@${PROJECT_ID}.iam.gserviceaccount.com"
    if gcloud iam service-accounts describe "${service_account}" &>/dev/null; then
        log_warning "Service account still exists: workstation-dev-sa"
        ((cleanup_issues++))
    fi
    
    if [[ ${cleanup_issues} -eq 0 ]]; then
        log_success "All resources successfully cleaned up"
    else
        log_warning "Found ${cleanup_issues} resources that may still exist"
        log_warning "Manual cleanup may be required for these resources"
    fi
}

# Main cleanup function
main() {
    log "=== Secure Remote Development Environment Cleanup ==="
    
    load_environment
    confirm_destruction
    
    log "Starting resource cleanup in reverse order of creation..."
    
    # Clean up resources in reverse order of creation
    cleanup_workstations
    cleanup_cloud_build
    cleanup_workstation_cluster
    cleanup_vpc_network
    cleanup_source_repository
    cleanup_artifact_registry
    cleanup_iam
    cleanup_temp_files
    
    # Verify cleanup
    verify_cleanup
    
    log_success "=== Cleanup completed! ==="
    log ""
    log "🧹 Resource cleanup summary:"
    log "   • Workstation instances and configurations removed"
    log "   • Cloud Build triggers and pools deleted"
    log "   • Workstation cluster destroyed"
    log "   • VPC network and subnets removed"
    log "   • Source repository deleted"
    log "   • Artifact Registry removed"
    log "   • IAM service account and bindings cleaned up"
    log "   • Temporary files removed"
    log ""
    log "📝 Detailed logs available at: ${LOG_FILE}"
    log ""
    log "⚠️  Note: Some Google Cloud APIs remain enabled but can be disabled manually if no longer needed"
    log "💰 All billable resources have been removed to prevent ongoing charges"
}

# Handle script arguments
if [[ "${1:-}" == "--force" ]]; then
    export FORCE_DELETE="true"
    log "Running in force mode - skipping confirmation prompts"
fi

# Run main function
main "$@"