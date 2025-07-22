#!/bin/bash

# =============================================================================
# Azure Resource Rightsizing Cleanup Script
# =============================================================================
# This script safely removes all resources created by the rightsizing solution
# including confirmation prompts and dependency handling.
# =============================================================================

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
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

# =============================================================================
# Configuration and Prerequisites
# =============================================================================

# Parse command line arguments
FORCE_DELETE=false
SKIP_CONFIRMATION=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --resource-group)
            RESOURCE_GROUP="$2"
            shift 2
            ;;
        --force)
            FORCE_DELETE=true
            shift
            ;;
        --yes)
            SKIP_CONFIRMATION=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo "Options:"
            echo "  --resource-group NAME         Resource group name to delete"
            echo "  --force                       Force deletion without additional prompts"
            echo "  --yes                         Skip confirmation prompts"
            echo "  --dry-run                     Show what would be deleted without actually deleting"
            echo "  --help                        Show this help message"
            exit 0
            ;;
        *)
            error "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Set defaults
DRY_RUN=${DRY_RUN:-false}

# =============================================================================
# Prerequisites Check
# =============================================================================

log "Checking prerequisites..."

# Check if Azure CLI is installed
if ! command -v az &> /dev/null; then
    error "Azure CLI is not installed. Please install it first."
    exit 1
fi

# Check if user is logged in
if ! az account show &> /dev/null; then
    error "Not logged in to Azure. Please run 'az login' first."
    exit 1
fi

# Get subscription ID
SUBSCRIPTION_ID=$(az account show --query id --output tsv)
if [[ -z "${SUBSCRIPTION_ID}" ]]; then
    error "No active Azure subscription found."
    exit 1
fi

success "Prerequisites check completed"

# =============================================================================
# Resource Group Discovery
# =============================================================================

# If no resource group specified, try to find rightsizing resource groups
if [[ -z "${RESOURCE_GROUP:-}" ]]; then
    log "Discovering rightsizing resource groups..."
    
    # Find resource groups with rightsizing tag or name pattern
    RIGHTSIZING_GROUPS=$(az group list \
        --query "[?tags.project=='rightsizing' || contains(name, 'rightsizing')].name" \
        --output tsv)
    
    if [[ -z "$RIGHTSIZING_GROUPS" ]]; then
        error "No rightsizing resource groups found. Please specify --resource-group."
        exit 1
    fi
    
    echo "Found rightsizing resource groups:"
    echo "$RIGHTSIZING_GROUPS" | nl
    
    if [[ "$SKIP_CONFIRMATION" != "true" ]]; then
        echo ""
        read -p "Enter the number of the resource group to delete (or 'all' for all groups): " SELECTION
        
        if [[ "$SELECTION" == "all" ]]; then
            RESOURCE_GROUPS_TO_DELETE="$RIGHTSIZING_GROUPS"
        else
            RESOURCE_GROUP=$(echo "$RIGHTSIZING_GROUPS" | sed -n "${SELECTION}p")
            if [[ -z "$RESOURCE_GROUP" ]]; then
                error "Invalid selection"
                exit 1
            fi
            RESOURCE_GROUPS_TO_DELETE="$RESOURCE_GROUP"
        fi
    else
        RESOURCE_GROUPS_TO_DELETE="$RIGHTSIZING_GROUPS"
    fi
else
    RESOURCE_GROUPS_TO_DELETE="$RESOURCE_GROUP"
fi

# =============================================================================
# Resource Discovery and Validation
# =============================================================================

log "Discovering resources to delete..."

for RG in $RESOURCE_GROUPS_TO_DELETE; do
    log "Checking resource group: $RG"
    
    # Check if resource group exists
    if ! az group exists --name "$RG" --output tsv 2>/dev/null; then
        warning "Resource group '$RG' does not exist. Skipping..."
        continue
    fi
    
    # Get resource count
    RESOURCE_COUNT=$(az resource list --resource-group "$RG" --query "length(@)" --output tsv)
    
    if [[ "$RESOURCE_COUNT" -eq 0 ]]; then
        warning "Resource group '$RG' is empty"
        continue
    fi
    
    echo "Resource group '$RG' contains $RESOURCE_COUNT resources:"
    
    # List resources with their types
    az resource list --resource-group "$RG" \
        --query "[].{Name:name, Type:type, Location:location}" \
        --output table
    
    # Check for protected resources
    PROTECTED_RESOURCES=$(az resource list --resource-group "$RG" \
        --query "[?tags.protected=='true'].name" \
        --output tsv)
    
    if [[ -n "$PROTECTED_RESOURCES" ]]; then
        warning "Found protected resources in '$RG':"
        echo "$PROTECTED_RESOURCES"
        if [[ "$FORCE_DELETE" != "true" ]]; then
            error "Protected resources found. Use --force to delete anyway."
            exit 1
        fi
    fi
    
    # Check for resources with locks
    LOCKED_RESOURCES=$(az lock list --resource-group "$RG" \
        --query "[].name" \
        --output tsv)
    
    if [[ -n "$LOCKED_RESOURCES" ]]; then
        warning "Found resource locks in '$RG':"
        echo "$LOCKED_RESOURCES"
        if [[ "$FORCE_DELETE" != "true" ]]; then
            error "Resource locks found. Use --force to delete anyway."
            exit 1
        fi
    fi
