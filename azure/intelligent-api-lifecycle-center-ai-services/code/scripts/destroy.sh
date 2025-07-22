#!/bin/bash

# Destroy Azure Intelligent API Lifecycle Management Solution
# This script safely removes all resources created by the deploy script
# Version: 1.1
# Last Updated: 2025-07-12

set -euo pipefail

# Color codes for output
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
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✅ $1${NC}"
}

warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️  $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ❌ $1${NC}"
}

# Parse command line arguments
DRY_RUN=false
FORCE_DELETE=false
RESOURCE_GROUP=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --force)
            FORCE_DELETE=true
            shift
            ;;
        --resource-group|-g)
            RESOURCE_GROUP="$2"
            shift 2
            ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo "Options:"
            echo "  --dry-run              Show what would be deleted without removing resources"
            echo "  --force                Skip confirmation prompts"
            echo "  --resource-group, -g   Specify the resource group name to delete"
            echo "  --help, -h             Show this help message"
            echo ""
            echo "Examples:"
            echo "  $0 --resource-group rg-api-lifecycle-a1b2c3"
            echo "  $0 --dry-run --resource-group rg-api-lifecycle-a1b2c3"
            echo "  $0 --force --resource-group rg-api-lifecycle-a1b2c3"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Function to execute command with dry-run support
execute_command() {
    local cmd="$1"
    local description="$2"
    
    if [ "$DRY_RUN" = true ]; then
        log "DRY RUN: $description"
        log "Command: $cmd"
        return 0
    else
        log "$description"
        eval "$cmd"
        return $?
    fi
}

# Display script header
echo -e "${BLUE}================================================"
echo "Azure API Lifecycle Management Cleanup"
echo "Recipe: Intelligent API Center with AI Services"
echo "Version: 1.1"
echo "================================================${NC}"

if [ "$DRY_RUN" = true ]; then
    warning "Running in dry-run mode. No resources will be deleted."
fi

# Check prerequisites
log "Checking prerequisites..."

# Check if Azure CLI is installed
if ! command -v az &> /dev/null; then
    error "Azure CLI is not installed. Please install it first."
fi

# Check if user is logged in
if ! az account show &> /dev/null; then
    error "Please log in to Azure CLI using 'az login'"
fi

success "Prerequisites check passed"

