#!/bin/bash

# Azure Content Moderation Cleanup Script
# Recipe: Automated Content Safety Moderation with Logic Apps
# Version: 1.0
# Description: Safely removes all content moderation infrastructure from Azure

set -e  # Exit on any error
set -u  # Exit on undefined variables
set -o pipefail  # Exit on pipe failures

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

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Banner
echo -e "${RED}"
echo "=================================================="
echo "  Azure Content Moderation Cleanup Script"
echo "=================================================="
echo -e "${NC}"

# Check if running in dry-run mode
DRY_RUN=${DRY_RUN:-false}
if [[ "$DRY_RUN" == "true" ]]; then
    warning "Running in DRY-RUN mode - no resources will be deleted"
fi

# Force mode for non-interactive cleanup
FORCE_MODE=${FORCE_MODE:-false}

# Default values
DEFAULT_RESOURCE_GROUP="rg-content-moderation"

# Try to load configuration from deployment
if [[ -f ".deployment_config" ]]; then
    log "Loading deployment configuration..."
    # shellcheck source=/dev/null
    source ".deployment_config"
    success "Configuration loaded from .deployment_config"
else
    warning "No deployment configuration found. Using defaults and environment variables."
fi

# Allow override via environment variables
RESOURCE_GROUP=${RESOURCE_GROUP:-$DEFAULT_RESOURCE_GROUP}

# Prerequisites check
log "Checking prerequisites..."

# Check if Azure CLI is installed
if ! command -v az &> /dev/null; then
    error "Azure CLI is not installed. Please install it from https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
    exit 1
fi

# Check if user is logged in
if ! az account show &> /dev/null; then
    error "Please log in to Azure CLI first: az login"
    exit 1
fi

# Get current subscription info
SUBSCRIPTION_ID=$(az account show --query id -o tsv)
SUBSCRIPTION_NAME=$(az account show --query name -o tsv)
log "Using subscription: ${SUBSCRIPTION_NAME} (${SUBSCRIPTION_ID})"

# Check if resource group exists
if ! az group exists --name "${RESOURCE_GROUP}" --output tsv | grep -q "true"; then
    warning "Resource group '${RESOURCE_GROUP}' does not exist. Nothing to clean up."
    exit 0
fi

# Get list of resources in the group
log "Scanning resource group '${RESOURCE_GROUP}'..."
RESOURCE_LIST=$(az resource list --resource-group "${RESOURCE_GROUP}" --query "[].{name:name, type:type}" -o tsv)

if [[ -z "$RESOURCE_LIST" ]]; then
    warning "No resources found in resource group '${RESOURCE_GROUP}'"
    
    if [[ "$DRY_RUN" != "true" ]]; then
        log "Deleting empty resource group..."
        az group delete --name "${RESOURCE_GROUP}" --yes --no-wait
        success "Empty resource group deletion initiated"
    else
        log "Would delete empty resource group"
    fi
    exit 0
fi

# Display resources to be deleted
echo -e "\n${YELLOW}Resources to be deleted:${NC}"
echo "$RESOURCE_LIST" | while IFS=$'\t' read -r name type; do
    echo "  - $name ($type)"
done

# Count total resources
RESOURCE_COUNT=$(echo "$RESOURCE_LIST" | wc -l)
log "Found ${RESOURCE_COUNT} resources in resource group '${RESOURCE_GROUP}'"

# Confirmation prompt
if [[ "$FORCE_MODE" != "true" && "$DRY_RUN" != "true" ]]; then
    echo -e "\n${RED}WARNING: This will permanently delete all resources in the resource group!${NC}"
    echo -e "${YELLOW}Are you sure you want to continue? (yes/no)${NC}"
    
    read -r response
    if [[ ! "$response" =~ ^[Yy][Ee][Ss]$ ]]; then
        log "Cleanup cancelled by user."
        exit 0
    fi
    
    echo -e "\n${RED}This action cannot be undone. Type 'DELETE' to confirm:${NC}"
    read -r confirmation
    if [[ "$confirmation" != "DELETE" ]]; then
        log "Cleanup cancelled. Confirmation not received."
        exit 0
    fi
fi

# Function to execute commands with dry-run support
execute_command() {
    local cmd="$1"
    local description="$2"
    
    log "${description}..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "  [DRY-RUN] Would execute: $cmd"
        return 0
    fi
    
    if eval "$cmd"; then
        success "${description} completed"
        return 0
    else
        error "${description} failed"
        return 1
    fi
}

# Function to wait for resource deletion
wait_for_deletion() {
    local resource_group="$1"
    local max_wait=300  # 5 minutes
    local wait_time=0
    
    log "Waiting for resource deletion to complete..."
    
    while [[ $wait_time -lt $max_wait ]]; do
        if ! az group exists --name "$resource_group" --output tsv | grep -q "true"; then
            success "Resource group deletion completed"
            return 0
        fi
        
        sleep 10
        wait_time=$((wait_time + 10))
        echo -n "."
    done
    
    warning "Resource deletion is taking longer than expected. Check Azure portal for status."
    return 1
}

