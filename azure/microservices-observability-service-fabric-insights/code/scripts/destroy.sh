#!/bin/bash

# Azure Service Fabric Microservices Monitoring - Cleanup Script
# This script safely removes all resources created by the deployment script

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
    exit 1
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1${NC}"
}

# Check if running in dry-run mode
DRY_RUN=false
if [[ "${1:-}" == "--dry-run" ]]; then
    DRY_RUN=true
    warn "Running in DRY-RUN mode - no resources will be deleted"
fi

# Check if running in force mode (skip confirmations)
FORCE_MODE=false
if [[ "${1:-}" == "--force" ]] || [[ "${2:-}" == "--force" ]]; then
    FORCE_MODE=true
    warn "Running in FORCE mode - skipping confirmation prompts"
fi

# Banner
echo -e "${RED}"
echo "========================================================"
echo "  Azure Service Fabric Microservices Monitoring"
echo "  CLEANUP SCRIPT"
echo "========================================================"
echo -e "${NC}"

# Prerequisites check
log "Checking prerequisites..."

# Check if Azure CLI is installed
if ! command -v az &> /dev/null; then
    error "Azure CLI is not installed. Please install it first."
fi

# Check if user is logged in
if ! az account show &> /dev/null; then
    error "Not logged in to Azure. Please run 'az login' first."
fi

# Get subscription info
SUBSCRIPTION_ID=$(az account show --query id --output tsv)
SUBSCRIPTION_NAME=$(az account show --query name --output tsv)
log "Using subscription: $SUBSCRIPTION_NAME ($SUBSCRIPTION_ID)"

# Function to safely delete resource with retry logic
safe_delete() {
    local resource_type="$1"
    local resource_name="$2"
    local delete_command="$3"
    local max_retries=3
    local retry_count=0
    
    info "Deleting $resource_type: $resource_name"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "DRY-RUN: $delete_command"
        return 0
    fi
    
    while [[ $retry_count -lt $max_retries ]]; do
        if eval "$delete_command" 2>/dev/null; then
            log "✅ Successfully deleted $resource_type: $resource_name"
            return 0
        else
            retry_count=$((retry_count + 1))
            if [[ $retry_count -lt $max_retries ]]; then
                warn "Failed to delete $resource_type: $resource_name (attempt $retry_count/$max_retries). Retrying in 10 seconds..."
                sleep 10
            else
                warn "❌ Failed to delete $resource_type: $resource_name after $max_retries attempts"
                return 1
            fi
        fi
    done
}

# Function to check if resource exists
resource_exists() {
    local check_command="$1"
    eval "$check_command" &> /dev/null
    return $?
}

# Try to load deployment info from file
DEPLOYMENT_INFO_FILE=""
if [[ -f ~/microservices-monitoring-config/deployment-info.txt ]]; then
    DEPLOYMENT_INFO_FILE=~/microservices-monitoring-config/deployment-info.txt
    info "Found deployment info file: $DEPLOYMENT_INFO_FILE"
elif [[ -f ./deployment-info.txt ]]; then
    DEPLOYMENT_INFO_FILE=./deployment-info.txt
    info "Found deployment info file: $DEPLOYMENT_INFO_FILE"
fi

# Extract resource names from deployment info or prompt user
if [[ -n "$DEPLOYMENT_INFO_FILE" ]]; then
    info "Loading resource information from deployment file..."
    RESOURCE_GROUP=$(grep "Resource Group:" "$DEPLOYMENT_INFO_FILE" | cut -d' ' -f3)
    LOCATION=$(grep "Location:" "$DEPLOYMENT_INFO_FILE" | cut -d' ' -f2)
    SF_CLUSTER_NAME=$(grep "Service Fabric Cluster:" "$DEPLOYMENT_INFO_FILE" | cut -d' ' -f4)
    APP_INSIGHTS_NAME=$(grep "Application Insights:" "$DEPLOYMENT_INFO_FILE" | cut -d' ' -f3)
    FUNCTION_APP_NAME=$(grep "Function App:" "$DEPLOYMENT_INFO_FILE" | cut -d' ' -f3)
    STORAGE_ACCOUNT_NAME=$(grep "Storage Account:" "$DEPLOYMENT_INFO_FILE" | cut -d' ' -f3)
    EVENT_HUB_NAMESPACE=$(grep "Event Hub Namespace:" "$DEPLOYMENT_INFO_FILE" | cut -d' ' -f4)
    LOG_ANALYTICS_NAME=$(grep "Log Analytics Workspace:" "$DEPLOYMENT_INFO_FILE" | cut -d' ' -f4)
