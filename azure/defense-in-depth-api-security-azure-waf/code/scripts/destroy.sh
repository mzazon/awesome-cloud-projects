#!/bin/bash

# Destroy Azure Zero-Trust API Security Infrastructure
# This script removes all resources created by deploy.sh to avoid ongoing charges

set -e  # Exit on any error
set -o pipefail  # Exit on pipe failures

# Color codes for output formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
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

# Check if script is run with dry-run flag
DRY_RUN=false
FORCE=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            warning "Running in DRY-RUN mode - no resources will be deleted"
            shift
            ;;
        --force)
            FORCE=true
            shift
            ;;
        *)
            echo "Unknown option $1"
            echo "Usage: $0 [--dry-run] [--force]"
            exit 1
            ;;
    esac
done

# Function to execute commands (respects dry-run mode)
execute() {
    if [[ "$DRY_RUN" == "true" ]]; then
        echo -e "${YELLOW}[DRY-RUN]${NC} Would execute: $1"
    else
        log "Executing: $1"
        eval "$1" || true  # Continue on errors during cleanup
    fi
}

log "Starting Azure Zero-Trust API Security infrastructure cleanup..."

# Load environment variables from .env file
if [[ -f ".env" ]]; then
    log "Loading environment variables from .env file..."
    source .env
else
    error ".env file not found. This file should have been created by deploy.sh"
    echo "Please ensure you're running this script from the same directory as deploy.sh"
    echo "Or set environment variables manually:"
    echo "  export RESOURCE_GROUP=\"your-resource-group-name\""
    echo "  export SUBSCRIPTION_ID=\"your-subscription-id\""
    
    # Try to get basic info if user is logged in
    if az account show &> /dev/null; then
        SUBSCRIPTION_ID=$(az account show --query id --output tsv)
        echo ""
        echo "Current subscription: $SUBSCRIPTION_ID"
        echo "Available resource groups with 'zero-trust' in name:"
        az group list --query "[?contains(name, 'zero-trust')].{Name:name, Location:location}" --output table 2>/dev/null || true
    fi
    
    exit 1
fi

# Verify required environment variables
if [[ -z "$RESOURCE_GROUP" ]]; then
    error "RESOURCE_GROUP environment variable is not set"
    exit 1
fi

if [[ -z "$SUBSCRIPTION_ID" ]]; then
    error "SUBSCRIPTION_ID environment variable is not set"
    exit 1
fi

# Prerequisites validation
log "Validating prerequisites..."

# Check if Azure CLI is installed
if ! command -v az &> /dev/null; then
    error "Azure CLI is not installed. Please install it from https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
    exit 1
fi

# Check if user is logged in to Azure
if ! az account show &> /dev/null; then
    error "Not logged in to Azure. Please run 'az login' first"
    exit 1
fi

# Verify subscription
CURRENT_SUBSCRIPTION=$(az account show --query id --output tsv)
if [[ "$CURRENT_SUBSCRIPTION" != "$SUBSCRIPTION_ID" ]]; then
    warning "Current subscription ($CURRENT_SUBSCRIPTION) doesn't match expected subscription ($SUBSCRIPTION_ID)"
    if [[ "$FORCE" == "false" ]]; then
        echo "Use --force to continue anyway, or switch to the correct subscription:"
        echo "  az account set --subscription $SUBSCRIPTION_ID"
        exit 1
    fi
fi

success "Prerequisites validation completed"

# Check if resource group exists
log "Checking if resource group exists..."
if ! az group exists --name "$RESOURCE_GROUP" &> /dev/null; then
    warning "Resource group '$RESOURCE_GROUP' does not exist or you don't have access to it"
    if [[ "$FORCE" == "false" ]]; then
        echo "Use --force to skip this check"
        exit 1
    fi
else
    success "Resource group '$RESOURCE_GROUP' found"
fi

# Display what will be deleted
echo ""
warning "=== RESOURCES TO BE DELETED ==="
log "Resource Group: $RESOURCE_GROUP"
log "Subscription: $SUBSCRIPTION_ID"

