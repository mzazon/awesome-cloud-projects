#!/bin/bash

# Event-Driven AI Agent Workflows with AI Foundry and Logic Apps - Cleanup Script
# Recipe: azure/event-driven-ai-agent-workflows-foundry-logic-apps
# Version: 1.1
# 
# This script removes all infrastructure created for the event-driven AI agent workflows
# recipe, including AI Foundry resources, Logic Apps, and Service Bus

set -euo pipefail

# Color codes for output formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO:${NC} $1"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARN:${NC} $1"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1"
}

success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] SUCCESS:${NC} $1"
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        error "Azure CLI is not installed. Please install it from https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
        exit 1
    fi
    
    # Check if user is logged in to Azure
    if ! az account show &> /dev/null; then
        error "You are not logged in to Azure. Please run 'az login' first."
        exit 1
    fi
    
    success "Prerequisites check passed"
}

# Function to load environment variables from deployment
load_environment_variables() {
    log "Loading environment variables..."
    
    # Try to load from deployment.env if it exists
    if [[ -f "deployment.env" ]]; then
        log "Loading variables from deployment.env"
        source deployment.env
    else
        # If no deployment.env, check for command line arguments
        if [[ -z "${RESOURCE_GROUP:-}" ]]; then
            error "Resource group not specified. Please provide via:"
            error "  1. deployment.env file in current directory, or"
            error "  2. --resource-group command line argument, or"
            error "  3. RESOURCE_GROUP environment variable"
            exit 1
        fi
    fi
    
    # Set default values for missing variables
    export SUBSCRIPTION_ID="${SUBSCRIPTION_ID:-$(az account show --query id --output tsv)}"
    
    log "Environment variables loaded:"
    log "  Resource Group: ${RESOURCE_GROUP}"
    log "  Subscription ID: ${SUBSCRIPTION_ID}"
    
    if [[ -n "${AI_FOUNDRY_HUB:-}" ]]; then
        log "  AI Foundry Hub: ${AI_FOUNDRY_HUB}"
    fi
    if [[ -n "${AI_FOUNDRY_PROJECT:-}" ]]; then
        log "  AI Foundry Project: ${AI_FOUNDRY_PROJECT}"
    fi
    if [[ -n "${SERVICE_BUS_NAMESPACE:-}" ]]; then
        log "  Service Bus Namespace: ${SERVICE_BUS_NAMESPACE}"
    fi
    if [[ -n "${LOGIC_APP_NAME:-}" ]]; then
        log "  Logic App Name: ${LOGIC_APP_NAME}"
    fi
}

# Function to confirm deletion
confirm_deletion() {
    if [[ "${FORCE_DELETE:-false}" != "true" ]]; then
        echo ""
        warn "⚠️  WARNING: This will permanently delete all resources in the resource group: ${RESOURCE_GROUP}"
        warn "This action cannot be undone!"
        echo ""
        
        # Show resources that will be deleted
        log "Resources that will be deleted:"
        if az group show --name "${RESOURCE_GROUP}" --output none 2>/dev/null; then
            az resource list --resource-group "${RESOURCE_GROUP}" --query "[].{Name:name, Type:type}" --output table 2>/dev/null || true
        else
            warn "Resource group ${RESOURCE_GROUP} not found or not accessible"
            return 1
        fi
        
        echo ""
        echo -n "Are you sure you want to continue? (type 'yes' to confirm): "
        read -r confirmation
        
        if [[ "$confirmation" != "yes" ]]; then
            log "Deletion cancelled by user"
            exit 0
        fi
    else
        log "Force delete mode enabled, skipping confirmation"
    fi
}

# Function to delete Logic App workflow
delete_logic_app() {
    if [[ -n "${LOGIC_APP_NAME:-}" ]]; then
        log "Deleting Logic App workflow: ${LOGIC_APP_NAME}"
        
        if az logic workflow show --name "${LOGIC_APP_NAME}" --resource-group "${RESOURCE_GROUP}" --output none 2>/dev/null; then
            az logic workflow delete \
                --name "${LOGIC_APP_NAME}" \
                --resource-group "${RESOURCE_GROUP}" \
                --yes \
                --output none
            
            success "Logic App workflow deleted: ${LOGIC_APP_NAME}"
        else
            warn "Logic App workflow ${LOGIC_APP_NAME} not found or already deleted"
        fi
    else
        log "Logic App name not specified, skipping deletion"
    fi
}

