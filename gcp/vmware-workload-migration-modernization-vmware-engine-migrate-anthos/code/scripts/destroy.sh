#!/bin/bash

# VMware Workload Migration and Modernization Cleanup Script
# This script removes all resources created by the deployment script

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING:${NC} $1"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1"
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO:${NC} $1"
}

# Check if required tools are installed
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        error "gcloud CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if kubectl is installed
    if ! command -v kubectl &> /dev/null; then
        error "kubectl is not installed. Please install it first."
        exit 1
    fi
    
    log "Prerequisites check completed successfully"
}

# Check if user is authenticated with gcloud
check_authentication() {
    log "Checking Google Cloud authentication..."
    
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q "@"; then
        error "Not authenticated with Google Cloud. Please run 'gcloud auth login' first."
        exit 1
    fi
    
    log "Authentication check completed successfully"
}

# Load environment variables from deployment info file
load_environment() {
    log "Loading environment variables..."
    
    local info_file="${HOME}/vmware-migration-deployment-info.txt"
    
    if [ -f "$info_file" ]; then
        info "Loading configuration from deployment info file"
        
        # Extract values from the info file
        export PROJECT_ID=$(grep "Project ID:" "$info_file" | cut -d' ' -f3)
        export REGION=$(grep "Region:" "$info_file" | cut -d' ' -f2)
        export ZONE=$(grep "Zone:" "$info_file" | cut -d' ' -f2)
        export PRIVATE_CLOUD_NAME=$(grep "Private Cloud Name:" "$info_file" | cut -d' ' -f4)
        export VMWARE_ENGINE_REGION=$(grep "Location:" "$info_file" | cut -d' ' -f2)
        export NETWORK_NAME=$(grep "VPC Network:" "$info_file" | cut -d' ' -f3)
        export GKE_CLUSTER_NAME=$(grep "Cluster Name:" "$info_file" | cut -d' ' -f3)
        export REPOSITORY_NAME=$(grep "Repository:" "$info_file" | cut -d' ' -f2)
    else
        warn "Deployment info file not found. Using environment variables or defaults."
        
        # Use environment variables or prompt for required values
        if [ -z "${PROJECT_ID:-}" ]; then
            export PROJECT_ID=$(gcloud config get-value project 2>/dev/null || echo "")
            if [ -z "$PROJECT_ID" ]; then
                read -p "Enter your Google Cloud Project ID: " PROJECT_ID
                export PROJECT_ID
            fi
        fi
        
        # Set default values if not provided
        export REGION="${REGION:-us-central1}"
        export ZONE="${ZONE:-us-central1-a}"
        export VMWARE_ENGINE_REGION="${VMWARE_ENGINE_REGION:-us-central1}"
        export REPOSITORY_NAME="${REPOSITORY_NAME:-modernized-apps}"
    fi
    
    # Set gcloud defaults
    gcloud config set project "${PROJECT_ID}"
    gcloud config set compute/region "${REGION}"
    gcloud config set compute/zone "${ZONE}"
    
    log "Environment variables loaded:"
    info "  PROJECT_ID: ${PROJECT_ID}"
    info "  REGION: ${REGION}"
    info "  PRIVATE_CLOUD_NAME: ${PRIVATE_CLOUD_NAME:-Not set}"
    info "  GKE_CLUSTER_NAME: ${GKE_CLUSTER_NAME:-Not set}"
    info "  NETWORK_NAME: ${NETWORK_NAME:-Not set}"
}

# Confirm destruction with user
confirm_destruction() {
    echo ""
    warn "This will permanently delete all VMware Migration infrastructure!"
    warn "This includes:"
    warn "  - VMware Engine private cloud (${PRIVATE_CLOUD_NAME:-unknown})"
    warn "  - GKE cluster (${GKE_CLUSTER_NAME:-unknown})"
    warn "  - VPC network (${NETWORK_NAME:-unknown})"
    warn "  - Artifact Registry repository (${REPOSITORY_NAME:-unknown})"
    warn "  - Monitoring dashboards and alerts"
    warn "  - All associated data and configurations"
    echo ""
    
    read -p "Are you sure you want to continue? (yes/no): " -r
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        info "Destruction cancelled by user"
        exit 0
    fi
    
    echo ""
    warn "Last chance! This action cannot be undone."
    read -p "Type 'DELETE' to confirm: " -r
    if [[ $REPLY != "DELETE" ]]; then
        info "Destruction cancelled by user"
        exit 0
    fi
    
    log "Destruction confirmed. Proceeding with cleanup..."
}

