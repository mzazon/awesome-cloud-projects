#!/bin/bash

# Cost-Optimized Content Generation Cleanup Script
# This script safely removes all Azure resources created for the content generation solution
# and provides confirmation prompts to prevent accidental deletion

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
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

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        error "Azure CLI is not installed. Please install it from https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
        exit 1
    fi
    
    # Check if logged into Azure
    if ! az account show &> /dev/null; then
        error "Not logged into Azure. Please run 'az login' first"
        exit 1
    fi
    
    success "Prerequisites check completed"
}

# Function to confirm deletion
confirm_deletion() {
    local resource_group="$1"
    
    echo -e "${RED}WARNING: This will permanently delete all resources in the resource group: ${resource_group}${NC}"
    echo -e "${RED}This action cannot be undone!${NC}"
    echo ""
    
    # List resources that will be deleted
    log "Resources that will be deleted:"
    if az group show --name "$resource_group" &> /dev/null; then
        az resource list --resource-group "$resource_group" --output table 2>/dev/null || {
            warning "Could not list resources in resource group"
        }
    else
        warning "Resource group '$resource_group' not found"
    fi
    
    echo ""
    read -p "Are you sure you want to proceed? Type 'yes' to confirm: " confirmation
    
    if [ "$confirmation" != "yes" ]; then
        log "Cleanup cancelled by user"
        exit 0
    fi
    
    # Second confirmation for extra safety
    echo ""
    echo -e "${RED}FINAL CONFIRMATION${NC}"
    read -p "This will delete ALL resources. Type the resource group name to confirm: " rg_confirmation
    
    if [ "$rg_confirmation" != "$resource_group" ]; then
        error "Resource group name does not match. Cleanup cancelled."
        exit 1
    fi
    
    success "Deletion confirmed. Proceeding with cleanup..."
}

# Function to list and backup important information
backup_resource_info() {
    local resource_group="$1"
    local backup_file="cleanup-backup-$(date +%Y%m%d-%H%M%S).json"
    
    log "Backing up resource information to: $backup_file"
    
    if az group show --name "$resource_group" &> /dev/null; then
        # Export resource group information
        az group show --name "$resource_group" > "$backup_file" 2>/dev/null || {
            warning "Could not backup resource group information"
        }
        
        # Export resource list
        az resource list --resource-group "$resource_group" >> "$backup_file" 2>/dev/null || {
            warning "Could not backup resource list"
        }
        
        success "Resource information backed up to: $backup_file"
    else
        warning "Resource group not found. Skipping backup."
    fi
}

