#!/bin/bash

# Database Development Workflows with AlloyDB Omni and Cloud Workstations - Cleanup Script
# This script safely removes all infrastructure created by the deployment script

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

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
DEPLOYMENT_INFO_FILE="${PROJECT_DIR}/deployment-info.txt"

# Default values
DEFAULT_PROJECT_ID=""
DEFAULT_REGION="us-central1"
DEFAULT_ZONE="us-central1-a"

# Function to display usage
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Destroy Database Development Workflows infrastructure

OPTIONS:
    -p, --project-id PROJECT_ID     Google Cloud Project ID (required if deployment-info.txt not found)
    -r, --region REGION             GCP region (default: ${DEFAULT_REGION})
    -z, --zone ZONE                 GCP zone (default: ${DEFAULT_ZONE})
    -f, --force                     Skip confirmation prompts
    -d, --dry-run                   Show what would be destroyed without making changes
    -h, --help                      Show this help message

EXAMPLES:
    $0                              # Destroy using deployment-info.txt
    $0 -p my-project                # Destroy with specific project ID
    $0 --dry-run                    # Preview destruction without making changes
    $0 --force                      # Skip confirmation prompts

EOF
}

# Parse command line arguments
PROJECT_ID="${DEFAULT_PROJECT_ID}"
REGION="${DEFAULT_REGION}"
ZONE="${DEFAULT_ZONE}"
FORCE=false
DRY_RUN=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -p|--project-id)
            PROJECT_ID="$2"
            shift 2
            ;;
        -r|--region)
            REGION="$2"
            shift 2
            ;;
        -z|--zone)
            ZONE="$2"
            shift 2
            ;;
        -f|--force)
            FORCE=true
            shift
            ;;
        -d|--dry-run)
            DRY_RUN=true
            shift
            ;;
        -h|--help)
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

# Load deployment information
load_deployment_info() {
    if [[ -f "$DEPLOYMENT_INFO_FILE" ]]; then
        log_info "Loading deployment information from ${DEPLOYMENT_INFO_FILE}..."
        
        # Extract values from deployment info file
        if [[ -z "$PROJECT_ID" ]]; then
            PROJECT_ID=$(grep "^Project ID:" "$DEPLOYMENT_INFO_FILE" | cut -d' ' -f3)
        fi
        if [[ "$REGION" == "$DEFAULT_REGION" ]]; then
            REGION=$(grep "^Region:" "$DEPLOYMENT_INFO_FILE" | cut -d' ' -f2)
        fi
        if [[ "$ZONE" == "$DEFAULT_ZONE" ]]; then
            ZONE=$(grep "^Zone:" "$DEPLOYMENT_INFO_FILE" | cut -d' ' -f2)
        fi
        
        # Extract resource names
        NETWORK_NAME=$(grep "^Network:" "$DEPLOYMENT_INFO_FILE" | cut -d' ' -f2)
        SUBNET_NAME=$(grep "^Subnet:" "$DEPLOYMENT_INFO_FILE" | cut -d' ' -f2)
        FIREWALL_RULE=$(grep "^Firewall Rule:" "$DEPLOYMENT_INFO_FILE" | cut -d' ' -f3)
        CLUSTER_NAME=$(grep "^Workstation Cluster:" "$DEPLOYMENT_INFO_FILE" | cut -d' ' -f3)
        CONFIG_NAME=$(grep "^Workstation Config:" "$DEPLOYMENT_INFO_FILE" | cut -d' ' -f3)
        WORKSTATION_NAME=$(grep "^Workstation:" "$DEPLOYMENT_INFO_FILE" | cut -d' ' -f2)
        REPO_NAME=$(grep "^Source Repository:" "$DEPLOYMENT_INFO_FILE" | cut -d' ' -f3)
        
        log_success "Deployment information loaded successfully"
    else
        log_warning "Deployment info file not found. Using provided/default values."
        
        # Use default naming patterns if no deployment info
        RANDOM_SUFFIX=$(openssl rand -hex 3)
        NETWORK_NAME="db-dev-network"
        SUBNET_NAME="db-dev-subnet"
        FIREWALL_RULE="${NETWORK_NAME}-allow-internal"
        CLUSTER_NAME="workstation-cluster-*"
        CONFIG_NAME="db-dev-config-*"
        WORKSTATION_NAME="db-dev-workstation-*"
        REPO_NAME="database-development-*"
    fi
    
    # Validate required values
    if [[ -z "$PROJECT_ID" ]]; then
        log_error "Project ID is required. Provide it with -p option or ensure deployment-info.txt exists."
        exit 1
    fi
}

