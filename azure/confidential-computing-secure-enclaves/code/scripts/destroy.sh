#!/bin/bash

#######################################################################
# Azure Confidential Computing with Secure Enclaves - Cleanup Script
# Recipe: Confidential Computing with Hardware-Protected Enclaves
# 
# This script safely removes all confidential computing resources including:
# - Confidential Virtual Machine and associated resources
# - Azure Managed HSM (with secure purge)
# - Azure Attestation Provider
# - Azure Key Vault Premium
# - Azure Storage Account
# - Managed identities and role assignments
# - Resource group (optional)
# - Local backup files
#
# Prerequisites:
# - Azure CLI v2.40.0 or later
# - Contributor or Owner role on subscription
# - Access to the same subscription used for deployment
#
# Estimated cleanup time: 10-15 minutes
#######################################################################

set -euo pipefail

# Script configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly RECIPE_NAME="confidential-computing-secure-enclaves"
readonly AZURE_CLI_MIN_VERSION="2.40.0"

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m' # No Color

# Global variables
CLEANUP_START_TIME=""
RESOURCE_GROUP=""
LOCATION=""
SUBSCRIPTION_ID=""
TENANT_ID=""
CLEANUP_ERRORS=0
DRY_RUN=false
FORCE_DELETE=false
KEEP_BACKUP_FILES=false

# Logging functions
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a "${SCRIPT_DIR}/destroy.log"
}

success() {
    echo -e "${GREEN}✅ $1${NC}" | tee -a "${SCRIPT_DIR}/destroy.log"
}

warning() {
    echo -e "${YELLOW}⚠️  $1${NC}" | tee -a "${SCRIPT_DIR}/destroy.log"
}

error() {
    echo -e "${RED}❌ $1${NC}" | tee -a "${SCRIPT_DIR}/destroy.log"
    ((CLEANUP_ERRORS++))
}

info() {
    echo -e "${CYAN}ℹ️  $1${NC}" | tee -a "${SCRIPT_DIR}/destroy.log"
}

# Progress tracking
show_progress() {
    local current=$1
    local total=$2
    local message=$3
    local progress=$((current * 100 / total))
    echo -e "${CYAN}[${progress}%] Step ${current}/${total}: ${message}${NC}"
}

# Usage information
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

OPTIONS:
    -h, --help              Show this help message
    -d, --dry-run           Show what would be deleted without actually deleting
    -f, --force             Skip confirmation prompts (use with caution)
    -k, --keep-backups      Keep HSM backup files after cleanup
    -r, --resource-group    Specify resource group to clean up
    -l, --location          Specify location (required for HSM purge)

EXAMPLES:
    $0                                    # Interactive cleanup
    $0 --dry-run                         # Show what would be deleted
    $0 --force                           # Skip confirmations
    $0 --resource-group "my-rg"          # Clean up specific resource group
    $0 --dry-run --resource-group "rg"   # Dry run for specific resource group

EOF
}

# Parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                usage
                exit 0
                ;;
            -d|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -f|--force)
                FORCE_DELETE=true
                shift
                ;;
            -k|--keep-backups)
                KEEP_BACKUP_FILES=true
                shift
                ;;
            -r|--resource-group)
                RESOURCE_GROUP="$2"
                shift 2
                ;;
            -l|--location)
                LOCATION="$2"
                shift 2
                ;;
            *)
                error "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done
}

# Check if running in Azure Cloud Shell or local environment
check_environment() {
    show_progress 1 10 "Checking cleanup environment"
    
    if [[ -n "${AZURE_HTTP_USER_AGENT:-}" ]]; then
        info "Running in Azure Cloud Shell"
    else
        info "Running in local environment"
    fi
    
    # Check Azure CLI version
    local az_version=$(az version --query '"azure-cli"' -o tsv 2>/dev/null || echo "not-installed")
    if [[ "$az_version" == "not-installed" ]]; then
        error "Azure CLI is not installed. Please install Azure CLI v${AZURE_CLI_MIN_VERSION} or later."
        exit 1
    fi
    
    # Version comparison (simplified)
    local version_major=$(echo "$az_version" | cut -d. -f1)
    local version_minor=$(echo "$az_version" | cut -d. -f2)
    if [[ "$version_major" -lt 2 ]] || [[ "$version_major" -eq 2 && "$version_minor" -lt 40 ]]; then
        error "Azure CLI version $az_version is too old. Please upgrade to v${AZURE_CLI_MIN_VERSION} or later."
        exit 1
    fi
    
    info "Azure CLI version: $az_version"
    success "Environment check completed"
}