# Function to remove specific resources in order
remove_resources_safely() {
    local resource_group="$1"
    
    log "Starting safe resource removal process..."
    
    # Check if resource group exists
    if ! az group show --name "$resource_group" &> /dev/null; then
        warning "Resource group '$resource_group' not found. Nothing to delete."
        return 0
    fi
    
    # Get subscription ID
    local subscription_id
    subscription_id=$(az account show --query id --output tsv)
    
    # Step 1: Remove Event Grid subscriptions first (to prevent new events)
    log "Removing Event Grid subscriptions..."
    local storage_accounts
    storage_accounts=$(az storage account list --resource-group "$resource_group" --query "[].id" --output tsv 2>/dev/null || echo "")
    
    for storage_account_id in $storage_accounts; do
        if [ -n "$storage_account_id" ]; then
            local subscriptions
            subscriptions=$(az eventgrid event-subscription list --source-resource-id "$storage_account_id" --query "[].name" --output tsv 2>/dev/null || echo "")
            
            for subscription_name in $subscriptions; do
                if [ -n "$subscription_name" ]; then
                    log "Removing Event Grid subscription: $subscription_name"
                    az eventgrid event-subscription delete \
                        --name "$subscription_name" \
                        --source-resource-id "$storage_account_id" &> /dev/null || {
                        warning "Failed to remove Event Grid subscription: $subscription_name"
                    }
                fi
            done
        fi
    done
    
    # Step 2: Remove AI model deployments
    log "Removing AI model deployments..."
    local ai_services
    ai_services=$(az cognitiveservices account list --resource-group "$resource_group" --query "[].name" --output tsv 2>/dev/null || echo "")
    
    for ai_service in $ai_services; do
        if [ -n "$ai_service" ]; then
            log "Removing model deployments from: $ai_service"
            local deployments
            deployments=$(az cognitiveservices account deployment list \
                --name "$ai_service" \
                --resource-group "$resource_group" \
                --query "[].name" --output tsv 2>/dev/null || echo "")
            
            for deployment in $deployments; do
                if [ -n "$deployment" ]; then
                    log "Removing model deployment: $deployment"
                    az cognitiveservices account deployment delete \
                        --name "$ai_service" \
                        --resource-group "$resource_group" \
                        --deployment-name "$deployment" &> /dev/null || {
                        warning "Failed to remove deployment: $deployment"
                    }
                fi
            done
        fi
    done
    
    # Step 3: Stop and remove Function Apps
    log "Stopping and removing Function Apps..."
    local function_apps
    function_apps=$(az functionapp list --resource-group "$resource_group" --query "[].name" --output tsv 2>/dev/null || echo "")
    
    for function_app in $function_apps; do
        if [ -n "$function_app" ]; then
            log "Stopping Function App: $function_app"
            az functionapp stop --name "$function_app" --resource-group "$resource_group" &> /dev/null || {
                warning "Failed to stop Function App: $function_app"
            }
            
            log "Removing Function App: $function_app"
            az functionapp delete --name "$function_app" --resource-group "$resource_group" &> /dev/null || {
                warning "Failed to remove Function App: $function_app"
            }
        fi
    done
    
    # Step 4: Clear storage containers before deleting storage account
    log "Clearing storage containers..."
    local storage_accounts_names
    storage_accounts_names=$(az storage account list --resource-group "$resource_group" --query "[].name" --output tsv 2>/dev/null || echo "")
    
    for storage_account in $storage_accounts_names; do
        if [ -n "$storage_account" ]; then
            local connection_string
            connection_string=$(az storage account show-connection-string \
                --name "$storage_account" \
                --resource-group "$resource_group" \
                --query connectionString --output tsv 2>/dev/null || echo "")
            
            if [ -n "$connection_string" ]; then
                log "Clearing containers in storage account: $storage_account"
                
                # List and delete blobs in containers
                local containers
                containers=$(az storage container list --connection-string "$connection_string" --query "[].name" --output tsv 2>/dev/null || echo "")
                
                for container in $containers; do
                    if [ -n "$container" ]; then
                        log "Clearing container: $container"
                        az storage blob delete-batch \
                            --source "$container" \
                            --connection-string "$connection_string" &> /dev/null || {
                            warning "Failed to clear container: $container"
                        }
                    fi
                done
            fi
        fi
    done
    
    # Step 5: Remove monitoring and alerts
    log "Removing monitoring resources..."
    
    # Remove metric alerts
    local alerts
    alerts=$(az monitor metrics alert list --resource-group "$resource_group" --query "[].name" --output tsv 2>/dev/null || echo "")
    
    for alert in $alerts; do
        if [ -n "$alert" ]; then
            log "Removing alert: $alert"
            az monitor metrics alert delete \
                --name "$alert" \
                --resource-group "$resource_group" &> /dev/null || {
                warning "Failed to remove alert: $alert"
            }
        fi
    done
    
    # Remove budgets (these are at subscription level)
    log "Removing budgets..."
    local budgets
    budgets=$(az consumption budget list --query "[?contains(name, 'content-generation')].name" --output tsv 2>/dev/null || echo "")
    
    for budget in $budgets; do
        if [ -n "$budget" ]; then
            log "Removing budget: $budget"
            az consumption budget delete --budget-name "$budget" &> /dev/null || {
                warning "Failed to remove budget: $budget (may require different permissions)"
            }
        fi
    done
    
    success "Individual resource cleanup completed"
}

# Function to remove the entire resource group
remove_resource_group() {
    local resource_group="$1"
    
    log "Removing resource group: $resource_group"
    
    if ! az group show --name "$resource_group" &> /dev/null; then
        warning "Resource group '$resource_group' not found"
        return 0
    fi
    
    # Delete resource group and all remaining resources
    log "Deleting resource group and all remaining resources..."
    az group delete \
        --name "$resource_group" \
        --yes \
        --no-wait
    
    success "Resource group deletion initiated: $resource_group"
    log "Note: Resource group deletion may take several minutes to complete"
    
    # Optional: Wait for deletion and verify
    read -p "Do you want to wait for deletion to complete? (y/n): " wait_choice
    
    if [ "$wait_choice" = "y" ] || [ "$wait_choice" = "Y" ]; then
        log "Waiting for resource group deletion to complete..."
        
        local max_attempts=60  # Wait up to 30 minutes (60 * 30 seconds)
        local attempt=0
        
        while [ $attempt -lt $max_attempts ]; do
            if ! az group show --name "$resource_group" &> /dev/null; then
                success "Resource group successfully deleted: $resource_group"
                break
            fi
            
            echo -n "."
            sleep 30
            ((attempt++))
        done
        
        if [ $attempt -eq $max_attempts ]; then
            warning "Deletion is taking longer than expected. Check Azure Portal for status."
        fi
    fi
}

