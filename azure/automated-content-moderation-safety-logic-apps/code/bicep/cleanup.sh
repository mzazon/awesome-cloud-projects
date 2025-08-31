#!/bin/bash

# Azure Resource Cleanup Script for Automated Content Moderation
# This script safely removes all resources created by the content moderation solution

set -e  # Exit on error

# Default values
RESOURCE_GROUP=""
SUBSCRIPTION_ID=""
FORCE_DELETE=false
BACKUP_DATA=false
VERBOSE=false

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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
    echo -e "${BLUE}[CLEANUP]${NC} $1"
}

# Function to show usage
show_usage() {
    cat << EOF
Usage: $0 -g <resource-group> [OPTIONS]

This script safely removes all Azure resources created by the content moderation solution.

Required Parameters:
  -g, --resource-group    Name of the Azure resource group to delete

Optional Parameters:
  -s, --subscription      Azure subscription ID (uses default if not specified)
  -f, --force             Skip confirmation prompts (USE WITH CAUTION)
  -b, --backup            Backup storage data before deletion
  --verbose               Enable verbose output
  -h, --help              Show this help message

Safety Features:
  - Lists all resources before deletion
  - Requires explicit confirmation
  - Optionally backs up storage data
  - Validates resource group exists before deletion

Examples:
  # Interactive cleanup with confirmation
  $0 -g rg-content-moderation-demo

  # Backup data before cleanup
  $0 -g rg-content-moderation-demo -b

  # Force cleanup without prompts (DANGEROUS)
  $0 -g rg-content-moderation-demo -f

EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -g|--resource-group)
            RESOURCE_GROUP="$2"
            shift 2
            ;;
        -s|--subscription)
            SUBSCRIPTION_ID="$2"
            shift 2
            ;;
        -f|--force)
            FORCE_DELETE=true
            shift
            ;;
        -b|--backup)
            BACKUP_DATA=true
            shift
            ;;
        --verbose)
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
    print_error "Resource group name is required"
    show_usage
    exit 1
fi

# Print cleanup information
print_header "Azure Content Moderation Solution Cleanup"
echo "======================================================"
print_status "Resource Group: $RESOURCE_GROUP"
if [[ "$FORCE_DELETE" == true ]]; then
    print_warning "Force delete mode enabled - no confirmations will be requested"
fi
if [[ "$BACKUP_DATA" == true ]]; then
    print_status "Data backup enabled - storage content will be downloaded first"
fi
echo "======================================================"

# Check if Azure CLI is installed
if ! command -v az &> /dev/null; then
    print_error "Azure CLI is not installed. Please install it first:"
    print_error "https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
    exit 1
fi

# Check if user is logged in to Azure
print_status "Checking Azure CLI authentication..."
if ! az account show &> /dev/null; then
    print_error "You are not logged in to Azure. Please run 'az login' first."
    exit 1
fi

# Set subscription if provided
if [[ -n "$SUBSCRIPTION_ID" ]]; then
    print_status "Setting subscription to: $SUBSCRIPTION_ID"
    az account set --subscription "$SUBSCRIPTION_ID"
fi

# Display current subscription
CURRENT_SUBSCRIPTION=$(az account show --query name -o tsv)
print_status "Using subscription: $CURRENT_SUBSCRIPTION"

# Check if resource group exists
print_status "Checking if resource group exists..."
if ! az group show --name "$RESOURCE_GROUP" &> /dev/null; then
    print_warning "Resource group '$RESOURCE_GROUP' does not exist"
    print_status "Nothing to clean up. Exiting."
    exit 0
else
    print_status "Resource group '$RESOURCE_GROUP' found"
fi

# List all resources in the resource group
print_status "Listing resources in the resource group..."
RESOURCES=$(az resource list --resource-group "$RESOURCE_GROUP" --query "[].{Name:name, Type:type, Location:location}" -o table)

if [[ -z "$RESOURCES" ]]; then
    print_warning "No resources found in resource group '$RESOURCE_GROUP'"
    print_status "The resource group exists but is empty."
else
    echo
    print_header "Resources to be deleted:"
    echo "$RESOURCES"
fi