# Function to detect resource group from config files
detect_resource_group() {
    local config_files=(deployment-config-*.env)
    
    if [ ${#config_files[@]} -eq 1 ] && [ -f "${config_files[0]}" ]; then
        # Source the config file to get resource group
        source "${config_files[0]}"
        if [ -n "${RESOURCE_GROUP:-}" ]; then
            log "Found resource group in config file: $RESOURCE_GROUP"
            return 0
        fi
    fi
    
    # Look for resource groups matching the pattern
    local matching_groups
    matching_groups=$(az group list --query "[?starts_with(name, 'rg-api-lifecycle-')].name" --output tsv 2>/dev/null || true)
    
    if [ -n "$matching_groups" ]; then
        local group_count
        group_count=$(echo "$matching_groups" | wc -l)
        
        if [ "$group_count" -eq 1 ]; then
            RESOURCE_GROUP="$matching_groups"
            log "Found matching resource group: $RESOURCE_GROUP"
            return 0
        elif [ "$group_count" -gt 1 ]; then
            warning "Multiple matching resource groups found:"
            echo "$matching_groups"
            return 1
        fi
    fi
    
    return 1
}

# Determine resource group to delete
if [ -z "$RESOURCE_GROUP" ]; then
    log "No resource group specified. Attempting to detect..."
    
    if ! detect_resource_group; then
        error "Could not automatically detect resource group. Please specify with --resource-group option."
    fi
fi

# Verify resource group exists
if ! az group show --name "$RESOURCE_GROUP" &> /dev/null; then
    error "Resource group '$RESOURCE_GROUP' does not exist or is not accessible."
fi

# Get subscription info
SUBSCRIPTION_ID=$(az account show --query id --output tsv)
TENANT_ID=$(az account show --query tenantId --output tsv)
log "Using subscription: $SUBSCRIPTION_ID"
log "Target resource group: $RESOURCE_GROUP"

# List resources in the resource group
log "Analyzing resources in resource group..."
resource_count=$(az resource list --resource-group "$RESOURCE_GROUP" --query "length(@)" --output tsv 2>/dev/null || echo "0")

if [ "$resource_count" -eq 0 ]; then
    warning "No resources found in resource group '$RESOURCE_GROUP'"
    log "Resource group appears to be empty or already cleaned up."
    exit 0
fi

log "Found $resource_count resources in resource group '$RESOURCE_GROUP'"

# Display resources to be deleted
if [ "$DRY_RUN" = true ] || [ "$FORCE_DELETE" = false ]; then
    log "Resources that will be deleted:"
    az resource list --resource-group "$RESOURCE_GROUP" --query "[].{Name:name, Type:type, Location:location}" --output table
fi

# Confirmation prompt (skip if --force flag is used)
if [ "$FORCE_DELETE" = false ] && [ "$DRY_RUN" = false ]; then
    echo
    warning "This will permanently delete ALL resources in the resource group '$RESOURCE_GROUP'!"
    warning "This action cannot be undone!"
    echo
    read -p "Are you sure you want to proceed? Type 'yes' to continue: " -r
    echo
    if [[ ! $REPLY == "yes" ]]; then
        log "Deletion cancelled by user"
        exit 0
    fi
fi

# Function to delete individual resources (for safer cleanup)
delete_resources_individually() {
    log "Deleting resources individually for safer cleanup..."
    
    # Get list of resources sorted by dependency order (reverse creation order)
    local resources
    resources=$(az resource list --resource-group "$RESOURCE_GROUP" --query "[].{id:id, type:type, name:name}" --output json)
    
    # Delete Logic Apps first
    echo "$resources" | jq -r '.[] | select(.type == "Microsoft.Logic/workflows") | .id' | while read -r resource_id; do
        if [ -n "$resource_id" ]; then
            execute_command "az resource delete --ids '$resource_id' --output none" \
                "Deleting Logic App: $(basename "$resource_id")"
        fi
    done
    
    # Delete API Management instances
    echo "$resources" | jq -r '.[] | select(.type == "Microsoft.ApiManagement/service") | .id' | while read -r resource_id; do
        if [ -n "$resource_id" ]; then
            execute_command "az resource delete --ids '$resource_id' --output none" \
                "Deleting API Management: $(basename "$resource_id")"
        fi
    done
    
    # Delete Cognitive Services (OpenAI, Anomaly Detector)
    echo "$resources" | jq -r '.[] | select(.type == "Microsoft.CognitiveServices/accounts") | .id' | while read -r resource_id; do
        if [ -n "$resource_id" ]; then
            execute_command "az resource delete --ids '$resource_id' --output none" \
                "Deleting Cognitive Service: $(basename "$resource_id")"
        fi
    done
    
    # Delete Application Insights
    echo "$resources" | jq -r '.[] | select(.type == "Microsoft.Insights/components") | .id' | while read -r resource_id; do
        if [ -n "$resource_id" ]; then
            execute_command "az resource delete --ids '$resource_id' --output none" \
                "Deleting Application Insights: $(basename "$resource_id")"
        fi
    done
    
    # Delete Storage Accounts
    echo "$resources" | jq -r '.[] | select(.type == "Microsoft.Storage/storageAccounts") | .id' | while read -r resource_id; do
        if [ -n "$resource_id" ]; then
            execute_command "az resource delete --ids '$resource_id' --output none" \
                "Deleting Storage Account: $(basename "$resource_id")"
        fi
    done
    
    # Delete API Center
    echo "$resources" | jq -r '.[] | select(.type == "Microsoft.ApiCenter/services") | .id' | while read -r resource_id; do
        if [ -n "$resource_id" ]; then
            execute_command "az resource delete --ids '$resource_id' --output none" \
                "Deleting API Center: $(basename "$resource_id")"
        fi
    done
    
    # Delete Log Analytics Workspace
    echo "$resources" | jq -r '.[] | select(.type == "Microsoft.OperationalInsights/workspaces") | .id' | while read -r resource_id; do
        if [ -n "$resource_id" ]; then
            execute_command "az resource delete --ids '$resource_id' --output none" \
                "Deleting Log Analytics Workspace: $(basename "$resource_id")"
        fi
    done
    
    # Delete any remaining resources
    echo "$resources" | jq -r '.[] | .id' | while read -r resource_id; do
        if [ -n "$resource_id" ]; then
            # Check if resource still exists
            if az resource show --ids "$resource_id" &> /dev/null; then
                execute_command "az resource delete --ids '$resource_id' --output none" \
                    "Deleting remaining resource: $(basename "$resource_id")"
            fi
        fi
    done
}

# Function to delete entire resource group
delete_resource_group() {
    log "Deleting entire resource group..."
    
    execute_command "az group delete --name '$RESOURCE_GROUP' --yes --output none" \
        "Deleting resource group: $RESOURCE_GROUP"
}

# Main cleanup process
log "Starting cleanup process..."

# Check if jq is available for individual resource deletion
if command -v jq &> /dev/null; then
    log "Using individual resource deletion for safer cleanup..."
    delete_resources_individually
    
    # Wait a moment for resources to be deleted
    if [ "$DRY_RUN" = false ]; then
        log "Waiting for individual resource deletions to complete..."
        sleep 10
    fi
    
    # Check if any resources remain and delete the resource group
    if [ "$DRY_RUN" = false ]; then
        remaining_resources=$(az resource list --resource-group "$RESOURCE_GROUP" --query "length(@)" --output tsv 2>/dev/null || echo "0")
        if [ "$remaining_resources" -gt 0 ]; then
            warning "Some resources still remain. Deleting resource group to ensure complete cleanup."
            delete_resource_group
        else
            log "All individual resources deleted successfully."
            execute_command "az group delete --name '$RESOURCE_GROUP' --yes --output none" \
                "Deleting empty resource group: $RESOURCE_GROUP"
        fi
    fi
else
    warning "jq not found. Using resource group deletion method."
    delete_resource_group
fi

# Verify deletion
if [ "$DRY_RUN" = false ]; then
    log "Verifying resource group deletion..."
    
    # Wait for deletion to complete
    local max_wait=300  # 5 minutes
    local wait_time=0
    
    while az group show --name "$RESOURCE_GROUP" &> /dev/null; do
        if [ $wait_time -ge $max_wait ]; then
            warning "Resource group deletion is taking longer than expected."
            warning "Please check the Azure portal for deletion status."
            break
        fi
        
        log "Waiting for resource group deletion to complete... (${wait_time}s/${max_wait}s)"
        sleep 10
        wait_time=$((wait_time + 10))
    done
    
    if ! az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        success "Resource group '$RESOURCE_GROUP' has been successfully deleted"
    else
        warning "Resource group '$RESOURCE_GROUP' may still be in the process of being deleted"
    fi
fi

# Clean up local configuration files
log "Cleaning up local configuration files..."
config_files=(deployment-config-*.env)
for config_file in "${config_files[@]}"; do
    if [ -f "$config_file" ]; then
        if [ "$DRY_RUN" = true ]; then
            log "DRY RUN: Would delete config file: $config_file"
        else
            rm -f "$config_file"
            success "Deleted config file: $config_file"
        fi
    fi
done

# Display cleanup summary
echo
echo -e "${GREEN}================================================"
echo "          CLEANUP COMPLETED SUCCESSFULLY"
echo "================================================${NC}"
echo
echo "📋 Cleanup Summary:"
echo "   • Resource Group: $RESOURCE_GROUP"
echo "   • Resources Deleted: $resource_count"
echo "   • Subscription: $SUBSCRIPTION_ID"
echo
echo "🔍 Verification:"
echo "   • Check Azure Portal to confirm all resources are deleted"
echo "   • Review billing to ensure no ongoing charges"
echo
echo "⚠️  Important Notes:"
echo "   • Some resources may take additional time to fully delete"
echo "   • Billing may show usage for the current billing period"
echo "   • Soft-deleted resources may still be recoverable for a limited time"
echo

if [ "$DRY_RUN" = true ]; then
    warning "This was a dry run. No resources were actually deleted."
    log "To perform actual cleanup, run: $0 --resource-group $RESOURCE_GROUP"
else
    success "Cleanup script completed successfully!"
fi