# Check prerequisites and permissions
check_prerequisites() {
    show_progress 2 10 "Checking prerequisites and permissions"
    
    # Check if logged in to Azure
    if ! az account show &>/dev/null; then
        error "Not logged in to Azure. Please run 'az login' first."
        exit 1
    fi
    
    # Get current subscription info
    SUBSCRIPTION_ID=$(az account show --query id --output tsv)
    TENANT_ID=$(az account show --query tenantId --output tsv)
    local account_name=$(az account show --query user.name --output tsv)
    
    info "Subscription ID: $SUBSCRIPTION_ID"
    info "Tenant ID: $TENANT_ID"
    info "Account: $account_name"
    
    # Check if user has sufficient permissions
    local user_id=$(az ad signed-in-user show --query id --output tsv 2>/dev/null || echo "")
    if [[ -z "$user_id" ]]; then
        warning "Could not verify user permissions. Proceeding with cleanup..."
    else
        info "User ID: $user_id"
        
        # Check role assignments
        local roles=$(az role assignment list --assignee "$user_id" --query "[].roleDefinitionName" --output tsv 2>/dev/null || echo "")
        if [[ "$roles" == *"Owner"* ]] || [[ "$roles" == *"Contributor"* ]]; then
            info "User has sufficient permissions for cleanup"
        else
            warning "User may not have sufficient permissions. Ensure you have Contributor or Owner role."
        fi
    fi
    
    success "Prerequisites check completed"
}

# Discover resources to cleanup
discover_resources() {
    show_progress 3 10 "Discovering resources to cleanup"
    
    # If resource group is provided, use it; otherwise try to discover
    if [[ -z "$RESOURCE_GROUP" ]]; then
        log "No resource group specified. Searching for confidential computing resources..."
        
        # Look for resource groups with confidential computing tags
        local rg_candidates=$(az group list \
            --query "[?tags.purpose=='confidential-computing' || tags.recipe=='$RECIPE_NAME'].name" \
            --output tsv 2>/dev/null || echo "")
        
        if [[ -n "$rg_candidates" ]]; then
            log "Found potential resource groups:"
            echo "$rg_candidates" | while read -r rg; do
                info "  - $rg"
            done
            
            # Use the first one found, or ask user to choose
            if [[ $(echo "$rg_candidates" | wc -l) -eq 1 ]]; then
                RESOURCE_GROUP="$rg_candidates"
                log "Using resource group: $RESOURCE_GROUP"
            else
                if [[ "$FORCE_DELETE" == false ]]; then
                    echo
                    echo "Multiple resource groups found. Please choose:"
                    local i=1
                    declare -a rg_array
                    while read -r rg; do
                        echo "  $i) $rg"
                        rg_array[$i]="$rg"
                        ((i++))
                    done <<< "$rg_candidates"
                    
                    echo -n "Enter choice (1-$((i-1))): "
                    read -r choice
                    
                    if [[ "$choice" -ge 1 && "$choice" -lt "$i" ]]; then
                        RESOURCE_GROUP="${rg_array[$choice]}"
                        log "Selected resource group: $RESOURCE_GROUP"
                    else
                        error "Invalid choice. Please specify resource group with -r option."
                        exit 1
                    fi
                else
                    error "Multiple resource groups found. Please specify with -r option."
                    exit 1
                fi
            fi
        else
            error "No confidential computing resource groups found."
            error "Please specify the resource group with -r option."
            exit 1
        fi
    fi
    
    # Verify resource group exists
    if ! az group show --name "$RESOURCE_GROUP" &>/dev/null; then
        error "Resource group '$RESOURCE_GROUP' not found or not accessible."
        exit 1
    fi
    
    log "Target resource group: $RESOURCE_GROUP"
    
    # Get location from resource group if not specified
    if [[ -z "$LOCATION" ]]; then
        LOCATION=$(az group show --name "$RESOURCE_GROUP" --query location --output tsv)
        info "Location: $LOCATION"
    fi
    
    success "Resource discovery completed"
}

