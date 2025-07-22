#!/bin/bash

# Multi-Tenant SaaS Resource Isolation Cleanup Script
# This script removes all resources created for the multi-tenant SaaS deployment

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
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✅ $1${NC}"
}

warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️  $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ❌ $1${NC}"
}

# Check if running in dry-run mode
DRY_RUN=false
FORCE=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            warning "Running in dry-run mode - no resources will be deleted"
            shift
            ;;
        --force)
            FORCE=true
            shift
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: $0 [--dry-run] [--force]"
            exit 1
            ;;
    esac
done

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        error "Azure CLI is not installed. Please install it from https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
        exit 1
    fi
    
    # Check if user is logged in
    if ! az account show &> /dev/null; then
        error "Please log in to Azure using 'az login'"
        exit 1
    fi
    
    # Check if jq is installed for JSON parsing
    if ! command -v jq &> /dev/null; then
        error "jq is not installed. Please install it for JSON parsing"
        exit 1
    fi
    
    success "All prerequisites met"
}

# Function to get environment variables
get_environment_variables() {
    log "Getting environment variables..."
    
    export SUBSCRIPTION_ID=$(az account show --query id --output tsv)
    export TENANT_ID=$(az account show --query tenantId --output tsv)
    
    # Try to find existing resources to determine SAAS_PREFIX
    local control_plane_rg=$(az group list --query "[?contains(name, 'rg-saas-control-plane')].name" --output tsv | head -1)
    
    if [[ -n "$control_plane_rg" ]]; then
        export RESOURCE_GROUP="$control_plane_rg"
        log "Found control plane resource group: ${RESOURCE_GROUP}"
        
        # Try to find Key Vault to determine SAAS_PREFIX
        local key_vault=$(az keyvault list --resource-group "${RESOURCE_GROUP}" --query "[?starts_with(name, 'kv-saas')].name" --output tsv | head -1)
        if [[ -n "$key_vault" ]]; then
            export SAAS_PREFIX=$(echo "$key_vault" | sed 's/kv-//')
            log "Found SaaS prefix: ${SAAS_PREFIX}"
        else
            warning "Could not determine SaaS prefix from existing resources"
            export SAAS_PREFIX="unknown"
        fi
    else
        warning "No control plane resource group found - some cleanup operations may not be possible"
        export RESOURCE_GROUP="rg-saas-control-plane"
        export SAAS_PREFIX="unknown"
    fi
    
    success "Environment variables determined"
}

# Function to confirm deletion
confirm_deletion() {
    if [[ "$FORCE" == "true" ]]; then
        log "Force mode enabled - skipping confirmation"
        return 0
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "Dry run mode - no confirmation needed"
        return 0
    fi
    
    warning "This will permanently delete all multi-tenant SaaS resources including:"
    echo "  - All tenant resource groups and their resources"
    echo "  - Control plane infrastructure"
    echo "  - Policy definitions"
    echo "  - RBAC role definitions"
    echo "  - Workload identity applications"
    echo "  - Monitoring resources"
    echo ""
    
    read -p "Are you sure you want to proceed? (type 'yes' to confirm): " confirmation
    
    if [[ "$confirmation" != "yes" ]]; then
        log "Cleanup cancelled by user"
        exit 0
    fi
    
    warning "Proceeding with resource deletion..."
}

# Function to remove tenant resources
remove_tenant_resources() {
    log "Removing tenant resources..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY RUN: Would remove tenant resources"
        return 0
    fi
    
    # Get list of tenant resource groups
    local tenant_groups=$(az group list --query "[?contains(name, 'rg-tenant-')].name" --output tsv)
    
    if [[ -z "$tenant_groups" ]]; then
        warning "No tenant resource groups found"
        return 0
    fi
    
    # Remove each tenant resource group
    while IFS= read -r group; do
        if [[ -n "$group" ]]; then
            log "Removing tenant resource group: $group"
            
            # Remove policy assignments first
            local tenant_id=$(echo "$group" | sed 's/rg-tenant-//')
            az policy assignment delete \
                --name "tenant-${tenant_id}-tagging" \
                --scope "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${group}" \
                2>/dev/null || warning "Policy assignment not found for tenant ${tenant_id}"
            
            # Delete the resource group
            az group delete \
                --name "$group" \
                --yes \
                --no-wait
            
            success "Initiated deletion of tenant resource group: $group"
        fi
    done <<< "$tenant_groups"
    
    success "Tenant resource deletion initiated"
}

# Function to remove workload identity
remove_workload_identity() {
    log "Removing workload identity..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY RUN: Would remove workload identity"
        return 0
    fi
    
    # Find workload identity application
    local workload_app_id=$(az ad app list --query "[?contains(displayName, 'SaaS-Tenant-Workload-${SAAS_PREFIX}')].appId" --output tsv)
    
    if [[ -n "$workload_app_id" ]]; then
        log "Removing workload identity application: $workload_app_id"
        az ad app delete --id "$workload_app_id"
        success "Workload identity application removed"
    else
        warning "Workload identity application not found"
    fi
}

# Function to remove policy definitions
remove_policy_definitions() {
    log "Removing policy definitions..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY RUN: Would remove policy definitions"
        return 0
    fi
    
    # Remove custom policy definitions
    local policies=("require-tenant-tags" "require-network-security-groups")
    
    for policy in "${policies[@]}"; do
        if az policy definition show --name "$policy" &> /dev/null; then
            log "Removing policy definition: $policy"
            az policy definition delete --name "$policy"
            success "Policy definition removed: $policy"
        else
            warning "Policy definition not found: $policy"
        fi
    done
    
    success "Policy definitions cleanup completed"
}

