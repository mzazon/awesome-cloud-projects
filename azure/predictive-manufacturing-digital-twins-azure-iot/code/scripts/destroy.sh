#!/bin/bash

# Azure Smart Manufacturing Digital Twins Cleanup Script
# This script safely removes all resources created by the deployment script

set -e
set -o pipefail

# Color codes for output formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

# Error handling function
handle_error() {
    log_error "Cleanup failed at line $1. Some resources may still exist."
    log_info "Please check the Azure Portal and manually clean up remaining resources."
    exit 1
}

trap 'handle_error $LINENO' ERR

# Print banner
echo "========================================================================"
echo "Azure Smart Manufacturing Digital Twins Cleanup"
echo "========================================================================"
echo ""

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        log_error "Azure CLI is not installed."
        exit 1
    fi
    
    # Check if user is logged in to Azure
    if ! az account show &> /dev/null; then
        log_error "Not logged in to Azure. Please run 'az login' first."
        exit 1
    fi
    
    # Check if required extensions are available
    az extension add --name azure-iot --upgrade -y 2>/dev/null || true
    az extension add --name dt --upgrade -y 2>/dev/null || true
    
    log_success "Prerequisites check completed"
}

# Function to discover existing resources
discover_resources() {
    log_info "Discovering existing manufacturing digital twins resources..."
    
    # Find resource groups that match our pattern
    RESOURCE_GROUPS=$(az group list --query "[?starts_with(name, 'rg-manufacturing-twins')].name" --output tsv)
    
    if [ -z "$RESOURCE_GROUPS" ]; then
        log_warning "No manufacturing digital twins resource groups found."
        echo "Looking for individual resources..."
        
        # Try to find individual resources
        IOT_HUBS=$(az iot hub list --query "[?starts_with(name, 'iothub-manufacturing')].name" --output tsv)
        DIGITAL_TWINS=$(az dt list --query "[?starts_with(name, 'dt-manufacturing')].name" --output tsv)
        
        if [ -z "$IOT_HUBS" ] && [ -z "$DIGITAL_TWINS" ]; then
            log_info "No manufacturing digital twins resources found to clean up."
            exit 0
        fi
    fi
    
    echo ""
    echo "Found the following resource groups to clean up:"
    for rg in $RESOURCE_GROUPS; do
        echo "  - $rg"
    done
    echo ""
}

# Function to get user confirmation
get_confirmation() {
    if [ "$FORCE_DELETE" = "true" ]; then
        log_warning "Force delete mode enabled. Skipping confirmation."
        return 0
    fi
    
    echo -e "${RED}WARNING:${NC} This will permanently delete all manufacturing digital twins resources!"
    echo "This action cannot be undone."
    echo ""
    read -p "Are you sure you want to continue? (yes/no): " -r REPLY
    echo ""
    
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        log_info "Cleanup cancelled by user."
        exit 0
    fi
    
    log_info "User confirmed deletion. Proceeding with cleanup..."
}

# Function to stop running simulations
stop_simulations() {
    log_info "Stopping any running device simulations..."
    
    # Kill any running Python simulation processes
    pkill -f "simulate_devices.py" 2>/dev/null || true
    pkill -f "python.*simulate" 2>/dev/null || true
    
    # Clean up simulation files
    rm -f simulate_devices.py 2>/dev/null || true
    
    log_success "Simulations stopped and files cleaned up"
}