# Function to delete Service Bus resources
delete_service_bus() {
    if [[ -n "${SERVICE_BUS_NAMESPACE:-}" ]]; then
        log "Deleting Service Bus namespace: ${SERVICE_BUS_NAMESPACE}"
        
        if az servicebus namespace show --name "${SERVICE_BUS_NAMESPACE}" --resource-group "${RESOURCE_GROUP}" --output none 2>/dev/null; then
            # Service Bus namespace deletion includes all queues, topics, and subscriptions
            az servicebus namespace delete \
                --name "${SERVICE_BUS_NAMESPACE}" \
                --resource-group "${RESOURCE_GROUP}" \
                --output none
            
            success "Service Bus namespace deleted: ${SERVICE_BUS_NAMESPACE}"
            
            # Wait for deletion to complete
            log "Waiting for Service Bus namespace deletion to complete..."
            local timeout=300
            local elapsed=0
            
            while az servicebus namespace show --name "${SERVICE_BUS_NAMESPACE}" --resource-group "${RESOURCE_GROUP}" --output none 2>/dev/null; do
                if [[ $elapsed -ge $timeout ]]; then
                    warn "Timeout waiting for Service Bus namespace deletion"
                    break
                fi
                sleep 10
                elapsed=$((elapsed + 10))
                echo -n "."
            done
            echo ""
            success "Service Bus namespace deletion completed"
        else
            warn "Service Bus namespace ${SERVICE_BUS_NAMESPACE} not found or already deleted"
        fi
    else
        log "Service Bus namespace not specified, skipping deletion"
    fi
}

# Function to delete AI Foundry resources
delete_ai_foundry() {
    # Delete AI project first (dependent resource)
    if [[ -n "${AI_FOUNDRY_PROJECT:-}" ]]; then
        log "Deleting AI Foundry Project: ${AI_FOUNDRY_PROJECT}"
        
        if az ml workspace show --name "${AI_FOUNDRY_PROJECT}" --resource-group "${RESOURCE_GROUP}" --output none 2>/dev/null; then
            az ml workspace delete \
                --name "${AI_FOUNDRY_PROJECT}" \
                --resource-group "${RESOURCE_GROUP}" \
                --yes \
                --output none
            
            success "AI Foundry Project deleted: ${AI_FOUNDRY_PROJECT}"
        else
            warn "AI Foundry Project ${AI_FOUNDRY_PROJECT} not found or already deleted"
        fi
    else
        log "AI Foundry Project name not specified, skipping deletion"
    fi
    
    # Wait a moment before deleting the hub
    sleep 10
    
    # Delete AI hub
    if [[ -n "${AI_FOUNDRY_HUB:-}" ]]; then
        log "Deleting AI Foundry Hub: ${AI_FOUNDRY_HUB}"
        
        if az ml workspace show --name "${AI_FOUNDRY_HUB}" --resource-group "${RESOURCE_GROUP}" --output none 2>/dev/null; then
            az ml workspace delete \
                --name "${AI_FOUNDRY_HUB}" \
                --resource-group "${RESOURCE_GROUP}" \
                --yes \
                --output none
            
            success "AI Foundry Hub deleted: ${AI_FOUNDRY_HUB}"
        else
            warn "AI Foundry Hub ${AI_FOUNDRY_HUB} not found or already deleted"
        fi
    else
        log "AI Foundry Hub name not specified, skipping deletion"
    fi
}

# Function to delete resource group and all remaining resources
delete_resource_group() {
    log "Deleting resource group and all remaining resources: ${RESOURCE_GROUP}"
    
    if az group show --name "${RESOURCE_GROUP}" --output none 2>/dev/null; then
        if [[ "${DELETE_RESOURCE_GROUP:-true}" == "true" ]]; then
            # Delete resource group (this will delete all remaining resources)
            az group delete \
                --name "${RESOURCE_GROUP}" \
                --yes \
                --no-wait
            
            success "Resource group deletion initiated: ${RESOURCE_GROUP}"
            log "Note: Complete deletion may take several minutes"
            
            # Optionally wait for deletion to complete
            if [[ "${WAIT_FOR_DELETION:-false}" == "true" ]]; then
                log "Waiting for resource group deletion to complete..."
                local timeout=1800  # 30 minutes
                local elapsed=0
                
                while az group show --name "${RESOURCE_GROUP}" --output none 2>/dev/null; do
                    if [[ $elapsed -ge $timeout ]]; then
                        warn "Timeout waiting for resource group deletion"
                        break
                    fi
                    sleep 30
                    elapsed=$((elapsed + 30))
                    echo -n "."
                done
                echo ""
                success "Resource group deletion completed"
            fi
        else
            log "Keeping resource group as requested"
        fi
    else
        warn "Resource group ${RESOURCE_GROUP} not found or already deleted"
    fi
}

# Function to clean up local files
cleanup_local_files() {
    log "Cleaning up local files..."
    
    # Remove deployment.env if it exists
    if [[ -f "deployment.env" ]]; then
        if [[ "${KEEP_DEPLOYMENT_ENV:-false}" != "true" ]]; then
            rm -f deployment.env
            log "Removed deployment.env file"
        else
            log "Keeping deployment.env file as requested"
        fi
    fi
    
    # Clean up any temporary files
    rm -f /tmp/logic-app-definition.json 2>/dev/null || true
    
    success "Local files cleaned up"
}