# Function to remove RBAC roles
remove_rbac_roles() {
    log "Removing custom RBAC roles..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY RUN: Would remove custom RBAC roles"
        return 0
    fi
    
    # Remove custom RBAC roles
    local roles=("Tenant Administrator" "Tenant User")
    
    for role in "${roles[@]}"; do
        local role_id=$(az role definition list --name "$role" --query "[0].id" --output tsv 2>/dev/null)
        if [[ -n "$role_id" ]]; then
            log "Removing RBAC role: $role"
            az role definition delete --name "$role"
            success "RBAC role removed: $role"
        else
            warning "RBAC role not found: $role"
        fi
    done
    
    success "RBAC roles cleanup completed"
}

# Function to remove control plane resources
remove_control_plane() {
    log "Removing control plane resources..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY RUN: Would remove control plane resource group"
        return 0
    fi
    
    # Check if control plane resource group exists
    if az group show --name "${RESOURCE_GROUP}" &> /dev/null; then
        log "Removing control plane resource group: ${RESOURCE_GROUP}"
        az group delete \
            --name "${RESOURCE_GROUP}" \
            --yes \
            --no-wait
        success "Control plane resource group deletion initiated"
    else
        warning "Control plane resource group not found: ${RESOURCE_GROUP}"
    fi
}

# Function to wait for resource deletions
wait_for_deletions() {
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY RUN: Would wait for resource deletions"
        return 0
    fi
    
    log "Waiting for resource group deletions to complete..."
    
    # Get list of resource groups that are being deleted
    local deleting_groups=$(az group list --query "[?properties.provisioningState=='Deleting'].name" --output tsv)
    
    if [[ -n "$deleting_groups" ]]; then
        warning "The following resource groups are being deleted:"
        echo "$deleting_groups"
        
        # Wait for a reasonable amount of time
        local max_wait=600  # 10 minutes
        local wait_time=0
        
        while [[ $wait_time -lt $max_wait ]]; do
            local still_deleting=$(az group list --query "[?properties.provisioningState=='Deleting'].name" --output tsv)
            if [[ -z "$still_deleting" ]]; then
                success "All resource groups have been deleted"
                return 0
            fi
            
            log "Still waiting for resource group deletions... ($wait_time/$max_wait seconds)"
            sleep 30
            wait_time=$((wait_time + 30))
        done
        
        warning "Resource group deletions are taking longer than expected"
        warning "Please check the Azure portal to monitor deletion progress"
    else
        log "No resource groups are currently being deleted"
    fi
}

# Function to clean up local files
cleanup_local_files() {
    log "Cleaning up local files..."
    
    # Remove any temporary files that might have been created
    local temp_files=(
        "/tmp/tenant-stack-template.json"
        "/tmp/tenant-tagging-policy.json"
        "/tmp/network-isolation-policy.json"
        "/tmp/federated-credential.json"
        "/tmp/tenant-admin-role.json"
        "/tmp/tenant-user-role.json"
    )
    
    for file in "${temp_files[@]}"; do
        if [[ -f "$file" ]]; then
            rm -f "$file"
            log "Removed temporary file: $file"
        fi
    done
    
    success "Local files cleaned up"
}

# Function to validate cleanup
validate_cleanup() {
    log "Validating cleanup..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY RUN: Would validate cleanup"
        return 0
    fi
    
    # Check for remaining tenant resource groups
    local remaining_tenant_groups=$(az group list --query "[?contains(name, 'rg-tenant-')].name" --output tsv)
    if [[ -n "$remaining_tenant_groups" ]]; then
        warning "Some tenant resource groups may still exist (deletion in progress):"
        echo "$remaining_tenant_groups"
    fi
    
    # Check for remaining policy definitions
    local remaining_policies=$(az policy definition list --query "[?contains(displayName, 'Tenant')].displayName" --output tsv)
    if [[ -n "$remaining_policies" ]]; then
        warning "Some policy definitions may still exist:"
        echo "$remaining_policies"
    fi
    
    # Check for remaining RBAC roles
    local remaining_roles=$(az role definition list --query "[?contains(roleName, 'Tenant')].roleName" --output tsv)
    if [[ -n "$remaining_roles" ]]; then
        warning "Some RBAC roles may still exist:"
        echo "$remaining_roles"
    fi
    
    success "Cleanup validation completed"
}

# Function to display cleanup summary
display_summary() {
    log "Cleanup Summary"
    echo "====================="
    echo "Subscription ID: ${SUBSCRIPTION_ID}"
    echo "Control plane resource group: ${RESOURCE_GROUP}"
    echo "SaaS prefix: ${SAAS_PREFIX}"
    echo "====================="
    
    if [[ "$DRY_RUN" == "false" ]]; then
        success "Multi-tenant SaaS resource isolation cleanup completed!"
        warning "Some resources may still be in the process of being deleted."
        warning "Please check the Azure portal to confirm all resources have been removed."
        warning "Monitor your Azure subscription for any remaining resources that may incur charges."
    else
        success "Dry run completed - no resources were deleted"
        log "To perform actual cleanup, run: $0 --force"
    fi
}

# Main cleanup function
main() {
    log "Starting multi-tenant SaaS resource isolation cleanup..."
    
    check_prerequisites
    get_environment_variables
    confirm_deletion
    remove_tenant_resources
    remove_workload_identity
    remove_policy_definitions
    remove_rbac_roles
    remove_control_plane
    wait_for_deletions
    cleanup_local_files
    validate_cleanup
    display_summary
}

# Error handling
trap 'error "Cleanup failed. Some resources may not have been removed. Please check the Azure portal."' ERR

# Run main function
main "$@"