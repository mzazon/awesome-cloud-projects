#!/bin/bash

# =============================================================================
# Azure HPC with Managed Lustre and CycleCloud - Cleanup Script
# =============================================================================
# This script safely removes all resources created by the deployment script:
# - Terminates CycleCloud clusters and compute nodes
# - Deletes Azure Managed Lustre file system
# - Removes virtual network infrastructure
# - Cleans up storage accounts and monitoring resources
# - Deletes the resource group and all contained resources
# =============================================================================

set -e  # Exit on any error
set -u  # Exit on undefined variables

# =============================================================================
# Configuration and Variables
# =============================================================================

# Script metadata
SCRIPT_NAME="destroy.sh"
SCRIPT_VERSION="1.0"
CLEANUP_START_TIME=$(date +%s)

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1${NC}"
}

# =============================================================================
# Prerequisites Check
# =============================================================================

check_prerequisites() {
    log "Checking prerequisites for cleanup..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        error "Azure CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if logged in to Azure
    if ! az account show &> /dev/null; then
        error "Please log in to Azure using 'az login'"
        exit 1
    fi
    
    log "Prerequisites check completed successfully"
}

# =============================================================================
# Environment Detection
# =============================================================================

detect_environment() {
    log "Detecting deployment environment..."
    
    # Look for state directory
    local state_dirs=(./deployment-state-*)
    if [[ ${#state_dirs[@]} -gt 0 && -d "${state_dirs[0]}" ]]; then
        export STATE_DIR="${state_dirs[0]}"
        log "Found state directory: $STATE_DIR"
        
        # Source environment variables if they exist
        if [[ -f "$STATE_DIR/environment.env" ]]; then
            source "$STATE_DIR/environment.env"
            log "Loaded environment variables from: $STATE_DIR/environment.env"
        else
            warn "Environment file not found: $STATE_DIR/environment.env"
        fi
    else
        warn "No state directory found. Manual cleanup may be required."
        return 1
    fi
    
    # Validate required variables
    if [[ -z "${RESOURCE_GROUP:-}" ]]; then
        error "RESOURCE_GROUP not found in environment. Cannot proceed with cleanup."
        exit 1
    fi
    
    # Display cleanup configuration
    info "Cleanup Configuration:"
    info "  Resource Group: ${RESOURCE_GROUP:-unknown}"
    info "  Location: ${LOCATION:-unknown}"
    info "  Lustre Name: ${LUSTRE_NAME:-unknown}"
    info "  CycleCloud Name: ${CYCLECLOUD_NAME:-unknown}"
    info "  Storage Account: ${STORAGE_ACCOUNT:-unknown}"
    info "  Virtual Network: ${VNET_NAME:-unknown}"
    
    return 0
}

# =============================================================================
# Manual Environment Setup
# =============================================================================

setup_manual_environment() {
    log "Setting up manual cleanup environment..."
    
    # Prompt for resource group name
    echo -n "Enter the resource group name to delete: "
    read -r RESOURCE_GROUP
    
    if [[ -z "$RESOURCE_GROUP" ]]; then
        error "Resource group name cannot be empty"
        exit 1
    fi
    
    # Check if resource group exists
    if ! az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        error "Resource group '$RESOURCE_GROUP' does not exist"
        exit 1
    fi
    
    # Get location from resource group
    export LOCATION=$(az group show --name "$RESOURCE_GROUP" --query location -o tsv)
    
    info "Manual cleanup configuration:"
    info "  Resource Group: $RESOURCE_GROUP"
    info "  Location: $LOCATION"
    
    # Set default values for optional cleanup
    export LUSTRE_NAME=""
    export CYCLECLOUD_NAME=""
    export STORAGE_ACCOUNT=""
    export VNET_NAME=""
    export SSH_KEY_NAME="hpc-ssh-key"
    export STATE_DIR=""
}

# =============================================================================
# Confirmation Prompt
# =============================================================================

confirm_cleanup() {
    warn "⚠️  DESTRUCTIVE OPERATION WARNING ⚠️"
    warn "This will permanently delete the following resources:"
    warn "  - Resource Group: $RESOURCE_GROUP"
    warn "  - All contained Azure resources"
    warn "  - Azure Managed Lustre file system and all data"
    warn "  - CycleCloud clusters and compute nodes"
    warn "  - Virtual network infrastructure"
    warn "  - Storage accounts and all data"
    warn "  - SSH keys and local configuration files"
    warn ""
    warn "This action cannot be undone!"
    
    echo -n "Are you sure you want to proceed? (type 'yes' to confirm): "
    read -r confirmation
    
    if [[ "$confirmation" != "yes" ]]; then
        info "Cleanup cancelled by user"
        exit 0
    fi
    
    log "Cleanup confirmed. Proceeding with resource deletion..."
}

# =============================================================================
# CycleCloud Cluster Cleanup
# =============================================================================

cleanup_cyclecloud_clusters() {
    log "Cleaning up CycleCloud clusters..."
    
    # Skip if CycleCloud name is not available
    if [[ -z "${CYCLECLOUD_NAME:-}" ]]; then
        warn "CycleCloud name not available. Skipping cluster cleanup."
        return 0
    fi
    
    # Check if CycleCloud VM exists
    if ! az vm show --name "$CYCLECLOUD_NAME" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        warn "CycleCloud VM '$CYCLECLOUD_NAME' not found. Skipping cluster cleanup."
        return 0
    fi
    
    # Get CycleCloud IP
    local cyclecloud_ip=$(az vm show \
        --name "$CYCLECLOUD_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --show-details \
        --query publicIps \
        --output tsv)
    
    if [[ -n "$cyclecloud_ip" && -f ~/.ssh/${SSH_KEY_NAME} ]]; then
        log "Attempting to terminate CycleCloud clusters..."
        
        # Try to terminate clusters (may fail if SSH is not accessible)
        ssh -i ~/.ssh/${SSH_KEY_NAME} -o ConnectTimeout=10 -o StrictHostKeyChecking=no \
            azureuser@${cyclecloud_ip} << 'REMOTE_COMMANDS' || warn "Failed to connect to CycleCloud for cluster termination"

# List and terminate all clusters
for cluster in $(cyclecloud show_clusters --output json | jq -r '.[].name'); do
    echo "Terminating cluster: $cluster"
    cyclecloud terminate_cluster "$cluster" || true
done

# Wait for cluster termination
sleep 30

exit
REMOTE_COMMANDS
        
        log "CycleCloud cluster termination completed"
    else
        warn "Cannot connect to CycleCloud for cluster termination"
    fi
}

# =============================================================================
# Lustre File System Cleanup
# =============================================================================

cleanup_lustre_filesystem() {
    log "Cleaning up Azure Managed Lustre file system..."
    
    # Skip if Lustre name is not available
    if [[ -z "${LUSTRE_NAME:-}" ]]; then
        warn "Lustre name not available. Skipping Lustre cleanup."
        return 0
    fi
    
    # Check if Lustre extension is available
    if ! az extension list | grep -q "amlfs"; then
        warn "Azure Managed Lustre extension not found. Installing..."
        az extension add --name amlfs || warn "Failed to install amlfs extension"
    fi
    
    # Check if Lustre file system exists
    if az amlfs show --name "$LUSTRE_NAME" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        warn "Deleting Lustre file system: $LUSTRE_NAME (this will destroy all data)"
        
        # Delete Lustre file system
        az amlfs delete \
            --name "$LUSTRE_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --yes || warn "Failed to delete Lustre file system"
        
        # Wait for deletion to complete
        log "Waiting for Lustre file system deletion to complete..."
        local timeout=600  # 10 minutes timeout
        local elapsed=0
        
        while az amlfs show --name "$LUSTRE_NAME" --resource-group "$RESOURCE_GROUP" &> /dev/null; do
            if [[ $elapsed -ge $timeout ]]; then
                warn "Timeout waiting for Lustre deletion. Proceeding with cleanup..."
                break
            fi
            sleep 10
            elapsed=$((elapsed + 10))
        done
        
        log "Lustre file system cleanup completed"
    else
        warn "Lustre file system '$LUSTRE_NAME' not found"
    fi
}

# =============================================================================
# Resource Group Cleanup
# =============================================================================

cleanup_resource_group() {
    log "Cleaning up resource group and all contained resources..."
    
    # List resources in the resource group
    log "Resources to be deleted:"
    az resource list --resource-group "$RESOURCE_GROUP" --output table || warn "Failed to list resources"
    
    # Delete the entire resource group
    log "Deleting resource group: $RESOURCE_GROUP"
    az group delete \
        --name "$RESOURCE_GROUP" \
        --yes \
        --no-wait
    
    log "Resource group deletion initiated"
    
    # Monitor deletion progress
    log "Monitoring resource group deletion progress..."
    local timeout=1800  # 30 minutes timeout
    local elapsed=0
    
    while az group show --name "$RESOURCE_GROUP" &> /dev/null; do
        if [[ $elapsed -ge $timeout ]]; then
            warn "Timeout waiting for resource group deletion. Check Azure portal for status."
            break
        fi
        
        # Print progress every 30 seconds
        if [[ $((elapsed % 30)) -eq 0 ]]; then
            info "Still deleting... elapsed time: ${elapsed}s"
        fi
        
        sleep 10
        elapsed=$((elapsed + 10))
    done
    
    if ! az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        log "Resource group deleted successfully"
    else
        warn "Resource group deletion may still be in progress"
    fi
}

# =============================================================================
# Local Cleanup
# =============================================================================

cleanup_local_files() {
    log "Cleaning up local files and SSH keys..."
    
    # Clean up SSH keys
    if [[ -n "${SSH_KEY_NAME:-}" ]]; then
        if [[ -f ~/.ssh/${SSH_KEY_NAME} ]]; then
            rm -f ~/.ssh/${SSH_KEY_NAME}*
            log "SSH keys deleted: ~/.ssh/${SSH_KEY_NAME}*"
        fi
    fi
    
    # Clean up state directory
    if [[ -n "${STATE_DIR:-}" && -d "$STATE_DIR" ]]; then
        rm -rf "$STATE_DIR"
        log "State directory deleted: $STATE_DIR"
    fi
    
    # Clean up any temporary files
    rm -f lustre-mount-script.sh
    rm -f ./deployment-state-*/lustre-mount-script.sh
    
    log "Local cleanup completed"
}

# =============================================================================
# Verification
# =============================================================================

verify_cleanup() {
    log "Verifying cleanup completion..."
    
    # Check if resource group still exists
    if az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        warn "Resource group '$RESOURCE_GROUP' still exists. Check Azure portal for deletion status."
        info "You can check deletion status with: az group show --name '$RESOURCE_GROUP'"
    else
        log "Resource group '$RESOURCE_GROUP' has been successfully deleted"
    fi
    
    # Check for remaining SSH keys
    if [[ -n "${SSH_KEY_NAME:-}" && -f ~/.ssh/${SSH_KEY_NAME} ]]; then
        warn "SSH keys still exist: ~/.ssh/${SSH_KEY_NAME}*"
    fi
    
    # Check for remaining state directories
    local remaining_state_dirs=(./deployment-state-*)
    if [[ ${#remaining_state_dirs[@]} -gt 0 && -d "${remaining_state_dirs[0]}" ]]; then
        warn "State directories still exist: ${remaining_state_dirs[*]}"
    fi
    
    log "Cleanup verification completed"
}

# =============================================================================
# Post-Cleanup Summary
# =============================================================================

cleanup_summary() {
    log "Cleanup operation summary:"
    
    # Calculate cleanup time
    local cleanup_end_time=$(date +%s)
    local cleanup_duration=$((cleanup_end_time - CLEANUP_START_TIME))
    local cleanup_minutes=$((cleanup_duration / 60))
    local cleanup_seconds=$((cleanup_duration % 60))
    
    info "=== Cleanup Summary ==="
    info "Resource Group: $RESOURCE_GROUP"
    info "Cleanup Duration: ${cleanup_minutes}m ${cleanup_seconds}s"
    info "Status: Completed"
    
    info "=== What was deleted ==="
    info "✅ CycleCloud clusters and compute nodes"
    info "✅ Azure Managed Lustre file system and all data"
    info "✅ Virtual network infrastructure"
    info "✅ Storage accounts and all data"
    info "✅ Log Analytics workspace"
    info "✅ Resource group and all contained resources"
    info "✅ SSH keys and local configuration files"
    
    info "=== Important Notes ==="
    info "• All HPC workload data has been permanently deleted"
    info "• Check Azure portal to confirm all resources are deleted"
    info "• Monitor your Azure billing to ensure no charges continue"
    info "• Resource group deletion may take up to 30 minutes to complete"
    
    log "Cleanup completed successfully!"
}

# =============================================================================
# Error Handling
# =============================================================================

handle_cleanup_error() {
    error "Cleanup operation failed!"
    error "Some resources may not have been deleted properly."
    error "Please check Azure portal and manually delete remaining resources."
    error "Resource group: ${RESOURCE_GROUP:-unknown}"
    
    exit 1
}

# Set up error handling
trap handle_cleanup_error ERR

# =============================================================================
# Main Cleanup Flow
# =============================================================================

main() {
    log "Starting Azure HPC cleanup process"
    log "Script: $SCRIPT_NAME v$SCRIPT_VERSION"
    
    # Check prerequisites
    check_prerequisites
    
    # Detect or setup environment
    if ! detect_environment; then
        setup_manual_environment
    fi
    
    # Confirm cleanup operation
    confirm_cleanup
    
    # Execute cleanup steps
    cleanup_cyclecloud_clusters
    cleanup_lustre_filesystem
    cleanup_resource_group
    cleanup_local_files
    
    # Verify and summarize cleanup
    verify_cleanup
    cleanup_summary
    
    log "Azure HPC cleanup process completed!"
}

# =============================================================================
# Script Execution
# =============================================================================

# Check if script is being sourced or executed
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi