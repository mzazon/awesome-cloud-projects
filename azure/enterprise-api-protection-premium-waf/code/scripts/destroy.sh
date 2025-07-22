#!/bin/bash

# Enterprise API Protection with Premium Management and WAF - Cleanup Script
# This script removes all Azure resources created by the deployment script
# including API Management Premium, Web Application Firewall, Redis Enterprise, and monitoring

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
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING:${NC} $1"
}

log_error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1"
}

log_info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO:${NC} $1"
}

# Error handling function
handle_error() {
    log_error "Cleanup failed on line $1"
    log_error "Some resources may still exist. Please check the Azure portal."
    exit 1
}

# Set up error handling
trap 'handle_error $LINENO' ERR

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        log_error "Azure CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if user is logged in
    if ! az account show &> /dev/null; then
        log_error "Please run 'az login' to authenticate with Azure"
        exit 1
    fi
    
    # Get subscription info
    local subscription_name=$(az account show --query name -o tsv)
    local subscription_id=$(az account show --query id -o tsv)
    log_info "Using subscription: $subscription_name ($subscription_id)"
    
    log "✅ Prerequisites check completed"
}

# Function to load deployment state
load_deployment_state() {
    log "Loading deployment state..."
    
    local state_file="$HOME/.azure-enterprise-api-deployment-state"
    
    if [[ -f "$state_file" ]]; then
        source "$state_file"
        log_info "Deployment state loaded from: $state_file"
        log_info "Resource Group: ${RESOURCE_GROUP:-not set}"
        log_info "Random Suffix: ${RANDOM_SUFFIX:-not set}"
    else
        log_warning "No deployment state file found. You may need to set environment variables manually."
        log_warning "State file expected at: $state_file"
    fi
}

# Function to set environment variables if not loaded from state
set_environment_variables() {
    log "Setting up environment variables..."
    
    # Set default values if not already set
    if [[ -z "${RESOURCE_GROUP:-}" ]]; then
        export RESOURCE_GROUP="rg-enterprise-api-security"
        log_warning "RESOURCE_GROUP not set, using default: $RESOURCE_GROUP"
    fi
    
    if [[ -z "${RANDOM_SUFFIX:-}" ]]; then
        log_warning "RANDOM_SUFFIX not set. You may need to specify resource names manually."
        echo
        echo "Available resource groups:"
        az group list --query "[?starts_with(name, 'rg-enterprise-api')].name" -o table
        echo
        read -p "Enter the resource group name to delete: " -r RESOURCE_GROUP
        export RESOURCE_GROUP
        
        # Try to extract suffix from existing resources
        local apim_names=$(az apim list --resource-group "$RESOURCE_GROUP" --query "[].name" -o tsv 2>/dev/null || echo "")
        if [[ -n "$apim_names" ]]; then
            local apim_name=$(echo "$apim_names" | head -n 1)
            export RANDOM_SUFFIX=$(echo "$apim_name" | sed 's/apim-enterprise-//')
            log_info "Extracted suffix from existing resources: $RANDOM_SUFFIX"
        fi
    fi
    
    # Set resource names if suffix is available
    if [[ -n "${RANDOM_SUFFIX:-}" ]]; then
        export APIM_NAME="${APIM_NAME:-apim-enterprise-${RANDOM_SUFFIX}}"
        export WAF_POLICY_NAME="${WAF_POLICY_NAME:-waf-enterprise-policy-${RANDOM_SUFFIX}}"
        export FRONT_DOOR_NAME="${FRONT_DOOR_NAME:-fd-enterprise-${RANDOM_SUFFIX}}"
        export REDIS_NAME="${REDIS_NAME:-redis-enterprise-${RANDOM_SUFFIX}}"
        export APP_INSIGHTS_NAME="${APP_INSIGHTS_NAME:-ai-enterprise-${RANDOM_SUFFIX}}"
        export LOG_WORKSPACE_NAME="${LOG_WORKSPACE_NAME:-law-enterprise-${RANDOM_SUFFIX}}"
    fi
    
    log "✅ Environment variables configured"
}

# Function to check if resource group exists
check_resource_group() {
    log "Checking if resource group exists..."
    
    if ! az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        log_warning "Resource group $RESOURCE_GROUP does not exist or is not accessible"
        log_info "Available resource groups:"
        az group list --query "[].name" -o table
        return 1
    fi
    
    log "✅ Resource group found: $RESOURCE_GROUP"
    return 0
}