# Function to clean up digital twins resources
cleanup_digital_twins() {
    log_info "Cleaning up Digital Twins resources..."
    
    for rg in $RESOURCE_GROUPS; do
        # Find Digital Twins instances in this resource group
        DT_INSTANCES=$(az dt list --resource-group "$rg" --query "[].name" --output tsv 2>/dev/null || true)
        
        for dt_name in $DT_INSTANCES; do
            log_info "Cleaning up Digital Twins instance: $dt_name"
            
            # Delete twin relationships first
            log_info "Deleting twin relationships in $dt_name..."
            TWINS=$(az dt twin query --dt-name "$dt_name" --query-command "SELECT * FROM DIGITALTWINS" --output tsv 2>/dev/null | cut -f1 || true)
            
            for twin_id in $TWINS; do
                # Get and delete relationships for this twin
                RELATIONSHIPS=$(az dt twin relationship list --dt-name "$dt_name" --twin-id "$twin_id" --query "[].relationshipId" --output tsv 2>/dev/null || true)
                for rel_id in $RELATIONSHIPS; do
                    az dt twin relationship delete --dt-name "$dt_name" --twin-id "$twin_id" --relationship-id "$rel_id" --yes 2>/dev/null || true
                done
            done
            
            # Delete twin instances
            log_info "Deleting twin instances in $dt_name..."
            for twin_id in $TWINS; do
                az dt twin delete --dt-name "$dt_name" --twin-id "$twin_id" --yes 2>/dev/null || true
            done
            
            # Delete models
            log_info "Deleting models in $dt_name..."
            MODELS=$(az dt model list --dt-name "$dt_name" --query "[].id" --output tsv 2>/dev/null || true)
            for model_id in $MODELS; do
                az dt model delete --dt-name "$dt_name" --dtmi-id "$model_id" --yes 2>/dev/null || true
            done
            
            log_success "Digital Twins instance $dt_name cleaned up"
        done
    done
}

# Function to clean up IoT Hub devices
cleanup_iot_devices() {
    log_info "Cleaning up IoT Hub devices..."
    
    for rg in $RESOURCE_GROUPS; do
        # Find IoT Hubs in this resource group
        IOT_HUBS=$(az iot hub list --resource-group "$rg" --query "[].name" --output tsv 2>/dev/null || true)
        
        for hub_name in $IOT_HUBS; do
            log_info "Cleaning up IoT Hub devices in: $hub_name"
            
            # Delete registered devices
            DEVICES=$(az iot hub device-identity list --hub-name "$hub_name" --query "[].deviceId" --output tsv 2>/dev/null || true)
            for device_id in $DEVICES; do
                az iot hub device-identity delete --hub-name "$hub_name" --device-id "$device_id" 2>/dev/null || true
                log_info "Deleted device: $device_id"
            done
            
            log_success "IoT Hub $hub_name devices cleaned up"
        done
    done
}

# Function to clean up TSI environments
cleanup_tsi_environments() {
    log_info "Cleaning up Time Series Insights environments..."
    
    for rg in $RESOURCE_GROUPS; do
        # Find TSI environments in this resource group
        TSI_ENVS=$(az tsi environment list --resource-group "$rg" --query "[].name" --output tsv 2>/dev/null || true)
        
        for tsi_name in $TSI_ENVS; do
            log_info "Deleting TSI environment: $tsi_name"
            az tsi environment delete --environment-name "$tsi_name" --resource-group "$rg" --yes 2>/dev/null || true
            log_success "TSI environment $tsi_name deleted"
        done
    done
}

# Function to clean up ML workspaces
cleanup_ml_workspaces() {
    log_info "Cleaning up Machine Learning workspaces..."
    
    for rg in $RESOURCE_GROUPS; do
        # Find ML workspaces in this resource group
        ML_WORKSPACES=$(az ml workspace list --resource-group "$rg" --query "[].name" --output tsv 2>/dev/null || true)
        
        for ml_name in $ML_WORKSPACES; do
            log_info "Deleting ML workspace: $ml_name"
            az ml workspace delete --workspace-name "$ml_name" --resource-group "$rg" --yes --all-resources 2>/dev/null || true
            log_success "ML workspace $ml_name deleted"
        done
    done
}

