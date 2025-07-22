#!/bin/bash

# Enterprise Identity Federation Workflows with Cloud IAM and Service Directory
# Cleanup/Destroy Script for GCP
# 
# This script safely removes all resources created by the deploy.sh script
# for the enterprise identity federation system.

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

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to show usage
show_usage() {
    echo "Usage: $0 [RANDOM_SUFFIX]"
    echo ""
    echo "This script destroys the Enterprise Identity Federation infrastructure."
    echo ""
    echo "Arguments:"
    echo "  RANDOM_SUFFIX    The random suffix used during deployment (optional)"
    echo ""
    echo "If no suffix is provided, the script will attempt to discover resources"
    echo "or prompt for the suffix interactively."
    echo ""
    echo "Examples:"
    echo "  $0 abc123"
    echo "  $0"
    exit 1
}

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if gcloud CLI is installed
    if ! command_exists gcloud; then
        log_error "Google Cloud CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if user is authenticated
    if ! gcloud auth list --filter="status:ACTIVE" --format="value(account)" | head -1 >/dev/null 2>&1; then
        log_error "Not authenticated with Google Cloud. Please run 'gcloud auth login'"
        exit 1
    fi
    
    log_success "Prerequisites check completed"
}

# Function to setup environment variables
setup_environment() {
    log_info "Setting up environment variables..."
    
    # Get current project ID
    export PROJECT_ID=$(gcloud config get-value project 2>/dev/null)
    if [[ -z "${PROJECT_ID}" ]]; then
        read -p "Enter your Google Cloud Project ID: " PROJECT_ID
        gcloud config set project "${PROJECT_ID}"
    fi
    
    # Set default region
    export REGION=$(gcloud config get-value compute/region 2>/dev/null || echo "us-central1")
    
    log_info "Project: ${PROJECT_ID}"
    log_info "Region: ${REGION}"
}

# Function to discover resources if suffix is not provided
discover_resources() {
    local suffix="$1"
    
    if [[ -z "${suffix}" ]]; then
        log_info "Attempting to discover resources..."
        
        # Try to find workload identity pools with our naming pattern
        local pools=$(gcloud iam workload-identity-pools list \
            --location="global" \
            --filter="displayName:('Enterprise Pool')" \
            --format="value(name)" 2>/dev/null || true)
        
        if [[ -n "${pools}" ]]; then
            # Extract suffix from first pool found
            local pool_name=$(echo "${pools}" | head -1 | sed 's/.*enterprise-pool-//')
            suffix="${pool_name}"
            log_info "Discovered resources with suffix: ${suffix}"
        fi
        
        # If still no suffix, try to find from deployment info files
        if [[ -z "${suffix}" ]]; then
            local info_files=$(ls deployment-info-*.txt 2>/dev/null || true)
            if [[ -n "${info_files}" ]]; then
                local latest_file=$(ls -t deployment-info-*.txt | head -1)
                suffix=$(echo "${latest_file}" | sed 's/deployment-info-//' | sed 's/.txt//')
                log_info "Found deployment info file: ${latest_file}"
                log_info "Using suffix: ${suffix}"
            fi
        fi
        
        # If still no suffix, prompt user
        if [[ -z "${suffix}" ]]; then
            log_warning "Could not automatically discover resources"
            read -p "Enter the random suffix used during deployment: " suffix
        fi
    fi
    
    if [[ -z "${suffix}" ]]; then
        log_error "No suffix provided and could not discover resources"
        exit 1
    fi
    
    export RANDOM_SUFFIX="${suffix}"
    
    # Set resource names using the suffix
    export WI_POOL_ID="enterprise-pool-${RANDOM_SUFFIX}"
    export WI_PROVIDER_ID="oidc-provider-${RANDOM_SUFFIX}"
    export SERVICE_ACCOUNT_NAME="federation-sa-${RANDOM_SUFFIX}"
    export NAMESPACE_NAME="enterprise-services-${RANDOM_SUFFIX}"
    export FUNCTION_NAME="identity-provisioner-${RANDOM_SUFFIX}"
    export SA_EMAIL="${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
    
    log_info "Using random suffix: ${RANDOM_SUFFIX}"
}