# Function to list resources in the group
list_resources() {
    log "Listing resources in resource group..."
    
    local resource_count=$(az resource list --resource-group "$RESOURCE_GROUP" --query "length(@)" -o tsv 2>/dev/null || echo "0")
    
    if [[ "$resource_count" -eq 0 ]]; then
        log_info "No resources found in resource group $RESOURCE_GROUP"
        return 0
    fi
    
    log_info "Found $resource_count resources in $RESOURCE_GROUP:"
    az resource list --resource-group "$RESOURCE_GROUP" --query "[].{Name:name, Type:type}" -o table
    echo
}

# Function to delete Front Door resources
delete_front_door() {
    log "Deleting Front Door and related resources..."
    
    # Delete Front Door profile (includes endpoints and routes)
    if [[ -n "${FRONT_DOOR_NAME:-}" ]]; then
        if az afd profile show --resource-group "$RESOURCE_GROUP" --profile-name "$FRONT_DOOR_NAME" &> /dev/null; then
            log_info "Deleting Front Door profile: $FRONT_DOOR_NAME"
            az afd profile delete \
                --resource-group "$RESOURCE_GROUP" \
                --profile-name "$FRONT_DOOR_NAME" \
                --yes
            log "✅ Front Door profile deleted: $FRONT_DOOR_NAME"
        else
            log_warning "Front Door profile $FRONT_DOOR_NAME not found"
        fi
    else
        # Try to find and delete any Front Door profiles
        local fd_profiles=$(az afd profile list --resource-group "$RESOURCE_GROUP" --query "[].name" -o tsv 2>/dev/null || echo "")
        if [[ -n "$fd_profiles" ]]; then
            echo "$fd_profiles" | while read -r profile_name; do
                if [[ -n "$profile_name" ]]; then
                    log_info "Deleting Front Door profile: $profile_name"
                    az afd profile delete \
                        --resource-group "$RESOURCE_GROUP" \
                        --profile-name "$profile_name" \
                        --yes
                    log "✅ Front Door profile deleted: $profile_name"
                fi
            done
        else
            log_info "No Front Door profiles found"
        fi
    fi
    
    # Delete WAF policy
    if [[ -n "${WAF_POLICY_NAME:-}" ]]; then
        if az network front-door waf-policy show --resource-group "$RESOURCE_GROUP" --name "$WAF_POLICY_NAME" &> /dev/null; then
            log_info "Deleting WAF policy: $WAF_POLICY_NAME"
            az network front-door waf-policy delete \
                --resource-group "$RESOURCE_GROUP" \
                --name "$WAF_POLICY_NAME" \
                --yes
            log "✅ WAF policy deleted: $WAF_POLICY_NAME"
        else
            log_warning "WAF policy $WAF_POLICY_NAME not found"
        fi
    else
        # Try to find and delete any WAF policies
        local waf_policies=$(az network front-door waf-policy list --resource-group "$RESOURCE_GROUP" --query "[].name" -o tsv 2>/dev/null || echo "")
        if [[ -n "$waf_policies" ]]; then
            echo "$waf_policies" | while read -r policy_name; do
                if [[ -n "$policy_name" ]]; then
                    log_info "Deleting WAF policy: $policy_name"
                    az network front-door waf-policy delete \
                        --resource-group "$RESOURCE_GROUP" \
                        --name "$policy_name" \
                        --yes
                    log "✅ WAF policy deleted: $policy_name"
                fi
            done
        else
            log_info "No WAF policies found"
        fi
    fi
}

