#!/bin/bash

# =============================================================================
# Azure Self-Healing Infrastructure Cleanup Script
# =============================================================================
# This script safely removes all resources created by the deployment script
# including Traffic Manager, Function Apps, Load Testing, and monitoring resources.
# =============================================================================

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
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

error() {
    echo -e "${RED}[ERROR] $1${NC}" >&2
}

success() {
    echo -e "${GREEN}[SUCCESS] $1${NC}"
}

warning() {
    echo -e "${YELLOW}[WARNING] $1${NC}"
}

# =============================================================================
# Load Configuration
# =============================================================================
load_configuration() {
    log "Loading deployment configuration..."
    
    if [ -f ".deployment_config" ]; then
        source .deployment_config
        success "Configuration loaded from .deployment_config"
    else
        error "Configuration file .deployment_config not found!"
        echo "Please run this script from the same directory where you ran deploy.sh"
        exit 1
    fi
    
    # Verify required variables are set
    REQUIRED_VARS=(
        "RESOURCE_GROUP"
        "SUBSCRIPTION_ID"
        "TRAFFIC_MANAGER_PROFILE"
        "FUNCTION_APP_NAME"
        "LOAD_TEST_RESOURCE"
    )
    
    for var in "${REQUIRED_VARS[@]}"; do
        if [ -z "${!var:-}" ]; then
            error "Required variable $var is not set in configuration"
            exit 1
        fi
    done
}

# =============================================================================
# Prerequisites Check
# =============================================================================
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        error "Azure CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if user is logged in
    if ! az account show &> /dev/null; then
        error "Please log in to Azure CLI first using 'az login'"
        exit 1
    fi
    
    # Verify subscription
    CURRENT_SUBSCRIPTION=$(az account show --query id --output tsv)
    if [ "$CURRENT_SUBSCRIPTION" != "$SUBSCRIPTION_ID" ]; then
        warning "Current subscription ($CURRENT_SUBSCRIPTION) differs from deployment subscription ($SUBSCRIPTION_ID)"
        read -p "Continue with current subscription? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log "Switching to deployment subscription..."
            az account set --subscription "$SUBSCRIPTION_ID"
        fi
    fi
    
    success "Prerequisites check completed"
}

# =============================================================================
# Confirmation Prompt
# =============================================================================
confirm_deletion() {
    echo ""
    echo "=============================================="
    echo "           RESOURCE DELETION WARNING"
    echo "=============================================="
    echo ""
    echo "This will permanently delete the following resources:"
    echo "  • Resource Group: ${RESOURCE_GROUP}"
    echo "  • Traffic Manager Profile: ${TRAFFIC_MANAGER_PROFILE}"
    echo "  • Function App: ${FUNCTION_APP_NAME}"
    echo "  • Load Testing Resource: ${LOAD_TEST_RESOURCE}"
    echo "  • All associated web apps, storage accounts, and monitoring resources"
    echo ""
    echo "⚠️  WARNING: This action cannot be undone!"
    echo ""
    
    read -p "Are you sure you want to proceed? (type 'DELETE' to confirm): " -r
    echo
    if [ "$REPLY" != "DELETE" ]; then
        log "Deletion cancelled by user"
        exit 0
    fi
    
    log "Deletion confirmed. Proceeding with cleanup..."
}

# =============================================================================
# Resource Existence Check
# =============================================================================
check_resource_existence() {
    log "Checking resource existence..."
    
    # Check if resource group exists
    if ! az group exists --name "$RESOURCE_GROUP"; then
        warning "Resource group $RESOURCE_GROUP does not exist"
        log "Nothing to clean up"
        exit 0
    fi
    
    success "Resource group $RESOURCE_GROUP exists"
}

