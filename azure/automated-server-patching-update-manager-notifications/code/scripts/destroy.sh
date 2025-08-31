#!/bin/bash

# =============================================================================
# Azure Automated Server Patching with Update Manager and Notifications
# Cleanup/Destroy Script
# =============================================================================

set -e
set -o pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

log_info() {
    log "${BLUE}INFO${NC}: $1"
}

log_success() {
    log "${GREEN}SUCCESS${NC}: $1"
}

log_warning() {
    log "${YELLOW}WARNING${NC}: $1"
}

log_error() {
    log "${RED}ERROR${NC}: $1"
}

# Error handling
handle_error() {
    local line_number=$1
    log_error "Script failed at line ${line_number}. Continuing with cleanup..."
}

trap 'handle_error ${LINENO}' ERR

# Check if running in interactive mode
check_interactive() {
    if [[ -t 0 ]]; then
        return 0  # Interactive
    else
        return 1  # Non-interactive
    fi
}

# Function to confirm destructive actions
confirm_action() {
    local action="$1"
    local resource="$2"
    
    if check_interactive && [[ "$FORCE_DELETE" != "true" ]]; then
        echo -e "${YELLOW}WARNING: This will permanently delete $resource${NC}"
        read -p "Are you sure you want to $action? (y/N): " confirmation
        if [[ ! "$confirmation" =~ ^[Yy]$ ]]; then
            log_info "Skipping $action"
            return 1
        fi
    fi
    return 0
}

# Banner
echo -e "${RED}"
cat << "EOF"
╔══════════════════════════════════════════════════════════════════════════════╗
║                 Azure Automated Server Patching Cleanup                     ║
║                        ⚠️  DESTRUCTIVE OPERATION  ⚠️                        ║
╚══════════════════════════════════════════════════════════════════════════════╝
EOF
echo -e "${NC}"

log_warning "Starting cleanup of Azure automated server patching solution..."
log_warning "This will permanently delete all deployed resources!"

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --force)
            FORCE_DELETE="true"
            log_info "Force delete mode enabled - skipping confirmation prompts"
            shift
            ;;
        --resource-group)
            RESOURCE_GROUP="$2"
            shift 2
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo "Options:"
            echo "  --force                Skip confirmation prompts"
            echo "  --resource-group NAME  Specify resource group to delete"
            echo "  --help                 Show this help message"
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# =============================================================================
# Prerequisites Check
# =============================================================================

log_info "Checking prerequisites..."

# Check if Azure CLI is installed
if ! command -v az &> /dev/null; then
    log_error "Azure CLI is not installed. Cannot proceed with cleanup."
    exit 1
fi

# Check if user is logged into Azure
if ! az account show &> /dev/null; then
    log_error "Not logged into Azure. Please run 'az login' first."
    exit 1
fi

log_success "Prerequisites check completed"

# =============================================================================
# Load Deployment Information
# =============================================================================

# Try to load deployment info from previous deployment
if [[ -f ".deployment_info" ]]; then
    log_info "Loading deployment information from .deployment_info..."
    source .deployment_info
    
    log_info "Found deployment information:"
    log_info "  Resource Group: $RESOURCE_GROUP"
    log_info "  Deployment Date: ${DEPLOYMENT_DATE:-Unknown}"
    log_info "  Subscription: $SUBSCRIPTION_ID"
else
    log_warning "No .deployment_info file found"
    
    # If no resource group specified and no deployment info, prompt user
    if [[ -z "$RESOURCE_GROUP" ]]; then
        if check_interactive; then
            echo "Available resource groups with 'patching' in the name:"
            az group list --query "[?contains(name, 'patching')].{Name:name, Location:location}" --output table 2>/dev/null || echo "None found"
            echo
            read -p "Enter the resource group name to delete: " RESOURCE_GROUP
            if [[ -z "$RESOURCE_GROUP" ]]; then
                log_error "Resource group name is required"
                exit 1
            fi
        else
            log_error "No resource group specified and no deployment info available"
            log_error "Use --resource-group option to specify the resource group to delete"
            exit 1
        fi
    fi