# Function to delete API Management
delete_api_management() {
    log "Deleting API Management..."
    
    if [[ -n "${APIM_NAME:-}" ]]; then
        if az apim show --resource-group "$RESOURCE_GROUP" --name "$APIM_NAME" &> /dev/null; then
            log_info "Deleting API Management instance: $APIM_NAME"
            log_warning "This operation may take 30-45 minutes to complete"
            az apim delete \
                --resource-group "$RESOURCE_GROUP" \
                --name "$APIM_NAME" \
                --yes \
                --no-wait
            log "✅ API Management deletion initiated: $APIM_NAME"
        else
            log_warning "API Management instance $APIM_NAME not found"
        fi
    else
        # Try to find and delete any API Management instances
        local apim_instances=$(az apim list --resource-group "$RESOURCE_GROUP" --query "[].name" -o tsv 2>/dev/null || echo "")
        if [[ -n "$apim_instances" ]]; then
            echo "$apim_instances" | while read -r apim_name; do
                if [[ -n "$apim_name" ]]; then
                    log_info "Deleting API Management instance: $apim_name"
                    log_warning "This operation may take 30-45 minutes to complete"
                    az apim delete \
                        --resource-group "$RESOURCE_GROUP" \
                        --name "$apim_name" \
                        --yes \
                        --no-wait
                    log "✅ API Management deletion initiated: $apim_name"
                fi
            done
        else
            log_info "No API Management instances found"
        fi
    fi
}

# Function to delete Redis cache
delete_redis_cache() {
    log "Deleting Redis Enterprise cache..."
    
    if [[ -n "${REDIS_NAME:-}" ]]; then
        if az redis show --resource-group "$RESOURCE_GROUP" --name "$REDIS_NAME" &> /dev/null; then
            log_info "Deleting Redis cache: $REDIS_NAME"
            az redis delete \
                --resource-group "$RESOURCE_GROUP" \
                --name "$REDIS_NAME" \
                --yes
            log "✅ Redis cache deleted: $REDIS_NAME"
        else
            log_warning "Redis cache $REDIS_NAME not found"
        fi
    else
        # Try to find and delete any Redis caches
        local redis_caches=$(az redis list --resource-group "$RESOURCE_GROUP" --query "[].name" -o tsv 2>/dev/null || echo "")
        if [[ -n "$redis_caches" ]]; then
            echo "$redis_caches" | while read -r redis_name; do
                if [[ -n "$redis_name" ]]; then
                    log_info "Deleting Redis cache: $redis_name"
                    az redis delete \
                        --resource-group "$RESOURCE_GROUP" \
                        --name "$redis_name" \
                        --yes
                    log "✅ Redis cache deleted: $redis_name"
                fi
            done
        else
            log_info "No Redis caches found"
        fi
    fi
}

# Function to delete monitoring resources
delete_monitoring() {
    log "Deleting monitoring resources..."
    
    # Delete Application Insights
    if [[ -n "${APP_INSIGHTS_NAME:-}" ]]; then
        if az monitor app-insights component show --app "$APP_INSIGHTS_NAME" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
            log_info "Deleting Application Insights: $APP_INSIGHTS_NAME"
            az monitor app-insights component delete \
                --resource-group "$RESOURCE_GROUP" \
                --app "$APP_INSIGHTS_NAME" \
                --yes
            log "✅ Application Insights deleted: $APP_INSIGHTS_NAME"
        else
            log_warning "Application Insights $APP_INSIGHTS_NAME not found"
        fi
    else
        # Try to find and delete any Application Insights components
        local ai_components=$(az monitor app-insights component list --resource-group "$RESOURCE_GROUP" --query "[].name" -o tsv 2>/dev/null || echo "")
        if [[ -n "$ai_components" ]]; then
            echo "$ai_components" | while read -r ai_name; do
                if [[ -n "$ai_name" ]]; then
                    log_info "Deleting Application Insights: $ai_name"
                    az monitor app-insights component delete \
                        --resource-group "$RESOURCE_GROUP" \
                        --app "$ai_name" \
                        --yes
                    log "✅ Application Insights deleted: $ai_name"
                fi
            done
        else
            log_info "No Application Insights components found"
        fi
    fi
    
    # Delete Log Analytics workspace
    if [[ -n "${LOG_WORKSPACE_NAME:-}" ]]; then
        if az monitor log-analytics workspace show --resource-group "$RESOURCE_GROUP" --workspace-name "$LOG_WORKSPACE_NAME" &> /dev/null; then
            log_info "Deleting Log Analytics workspace: $LOG_WORKSPACE_NAME"
            az monitor log-analytics workspace delete \
                --resource-group "$RESOURCE_GROUP" \
                --workspace-name "$LOG_WORKSPACE_NAME" \
                --yes \
                --force
            log "✅ Log Analytics workspace deleted: $LOG_WORKSPACE_NAME"
        else
            log_warning "Log Analytics workspace $LOG_WORKSPACE_NAME not found"
        fi
    else
        # Try to find and delete any Log Analytics workspaces
        local law_workspaces=$(az monitor log-analytics workspace list --resource-group "$RESOURCE_GROUP" --query "[].name" -o tsv 2>/dev/null || echo "")
        if [[ -n "$law_workspaces" ]]; then
            echo "$law_workspaces" | while read -r law_name; do
                if [[ -n "$law_name" ]]; then
                    log_info "Deleting Log Analytics workspace: $law_name"
                    az monitor log-analytics workspace delete \
                        --resource-group "$RESOURCE_GROUP" \
                        --workspace-name "$law_name" \
                        --yes \
                        --force
                    log "✅ Log Analytics workspace deleted: $law_name"
                fi
            done
        else
            log_info "No Log Analytics workspaces found"
        fi
    fi
}

