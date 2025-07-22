#!/bin/bash

# Destroy Multi-Platform Push Notifications with Azure Notification Hubs and Azure Spring Apps
# This script removes all resources created by the deployment script

set -e
set -u
set -o pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/destroy.log"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${1}" | tee -a "$LOG_FILE"
}

# Error handler
error_exit() {
    log "${RED}❌ ERROR: $1${NC}"
    exit 1
}

# Check if running in dry-run mode
DRY_RUN=${DRY_RUN:-false}
if [[ "$DRY_RUN" == "true" ]]; then
    log "${YELLOW}🔍 Running in DRY-RUN mode - no resources will be deleted${NC}"
    AZ_CMD="echo [DRY-RUN] az"
else
    AZ_CMD="az"
fi

# Print banner
log "${RED}============================================${NC}"
log "${RED}  Azure Push Notification System Cleanup${NC}"
log "${RED}============================================${NC}"
log ""

# Check prerequisites
log "${BLUE}🔍 Checking prerequisites...${NC}"

# Check if Azure CLI is installed
if ! command -v az &> /dev/null; then
    error_exit "Azure CLI is not installed. Please install it from https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
fi

# Check if user is logged in
if ! az account show &> /dev/null; then
    error_exit "Not logged in to Azure. Please run 'az login' first"
fi

log "${GREEN}✅ Prerequisites check passed${NC}"

# Default values (should match deployment script)
RESOURCE_GROUP=${RESOURCE_GROUP:-"rg-pushnotif-demo"}
NOTIFICATION_HUB_NAMESPACE=${NOTIFICATION_HUB_NAMESPACE:-""}
NOTIFICATION_HUB_NAME=${NOTIFICATION_HUB_NAME:-"nh-multiplatform"}
SPRING_APPS_NAME=${SPRING_APPS_NAME:-""}
KEY_VAULT_NAME=${KEY_VAULT_NAME:-""}
APP_INSIGHTS_NAME=${APP_INSIGHTS_NAME:-"ai-pushnotif"}
SPRING_APP_NAME=${SPRING_APP_NAME:-"notification-api"}

# Display configuration
log "${BLUE}📋 Configuration:${NC}"
log "Resource Group: $RESOURCE_GROUP"
log "Notification Hub Namespace: $NOTIFICATION_HUB_NAMESPACE"
log "Notification Hub Name: $NOTIFICATION_HUB_NAME"
log "Spring Apps Name: $SPRING_APPS_NAME"
log "Key Vault Name: $KEY_VAULT_NAME"
log "Application Insights Name: $APP_INSIGHTS_NAME"
log "Spring App Name: $SPRING_APP_NAME"
log ""

# Check if resource group exists
if ! az group show --name "$RESOURCE_GROUP" &> /dev/null; then
    log "${YELLOW}⚠️  Resource group '$RESOURCE_GROUP' does not exist${NC}"
    log "${GREEN}✅ Nothing to clean up${NC}"
    exit 0
fi

# Auto-discover resource names if not provided
if [[ -z "$NOTIFICATION_HUB_NAMESPACE" ]] || [[ -z "$SPRING_APPS_NAME" ]] || [[ -z "$KEY_VAULT_NAME" ]]; then
    log "${BLUE}🔍 Auto-discovering resource names...${NC}"
    
    # Get Notification Hub namespace
    if [[ -z "$NOTIFICATION_HUB_NAMESPACE" ]]; then
        NOTIFICATION_HUB_NAMESPACE=$(az notification-hub namespace list \
            --resource-group "$RESOURCE_GROUP" \
            --query "[0].name" -o tsv 2>/dev/null || echo "")
        if [[ -n "$NOTIFICATION_HUB_NAMESPACE" ]]; then
            log "Found Notification Hub namespace: $NOTIFICATION_HUB_NAMESPACE"
        fi
    fi
    
    # Get Spring Apps service
    if [[ -z "$SPRING_APPS_NAME" ]]; then
        SPRING_APPS_NAME=$(az spring list \
            --resource-group "$RESOURCE_GROUP" \
            --query "[0].name" -o tsv 2>/dev/null || echo "")
        if [[ -n "$SPRING_APPS_NAME" ]]; then
            log "Found Spring Apps service: $SPRING_APPS_NAME"
        fi
    fi
    
    # Get Key Vault
    if [[ -z "$KEY_VAULT_NAME" ]]; then
        KEY_VAULT_NAME=$(az keyvault list \
            --resource-group "$RESOURCE_GROUP" \
            --query "[0].name" -o tsv 2>/dev/null || echo "")
        if [[ -n "$KEY_VAULT_NAME" ]]; then
            log "Found Key Vault: $KEY_VAULT_NAME"
        fi
    fi
fi