# Function to check for protected resources
check_protected_resources() {
    local resource_group="$1"
    
    log "Checking for protected resources..."
    
    # Check for locks on the resource group
    LOCKS=$(az lock list --resource-group "$resource_group" --query "[].name" -o tsv 2>/dev/null || echo "")
    
    if [[ -n "$LOCKS" ]]; then
        warning "Found resource locks that may prevent deletion:"
        echo "$LOCKS" | while read -r lock; do
            echo "  - $lock"
        done
        
        if [[ "$DRY_RUN" != "true" ]]; then
            echo -e "\n${YELLOW}Remove these locks before proceeding? (y/N)${NC}"
            read -r response
            if [[ "$response" =~ ^[Yy]$ ]]; then
                echo "$LOCKS" | while read -r lock; do
                    az lock delete --name "$lock" --resource-group "$resource_group"
                done
                success "Resource locks removed"
            else
                error "Cannot proceed with locks in place. Please remove them manually."
                exit 1
            fi
        fi
    fi
}

# Function to backup important data
backup_data() {
    local resource_group="$1"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "Would check for data backup opportunities"
        return 0
    fi
    
    log "Checking for data that might need backup..."
    
    # Check for storage accounts with data
    STORAGE_ACCOUNTS=$(az storage account list --resource-group "$resource_group" --query "[].name" -o tsv 2>/dev/null || echo "")
    
    if [[ -n "$STORAGE_ACCOUNTS" ]]; then
        warning "Found storage accounts with potential data:"
        echo "$STORAGE_ACCOUNTS" | while read -r account; do
            echo "  - $account"
        done
        
        echo -e "\n${YELLOW}Do you want to backup storage account data? (y/N)${NC}"
        read -r response
        if [[ "$response" =~ ^[Yy]$ ]]; then
            warning "Manual backup required. Please backup your data before proceeding."
            echo "Press Enter to continue after backing up data..."
            read -r
        fi
    fi
}

# Function to clean up specific resource types in order
cleanup_resources_ordered() {
    local resource_group="$1"
    
    log "Starting ordered resource cleanup..."
    
    # 1. Delete Event Grid subscriptions first
    log "Deleting Event Grid subscriptions..."
    EVENT_SUBSCRIPTIONS=$(az eventgrid event-subscription list --resource-group "$resource_group" --query "[].name" -o tsv 2>/dev/null || echo "")
    if [[ -n "$EVENT_SUBSCRIPTIONS" ]]; then
        echo "$EVENT_SUBSCRIPTIONS" | while read -r subscription; do
            if [[ "$DRY_RUN" != "true" ]]; then
                az eventgrid event-subscription delete --name "$subscription" --resource-group "$resource_group" || true
            else
                log "Would delete Event Grid subscription: $subscription"
            fi
        done
    fi
    
    # 2. Delete diagnostic settings
    log "Deleting diagnostic settings..."
    if [[ "$DRY_RUN" != "true" ]]; then
        # Get Logic App resource ID if available
        if [[ -n "${LOGIC_APP_NAME:-}" ]]; then
            LOGIC_APP_ID=$(az logic workflow show --name "${LOGIC_APP_NAME}" --resource-group "$resource_group" --query id -o tsv 2>/dev/null || echo "")
            if [[ -n "$LOGIC_APP_ID" ]]; then
                az monitor diagnostic-settings delete --name logic-app-diagnostics --resource "$LOGIC_APP_ID" 2>/dev/null || true
            fi
        fi
    else
        log "Would delete diagnostic settings"
    fi
    
    # 3. Delete Function Apps
    log "Deleting Function Apps..."
    FUNCTION_APPS=$(az functionapp list --resource-group "$resource_group" --query "[].name" -o tsv 2>/dev/null || echo "")
    if [[ -n "$FUNCTION_APPS" ]]; then
        echo "$FUNCTION_APPS" | while read -r app; do
            if [[ "$DRY_RUN" != "true" ]]; then
                az functionapp delete --name "$app" --resource-group "$resource_group" || true
            else
                log "Would delete Function App: $app"
            fi
        done
    fi
    
    # 4. Delete Logic Apps
    log "Deleting Logic Apps..."
    LOGIC_APPS=$(az logic workflow list --resource-group "$resource_group" --query "[].name" -o tsv 2>/dev/null || echo "")
    if [[ -n "$LOGIC_APPS" ]]; then
        echo "$LOGIC_APPS" | while read -r app; do
            if [[ "$DRY_RUN" != "true" ]]; then
                az logic workflow delete --name "$app" --resource-group "$resource_group" --yes || true
            else
                log "Would delete Logic App: $app"
            fi
        done
    fi
    
    # 5. Delete Event Grid topics
    log "Deleting Event Grid topics..."
    EVENT_TOPICS=$(az eventgrid topic list --resource-group "$resource_group" --query "[].name" -o tsv 2>/dev/null || echo "")
    if [[ -n "$EVENT_TOPICS" ]]; then
        echo "$EVENT_TOPICS" | while read -r topic; do
            if [[ "$DRY_RUN" != "true" ]]; then
                az eventgrid topic delete --name "$topic" --resource-group "$resource_group" || true
            else
                log "Would delete Event Grid topic: $topic"
            fi
        done
    fi
    
    # 6. Delete Cognitive Services accounts
    log "Deleting Cognitive Services accounts..."
    COGNITIVE_ACCOUNTS=$(az cognitiveservices account list --resource-group "$resource_group" --query "[].name" -o tsv 2>/dev/null || echo "")
    if [[ -n "$COGNITIVE_ACCOUNTS" ]]; then
        echo "$COGNITIVE_ACCOUNTS" | while read -r account; do
            if [[ "$DRY_RUN" != "true" ]]; then
                az cognitiveservices account delete --name "$account" --resource-group "$resource_group" || true
            else
                log "Would delete Cognitive Services account: $account"
            fi
        done
    fi
    
    # 7. Delete Log Analytics workspaces
    log "Deleting Log Analytics workspaces..."
    LOG_WORKSPACES=$(az monitor log-analytics workspace list --resource-group "$resource_group" --query "[].name" -o tsv 2>/dev/null || echo "")
    if [[ -n "$LOG_WORKSPACES" ]]; then
        echo "$LOG_WORKSPACES" | while read -r workspace; do
            if [[ "$DRY_RUN" != "true" ]]; then
                az monitor log-analytics workspace delete --workspace-name "$workspace" --resource-group "$resource_group" --yes || true
            else
                log "Would delete Log Analytics workspace: $workspace"
            fi
        done
    fi
    
    # 8. Delete storage accounts (last as they may be dependencies)
    log "Deleting storage accounts..."
    STORAGE_ACCOUNTS=$(az storage account list --resource-group "$resource_group" --query "[].name" -o tsv 2>/dev/null || echo "")
    if [[ -n "$STORAGE_ACCOUNTS" ]]; then
        echo "$STORAGE_ACCOUNTS" | while read -r account; do
            if [[ "$DRY_RUN" != "true" ]]; then
                az storage account delete --name "$account" --resource-group "$resource_group" --yes || true
            else
                log "Would delete Storage Account: $account"
            fi
        done
    fi
    
    success "Ordered resource cleanup completed"
}