# Function to delete any remaining resources
delete_remaining_resources() {
    log "Checking for remaining resources..."
    
    local remaining_resources=$(az resource list --resource-group "$RESOURCE_GROUP" --query "[].{Name:name, Type:type}" -o tsv 2>/dev/null || echo "")
    
    if [[ -n "$remaining_resources" ]]; then
        log_warning "Found remaining resources:"
        echo "$remaining_resources"
        echo
        
        read -p "Do you want to delete all remaining resources? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            log_info "Deleting remaining resources..."
            
            # Get resource IDs and delete them
            local resource_ids=$(az resource list --resource-group "$RESOURCE_GROUP" --query "[].id" -o tsv 2>/dev/null || echo "")
            if [[ -n "$resource_ids" ]]; then
                echo "$resource_ids" | while read -r resource_id; do
                    if [[ -n "$resource_id" ]]; then
                        log_info "Deleting resource: $resource_id"
                        az resource delete --ids "$resource_id" --no-wait || log_warning "Failed to delete resource: $resource_id"
                    fi
                done
            fi
            
            # Wait a bit and check again
            sleep 10
            local final_count=$(az resource list --resource-group "$RESOURCE_GROUP" --query "length(@)" -o tsv 2>/dev/null || echo "0")
            if [[ "$final_count" -eq 0 ]]; then
                log "✅ All remaining resources deleted"
            else
                log_warning "$final_count resources may still exist"
            fi
        else
            log_info "Keeping remaining resources"
        fi
    else
        log "✅ No remaining resources found"
    fi
}

# Function to delete resource group
delete_resource_group() {
    log "Deleting resource group..."
    
    # Final confirmation for resource group deletion
    echo
    log_warning "FINAL CONFIRMATION: This will permanently delete the resource group and ALL its contents."
    log_warning "Resource Group: $RESOURCE_GROUP"
    echo
    read -p "Are you absolutely sure you want to delete the entire resource group? (y/N): " -n 1 -r
    echo
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        log_info "Deleting resource group: $RESOURCE_GROUP"
        az group delete \
            --name "$RESOURCE_GROUP" \
            --yes \
            --no-wait
        log "✅ Resource group deletion initiated: $RESOURCE_GROUP"
        log_info "The resource group deletion will continue in the background"
    else
        log_info "Resource group deletion cancelled"
        log_info "Individual resources have been deleted, but the resource group remains"
    fi
}

# Function to cleanup deployment state
cleanup_deployment_state() {
    log "Cleaning up deployment state..."
    
    local state_file="$HOME/.azure-enterprise-api-deployment-state"
    
    if [[ -f "$state_file" ]]; then
        rm -f "$state_file"
        log "✅ Deployment state file removed: $state_file"
    else
        log_info "No deployment state file found to clean up"
    fi
}

# Function to display cleanup summary
display_summary() {
    log "================================="
    log "CLEANUP COMPLETED!"
    log "================================="
    
    echo
    log_info "Cleanup Summary:"
    echo "  ✅ Front Door and WAF resources deleted"
    echo "  ✅ API Management deletion initiated (may take 30-45 minutes)"
    echo "  ✅ Redis Enterprise cache deleted"
    echo "  ✅ Application Insights deleted"
    echo "  ✅ Log Analytics workspace deleted"
    echo "  ✅ Deployment state cleaned up"
    echo
    
    if [[ "${RESOURCE_GROUP_DELETED:-false}" == "true" ]]; then
        echo "  ✅ Resource group deletion initiated"
    else
        echo "  ⚠️  Resource group retained: $RESOURCE_GROUP"
    fi
    echo
    
    log_info "Important Notes:"
    echo "  - API Management deletion continues in the background and may take 30-45 minutes"
    echo "  - Monitor the Azure portal to confirm complete deletion"
    echo "  - Check your Azure billing dashboard to verify cost reduction"
    echo
    
    log_info "Verification Commands:"
    echo "  # Check if resource group still exists"
    echo "  az group show --name $RESOURCE_GROUP"
    echo
    echo "  # List any remaining resources"
    echo "  az resource list --resource-group $RESOURCE_GROUP"
    echo
    echo "  # Check API Management deletion status"
    echo "  az apim list --resource-group $RESOURCE_GROUP"
}