# List all resources before deletion
list_resources() {
    show_progress 4 10 "Listing resources for cleanup"
    
    echo
    echo "Resources in resource group '$RESOURCE_GROUP':"
    echo "============================================="
    
    # Get comprehensive resource list
    local resources=$(az resource list \
        --resource-group "$RESOURCE_GROUP" \
        --query "[].{Name:name, Type:type, Location:location, Tags:tags}" \
        --output table)
    
    if [[ -n "$resources" ]]; then
        echo "$resources"
    else
        warning "No resources found in resource group"
        return 0
    fi
    
    echo
    
    # Count resources by type
    local resource_count=$(az resource list --resource-group "$RESOURCE_GROUP" --query "length(@)" --output tsv)
    local vm_count=$(az vm list --resource-group "$RESOURCE_GROUP" --query "length(@)" --output tsv)
    local hsm_count=$(az keyvault list --resource-group "$RESOURCE_GROUP" --resource-type hsm --query "length(@)" --output tsv 2>/dev/null || echo "0")
    local kv_count=$(az keyvault list --resource-group "$RESOURCE_GROUP" --query "length([?properties.vaultUri != null])" --output tsv 2>/dev/null || echo "0")
    local storage_count=$(az storage account list --resource-group "$RESOURCE_GROUP" --query "length(@)" --output tsv)
    local attestation_count=$(az attestation list --resource-group "$RESOURCE_GROUP" --query "length(@)" --output tsv 2>/dev/null || echo "0")
    
    echo "📊 RESOURCE SUMMARY:"
    echo "  Total resources:      $resource_count"
    echo "  Virtual Machines:     $vm_count"
    echo "  Managed HSMs:         $hsm_count"
    echo "  Key Vaults:           $kv_count"
    echo "  Storage Accounts:     $storage_count"
    echo "  Attestation Providers: $attestation_count"
    echo
    
    # Estimate cleanup time
    local estimated_time=5
    if [[ "$hsm_count" -gt 0 ]]; then
        estimated_time=$((estimated_time + 5))
    fi
    if [[ "$vm_count" -gt 0 ]]; then
        estimated_time=$((estimated_time + 3))
    fi
    
    info "Estimated cleanup time: $estimated_time minutes"
    
    success "Resource listing completed"
}

# Confirm deletion with user
confirm_deletion() {
    if [[ "$DRY_RUN" == true ]]; then
        echo
        info "DRY RUN: The following resources would be deleted:"
        echo "=================================================="
        az resource list --resource-group "$RESOURCE_GROUP" --query "[].{Name:name, Type:type}" --output table
        echo
        info "No actual resources will be deleted in dry run mode."
        return 0
    fi
    
    if [[ "$FORCE_DELETE" == true ]]; then
        warning "Force delete mode enabled - skipping confirmation"
        return 0
    fi
    
    echo
    warning "⚠️  DESTRUCTIVE OPERATION WARNING ⚠️"
    echo
    echo "This script will permanently delete the following:"
    echo "- All resources in resource group: $RESOURCE_GROUP"
    echo "- Managed HSM data (with PURGE - cannot be recovered)"
    echo "- Confidential VM and all data"
    echo "- Storage accounts and all data"
    echo "- Key Vault and all keys/secrets"
    echo "- All role assignments and managed identities"
    echo "- Security domain backup files (unless --keep-backups is used)"
    echo
    warning "This action cannot be undone!"
    echo
    
    # Double confirmation for destructive operations
    local confirmation=""
    local final_confirmation=""
    
    while [[ "$confirmation" != "DELETE" ]]; do
        echo -n "Are you sure you want to continue? Type 'DELETE' to confirm: "
        read -r confirmation
        if [[ "$confirmation" != "DELETE" ]]; then
            echo "Please type 'DELETE' exactly to confirm, or Ctrl+C to cancel."
        fi
    done
    
    while [[ "$final_confirmation" != "YES" ]]; do
        echo -n "Final confirmation - Type 'YES' to proceed with deletion: "
        read -r final_confirmation
        if [[ "$final_confirmation" != "YES" ]]; then
            echo "Please type 'YES' exactly to confirm, or Ctrl+C to cancel."
        fi
    done
    
    log "User confirmed deletion. Proceeding with cleanup..."
}

