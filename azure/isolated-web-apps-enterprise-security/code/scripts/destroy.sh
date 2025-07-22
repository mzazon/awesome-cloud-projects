#!/bin/bash

# =============================================================================
# Azure App Service Environment v3 Enterprise Cleanup Script
# =============================================================================
# This script safely removes all resources deployed by the deploy.sh script
# including Azure App Service Environment v3, Private DNS, NAT Gateway, and
# supporting infrastructure components.
#
# WARNING: This script will permanently delete all resources.
# Ensure you have backed up any important data before running.
#
# Estimated cleanup time: 60-90 minutes (primarily ASE deletion)
# =============================================================================

set -euo pipefail

# Color codes for output formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

# Error handling
error_exit() {
    log_error "$1"
    exit 1
}

# Function to check if resource exists
resource_exists() {
    local resource_type="$1"
    local resource_name="$2"
    local resource_group="$3"
    
    case "$resource_type" in
        "webapp")
            az webapp show --name "$resource_name" --resource-group "$resource_group" &> /dev/null
            ;;
        "asp")
            az appservice plan show --name "$resource_name" --resource-group "$resource_group" &> /dev/null
            ;;
        "ase")
            az appservice ase show --name "$resource_name" --resource-group "$resource_group" &> /dev/null
            ;;
        "vm")
            az vm show --name "$resource_name" --resource-group "$resource_group" &> /dev/null
            ;;
        "bastion")
            az network bastion show --name "$resource_name" --resource-group "$resource_group" &> /dev/null
            ;;
        "nat-gateway")
            az network nat gateway show --name "$resource_name" --resource-group "$resource_group" &> /dev/null
            ;;
        "public-ip")
            az network public-ip show --name "$resource_name" --resource-group "$resource_group" &> /dev/null
            ;;
        "private-dns")
            az network private-dns zone show --name "$resource_name" --resource-group "$resource_group" &> /dev/null
            ;;
        "vnet")
            az network vnet show --name "$resource_name" --resource-group "$resource_group" &> /dev/null
            ;;
        "resource-group")
            az group show --name "$resource_name" &> /dev/null
            ;;
        *)
            return 1
            ;;
    esac
}

# Function to wait for resource deletion
wait_for_deletion() {
    local resource_type="$1"
    local resource_name="$2"
    local resource_group="$3"
    local timeout="${4:-300}"  # Default 5 minutes
    
    local start_time=$(date +%s)
    local check_interval=30
    
    log_info "Waiting for $resource_type '$resource_name' to be deleted..."
    
    while resource_exists "$resource_type" "$resource_name" "$resource_group"; do
        local current_time=$(date +%s)
        local elapsed_time=$((current_time - start_time))
        
        if [[ $elapsed_time -gt $timeout ]]; then
            log_warning "$resource_type '$resource_name' deletion timed out after $timeout seconds"
            return 1
        fi
        
        local elapsed_minutes=$((elapsed_time / 60))
        log_info "Still waiting for $resource_type deletion... (${elapsed_minutes} minutes elapsed)"
        sleep $check_interval
    done
    
    log_success "$resource_type '$resource_name' has been deleted"
}

# =============================================================================
# PREREQUISITE CHECKS
# =============================================================================

log_info "Starting cleanup prerequisite checks..."

# Check if Azure CLI is installed
if ! command -v az &> /dev/null; then
    error_exit "Azure CLI is not installed. Please install Azure CLI to run this script."
fi

# Check if user is logged in
if ! az account show &> /dev/null; then
    error_exit "Not logged in to Azure. Please run 'az login' first."
fi

# Get subscription information
SUBSCRIPTION_ID=$(az account show --query id --output tsv)
SUBSCRIPTION_NAME=$(az account show --query name --output tsv)
log_info "Using subscription: ${SUBSCRIPTION_NAME} (${SUBSCRIPTION_ID})"