# Function to handle interactive resource selection
interactive_cleanup() {
    log "Starting interactive cleanup mode..."
    
    echo
    log_info "Select cleanup option:"
    echo "1. Delete individual resources only"
    echo "2. Delete individual resources and resource group"
    echo "3. Delete entire resource group (fastest)"
    echo "4. Cancel cleanup"
    echo
    read -p "Enter your choice (1-4): " -n 1 -r
    echo
    
    case $REPLY in
        1)
            log_info "Selected: Delete individual resources only"
            delete_front_door
            delete_api_management
            delete_redis_cache
            delete_monitoring
            delete_remaining_resources
            ;;
        2)
            log_info "Selected: Delete individual resources and resource group"
            delete_front_door
            delete_api_management
            delete_redis_cache
            delete_monitoring
            delete_remaining_resources
            delete_resource_group
            export RESOURCE_GROUP_DELETED=true
            ;;
        3)
            log_info "Selected: Delete entire resource group"
            delete_resource_group
            export RESOURCE_GROUP_DELETED=true
            ;;
        4)
            log_info "Cleanup cancelled by user"
            exit 0
            ;;
        *)
            log_error "Invalid choice. Please run the script again."
            exit 1
            ;;
    esac
}

# Main cleanup function
main() {
    log "Starting Azure Enterprise API Protection cleanup..."
    log "=============================================="
    
    # Execute cleanup steps
    check_prerequisites
    load_deployment_state
    set_environment_variables
    
    # Check if resource group exists
    if ! check_resource_group; then
        log_error "Cannot proceed with cleanup. Resource group not found or not accessible."
        exit 1
    fi
    
    # List resources for user awareness
    list_resources
    
    # Check if running in non-interactive mode
    if [[ "${FORCE_DELETE:-}" == "true" ]]; then
        log_warning "Force delete mode enabled. Deleting all resources..."
        delete_front_door
        delete_api_management
        delete_redis_cache
        delete_monitoring
        delete_remaining_resources
        if [[ "${DELETE_RESOURCE_GROUP:-}" == "true" ]]; then
            delete_resource_group
            export RESOURCE_GROUP_DELETED=true
        fi
    else
        # Interactive mode
        interactive_cleanup
    fi
    
    # Cleanup deployment state
    cleanup_deployment_state
    
    # Display summary
    display_summary
    
    log "Cleanup completed! 🧹"
}

# Show help function
show_help() {
    echo "Azure Enterprise API Protection - Cleanup Script"
    echo
    echo "Usage: $0 [OPTIONS]"
    echo
    echo "Options:"
    echo "  -h, --help              Show this help message"
    echo "  -f, --force             Force delete without confirmation"
    echo "  -g, --delete-group      Also delete the resource group (use with --force)"
    echo "  -r, --resource-group    Specify resource group name"
    echo
    echo "Environment Variables:"
    echo "  RESOURCE_GROUP          Resource group name"
    echo "  FORCE_DELETE           Set to 'true' to skip confirmations"
    echo "  DELETE_RESOURCE_GROUP   Set to 'true' to delete resource group"
    echo
    echo "Examples:"
    echo "  $0                                    # Interactive cleanup"
    echo "  $0 --force                          # Force delete resources only"
    echo "  $0 --force --delete-group           # Force delete everything"
    echo "  $0 --resource-group my-rg           # Specify resource group"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        -f|--force)
            export FORCE_DELETE=true
            shift
            ;;
        -g|--delete-group)
            export DELETE_RESOURCE_GROUP=true
            shift
            ;;
        -r|--resource-group)
            export RESOURCE_GROUP="$2"
            shift 2
            ;;
        *)
            log_error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Execute main function
main "$@"