# Function to confirm destruction
confirm_destruction() {
    log_warning "========================================="
    log_warning "DESTRUCTIVE ACTION CONFIRMATION"
    log_warning "========================================="
    log_warning "This will permanently delete the following resources:"
    log_warning "- Workload Identity Pool: ${WI_POOL_ID}"
    log_warning "- OIDC Provider: ${WI_PROVIDER_ID}"
    log_warning "- Service Accounts: ${SERVICE_ACCOUNT_NAME}, read-only-sa-${RANDOM_SUFFIX}, admin-sa-${RANDOM_SUFFIX}"
    log_warning "- Service Directory Namespace: ${NAMESPACE_NAME}"
    log_warning "- Cloud Function: ${FUNCTION_NAME}"
    log_warning "- DNS Zone: enterprise-services-${RANDOM_SUFFIX}"
    log_warning "- Secrets: federation-config-${RANDOM_SUFFIX}, idp-config-${RANDOM_SUFFIX}"
    log_warning "========================================="
    
    read -p "Are you sure you want to proceed? (yes/no): " confirmation
    
    if [[ "${confirmation}" != "yes" ]]; then
        log_info "Destruction cancelled by user"
        exit 0
    fi
    
    log_info "Proceeding with resource destruction..."
}

# Function to delete Cloud Function
delete_cloud_function() {
    log_info "Deleting Cloud Function..."
    
    if gcloud functions describe "${FUNCTION_NAME}" >/dev/null 2>&1; then
        if gcloud functions delete "${FUNCTION_NAME}" --quiet; then
            log_success "Cloud Function deleted: ${FUNCTION_NAME}"
        else
            log_error "Failed to delete Cloud Function: ${FUNCTION_NAME}"
        fi
    else
        log_warning "Cloud Function not found: ${FUNCTION_NAME}"
    fi
    
    # Clean up any leftover source directories
    if [[ -d "./identity-provisioner-${RANDOM_SUFFIX}" ]]; then
        rm -rf "./identity-provisioner-${RANDOM_SUFFIX}"
        log_success "Cleaned up function source directory"
    fi
}

# Function to delete Service Directory resources
delete_service_directory() {
    log_info "Deleting Service Directory resources..."
    
    # Delete services first
    local services=("user-management" "identity-provider" "resource-manager")
    
    for service in "${services[@]}"; do
        if gcloud service-directory services describe "${service}" \
            --namespace="${NAMESPACE_NAME}" \
            --location="${REGION}" >/dev/null 2>&1; then
            
            if gcloud service-directory services delete "${service}" \
                --namespace="${NAMESPACE_NAME}" \
                --location="${REGION}" \
                --quiet; then
                log_success "Deleted service: ${service}"
            else
                log_warning "Failed to delete service: ${service}"
            fi
        else
            log_warning "Service not found: ${service}"
        fi
    done
    
    # Delete namespace
    if gcloud service-directory namespaces describe "${NAMESPACE_NAME}" \
        --location="${REGION}" >/dev/null 2>&1; then
        
        if gcloud service-directory namespaces delete "${NAMESPACE_NAME}" \
            --location="${REGION}" \
            --quiet; then
            log_success "Service Directory namespace deleted: ${NAMESPACE_NAME}"
        else
            log_error "Failed to delete Service Directory namespace: ${NAMESPACE_NAME}"
        fi
    else
        log_warning "Service Directory namespace not found: ${NAMESPACE_NAME}"
    fi
}

# Function to delete DNS resources
delete_dns_resources() {
    log_info "Deleting DNS resources..."
    
    local dns_zone="enterprise-services-${RANDOM_SUFFIX}"
    
    # Check if DNS zone exists
    if gcloud dns managed-zones describe "${dns_zone}" >/dev/null 2>&1; then
        
        # Delete any custom DNS records first (excluding default NS and SOA records)
        local records=$(gcloud dns record-sets list \
            --zone="${dns_zone}" \
            --filter="type != NS AND type != SOA" \
            --format="value(name,type)" 2>/dev/null || true)
        
        if [[ -n "${records}" ]]; then
            log_info "Deleting custom DNS records..."
            
            # Start a transaction to delete records
            if gcloud dns record-sets transaction start --zone="${dns_zone}" --quiet; then
                
                # Process each record
                while IFS=$'\t' read -r name type; do
                    if [[ -n "${name}" && -n "${type}" ]]; then
                        local ttl=$(gcloud dns record-sets list \
                            --zone="${dns_zone}" \
                            --filter="name:'${name}' AND type:'${type}'" \
                            --format="value(ttl)" | head -1)
                        
                        local rrdatas=$(gcloud dns record-sets list \
                            --zone="${dns_zone}" \
                            --filter="name:'${name}' AND type:'${type}'" \
                            --format="value(rrdatas[].join(' '))" | head -1)
                        
                        if [[ -n "${ttl}" && -n "${rrdatas}" ]]; then
                            gcloud dns record-sets transaction remove "${rrdatas}" \
                                --zone="${dns_zone}" \
                                --name="${name}" \
                                --type="${type}" \
                                --ttl="${ttl}" || true
                        fi
                    fi
                done <<< "${records}"
                
                # Execute the transaction
                if gcloud dns record-sets transaction execute --zone="${dns_zone}" --quiet; then
                    log_success "Deleted custom DNS records"
                else
                    log_warning "Failed to delete some DNS records, continuing..."
                    # Abort the transaction if it failed
                    gcloud dns record-sets transaction abort --zone="${dns_zone}" --quiet || true
                fi
            fi
        fi
        
        # Delete the DNS zone
        if gcloud dns managed-zones delete "${dns_zone}" --quiet; then
            log_success "DNS zone deleted: ${dns_zone}"
        else
            log_error "Failed to delete DNS zone: ${dns_zone}"
        fi
    else
        log_warning "DNS zone not found: ${dns_zone}"
    fi
}

