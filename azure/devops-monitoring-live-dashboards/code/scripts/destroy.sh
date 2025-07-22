#!/bin/bash

# Azure DevOps Monitoring Dashboard - Cleanup Script
# This script removes all resources created by the deployment script including:
# - Azure SignalR Service
# - Azure Functions
# - Azure App Service and App Service Plan
# - Azure Storage Account
# - Azure Monitor alerts and action groups
# - Log Analytics workspace
# - Resource group (optional)

set -e  # Exit on any error

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
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️ $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ❌ $1${NC}"
}

# Check if running in dry-run mode
DRY_RUN=false
if [[ "$1" == "--dry-run" ]]; then
    DRY_RUN=true
    warning "Running in dry-run mode - no resources will be deleted"
fi

# Check if running in force mode (no confirmation prompts)
FORCE_MODE=false
if [[ "$1" == "--force" ]] || [[ "$2" == "--force" ]]; then
    FORCE_MODE=true
    warning "Running in force mode - no confirmation prompts"
fi

# Function to execute commands with dry-run support
execute_command() {
    local cmd="$1"
    local description="$2"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY-RUN] Would execute: $cmd"
        return 0
    else
        log "$description"
        eval "$cmd"
        return $?
    fi
}

# Function to confirm destructive actions
confirm_action() {
    local action="$1"
    
    if [[ "$FORCE_MODE" == "true" ]] || [[ "$DRY_RUN" == "true" ]]; then
        return 0
    fi
    
    echo -e "${YELLOW}WARNING: This will $action${NC}"
    read -p "Are you sure you want to continue? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log "Operation cancelled by user"
        exit 1
    fi
}

log "Starting Azure DevOps Monitoring Dashboard cleanup..."

# Prerequisites check
log "Checking prerequisites..."

# Check Azure CLI installation
if ! command -v az &> /dev/null; then
    error "Azure CLI is not installed. Please install it first."
    exit 1
fi

# Check Azure CLI login status
if ! az account show &> /dev/null; then
    error "Not logged into Azure. Please run 'az login' first."
    exit 1
fi

success "Prerequisites check completed"

# Try to load deployment information from file
if [[ -f "deployment-info.json" ]]; then
    log "Loading deployment information from deployment-info.json..."
    
    RESOURCE_GROUP=$(jq -r '.resourceGroup' deployment-info.json 2>/dev/null)
    SIGNALR_NAME=$(jq -r '.signalrName' deployment-info.json 2>/dev/null)
    FUNCTION_APP_NAME=$(jq -r '.functionAppName' deployment-info.json 2>/dev/null)
    WEB_APP_NAME=$(jq -r '.webAppName' deployment-info.json 2>/dev/null)
    STORAGE_ACCOUNT_NAME=$(jq -r '.storageAccountName' deployment-info.json 2>/dev/null)
    LOG_ANALYTICS_NAME=$(jq -r '.logAnalyticsName' deployment-info.json 2>/dev/null)
    APP_SERVICE_PLAN_NAME=$(jq -r '.appServicePlanName' deployment-info.json 2>/dev/null)
    
    success "Deployment information loaded from file"
else
    warning "deployment-info.json not found. Using environment variables or defaults."
fi

# Set default values if not provided
RESOURCE_GROUP=${RESOURCE_GROUP:-"rg-monitoring-dashboard"}

# Get subscription ID
SUBSCRIPTION_ID=$(az account show --query id --output tsv)
if [[ -z "$SUBSCRIPTION_ID" ]]; then
    error "Failed to get Azure subscription ID"
    exit 1
fi

log "Cleanup configuration:"
log "  Resource Group: $RESOURCE_GROUP"
log "  Subscription ID: $SUBSCRIPTION_ID"

# Check if resource group exists
if ! az group show --name "$RESOURCE_GROUP" &> /dev/null; then
    warning "Resource group '$RESOURCE_GROUP' does not exist. Nothing to clean up."
    exit 0
fi