# =============================================================================
# RESOURCE GROUP DISCOVERY
# =============================================================================

log_info "Discovering resource groups to cleanup..."

# If resource group name is provided as argument, use it
if [[ $# -gt 0 ]]; then
    RESOURCE_GROUP="$1"
    log_info "Using provided resource group: ${RESOURCE_GROUP}"
else
    # Find resource groups with our naming pattern
    log_info "Searching for enterprise ASE resource groups..."
    
    # List all resource groups matching our pattern
    RESOURCE_GROUPS=$(az group list --query "[?starts_with(name, 'rg-ase-enterprise-')].name" --output tsv)
    
    if [[ -z "$RESOURCE_GROUPS" ]]; then
        log_info "No enterprise ASE resource groups found. Nothing to cleanup."
        exit 0
    fi
    
    log_info "Found the following resource groups:"
    echo "$RESOURCE_GROUPS" | nl
    
    # If multiple groups found, ask user to choose
    if [[ $(echo "$RESOURCE_GROUPS" | wc -l) -gt 1 ]]; then
        echo
        read -p "Enter the number of the resource group to delete (or 'all' to delete all): " choice
        
        if [[ "$choice" == "all" ]]; then
            log_warning "Will delete ALL enterprise ASE resource groups!"
        else
            RESOURCE_GROUP=$(echo "$RESOURCE_GROUPS" | sed -n "${choice}p")
            if [[ -z "$RESOURCE_GROUP" ]]; then
                error_exit "Invalid selection."
            fi
        fi
    else
        RESOURCE_GROUP="$RESOURCE_GROUPS"
    fi
fi

# =============================================================================
# SAFETY CONFIRMATION
# =============================================================================

log_warning "=== DANGER: DESTRUCTIVE OPERATION ==="
log_warning "This script will permanently delete the following:"
log_warning "- Azure App Service Environment v3 (expensive resource)"
log_warning "- All web applications and app service plans"
log_warning "- Virtual machines and Azure Bastion"
log_warning "- Virtual networks and subnets"
log_warning "- NAT Gateway and public IP addresses"
log_warning "- Private DNS zones and records"
log_warning "- All associated storage and configuration"

if [[ "$choice" == "all" ]]; then
    log_warning "Resource groups to delete: ALL enterprise ASE groups"
    echo "$RESOURCE_GROUPS"
else
    log_warning "Resource group to delete: ${RESOURCE_GROUP}"
fi

echo
read -p "Are you absolutely sure you want to proceed? Type 'DELETE' to confirm: " confirm

if [[ "$confirm" != "DELETE" ]]; then
    log_info "Cleanup cancelled by user."
    exit 0
fi

log_info "Cleanup confirmed. Starting resource deletion..."

# =============================================================================
# CLEANUP FUNCTION FOR SINGLE RESOURCE GROUP
# =============================================================================

cleanup_resource_group() {
    local rg_name="$1"
    
    log_info "=== Starting cleanup for resource group: ${rg_name} ==="
    
    # Check if resource group exists
    if ! resource_exists "resource-group" "$rg_name" ""; then
        log_warning "Resource group ${rg_name} does not exist. Skipping..."
        return 0
    fi
    
    # Extract resource names from the resource group
    local random_suffix="${rg_name#rg-ase-enterprise-}"
    local ase_name="ase-enterprise-${random_suffix}"
    local app_service_plan_name="asp-enterprise-${random_suffix}"
    local web_app_name="webapp-enterprise-${random_suffix}"
    local management_vm_name="vm-management-${random_suffix}"
    local bastion_name="bastion-${random_suffix}"
    local nat_gateway_name="nat-gateway-${random_suffix}"
    local public_ip_name="pip-nat-${random_suffix}"
    local bastion_pip_name="pip-bastion-${random_suffix}"
    local private_dns_zone="enterprise.internal"
    local vnet_name="vnet-ase-enterprise-${random_suffix}"
    
    # =============================================================================
    # PHASE 1: DELETE WEB APPLICATIONS AND APP SERVICE PLANS
    # =============================================================================
    
    log_info "Phase 1: Removing web applications and app service plans..."
    
    # Delete web application
    if resource_exists "webapp" "$web_app_name" "$rg_name"; then
        log_info "Deleting web application: ${web_app_name}"
        az webapp delete \
            --name "$web_app_name" \
            --resource-group "$rg_name" \
            --yes \
            --output none
        log_success "Web application deleted: ${web_app_name}"
    else
        log_info "Web application ${web_app_name} not found, skipping..."
    fi
    
    # Delete App Service Plan
    if resource_exists "asp" "$app_service_plan_name" "$rg_name"; then
        log_info "Deleting App Service Plan: ${app_service_plan_name}"
        az appservice plan delete \
            --name "$app_service_plan_name" \
            --resource-group "$rg_name" \
            --yes \
            --output none
        log_success "App Service Plan deleted: ${app_service_plan_name}"
    else
        log_info "App Service Plan ${app_service_plan_name} not found, skipping..."
    fi
    
    # =============================================================================
    # PHASE 2: DELETE APP SERVICE ENVIRONMENT (TAKES LONGEST)
    # =============================================================================
    
    log_info "Phase 2: Removing App Service Environment (this will take 60-90 minutes)..."
    
    if resource_exists "ase" "$ase_name" "$rg_name"; then
        log_info "Deleting App Service Environment: ${ase_name}"
        log_warning "This operation will take 60-90 minutes to complete..."
        
        az appservice ase delete \
            --name "$ase_name" \
            --resource-group "$rg_name" \
            --yes \
            --output none
        
        log_success "App Service Environment deletion initiated: ${ase_name}"
        log_info "ASE deletion is running in the background. Continuing with other resources..."
    else
        log_info "App Service Environment ${ase_name} not found, skipping..."
    fi
    
    # =============================================================================
    # PHASE 3: DELETE VIRTUAL MACHINES AND AZURE BASTION
    # =============================================================================
    
    log_info "Phase 3: Removing virtual machines and Azure Bastion..."
    
    # Delete management VM
    if resource_exists "vm" "$management_vm_name" "$rg_name"; then
        log_info "Deleting management VM: ${management_vm_name}"
        az vm delete \
            --name "$management_vm_name" \
            --resource-group "$rg_name" \
            --yes \
            --output none
        log_success "Management VM deleted: ${management_vm_name}"
    else
        log_info "Management VM ${management_vm_name} not found, skipping..."
    fi
    
    # Delete Azure Bastion
    if resource_exists "bastion" "$bastion_name" "$rg_name"; then
        log_info "Deleting Azure Bastion: ${bastion_name}"
        az network bastion delete \
            --name "$bastion_name" \
            --resource-group "$rg_name" \
            --output none
        log_success "Azure Bastion deleted: ${bastion_name}"
    else
        log_info "Azure Bastion ${bastion_name} not found, skipping..."
    fi
    
    # =============================================================================
    # PHASE 4: DELETE NETWORK INFRASTRUCTURE
    # =============================================================================
    
    log_info "Phase 4: Removing network infrastructure..."
    
    # Delete NAT Gateway
    if resource_exists "nat-gateway" "$nat_gateway_name" "$rg_name"; then
        log_info "Deleting NAT Gateway: ${nat_gateway_name}"
        az network nat gateway delete \
            --name "$nat_gateway_name" \
            --resource-group "$rg_name" \
            --output none
        log_success "NAT Gateway deleted: ${nat_gateway_name}"
    else
        log_info "NAT Gateway ${nat_gateway_name} not found, skipping..."
    fi
    
    # Delete public IP addresses
    for pip_name in "$public_ip_name" "$bastion_pip_name"; do
        if resource_exists "public-ip" "$pip_name" "$rg_name"; then
            log_info "Deleting public IP: ${pip_name}"
            az network public-ip delete \
                --name "$pip_name" \
                --resource-group "$rg_name" \
                --output none
            log_success "Public IP deleted: ${pip_name}"
        else
            log_info "Public IP ${pip_name} not found, skipping..."
        fi
    done
    
    # Delete private DNS zone
    if resource_exists "private-dns" "$private_dns_zone" "$rg_name"; then
        log_info "Deleting private DNS zone: ${private_dns_zone}"
        az network private-dns zone delete \
            --name "$private_dns_zone" \
            --resource-group "$rg_name" \
            --yes \
            --output none
        log_success "Private DNS zone deleted: ${private_dns_zone}"
    else
        log_info "Private DNS zone ${private_dns_zone} not found, skipping..."
    fi
    
    # =============================================================================
    # PHASE 5: WAIT FOR ASE DELETION BEFORE DELETING RESOURCE GROUP
    # =============================================================================
    
    log_info "Phase 5: Waiting for App Service Environment deletion to complete..."
    
    if resource_exists "ase" "$ase_name" "$rg_name"; then
        log_info "Waiting for App Service Environment deletion to complete..."
        log_warning "This may take up to 90 minutes. Please be patient..."
        
        # Wait for ASE deletion with extended timeout
        if ! wait_for_deletion "ase" "$ase_name" "$rg_name" 5400; then  # 90 minutes
            log_warning "ASE deletion timeout reached. Proceeding with resource group deletion..."
            log_warning "The resource group deletion will wait for ASE deletion to complete."
        fi
    fi
    
    # =============================================================================
    # PHASE 6: DELETE RESOURCE GROUP
    # =============================================================================
    
    log_info "Phase 6: Deleting resource group (this will wait for all resources)..."
    
    log_info "Deleting resource group: ${rg_name}"
    log_warning "This will wait for all remaining resources to be deleted..."
    
    az group delete \
        --name "$rg_name" \
        --yes \
        --no-wait \
        --output none
    
    log_success "Resource group deletion initiated: ${rg_name}"
    log_info "Resource group deletion is running in the background"
    
    # Optionally wait for resource group deletion
    read -p "Wait for resource group deletion to complete? (y/N): " wait_choice
    if [[ "$wait_choice" =~ ^[Yy]$ ]]; then
        log_info "Waiting for resource group deletion to complete..."
        wait_for_deletion "resource-group" "$rg_name" "" 7200  # 2 hours
    fi
    
    log_success "Cleanup completed for resource group: ${rg_name}"
}

# =============================================================================
# MAIN CLEANUP EXECUTION
# =============================================================================

if [[ "$choice" == "all" ]]; then
    # Delete all resource groups
    while IFS= read -r rg; do
        cleanup_resource_group "$rg"
        echo
    done <<< "$RESOURCE_GROUPS"
else
    # Delete single resource group
    cleanup_resource_group "$RESOURCE_GROUP"
fi

# =============================================================================
# CLEANUP SUMMARY
# =============================================================================

log_success "=== CLEANUP COMPLETED ==="
log_info "Summary of actions taken:"
log_info "✅ Web applications and app service plans deleted"
log_info "✅ App Service Environment deletion initiated (background process)"
log_info "✅ Virtual machines and Azure Bastion deleted"
log_info "✅ Network infrastructure deleted"
log_info "✅ Private DNS zones deleted"
log_info "✅ Resource group deletion initiated"

log_info ""
log_info "Important Notes:"
log_info "- App Service Environment deletion may take up to 90 minutes"
log_info "- Resource group deletion will wait for all resources to be removed"
log_info "- You can monitor progress in the Azure portal"
log_info "- Billing will stop once all resources are fully deleted"

log_info ""
log_info "To verify cleanup completion, run:"
log_info "az group list --query \"[?starts_with(name, 'rg-ase-enterprise-')].name\" --output table"

log_success "Cleanup script completed successfully!"