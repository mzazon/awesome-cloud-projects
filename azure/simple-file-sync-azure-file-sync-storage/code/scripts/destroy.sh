#!/bin/bash

#################################################################################
# Azure File Sync Cleanup Script
# 
# This script safely removes Azure File Sync infrastructure including:
# - Cloud Endpoints
# - Sync Groups
# - Storage Sync Service
# - Azure File Shares
# - Storage Account
# - Resource Group
#
# Usage: ./destroy.sh [--dry-run] [--force] [--help]
#################################################################################

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/destroy.log"
DRY_RUN=false
FORCE_DELETE=false

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

#################################################################################
# Logging Functions
#################################################################################

log() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case $level in
        "INFO")
            echo -e "${GREEN}[INFO]${NC} $message"
            ;;
        "WARN")
            echo -e "${YELLOW}[WARN]${NC} $message"
            ;;
        "ERROR")
            echo -e "${RED}[ERROR]${NC} $message"
            ;;
        "DEBUG")
            echo -e "${BLUE}[DEBUG]${NC} $message"
            ;;
    esac
    
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
}

#################################################################################
# Utility Functions
#################################################################################

show_help() {
    echo "Azure File Sync Cleanup Script"
    echo ""
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --dry-run    Show what would be deleted without making changes"
    echo "  --force      Skip confirmation prompts (use with caution)"
    echo "  --help       Show this help message"
    echo ""
    echo "Environment Variables (optional):"
    echo "  RESOURCE_GROUP   Specific resource group to delete"
    echo "  AZURE_LOCATION   Azure region to search for resources"
    echo ""
}

check_prerequisites() {
    log "INFO" "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        log "ERROR" "Azure CLI is not installed. Please install it first."
        log "INFO" "Visit: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
        exit 1
    fi
    
    # Check if logged into Azure
    if ! az account show &> /dev/null; then
        log "ERROR" "Not logged into Azure. Please run 'az login' first."
        exit 1
    fi
    
    # Check if Azure File Sync extension is available
    if ! az extension list | grep -q "storagesync"; then
        log "WARN" "Azure File Sync CLI extension not found. Some cleanup operations may fail."
        if ! az extension add --name storagesync --only-show-errors 2>/dev/null; then
            log "WARN" "Could not install Azure File Sync extension. Continuing anyway."
        fi
    fi
    
    log "INFO" "Prerequisites check completed"
}

confirm_deletion() {
    if [[ "$FORCE_DELETE" == "true" ]] || [[ "$DRY_RUN" == "true" ]]; then
        return 0
    fi
    
    echo ""
    echo -e "${RED}WARNING: This will permanently delete Azure File Sync resources!${NC}"
    echo ""
    echo "Resources to be deleted:"
    echo "- All Cloud Endpoints and Sync Groups"
    echo "- Storage Sync Services"
    echo "- Azure File Shares and their contents"
    echo "- Storage Accounts"
    echo "- Resource Groups (if created by this recipe)"
    echo ""
    echo -e "${YELLOW}This action cannot be undone!${NC}"
    echo ""
    
    read -p "Are you sure you want to continue? (type 'yes' to confirm): " confirmation
    
    if [[ "$confirmation" != "yes" ]]; then
        log "INFO" "Deletion cancelled by user"
        exit 0
    fi
    
    log "INFO" "User confirmed deletion. Proceeding with cleanup..."
}