fi

# Validate resource group exists
if ! az group show --name "$RESOURCE_GROUP" &> /dev/null; then
    log_error "Resource group '$RESOURCE_GROUP' does not exist or is not accessible"
    exit 1
fi

# Get current subscription for verification
CURRENT_SUBSCRIPTION=$(az account show --query id --output tsv)
if [[ -n "$SUBSCRIPTION_ID" && "$SUBSCRIPTION_ID" != "$CURRENT_SUBSCRIPTION" ]]; then
    log_warning "Current subscription ($CURRENT_SUBSCRIPTION) differs from deployment subscription ($SUBSCRIPTION_ID)"
    if check_interactive && [[ "$FORCE_DELETE" != "true" ]]; then
        read -p "Continue with cleanup? (y/N): " continue_cleanup
        if [[ ! "$continue_cleanup" =~ ^[Yy]$ ]]; then
            log_info "Cleanup cancelled by user"
            exit 0
        fi
    fi
fi

# =============================================================================
# Cleanup Confirmation
# =============================================================================

# Show what will be deleted
log_info "Resources to be deleted in resource group '$RESOURCE_GROUP':"
az resource list --resource-group "$RESOURCE_GROUP" --query "[].{Name:name, Type:type, Location:location}" --output table 2>/dev/null || log_warning "Could not list resources"

# Final confirmation
if ! confirm_action "delete all resources in resource group '$RESOURCE_GROUP'" "ALL RESOURCES IN $RESOURCE_GROUP"; then
    log_info "Cleanup cancelled by user"
    exit 0
fi

# =============================================================================
# Individual Resource Cleanup (Selective)
# =============================================================================

log_info "Starting selective resource cleanup..."

# Remove Activity Log Alerts first (they depend on Action Groups)
if [[ -n "$PATCH_ALERT_NAME" ]]; then
    log_info "Removing patch deployment activity alert: $PATCH_ALERT_NAME"
    if az monitor activity-log alert show --resource-group "$RESOURCE_GROUP" --name "$PATCH_ALERT_NAME" &> /dev/null; then
        az monitor activity-log alert delete \
            --resource-group "$RESOURCE_GROUP" \
            --name "$PATCH_ALERT_NAME" \
            --yes &> /dev/null || log_warning "Failed to delete patch deployment alert"
        log_success "Patch deployment activity alert removed"
    else
        log_info "Patch deployment activity alert not found, skipping"
    fi
fi

if [[ -n "$ASSIGNMENT_ALERT_NAME" ]]; then
    log_info "Removing maintenance assignment alert: $ASSIGNMENT_ALERT_NAME"
    if az monitor activity-log alert show --resource-group "$RESOURCE_GROUP" --name "$ASSIGNMENT_ALERT_NAME" &> /dev/null; then
        az monitor activity-log alert delete \
            --resource-group "$RESOURCE_GROUP" \
            --name "$ASSIGNMENT_ALERT_NAME" \
            --yes &> /dev/null || log_warning "Failed to delete maintenance assignment alert"
        log_success "Maintenance assignment alert removed"
    else
        log_info "Maintenance assignment alert not found, skipping"
    fi
fi

# Remove Maintenance Configuration Assignment
if [[ -n "$VM_NAME" && -n "$ASSIGNMENT_NAME" ]]; then
    log_info "Removing maintenance configuration assignment: $ASSIGNMENT_NAME"
    if az maintenance assignment show \
        --resource-group "$RESOURCE_GROUP" \
        --resource-name "$VM_NAME" \
        --resource-type "virtualMachines" \
        --provider-name "Microsoft.Compute" \
        --configuration-assignment-name "$ASSIGNMENT_NAME" &> /dev/null; then
        
        az maintenance assignment delete \
            --resource-group "$RESOURCE_GROUP" \
            --resource-name "$VM_NAME" \
            --resource-type "virtualMachines" \
            --provider-name "Microsoft.Compute" \
            --configuration-assignment-name "$ASSIGNMENT_NAME" &> /dev/null || log_warning "Failed to delete maintenance assignment"
        log_success "Maintenance configuration assignment removed"
    else
        log_info "Maintenance configuration assignment not found, skipping"
    fi