if [[ -n "$VNET_NAME" ]]; then log "Virtual Network: $VNET_NAME"; fi
if [[ -n "$APIM_NAME" ]]; then log "API Management: $APIM_NAME"; fi
if [[ -n "$AGW_NAME" ]]; then log "Application Gateway: $AGW_NAME"; fi
if [[ -n "$WAF_POLICY_NAME" ]]; then log "WAF Policy: $WAF_POLICY_NAME"; fi
if [[ -n "$LOG_WORKSPACE_NAME" ]]; then log "Log Analytics: $LOG_WORKSPACE_NAME"; fi
if [[ -n "$APP_INSIGHTS_NAME" ]]; then log "Application Insights: $APP_INSIGHTS_NAME"; fi

echo ""

# Confirmation prompt (skip in dry-run or force mode)
if [[ "$DRY_RUN" == "false" && "$FORCE" == "false" ]]; then
    warning "This will PERMANENTLY DELETE all resources in the resource group '$RESOURCE_GROUP'"
    warning "This action CANNOT be undone!"
    echo ""
    read -p "Are you sure you want to continue? (Type 'yes' to confirm): " confirm
    
    if [[ "$confirm" != "yes" ]]; then
        log "Cleanup cancelled by user"
        exit 0
    fi
fi

# Start cleanup process
log "Starting resource cleanup..."

# Function to safely delete a resource
safe_delete() {
    local resource_type="$1"
    local resource_name="$2"
    local delete_command="$3"
    
    log "Checking if $resource_type '$resource_name' exists..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        echo -e "${YELLOW}[DRY-RUN]${NC} Would delete $resource_type: $resource_name"
        return
    fi
    
    # Check if resource exists before attempting deletion
    case "$resource_type" in
        "Application Gateway")
            if az network application-gateway show --resource-group "$RESOURCE_GROUP" --name "$resource_name" &> /dev/null; then
                execute "$delete_command"
            else
                log "$resource_type '$resource_name' not found, skipping"
            fi
            ;;
        "Public IP")
            if az network public-ip show --resource-group "$RESOURCE_GROUP" --name "$resource_name" &> /dev/null; then
                execute "$delete_command"
            else
                log "$resource_type '$resource_name' not found, skipping"
            fi
            ;;
        "API Management")
            if az apim show --resource-group "$RESOURCE_GROUP" --name "$resource_name" &> /dev/null; then
                warning "API Management deletion is a long-running operation (10-15 minutes)"
                execute "$delete_command"
            else
                log "$resource_type '$resource_name' not found, skipping"
            fi
            ;;
        "WAF Policy")
            if az network application-gateway waf-policy show --resource-group "$RESOURCE_GROUP" --name "$resource_name" &> /dev/null; then
                execute "$delete_command"
            else
                log "$resource_type '$resource_name' not found, skipping"
            fi
            ;;
        "Private Endpoint")
            if az network private-endpoint show --resource-group "$RESOURCE_GROUP" --name "$resource_name" &> /dev/null; then
                execute "$delete_command"
            else
                log "$resource_type '$resource_name' not found, skipping"
            fi
            ;;
        "Private DNS Zone")
            if az network private-dns zone show --resource-group "$RESOURCE_GROUP" --name "$resource_name" &> /dev/null; then
                execute "$delete_command"
            else
                log "$resource_type '$resource_name' not found, skipping"
            fi
            ;;
        *)
            execute "$delete_command"
            ;;
    esac
}

# Remove Application Gateway first (depends on other resources)
if [[ -n "$AGW_NAME" ]]; then
    safe_delete "Application Gateway" "$AGW_NAME" \
        "az network application-gateway delete --resource-group \$RESOURCE_GROUP --name \$AGW_NAME --no-wait"
    success "Application Gateway deletion initiated"
fi

# Remove Public IP
if [[ -n "$AGW_NAME" ]]; then
    safe_delete "Public IP" "${AGW_NAME}-pip" \
        "az network public-ip delete --resource-group \$RESOURCE_GROUP --name \${AGW_NAME}-pip"
    success "Public IP deleted"
