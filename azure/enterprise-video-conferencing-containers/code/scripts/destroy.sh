#!/bin/bash

# destroy.sh - Cleanup script for Azure Video Conferencing Application
# This script removes all resources created by the deployment script

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/destroy.log"
FORCE=${FORCE:-false}
DRY_RUN=${DRY_RUN:-false}

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}" | tee -a "$LOG_FILE"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}" | tee -a "$LOG_FILE"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}" | tee -a "$LOG_FILE"
    exit 1
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1${NC}" | tee -a "$LOG_FILE"
}

# Display script header
display_header() {
    echo -e "${RED}"
    echo "================================================================="
    echo "  Azure Video Conferencing Application Cleanup Script"
    echo "================================================================="
    echo -e "${NC}"
    echo "This script will remove:"
    echo "- Auto-scaling configuration"
    echo "- Azure Web App for Containers"
    echo "- Azure App Service Plan"
    echo "- Azure Container Registry"
    echo "- Azure Communication Services"
    echo "- Azure Blob Storage"
    echo "- Application Insights"
    echo "- Resource Group (if empty)"
    echo ""
    echo -e "${RED}WARNING: This action cannot be undone!${NC}"
    echo ""
}

# Prerequisites check
check_prerequisites() {
    info "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        error "Azure CLI is not installed. Please install it first."
    fi
    
    # Check if logged in to Azure
    if ! az account show &> /dev/null; then
        error "Not logged in to Azure. Please run 'az login' first."
    fi
    
    log "Prerequisites check completed successfully"
}

# Load configuration from deployment
load_configuration() {
    info "Loading configuration..."
    
    local CONFIG_FILE="$SCRIPT_DIR/../deployment-config.json"
    
    if [[ -f "$CONFIG_FILE" ]]; then
        # Load configuration from JSON file
        export RESOURCE_GROUP=$(jq -r '.resourceGroup' "$CONFIG_FILE")
        export LOCATION=$(jq -r '.location' "$CONFIG_FILE")
        export SUBSCRIPTION_ID=$(jq -r '.subscriptionId' "$CONFIG_FILE")
        export STORAGE_ACCOUNT=$(jq -r '.storageAccount' "$CONFIG_FILE")
        export COMMUNICATION_SERVICE=$(jq -r '.communicationService' "$CONFIG_FILE")
        export WEBAPP_NAME=$(jq -r '.webAppName' "$CONFIG_FILE")
        export CONTAINER_REGISTRY=$(jq -r '.containerRegistry' "$CONFIG_FILE")
        export APP_SERVICE_PLAN=$(jq -r '.appServicePlan' "$CONFIG_FILE")
        export AUTOSCALE_NAME=$(jq -r '.autoscaleName' "$CONFIG_FILE")
        export APPINSIGHTS_NAME=$(jq -r '.appInsightsName' "$CONFIG_FILE")
        
        log "Configuration loaded from $CONFIG_FILE"
    else
        warn "Configuration file not found. Using environment variables or defaults."
        
        # Set default values or get from environment
        export RESOURCE_GROUP="${RESOURCE_GROUP:-rg-video-conferencing-app}"
        export LOCATION="${LOCATION:-eastus}"
        export SUBSCRIPTION_ID="${SUBSCRIPTION_ID:-$(az account show --query id --output tsv)}"
        
        # Try to detect resources based on naming patterns
        if [[ -z "${RANDOM_SUFFIX:-}" ]]; then
            warn "RANDOM_SUFFIX not set. Will try to detect resources."
        fi
        
        # Set resource names with fallback detection
        export STORAGE_ACCOUNT="${STORAGE_ACCOUNT:-}"
        export COMMUNICATION_SERVICE="${COMMUNICATION_SERVICE:-}"
        export WEBAPP_NAME="${WEBAPP_NAME:-}"
        export CONTAINER_REGISTRY="${CONTAINER_REGISTRY:-}"
        export APP_SERVICE_PLAN="${APP_SERVICE_PLAN:-}"
        export AUTOSCALE_NAME="${AUTOSCALE_NAME:-video-conferencing-autoscale}"
        export APPINSIGHTS_NAME="${APPINSIGHTS_NAME:-video-conferencing-insights}"
    fi
    
    # Configuration summary
    log "Configuration:"
    log "  Resource Group: $RESOURCE_GROUP"
    log "  Location: $LOCATION"
    log "  Subscription ID: $SUBSCRIPTION_ID"
    log "  Storage Account: $STORAGE_ACCOUNT"
    log "  Communication Service: $COMMUNICATION_SERVICE"
    log "  Web App Name: $WEBAPP_NAME"
    log "  Container Registry: $CONTAINER_REGISTRY"
    log "  App Service Plan: $APP_SERVICE_PLAN"
    log "  Auto-scale Name: $AUTOSCALE_NAME"
    log "  App Insights Name: $APPINSIGHTS_NAME"
}