fi

# Remove any remaining activity log alerts (search by pattern)
log_info "Searching for additional activity log alerts..."
ADDITIONAL_ALERTS=$(az monitor activity-log alert list \
    --resource-group "$RESOURCE_GROUP" \
    --query "[?contains(name, 'Alert-') || contains(name, 'Activity-')].name" \
    --output tsv 2>/dev/null || echo "")

if [[ -n "$ADDITIONAL_ALERTS" ]]; then
    while IFS= read -r alert_name; do
        if [[ -n "$alert_name" ]]; then
            log_info "Removing additional activity log alert: $alert_name"
            az monitor activity-log alert delete \
                --resource-group "$RESOURCE_GROUP" \
                --name "$alert_name" \
                --yes &> /dev/null || log_warning "Failed to delete alert: $alert_name"
        fi
    done <<< "$ADDITIONAL_ALERTS"
    log_success "Additional activity log alerts removed"
fi

log_success "Selective resource cleanup completed"

# =============================================================================
# Complete Resource Group Deletion
# =============================================================================

# Option to delete entire resource group or continue with individual cleanup
if check_interactive && [[ "$FORCE_DELETE" != "true" ]]; then
    echo
    log_info "Cleanup options:"
    echo "1. Delete entire resource group (fastest, removes everything)"
    echo "2. Delete remaining resources individually (slower, more granular)"
    echo "3. Cancel cleanup"
    read -p "Choose option (1-3): " cleanup_option
    
    case $cleanup_option in
        1)
            DELETE_RESOURCE_GROUP="true"
            ;;
        2)
            DELETE_RESOURCE_GROUP="false"
            ;;
        3)
            log_info "Cleanup cancelled by user"
            exit 0
            ;;
        *)
            log_warning "Invalid option, defaulting to resource group deletion"
            DELETE_RESOURCE_GROUP="true"
            ;;
    esac
else
    DELETE_RESOURCE_GROUP="true"
fi

if [[ "$DELETE_RESOURCE_GROUP" == "true" ]]; then
    log_info "Deleting entire resource group: $RESOURCE_GROUP"
    log_warning "This will delete ALL resources in the resource group!"
    
    # Final confirmation for resource group deletion
    if confirm_action "delete the entire resource group" "RESOURCE GROUP $RESOURCE_GROUP"; then
        az group delete \
            --name "$RESOURCE_GROUP" \
            --yes \
            --no-wait &> /dev/null
        
        log_success "Resource group deletion initiated: $RESOURCE_GROUP"
        log_info "Deletion is running in the background and may take several minutes"
        
        # Optional: Wait for deletion to complete
        if check_interactive; then
            read -p "Wait for deletion to complete? (y/N): " wait_for_deletion
            if [[ "$wait_for_deletion" =~ ^[Yy]$ ]]; then
                log_info "Waiting for resource group deletion to complete..."
                
                # Check deletion status
                while az group show --name "$RESOURCE_GROUP" &> /dev/null; do
                    echo -n "."
                    sleep 10
                done
                echo
                log_success "Resource group deletion completed: $RESOURCE_GROUP"
            fi
        fi
    else
        log_info "Resource group deletion cancelled"
    fi