# Stop and deallocate VMs
stop_virtual_machines() {
    show_progress 5 10 "Stopping virtual machines"
    
    local vms=$(az vm list \
        --resource-group "$RESOURCE_GROUP" \
        --query "[].name" \
        --output tsv)
    
    if [[ -n "$vms" ]]; then
        info "Found VMs to stop: $vms"
        
        for vm in $vms; do
            if [[ "$DRY_RUN" == true ]]; then
                info "[DRY RUN] Would stop VM: $vm"
                continue
            fi
            
            log "Stopping VM: $vm"
            if az vm deallocate \
                --resource-group "$RESOURCE_GROUP" \
                --name "$vm" \
                --no-wait; then
                success "VM '$vm' stop initiated"
            else
                error "Failed to stop VM '$vm'"
            fi
        done
        
        if [[ "$DRY_RUN" == false ]]; then
            # Wait for VMs to stop
            info "Waiting for VMs to stop..."
            for vm in $vms; do
                local max_attempts=30
                local attempts=0
                
                while [[ $attempts -lt $max_attempts ]]; do
                    local power_state=$(az vm show \
                        --resource-group "$RESOURCE_GROUP" \
                        --name "$vm" \
                        --show-details \
                        --query powerState \
                        --output tsv 2>/dev/null || echo "VM deallocated")
                    
                    if [[ "$power_state" == "VM deallocated" ]] || [[ "$power_state" == "VM stopped" ]]; then
                        success "VM '$vm' stopped"
                        break
                    else
                        info "VM '$vm' power state: $power_state (waiting...)"
                        sleep 10
                        ((attempts++))
                    fi
                done
                
                if [[ $attempts -eq $max_attempts ]]; then
                    warning "VM '$vm' did not stop within expected time"
                fi
            done
        fi
    else
        info "No VMs found to stop"
    fi
}

# Delete Managed HSM with secure purge
delete_managed_hsm() {
    show_progress 6 10 "Deleting Managed HSM"
    
    local hsms=$(az keyvault list \
        --resource-group "$RESOURCE_GROUP" \
        --resource-type hsm \
        --query "[].name" \
        --output tsv 2>/dev/null || echo "")
    
    if [[ -n "$hsms" ]]; then
        info "Found Managed HSMs to delete: $hsms"
        
        for hsm in $hsms; do
            if [[ "$DRY_RUN" == true ]]; then
                info "[DRY RUN] Would delete and purge HSM: $hsm"
                continue
            fi
            
            log "Soft deleting HSM: $hsm"
            if az keyvault delete --hsm-name "$hsm"; then
                success "HSM '$hsm' soft deleted"
            else
                error "Failed to soft delete HSM '$hsm'"
                continue
            fi
            
            log "Purging HSM: $hsm (permanent deletion)"
            if az keyvault purge \
                --hsm-name "$hsm" \
                --location "$LOCATION"; then
                success "HSM '$hsm' purged permanently"
            else
                error "Failed to purge HSM '$hsm'"
            fi
        done
    else
        info "No Managed HSMs found to delete"
    fi
}