# Detect resources if not configured
detect_resources() {
    info "Detecting resources in resource group..."
    
    if ! az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        warn "Resource group $RESOURCE_GROUP does not exist"
        return
    fi
    
    # Detect storage accounts
    if [[ -z "$STORAGE_ACCOUNT" ]]; then
        STORAGE_ACCOUNT=$(az storage account list \
            --resource-group "$RESOURCE_GROUP" \
            --query "[?contains(name, 'stvideoconf')].name" \
            --output tsv | head -1)
        
        if [[ -n "$STORAGE_ACCOUNT" ]]; then
            log "Detected storage account: $STORAGE_ACCOUNT"
        fi
    fi
    
    # Detect communication services
    if [[ -z "$COMMUNICATION_SERVICE" ]]; then
        COMMUNICATION_SERVICE=$(az communication list \
            --resource-group "$RESOURCE_GROUP" \
            --query "[?contains(name, 'cs-video-conferencing')].name" \
            --output tsv | head -1)
        
        if [[ -n "$COMMUNICATION_SERVICE" ]]; then
            log "Detected communication service: $COMMUNICATION_SERVICE"
        fi
    fi
    
    # Detect web apps
    if [[ -z "$WEBAPP_NAME" ]]; then
        WEBAPP_NAME=$(az webapp list \
            --resource-group "$RESOURCE_GROUP" \
            --query "[?contains(name, 'webapp-video-conferencing')].name" \
            --output tsv | head -1)
        
        if [[ -n "$WEBAPP_NAME" ]]; then
            log "Detected web app: $WEBAPP_NAME"
        fi
    fi
    
    # Detect container registries
    if [[ -z "$CONTAINER_REGISTRY" ]]; then
        CONTAINER_REGISTRY=$(az acr list \
            --resource-group "$RESOURCE_GROUP" \
            --query "[?contains(name, 'acrvideo')].name" \
            --output tsv | head -1)
        
        if [[ -n "$CONTAINER_REGISTRY" ]]; then
            log "Detected container registry: $CONTAINER_REGISTRY"
        fi
    fi
    
    # Detect app service plans
    if [[ -z "$APP_SERVICE_PLAN" ]]; then
        APP_SERVICE_PLAN=$(az appservice plan list \
            --resource-group "$RESOURCE_GROUP" \
            --query "[?contains(name, 'asp-video-conferencing')].name" \
            --output tsv | head -1)
        
        if [[ -n "$APP_SERVICE_PLAN" ]]; then
            log "Detected app service plan: $APP_SERVICE_PLAN"
        fi
    fi
}

# Confirmation prompt
confirm_deletion() {
    if [[ "$FORCE" == "true" ]]; then
        log "FORCE mode enabled - skipping confirmation"
        return
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY RUN mode enabled - no resources will be deleted"
        return
    fi
    
    echo ""
    echo -e "${RED}You are about to DELETE the following resources:${NC}"
    echo "  Resource Group: $RESOURCE_GROUP"
    [[ -n "$STORAGE_ACCOUNT" ]] && echo "  Storage Account: $STORAGE_ACCOUNT"
    [[ -n "$COMMUNICATION_SERVICE" ]] && echo "  Communication Service: $COMMUNICATION_SERVICE"
    [[ -n "$WEBAPP_NAME" ]] && echo "  Web App: $WEBAPP_NAME"
    [[ -n "$CONTAINER_REGISTRY" ]] && echo "  Container Registry: $CONTAINER_REGISTRY"
    [[ -n "$APP_SERVICE_PLAN" ]] && echo "  App Service Plan: $APP_SERVICE_PLAN"
    [[ -n "$AUTOSCALE_NAME" ]] && echo "  Auto-scale: $AUTOSCALE_NAME"
    [[ -n "$APPINSIGHTS_NAME" ]] && echo "  Application Insights: $APPINSIGHTS_NAME"
    echo ""
    echo -e "${RED}This action cannot be undone!${NC}"
    echo ""
    read -p "Are you sure you want to continue? (type 'yes' to confirm): " -r
    
    if [[ ! $REPLY =~ ^yes$ ]]; then
        log "Deletion cancelled by user"
        exit 0
    fi
    
    log "Deletion confirmed by user"
}

# Remove auto-scaling configuration
remove_auto_scaling() {
    info "Removing auto-scaling configuration..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY RUN: Would remove auto-scaling configuration"
        return
    fi
    
    if [[ -n "$AUTOSCALE_NAME" ]]; then
        if az monitor autoscale show --resource-group "$RESOURCE_GROUP" --name "$AUTOSCALE_NAME" &> /dev/null; then
            az monitor autoscale delete \
                --resource-group "$RESOURCE_GROUP" \
                --name "$AUTOSCALE_NAME"
            
            log "Auto-scaling configuration removed: $AUTOSCALE_NAME"
        else
            warn "Auto-scaling configuration $AUTOSCALE_NAME not found"
        fi
    else
        warn "Auto-scaling name not configured"
    fi
}