# =============================================================================
# Alert Rules Cleanup
# =============================================================================
cleanup_alert_rules() {
    log "Cleaning up alert rules..."
    
    # Get all alert rules in the resource group
    ALERT_RULES=$(az monitor metrics alert list \
        --resource-group "$RESOURCE_GROUP" \
        --query '[].name' \
        --output tsv 2>/dev/null || echo "")
    
    if [ -n "$ALERT_RULES" ]; then
        while IFS= read -r alert_rule; do
            if [ -n "$alert_rule" ]; then
                log "Deleting alert rule: $alert_rule"
                az monitor metrics alert delete \
                    --name "$alert_rule" \
                    --resource-group "$RESOURCE_GROUP" \
                    --yes || warning "Failed to delete alert rule: $alert_rule"
            fi
        done <<< "$ALERT_RULES"
    else
        log "No alert rules found to delete"
    fi
    
    # Clean up action groups
    log "Cleaning up action groups..."
    ACTION_GROUPS=$(az monitor action-group list \
        --resource-group "$RESOURCE_GROUP" \
        --query '[].name' \
        --output tsv 2>/dev/null || echo "")
    
    if [ -n "$ACTION_GROUPS" ]; then
        while IFS= read -r action_group; do
            if [ -n "$action_group" ]; then
                log "Deleting action group: $action_group"
                az monitor action-group delete \
                    --name "$action_group" \
                    --resource-group "$RESOURCE_GROUP" || warning "Failed to delete action group: $action_group"
            fi
        done <<< "$ACTION_GROUPS"
    else
        log "No action groups found to delete"
    fi
    
    success "Alert rules and action groups cleanup completed"
}