# Delete Key Vaults
delete_key_vaults() {
    show_progress 7 10 "Deleting Key Vaults"
    
    local kvs=$(az keyvault list \
        --resource-group "$RESOURCE_GROUP" \
        --query "[?properties.vaultUri != null].name" \
        --output tsv 2>/dev/null || echo "")
    
    if [[ -n "$kvs" ]]; then
        info "Found Key Vaults to delete: $kvs"
        
        for kv in $kvs; do
            if [[ "$DRY_RUN" == true ]]; then
                info "[DRY RUN] Would delete and purge Key Vault: $kv"
                continue
            fi
            
            log "Soft deleting Key Vault: $kv"
            if az keyvault delete --name "$kv"; then
                success "Key Vault '$kv' soft deleted"
            else
                error "Failed to soft delete Key Vault '$kv'"
                continue
            fi
            
            log "Purging Key Vault: $kv (permanent deletion)"
            if az keyvault purge \
                --name "$kv" \
                --location "$LOCATION"; then
                success "Key Vault '$kv' purged permanently"
            else
                error "Failed to purge Key Vault '$kv'"
            fi
        done
    else
        info "No Key Vaults found to delete"
    fi
}

# Delete remaining resources
delete_remaining_resources() {
    show_progress 8 10 "Deleting remaining resources"
    
    # Delete Attestation Providers
    local attestation_providers=$(az attestation list \
        --resource-group "$RESOURCE_GROUP" \
        --query "[].name" \
        --output tsv 2>/dev/null || echo "")
    
    if [[ -n "$attestation_providers" ]]; then
        info "Found Attestation Providers to delete: $attestation_providers"
        
        for provider in $attestation_providers; do
            if [[ "$DRY_RUN" == true ]]; then
                info "[DRY RUN] Would delete attestation provider: $provider"
                continue
            fi
            
            log "Deleting attestation provider: $provider"
            if az attestation delete \
                --name "$provider" \
                --resource-group "$RESOURCE_GROUP" \
                --yes; then
                success "Attestation provider '$provider' deleted"
            else
                error "Failed to delete attestation provider '$provider'"
            fi
        done
    fi
    
    # Delete Storage Accounts
    local storage_accounts=$(az storage account list \
        --resource-group "$RESOURCE_GROUP" \
        --query "[].name" \
        --output tsv 2>/dev/null || echo "")
    
    if [[ -n "$storage_accounts" ]]; then
        info "Found Storage Accounts to delete: $storage_accounts"
        
        for storage in $storage_accounts; do
            if [[ "$DRY_RUN" == true ]]; then
                info "[DRY RUN] Would delete storage account: $storage"
                continue
            fi
            
            log "Deleting storage account: $storage"
            if az storage account delete \
                --name "$storage" \
                --resource-group "$RESOURCE_GROUP" \
                --yes; then
                success "Storage account '$storage' deleted"
            else
                error "Failed to delete storage account '$storage'"
            fi
        done
    fi
    
    # Delete Managed Identities
    local identities=$(az identity list \
        --resource-group "$RESOURCE_GROUP" \
        --query "[].name" \
        --output tsv 2>/dev/null || echo "")
    
    if [[ -n "$identities" ]]; then
        info "Found Managed Identities to delete: $identities"
        
        for identity in $identities; do
            if [[ "$DRY_RUN" == true ]]; then
                info "[DRY RUN] Would delete managed identity: $identity"
                continue
            fi
            
            log "Deleting managed identity: $identity"
            if az identity delete \
                --name "$identity" \
                --resource-group "$RESOURCE_GROUP"; then
                success "Managed identity '$identity' deleted"
            else
                error "Failed to delete identity '$identity'"
            fi
        done
    fi
    
    # Delete VMs and associated resources
    local vms=$(az vm list \
        --resource-group "$RESOURCE_GROUP" \
        --query "[].name" \
        --output tsv)
    
    if [[ -n "$vms" ]]; then
        info "Found VMs to delete: $vms"
        
        for vm in $vms; do
            if [[ "$DRY_RUN" == true ]]; then
                info "[DRY RUN] Would delete VM and associated resources: $vm"
                continue
            fi
            
            log "Deleting VM and associated resources: $vm"
            if az vm delete \
                --resource-group "$RESOURCE_GROUP" \
                --name "$vm" \
                --yes \
                --force-deletion true; then
                success "VM '$vm' and associated resources deleted"
            else
                error "Failed to delete VM '$vm'"
            fi
        done
    fi
    
    # Clean up any remaining resources
    local remaining_resources=$(az resource list \
        --resource-group "$RESOURCE_GROUP" \
        --query "[].{name:name, type:type}" \
        --output tsv 2>/dev/null || echo "")
    
    if [[ -n "$remaining_resources" ]]; then
        info "Cleaning up remaining resources..."
        
        while IFS=$'\t' read -r name type; do
            if [[ -n "$name" && -n "$type" ]]; then
                if [[ "$DRY_RUN" == true ]]; then
                    info "[DRY RUN] Would delete resource: $name (type: $type)"
                    continue
                fi
                
                log "Deleting resource: $name (type: $type)"
                if az resource delete \
                    --resource-group "$RESOURCE_GROUP" \
                    --name "$name" \
                    --resource-type "$type"; then
                    success "Resource '$name' deleted"
                else
                    error "Failed to delete resource '$name'"
                fi
            fi
        done <<< "$remaining_resources"
    fi
}