# Function to check if resource exists
resource_exists() {
    local resource_type=$1
    local resource_name=$2
    local resource_group=$3
    
    if [[ -z "$resource_name" ]]; then
        return 1
    fi
    
    case $resource_type in
        "group")
            $AZ_CMD group show --name "$resource_name" &> /dev/null
            ;;
        "keyvault")
            $AZ_CMD keyvault show --name "$resource_name" &> /dev/null
            ;;
        "notification-hub-namespace")
            $AZ_CMD notification-hub namespace show --name "$resource_name" --resource-group "$resource_group" &> /dev/null
            ;;
        "notification-hub")
            $AZ_CMD notification-hub show --name "$resource_name" --namespace-name "$NOTIFICATION_HUB_NAMESPACE" --resource-group "$resource_group" &> /dev/null
            ;;
        "spring")
            $AZ_CMD spring show --name "$resource_name" --resource-group "$resource_group" &> /dev/null
            ;;
        "spring-app")
            $AZ_CMD spring app show --name "$resource_name" --service "$SPRING_APPS_NAME" --resource-group "$resource_group" &> /dev/null
            ;;
        "app-insights")
            $AZ_CMD monitor app-insights component show --app "$resource_name" --resource-group "$resource_group" &> /dev/null
            ;;
        *)
            return 1
            ;;
    esac
}

# Function to safely delete resource
safe_delete() {
    local resource_type=$1
    local resource_name=$2
    local resource_group=$3
    local additional_params=${4:-""}
    
    if [[ -z "$resource_name" ]]; then
        log "${YELLOW}⚠️  Skipping $resource_type deletion - name not provided${NC}"
        return 0
    fi
    
    if resource_exists "$resource_type" "$resource_name" "$resource_group"; then
        log "${BLUE}🗑️  Deleting $resource_type: $resource_name${NC}"
        
        case $resource_type in
            "spring-app")
                $AZ_CMD spring app delete \
                    --name "$resource_name" \
                    --service "$SPRING_APPS_NAME" \
                    --resource-group "$resource_group" \
                    --yes
                ;;
            "spring")
                $AZ_CMD spring delete \
                    --name "$resource_name" \
                    --resource-group "$resource_group" \
                    --yes
                ;;
            "notification-hub")
                $AZ_CMD notification-hub delete \
                    --name "$resource_name" \
                    --namespace-name "$NOTIFICATION_HUB_NAMESPACE" \
                    --resource-group "$resource_group"
                ;;
            "notification-hub-namespace")
                $AZ_CMD notification-hub namespace delete \
                    --name "$resource_name" \
                    --resource-group "$resource_group"
                ;;
            "keyvault")
                $AZ_CMD keyvault delete \
                    --name "$resource_name" \
                    --resource-group "$resource_group"
                
                # Purge the key vault to allow name reuse
                if [[ "$DRY_RUN" != "true" ]]; then
                    log "${BLUE}🗑️  Purging Key Vault: $resource_name${NC}"
                    $AZ_CMD keyvault purge \
                        --name "$resource_name" \
                        --no-wait || log "${YELLOW}⚠️  Key Vault purge failed or already purged${NC}"
                fi
                ;;
            "app-insights")
                $AZ_CMD monitor app-insights component delete \
                    --app "$resource_name" \
                    --resource-group "$resource_group"
                ;;
            *)
                log "${YELLOW}⚠️  Unknown resource type: $resource_type${NC}"
                return 1
                ;;
        esac
        
        log "${GREEN}✅ $resource_type deleted successfully${NC}"
    else
        log "${YELLOW}⚠️  $resource_type '$resource_name' does not exist or already deleted${NC}"
    fi
}

# Warning and confirmation
log "${RED}⚠️  WARNING: This will permanently delete all resources!${NC}"
log "${RED}⚠️  This action cannot be undone!${NC}"
log ""
log "Resources to be deleted:"
log "- Resource Group: $RESOURCE_GROUP"
log "- Spring Apps Service: $SPRING_APPS_NAME"
log "- Spring App: $SPRING_APP_NAME"
log "- Notification Hub Namespace: $NOTIFICATION_HUB_NAMESPACE"
log "- Notification Hub: $NOTIFICATION_HUB_NAME"
log "- Key Vault: $KEY_VAULT_NAME"
log "- Application Insights: $APP_INSIGHTS_NAME"
log "- All Log Analytics workspaces in the resource group"
log ""

# Multiple confirmation prompts for safety
if [[ "$DRY_RUN" != "true" ]]; then
    read -p "Are you sure you want to delete all resources? Type 'yes' to confirm: " -r
    if [[ "$REPLY" != "yes" ]]; then
        log "${YELLOW}Cleanup cancelled${NC}"
        exit 0
    fi
    
    read -p "This will permanently delete the resource group '$RESOURCE_GROUP' and ALL its contents. Type 'DELETE' to confirm: " -r
    if [[ "$REPLY" != "DELETE" ]]; then
        log "${YELLOW}Cleanup cancelled${NC}"
        exit 0
    fi
fi

log "${BLUE}🧹 Starting cleanup process...${NC}"