discover_resources() {
    log "INFO" "Discovering Azure File Sync resources..."
    
    # Find resource groups that match our naming pattern
    if [[ -n "${RESOURCE_GROUP:-}" ]]; then
        RESOURCE_GROUPS=("$RESOURCE_GROUP")
    else
        # Look for resource groups created by the deployment script
        readarray -t RESOURCE_GROUPS < <(az group list \
            --query "[?contains(name, 'rg-filesync-') || contains(tags.purpose, 'recipe')].name" \
            --output tsv 2>/dev/null || echo "")
    fi
    
    if [[ ${#RESOURCE_GROUPS[@]} -eq 0 ]] || [[ -z "${RESOURCE_GROUPS[0]}" ]]; then
        log "WARN" "No Azure File Sync resource groups found"
        log "INFO" "Looking for individual resources..."
        
        # If no resource groups found, look for individual storage sync services
        readarray -t STORAGE_SYNC_SERVICES < <(az resource list \
            --resource-type "Microsoft.StorageSync/storageSyncServices" \
            --query "[].{name:name,resourceGroup:resourceGroup}" \
            --output tsv 2>/dev/null | awk '{print $2 ":" $1}' || echo "")
        
        if [[ ${#STORAGE_SYNC_SERVICES[@]} -eq 0 ]] || [[ -z "${STORAGE_SYNC_SERVICES[0]}" ]]; then
            log "INFO" "No Azure File Sync resources found. Nothing to clean up."
            exit 0
        fi
    fi
    
    log "INFO" "Found ${#RESOURCE_GROUPS[@]} resource group(s) to process"
}

wait_for_deletion() {
    local resource_type=$1
    local resource_name=$2
    local max_attempts=20
    local attempt=1
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "[DRY-RUN] Would wait for $resource_type deletion"
        return 0
    fi
    
    log "INFO" "Waiting for $resource_type '$resource_name' deletion..."
    
    while [ $attempt -le $max_attempts ]; do
        sleep 5
        log "DEBUG" "Checking deletion status (attempt $attempt/$max_attempts)..."
        attempt=$((attempt + 1))
    done
    
    log "INFO" "$resource_type deletion completed"
}

#################################################################################
# Cleanup Functions
#################################################################################

cleanup_sync_groups() {
    local resource_group=$1
    
    log "INFO" "Cleaning up sync groups in resource group '$resource_group'..."
    
    # Get all storage sync services in the resource group
    local sync_services
    readarray -t sync_services < <(az storagesync list \
        --resource-group "$resource_group" \
        --query "[].name" \
        --output tsv 2>/dev/null || echo "")
    
    if [[ ${#sync_services[@]} -eq 0 ]] || [[ -z "${sync_services[0]}" ]]; then
        log "INFO" "No Storage Sync Services found in resource group '$resource_group'"
        return 0
    fi
    
    for sync_service in "${sync_services[@]}"; do
        if [[ -z "$sync_service" ]]; then
            continue
        fi
        
        log "INFO" "Processing Storage Sync Service: $sync_service"
        
        if [[ "$DRY_RUN" == "true" ]]; then
            log "INFO" "[DRY-RUN] Would clean up sync groups for service: $sync_service"
            continue
        fi
        
        # Get all sync groups for this service
        local sync_groups
        readarray -t sync_groups < <(az storagesync sync-group list \
            --resource-group "$resource_group" \
            --storage-sync-service "$sync_service" \
            --query "[].name" \
            --output tsv 2>/dev/null || echo "")
        
        for sync_group in "${sync_groups[@]}"; do
            if [[ -z "$sync_group" ]]; then
                continue
            fi
            
            log "INFO" "Cleaning up sync group: $sync_group"
            
            # Delete all cloud endpoints first
            local cloud_endpoints
            readarray -t cloud_endpoints < <(az storagesync sync-group cloud-endpoint list \
                --resource-group "$resource_group" \
                --storage-sync-service "$sync_service" \
                --sync-group-name "$sync_group" \
                --query "[].name" \
                --output tsv 2>/dev/null || echo "")
            
            for endpoint in "${cloud_endpoints[@]}"; do
                if [[ -z "$endpoint" ]]; then
                    continue
                fi
                
                log "INFO" "Deleting cloud endpoint: $endpoint"
                az storagesync sync-group cloud-endpoint delete \
                    --resource-group "$resource_group" \
                    --storage-sync-service "$sync_service" \
                    --sync-group-name "$sync_group" \
                    --name "$endpoint" \
                    --yes \
                    --only-show-errors 2>/dev/null || {
                    log "WARN" "Failed to delete cloud endpoint: $endpoint"
                }
            done
            
            # Delete any server endpoints
            local server_endpoints
            readarray -t server_endpoints < <(az storagesync sync-group server-endpoint list \
                --resource-group "$resource_group" \
                --storage-sync-service "$sync_service" \
                --sync-group-name "$sync_group" \
                --query "[].name" \
                --output tsv 2>/dev/null || echo "")
            
            for endpoint in "${server_endpoints[@]}"; do
                if [[ -z "$endpoint" ]]; then
                    continue
                fi
                
                log "INFO" "Deleting server endpoint: $endpoint"
                az storagesync sync-group server-endpoint delete \
                    --resource-group "$resource_group" \
                    --storage-sync-service "$sync_service" \
                    --sync-group-name "$sync_group" \
                    --name "$endpoint" \
                    --yes \
                    --only-show-errors 2>/dev/null || {
                    log "WARN" "Failed to delete server endpoint: $endpoint"
                }
            done
            
            # Delete the sync group
            log "INFO" "Deleting sync group: $sync_group"
            az storagesync sync-group delete \
                --resource-group "$resource_group" \
                --storage-sync-service "$sync_service" \
                --name "$sync_group" \
                --yes \
                --only-show-errors 2>/dev/null || {
                log "WARN" "Failed to delete sync group: $sync_group"
            }
            
            wait_for_deletion "Sync Group" "$sync_group"
        done
    done
    
    log "INFO" "Sync group cleanup completed for resource group '$resource_group'"
}

cleanup_storage_sync_services() {
    local resource_group=$1
    
    log "INFO" "Cleaning up Storage Sync Services in resource group '$resource_group'..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "[DRY-RUN] Would delete all Storage Sync Services in: $resource_group"
        return 0
    fi
    
    # Get all storage sync services
    local sync_services
    readarray -t sync_services < <(az storagesync list \
        --resource-group "$resource_group" \
        --query "[].name" \
        --output tsv 2>/dev/null || echo "")
    
    for sync_service in "${sync_services[@]}"; do
        if [[ -z "$sync_service" ]]; then
            continue
        fi
        
        log "INFO" "Deleting Storage Sync Service: $sync_service"
        az storagesync delete \
            --resource-group "$resource_group" \
            --name "$sync_service" \
            --yes \
            --only-show-errors 2>/dev/null || {
            log "WARN" "Failed to delete Storage Sync Service: $sync_service"
        }
        
        wait_for_deletion "Storage Sync Service" "$sync_service"
    done
    
    log "INFO" "Storage Sync Service cleanup completed"
}

cleanup_storage_accounts() {
    local resource_group=$1
    
    log "INFO" "Cleaning up storage accounts in resource group '$resource_group'..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "[DRY-RUN] Would delete storage accounts in: $resource_group"
        return 0
    fi
    
    # Get storage accounts that might be related to file sync (look for tags or naming patterns)
    local storage_accounts
    readarray -t storage_accounts < <(az storage account list \
        --resource-group "$resource_group" \
        --query "[?contains(name, 'filesync') || contains(tags.purpose, 'recipe')].name" \
        --output tsv 2>/dev/null || echo "")
    
    if [[ ${#storage_accounts[@]} -eq 0 ]] || [[ -z "${storage_accounts[0]}" ]]; then
        # If no tagged accounts found, get all storage accounts in the resource group
        readarray -t storage_accounts < <(az storage account list \
            --resource-group "$resource_group" \
            --query "[].name" \
            --output tsv 2>/dev/null || echo "")
    fi
    
    for storage_account in "${storage_accounts[@]}"; do
        if [[ -z "$storage_account" ]]; then
            continue
        fi
        
        log "INFO" "Deleting storage account: $storage_account"
        
        # First, try to delete file shares explicitly (for better error handling)
        local file_shares
        readarray -t file_shares < <(az storage share list \
            --account-name "$storage_account" \
            --auth-mode login \
            --query "[].name" \
            --output tsv 2>/dev/null || echo "")
        
        for share in "${file_shares[@]}"; do
            if [[ -z "$share" ]]; then
                continue
            fi
            
            log "INFO" "Deleting file share: $share"
            az storage share delete \
                --account-name "$storage_account" \
                --name "$share" \
                --auth-mode login \
                --only-show-errors 2>/dev/null || {
                log "WARN" "Could not delete file share: $share"
            }
        done
        
        # Delete the storage account
        az storage account delete \
            --name "$storage_account" \
            --resource-group "$resource_group" \
            --yes \
            --only-show-errors 2>/dev/null || {
            log "WARN" "Failed to delete storage account: $storage_account"
        }
        
        wait_for_deletion "Storage Account" "$storage_account"
    done
    
    log "INFO" "Storage account cleanup completed"
}

cleanup_resource_group() {
    local resource_group=$1
    
    log "INFO" "Cleaning up resource group '$resource_group'..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "[DRY-RUN] Would delete resource group: $resource_group"
        return 0
    fi
    
    # Check if resource group exists
    if ! az group show --name "$resource_group" &>/dev/null; then
        log "INFO" "Resource group '$resource_group' does not exist"
        return 0
    fi
    
    # Check if this resource group was created by our recipe (has appropriate tags)
    local created_by_recipe
    created_by_recipe=$(az group show \
        --name "$resource_group" \
        --query "tags.purpose" \
        --output tsv 2>/dev/null || echo "")
    
    if [[ "$created_by_recipe" != "recipe" ]] && [[ "$FORCE_DELETE" != "true" ]]; then
        log "WARN" "Resource group '$resource_group' doesn't appear to be created by this recipe"
        echo ""
        read -p "Do you want to delete this resource group anyway? (type 'yes' to confirm): " rg_confirmation
        
        if [[ "$rg_confirmation" != "yes" ]]; then
            log "INFO" "Skipping resource group deletion: $resource_group"
            return 0
        fi
    fi
    
    log "INFO" "Deleting resource group: $resource_group"
    az group delete \
        --name "$resource_group" \
        --yes \
        --no-wait \
        --only-show-errors || {
        log "ERROR" "Failed to initiate deletion of resource group: $resource_group"
        return 1
    }
    
    log "INFO" "Resource group deletion initiated: $resource_group"
    log "INFO" "Note: Complete deletion may take several minutes"
}

display_cleanup_summary() {
    log "INFO" "Cleanup process completed!"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "[DRY-RUN] Summary of resources that would be deleted:"
    else
        log "INFO" "Cleanup Summary:"
    fi
    
    echo ""
    echo "============================================="
    echo "       Azure File Sync Cleanup Complete"
    echo "============================================="
    echo "Processed Resource Groups: ${#RESOURCE_GROUPS[@]}"
    echo "Cleanup completed at: $(date)"
    echo "============================================="
    echo ""
    
    if [[ "$DRY_RUN" == "false" ]]; then
        echo "All Azure File Sync resources have been cleaned up."
        echo "Please verify in the Azure portal that all resources are deleted."
        echo ""
        echo "If any resources remain, they may be:"
        echo "- Still in the deletion process (check again in a few minutes)"
        echo "- Protected by deletion locks"
        echo "- Dependencies that require manual cleanup"
        echo ""
        log "INFO" "Log file available at: $LOG_FILE"
    else
        log "INFO" "Dry-run completed. Use './destroy.sh' to execute the actual cleanup."
    fi
}

#################################################################################
# Main Execution
#################################################################################

main() {
    # Initialize log file
    echo "=== Azure File Sync Cleanup Started at $(date) ===" > "$LOG_FILE"
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --dry-run)
                DRY_RUN=true
                log "INFO" "Running in dry-run mode - no resources will be deleted"
                shift
                ;;
            --force)
                FORCE_DELETE=true
                log "INFO" "Force mode enabled - skipping confirmation prompts"
                shift
                ;;
            --help)
                show_help
                exit 0
                ;;
            *)
                log "ERROR" "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
    
    log "INFO" "Starting Azure File Sync cleanup..."
    
    # Execute cleanup steps
    check_prerequisites
    discover_resources
    confirm_deletion
    
    # Process each resource group
    for resource_group in "${RESOURCE_GROUPS[@]}"; do
        if [[ -z "$resource_group" ]]; then
            continue
        fi
        
        log "INFO" "Processing resource group: $resource_group"
        
        # Clean up in reverse order of creation
        cleanup_sync_groups "$resource_group"
        cleanup_storage_sync_services "$resource_group"
        cleanup_storage_accounts "$resource_group"
        cleanup_resource_group "$resource_group"
    done
    
    display_cleanup_summary
    
    if [[ "$DRY_RUN" == "false" ]]; then
        log "INFO" "Cleanup completed. Verify resource deletion in the Azure portal."
    fi
}

# Handle script interruption
trap 'log "ERROR" "Script interrupted. Cleanup may be incomplete."; exit 1' INT TERM

# Execute main function
main "$@"