else
    warn "No deployment info file found. You'll need to provide resource names manually."
    echo
    
    # Prompt for resource group name
    if [[ -z "${RESOURCE_GROUP:-}" ]]; then
        read -p "Enter Resource Group name to delete: " RESOURCE_GROUP
        if [[ -z "$RESOURCE_GROUP" ]]; then
            error "Resource Group name is required"
        fi
    fi
    
    # Check if resource group exists
    if ! resource_exists "az group show --name $RESOURCE_GROUP"; then
        error "Resource group '$RESOURCE_GROUP' does not exist"
    fi
    
    # Get resource information from Azure
    info "Discovering resources in resource group: $RESOURCE_GROUP"
    LOCATION=$(az group show --name "$RESOURCE_GROUP" --query location --output tsv)
fi

# Display resources to be deleted
echo
warn "The following resources will be PERMANENTLY DELETED:"
echo
info "Resource Group: ${RESOURCE_GROUP:-Unknown}"
info "Location: ${LOCATION:-Unknown}"
if [[ -n "$DEPLOYMENT_INFO_FILE" ]]; then
    info "Service Fabric Cluster: ${SF_CLUSTER_NAME:-Unknown}"
    info "Application Insights: ${APP_INSIGHTS_NAME:-Unknown}"
    info "Function App: ${FUNCTION_APP_NAME:-Unknown}"
    info "Storage Account: ${STORAGE_ACCOUNT_NAME:-Unknown}"
    info "Event Hub Namespace: ${EVENT_HUB_NAMESPACE:-Unknown}"
    info "Log Analytics Workspace: ${LOG_ANALYTICS_NAME:-Unknown}"
else
    info "All resources in the resource group will be deleted"
fi
echo

# Confirmation prompt
if [[ "$FORCE_MODE" == "false" && "$DRY_RUN" == "false" ]]; then
    warn "THIS ACTION CANNOT BE UNDONE!"
    echo
    read -p "Are you sure you want to delete all these resources? (type 'yes' to confirm): " -r
    echo
    if [[ "$REPLY" != "yes" ]]; then
        log "Cleanup cancelled by user."
        exit 0
    fi
    
    echo
    read -p "Are you ABSOLUTELY sure? This will delete everything! (type 'DELETE' to confirm): " -r
    echo
    if [[ "$REPLY" != "DELETE" ]]; then
        log "Cleanup cancelled by user."
        exit 0
    fi
fi

# Start cleanup process
log "Starting cleanup process..."