# Function to clean up local files
cleanup_local_files() {
    log "Cleaning up local files..."
    
    # Remove temporary function directories
    if [ -d "/tmp/content-functions-"* ]; then
        rm -rf /tmp/content-functions-* 2>/dev/null || {
            warning "Could not remove all temporary function directories"
        }
    fi
    
    # Clean up deployment info files (ask user first)
    local deployment_files
    deployment_files=$(ls deployment-info-*.txt 2>/dev/null || echo "")
    
    if [ -n "$deployment_files" ]; then
        echo ""
        log "Found deployment info files:"
        ls -la deployment-info-*.txt 2>/dev/null || true
        
        read -p "Remove deployment info files? (y/n): " remove_files
        
        if [ "$remove_files" = "y" ] || [ "$remove_files" = "Y" ]; then
            rm -f deployment-info-*.txt
            success "Deployment info files removed"
        else
            log "Deployment info files preserved"
        fi
    fi
    
    success "Local cleanup completed"
}

# Function to verify cleanup
verify_cleanup() {
    local resource_group="$1"
    
    log "Verifying cleanup..."
    
    if az group show --name "$resource_group" &> /dev/null; then
        warning "Resource group '$resource_group' still exists"
        
        # List remaining resources
        local remaining_resources
        remaining_resources=$(az resource list --resource-group "$resource_group" --query "length(@)" --output tsv 2>/dev/null || echo "unknown")
        
        if [ "$remaining_resources" != "0" ] && [ "$remaining_resources" != "unknown" ]; then
            warning "Found $remaining_resources remaining resources:"
            az resource list --resource-group "$resource_group" --output table 2>/dev/null || true
        fi
        
        log "Resource group deletion may still be in progress. Check Azure Portal for status."
    else
        success "Resource group successfully removed: $resource_group"
    fi
    
    success "Cleanup verification completed"
}

# Function to show cleanup summary
show_cleanup_summary() {
    local resource_group="$1"
    
    echo ""
    log "Cleanup Summary:"
    log "=================="
    log "Resource Group: $resource_group"
    log "Cleanup Date: $(date)"
    log "Status: Deletion initiated"
    echo ""
    log "What was removed:"
    log "- Event Grid subscriptions"
    log "- AI model deployments"
    log "- Azure Functions"
    log "- Storage accounts and containers"
    log "- Monitoring alerts and budgets"
    log "- Resource group (deletion in progress)"
    echo ""
    log "Important Notes:"
    log "- Deletion may take several minutes to complete"
    log "- Check Azure Portal to confirm complete removal"
    log "- Any backup files created during cleanup are preserved locally"
    log "- Billing should stop once all resources are deleted"
    echo ""
    warning "If you encounter any issues, check the Azure Portal or contact support"
}

# Main cleanup function
main() {
    local resource_group="${1:-}"
    
    # If no resource group provided, try to find deployment info
    if [ -z "$resource_group" ]; then
        log "No resource group specified. Looking for deployment info files..."
        
        local deployment_files
        deployment_files=$(ls deployment-info-*.txt 2>/dev/null || echo "")
        
        if [ -n "$deployment_files" ]; then
            log "Found deployment info files:"
            ls -la deployment-info-*.txt
            echo ""
            
            # Extract resource group from first deployment file
            local first_file
            first_file=$(ls deployment-info-*.txt | head -n1)
            resource_group=$(grep "Resource Group:" "$first_file" | cut -d' ' -f3 2>/dev/null || echo "")
            
            if [ -n "$resource_group" ]; then
                log "Found resource group in deployment info: $resource_group"
                read -p "Use this resource group? (y/n): " use_rg
                
                if [ "$use_rg" != "y" ] && [ "$use_rg" != "Y" ]; then
                    resource_group=""
                fi
            fi
        fi
        
        if [ -z "$resource_group" ]; then
            echo "Usage: $0 <resource-group-name>"
            echo ""
            echo "Example: $0 rg-content-generation-abc123"
            echo ""
            echo "To find your resource group, run:"
            echo "az group list --query \"[?contains(name, 'content-generation')].name\" --output table"
            exit 1
        fi
    fi
    
    log "Starting Azure Cost-Optimized Content Generation cleanup..."
    log "Target resource group: $resource_group"
    
    check_prerequisites
    confirm_deletion "$resource_group"
    backup_resource_info "$resource_group"
    remove_resources_safely "$resource_group"
    remove_resource_group "$resource_group"
    cleanup_local_files
    verify_cleanup "$resource_group"
    show_cleanup_summary "$resource_group"
    
    success "Cleanup process completed!"
    log "Thank you for using Azure Cost-Optimized Content Generation solution"
}

# Show help if requested
if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
    echo "Azure Cost-Optimized Content Generation Cleanup Script"
    echo ""
    echo "Usage: $0 [resource-group-name]"
    echo ""
    echo "This script safely removes all Azure resources created for the content generation solution."
    echo ""
    echo "Options:"
    echo "  -h, --help    Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 rg-content-generation-abc123    # Clean up specific resource group"
    echo "  $0                                 # Auto-detect from deployment info files"
    echo ""
    echo "Safety Features:"
    echo "- Double confirmation prompts"
    echo "- Resource backup before deletion"
    echo "- Ordered resource removal"
    echo "- Cleanup verification"
    echo ""
    exit 0
fi

# Run main function
main "$@"