# Confirmation prompt
confirm_destruction() {
    if [[ "$FORCE" == "true" ]]; then
        return 0
    fi
    
    echo
    log_warning "This will permanently destroy the following resources:"
    log_warning "  Project: ${PROJECT_ID}"
    log_warning "  Region: ${REGION}"
    log_warning "  All Cloud Workstations resources"
    log_warning "  VPC network and firewall rules"
    log_warning "  Source repositories and build triggers"
    log_warning "  Local configuration files"
    echo
    log_warning "This action cannot be undone!"
    echo
    
    read -p "Are you sure you want to continue? [y/N]: " -n 1 -r
    echo
    
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Destruction cancelled by user."
        exit 0
    fi
}

# Dry run mode
show_dry_run() {
    log_info "DRY RUN MODE - No resources will be destroyed"
    log_info "Would destroy the following resources:"
    log_info "  Project: ${PROJECT_ID}"
    log_info "  Region: ${REGION}"
    log_info "  Network: ${NETWORK_NAME}"
    log_info "  Subnet: ${SUBNET_NAME}"
    log_info "  Firewall Rule: ${FIREWALL_RULE}"
    log_info "  Workstation Cluster: ${CLUSTER_NAME}"
    log_info "  Workstation Config: ${CONFIG_NAME}"
    log_info "  Workstation: ${WORKSTATION_NAME}"
    log_info "  Source Repository: ${REPO_NAME}"
    log_info "  Build triggers (all)"
    log_info "  Local configuration files"
    exit 0
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "gcloud CLI is not installed. Please install it from https://cloud.google.com/sdk"
        exit 1
    fi
    
    # Check if authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        log_error "No active gcloud authentication found. Please run 'gcloud auth login'"
        exit 1
    fi
    
    # Set project
    gcloud config set project "${PROJECT_ID}"
    gcloud config set compute/region "${REGION}"
    gcloud config set compute/zone "${ZONE}"
    
    log_success "Prerequisites check completed"
}

# Stop and delete workstations
cleanup_workstations() {
    log_info "Cleaning up Cloud Workstations resources..."
    
    # List all workstations that match our pattern or specific name
    local workstations
    if [[ "$WORKSTATION_NAME" == *"*"* ]]; then
        # Pattern matching for when we don't have exact names
        workstations=$(gcloud workstations list --region="${REGION}" \
            --format="value(name)" --filter="name~db-dev-workstation" 2>/dev/null || true)
    else
        # Specific workstation name
        workstations=$(gcloud workstations list --region="${REGION}" \
            --format="value(name)" --filter="name=${WORKSTATION_NAME}" 2>/dev/null || true)
    fi
    
    # Stop and delete workstations
    if [[ -n "$workstations" ]]; then
        while IFS= read -r workstation; do
            if [[ -n "$workstation" ]]; then
                log_info "Stopping workstation: ${workstation}..."
                gcloud workstations stop "$workstation" \
                    --region="${REGION}" \
                    --cluster="${CLUSTER_NAME}" \
                    --config="${CONFIG_NAME}" \
                    --quiet 2>/dev/null || log_warning "Failed to stop workstation ${workstation}"
                
                log_info "Deleting workstation: ${workstation}..."
                gcloud workstations delete "$workstation" \
                    --region="${REGION}" \
                    --cluster="${CLUSTER_NAME}" \
                    --config="${CONFIG_NAME}" \
                    --quiet 2>/dev/null || log_warning "Failed to delete workstation ${workstation}"
            fi
        done <<< "$workstations"
    else
        log_info "No workstations found to delete"
    fi
    
    # Delete workstation configurations
    local configs
    if [[ "$CONFIG_NAME" == *"*"* ]]; then
        configs=$(gcloud workstations configs list --region="${REGION}" \
            --cluster="${CLUSTER_NAME}" --format="value(name)" \
            --filter="name~db-dev-config" 2>/dev/null || true)
    else
        configs=$(gcloud workstations configs list --region="${REGION}" \
            --cluster="${CLUSTER_NAME}" --format="value(name)" \
            --filter="name=${CONFIG_NAME}" 2>/dev/null || true)
    fi
    
    if [[ -n "$configs" ]]; then
        while IFS= read -r config; do
            if [[ -n "$config" ]]; then
                log_info "Deleting workstation configuration: ${config}..."
                gcloud workstations configs delete "$config" \
                    --region="${REGION}" \
                    --cluster="${CLUSTER_NAME}" \
                    --quiet 2>/dev/null || log_warning "Failed to delete config ${config}"
            fi
        done <<< "$configs"
    else
        log_info "No workstation configurations found to delete"
    fi
    
    # Delete workstation clusters
    local clusters
    if [[ "$CLUSTER_NAME" == *"*"* ]]; then
        clusters=$(gcloud workstations clusters list --region="${REGION}" \
            --format="value(name)" --filter="name~workstation-cluster" 2>/dev/null || true)
    else
        clusters=$(gcloud workstations clusters list --region="${REGION}" \
            --format="value(name)" --filter="name=${CLUSTER_NAME}" 2>/dev/null || true)
    fi
    
    if [[ -n "$clusters" ]]; then
        while IFS= read -r cluster; do
            if [[ -n "$cluster" ]]; then
                log_info "Deleting workstation cluster: ${cluster}..."
                gcloud workstations clusters delete "$cluster" \
                    --region="${REGION}" \
                    --quiet 2>/dev/null || log_warning "Failed to delete cluster ${cluster}"
            fi
        done <<< "$clusters"
    else
        log_info "No workstation clusters found to delete"
    fi
    
    log_success "Cloud Workstations resources cleanup completed"
}