# Function to delete secrets
delete_secrets() {
    log_info "Deleting secrets..."
    
    local secrets=("federation-config-${RANDOM_SUFFIX}" "idp-config-${RANDOM_SUFFIX}")
    
    for secret in "${secrets[@]}"; do
        if gcloud secrets describe "${secret}" >/dev/null 2>&1; then
            if gcloud secrets delete "${secret}" --quiet; then
                log_success "Deleted secret: ${secret}"
            else
                log_error "Failed to delete secret: ${secret}"
            fi
        else
            log_warning "Secret not found: ${secret}"
        fi
    done
}

# Function to remove IAM bindings and delete service accounts
delete_iam_resources() {
    log_info "Removing IAM bindings and deleting service accounts..."
    
    # Remove IAM bindings from project
    local roles=("roles/servicedirectory.editor" "roles/secretmanager.secretAccessor")
    
    for role in "${roles[@]}"; do
        if gcloud projects remove-iam-policy-binding "${PROJECT_ID}" \
            --member="serviceAccount:${SA_EMAIL}" \
            --role="${role}" \
            --quiet 2>/dev/null; then
            log_success "Removed IAM binding: ${role}"
        else
            log_warning "Failed to remove IAM binding: ${role} (may not exist)"
        fi
    done
    
    # Delete service accounts
    local service_accounts=("${SERVICE_ACCOUNT_NAME}" "read-only-sa-${RANDOM_SUFFIX}" "admin-sa-${RANDOM_SUFFIX}")
    
    for account in "${service_accounts[@]}"; do
        local account_email="${account}@${PROJECT_ID}.iam.gserviceaccount.com"
        
        if gcloud iam service-accounts describe "${account_email}" >/dev/null 2>&1; then
            if gcloud iam service-accounts delete "${account_email}" --quiet; then
                log_success "Deleted service account: ${account_email}"
            else
                log_error "Failed to delete service account: ${account_email}"
            fi
        else
            log_warning "Service account not found: ${account_email}"
        fi
    done
}

# Function to delete Workload Identity Federation resources
delete_workload_identity() {
    log_info "Deleting Workload Identity Federation resources..."
    
    # Delete workload identity provider
    if gcloud iam workload-identity-pools providers describe "${WI_PROVIDER_ID}" \
        --workload-identity-pool="${WI_POOL_ID}" \
        --location="global" >/dev/null 2>&1; then
        
        if gcloud iam workload-identity-pools providers delete "${WI_PROVIDER_ID}" \
            --workload-identity-pool="${WI_POOL_ID}" \
            --location="global" \
            --quiet; then
            log_success "Deleted workload identity provider: ${WI_PROVIDER_ID}"
        else
            log_error "Failed to delete workload identity provider: ${WI_PROVIDER_ID}"
        fi
    else
        log_warning "Workload identity provider not found: ${WI_PROVIDER_ID}"
    fi
    
    # Wait a moment for provider deletion to complete
    sleep 5
    
    # Delete workload identity pool
    if gcloud iam workload-identity-pools describe "${WI_POOL_ID}" \
        --location="global" >/dev/null 2>&1; then
        
        if gcloud iam workload-identity-pools delete "${WI_POOL_ID}" \
            --location="global" \
            --quiet; then
            log_success "Deleted workload identity pool: ${WI_POOL_ID}"
        else
            log_error "Failed to delete workload identity pool: ${WI_POOL_ID}"
        fi
    else
        log_warning "Workload identity pool not found: ${WI_POOL_ID}"
    fi
}