# Delete resource group
delete_resource_group() {
    show_progress 9 10 "Deleting resource group"
    
    if [[ "$DRY_RUN" == true ]]; then
        info "[DRY RUN] Would delete resource group: $RESOURCE_GROUP"
        return 0
    fi
    
    # Check if resource group still has resources
    local remaining_count=$(az resource list \
        --resource-group "$RESOURCE_GROUP" \
        --query "length(@)" \
        --output tsv 2>/dev/null || echo "0")
    
    if [[ "$remaining_count" -gt 0 ]]; then
        warning "Resource group still contains $remaining_count resources"
        
        if [[ "$FORCE_DELETE" == false ]]; then
            echo -n "Delete resource group anyway? (y/N): "
            read -r -n 1 reply
            echo
            if [[ ! $reply =~ ^[Yy]$ ]]; then
                log "Resource group deletion skipped"
                return 0
            fi
        fi
    fi
    
    # Final confirmation for resource group deletion
    if [[ "$FORCE_DELETE" == false ]]; then
        echo
        warning "Final step: Delete the entire resource group '$RESOURCE_GROUP'?"
        echo "This will remove any remaining resources and the resource group itself."
        echo -n "Delete resource group? (y/N): "
        read -r -n 1 reply
        echo
        
        if [[ ! $reply =~ ^[Yy]$ ]]; then
            log "Resource group deletion skipped"
            warning "Resource group '$RESOURCE_GROUP' still exists with any remaining resources"
            return 0
        fi
    fi
    
    log "Deleting resource group: $RESOURCE_GROUP"
    if az group delete \
        --name "$RESOURCE_GROUP" \
        --yes \
        --no-wait; then
        success "Resource group deletion initiated (running in background)"
        info "Full cleanup may take several minutes to complete"
    else
        error "Failed to delete resource group '$RESOURCE_GROUP'"
    fi
}

# Clean up local files
cleanup_local_files() {
    show_progress 10 10 "Cleaning up local files"
    
    if [[ "$KEEP_BACKUP_FILES" == true ]]; then
        info "Keeping backup files as requested"
        return 0
    fi
    
    local files_to_clean=(
        "${SCRIPT_DIR}/hsm-backup/"
        "${SCRIPT_DIR}/SecurityDomain.json"
        "${SCRIPT_DIR}/SecurityDomainExchangeKey.pem"
        "${SCRIPT_DIR}/attestation-policy.json"
        "${SCRIPT_DIR}/deploy-app.sh"
    )
    
    for file in "${files_to_clean[@]}"; do
        if [[ -e "$file" ]]; then
            if [[ "$DRY_RUN" == true ]]; then
                info "[DRY RUN] Would remove local file/directory: $file"
                continue
            fi
            
            log "Removing local file/directory: $file"
            if rm -rf "$file"; then
                success "File/directory '$file' removed"
            else
                error "Failed to remove '$file'"
            fi
        fi
    done
    
    if [[ "$DRY_RUN" == false ]]; then
        info "Local file cleanup completed"
    fi
}