# Method 1: Individual resource deletion (more granular control)
if [[ "${DELETE_METHOD:-"group"}" == "individual" ]]; then
    log "${BLUE}🔄 Using individual resource deletion method${NC}"
    
    # Delete Spring App first
    safe_delete "spring-app" "$SPRING_APP_NAME" "$RESOURCE_GROUP"
    
    # Delete Spring Apps service
    safe_delete "spring" "$SPRING_APPS_NAME" "$RESOURCE_GROUP"
    
    # Delete Notification Hub
    safe_delete "notification-hub" "$NOTIFICATION_HUB_NAME" "$RESOURCE_GROUP"
    
    # Delete Notification Hub namespace
    safe_delete "notification-hub-namespace" "$NOTIFICATION_HUB_NAMESPACE" "$RESOURCE_GROUP"
    
    # Delete Key Vault
    safe_delete "keyvault" "$KEY_VAULT_NAME" "$RESOURCE_GROUP"
    
    # Delete Application Insights
    safe_delete "app-insights" "$APP_INSIGHTS_NAME" "$RESOURCE_GROUP"
    
    # Delete Log Analytics workspaces
    log "${BLUE}🗑️  Deleting Log Analytics workspaces...${NC}"
    if [[ "$DRY_RUN" != "true" ]]; then
        LAW_NAMES=$(az monitor log-analytics workspace list \
            --resource-group "$RESOURCE_GROUP" \
            --query "[].name" -o tsv 2>/dev/null || echo "")
        
        for law_name in $LAW_NAMES; do
            log "${BLUE}🗑️  Deleting Log Analytics workspace: $law_name${NC}"
            $AZ_CMD monitor log-analytics workspace delete \
                --workspace-name "$law_name" \
                --resource-group "$RESOURCE_GROUP" \
                --yes
        done
    fi
    
    # Finally delete the resource group
    log "${BLUE}🗑️  Deleting Resource Group: $RESOURCE_GROUP${NC}"
    $AZ_CMD group delete \
        --name "$RESOURCE_GROUP" \
        --yes \
        --no-wait

else
    # Method 2: Delete entire resource group (faster, simpler)
    log "${BLUE}🔄 Using resource group deletion method${NC}"
    
    # Delete the entire resource group
    log "${BLUE}🗑️  Deleting Resource Group: $RESOURCE_GROUP${NC}"
    $AZ_CMD group delete \
        --name "$RESOURCE_GROUP" \
        --yes \
        --no-wait
    
    # Purge Key Vault if we know its name
    if [[ -n "$KEY_VAULT_NAME" && "$DRY_RUN" != "true" ]]; then
        log "${BLUE}🗑️  Purging Key Vault: $KEY_VAULT_NAME${NC}"
        $AZ_CMD keyvault purge \
            --name "$KEY_VAULT_NAME" \
            --no-wait 2>/dev/null || log "${YELLOW}⚠️  Key Vault purge failed or already purged${NC}"
    fi
fi

# Clean up local files
log "${BLUE}🧹 Cleaning up local files...${NC}"
if [[ -f "${SCRIPT_DIR}/notification-service" ]]; then
    rm -rf "${SCRIPT_DIR}/notification-service"
    log "${GREEN}✅ Local notification service files removed${NC}"
fi

# Verification
log "${BLUE}🔍 Verifying cleanup...${NC}"
if [[ "$DRY_RUN" != "true" ]]; then
    sleep 5  # Give Azure time to process the deletion
    
    if ! az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        log "${GREEN}✅ Resource group '$RESOURCE_GROUP' has been deleted${NC}"
    else
        log "${YELLOW}⚠️  Resource group '$RESOURCE_GROUP' still exists - deletion may be in progress${NC}"
        log "You can check the status with: az group show --name $RESOURCE_GROUP"
    fi
else
    log "${YELLOW}[DRY-RUN] Resource group would be deleted${NC}"
fi

log ""
log "${GREEN}🎉 Cleanup completed successfully!${NC}"
log ""
log "${BLUE}📋 Summary:${NC}"
log "=================================="
log "Resource Group: $RESOURCE_GROUP - Deleted"
log "Spring Apps Service: $SPRING_APPS_NAME - Deleted"
log "Spring App: $SPRING_APP_NAME - Deleted"
log "Notification Hub Namespace: $NOTIFICATION_HUB_NAMESPACE - Deleted"
log "Notification Hub: $NOTIFICATION_HUB_NAME - Deleted"
log "Key Vault: $KEY_VAULT_NAME - Deleted and Purged"
log "Application Insights: $APP_INSIGHTS_NAME - Deleted"
log "Log Analytics Workspaces: All deleted"
log ""
log "${YELLOW}⚠️  Note: Some resources may take a few minutes to be fully deleted${NC}"
log "${YELLOW}⚠️  Key Vault purge may take up to 90 days to complete${NC}"
log ""
log "${GREEN}✅ Cleanup log saved to: $LOG_FILE${NC}"

# Final safety check
if [[ "$DRY_RUN" != "true" ]]; then
    log ""
    log "${BLUE}🔍 Final verification in 30 seconds...${NC}"
    sleep 30
    
    if ! az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        log "${GREEN}✅ Final verification: Resource group has been successfully deleted${NC}"
    else
        log "${YELLOW}⚠️  Final verification: Resource group still exists - deletion may be in progress${NC}"
        log "Monitor deletion status with: az group show --name $RESOURCE_GROUP"
    fi
fi