# Get resource names if not loaded from file
if [[ -z "$SIGNALR_NAME" ]]; then
    log "Discovering resources in resource group..."
    
    # Get SignalR Service names
    SIGNALR_SERVICES=$(az signalr list --resource-group "$RESOURCE_GROUP" --query '[].name' --output tsv 2>/dev/null || echo "")
    
    # Get Function App names
    FUNCTION_APPS=$(az functionapp list --resource-group "$RESOURCE_GROUP" --query '[].name' --output tsv 2>/dev/null || echo "")
    
    # Get Web App names
    WEB_APPS=$(az webapp list --resource-group "$RESOURCE_GROUP" --query '[].name' --output tsv 2>/dev/null || echo "")
    
    # Get Storage Account names
    STORAGE_ACCOUNTS=$(az storage account list --resource-group "$RESOURCE_GROUP" --query '[].name' --output tsv 2>/dev/null || echo "")
    
    # Get Log Analytics workspace names
    LOG_ANALYTICS_WORKSPACES=$(az monitor log-analytics workspace list --resource-group "$RESOURCE_GROUP" --query '[].name' --output tsv 2>/dev/null || echo "")
    
    # Get App Service Plan names
    APP_SERVICE_PLANS=$(az appservice plan list --resource-group "$RESOURCE_GROUP" --query '[].name' --output tsv 2>/dev/null || echo "")
    
    success "Resource discovery completed"
fi

# Confirm cleanup action
confirm_action "permanently delete all monitoring dashboard resources in resource group '$RESOURCE_GROUP'"

# Remove Azure Monitor alerts first
log "Removing Azure Monitor alerts..."

# Get all metric alerts in the resource group
METRIC_ALERTS=$(az monitor metrics alert list --resource-group "$RESOURCE_GROUP" --query '[].name' --output tsv 2>/dev/null || echo "")

if [[ -n "$METRIC_ALERTS" ]]; then
    for alert in $METRIC_ALERTS; do
        execute_command "az monitor metrics alert delete --name '$alert' --resource-group '$RESOURCE_GROUP' --yes" \
            "Deleting metric alert: $alert"
    done
    success "Metric alerts removed"
else
    log "No metric alerts found to remove"
fi

# Remove action groups
log "Removing Azure Monitor action groups..."

ACTION_GROUPS=$(az monitor action-group list --resource-group "$RESOURCE_GROUP" --query '[].name' --output tsv 2>/dev/null || echo "")

if [[ -n "$ACTION_GROUPS" ]]; then
    for action_group in $ACTION_GROUPS; do
        execute_command "az monitor action-group delete --name '$action_group' --resource-group '$RESOURCE_GROUP' --yes" \
            "Deleting action group: $action_group"
    done
    success "Action groups removed"
else
    log "No action groups found to remove"
fi

# Remove Azure DevOps Service Hooks (manual instruction)
if [[ "$DRY_RUN" == "false" ]]; then
    warning "MANUAL CLEANUP REQUIRED:"
    warning "Please remove Azure DevOps Service Hooks manually:"
    warning "1. Go to your Azure DevOps project"
    warning "2. Navigate to Project Settings > Service hooks"
    warning "3. Delete any webhook configurations pointing to the Function App"
    warning "4. Look for webhooks containing 'func-monitor' or similar patterns"
    echo ""
fi

# Remove Web Apps
log "Removing Web Apps..."

if [[ -n "$WEB_APP_NAME" ]]; then
    execute_command "az webapp delete --name '$WEB_APP_NAME' --resource-group '$RESOURCE_GROUP' --yes" \
        "Deleting Web App: $WEB_APP_NAME"
elif [[ -n "$WEB_APPS" ]]; then
    for webapp in $WEB_APPS; do
        execute_command "az webapp delete --name '$webapp' --resource-group '$RESOURCE_GROUP' --yes" \
            "Deleting Web App: $webapp"
    done
fi

if [[ -n "$WEB_APP_NAME" ]] || [[ -n "$WEB_APPS" ]]; then
    success "Web Apps removed"
else
    log "No Web Apps found to remove"
fi

# Remove Function Apps
log "Removing Function Apps..."