# Function to clean up deployment info files
cleanup_deployment_files() {
    log_info "Cleaning up deployment information files..."
    
    local info_file="deployment-info-${RANDOM_SUFFIX}.txt"
    
    if [[ -f "${info_file}" ]]; then
        rm -f "${info_file}"
        log_success "Removed deployment info file: ${info_file}"
    else
        log_warning "Deployment info file not found: ${info_file}"
    fi
}

# Function to verify cleanup
verify_cleanup() {
    log_info "Verifying resource cleanup..."
    
    local cleanup_issues=()
    
    # Check workload identity pool
    if gcloud iam workload-identity-pools describe "${WI_POOL_ID}" \
        --location="global" >/dev/null 2>&1; then
        cleanup_issues+=("Workload Identity Pool: ${WI_POOL_ID}")
    fi
    
    # Check service directory namespace
    if gcloud service-directory namespaces describe "${NAMESPACE_NAME}" \
        --location="${REGION}" >/dev/null 2>&1; then
        cleanup_issues+=("Service Directory Namespace: ${NAMESPACE_NAME}")
    fi
    
    # Check Cloud Function
    if gcloud functions describe "${FUNCTION_NAME}" >/dev/null 2>&1; then
        cleanup_issues+=("Cloud Function: ${FUNCTION_NAME}")
    fi
    
    # Check DNS zone
    if gcloud dns managed-zones describe "enterprise-services-${RANDOM_SUFFIX}" >/dev/null 2>&1; then
        cleanup_issues+=("DNS Zone: enterprise-services-${RANDOM_SUFFIX}")
    fi
    
    # Check secrets
    if gcloud secrets describe "federation-config-${RANDOM_SUFFIX}" >/dev/null 2>&1; then
        cleanup_issues+=("Secret: federation-config-${RANDOM_SUFFIX}")
    fi
    
    if [[ ${#cleanup_issues[@]} -eq 0 ]]; then
        log_success "All resources have been successfully cleaned up"
    else
        log_warning "Some resources may still exist:"
        for issue in "${cleanup_issues[@]}"; do
            log_warning "  - ${issue}"
        done
        log_warning "You may need to manually delete these resources"
    fi
}

# Function to display final summary
display_summary() {
    log_success "========================================="
    log_success "Enterprise Identity Federation cleanup completed!"
    log_success "========================================="
    log_info "Project: ${PROJECT_ID}"
    log_info "Suffix used: ${RANDOM_SUFFIX}"
    log_info "Resources that were targeted for deletion:"
    log_info "  - Workload Identity Pool: ${WI_POOL_ID}"
    log_info "  - OIDC Provider: ${WI_PROVIDER_ID}"
    log_info "  - Service Accounts: ${SERVICE_ACCOUNT_NAME}, read-only-sa-${RANDOM_SUFFIX}, admin-sa-${RANDOM_SUFFIX}"
    log_info "  - Service Directory Namespace: ${NAMESPACE_NAME}"
    log_info "  - Cloud Function: ${FUNCTION_NAME}"
    log_info "  - DNS Zone: enterprise-services-${RANDOM_SUFFIX}"
    log_info "  - Secrets: federation-config-${RANDOM_SUFFIX}, idp-config-${RANDOM_SUFFIX}"
    
    log_warning "Note: Some resources may take a few minutes to be fully deleted from Google Cloud"
}

# Main cleanup function
main() {
    local suffix="${1:-}"
    
    log_info "Starting Enterprise Identity Federation cleanup..."
    
    # Show help if requested
    if [[ "${suffix}" == "-h" || "${suffix}" == "--help" ]]; then
        show_usage
    fi
    
    check_prerequisites
    setup_environment
    discover_resources "${suffix}"
    confirm_destruction
    
    # Perform cleanup in reverse order of creation
    delete_cloud_function
    delete_dns_resources
    delete_service_directory
    delete_secrets
    delete_iam_resources
    delete_workload_identity
    cleanup_deployment_files
    
    verify_cleanup
    display_summary
}

# Trap to handle script interruption
trap 'log_error "Script interrupted. Some resources may still exist."; exit 1' INT TERM

# Run main function with all arguments
main "$@"