# Delete build triggers and source repositories
cleanup_build_and_source() {
    log_info "Cleaning up Cloud Build triggers and Source Repositories..."
    
    # Delete build triggers
    local triggers
    triggers=$(gcloud builds triggers list --format="value(id)" \
        --filter="description~'Automated database testing'" 2>/dev/null || true)
    
    if [[ -n "$triggers" ]]; then
        while IFS= read -r trigger; do
            if [[ -n "$trigger" ]]; then
                log_info "Deleting build trigger: ${trigger}..."
                gcloud builds triggers delete "$trigger" --quiet 2>/dev/null || \
                    log_warning "Failed to delete trigger ${trigger}"
            fi
        done <<< "$triggers"
    else
        log_info "No build triggers found to delete"
    fi
    
    # Delete source repositories
    local repos
    if [[ "$REPO_NAME" == *"*"* ]]; then
        repos=$(gcloud source repos list --format="value(name)" \
            --filter="name~database-development" 2>/dev/null || true)
    else
        repos=$(gcloud source repos list --format="value(name)" \
            --filter="name=${REPO_NAME}" 2>/dev/null || true)
    fi
    
    if [[ -n "$repos" ]]; then
        while IFS= read -r repo; do
            if [[ -n "$repo" ]]; then
                log_info "Deleting source repository: ${repo}..."
                gcloud source repos delete "$repo" --quiet 2>/dev/null || \
                    log_warning "Failed to delete repository ${repo}"
            fi
        done <<< "$repos"
    else
        log_info "No source repositories found to delete"
    fi
    
    log_success "Build and source control resources cleanup completed"
}

# Delete networking resources
cleanup_networking() {
    log_info "Cleaning up networking resources..."
    
    # Delete firewall rule
    if gcloud compute firewall-rules describe "${FIREWALL_RULE}" &>/dev/null; then
        log_info "Deleting firewall rule: ${FIREWALL_RULE}..."
        gcloud compute firewall-rules delete "${FIREWALL_RULE}" --quiet 2>/dev/null || \
            log_warning "Failed to delete firewall rule ${FIREWALL_RULE}"
    else
        log_info "Firewall rule ${FIREWALL_RULE} not found"
    fi
    
    # Delete subnet
    if gcloud compute networks subnets describe "${SUBNET_NAME}" --region="${REGION}" &>/dev/null; then
        log_info "Deleting subnet: ${SUBNET_NAME}..."
        gcloud compute networks subnets delete "${SUBNET_NAME}" \
            --region="${REGION}" --quiet 2>/dev/null || \
            log_warning "Failed to delete subnet ${SUBNET_NAME}"
    else
        log_info "Subnet ${SUBNET_NAME} not found"
    fi
    
    # Delete VPC network
    if gcloud compute networks describe "${NETWORK_NAME}" &>/dev/null; then
        log_info "Deleting VPC network: ${NETWORK_NAME}..."
        gcloud compute networks delete "${NETWORK_NAME}" --quiet 2>/dev/null || \
            log_warning "Failed to delete network ${NETWORK_NAME}"
    else
        log_info "VPC network ${NETWORK_NAME} not found"
    fi
    
    log_success "Networking resources cleanup completed"
}