# Remove sample application and GKE cluster
cleanup_gke_resources() {
    log "Cleaning up GKE resources..."
    
    # Check if GKE cluster exists
    if [ -n "${GKE_CLUSTER_NAME:-}" ]; then
        if gcloud container clusters describe "${GKE_CLUSTER_NAME}" --region="${REGION}" &>/dev/null; then
            info "Removing GKE cluster: ${GKE_CLUSTER_NAME}"
            
            # Get cluster credentials first
            gcloud container clusters get-credentials "${GKE_CLUSTER_NAME}" \
                --region="${REGION}" 2>/dev/null || true
            
            # Remove sample application
            info "Removing sample application"
            kubectl delete namespace modernized-apps --ignore-not-found=true || true
            
            # Delete GKE cluster
            info "Deleting GKE cluster (this may take several minutes)"
            gcloud container clusters delete "${GKE_CLUSTER_NAME}" \
                --region="${REGION}" \
                --quiet || {
                error "Failed to delete GKE cluster"
                # Continue with other cleanup
            }
            
            log "GKE cluster cleanup completed"
        else
            info "GKE cluster not found, skipping"
        fi
    else
        info "GKE cluster name not provided, skipping"
    fi
}

# Remove Artifact Registry repository
cleanup_artifact_registry() {
    log "Cleaning up Artifact Registry repository..."
    
    if [ -n "${REPOSITORY_NAME:-}" ]; then
        if gcloud artifacts repositories describe "${REPOSITORY_NAME}" --location="${REGION}" &>/dev/null; then
            info "Removing Artifact Registry repository: ${REPOSITORY_NAME}"
            gcloud artifacts repositories delete "${REPOSITORY_NAME}" \
                --location="${REGION}" \
                --quiet || {
                error "Failed to delete Artifact Registry repository"
                # Continue with other cleanup
            }
            
            log "Artifact Registry repository cleanup completed"
        else
            info "Artifact Registry repository not found, skipping"
        fi
    else
        info "Repository name not provided, skipping"
    fi
}

# Remove VMware Engine private cloud
cleanup_vmware_engine() {
    log "Cleaning up VMware Engine private cloud..."
    warn "This operation takes 30-45 minutes to complete"
    
    if [ -n "${PRIVATE_CLOUD_NAME:-}" ]; then
        if gcloud vmware private-clouds describe "${PRIVATE_CLOUD_NAME}" --location="${VMWARE_ENGINE_REGION}" &>/dev/null; then
            info "Removing VMware Engine private cloud: ${PRIVATE_CLOUD_NAME}"
            
            gcloud vmware private-clouds delete "${PRIVATE_CLOUD_NAME}" \
                --location="${VMWARE_ENGINE_REGION}" \
                --quiet || {
                error "Failed to delete VMware Engine private cloud"
                # Continue with other cleanup
            }
            
            # Wait for deletion to complete
            info "Waiting for VMware Engine private cloud deletion to complete..."
            while true; do
                if ! gcloud vmware private-clouds describe "${PRIVATE_CLOUD_NAME}" --location="${VMWARE_ENGINE_REGION}" &>/dev/null; then
                    log "VMware Engine private cloud deletion completed"
                    break
                else
                    info "Still deleting... waiting 60 seconds"
                    sleep 60
                fi
            done
        else
            info "VMware Engine private cloud not found, skipping"
        fi
    else
        info "Private cloud name not provided, skipping"
    fi
}

# Remove monitoring resources
cleanup_monitoring() {
    log "Cleaning up monitoring resources..."
    
    # Remove monitoring policies
    info "Removing monitoring policies"
    local policies=$(gcloud alpha monitoring policies list --format="value(name)" 2>/dev/null || echo "")
    if [ -n "$policies" ]; then
        while IFS= read -r policy; do
            if [[ "$policy" == *"Hybrid Infrastructure Alerts"* ]]; then
                info "Removing policy: $policy"
                gcloud alpha monitoring policies delete "$policy" --quiet || true
            fi
        done <<< "$policies"
    else
        info "No monitoring policies found"
    fi
    
    # Remove monitoring dashboards
    info "Removing monitoring dashboards"
    local dashboards=$(gcloud monitoring dashboards list --format="value(name)" 2>/dev/null || echo "")
    if [ -n "$dashboards" ]; then
        while IFS= read -r dashboard; do
            local dashboard_name=$(gcloud monitoring dashboards describe "$dashboard" --format="value(displayName)" 2>/dev/null || echo "")
            if [[ "$dashboard_name" == *"VMware Migration"* ]]; then
                info "Removing dashboard: $dashboard_name"
                gcloud monitoring dashboards delete "$dashboard" --quiet || true
            fi
        done <<< "$dashboards"
    else
        info "No monitoring dashboards found"
    fi
    
    log "Monitoring resources cleanup completed"
}

