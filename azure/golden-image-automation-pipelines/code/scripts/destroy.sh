#!/bin/bash

# Destroy Azure VM Image Builder with Private DNS Resolver
# This script removes all resources created by the deployment script

set -e
set -o pipefail

# Colors for output
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
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ❌ $1${NC}" >&2
}

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check Azure CLI
    if ! command -v az &> /dev/null; then
        error "Azure CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if logged in
    if ! az account show &> /dev/null; then
        error "Not logged in to Azure. Please run 'az login' first."
        exit 1
    fi
    
    success "Prerequisites check passed"
}

# Load deployment information
load_deployment_info() {
    log "Loading deployment information..."
    
    # Check if deployment-info.txt exists
    if [ ! -f "deployment-info.txt" ]; then
        warning "deployment-info.txt not found. You'll need to provide resource information manually."
        
        # Prompt for resource group name
        read -p "Enter the resource group name to delete: " RESOURCE_GROUP
        
        if [ -z "$RESOURCE_GROUP" ]; then
            error "Resource group name is required."
            exit 1
        fi
        
        # Set default values
        export SUBSCRIPTION_ID=$(az account show --query id --output tsv)
        export LOCATION="eastus"
        
        # Try to extract resource suffix from resource group name
        if [[ $RESOURCE_GROUP =~ rg-golden-image-([a-f0-9]+) ]]; then
            RANDOM_SUFFIX="${BASH_REMATCH[1]}"
            export HUB_VNET_NAME="vnet-hub-${RANDOM_SUFFIX}"
            export BUILD_VNET_NAME="vnet-build-${RANDOM_SUFFIX}"
            export PRIVATE_DNS_RESOLVER_NAME="pdns-resolver-${RANDOM_SUFFIX}"
            export COMPUTE_GALLERY_NAME="gallery${RANDOM_SUFFIX}"
            export IMAGE_TEMPLATE_NAME="template-ubuntu-${RANDOM_SUFFIX}"
            export MANAGED_IDENTITY_NAME="id-image-builder-${RANDOM_SUFFIX}"
        else
            warning "Cannot extract resource names from resource group. Will attempt to list resources."
        fi
    else
        # Extract information from deployment-info.txt
        export RESOURCE_GROUP=$(grep "Resource Group:" deployment-info.txt | cut -d' ' -f3)
        export SUBSCRIPTION_ID=$(grep "Subscription ID:" deployment-info.txt | cut -d' ' -f3)
        export HUB_VNET_NAME=$(grep "Hub Virtual Network:" deployment-info.txt | cut -d' ' -f4)
        export BUILD_VNET_NAME=$(grep "Build Virtual Network:" deployment-info.txt | cut -d' ' -f4)
        export PRIVATE_DNS_RESOLVER_NAME=$(grep "Private DNS Resolver:" deployment-info.txt | cut -d' ' -f4)
        export COMPUTE_GALLERY_NAME=$(grep "Compute Gallery:" deployment-info.txt | cut -d' ' -f3)
        export IMAGE_TEMPLATE_NAME=$(grep "Image Template:" deployment-info.txt | cut -d' ' -f3)
        export MANAGED_IDENTITY_NAME=$(grep "Managed Identity:" deployment-info.txt | cut -d' ' -f3)
    fi
    
    log "Deployment information loaded:"
    log "  Resource Group: ${RESOURCE_GROUP}"
    log "  Subscription ID: ${SUBSCRIPTION_ID}"
    
    success "Deployment information loaded successfully"
}

# Confirm destruction
confirm_destruction() {
    log "This will permanently delete all resources in the resource group: ${RESOURCE_GROUP}"
    
    # List resources in the resource group
    log "Resources to be deleted:"
    az resource list --resource-group ${RESOURCE_GROUP} --query "[].{Name:name, Type:type}" --output table 2>/dev/null || {
        warning "Unable to list resources. Resource group may not exist or may be empty."
    }
    
    # Confirmation prompt
    echo ""
    warning "This action cannot be undone!"
    read -p "Are you sure you want to delete all resources? (type 'yes' to confirm): " confirmation
    
    if [ "$confirmation" != "yes" ]; then
        log "Destruction cancelled by user."
        exit 0
    fi
    
    success "Destruction confirmed"
}

# Cancel any running image builds
cancel_image_builds() {
    log "Checking for running image builds..."
    
    if [ -n "$IMAGE_TEMPLATE_NAME" ]; then
        # Check if image template exists and has a running build
        BUILD_STATUS=$(az image builder show \
            --name ${IMAGE_TEMPLATE_NAME} \
            --resource-group ${RESOURCE_GROUP} \
            --query properties.lastRunStatus.runState \
            --output tsv 2>/dev/null || echo "NotFound")
        
        if [ "$BUILD_STATUS" == "Running" ]; then
            warning "Image build is currently running. Cancelling..."
            
            # Cancel the build
            az image builder cancel \
                --name ${IMAGE_TEMPLATE_NAME} \
                --resource-group ${RESOURCE_GROUP} || {
                warning "Failed to cancel image build. Continuing with destruction..."
            }
            
            # Wait for cancellation to complete
            sleep 30
            
            success "Image build cancelled"
        elif [ "$BUILD_STATUS" == "NotFound" ]; then
            log "Image template not found or already deleted"
        else
            log "Image build status: ${BUILD_STATUS}"
        fi
    else
        log "Image template name not available. Skipping build cancellation."
    fi
}