# Clean up local files
cleanup_local_files() {
    log_info "Cleaning up local configuration files..."
    
    # Remove AlloyDB configuration directory
    if [[ -d "${PROJECT_DIR}/alloydb-config" ]]; then
        log_info "Removing AlloyDB configuration directory..."
        rm -rf "${PROJECT_DIR}/alloydb-config"
    fi
    
    # Remove Cloud Build configuration
    if [[ -f "${PROJECT_DIR}/cloudbuild.yaml" ]]; then
        log_info "Removing Cloud Build configuration..."
        rm -f "${PROJECT_DIR}/cloudbuild.yaml"
    fi
    
    # Remove temporary workstation configuration
    if [[ -f "${SCRIPT_DIR}/workstation-config.yaml" ]]; then
        log_info "Removing temporary workstation configuration..."
        rm -f "${SCRIPT_DIR}/workstation-config.yaml"
    fi
    
    # Remove deployment info file
    if [[ -f "${DEPLOYMENT_INFO_FILE}" ]]; then
        log_info "Removing deployment information file..."
        rm -f "${DEPLOYMENT_INFO_FILE}"
    fi
    
    # Remove any temporary directories
    if [[ -d "${SCRIPT_DIR}/temp-repo" ]]; then
        rm -rf "${SCRIPT_DIR}/temp-repo"
    fi
    
    log_success "Local files cleanup completed"
}

# Verify cleanup completion
verify_cleanup() {
    log_info "Verifying cleanup completion..."
    
    local issues_found=false
    
    # Check for remaining workstation clusters
    local remaining_clusters
    remaining_clusters=$(gcloud workstations clusters list --region="${REGION}" \
        --format="value(name)" --filter="name~workstation-cluster" 2>/dev/null || true)
    
    if [[ -n "$remaining_clusters" ]]; then
        log_warning "Some workstation clusters may still exist:"
        echo "$remaining_clusters"
        issues_found=true
    fi
    
    # Check for remaining source repositories
    local remaining_repos
    remaining_repos=$(gcloud source repos list --format="value(name)" \
        --filter="name~database-development" 2>/dev/null || true)
    
    if [[ -n "$remaining_repos" ]]; then
        log_warning "Some source repositories may still exist:"
        echo "$remaining_repos"
        issues_found=true
    fi
    
    # Check for remaining networks
    if gcloud compute networks describe "${NETWORK_NAME}" &>/dev/null; then
        log_warning "VPC network ${NETWORK_NAME} may still exist"
        issues_found=true
    fi
    
    if [[ "$issues_found" == "true" ]]; then
        log_warning "Some resources may still exist. Please check the Google Cloud Console."
        log_info "You may need to manually delete remaining resources or wait for async operations to complete."
    else
        log_success "All resources appear to have been cleaned up successfully"
    fi
}

# Main cleanup function
main() {
    log_info "Starting Database Development Workflows cleanup..."
    
    load_deployment_info
    
    if [[ "$DRY_RUN" == "true" ]]; then
        show_dry_run
    fi
    
    confirm_destruction
    check_prerequisites
    
    log_info "Project: ${PROJECT_ID}"
    log_info "Region: ${REGION}"
    log_info "Beginning resource cleanup..."
    
    # Cleanup in reverse order of creation to handle dependencies
    cleanup_workstations
    cleanup_build_and_source
    cleanup_networking
    cleanup_local_files
    verify_cleanup
    
    log_success "Cleanup completed successfully!"
    log_success "All Database Development Workflows resources have been removed."
    
    echo
    log_info "Summary:"
    log_info "✅ Cloud Workstations resources deleted"
    log_info "✅ Build triggers and source repositories deleted"
    log_info "✅ VPC network and firewall rules deleted"
    log_info "✅ Local configuration files removed"
    echo
    log_info "If you plan to redeploy, you can run ./scripts/deploy.sh again."
    log_warning "Check your Google Cloud Console to confirm all resources have been removed."
}

# Error handling for cleanup
handle_cleanup_error() {
    log_error "Cleanup encountered an error at line $1."
    log_warning "Some resources may not have been deleted completely."
    log_info "Please check the Google Cloud Console and manually delete any remaining resources."
    log_info "You can also try running this script again to retry the cleanup."
    exit 1
}

trap 'handle_cleanup_error $LINENO' ERR

# Run main function
main "$@"