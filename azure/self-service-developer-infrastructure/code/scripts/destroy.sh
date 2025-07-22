#!/bin/bash

# Destroy Azure Dev Box and Deployment Environments Infrastructure
# This script safely removes all resources created by the deployment script

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Check if running in dry-run mode
DRY_RUN=${DRY_RUN:-false}
if [[ "$1" == "--dry-run" ]]; then
    DRY_RUN=true
    warning "Running in dry-run mode - no resources will be deleted"
fi

# Force mode (skip confirmations)
FORCE_MODE=${FORCE_MODE:-false}
if [[ "$1" == "--force" ]] || [[ "$2" == "--force" ]]; then
    FORCE_MODE=true
    warning "Running in force mode - skipping confirmations"
fi

# Prerequisites check
check_prerequisites() {
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
    
    success "Prerequisites check completed"
}

# Set environment variables
set_environment_variables() {
    log "Setting environment variables..."
    
    # Use same defaults as deploy script
    export RESOURCE_GROUP="${RESOURCE_GROUP:-rg-devinfra-demo}"
    export LOCATION="${LOCATION:-eastus}"
    export DEVCENTER_NAME="${DEVCENTER_NAME:-dc-selfservice-demo}"
    export PROJECT_NAME="${PROJECT_NAME:-proj-webapp-team}"
    
    # Get subscription ID
    export SUBSCRIPTION_ID=$(az account show --query id --output tsv)
    
    # Try to get the random suffix from existing resources
    local vnet_name=$(az network vnet list --resource-group "$RESOURCE_GROUP" --query "[?starts_with(name, 'vnet-devbox-')].name" -o tsv 2>/dev/null | head -1)
    if [[ -n "$vnet_name" ]]; then
        export RANDOM_SUFFIX=${vnet_name#vnet-devbox-}
        log "Detected random suffix from existing resources: $RANDOM_SUFFIX"
    else
        export RANDOM_SUFFIX="unknown"
        warning "Could not detect random suffix from existing resources"
    fi
    
    log "Resource Group: $RESOURCE_GROUP"
    log "Location: $LOCATION"
    log "DevCenter Name: $DEVCENTER_NAME"
    log "Project Name: $PROJECT_NAME"
    log "Subscription ID: $SUBSCRIPTION_ID"
    log "Random Suffix: $RANDOM_SUFFIX"
    
    success "Environment variables set"
}

# Confirmation prompt
confirm_destruction() {
    if [[ "$FORCE_MODE" == "true" ]]; then
        log "Force mode enabled - skipping confirmation"
        return 0
    fi
    
    echo ""
    warning "⚠️  WARNING: This will permanently delete all resources created by the deployment script"
    echo ""
    echo "Resources to be deleted:"
    echo "- Resource Group: $RESOURCE_GROUP"
    echo "- DevCenter: $DEVCENTER_NAME"
    echo "- Project: $PROJECT_NAME"
    echo "- All associated Dev Boxes and environments"
    echo "- All network resources"
    echo ""
    echo "This action cannot be undone!"
    echo ""
    
    read -p "Are you sure you want to proceed? (type 'yes' to confirm): " confirmation
    
    if [[ "$confirmation" != "yes" ]]; then
        log "Destruction cancelled by user"
        exit 0
    fi
    
    log "Destruction confirmed"
}

# List active Dev Boxes for user awareness
list_active_devboxes() {
    log "Checking for active Dev Boxes..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY RUN: Would check for active Dev Boxes"
        return 0
    fi
    
    # Check if resource group exists
    if ! az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        warning "Resource group $RESOURCE_GROUP does not exist"
        return 0
    fi
    
    # Check if project exists
    if ! az devcenter admin project show --name "$PROJECT_NAME" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        warning "Project $PROJECT_NAME does not exist"
        return 0
    fi
    
    # List active Dev Boxes
    local active_devboxes=$(az devcenter dev devbox list --project "$PROJECT_NAME" --dev-center "$DEVCENTER_NAME" --output json 2>/dev/null || echo "[]")
    local devbox_count=$(echo "$active_devboxes" | jq length 2>/dev/null || echo "0")
    
    if [[ "$devbox_count" -gt 0 ]]; then
        warning "Found $devbox_count active Dev Box(es) in project $PROJECT_NAME"
        echo "$active_devboxes" | jq -r '.[] | "- \(.name) (Status: \(.provisioningState))"' 2>/dev/null || echo "Unable to parse Dev Box details"
        echo ""
        
        if [[ "$FORCE_MODE" != "true" ]]; then
            read -p "Continue with deletion? These Dev Boxes will be permanently deleted (y/N): " continue_deletion
            if [[ "$continue_deletion" != "y" ]] && [[ "$continue_deletion" != "Y" ]]; then
                log "Destruction cancelled by user"
                exit 0
            fi
        fi
    else
        log "No active Dev Boxes found"
    fi
}

# Delete Dev Box pools and schedules
delete_devbox_pools() {
    log "Deleting Dev Box pools..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY RUN: Would delete Dev Box pools"
        return 0
    fi
    
    # Check if project exists
    if ! az devcenter admin project show --name "$PROJECT_NAME" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        warning "Project $PROJECT_NAME does not exist, skipping pool deletion"
        return 0
    fi
    
    # List all pools in the project
    local pools=$(az devcenter admin pool list --project "$PROJECT_NAME" --resource-group "$RESOURCE_GROUP" --query "[].name" -o tsv 2>/dev/null || echo "")
    
    if [[ -n "$pools" ]]; then
        for pool in $pools; do
            log "Deleting Dev Box pool: $pool"
            
            # Delete schedules first
            local schedules=$(az devcenter admin schedule list --pool-name "$pool" --project "$PROJECT_NAME" --resource-group "$RESOURCE_GROUP" --query "[].name" -o tsv 2>/dev/null || echo "")
            for schedule in $schedules; do
                log "Deleting schedule: $schedule"
                az devcenter admin schedule delete \
                    --name "$schedule" \
                    --pool-name "$pool" \
                    --project "$PROJECT_NAME" \
                    --resource-group "$RESOURCE_GROUP" \
                    --yes &> /dev/null || warning "Failed to delete schedule $schedule"
            done
            
            # Delete the pool
            az devcenter admin pool delete \
                --name "$pool" \
                --project "$PROJECT_NAME" \
                --resource-group "$RESOURCE_GROUP" \
                --yes &> /dev/null || warning "Failed to delete pool $pool"
        done
        success "Dev Box pools deleted"
    else
        log "No Dev Box pools found"
    fi
}

# Remove role assignments
remove_role_assignments() {
    log "Removing role assignments..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY RUN: Would remove role assignments"
        return 0
    fi
    
    # Check if project exists
    if ! az devcenter admin project show --name "$PROJECT_NAME" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        warning "Project $PROJECT_NAME does not exist, skipping role assignment removal"
        return 0
    fi
    
    # Get current user's object ID
    local current_user_id=$(az ad signed-in-user show --query id --output tsv)
    
    # Remove Dev Box User role
    local project_scope="/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.DevCenter/projects/$PROJECT_NAME"
    
    az role assignment delete \
        --assignee "$current_user_id" \
        --role "DevCenter Dev Box User" \
        --scope "$project_scope" &> /dev/null || log "Dev Box User role not found or already removed"
    
    # Remove Deployment Environments User role
    az role assignment delete \
        --assignee "$current_user_id" \
        --role "Deployment Environments User" \
        --scope "$project_scope" &> /dev/null || log "Deployment Environments User role not found or already removed"
    
    success "Role assignments removed"
}

# Delete project
delete_project() {
    log "Deleting project..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY RUN: Would delete project $PROJECT_NAME"
        return 0
    fi
    
    # Check if project exists
    if az devcenter admin project show --name "$PROJECT_NAME" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        log "Deleting project: $PROJECT_NAME"
        az devcenter admin project delete \
            --name "$PROJECT_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --yes
        success "Project deleted"
    else
        log "Project $PROJECT_NAME does not exist"
    fi
}

# Remove DevCenter permissions
remove_devcenter_permissions() {
    log "Removing DevCenter permissions..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY RUN: Would remove DevCenter permissions"
        return 0
    fi
    
    # Get DevCenter principal ID if it exists
    local devcenter_principal_id=$(az devcenter admin devcenter show \
        --name "$DEVCENTER_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --query identity.principalId \
        --output tsv 2>/dev/null || echo "")
    
    if [[ -n "$devcenter_principal_id" ]]; then
        log "Removing DevCenter permissions for principal: $devcenter_principal_id"
        
        # Remove Contributor role
        az role assignment delete \
            --assignee "$devcenter_principal_id" \
            --role "Contributor" \
            --scope "/subscriptions/$SUBSCRIPTION_ID" &> /dev/null || log "Contributor role not found or already removed"
        
        # Remove User Access Administrator role
        az role assignment delete \
            --assignee "$devcenter_principal_id" \
            --role "User Access Administrator" \
            --scope "/subscriptions/$SUBSCRIPTION_ID" &> /dev/null || log "User Access Administrator role not found or already removed"
        
        success "DevCenter permissions removed"
    else
        log "DevCenter principal ID not found"
    fi
}

# Delete Dev Box definitions
delete_devbox_definitions() {
    log "Deleting Dev Box definitions..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY RUN: Would delete Dev Box definitions"
        return 0
    fi
    
    # Check if DevCenter exists
    if ! az devcenter admin devcenter show --name "$DEVCENTER_NAME" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        warning "DevCenter $DEVCENTER_NAME does not exist, skipping definition deletion"
        return 0
    fi
    
    # List all Dev Box definitions
    local definitions=$(az devcenter admin devbox-definition list --dev-center "$DEVCENTER_NAME" --resource-group "$RESOURCE_GROUP" --query "[].name" -o tsv 2>/dev/null || echo "")
    
    if [[ -n "$definitions" ]]; then
        for definition in $definitions; do
            log "Deleting Dev Box definition: $definition"
            az devcenter admin devbox-definition delete \
                --name "$definition" \
                --dev-center "$DEVCENTER_NAME" \
                --resource-group "$RESOURCE_GROUP" \
                --yes &> /dev/null || warning "Failed to delete definition $definition"
        done
        success "Dev Box definitions deleted"
    else
        log "No Dev Box definitions found"
    fi
}

# Delete network resources
delete_network_resources() {
    log "Deleting network resources..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY RUN: Would delete network resources"
        return 0
    fi
    
    # Check if DevCenter exists
    if az devcenter admin devcenter show --name "$DEVCENTER_NAME" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        # Remove attached network connections
        local attached_networks=$(az devcenter admin attached-network list --dev-center "$DEVCENTER_NAME" --resource-group "$RESOURCE_GROUP" --query "[].name" -o tsv 2>/dev/null || echo "")
        for network in $attached_networks; do
            log "Detaching network connection: $network"
            az devcenter admin attached-network delete \
                --name "$network" \
                --dev-center "$DEVCENTER_NAME" \
                --resource-group "$RESOURCE_GROUP" \
                --yes &> /dev/null || warning "Failed to detach network $network"
        done
    fi
    
    # Delete network connections
    local nc_name="nc-devbox-$RANDOM_SUFFIX"
    if az devcenter admin network-connection show --name "$nc_name" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        log "Deleting network connection: $nc_name"
        az devcenter admin network-connection delete \
            --name "$nc_name" \
            --resource-group "$RESOURCE_GROUP" \
            --yes &> /dev/null || warning "Failed to delete network connection $nc_name"
    fi
    
    # Delete virtual network
    local vnet_name="vnet-devbox-$RANDOM_SUFFIX"
    if az network vnet show --name "$vnet_name" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        log "Deleting virtual network: $vnet_name"
        az network vnet delete \
            --name "$vnet_name" \
            --resource-group "$RESOURCE_GROUP" &> /dev/null || warning "Failed to delete virtual network $vnet_name"
    fi
    
    success "Network resources deleted"
}

# Delete catalogs
delete_catalogs() {
    log "Deleting catalogs..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY RUN: Would delete catalogs"
        return 0
    fi
    
    # Check if DevCenter exists
    if ! az devcenter admin devcenter show --name "$DEVCENTER_NAME" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        warning "DevCenter $DEVCENTER_NAME does not exist, skipping catalog deletion"
        return 0
    fi
    
    # List all catalogs
    local catalogs=$(az devcenter admin catalog list --dev-center "$DEVCENTER_NAME" --resource-group "$RESOURCE_GROUP" --query "[].name" -o tsv 2>/dev/null || echo "")
    
    if [[ -n "$catalogs" ]]; then
        for catalog in $catalogs; do
            log "Deleting catalog: $catalog"
            az devcenter admin catalog delete \
                --name "$catalog" \
                --dev-center "$DEVCENTER_NAME" \
                --resource-group "$RESOURCE_GROUP" \
                --yes &> /dev/null || warning "Failed to delete catalog $catalog"
        done
        success "Catalogs deleted"
    else
        log "No catalogs found"
    fi
}

# Delete environment types
delete_environment_types() {
    log "Deleting environment types..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY RUN: Would delete environment types"
        return 0
    fi
    
    # Check if DevCenter exists
    if ! az devcenter admin devcenter show --name "$DEVCENTER_NAME" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        warning "DevCenter $DEVCENTER_NAME does not exist, skipping environment type deletion"
        return 0
    fi
    
    # List all environment types
    local env_types=$(az devcenter admin environment-type list --dev-center "$DEVCENTER_NAME" --resource-group "$RESOURCE_GROUP" --query "[].name" -o tsv 2>/dev/null || echo "")
    
    if [[ -n "$env_types" ]]; then
        for env_type in $env_types; do
            log "Deleting environment type: $env_type"
            az devcenter admin environment-type delete \
                --name "$env_type" \
                --dev-center "$DEVCENTER_NAME" \
                --resource-group "$RESOURCE_GROUP" \
                --yes &> /dev/null || warning "Failed to delete environment type $env_type"
        done
        success "Environment types deleted"
    else
        log "No environment types found"
    fi
}

# Delete DevCenter
delete_devcenter() {
    log "Deleting DevCenter..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY RUN: Would delete DevCenter $DEVCENTER_NAME"
        return 0
    fi
    
    # Check if DevCenter exists
    if az devcenter admin devcenter show --name "$DEVCENTER_NAME" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        log "Deleting DevCenter: $DEVCENTER_NAME"
        az devcenter admin devcenter delete \
            --name "$DEVCENTER_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --yes
        success "DevCenter deleted"
    else
        log "DevCenter $DEVCENTER_NAME does not exist"
    fi
}

# Delete resource group
delete_resource_group() {
    log "Deleting resource group..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY RUN: Would delete resource group $RESOURCE_GROUP"
        return 0
    fi
    
    # Check if resource group exists
    if az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        log "Deleting resource group: $RESOURCE_GROUP"
        
        # Final confirmation for resource group deletion
        if [[ "$FORCE_MODE" != "true" ]]; then
            echo ""
            warning "⚠️  FINAL WARNING: About to delete entire resource group $RESOURCE_GROUP"
            echo "This will permanently delete ALL resources in the group, including any resources not created by this script."
            echo ""
            read -p "Are you absolutely sure? (type 'DELETE' to confirm): " final_confirmation
            
            if [[ "$final_confirmation" != "DELETE" ]]; then
                log "Resource group deletion cancelled by user"
                return 0
            fi
        fi
        
        az group delete \
            --name "$RESOURCE_GROUP" \
            --yes \
            --no-wait
        
        success "Resource group deletion initiated (running in background)"
        log "Full cleanup may take 10-15 minutes to complete"
    else
        log "Resource group $RESOURCE_GROUP does not exist"
    fi
}

# Validation
validate_cleanup() {
    log "Validating cleanup..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY RUN: Would validate cleanup"
        return 0
    fi
    
    # Check if DevCenter still exists
    if az devcenter admin devcenter show --name "$DEVCENTER_NAME" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        warning "DevCenter $DEVCENTER_NAME still exists"
    else
        success "DevCenter has been deleted"
    fi
    
    # Check if resource group still exists
    if az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        warning "Resource group $RESOURCE_GROUP still exists (deletion may be in progress)"
    else
        success "Resource group has been deleted"
    fi
    
    success "Cleanup validation completed"
}

# Main cleanup function
main() {
    log "Starting Azure Dev Box and Deployment Environments cleanup..."
    
    check_prerequisites
    set_environment_variables
    confirm_destruction
    list_active_devboxes
    delete_devbox_pools
    remove_role_assignments
    delete_project
    remove_devcenter_permissions
    delete_devbox_definitions
    delete_network_resources
    delete_catalogs
    delete_environment_types
    delete_devcenter
    delete_resource_group
    validate_cleanup
    
    success "Cleanup completed successfully!"
    log "Note: Some resources may take additional time to fully delete in the background"
}

# Handle script interruption
trap 'error "Script interrupted. Some resources may not have been deleted."; exit 1' INT TERM

# Run main function
main "$@"