# Validate cleanup
validate_cleanup() {
    if [[ "$DRY_RUN" == true ]]; then
        info "DRY RUN: Skipping cleanup validation"
        return 0
    fi
    
    echo
    info "🔍 Validating cleanup..."
    
    # Check if resource group still exists
    if az group show --name "$RESOURCE_GROUP" &>/dev/null; then
        local remaining_count=$(az resource list \
            --resource-group "$RESOURCE_GROUP" \
            --query "length(@)" \
            --output tsv 2>/dev/null || echo "0")
        
        if [[ "$remaining_count" -gt 0 ]]; then
            warning "Resource group still contains $remaining_count resources"
            echo "Remaining resources:"
            az resource list \
                --resource-group "$RESOURCE_GROUP" \
                --query "[].{Name:name, Type:type}" \
                --output table
        else
            success "Resource group is empty (deletion may still be in progress)"
        fi
    else
        success "Resource group has been deleted"
    fi
    
    # Check for soft-deleted resources that may need manual purging
    info "Checking for soft-deleted resources..."
    
    # Check for soft-deleted Key Vaults
    local soft_deleted_kvs=$(az keyvault list-deleted \
        --query "[?properties.location=='$LOCATION'].name" \
        --output tsv 2>/dev/null || echo "")
    
    if [[ -n "$soft_deleted_kvs" ]]; then
        info "Found soft-deleted Key Vaults (should be auto-purged):"
        echo "$soft_deleted_kvs"
    fi
    
    # Check for soft-deleted Managed HSMs
    local soft_deleted_hsms=$(az keyvault list-deleted \
        --resource-type hsm \
        --query "[?properties.location=='$LOCATION'].name" \
        --output tsv 2>/dev/null || echo "")
    
    if [[ -n "$soft_deleted_hsms" ]]; then
        info "Found soft-deleted Managed HSMs (should be auto-purged):"
        echo "$soft_deleted_hsms"
    fi
    
    success "Cleanup validation completed"
}

# Display cleanup summary
display_summary() {
    local cleanup_end_time=$(date +%s)
    local cleanup_duration=$((cleanup_end_time - CLEANUP_START_TIME))
    local duration_minutes=$((cleanup_duration / 60))
    local duration_seconds=$((cleanup_duration % 60))
    
    echo
    echo "========================================================================"
    if [[ "$DRY_RUN" == true ]]; then
        echo "🔍 AZURE CONFIDENTIAL COMPUTING CLEANUP - DRY RUN COMPLETED"
    else
        echo "🧹 AZURE CONFIDENTIAL COMPUTING CLEANUP COMPLETED"
    fi
    echo "========================================================================"
    echo
    echo "📋 CLEANUP SUMMARY:"
    echo "  Resource Group:      $RESOURCE_GROUP"
    echo "  Location:            $LOCATION"
    echo "  Cleanup Duration:    ${duration_minutes}m ${duration_seconds}s"
    echo "  Subscription:        $SUBSCRIPTION_ID"
    echo "  Errors Encountered:  $CLEANUP_ERRORS"
    echo
    
    if [[ "$DRY_RUN" == true ]]; then
        echo "🔍 DRY RUN RESULTS:"
        echo "  This was a dry run - no actual resources were deleted"
        echo "  Re-run without --dry-run to perform actual cleanup"
    else
        echo "🗑️  RESOURCES REMOVED:"
        echo "  ✅ Confidential Virtual Machines"
        echo "  ✅ Managed HSM (purged permanently)"
        echo "  ✅ Key Vaults (purged permanently)"
        echo "  ✅ Attestation Providers"
        echo "  ✅ Storage Accounts"
        echo "  ✅ Managed Identities"
        echo "  ✅ Network Resources (NICs, IPs, NSGs)"
        if [[ "$KEEP_BACKUP_FILES" == false ]]; then
            echo "  ✅ Local security files"
        else
            echo "  ⚠️  Local security files kept as requested"
        fi
    fi
    
    echo
    echo "⏳ BACKGROUND OPERATIONS:"
    echo "  - Resource group deletion (if initiated)"
    echo "  - Final resource cleanup (may take 5-10 minutes)"
    echo
    
    if [[ "$DRY_RUN" == false ]]; then
        echo "💰 COST IMPACT:"
        echo "  All billable resources have been removed"
        echo "  Billing should stop within the next hour"
        echo
        echo "⚠️  IMPORTANT NOTES:"
        echo "  - Managed HSM data has been permanently deleted"
        if [[ "$KEEP_BACKUP_FILES" == false ]]; then
            echo "  - Security domain backups have been removed"
        else
            echo "  - Security domain backups are preserved in: $SCRIPT_DIR/hsm-backup/"
        fi
        echo "  - Any data in storage accounts has been permanently lost"
        echo "  - Soft-deleted resources have been purged"
        echo
        
        if [[ $CLEANUP_ERRORS -gt 0 ]]; then
            echo "⚠️  CLEANUP WARNINGS:"
            echo "  - $CLEANUP_ERRORS errors occurred during cleanup"
            echo "  - Check the cleanup log for details: $SCRIPT_DIR/destroy.log"
            echo "  - Some resources may require manual cleanup"
            echo
        fi
    fi
    
    echo "📚 ADDITIONAL INFORMATION:"
    echo "  - Cleanup logs: $SCRIPT_DIR/destroy.log"
    echo "  - Azure portal: https://portal.azure.com"
    echo "  - Azure billing: https://portal.azure.com/#blade/Microsoft_Azure_Billing/ModernBillingMenuBlade/Overview"
    echo "========================================================================"
}