# Remove Web App
remove_web_app() {
    info "Removing Web App..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY RUN: Would remove web app"
        return
    fi
    
    if [[ -n "$WEBAPP_NAME" ]]; then
        if az webapp show --name "$WEBAPP_NAME" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
            az webapp delete \
                --name "$WEBAPP_NAME" \
                --resource-group "$RESOURCE_GROUP"
            
            log "Web App removed: $WEBAPP_NAME"
        else
            warn "Web App $WEBAPP_NAME not found"
        fi
    else
        warn "Web App name not configured"
    fi
}

# Remove App Service Plan
remove_app_service_plan() {
    info "Removing App Service Plan..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY RUN: Would remove app service plan"
        return
    fi
    
    if [[ -n "$APP_SERVICE_PLAN" ]]; then
        if az appservice plan show --name "$APP_SERVICE_PLAN" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
            az appservice plan delete \
                --name "$APP_SERVICE_PLAN" \
                --resource-group "$RESOURCE_GROUP" \
                --yes
            
            log "App Service Plan removed: $APP_SERVICE_PLAN"
        else
            warn "App Service Plan $APP_SERVICE_PLAN not found"
        fi
    else
        warn "App Service Plan name not configured"
    fi
}

# Remove Container Registry
remove_container_registry() {
    info "Removing Container Registry..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY RUN: Would remove container registry"
        return
    fi
    
    if [[ -n "$CONTAINER_REGISTRY" ]]; then
        if az acr show --name "$CONTAINER_REGISTRY" &> /dev/null; then
            az acr delete \
                --name "$CONTAINER_REGISTRY" \
                --resource-group "$RESOURCE_GROUP" \
                --yes
            
            log "Container Registry removed: $CONTAINER_REGISTRY"
        else
            warn "Container Registry $CONTAINER_REGISTRY not found"
        fi
    else
        warn "Container Registry name not configured"
    fi
}

# Remove Communication Services
remove_communication_services() {
    info "Removing Communication Services..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY RUN: Would remove communication services"
        return
    fi
    
    if [[ -n "$COMMUNICATION_SERVICE" ]]; then
        if az communication show --name "$COMMUNICATION_SERVICE" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
            az communication delete \
                --name "$COMMUNICATION_SERVICE" \
                --resource-group "$RESOURCE_GROUP" \
                --yes
            
            log "Communication Services removed: $COMMUNICATION_SERVICE"
        else
            warn "Communication Service $COMMUNICATION_SERVICE not found"
        fi
    else
        warn "Communication Service name not configured"
    fi
}

# Remove Storage Account
remove_storage_account() {
    info "Removing Storage Account..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY RUN: Would remove storage account"
        return
    fi
    
    if [[ -n "$STORAGE_ACCOUNT" ]]; then
        if az storage account show --name "$STORAGE_ACCOUNT" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
            az storage account delete \
                --name "$STORAGE_ACCOUNT" \
                --resource-group "$RESOURCE_GROUP" \
                --yes
            
            log "Storage Account removed: $STORAGE_ACCOUNT"
        else
            warn "Storage Account $STORAGE_ACCOUNT not found"
        fi
    else
        warn "Storage Account name not configured"
    fi
}

# Remove Application Insights
remove_application_insights() {
    info "Removing Application Insights..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY RUN: Would remove application insights"
        return
    fi
    
    if [[ -n "$APPINSIGHTS_NAME" ]]; then
        if az monitor app-insights component show --app "$APPINSIGHTS_NAME" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
            az monitor app-insights component delete \
                --app "$APPINSIGHTS_NAME" \
                --resource-group "$RESOURCE_GROUP"
            
            log "Application Insights removed: $APPINSIGHTS_NAME"
        else
            warn "Application Insights $APPINSIGHTS_NAME not found"
        fi
    else
        warn "Application Insights name not configured"
    fi
}

# Remove remaining resources
remove_remaining_resources() {
    info "Checking for remaining resources..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY RUN: Would check for remaining resources"
        return
    fi
    
    # List remaining resources in the resource group
    local remaining_resources=$(az resource list \
        --resource-group "$RESOURCE_GROUP" \
        --query "[].{Name:name, Type:type}" \
        --output tsv 2>/dev/null || echo "")
    
    if [[ -n "$remaining_resources" ]]; then
        warn "Found remaining resources in resource group:"
        echo "$remaining_resources" | while read -r name type; do
            warn "  - $name ($type)"
        done
        
        # Ask if user wants to delete remaining resources
        if [[ "$FORCE" != "true" ]]; then
            read -p "Delete remaining resources? (y/N): " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                info "Deleting remaining resources..."
                echo "$remaining_resources" | while read -r name type; do
                    az resource delete \
                        --resource-group "$RESOURCE_GROUP" \
                        --name "$name" \
                        --resource-type "$type" \
                        --verbose || warn "Failed to delete $name"
                done
            fi
        fi
    else
        log "No remaining resources found in resource group"
    fi
}