done

# =============================================================================
# Confirmation and Safety Checks
# =============================================================================

if [[ "$DRY_RUN" == "true" ]]; then
    success "Dry run completed. The following resource groups would be deleted:"
    echo "$RESOURCE_GROUPS_TO_DELETE"
    exit 0
fi

if [[ "$SKIP_CONFIRMATION" != "true" ]]; then
    echo ""
    warning "This action will permanently delete the following resources:"
    for RG in $RESOURCE_GROUPS_TO_DELETE; do
        echo "  - Resource Group: $RG"
        echo "    Resources: $(az resource list --resource-group "$RG" --query "length(@)" --output tsv) items"
    done
    echo ""
    
    read -p "Are you sure you want to proceed? Type 'DELETE' to confirm: " CONFIRMATION
    
    if [[ "$CONFIRMATION" != "DELETE" ]]; then
        log "Cleanup cancelled by user."
        exit 0
    fi
fi

# =============================================================================
# Cleanup Process
# =============================================================================

log "Starting cleanup process..."

# Function to safely delete a resource group
delete_resource_group() {
    local rg_name="$1"
    
    log "Deleting resource group: $rg_name"
    
    # Remove resource locks first if they exist
    if az lock list --resource-group "$rg_name" --query "[0]" --output tsv > /dev/null 2>&1; then
        log "Removing resource locks from $rg_name..."
        az lock delete --resource-group "$rg_name" --name "$(az lock list --resource-group "$rg_name" --query "[0].name" --output tsv)" || true
    fi
    
    # Delete individual resources that might need special handling
    log "Cleaning up special resources in $rg_name..."
    
    # Delete Logic Apps (might have dependencies)
    LOGIC_APPS=$(az logic workflow list --resource-group "$rg_name" --query "[].name" --output tsv)
    for logic_app in $LOGIC_APPS; do
        log "Deleting Logic App: $logic_app"
        az logic workflow delete --resource-group "$rg_name" --name "$logic_app" --yes || true
    done
    
    # Delete Function Apps (might have dependencies)
    FUNCTION_APPS=$(az functionapp list --resource-group "$rg_name" --query "[].name" --output tsv)
    for function_app in $FUNCTION_APPS; do
        log "Deleting Function App: $function_app"
        az functionapp delete --resource-group "$rg_name" --name "$function_app" || true
    done
    
    # Delete Web Apps and App Service Plans
    WEB_APPS=$(az webapp list --resource-group "$rg_name" --query "[].name" --output tsv)
    for web_app in $WEB_APPS; do
        log "Deleting Web App: $web_app"
        az webapp delete --resource-group "$rg_name" --name "$web_app" || true
    done
    
    APP_PLANS=$(az appservice plan list --resource-group "$rg_name" --query "[].name" --output tsv)
    for app_plan in $APP_PLANS; do
        log "Deleting App Service Plan: $app_plan"
        az appservice plan delete --resource-group "$rg_name" --name "$app_plan" --yes || true
    done
    
    # Delete VMs (might take time)
    VMS=$(az vm list --resource-group "$rg_name" --query "[].name" --output tsv)
    for vm in $VMS; do
        log "Deleting VM: $vm"
        az vm delete --resource-group "$rg_name" --name "$vm" --yes --force-deletion || true
    done
    
    # Delete Network Security Groups
    NSGS=$(az network nsg list --resource-group "$rg_name" --query "[].name" --output tsv)
    for nsg in $NSGS; do
        log "Deleting Network Security Group: $nsg"
        az network nsg delete --resource-group "$rg_name" --name "$nsg" || true
    done
    
    # Delete Application Insights
    APP_INSIGHTS=$(az monitor app-insights component show --resource-group "$rg_name" --query "[].name" --output tsv 2>/dev/null || true)
    for ai in $APP_INSIGHTS; do
        log "Deleting Application Insights: $ai"
        az monitor app-insights component delete --resource-group "$rg_name" --app "$ai" || true
    done
    
    # Delete Log Analytics Workspaces
    LOG_WORKSPACES=$(az monitor log-analytics workspace list --resource-group "$rg_name" --query "[].name" --output tsv)
    for workspace in $LOG_WORKSPACES; do
        log "Deleting Log Analytics Workspace: $workspace"
        az monitor log-analytics workspace delete --resource-group "$rg_name" --workspace-name "$workspace" --yes || true
    done
    
    # Delete Storage Accounts (might contain data)
    STORAGE_ACCOUNTS=$(az storage account list --resource-group "$rg_name" --query "[].name" --output tsv)
    for storage in $STORAGE_ACCOUNTS; do
        log "Deleting Storage Account: $storage"
        az storage account delete --resource-group "$rg_name" --name "$storage" --yes || true
    done
    
    # Wait a bit for resources to be cleaned up
    log "Waiting for resources to be deleted..."
    sleep 30
    
    # Delete the resource group itself
    log "Deleting resource group: $rg_name"
    az group delete --name "$rg_name" --yes --no-wait
    
    success "Resource group deletion initiated: $rg_name"
}