# Error handling
cleanup_on_error() {
    local exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        echo
        error "Cleanup failed or was interrupted (exit code: $exit_code)"
        error "Check the cleanup log for details: $SCRIPT_DIR/destroy.log"
        warning "Some resources may still exist. Check the Azure portal and consider manual cleanup."
        
        # Show recent log entries
        if [[ -f "$SCRIPT_DIR/destroy.log" ]]; then
            echo
            echo "Recent log entries:"
            tail -10 "$SCRIPT_DIR/destroy.log"
        fi
    fi
}

# Main cleanup function
main() {
    # Record cleanup start time
    CLEANUP_START_TIME=$(date +%s)
    
    # Initialize logging
    exec 2> >(tee -a "${SCRIPT_DIR}/destroy.log")
    
    echo "========================================================================"
    if [[ "$DRY_RUN" == true ]]; then
        echo "🔍 AZURE CONFIDENTIAL COMPUTING CLEANUP - DRY RUN"
    else
        echo "🧹 AZURE CONFIDENTIAL COMPUTING CLEANUP"
    fi
    echo "========================================================================"
    echo "This script will remove all confidential computing resources"
    echo "including Managed HSM, Confidential VMs, and related services."
    echo
    
    if [[ "$DRY_RUN" == true ]]; then
        echo "🔍 DRY RUN MODE: No resources will be actually deleted"
        echo "This mode shows what would be deleted without making changes."
    else
        echo "⚠️  WARNING: This is a destructive operation!"
        echo "All data will be permanently lost."
    fi
    
    echo
    
    # Set trap for error handling
    trap cleanup_on_error EXIT
    
    # Execute cleanup steps
    check_environment
    check_prerequisites
    discover_resources
    list_resources
    confirm_deletion
    
    if [[ "$DRY_RUN" == true ]]; then
        info "DRY RUN: Simulating cleanup process..."
    else
        log "Starting actual cleanup process..."
    fi
    
    stop_virtual_machines
    delete_managed_hsm
    delete_key_vaults
    delete_remaining_resources
    delete_resource_group
    cleanup_local_files
    validate_cleanup
    display_summary
    
    if [[ "$DRY_RUN" == true ]]; then
        success "Dry run completed successfully! 🔍"
    else
        if [[ $CLEANUP_ERRORS -eq 0 ]]; then
            success "Cleanup completed successfully! 🗑️"
        else
            warning "Cleanup completed with $CLEANUP_ERRORS errors"
            exit 1
        fi
    fi
}

# Script entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Parse command line arguments
    parse_arguments "$@"
    
    # Run main function
    main
fi