# If we have specific resource names, delete them individually first
if [[ -n "$DEPLOYMENT_INFO_FILE" ]]; then
    
    # Step 1: Delete Service Fabric Cluster (takes longest, start first)
    if [[ -n "${SF_CLUSTER_NAME:-}" ]]; then
        if resource_exists "az sf managed-cluster show --resource-group $RESOURCE_GROUP --cluster-name $SF_CLUSTER_NAME"; then
            warn "Deleting Service Fabric cluster - this may take 10-15 minutes..."
            safe_delete "Service Fabric Cluster" "$SF_CLUSTER_NAME" \
                "az sf managed-cluster delete --resource-group $RESOURCE_GROUP --cluster-name $SF_CLUSTER_NAME --yes"
        else
            info "Service Fabric cluster '$SF_CLUSTER_NAME' not found, skipping..."
        fi
    fi
    
    # Step 2: Delete Function App
    if [[ -n "${FUNCTION_APP_NAME:-}" ]]; then
        if resource_exists "az functionapp show --name $FUNCTION_APP_NAME --resource-group $RESOURCE_GROUP"; then
            safe_delete "Function App" "$FUNCTION_APP_NAME" \
                "az functionapp delete --name $FUNCTION_APP_NAME --resource-group $RESOURCE_GROUP"
        else
            info "Function App '$FUNCTION_APP_NAME' not found, skipping..."
        fi
    fi
    
    # Step 3: Delete Storage Account
    if [[ -n "${STORAGE_ACCOUNT_NAME:-}" ]]; then
        if resource_exists "az storage account show --name $STORAGE_ACCOUNT_NAME --resource-group $RESOURCE_GROUP"; then
            safe_delete "Storage Account" "$STORAGE_ACCOUNT_NAME" \
                "az storage account delete --name $STORAGE_ACCOUNT_NAME --resource-group $RESOURCE_GROUP --yes"
        else
            info "Storage Account '$STORAGE_ACCOUNT_NAME' not found, skipping..."
        fi
    fi
    
    # Step 4: Delete Event Hub Namespace
    if [[ -n "${EVENT_HUB_NAMESPACE:-}" ]]; then
        if resource_exists "az eventhubs namespace show --resource-group $RESOURCE_GROUP --name $EVENT_HUB_NAMESPACE"; then
            safe_delete "Event Hub Namespace" "$EVENT_HUB_NAMESPACE" \
                "az eventhubs namespace delete --resource-group $RESOURCE_GROUP --name $EVENT_HUB_NAMESPACE"
        else
            info "Event Hub Namespace '$EVENT_HUB_NAMESPACE' not found, skipping..."
        fi
    fi
    
    # Step 5: Delete Application Insights
    if [[ -n "${APP_INSIGHTS_NAME:-}" ]]; then
        if resource_exists "az monitor app-insights component show --app $APP_INSIGHTS_NAME --resource-group $RESOURCE_GROUP"; then
            safe_delete "Application Insights" "$APP_INSIGHTS_NAME" \
                "az monitor app-insights component delete --app $APP_INSIGHTS_NAME --resource-group $RESOURCE_GROUP"
        else
            info "Application Insights '$APP_INSIGHTS_NAME' not found, skipping..."
        fi
    fi
    
    # Step 6: Delete Log Analytics Workspace
    if [[ -n "${LOG_ANALYTICS_NAME:-}" ]]; then
        if resource_exists "az monitor log-analytics workspace show --resource-group $RESOURCE_GROUP --workspace-name $LOG_ANALYTICS_NAME"; then
            safe_delete "Log Analytics Workspace" "$LOG_ANALYTICS_NAME" \
                "az monitor log-analytics workspace delete --resource-group $RESOURCE_GROUP --workspace-name $LOG_ANALYTICS_NAME --yes"
        else
            info "Log Analytics Workspace '$LOG_ANALYTICS_NAME' not found, skipping..."
        fi
    fi
    
    # Step 7: Delete any remaining alerts
    info "Checking for remaining alerts..."
    if [[ "$DRY_RUN" == "false" ]]; then
        ALERTS=$(az monitor metrics alert list --resource-group "$RESOURCE_GROUP" --query "[].name" --output tsv 2>/dev/null || echo "")
        if [[ -n "$ALERTS" ]]; then
            echo "$ALERTS" | while read -r alert; do
                safe_delete "Alert" "$alert" \
                    "az monitor metrics alert delete --resource-group $RESOURCE_GROUP --name '$alert'"
            done
        fi
        
        SCHEDULED_QUERIES=$(az monitor scheduled-query list --resource-group "$RESOURCE_GROUP" --query "[].name" --output tsv 2>/dev/null || echo "")
        if [[ -n "$SCHEDULED_QUERIES" ]]; then
            echo "$SCHEDULED_QUERIES" | while read -r query; do
                safe_delete "Scheduled Query" "$query" \
                    "az monitor scheduled-query delete --resource-group $RESOURCE_GROUP --name '$query'"
            done
        fi
    fi
    
