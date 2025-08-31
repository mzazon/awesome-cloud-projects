#!/bin/bash

# ===========================================
# Azure Image Resizing Solution Cleanup Script
# ===========================================
# This script safely removes all resources created by the image resizing solution

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
RESOURCE_GROUP=""
CONFIRM_DELETE="false"
BACKUP_IMAGES="false"
FORCE_DELETE="false"

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to show usage
show_usage() {
    cat << EOF
Azure Image Resizing Solution Cleanup Script

USAGE:
    $0 [OPTIONS]

OPTIONS:
    -g, --resource-group     Resource group name (required)
    -c, --confirm           Confirm deletion without interactive prompt
    -b, --backup            Backup images before deletion
    -f, --force             Force deletion without safety checks
    -h, --help              Show this help message

EXAMPLES:
    # Interactive cleanup with confirmation
    $0 -g rg-image-resize-demo

    # Automatic cleanup with backup
    $0 -g rg-image-resize-demo -c -b

    # Force cleanup without prompts (dangerous)
    $0 -g rg-image-resize-demo -f

SAFETY FEATURES:
    - Interactive confirmation by default
    - Option to backup images before deletion
    - Lists resources before deletion
    - Validates resource group exists

EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -g|--resource-group)
            RESOURCE_GROUP="$2"
            shift 2
            ;;
        -c|--confirm)
            CONFIRM_DELETE="true"
            shift
            ;;
        -b|--backup)
            BACKUP_IMAGES="true"
            shift
            ;;
        -f|--force)
            FORCE_DELETE="true"
            CONFIRM_DELETE="true"
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

# Validate Azure CLI is installed and logged in
if ! command -v az &> /dev/null; then
    print_error "Azure CLI is not installed. Please install it first."
    exit 1
fi

# Check if logged in
if ! az account show &> /dev/null; then
    print_error "Not logged in to Azure. Please run 'az login' first."
    exit 1
fi

print_status "=== Azure Image Resizing Solution Cleanup ==="
print_status "Resource Group: $RESOURCE_GROUP"
print_status "Backup Images: $BACKUP_IMAGES"
print_status "Force Delete: $FORCE_DELETE"

# Check if resource group exists
if ! az group show --name "$RESOURCE_GROUP" &> /dev/null; then
    print_error "Resource group '$RESOURCE_GROUP' does not exist"
    exit 1
fi

# List resources in the group
print_status "Resources in resource group '$RESOURCE_GROUP':"
RESOURCES=$(az resource list --resource-group "$RESOURCE_GROUP" --output table)
echo "$RESOURCES"

if [[ -z "$RESOURCES" || "$RESOURCES" == "[]" ]]; then
    print_warning "No resources found in resource group '$RESOURCE_GROUP'"
    exit 0
fi

# Backup images if requested
if [[ "$BACKUP_IMAGES" == "true" ]]; then
    print_status "Backing up images..."
    
    # Find storage accounts in the resource group
    STORAGE_ACCOUNTS=$(az storage account list --resource-group "$RESOURCE_GROUP" --query "[].name" -o tsv)
    
    if [[ -n "$STORAGE_ACCOUNTS" ]]; then
        BACKUP_DIR="image-backup-$(date +%Y%m%d-%H%M%S)"
        mkdir -p "$BACKUP_DIR"
        
        for STORAGE_ACCOUNT in $STORAGE_ACCOUNTS; do
            print_status "Backing up from storage account: $STORAGE_ACCOUNT"
            
            # Get storage account key
            STORAGE_KEY=$(az storage account keys list \
                --resource-group "$RESOURCE_GROUP" \
                --account-name "$STORAGE_ACCOUNT" \
                --query "[0].value" -o tsv)
            
            # Backup each container
            for CONTAINER in "original-images" "thumbnails" "medium-images"; do
                if az storage container exists \
                    --name "$CONTAINER" \
                    --account-name "$STORAGE_ACCOUNT" \
                    --account-key "$STORAGE_KEY" \
                    --query "exists" -o tsv | grep -q "true"; then
                    
                    print_status "Backing up container: $CONTAINER"
                    CONTAINER_DIR="$BACKUP_DIR/$STORAGE_ACCOUNT/$CONTAINER"
                    mkdir -p "$CONTAINER_DIR"
                    
                    # Download all blobs
                    az storage blob download-batch \
                        --destination "$CONTAINER_DIR" \
                        --source "$CONTAINER" \
                        --account-name "$STORAGE_ACCOUNT" \
                        --account-key "$STORAGE_KEY" \
                        --max-connections 10 || true
                fi
            done
        done
        
        if [[ -d "$BACKUP_DIR" ]]; then
            print_success "Images backed up to: $BACKUP_DIR"
        fi
    else
        print_warning "No storage accounts found for backup"
    fi
fi

# Confirmation unless force delete or already confirmed
if [[ "$FORCE_DELETE" != "true" && "$CONFIRM_DELETE" != "true" ]]; then
    echo
    print_warning "This will DELETE ALL resources in the resource group '$RESOURCE_GROUP'"
    print_warning "This action cannot be undone!"
    echo
    read -p "Are you sure you want to continue? Type 'DELETE' to confirm: " -r
    echo
    if [[ "$REPLY" != "DELETE" ]]; then
        print_warning "Cleanup cancelled by user"
        exit 0
    fi
fi

# Perform deletion
print_status "Starting resource group deletion..."
print_warning "This may take several minutes to complete..."

if az group delete \
    --name "$RESOURCE_GROUP" \
    --yes \
    --no-wait; then
    
    print_success "Resource group deletion initiated successfully"
    print_status "Deletion is running in the background"
    
    if [[ "$FORCE_DELETE" != "true" ]]; then
        echo
        read -p "Do you want to wait for deletion to complete? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            print_status "Waiting for deletion to complete..."
            
            # Wait for resource group to be deleted
            while az group show --name "$RESOURCE_GROUP" &> /dev/null; do
                print_status "Deletion in progress..."
                sleep 30
            done
            
            print_success "Resource group '$RESOURCE_GROUP' has been completely deleted"
        else
            print_status "You can check deletion status with:"
            print_status "az group show --name '$RESOURCE_GROUP'"
        fi
    fi
    
else
    print_error "Failed to initiate resource group deletion"
    exit 1
fi

# Final status
echo
print_success "=== Cleanup Complete ==="
cat << EOF

Summary:
- Resource group '$RESOURCE_GROUP' deletion initiated
- All infrastructure resources will be removed
EOF

if [[ "$BACKUP_IMAGES" == "true" && -d "$BACKUP_DIR" ]]; then
    echo "- Images backed up to: $BACKUP_DIR"
fi

cat << EOF

The following resources were scheduled for deletion:
- Storage accounts and blob containers
- Function Apps and service plans
- Event Grid system topics and subscriptions
- Application Insights and Log Analytics workspaces
- Role assignments and managed identities

Note: Billing will stop once resources are fully deleted.
You can verify completion by checking the Azure portal or running:
az group show --name '$RESOURCE_GROUP'

EOF

print_success "Cleanup script completed successfully!"