# Remove custom role definitions
remove_custom_roles() {
    log "Removing custom role definitions..."
    
    # Remove custom role definition if it exists
    CUSTOM_ROLE_ID=$(az role definition list \
        --name "Image Builder Gallery Role" \
        --query "[0].id" \
        --output tsv 2>/dev/null || echo "")
    
    if [ -n "$CUSTOM_ROLE_ID" ] && [ "$CUSTOM_ROLE_ID" != "null" ]; then
        log "Removing custom role definition: ${CUSTOM_ROLE_ID}"
        az role definition delete --id ${CUSTOM_ROLE_ID} || {
            warning "Failed to remove custom role definition. Continuing..."
        }
        success "Custom role definition removed"
    else
        log "Custom role definition not found or already removed"
    fi
}

# Remove role assignments
remove_role_assignments() {
    log "Removing role assignments..."
    
    if [ -n "$MANAGED_IDENTITY_NAME" ]; then
        # Get managed identity principal ID
        IDENTITY_PRINCIPAL_ID=$(az identity show \
            --name ${MANAGED_IDENTITY_NAME} \
            --resource-group ${RESOURCE_GROUP} \
            --query principalId \
            --output tsv 2>/dev/null || echo "")
        
        if [ -n "$IDENTITY_PRINCIPAL_ID" ] && [ "$IDENTITY_PRINCIPAL_ID" != "null" ]; then
            log "Removing role assignments for managed identity: ${IDENTITY_PRINCIPAL_ID}"
            
            # Remove role assignments
            ROLE_ASSIGNMENTS=$(az role assignment list \
                --assignee ${IDENTITY_PRINCIPAL_ID} \
                --query "[].id" \
                --output tsv 2>/dev/null || echo "")
            
            if [ -n "$ROLE_ASSIGNMENTS" ]; then
                for assignment in $ROLE_ASSIGNMENTS; do
                    log "Removing role assignment: ${assignment}"
                    az role assignment delete --ids ${assignment} || {
                        warning "Failed to remove role assignment: ${assignment}"
                    }
                done
                success "Role assignments removed"
            else
                log "No role assignments found for managed identity"
            fi
        else
            log "Managed identity not found or already removed"
        fi
    else
        log "Managed identity name not available. Skipping role assignment removal."
    fi
}

# Delete specific high-level resources first
delete_high_level_resources() {
    log "Deleting high-level resources..."
    
    # Delete VM Image Builder template
    if [ -n "$IMAGE_TEMPLATE_NAME" ]; then
        log "Deleting VM Image Builder template: ${IMAGE_TEMPLATE_NAME}"
        az image builder delete \
            --name ${IMAGE_TEMPLATE_NAME} \
            --resource-group ${RESOURCE_GROUP} \
            --no-wait || {
            warning "Failed to delete image template or it doesn't exist"
        }
    fi
    
    # Delete compute gallery
    if [ -n "$COMPUTE_GALLERY_NAME" ]; then
        log "Deleting Compute Gallery: ${COMPUTE_GALLERY_NAME}"
        az sig delete \
            --gallery-name ${COMPUTE_GALLERY_NAME} \
            --resource-group ${RESOURCE_GROUP} \
            --no-wait || {
            warning "Failed to delete compute gallery or it doesn't exist"
        }
    fi
    
    # Delete DNS resolver
    if [ -n "$PRIVATE_DNS_RESOLVER_NAME" ]; then
        log "Deleting Private DNS Resolver: ${PRIVATE_DNS_RESOLVER_NAME}"
        az dns-resolver delete \
            --name ${PRIVATE_DNS_RESOLVER_NAME} \
            --resource-group ${RESOURCE_GROUP} \
            --no-wait || {
            warning "Failed to delete DNS resolver or it doesn't exist"
        }
    fi
    
    # Delete virtual network peerings
    if [ -n "$BUILD_VNET_NAME" ] && [ -n "$HUB_VNET_NAME" ]; then
        log "Deleting virtual network peerings..."
        
        az network vnet peering delete \
            --name "build-to-hub" \
            --resource-group ${RESOURCE_GROUP} \
            --vnet-name ${BUILD_VNET_NAME} \
            --no-wait || {
            warning "Failed to delete build-to-hub peering or it doesn't exist"
        }
        
        az network vnet peering delete \
            --name "hub-to-build" \
            --resource-group ${RESOURCE_GROUP} \
            --vnet-name ${HUB_VNET_NAME} \
            --no-wait || {
            warning "Failed to delete hub-to-build peering or it doesn't exist"
        }
    fi
    
    success "High-level resources deletion initiated"
}