# Function to delete resource groups
delete_resource_groups() {
    log_info "Deleting resource groups..."
    
    for rg in $RESOURCE_GROUPS; do
        log_info "Deleting resource group: $rg"
        az group delete --name "$rg" --yes --no-wait 2>/dev/null || log_warning "Failed to delete resource group $rg"
    done
    
    log_success "Resource group deletion initiated"
    log_info "Note: Resource group deletion may take 10-15 minutes to complete"
}

# Function to clean up local files
cleanup_local_files() {
    log_info "Cleaning up local files..."
    
    # Remove temporary files that might have been created
    rm -f production-line-model.json 2>/dev/null || true
    rm -f equipment-model.json 2>/dev/null || true
    rm -f simulate_devices.py 2>/dev/null || true
    rm -rf temp_models 2>/dev/null || true
    
    log_success "Local files cleaned up"
}

# Function to verify cleanup
verify_cleanup() {
    log_info "Verifying cleanup completion..."
    
    # Check for remaining resource groups
    REMAINING_RGS=$(az group list --query "[?starts_with(name, 'rg-manufacturing-twins')].name" --output tsv)
    
    if [ -n "$REMAINING_RGS" ]; then
        log_warning "Some resource groups are still being deleted:"
        for rg in $REMAINING_RGS; do
            STATUS=$(az group show --name "$rg" --query "properties.provisioningState" --output tsv 2>/dev/null || echo "Deleting")
            echo "  - $rg: $STATUS"
        done
        echo ""
        log_info "Deletion is in progress. Check Azure Portal for completion status."
    else
        log_success "All resource groups have been removed"
    fi
    
    # Check for remaining individual resources
    REMAINING_IOT=$(az iot hub list --query "[?starts_with(name, 'iothub-manufacturing')]" --output tsv)
    REMAINING_DT=$(az dt list --query "[?starts_with(name, 'dt-manufacturing')]" --output tsv)
    
    if [ -n "$REMAINING_IOT" ] || [ -n "$REMAINING_DT" ]; then
        log_warning "Some individual resources may still exist. Check Azure Portal."
    fi
}

# Function to display cleanup summary
display_summary() {
    echo ""
    echo "========================================================================"
    echo "CLEANUP SUMMARY"
    echo "========================================================================"
    echo "The following actions were performed:"
    echo "✓ Stopped device simulations"
    echo "✓ Cleaned up Digital Twins instances, relationships, and models"
    echo "✓ Removed IoT Hub devices"
    echo "✓ Deleted Time Series Insights environments"
    echo "✓ Removed Machine Learning workspaces"
    echo "✓ Initiated resource group deletion"
    echo "✓ Cleaned up local files"
    echo ""
    echo "Note: Resource deletion may take several minutes to complete."
    echo "Check the Azure Portal to monitor deletion progress."
    echo "========================================================================"
}

# Main cleanup function
main() {
    log_info "Starting Azure Smart Manufacturing Digital Twins cleanup..."
    
    check_prerequisites
    discover_resources
    get_confirmation
    stop_simulations
    cleanup_digital_twins
    cleanup_iot_devices
    cleanup_tsi_environments
    cleanup_ml_workspaces
    delete_resource_groups
    cleanup_local_files
    verify_cleanup
    display_summary
    
    log_success "Cleanup process completed!"
}

# Parse command line arguments
FORCE_DELETE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --force)
            FORCE_DELETE=true
            shift
            ;;
        --help)
            echo "Usage: $0 [options]"
            echo "Options:"
            echo "  --force    Skip confirmation prompts (use with caution)"
            echo "  --help     Show this help message"
            echo ""
            echo "This script will:"
            echo "1. Stop any running device simulations"
            echo "2. Clean up Digital Twins instances, relationships, and models"
            echo "3. Remove IoT Hub devices"
            echo "4. Delete Time Series Insights environments"
            echo "5. Remove Machine Learning workspaces"
            echo "6. Delete resource groups and all contained resources"
            echo "7. Clean up local simulation files"
            echo ""
            echo "WARNING: This action is irreversible!"
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Run main cleanup
main