# =============================================================================
# Function App Cleanup
# =============================================================================
cleanup_function_app() {
    log "Cleaning up Function App and related resources..."
    
    # Check if Function App exists
    if az functionapp show --name "$FUNCTION_APP_NAME" --resource-group "$RESOURCE_GROUP" &>/dev/null; then
        log "Removing Function App role assignments..."
        
        # Get Function App managed identity
        FUNCTION_IDENTITY=$(az functionapp identity show \
            --name "$FUNCTION_APP_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --query principalId --output tsv 2>/dev/null || echo "")
        
        if [ -n "$FUNCTION_IDENTITY" ]; then
            # Remove role assignments
            ROLE_ASSIGNMENTS=$(az role assignment list \
                --assignee "$FUNCTION_IDENTITY" \
                --query '[].id' \
                --output tsv 2>/dev/null || echo "")
            
            if [ -n "$ROLE_ASSIGNMENTS" ]; then
                while IFS= read -r assignment_id; do
                    if [ -n "$assignment_id" ]; then
                        log "Removing role assignment: $assignment_id"
                        az role assignment delete --ids "$assignment_id" || warning "Failed to remove role assignment"
                    fi
                done <<< "$ROLE_ASSIGNMENTS"
            fi
        fi
        
        # Delete Function App
        log "Deleting Function App: $FUNCTION_APP_NAME"
        az functionapp delete \
            --name "$FUNCTION_APP_NAME" \
            --resource-group "$RESOURCE_GROUP" || warning "Failed to delete Function App"
    else
        log "Function App $FUNCTION_APP_NAME not found"
    fi
    
    success "Function App cleanup completed"
}

# =============================================================================
# Load Testing Resource Cleanup
# =============================================================================
cleanup_load_testing() {
    log "Cleaning up Load Testing resource..."
    
    # Check if Load Testing resource exists
    if az load test show --name "$LOAD_TEST_RESOURCE" --resource-group "$RESOURCE_GROUP" &>/dev/null; then
        log "Deleting Load Testing resource: $LOAD_TEST_RESOURCE"
        az load test delete \
            --name "$LOAD_TEST_RESOURCE" \
            --resource-group "$RESOURCE_GROUP" \
            --yes || warning "Failed to delete Load Testing resource"
    else
        log "Load Testing resource $LOAD_TEST_RESOURCE not found"
    fi
    
    success "Load Testing resource cleanup completed"
}

# =============================================================================
# Traffic Manager Cleanup
# =============================================================================
cleanup_traffic_manager() {
    log "Cleaning up Traffic Manager..."
    
    # Check if Traffic Manager profile exists
    if az network traffic-manager profile show --name "$TRAFFIC_MANAGER_PROFILE" --resource-group "$RESOURCE_GROUP" &>/dev/null; then
        log "Deleting Traffic Manager profile: $TRAFFIC_MANAGER_PROFILE"
        az network traffic-manager profile delete \
            --name "$TRAFFIC_MANAGER_PROFILE" \
            --resource-group "$RESOURCE_GROUP" || warning "Failed to delete Traffic Manager profile"
    else
        log "Traffic Manager profile $TRAFFIC_MANAGER_PROFILE not found"
    fi
    
    success "Traffic Manager cleanup completed"
}

# =============================================================================
# Web Applications Cleanup
# =============================================================================
cleanup_web_applications() {
    log "Cleaning up web applications..."
    
    # Get all web apps in the resource group
    WEB_APPS=$(az webapp list \
        --resource-group "$RESOURCE_GROUP" \
        --query '[].name' \
        --output tsv 2>/dev/null || echo "")
    
    if [ -n "$WEB_APPS" ]; then
        while IFS= read -r webapp; do
            if [ -n "$webapp" ]; then
                log "Deleting web app: $webapp"
                az webapp delete \
                    --name "$webapp" \
                    --resource-group "$RESOURCE_GROUP" || warning "Failed to delete web app: $webapp"
            fi
        done <<< "$WEB_APPS"
    else
        log "No web apps found to delete"
    fi
    
    # Get all app service plans in the resource group
    APP_SERVICE_PLANS=$(az appservice plan list \
        --resource-group "$RESOURCE_GROUP" \
        --query '[].name' \
        --output tsv 2>/dev/null || echo "")
    
    if [ -n "$APP_SERVICE_PLANS" ]; then
        while IFS= read -r plan; do
            if [ -n "$plan" ]; then
                log "Deleting app service plan: $plan"
                az appservice plan delete \
                    --name "$plan" \
                    --resource-group "$RESOURCE_GROUP" \
                    --yes || warning "Failed to delete app service plan: $plan"
            fi
        done <<< "$APP_SERVICE_PLANS"
    else
        log "No app service plans found to delete"
    fi
    
    success "Web applications cleanup completed"
}

# =============================================================================
# Storage and Monitoring Cleanup
# =============================================================================
cleanup_storage_and_monitoring() {
    log "Cleaning up storage and monitoring resources..."
    
    # Storage accounts cleanup
    STORAGE_ACCOUNTS=$(az storage account list \
        --resource-group "$RESOURCE_GROUP" \
        --query '[].name' \
        --output tsv 2>/dev/null || echo "")
    
    if [ -n "$STORAGE_ACCOUNTS" ]; then
        while IFS= read -r storage_account; do
            if [ -n "$storage_account" ]; then
                log "Deleting storage account: $storage_account"
                az storage account delete \
                    --name "$storage_account" \
                    --resource-group "$RESOURCE_GROUP" \
                    --yes || warning "Failed to delete storage account: $storage_account"
            fi
        done <<< "$STORAGE_ACCOUNTS"
    else
        log "No storage accounts found to delete"
    fi
    
    # Application Insights cleanup
    APP_INSIGHTS=$(az monitor app-insights component list \
        --resource-group "$RESOURCE_GROUP" \
        --query '[].name' \
        --output tsv 2>/dev/null || echo "")
    
    if [ -n "$APP_INSIGHTS" ]; then
        while IFS= read -r app_insight; do
            if [ -n "$app_insight" ]; then
                log "Deleting Application Insights: $app_insight"
                az monitor app-insights component delete \
                    --app "$app_insight" \
                    --resource-group "$RESOURCE_GROUP" || warning "Failed to delete Application Insights: $app_insight"
            fi
        done <<< "$APP_INSIGHTS"
    else
        log "No Application Insights found to delete"
    fi
    
    # Log Analytics workspace cleanup
    LOG_WORKSPACES=$(az monitor log-analytics workspace list \
        --resource-group "$RESOURCE_GROUP" \
        --query '[].name' \
        --output tsv 2>/dev/null || echo "")
    
    if [ -n "$LOG_WORKSPACES" ]; then
        while IFS= read -r workspace; do
            if [ -n "$workspace" ]; then
                log "Deleting Log Analytics workspace: $workspace"
                az monitor log-analytics workspace delete \
                    --resource-group "$RESOURCE_GROUP" \
                    --workspace-name "$workspace" \
                    --yes || warning "Failed to delete Log Analytics workspace: $workspace"
            fi
        done <<< "$LOG_WORKSPACES"
    else
        log "No Log Analytics workspaces found to delete"
    fi
    
    success "Storage and monitoring cleanup completed"
}

# =============================================================================
# Final Resource Group Cleanup
# =============================================================================
cleanup_resource_group() {
    log "Performing final resource group cleanup..."
    
    # Wait a moment for resources to be fully deleted
    log "Waiting for resources to be fully deleted..."
    sleep 30
    
    # Check if there are any remaining resources
    REMAINING_RESOURCES=$(az resource list \
        --resource-group "$RESOURCE_GROUP" \
        --query 'length(@)' \
        --output tsv 2>/dev/null || echo "0")
    
    if [ "$REMAINING_RESOURCES" -gt 0 ]; then
        warning "Found $REMAINING_RESOURCES remaining resources in resource group"
        log "Listing remaining resources:"
        az resource list \
            --resource-group "$RESOURCE_GROUP" \
            --query '[].{Name:name,Type:type,Location:location}' \
            --output table || true
        
        read -p "Force delete the entire resource group? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            log "Force deleting resource group..."
            az group delete \
                --name "$RESOURCE_GROUP" \
                --yes \
                --no-wait
        else
            warning "Resource group cleanup skipped. Manual cleanup may be required."
            return 0
        fi
    else
        log "No remaining resources found. Deleting resource group..."
        az group delete \
            --name "$RESOURCE_GROUP" \
            --yes \
            --no-wait
    fi
    
    success "Resource group deletion initiated"
}

# =============================================================================
# Cleanup Configuration Files
# =============================================================================
cleanup_configuration() {
    log "Cleaning up configuration files..."
    
    if [ -f ".deployment_config" ]; then
        rm -f .deployment_config
        success "Configuration file removed"
    fi
    
    # Clean up any temporary files
    rm -f function.zip 2>/dev/null || true
    
    success "Configuration cleanup completed"
}

# =============================================================================
# Verification
# =============================================================================
verify_cleanup() {
    log "Verifying cleanup completion..."
    
    # Check if resource group still exists
    if az group exists --name "$RESOURCE_GROUP"; then
        warning "Resource group $RESOURCE_GROUP still exists (deletion may be in progress)"
        log "You can monitor deletion progress with: az group wait --name $RESOURCE_GROUP --deleted"
    else
        success "Resource group $RESOURCE_GROUP has been deleted"
    fi
    
    # Check for any remaining role assignments (if we have the identity)
    if [ -n "${FUNCTION_IDENTITY:-}" ]; then
        REMAINING_ASSIGNMENTS=$(az role assignment list \
            --assignee "$FUNCTION_IDENTITY" \
            --query 'length(@)' \
            --output tsv 2>/dev/null || echo "0")
        
        if [ "$REMAINING_ASSIGNMENTS" -gt 0 ]; then
            warning "Found $REMAINING_ASSIGNMENTS remaining role assignments"
        else
            log "No remaining role assignments found"
        fi
    fi
    
    success "Cleanup verification completed"
}

# =============================================================================
# Main Execution
# =============================================================================
main() {
    log "Starting Azure Self-Healing Infrastructure cleanup..."
    
    # Execute cleanup steps
    load_configuration
    check_prerequisites
    confirm_deletion
    check_resource_existence
    
    # Cleanup in reverse order of creation
    cleanup_alert_rules
    cleanup_function_app
    cleanup_load_testing
    cleanup_traffic_manager
    cleanup_web_applications
    cleanup_storage_and_monitoring
    cleanup_resource_group
    cleanup_configuration
    verify_cleanup
    
    # Display cleanup summary
    echo ""
    echo "=============================================="
    echo "     CLEANUP COMPLETED SUCCESSFULLY!"
    echo "=============================================="
    echo ""
    echo "All resources have been deleted or marked for deletion:"
    echo "  ✓ Alert rules and action groups"
    echo "  ✓ Function App and role assignments"
    echo "  ✓ Load Testing resource"
    echo "  ✓ Traffic Manager profile"
    echo "  ✓ Web applications and service plans"
    echo "  ✓ Storage and monitoring resources"
    echo "  ✓ Resource group: $RESOURCE_GROUP"
    echo ""
    echo "Note: Some resources may take a few minutes to be fully deleted."
    echo "You can monitor the deletion progress in the Azure portal."
    echo ""
    
    success "Self-healing infrastructure cleanup completed!"
}

# Run main function
main "$@"