# Wait for async operations to complete
wait_for_deletions() {
    log "Waiting for resource deletions to complete..."
    
    # Wait for critical resources to be deleted
    local max_wait=300  # 5 minutes
    local wait_time=0
    
    while [ $wait_time -lt $max_wait ]; do
        # Check if DNS resolver still exists
        if [ -n "$PRIVATE_DNS_RESOLVER_NAME" ]; then
            RESOLVER_EXISTS=$(az dns-resolver show \
                --name ${PRIVATE_DNS_RESOLVER_NAME} \
                --resource-group ${RESOURCE_GROUP} \
                --query name \
                --output tsv 2>/dev/null || echo "")
            
            if [ -z "$RESOLVER_EXISTS" ]; then
                log "DNS resolver deletion completed"
                break
            fi
        else
            break
        fi
        
        log "Waiting for resources to be deleted... (${wait_time}s/${max_wait}s)"
        sleep 30
        wait_time=$((wait_time + 30))
    done
    
    if [ $wait_time -ge $max_wait ]; then
        warning "Timeout waiting for resources to be deleted. Proceeding with resource group deletion."
    fi
}

# Delete entire resource group
delete_resource_group() {
    log "Deleting resource group: ${RESOURCE_GROUP}"
    
    # Check if resource group exists
    if az group show --name ${RESOURCE_GROUP} &> /dev/null; then
        log "Deleting resource group and all contained resources..."
        
        # Delete resource group (this will delete all resources within it)
        az group delete \
            --name ${RESOURCE_GROUP} \
            --yes \
            --no-wait
        
        success "Resource group deletion initiated: ${RESOURCE_GROUP}"
        log "Note: Complete deletion may take several minutes to finish."
        
        # Optional: Wait for resource group deletion to complete
        read -p "Do you want to wait for the resource group deletion to complete? (y/n): " wait_confirm
        
        if [ "$wait_confirm" == "y" ] || [ "$wait_confirm" == "Y" ]; then
            log "Waiting for resource group deletion to complete..."
            
            local max_wait=1800  # 30 minutes
            local wait_time=0
            
            while [ $wait_time -lt $max_wait ]; do
                if ! az group show --name ${RESOURCE_GROUP} &> /dev/null; then
                    success "Resource group deletion completed"
                    break
                fi
                
                log "Waiting for resource group deletion... (${wait_time}s/${max_wait}s)"
                sleep 30
                wait_time=$((wait_time + 30))
            done
            
            if [ $wait_time -ge $max_wait ]; then
                warning "Timeout waiting for resource group deletion. Check Azure portal for status."
            fi
        fi
    else
        log "Resource group ${RESOURCE_GROUP} not found or already deleted"
    fi
}

# Clean up local files
cleanup_local_files() {
    log "Cleaning up local files..."
    
    # Remove generated files
    local files_to_remove=(
        "image-template.json"
        "azure-pipelines.yml"
        "image-builder-role.json"
        "deployment-info.txt"
    )
    
    for file in "${files_to_remove[@]}"; do
        if [ -f "$file" ]; then
            log "Removing file: $file"
            rm -f "$file"
        fi
    done
    
    success "Local files cleaned up"
}

# Verify destruction
verify_destruction() {
    log "Verifying destruction..."
    
    # Check if resource group still exists
    if az group show --name ${RESOURCE_GROUP} &> /dev/null; then
        warning "Resource group still exists. Deletion may be in progress."
        log "You can check the status in the Azure portal or run: az group show --name ${RESOURCE_GROUP}"
    else
        success "Resource group successfully deleted"
    fi
    
    # Check for remaining role definitions
    REMAINING_ROLES=$(az role definition list \
        --name "Image Builder Gallery Role" \
        --query "[].name" \
        --output tsv 2>/dev/null || echo "")
    
    if [ -n "$REMAINING_ROLES" ]; then
        warning "Custom role definitions may still exist. Consider removing them manually."
    else
        success "Custom role definitions cleaned up"
    fi
}

# Main execution
main() {
    log "Starting Azure VM Image Builder with Private DNS Resolver destruction..."
    
    # Store destruction info
    export DESTRUCTION_START_TIME=$(date)
    
    # Execute destruction steps
    check_prerequisites
    load_deployment_info
    confirm_destruction
    cancel_image_builds
    remove_custom_roles
    remove_role_assignments
    delete_high_level_resources
    wait_for_deletions
    delete_resource_group
    cleanup_local_files
    verify_destruction
    
    success "Destruction process completed!"
    
    log "Destruction Summary:"
    log "  Started at: ${DESTRUCTION_START_TIME}"
    log "  Completed at: $(date)"
    log "  Resource Group: ${RESOURCE_GROUP}"
    
    warning "Note: Some resources may take additional time to be completely removed."
    warning "Check the Azure portal to confirm all resources have been deleted."
    
    log "If you need to recreate the infrastructure, run: ./deploy.sh"
}

# Error handling
trap 'error "Script failed on line $LINENO. Check the logs for details."' ERR

# Run main function
main "$@"