# Main cleanup process
log "Starting Azure Content Moderation infrastructure cleanup..."

# Check for protected resources
check_protected_resources "$RESOURCE_GROUP"

# Backup data if needed
backup_data "$RESOURCE_GROUP"

# Perform ordered cleanup of individual resources
cleanup_resources_ordered "$RESOURCE_GROUP"

# Final resource group deletion
if [[ "$DRY_RUN" != "true" ]]; then
    log "Deleting resource group '${RESOURCE_GROUP}'..."
    
    # Check if resource group still exists and has resources
    if az group exists --name "${RESOURCE_GROUP}" --output tsv | grep -q "true"; then
        az group delete --name "${RESOURCE_GROUP}" --yes --no-wait
        success "Resource group deletion initiated"
        
        # Wait for deletion to complete
        wait_for_deletion "$RESOURCE_GROUP"
    else
        success "Resource group has already been deleted"
    fi
else
    log "Would delete resource group '${RESOURCE_GROUP}'"
fi

# Clean up local files
if [[ "$DRY_RUN" != "true" ]]; then
    log "Cleaning up local configuration files..."
    
    if [[ -f ".deployment_config" ]]; then
        rm -f ".deployment_config"
        success "Removed .deployment_config file"
    fi
    
    # Clean up any other temporary files
    rm -f "test-content.txt" 2>/dev/null || true
    
    success "Local cleanup completed"
else
    log "Would clean up local configuration files"
fi

# Display cleanup summary
echo -e "\n${GREEN}=================================================="
echo "        Cleanup Completed Successfully!"
echo -e "==================================================${NC}"
echo

if [[ "$DRY_RUN" != "true" ]]; then
    echo "Summary:"
    echo "  ✅ Resource group '${RESOURCE_GROUP}' deleted"
    echo "  ✅ All associated resources removed"
    echo "  ✅ Local configuration files cleaned up"
    echo
    echo "Verification:"
    echo "  - Check Azure portal to confirm resource deletion"
    echo "  - Review your subscription billing to ensure no unexpected charges"
    echo
    echo "Note: Some resources may take additional time to fully delete from Azure billing."
else
    echo "This was a dry-run. No resources were actually deleted."
    echo "To perform the actual cleanup, run: DRY_RUN=false ./destroy.sh"
    echo "To force cleanup without prompts, run: FORCE_MODE=true ./destroy.sh"
fi

success "Cleanup script completed successfully!"