if [[ -n "$FUNCTION_APP_NAME" ]]; then
    execute_command "az functionapp delete --name '$FUNCTION_APP_NAME' --resource-group '$RESOURCE_GROUP' --yes" \
        "Deleting Function App: $FUNCTION_APP_NAME"
elif [[ -n "$FUNCTION_APPS" ]]; then
    for functionapp in $FUNCTION_APPS; do
        execute_command "az functionapp delete --name '$functionapp' --resource-group '$RESOURCE_GROUP' --yes" \
            "Deleting Function App: $functionapp"
    done
fi

if [[ -n "$FUNCTION_APP_NAME" ]] || [[ -n "$FUNCTION_APPS" ]]; then
    success "Function Apps removed"
else
    log "No Function Apps found to remove"
fi

# Remove App Service Plans
log "Removing App Service Plans..."

if [[ -n "$APP_SERVICE_PLAN_NAME" ]]; then
    execute_command "az appservice plan delete --name '$APP_SERVICE_PLAN_NAME' --resource-group '$RESOURCE_GROUP' --yes" \
        "Deleting App Service Plan: $APP_SERVICE_PLAN_NAME"
elif [[ -n "$APP_SERVICE_PLANS" ]]; then
    for plan in $APP_SERVICE_PLANS; do
        execute_command "az appservice plan delete --name '$plan' --resource-group '$RESOURCE_GROUP' --yes" \
            "Deleting App Service Plan: $plan"
    done
fi

if [[ -n "$APP_SERVICE_PLAN_NAME" ]] || [[ -n "$APP_SERVICE_PLANS" ]]; then
    success "App Service Plans removed"
else
    log "No App Service Plans found to remove"
fi

# Remove SignalR Services
log "Removing SignalR Services..."

if [[ -n "$SIGNALR_NAME" ]]; then
    execute_command "az signalr delete --name '$SIGNALR_NAME' --resource-group '$RESOURCE_GROUP' --yes" \
        "Deleting SignalR Service: $SIGNALR_NAME"
elif [[ -n "$SIGNALR_SERVICES" ]]; then
    for signalr in $SIGNALR_SERVICES; do
        execute_command "az signalr delete --name '$signalr' --resource-group '$RESOURCE_GROUP' --yes" \
            "Deleting SignalR Service: $signalr"
    done
fi

if [[ -n "$SIGNALR_NAME" ]] || [[ -n "$SIGNALR_SERVICES" ]]; then
    success "SignalR Services removed"
else
    log "No SignalR Services found to remove"
fi

# Remove Storage Accounts
log "Removing Storage Accounts..."

if [[ -n "$STORAGE_ACCOUNT_NAME" ]]; then
    execute_command "az storage account delete --name '$STORAGE_ACCOUNT_NAME' --resource-group '$RESOURCE_GROUP' --yes" \
        "Deleting Storage Account: $STORAGE_ACCOUNT_NAME"
elif [[ -n "$STORAGE_ACCOUNTS" ]]; then
    for storage in $STORAGE_ACCOUNTS; do
        execute_command "az storage account delete --name '$storage' --resource-group '$RESOURCE_GROUP' --yes" \
            "Deleting Storage Account: $storage"
    done
fi

if [[ -n "$STORAGE_ACCOUNT_NAME" ]] || [[ -n "$STORAGE_ACCOUNTS" ]]; then
    success "Storage Accounts removed"
else
    log "No Storage Accounts found to remove"
fi

# Remove Log Analytics workspaces
log "Removing Log Analytics workspaces..."

if [[ -n "$LOG_ANALYTICS_NAME" ]]; then
    execute_command "az monitor log-analytics workspace delete --workspace-name '$LOG_ANALYTICS_NAME' --resource-group '$RESOURCE_GROUP' --yes" \
        "Deleting Log Analytics workspace: $LOG_ANALYTICS_NAME"