# Remove Resource Group
remove_resource_group() {
    info "Removing Resource Group..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY RUN: Would remove resource group"
        return
    fi
    
    if az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        # Check if resource group is empty
        local resource_count=$(az resource list \
            --resource-group "$RESOURCE_GROUP" \
            --query "length([])" \
            --output tsv 2>/dev/null || echo "0")
        
        if [[ "$resource_count" -eq 0 ]]; then
            az group delete \
                --name "$RESOURCE_GROUP" \
                --yes \
                --no-wait
            
            log "Resource Group removal initiated: $RESOURCE_GROUP"
        else
            warn "Resource Group $RESOURCE_GROUP is not empty ($resource_count resources remaining)"
            if [[ "$FORCE" == "true" ]]; then
                warn "FORCE mode enabled - attempting to delete non-empty resource group"
                az group delete \
                    --name "$RESOURCE_GROUP" \
                    --yes \
                    --no-wait
                
                log "Resource Group removal initiated (forced): $RESOURCE_GROUP"
            else
                read -p "Force delete non-empty resource group? (y/N): " -n 1 -r
                echo
                if [[ $REPLY =~ ^[Yy]$ ]]; then
                    az group delete \
                        --name "$RESOURCE_GROUP" \
                        --yes \
                        --no-wait
                    
                    log "Resource Group removal initiated (forced): $RESOURCE_GROUP"
                else
                    warn "Resource Group $RESOURCE_GROUP was not deleted"
                fi
            fi
        fi
    else
        warn "Resource Group $RESOURCE_GROUP not found"
    fi
}

# Clean up local files
cleanup_local_files() {
    info "Cleaning up local files..."
    
    local APP_DIR="$SCRIPT_DIR/../video-conferencing-app"
    local CONFIG_FILE="$SCRIPT_DIR/../deployment-config.json"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY RUN: Would clean up local files"
        return
    fi
    
    # Remove application directory
    if [[ -d "$APP_DIR" ]]; then
        rm -rf "$APP_DIR"
        log "Removed application directory: $APP_DIR"
    fi
    
    # Remove configuration file
    if [[ -f "$CONFIG_FILE" ]]; then
        rm -f "$CONFIG_FILE"
        log "Removed configuration file: $CONFIG_FILE"
    fi
    
    # Remove log files older than 7 days
    find "$SCRIPT_DIR" -name "*.log" -type f -mtime +7 -delete 2>/dev/null || true
    
    log "Local cleanup completed"
}

# Display cleanup summary
display_summary() {
    echo ""
    echo -e "${GREEN}================================================================="
    echo "                    CLEANUP COMPLETED"
    echo -e "=================================================================${NC}"
    echo ""
    echo "Resources removed:"
    echo "  - Auto-scaling configuration: $AUTOSCALE_NAME"
    echo "  - Web App: $WEBAPP_NAME"
    echo "  - App Service Plan: $APP_SERVICE_PLAN"
    echo "  - Container Registry: $CONTAINER_REGISTRY"
    echo "  - Communication Service: $COMMUNICATION_SERVICE"
    echo "  - Storage Account: $STORAGE_ACCOUNT"
    echo "  - Application Insights: $APPINSIGHTS_NAME"
    echo "  - Resource Group: $RESOURCE_GROUP"
    echo ""
    echo "Local files cleaned up:"
    echo "  - Application directory"
    echo "  - Configuration file"
    echo "  - Old log files"
    echo ""
    echo "Note: Resource group deletion may take several minutes to complete."
    echo "You can check the status in the Azure portal."
    echo ""
}

# Main cleanup function
main() {
    # Initialize log file
    echo "Cleanup started at $(date)" > "$LOG_FILE"
    
    display_header
    
    # Check for dry run mode
    if [[ "$DRY_RUN" == "true" ]]; then
        warn "Running in DRY RUN mode - no resources will be deleted"
    fi
    
    # Execute cleanup steps
    check_prerequisites
    load_configuration
    detect_resources
    confirm_deletion
    remove_auto_scaling
    remove_web_app
    remove_app_service_plan
    remove_container_registry
    remove_communication_services
    remove_storage_account
    remove_application_insights
    remove_remaining_resources
    remove_resource_group
    cleanup_local_files
    display_summary
    
    log "Cleanup completed successfully!"
}

# Handle script interruption
trap 'error "Cleanup interrupted by user"' INT TERM

# Run main function
main "$@"