else
    # Individual resource deletion
    log_info "Proceeding with individual resource deletion..."
    
    # Delete Virtual Machine
    if [[ -n "$VM_NAME" ]]; then
        log_info "Deleting virtual machine: $VM_NAME"
        if az vm show --resource-group "$RESOURCE_GROUP" --name "$VM_NAME" &> /dev/null; then
            az vm delete \
                --resource-group "$RESOURCE_GROUP" \
                --name "$VM_NAME" \
                --yes &> /dev/null || log_warning "Failed to delete VM: $VM_NAME"
            log_success "Virtual machine deleted: $VM_NAME"
        else
            log_info "Virtual machine not found, skipping"
        fi
    fi
    
    # Delete Maintenance Configuration
    if [[ -n "$MAINTENANCE_CONFIG_NAME" ]]; then
        log_info "Deleting maintenance configuration: $MAINTENANCE_CONFIG_NAME"
        if az maintenance configuration show --resource-group "$RESOURCE_GROUP" --resource-name "$MAINTENANCE_CONFIG_NAME" &> /dev/null; then
            az maintenance configuration delete \
                --resource-group "$RESOURCE_GROUP" \
                --resource-name "$MAINTENANCE_CONFIG_NAME" \
                --yes &> /dev/null || log_warning "Failed to delete maintenance configuration: $MAINTENANCE_CONFIG_NAME"
            log_success "Maintenance configuration deleted: $MAINTENANCE_CONFIG_NAME"
        else
            log_info "Maintenance configuration not found, skipping"
        fi
    fi
    
    # Delete Action Group
    if [[ -n "$ACTION_GROUP_NAME" ]]; then
        log_info "Deleting Action Group: $ACTION_GROUP_NAME"
        if az monitor action-group show --resource-group "$RESOURCE_GROUP" --name "$ACTION_GROUP_NAME" &> /dev/null; then
            az monitor action-group delete \
                --resource-group "$RESOURCE_GROUP" \
                --name "$ACTION_GROUP_NAME" &> /dev/null || log_warning "Failed to delete Action Group: $ACTION_GROUP_NAME"
            log_success "Action Group deleted: $ACTION_GROUP_NAME"
        else
            log_info "Action Group not found, skipping"
        fi
    fi
    
    # Delete any remaining network resources (NICs, NSGs, Public IPs, etc.)
    log_info "Cleaning up remaining network resources..."
    
    # Delete Network Security Groups
    NSG_LIST=$(az network nsg list --resource-group "$RESOURCE_GROUP" --query "[].name" --output tsv 2>/dev/null || echo "")
    if [[ -n "$NSG_LIST" ]]; then
        while IFS= read -r nsg_name; do
            if [[ -n "$nsg_name" ]]; then
                log_info "Deleting network security group: $nsg_name"
                az network nsg delete --resource-group "$RESOURCE_GROUP" --name "$nsg_name" &> /dev/null || log_warning "Failed to delete NSG: $nsg_name"
            fi
        done <<< "$NSG_LIST"
    fi
    
    # Delete Public IP addresses
    PIP_LIST=$(az network public-ip list --resource-group "$RESOURCE_GROUP" --query "[].name" --output tsv 2>/dev/null || echo "")
    if [[ -n "$PIP_LIST" ]]; then
        while IFS= read -r pip_name; do
            if [[ -n "$pip_name" ]]; then
                log_info "Deleting public IP: $pip_name"
                az network public-ip delete --resource-group "$RESOURCE_GROUP" --name "$pip_name" &> /dev/null || log_warning "Failed to delete public IP: $pip_name"
            fi
        done <<< "$PIP_LIST"
    fi
    
    # Delete Network Interfaces
    NIC_LIST=$(az network nic list --resource-group "$RESOURCE_GROUP" --query "[].name" --output tsv 2>/dev/null || echo "")
    if [[ -n "$NIC_LIST" ]]; then
        while IFS= read -r nic_name; do
            if [[ -n "$nic_name" ]]; then
                log_info "Deleting network interface: $nic_name"
                az network nic delete --resource-group "$RESOURCE_GROUP" --name "$nic_name" &> /dev/null || log_warning "Failed to delete NIC: $nic_name"
            fi
        done <<< "$NIC_LIST"
    fi
    
    # Delete Virtual Networks
    VNET_LIST=$(az network vnet list --resource-group "$RESOURCE_GROUP" --query "[].name" --output tsv 2>/dev/null || echo "")
    if [[ -n "$VNET_LIST" ]]; then
        while IFS= read -r vnet_name; do
            if [[ -n "$vnet_name" ]]; then
                log_info "Deleting virtual network: $vnet_name"
                az network vnet delete --resource-group "$RESOURCE_GROUP" --name "$vnet_name" &> /dev/null || log_warning "Failed to delete VNet: $vnet_name"
            fi
        done <<< "$VNET_LIST"
    fi
    
    # Delete Storage Accounts (if any)
    STORAGE_LIST=$(az storage account list --resource-group "$RESOURCE_GROUP" --query "[].name" --output tsv 2>/dev/null || echo "")
    if [[ -n "$STORAGE_LIST" ]]; then
        while IFS= read -r storage_name; do
            if [[ -n "$storage_name" ]]; then
                log_info "Deleting storage account: $storage_name"
                az storage account delete --resource-group "$RESOURCE_GROUP" --name "$storage_name" --yes &> /dev/null || log_warning "Failed to delete storage account: $storage_name"
            fi
        done <<< "$STORAGE_LIST"
    fi
    
    log_success "Individual resource cleanup completed"
    
    # Check if resource group is now empty
    REMAINING_RESOURCES=$(az resource list --resource-group "$RESOURCE_GROUP" --query "length(@)" --output tsv 2>/dev/null || echo "0")
    if [[ "$REMAINING_RESOURCES" -eq 0 ]]; then
        log_info "Resource group is now empty"
        if confirm_action "delete the empty resource group" "EMPTY RESOURCE GROUP $RESOURCE_GROUP"; then
            az group delete --name "$RESOURCE_GROUP" --yes --no-wait &> /dev/null
            log_success "Empty resource group deletion initiated: $RESOURCE_GROUP"
        fi
    else
        log_warning "$REMAINING_RESOURCES resources remain in the resource group"
        log_info "You may need to manually delete these resources or the resource group"
    fi