# Function to backup storage data
backup_storage_data() {
    print_status "Searching for storage accounts to backup..."
    
    STORAGE_ACCOUNTS=$(az storage account list --resource-group "$RESOURCE_GROUP" --query "[].name" -o tsv)
    
    if [[ -z "$STORAGE_ACCOUNTS" ]]; then
        print_status "No storage accounts found to backup"
        return
    fi
    
    BACKUP_DIR="./backup-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$BACKUP_DIR"
    print_status "Created backup directory: $BACKUP_DIR"
    
    for STORAGE_ACCOUNT in $STORAGE_ACCOUNTS; do
        print_status "Backing up storage account: $STORAGE_ACCOUNT"
        
        # Get storage account key
        STORAGE_KEY=$(az storage account keys list \
            --account-name "$STORAGE_ACCOUNT" \
            --resource-group "$RESOURCE_GROUP" \
            --query "[0].value" -o tsv)
        
        # List and download blobs
        CONTAINERS=$(az storage container list \
            --account-name "$STORAGE_ACCOUNT" \
            --account-key "$STORAGE_KEY" \
            --query "[].name" -o tsv)
        
        for CONTAINER in $CONTAINERS; do
            print_status "Backing up container: $CONTAINER"
            CONTAINER_DIR="$BACKUP_DIR/$STORAGE_ACCOUNT/$CONTAINER"
            mkdir -p "$CONTAINER_DIR"
            
            # List blobs in container
            BLOBS=$(az storage blob list \
                --container-name "$CONTAINER" \
                --account-name "$STORAGE_ACCOUNT" \
                --account-key "$STORAGE_KEY" \
                --query "[].name" -o tsv)
            
            if [[ -n "$BLOBS" ]]; then
                for BLOB in $BLOBS; do
                    print_status "Downloading blob: $BLOB"
                    az storage blob download \
                        --container-name "$CONTAINER" \
                        --name "$BLOB" \
                        --file "$CONTAINER_DIR/$BLOB" \
                        --account-name "$STORAGE_ACCOUNT" \
                        --account-key "$STORAGE_KEY" \
                        --no-progress \
                        || print_warning "Failed to download blob: $BLOB"
                done
            else
                print_status "No blobs found in container: $CONTAINER"
            fi
        done
    done
    
    print_status "Backup completed in directory: $BACKUP_DIR"
}

# Backup data if requested
if [[ "$BACKUP_DATA" == true ]]; then
    echo
    print_header "Backing up storage data..."
    backup_storage_data
fi

# Confirmation prompt unless force delete is enabled
if [[ "$FORCE_DELETE" != true ]]; then
    echo
    print_warning "WARNING: This will permanently delete ALL resources in the resource group!"
    print_warning "This action cannot be undone."
    echo
    read -p "Are you sure you want to delete resource group '$RESOURCE_GROUP' and ALL its resources? (type 'DELETE' to confirm): " -r
    echo
    
    if [[ "$REPLY" != "DELETE" ]]; then
        print_status "Cleanup cancelled by user"
        exit 0
    fi
    
    # Double confirmation for production-like environments
    if [[ "$RESOURCE_GROUP" =~ (prod|production) ]]; then
        print_error "PRODUCTION RESOURCE GROUP DETECTED!"
        print_warning "You are about to delete what appears to be a production resource group."
        read -p "Type 'I UNDERSTAND THE RISKS' to proceed: " -r
        echo
        
        if [[ "$REPLY" != "I UNDERSTAND THE RISKS" ]]; then
            print_status "Cleanup cancelled for safety"
            exit 0
        fi
    fi
fi

# Stop Logic Apps before deletion to prevent running workflows
print_status "Stopping Logic Apps to prevent active workflows..."
LOGIC_APPS=$(az logic workflow list --resource-group "$RESOURCE_GROUP" --query "[].name" -o tsv)

for LOGIC_APP in $LOGIC_APPS; do
    if [[ -n "$LOGIC_APP" ]]; then
        print_status "Stopping Logic App: $LOGIC_APP"
        az logic workflow update \
            --resource-group "$RESOURCE_GROUP" \
            --name "$LOGIC_APP" \
            --state Disabled \
            || print_warning "Failed to stop Logic App: $LOGIC_APP"
    fi
done

# Delete the resource group
print_status "Deleting resource group '$RESOURCE_GROUP'..."
echo "This may take several minutes..."

DELETE_CMD="az group delete --name '$RESOURCE_GROUP' --yes"

if [[ "$VERBOSE" == true ]]; then
    DELETE_CMD="$DELETE_CMD --verbose"
else
    DELETE_CMD="$DELETE_CMD --no-wait"
fi

eval $DELETE_CMD

if [[ $? -eq 0 ]]; then
    if [[ "$VERBOSE" == true ]]; then
        print_status "Resource group deletion completed successfully!"
    else
        print_status "Resource group deletion initiated successfully!"
        print_status "Deletion is running in the background and may take several minutes to complete."
        
        # Provide command to check deletion status
        echo
        print_header "Check deletion status:"
        echo "az group exists --name '$RESOURCE_GROUP'"
        echo "(Returns 'false' when deletion is complete)"
    fi
    
    # Summary
    echo
    print_header "Cleanup Summary:"
    print_status "Resource group '$RESOURCE_GROUP' deletion initiated"
    if [[ "$BACKUP_DATA" == true ]]; then
        print_status "Storage data backed up to: $BACKUP_DIR"
    fi
    print_status "All resources will be permanently removed"
    
else
    print_error "Failed to delete resource group!"
    print_error "Check the Azure portal or run 'az group show --name $RESOURCE_GROUP' for status"
    exit 1
fi

# Verify deletion (only if not using --no-wait)
if [[ "$VERBOSE" == true ]]; then
    print_status "Verifying resource group deletion..."
    sleep 5
    
    if az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        print_warning "Resource group still exists. Deletion may be in progress."
    else
        print_status "Resource group successfully deleted!"
    fi
fi

print_status "Cleanup script completed!"

# Cleanup function
cleanup() {
    if [[ "$BACKUP_DATA" == true && -d "$BACKUP_DIR" ]]; then
        print_status "Backup data preserved in: $BACKUP_DIR"
        print_status "Remember to clean up backup files when no longer needed"
    fi
}

trap cleanup EXIT