# Process each resource group
for RG in $RESOURCE_GROUPS_TO_DELETE; do
    if az group exists --name "$RG" --output tsv 2>/dev/null; then
        delete_resource_group "$RG"
    else
        warning "Resource group '$RG' does not exist or was already deleted"
    fi
done

# =============================================================================
# Cleanup Verification
# =============================================================================

log "Verifying cleanup..."

# Wait for resource group deletions to complete
sleep 10

for RG in $RESOURCE_GROUPS_TO_DELETE; do
    if az group exists --name "$RG" --output tsv 2>/dev/null; then
        warning "Resource group '$RG' still exists (deletion in progress)"
    else
        success "Resource group '$RG' successfully deleted"
    fi
done

# =============================================================================
# Additional Cleanup Tasks
# =============================================================================

log "Performing additional cleanup tasks..."

# Clean up Azure AD applications if any were created
log "Checking for Azure AD applications..."
AD_APPS=$(az ad app list --display-name "*rightsizing*" --query "[].appId" --output tsv 2>/dev/null || true)
if [[ -n "$AD_APPS" ]]; then
    for app_id in $AD_APPS; do
        log "Deleting Azure AD application: $app_id"
        az ad app delete --id "$app_id" 2>/dev/null || true
    done
fi

# Clean up service principals
log "Checking for service principals..."
SERVICE_PRINCIPALS=$(az ad sp list --display-name "*rightsizing*" --query "[].appId" --output tsv 2>/dev/null || true)
if [[ -n "$SERVICE_PRINCIPALS" ]]; then
    for sp_id in $SERVICE_PRINCIPALS; do
        log "Deleting service principal: $sp_id"
        az ad sp delete --id "$sp_id" 2>/dev/null || true
    done
fi

# Clean up role assignments
log "Checking for custom role assignments..."
ROLE_ASSIGNMENTS=$(az role assignment list --assignee "$(az account show --query user.name --output tsv)" --query "[?roleDefinitionName=='Rightsizing Operator'].id" --output tsv 2>/dev/null || true)
if [[ -n "$ROLE_ASSIGNMENTS" ]]; then
    for assignment in $ROLE_ASSIGNMENTS; do
        log "Deleting role assignment: $assignment"
        az role assignment delete --ids "$assignment" 2>/dev/null || true
    done
fi

# Clean up temporary files
log "Cleaning up temporary files..."
rm -rf ./azd-rightsizing 2>/dev/null || true
rm -rf /tmp/rightsizing-* 2>/dev/null || true

success "Additional cleanup completed"

# =============================================================================
# Final Verification and Summary
# =============================================================================

log "Final verification..."

# Check if any resources still exist
REMAINING_GROUPS=""
for RG in $RESOURCE_GROUPS_TO_DELETE; do
    if az group exists --name "$RG" --output tsv 2>/dev/null; then
        REMAINING_GROUPS="$REMAINING_GROUPS $RG"
    fi
done

# Summary
echo ""
echo "==============================================================================="
echo "CLEANUP SUMMARY"
echo "==============================================================================="

if [[ -n "$REMAINING_GROUPS" ]]; then
    warning "The following resource groups are still being deleted:"
    for RG in $REMAINING_GROUPS; do
        echo "  - $RG (deletion in progress)"
    done
    echo ""
    echo "Note: Azure resource group deletion can take several minutes to complete."
    echo "You can check the status in the Azure portal or by running:"
    echo "  az group exists --name <resource-group-name>"
else
    success "All resource groups have been successfully deleted!"
fi

echo ""
echo "Cleanup completed for Azure Resource Rightsizing solution."
echo "All associated resources have been removed or are being removed."
echo ""
echo "If you need to redeploy, run: ./deploy.sh"
echo "==============================================================================="

success "Cleanup script completed successfully!"