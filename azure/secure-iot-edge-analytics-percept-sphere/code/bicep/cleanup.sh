#!/bin/bash

# ==============================================================================
# Azure IoT Edge Analytics Cleanup Script
# ==============================================================================
# This script removes the Secure IoT Edge Analytics solution and all resources
# ==============================================================================

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
RESOURCE_GROUP=""
FORCE_DELETE=false
VERBOSE=false

# Function to print colored output
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_header() {
    echo -e "${BLUE}[HEADER]${NC} $1"
}

# Function to show usage
show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Remove Azure IoT Edge Analytics solution and all resources.

OPTIONS:
    -g, --resource-group RG    Resource group name [required]
    -f, --force                Force deletion without confirmation
    -v, --verbose              Enable verbose output
    -h, --help                 Show this help message

EXAMPLES:
    # Remove development environment
    $0 -g rg-iot-analytics-dev

    # Force deletion without confirmation
    $0 -g rg-iot-analytics-prod -f

    # Verbose cleanup
    $0 -g rg-iot-analytics-test -v

EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -g|--resource-group)
            RESOURCE_GROUP="$2"
            shift 2
            ;;
        -f|--force)
            FORCE_DELETE=true
            shift
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        -h|--help)
            show_usage
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
done

# Validate required parameters
if [[ -z "$RESOURCE_GROUP" ]]; then
    print_error "Resource group is required. Use -g or --resource-group"
    exit 1
fi

# Check if Azure CLI is installed
if ! command -v az &> /dev/null; then
    print_error "Azure CLI is not installed. Please install it from https://aka.ms/azure-cli"
    exit 1
fi

# Check if logged in to Azure
if ! az account show &> /dev/null; then
    print_error "Not logged in to Azure. Please run 'az login' first"
    exit 1
fi

# Check if resource group exists
if ! az group show --name "$RESOURCE_GROUP" &> /dev/null; then
    print_error "Resource group '$RESOURCE_GROUP' does not exist"
    exit 1
fi

# Get current subscription
SUBSCRIPTION_ID=$(az account show --query id --output tsv)
SUBSCRIPTION_NAME=$(az account show --query name --output tsv)

# Display cleanup information
print_header "Azure IoT Edge Analytics Cleanup"
echo "Resource Group:  $RESOURCE_GROUP"
echo "Subscription:    $SUBSCRIPTION_NAME ($SUBSCRIPTION_ID)"
echo

# Show resources to be deleted
print_status "Resources to be deleted:"
az resource list --resource-group "$RESOURCE_GROUP" --query "[].{Name:name, Type:type, Location:location}" --output table

# Warning message
print_warning "This operation will permanently delete all resources in the resource group."
print_warning "This action cannot be undone."
echo

# Confirm deletion
if [[ "$FORCE_DELETE" == false ]]; then
    read -p "Are you sure you want to delete ALL resources in '$RESOURCE_GROUP'? (type 'yes' to confirm): " -r
    echo
    if [[ "$REPLY" != "yes" ]]; then
        print_status "Cleanup cancelled"
        exit 0
    fi
fi

# Stop Stream Analytics jobs first to avoid running costs
print_status "Stopping Stream Analytics jobs..."
STREAM_JOBS=$(az stream-analytics job list --resource-group "$RESOURCE_GROUP" --query "[].name" --output tsv)
if [[ -n "$STREAM_JOBS" ]]; then
    while IFS= read -r job; do
        if [[ -n "$job" ]]; then
            print_status "Stopping Stream Analytics job: $job"
            az stream-analytics job stop --name "$job" --resource-group "$RESOURCE_GROUP" --no-wait
        fi
    done <<< "$STREAM_JOBS"
    
    print_status "Waiting for Stream Analytics jobs to stop..."
    sleep 30
else
    print_status "No Stream Analytics jobs found"
fi

# Delete individual resources first (for better error handling)
print_status "Deleting individual resources..."

# Delete IoT Hub devices first
print_status "Cleaning up IoT Hub devices..."
IOT_HUBS=$(az iot hub list --resource-group "$RESOURCE_GROUP" --query "[].name" --output tsv)
if [[ -n "$IOT_HUBS" ]]; then
    while IFS= read -r hub; do
        if [[ -n "$hub" ]]; then
            print_status "Cleaning up devices in IoT Hub: $hub"
            # Delete all devices in the hub
            DEVICES=$(az iot hub device-identity list --hub-name "$hub" --query "[].deviceId" --output tsv 2>/dev/null || echo "")
            if [[ -n "$DEVICES" ]]; then
                while IFS= read -r device; do
                    if [[ -n "$device" ]]; then
                        print_status "Deleting device: $device"
                        az iot hub device-identity delete --hub-name "$hub" --device-id "$device" --no-wait
                    fi
                done <<< "$DEVICES"
            fi
        fi
    done <<< "$IOT_HUBS"
fi

# Delete Key Vault with purge protection
print_status "Deleting Key Vaults..."
KEY_VAULTS=$(az keyvault list --resource-group "$RESOURCE_GROUP" --query "[].name" --output tsv)
if [[ -n "$KEY_VAULTS" ]]; then
    while IFS= read -r vault; do
        if [[ -n "$vault" ]]; then
            print_status "Deleting Key Vault: $vault"
            az keyvault delete --name "$vault" --no-wait
            # Purge the vault to fully remove it
            print_status "Purging Key Vault: $vault"
            az keyvault purge --name "$vault" --no-wait
        fi
    done <<< "$KEY_VAULTS"
fi

# Delete the entire resource group
print_status "Deleting resource group: $RESOURCE_GROUP"
START_TIME=$(date +%s)

DELETE_CMD="az group delete --name \"$RESOURCE_GROUP\" --yes --no-wait"

if [[ "$VERBOSE" == true ]]; then
    DELETE_CMD="$DELETE_CMD --verbose"
fi

eval $DELETE_CMD

# Monitor deletion progress
print_status "Resource group deletion initiated..."
print_status "Monitoring deletion progress (this may take several minutes)..."

# Wait for resource group to be deleted
while az group show --name "$RESOURCE_GROUP" &> /dev/null; do
    print_status "Deletion in progress..."
    sleep 30
done

END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

print_status "Resource group '$RESOURCE_GROUP' deleted successfully in ${DURATION}s"

# Clean up any remaining Azure resources that might not be in the resource group
print_status "Checking for orphaned resources..."

# Check for any remaining Key Vault soft-deleted items
DELETED_VAULTS=$(az keyvault list-deleted --query "[?properties.scheduledPurgeDate].name" --output tsv 2>/dev/null || echo "")
if [[ -n "$DELETED_VAULTS" ]]; then
    print_warning "Found soft-deleted Key Vaults that will be purged automatically:"
    while IFS= read -r vault; do
        if [[ -n "$vault" ]]; then
            echo "  - $vault"
        fi
    done <<< "$DELETED_VAULTS"
fi

print_header "Cleanup Summary"
echo "✅ Resource group '$RESOURCE_GROUP' has been completely deleted"
echo "✅ All IoT devices have been removed"
echo "✅ Stream Analytics jobs have been stopped and deleted"
echo "✅ Key Vaults have been deleted and purged"
echo "✅ Storage accounts and all data have been removed"
echo

print_warning "Important Notes:"
echo "• Billing will stop for all deleted resources"
echo "• Any data in storage accounts has been permanently deleted"
echo "• IoT device certificates are no longer valid"
echo "• Stream Analytics job history has been removed"
echo

print_status "Cleanup completed successfully!"