fi

# Remove API Management (long-running operation)
if [[ -n "$APIM_NAME" ]]; then
    safe_delete "API Management" "$APIM_NAME" \
        "az apim delete --resource-group \$RESOURCE_GROUP --name \$APIM_NAME --no-wait"
    success "API Management deletion initiated"
fi

# Remove WAF Policy
if [[ -n "$WAF_POLICY_NAME" ]]; then
    safe_delete "WAF Policy" "$WAF_POLICY_NAME" \
        "az network application-gateway waf-policy delete --resource-group \$RESOURCE_GROUP --name \$WAF_POLICY_NAME"
    success "WAF Policy deleted"
fi

# Remove Private Endpoints and DNS zones
safe_delete "Private Endpoint" "pe-backend" \
    "az network private-endpoint delete --resource-group \$RESOURCE_GROUP --name pe-backend"

safe_delete "Private DNS Zone" "privatelink.azure-api.net" \
    "az network private-dns zone delete --resource-group \$RESOURCE_GROUP --name privatelink.azure-api.net --yes"

success "Private networking resources deleted"

# Wait a moment for Application Gateway deletion to progress before removing the entire resource group
if [[ "$DRY_RUN" == "false" ]]; then
    log "Waiting 30 seconds for long-running deletions to register..."
    sleep 30
fi

# Remove entire resource group (this will clean up any remaining resources)
log "Deleting resource group and all remaining resources..."

if [[ "$DRY_RUN" == "false" ]]; then
    # Check one more time if resource group exists
    if az group exists --name "$RESOURCE_GROUP" &> /dev/null; then
        execute "az group delete --name \$RESOURCE_GROUP --yes --no-wait"
        success "Resource group deletion initiated: $RESOURCE_GROUP"
        
        log "Cleanup initiated successfully. Long-running operations will continue in the background."
        warning "Complete cleanup may take 30-45 minutes due to API Management deletion"
        
        # Optionally wait for completion
        echo ""
        read -p "Would you like to wait for cleanup completion? (y/n): " wait_confirm
        
        if [[ "$wait_confirm" =~ ^[Yy]$ ]]; then
            log "Waiting for resource group deletion to complete..."
            
            # Poll for resource group existence
            while az group exists --name "$RESOURCE_GROUP" &> /dev/null; do
                log "Resource group still exists, checking again in 60 seconds..."
                sleep 60
            done
            
            success "Resource group '$RESOURCE_GROUP' has been completely deleted"
        else
            log "You can check deletion status with: az group exists --name $RESOURCE_GROUP"
        fi
    else
        warning "Resource group '$RESOURCE_GROUP' no longer exists"
    fi
fi

# Clean up local files
log "Cleaning up local files..."
if [[ -f ".env" ]]; then
    if [[ "$DRY_RUN" == "false" ]]; then
        rm -f .env
        success "Removed .env file"
    else
        echo -e "${YELLOW}[DRY-RUN]${NC} Would remove .env file"
    fi
fi

if [[ -f "security-policy.xml" ]]; then
    if [[ "$DRY_RUN" == "false" ]]; then
        rm -f security-policy.xml
        success "Removed temporary security-policy.xml file"
    else
        echo -e "${YELLOW}[DRY-RUN]${NC} Would remove security-policy.xml file"
    fi
fi

# Final status
echo ""
if [[ "$DRY_RUN" == "true" ]]; then
    warning "=== DRY-RUN COMPLETED ==="
    log "This was a dry-run. No resources were actually deleted."
    log "Run without --dry-run flag to perform the actual cleanup"
else
    success "=== CLEANUP COMPLETED ==="
    log "All Azure Zero-Trust API Security resources have been scheduled for deletion"
    log "Monitor the Azure portal or use Azure CLI to verify complete cleanup"
    
    # Provide verification command
    echo ""
    log "To verify cleanup completion, run:"
    log "  az group exists --name $RESOURCE_GROUP"
    log "  (should return 'false' when cleanup is complete)"
fi

echo ""
log "Cleanup process finished"