elif [[ -n "$LOG_ANALYTICS_WORKSPACES" ]]; then
    for workspace in $LOG_ANALYTICS_WORKSPACES; do
        execute_command "az monitor log-analytics workspace delete --workspace-name '$workspace' --resource-group '$RESOURCE_GROUP' --yes" \
            "Deleting Log Analytics workspace: $workspace"
    done
fi

if [[ -n "$LOG_ANALYTICS_NAME" ]] || [[ -n "$LOG_ANALYTICS_WORKSPACES" ]]; then
    success "Log Analytics workspaces removed"
else
    log "No Log Analytics workspaces found to remove"
fi

# Option to remove the entire resource group
if [[ "$DRY_RUN" == "false" ]]; then
    echo ""
    if [[ "$FORCE_MODE" == "true" ]]; then
        DELETE_RG="y"
    else
        echo -e "${YELLOW}Do you want to delete the entire resource group '$RESOURCE_GROUP'? (y/N): ${NC}"
        read -n 1 -r DELETE_RG
        echo
    fi
    
    if [[ $DELETE_RG =~ ^[Yy]$ ]]; then
        log "Deleting resource group '$RESOURCE_GROUP'..."
        
        # Final confirmation for resource group deletion
        if [[ "$FORCE_MODE" == "false" ]]; then
            echo -e "${RED}WARNING: This will permanently delete the entire resource group and ALL resources in it!${NC}"
            read -p "Are you absolutely sure? Type 'DELETE' to confirm: " -r
            echo
            if [[ $REPLY != "DELETE" ]]; then
                log "Resource group deletion cancelled"
                exit 1
            fi
        fi
        
        az group delete --name "$RESOURCE_GROUP" --yes --no-wait
        success "Resource group deletion initiated: $RESOURCE_GROUP"
        log "Note: Resource group deletion may take several minutes to complete"
    else
        log "Resource group '$RESOURCE_GROUP' kept (contains other resources)"
    fi
fi

# Clean up local files
if [[ "$DRY_RUN" == "false" ]]; then
    log "Cleaning up local files..."
    
    # Remove deployment info file if it exists
    if [[ -f "deployment-info.json" ]]; then
        rm -f deployment-info.json
        success "Removed deployment-info.json"
    fi
    
    # Remove any temporary files created during deployment
    rm -f function-app.zip dashboard-app.zip 2>/dev/null || true
    
    success "Local files cleaned up"
fi

# Verify cleanup
if [[ "$DRY_RUN" == "false" ]]; then
    log "Verifying cleanup..."
    
    # Check if resource group still exists and has resources
    if az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        REMAINING_RESOURCES=$(az resource list --resource-group "$RESOURCE_GROUP" --query 'length(@)' --output tsv 2>/dev/null || echo "0")
        
        if [[ "$REMAINING_RESOURCES" -eq "0" ]]; then
            success "Resource group is empty - cleanup completed successfully"
        else
            warning "Resource group still contains $REMAINING_RESOURCES resources"
            log "Remaining resources:"
            az resource list --resource-group "$RESOURCE_GROUP" --query '[].{Name:name,Type:type,Location:location}' --output table 2>/dev/null || true
        fi
    else
        success "Resource group has been deleted - cleanup completed successfully"
    fi
fi

# Display cleanup summary
log "Cleanup operation completed!"
echo ""
success "=== CLEANUP SUMMARY ==="
success "Resource Group: $RESOURCE_GROUP"

if [[ "$DRY_RUN" == "false" ]]; then
    success "✅ Azure Monitor alerts removed"
    success "✅ Action groups removed"
    success "✅ Web Apps removed"
    success "✅ Function Apps removed"
    success "✅ App Service Plans removed"
    success "✅ SignalR Services removed"
    success "✅ Storage Accounts removed"
    success "✅ Log Analytics workspaces removed"
    success "✅ Local files cleaned up"
    echo ""
    
    warning "MANUAL CLEANUP REQUIRED:"
    warning "- Remove Azure DevOps Service Hooks from your DevOps project"
    warning "- Review any remaining resources in other resource groups"
    echo ""
else
    success "Dry-run completed - no resources were actually deleted"
fi

success "Cleanup completed successfully! 🎉"