# Function to verify cleanup
verify_cleanup() {
    log "Verifying cleanup..."
    
    # Check if resource group still exists
    if az group show --name "${RESOURCE_GROUP}" --output none 2>/dev/null; then
        if [[ "${DELETE_RESOURCE_GROUP:-true}" == "true" ]]; then
            warn "Resource group ${RESOURCE_GROUP} still exists (deletion may be in progress)"
        else
            log "Resource group ${RESOURCE_GROUP} still exists (as requested)"
        fi
        
        # List remaining resources
        log "Remaining resources in resource group:"
        az resource list --resource-group "${RESOURCE_GROUP}" --query "[].{Name:name, Type:type}" --output table 2>/dev/null || true
    else
        success "Resource group ${RESOURCE_GROUP} has been deleted"
    fi
    
    success "Cleanup verification completed"
}

# Function to handle script interruption
cleanup_on_error() {
    error "Cleanup interrupted. Some resources may still exist."
    error "Please check the Azure portal and manually delete any remaining resources in:"
    error "  Resource Group: ${RESOURCE_GROUP}"
    exit 1
}

# Function to list resources before deletion
list_resources() {
    log "Listing resources in resource group: ${RESOURCE_GROUP}"
    
    if az group show --name "${RESOURCE_GROUP}" --output none 2>/dev/null; then
        echo ""
        echo "Resources to be deleted:"
        echo "========================"
        az resource list --resource-group "${RESOURCE_GROUP}" --query "[].{Name:name, Type:type, Location:location}" --output table
        echo ""
    else
        warn "Resource group ${RESOURCE_GROUP} not found"
        return 1
    fi
}

# Main execution function
main() {
    log "Starting cleanup of Event-Driven AI Agent Workflows resources"
    log "Recipe: azure/event-driven-ai-agent-workflows-foundry-logic-apps"
    
    # Set up error handling
    trap cleanup_on_error INT TERM
    
    # Execute cleanup steps
    check_prerequisites
    load_environment_variables
    
    # List resources if requested
    if [[ "${LIST_RESOURCES:-false}" == "true" ]]; then
        list_resources
        if [[ "${CONFIRM_BEFORE_DELETE:-true}" == "true" ]]; then
            echo ""
            echo -n "Proceed with deletion? (y/N): "
            read -r proceed
            if [[ "$proceed" != "y" && "$proceed" != "Y" ]]; then
                log "Cleanup cancelled by user"
                exit 0
            fi
        fi
    fi
    
    # Confirm deletion unless forced
    confirm_deletion
    
    # Execute deletion in reverse order of creation
    delete_logic_app
    delete_service_bus
    delete_ai_foundry
    delete_resource_group
    cleanup_local_files
    
    # Verify cleanup
    verify_cleanup
    
    success "Cleanup completed successfully!"
    
    echo ""
    echo "=================================================="
    echo "              CLEANUP SUMMARY"
    echo "=================================================="
    echo ""
    echo "✅ Logic App workflow deleted"
    echo "✅ Service Bus namespace and messaging infrastructure deleted"
    echo "✅ AI Foundry Project and Hub deleted"
    if [[ "${DELETE_RESOURCE_GROUP:-true}" == "true" ]]; then
        echo "✅ Resource group deletion initiated"
        echo "   Note: Complete deletion may take several minutes"
    else
        echo "ℹ️  Resource group kept as requested"
    fi
    echo "✅ Local files cleaned up"
    echo ""
    echo "=================================================="
}

# Script usage information
usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -g, --resource-group NAME  Resource group to delete"
    echo "  -f, --force               Skip confirmation prompts"
    echo "  -l, --list                List resources before deletion"
    echo "  -w, --wait                Wait for deletion to complete"
    echo "  -k, --keep-rg             Keep resource group (delete resources only)"
    echo "  -e, --keep-env            Keep deployment.env file"
    echo "  -h, --help                Show this help message"
    echo ""
    echo "Environment Variables:"
    echo "  RESOURCE_GROUP            Resource group to delete"
    echo "  FORCE_DELETE              Skip confirmations (true/false)"
    echo "  DELETE_RESOURCE_GROUP     Delete resource group (default: true)"
    echo "  WAIT_FOR_DELETION         Wait for deletion to complete (true/false)"
    echo "  KEEP_DEPLOYMENT_ENV       Keep deployment.env file (true/false)"
    echo "  LIST_RESOURCES            List resources before deletion (true/false)"
    echo ""
    echo "Examples:"
    echo "  $0                                    Use deployment.env for configuration"
    echo "  $0 -g rg-ai-workflows-abc123         Delete specific resource group"
    echo "  $0 --force --wait                    Force delete and wait for completion"
    echo "  $0 --list --keep-rg                  List resources and keep resource group"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -g|--resource-group)
            export RESOURCE_GROUP="$2"
            shift 2
            ;;
        -f|--force)
            export FORCE_DELETE="true"
            export CONFIRM_BEFORE_DELETE="false"
            shift
            ;;
        -l|--list)
            export LIST_RESOURCES="true"
            shift
            ;;
        -w|--wait)
            export WAIT_FOR_DELETION="true"
            shift
            ;;
        -k|--keep-rg)
            export DELETE_RESOURCE_GROUP="false"
            shift
            ;;
        -e|--keep-env)
            export KEEP_DEPLOYMENT_ENV="true"
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            error "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# Execute main function
main "$@"