# Remove networking resources
cleanup_networking() {
    log "Cleaning up networking resources..."
    
    if [ -n "${NETWORK_NAME:-}" ]; then
        # Remove firewall rules
        info "Removing firewall rules"
        local firewall_rules=$(gcloud compute firewall-rules list --filter="network:${NETWORK_NAME}" --format="value(name)" 2>/dev/null || echo "")
        if [ -n "$firewall_rules" ]; then
            while IFS= read -r rule; do
                if [ -n "$rule" ]; then
                    info "Removing firewall rule: $rule"
                    gcloud compute firewall-rules delete "$rule" --quiet || true
                fi
            done <<< "$firewall_rules"
        fi
        
        # Remove VPN gateway if exists
        info "Checking for VPN gateway"
        if gcloud compute vpn-gateways describe vmware-vpn-gateway --region="${REGION}" &>/dev/null; then
            info "Removing VPN gateway"
            gcloud compute vpn-gateways delete vmware-vpn-gateway --region="${REGION}" --quiet || true
        fi
        
        # Remove subnets
        info "Removing subnets"
        local subnets=$(gcloud compute networks subnets list --filter="network:${NETWORK_NAME}" --format="value(name,region)" 2>/dev/null || echo "")
        if [ -n "$subnets" ]; then
            while IFS= read -r subnet_info; do
                if [ -n "$subnet_info" ]; then
                    local subnet_name=$(echo "$subnet_info" | awk '{print $1}')
                    local subnet_region=$(echo "$subnet_info" | awk '{print $2}')
                    info "Removing subnet: $subnet_name in region: $subnet_region"
                    gcloud compute networks subnets delete "$subnet_name" --region="$subnet_region" --quiet || true
                fi
            done <<< "$subnets"
        fi
        
        # Remove VPC network
        info "Removing VPC network: ${NETWORK_NAME}"
        gcloud compute networks delete "${NETWORK_NAME}" --quiet || {
            error "Failed to delete VPC network"
            # Continue with other cleanup
        }
        
        log "Networking resources cleanup completed"
    else
        info "Network name not provided, skipping networking cleanup"
    fi
}

# Remove local workspace
cleanup_workspace() {
    log "Cleaning up local workspace..."
    
    local workspace_dir="${HOME}/vmware-migration-workspace"
    if [ -d "$workspace_dir" ]; then
        info "Removing migration workspace: $workspace_dir"
        rm -rf "$workspace_dir" || {
            warn "Failed to remove workspace directory"
        }
    else
        info "Workspace directory not found, skipping"
    fi
    
    # Remove deployment info file
    local info_file="${HOME}/vmware-migration-deployment-info.txt"
    if [ -f "$info_file" ]; then
        info "Removing deployment info file: $info_file"
        rm -f "$info_file" || {
            warn "Failed to remove deployment info file"
        }
    else
        info "Deployment info file not found, skipping"
    fi
    
    log "Local workspace cleanup completed"
}

# Verify cleanup completion
verify_cleanup() {
    log "Verifying cleanup completion..."
    
    local cleanup_issues=0
    
    # Check VMware Engine private cloud
    if [ -n "${PRIVATE_CLOUD_NAME:-}" ]; then
        if gcloud vmware private-clouds describe "${PRIVATE_CLOUD_NAME}" --location="${VMWARE_ENGINE_REGION}" &>/dev/null; then
            warn "VMware Engine private cloud still exists (may still be deleting)"
            cleanup_issues=$((cleanup_issues + 1))
        else
            info "✓ VMware Engine private cloud removed"
        fi
    fi
    
    # Check GKE cluster
    if [ -n "${GKE_CLUSTER_NAME:-}" ]; then
        if gcloud container clusters describe "${GKE_CLUSTER_NAME}" --region="${REGION}" &>/dev/null; then
            warn "GKE cluster still exists"
            cleanup_issues=$((cleanup_issues + 1))
        else
            info "✓ GKE cluster removed"
        fi
    fi
    
    # Check Artifact Registry
    if [ -n "${REPOSITORY_NAME:-}" ]; then
        if gcloud artifacts repositories describe "${REPOSITORY_NAME}" --location="${REGION}" &>/dev/null; then
            warn "Artifact Registry repository still exists"
            cleanup_issues=$((cleanup_issues + 1))
        else
            info "✓ Artifact Registry repository removed"
        fi
    fi
    
    # Check VPC network
    if [ -n "${NETWORK_NAME:-}" ]; then
        if gcloud compute networks describe "${NETWORK_NAME}" &>/dev/null; then
            warn "VPC network still exists"
            cleanup_issues=$((cleanup_issues + 1))
        else
            info "✓ VPC network removed"
        fi
    fi
    
    if [ $cleanup_issues -eq 0 ]; then
        log "Cleanup verification completed successfully"
    else
        warn "Cleanup completed with $cleanup_issues issues. Some resources may still be deleting."
    fi
}

# Main cleanup function
main() {
    log "Starting VMware Migration and Modernization cleanup..."
    
    # Run cleanup steps
    check_prerequisites
    check_authentication
    load_environment
    confirm_destruction
    
    # Cleanup resources in reverse order of creation
    cleanup_gke_resources
    cleanup_artifact_registry
    cleanup_vmware_engine
    cleanup_monitoring
    cleanup_networking
    cleanup_workspace
    
    # Verify cleanup
    verify_cleanup
    
    log "Cleanup completed successfully!"
    info ""
    info "Important Notes:"
    info "- VMware Engine private cloud deletion takes 30-45 minutes"
    info "- Check Google Cloud Console to verify all resources are removed"
    info "- Monitor your billing to ensure no unexpected charges"
    info "- Some resources may have dependencies that prevent immediate deletion"
    info ""
    log "All cleanup operations have been initiated"
}

# Run main function
main "$@"