else
    # If we don't have specific resource names, just list all resources
    info "Discovering all resources in resource group..."
    if [[ "$DRY_RUN" == "false" ]]; then
        RESOURCES=$(az resource list --resource-group "$RESOURCE_GROUP" --query "[].{name:name,type:type}" --output tsv 2>/dev/null || echo "")
        if [[ -n "$RESOURCES" ]]; then
            info "Found the following resources:"
            echo "$RESOURCES" | while IFS=$'\t' read -r name type; do
                info "  - $name ($type)"
            done
        else
            info "No resources found in resource group"
        fi
    fi
fi

# Step 8: Delete the entire resource group
log "Deleting resource group and all remaining resources..."
if resource_exists "az group show --name $RESOURCE_GROUP"; then
    safe_delete "Resource Group" "$RESOURCE_GROUP" \
        "az group delete --name $RESOURCE_GROUP --yes --no-wait"
    
    if [[ "$DRY_RUN" == "false" ]]; then
        info "Resource group deletion initiated. This may take several minutes to complete."
        info "You can check the status with: az group show --name $RESOURCE_GROUP"
    fi
else
    warn "Resource group '$RESOURCE_GROUP' does not exist"
fi

# Step 9: Clean up local configuration files
log "Cleaning up local configuration files..."
if [[ -d ~/microservices-monitoring-config ]]; then
    if [[ "$DRY_RUN" == "false" ]]; then
        rm -rf ~/microservices-monitoring-config
        log "✅ Local configuration directory removed"
    else
        info "DRY-RUN: Would remove ~/microservices-monitoring-config"
    fi
else
    info "No local configuration directory found"
fi

# Step 10: Final verification
log "Performing final verification..."
if [[ "$DRY_RUN" == "false" ]]; then
    # Check if resource group still exists (it might during deletion)
    if resource_exists "az group show --name $RESOURCE_GROUP"; then
        DELETION_STATUS=$(az group show --name "$RESOURCE_GROUP" --query "properties.provisioningState" --output tsv 2>/dev/null || echo "NotFound")
        if [[ "$DELETION_STATUS" == "Deleting" ]]; then
            warn "Resource group is being deleted. This process may take several minutes."
            info "You can monitor the progress with: az group show --name $RESOURCE_GROUP"
        else
            warn "Resource group still exists. Some resources may not have been deleted."
        fi
    else
        log "✅ Resource group has been deleted"
    fi
    
    # Check for any remaining resources in the subscription with our tags
    info "Checking for any remaining tagged resources..."
    REMAINING_RESOURCES=$(az resource list --tag purpose=microservices-monitoring --query "[].{name:name,resourceGroup:resourceGroup,type:type}" --output tsv 2>/dev/null || echo "")
    if [[ -n "$REMAINING_RESOURCES" ]]; then
        warn "Found remaining resources with monitoring tags:"
        echo "$REMAINING_RESOURCES" | while IFS=$'\t' read -r name rg type; do
            warn "  - $name in $rg ($type)"
        done
        warn "You may want to clean these up manually"
    else
        log "✅ No remaining tagged resources found"
    fi
else
    info "DRY-RUN: Skipping verification"
fi

# Summary
echo
if [[ "$DRY_RUN" == "true" ]]; then
    echo -e "${YELLOW}========================================================"
    echo "  DRY-RUN COMPLETE"
    echo "========================================================${NC}"
    echo
    info "This was a dry-run. No resources were actually deleted."
    info "To perform the actual cleanup, run: ./destroy.sh"
else
    echo -e "${GREEN}========================================================"
    echo "  CLEANUP COMPLETE"
    echo "========================================================${NC}"
    echo
    log "Azure Service Fabric Microservices Monitoring resources have been deleted!"
    echo
    info "Summary:"
    info "✅ Resource group deletion initiated"
    info "✅ Individual resources cleaned up"
    info "✅ Local configuration files removed"
    info "✅ Alerts and monitoring rules deleted"
    echo
    info "Note: Resource group deletion may take several minutes to complete fully."
    info "You can verify completion with: az group show --name $RESOURCE_GROUP"
    echo
    log "Cleanup completed successfully!"
fi