fi

# =============================================================================
# Cleanup Local Files
# =============================================================================

log_info "Cleaning up local deployment files..."

# Remove deployment info file
if [[ -f ".deployment_info" ]]; then
    rm -f .deployment_info
    log_success "Removed .deployment_info file"
fi

# Remove any log files (optional)
if check_interactive; then
    read -p "Remove deployment log files? (y/N): " remove_logs
    if [[ "$remove_logs" =~ ^[Yy]$ ]]; then
        rm -f deploy_*.log destroy_*.log 2>/dev/null || true
        log_success "Log files removed"
    fi
fi

# =============================================================================
# Cleanup Summary
# =============================================================================

log_success "Cleanup completed!"

echo -e "\n${GREEN}=== CLEANUP SUMMARY ===${NC}"
if [[ "$DELETE_RESOURCE_GROUP" == "true" ]]; then
    echo -e "Resource Group:           ${RED}DELETED${NC} ($RESOURCE_GROUP)"
    echo -e "Status:                   ${YELLOW}Deletion in progress${NC}"
else
    echo -e "Resource Group:           ${BLUE}$RESOURCE_GROUP${NC}"
    echo -e "Individual Resources:     ${RED}DELETED${NC}"
fi

echo -e "\n${YELLOW}=== VERIFICATION ===${NC}"
echo "To verify all resources are deleted, run:"
echo "  az group show --name $RESOURCE_GROUP"
echo "Expected result: Resource group not found (if fully deleted)"

echo -e "\n${BLUE}=== BILLING IMPACT ===${NC}"
echo "• All billable resources have been deleted"
echo "• No further charges should accrue from this deployment"
echo "• Check your Azure bill to confirm resource deletion"

if [[ "$DELETE_RESOURCE_GROUP" == "true" ]]; then
    echo -e "\n${YELLOW}Note: Resource group deletion is asynchronous and may take several minutes to complete.${NC}"
fi

log_success "Azure automated server patching solution cleanup completed!"