#!/bin/bash

# Azure Resource Cleanup Script for QR Code Generator
# This script safely removes all resources created by the QR Code Generator deployment

set -e  # Exit on any error

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

# Default values
RESOURCE_GROUP=""
FORCE_DELETE=false
SKIP_CONFIRMATION=false
DELETE_RESOURCE_GROUP=false
BACKUP_DATA=false

# Function to show usage
show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Clean up Azure QR Code Generator resources

OPTIONS:
    -g, --resource-group        Resource group name (required)
    -f, --force                Force deletion without additional prompts
    -y, --yes                  Skip all confirmation prompts
    -r, --delete-resource-group Delete the entire resource group
    -b, --backup               Backup QR codes before deletion
    -h, --help                 Show this help message

EXAMPLES:
    # Interactive cleanup (recommended)
    $0 -g rg-qr-generator-dev

    # Force cleanup without prompts
    $0 -g rg-qr-generator-dev -f -y

    # Delete entire resource group
    $0 -g rg-qr-generator-dev -r -y

    # Backup data before cleanup
    $0 -g rg-qr-generator-dev -b

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
        -y|--yes)
            SKIP_CONFIRMATION=true
            shift
            ;;
        -r|--delete-resource-group)
            DELETE_RESOURCE_GROUP=true
            shift
            ;;
        -b|--backup)
            BACKUP_DATA=true
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
    print_error "Resource group name is required. Use -g or --resource-group option."
    show_usage
    exit 1
fi

# Check if Azure CLI is installed and logged in
if ! command -v az &> /dev/null; then
    print_error "Azure CLI is not installed. Please install it first."
    exit 1
fi

# Check Azure CLI login status
if ! az account show &> /dev/null; then
    print_error "Not logged in to Azure. Please run 'az login' first."
    exit 1
fi

# Check if resource group exists
if ! az group show --name "$RESOURCE_GROUP" &> /dev/null; then
    print_error "Resource group '$RESOURCE_GROUP' does not exist."
    exit 1
fi

# Display cleanup information
print_header "QR Code Generator Resource Cleanup"
echo "====================================="
echo "Resource Group:        $RESOURCE_GROUP"
echo "Force Delete:          $FORCE_DELETE"
echo "Skip Confirmation:     $SKIP_CONFIRMATION"
echo "Delete Resource Group: $DELETE_RESOURCE_GROUP"
echo "Backup Data:           $BACKUP_DATA"
echo "====================================="

# Get current subscription
SUBSCRIPTION_ID=$(az account show --query id --output tsv)
SUBSCRIPTION_NAME=$(az account show --query name --output tsv)
print_status "Using subscription: $SUBSCRIPTION_NAME ($SUBSCRIPTION_ID)"

# Function to confirm action
confirm_action() {
    local message="$1"
    if [[ "$SKIP_CONFIRMATION" == "true" ]]; then
        return 0
    fi
    
    echo -n "$message (y/N): "
    read -r response
    case "$response" in
        [yY][eE][sS]|[yY])
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# Function to backup QR codes
backup_qr_codes() {
    print_status "Searching for storage accounts in resource group..."
    
    local storage_accounts
    storage_accounts=$(az storage account list \
        --resource-group "$RESOURCE_GROUP" \
        --query "[?contains(name, 'qrgen') || contains(name, 'stqr')].name" \
        --output tsv)
    
    if [[ -z "$storage_accounts" ]]; then
        print_warning "No QR generator storage accounts found."
        return 0
    fi
    
    for storage_account in $storage_accounts; do
        print_status "Backing up QR codes from storage account: $storage_account"
        
        # Create backup directory
        local backup_dir="qr-backup-$(date +%Y%m%d-%H%M%S)"
        mkdir -p "$backup_dir"
        
        # Get storage account key
        local storage_key
        storage_key=$(az storage account keys list \
            --resource-group "$RESOURCE_GROUP" \
            --account-name "$storage_account" \
            --query "[0].value" \
            --output tsv)
        
        # Download all blobs from qr-codes container
        if az storage container exists \
            --name "qr-codes" \
            --account-name "$storage_account" \
            --account-key "$storage_key" \
            --output none; then
            
            print_status "Downloading QR codes to $backup_dir..."
            az storage blob download-batch \
                --destination "$backup_dir" \
                --source "qr-codes" \
                --account-name "$storage_account" \
                --account-key "$storage_key" \
                --output none
            
            local file_count
            file_count=$(find "$backup_dir" -type f | wc -l)
            print_status "Backed up $file_count QR code files to $backup_dir"
        else
            print_warning "No qr-codes container found in storage account $storage_account"
        fi
    done
}

# Function to list resources to be deleted
list_resources() {
    print_status "Resources in resource group '$RESOURCE_GROUP':"
    echo ""
    
    az resource list \
        --resource-group "$RESOURCE_GROUP" \
        --output table \
        --query "[].{Name:name, Type:type, Location:location}"
    
    echo ""
    
    # Get cost information if available
    print_status "Attempting to get cost information..."
    local current_month
    current_month=$(date +%Y-%m-01)
    
    az consumption usage list \
        --scope "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP" \
        --start-date "$current_month" \
        --end-date "$(date +%Y-%m-%d)" \
        --output table \
        --query "[].{Resource:instanceName, Cost:pretaxCost, Currency:currency}" \
        2>/dev/null || print_warning "Cost information not available"
}

# Main cleanup logic
print_status "Analyzing resources in resource group '$RESOURCE_GROUP'..."

# List resources to be deleted
list_resources

# Backup data if requested
if [[ "$BACKUP_DATA" == "true" ]]; then
    if confirm_action "Do you want to backup QR codes before deletion?"; then
        backup_qr_codes
    fi
fi

# Confirm cleanup action
if [[ "$DELETE_RESOURCE_GROUP" == "true" ]]; then
    print_warning "This will DELETE the ENTIRE resource group and ALL resources within it."
    print_warning "This action cannot be undone!"
    
    if ! confirm_action "Are you absolutely sure you want to delete the entire resource group '$RESOURCE_GROUP'?"; then
        print_status "Cleanup cancelled by user."
        exit 0
    fi
    
    print_status "Deleting resource group '$RESOURCE_GROUP'..."
    if [[ "$FORCE_DELETE" == "true" ]]; then
        az group delete \
            --name "$RESOURCE_GROUP" \
            --yes \
            --no-wait
        print_status "Resource group deletion initiated (running in background)."
    else
        az group delete \
            --name "$RESOURCE_GROUP" \
            --yes
        print_status "Resource group deleted successfully."
    fi
else
    # Individual resource cleanup
    print_warning "This will delete QR Code Generator resources in resource group '$RESOURCE_GROUP'."
    
    if ! confirm_action "Do you want to proceed with cleanup?"; then
        print_status "Cleanup cancelled by user."
        exit 0
    fi
    
    # Delete Function Apps
    print_status "Deleting Function Apps..."
    local function_apps
    function_apps=$(az functionapp list \
        --resource-group "$RESOURCE_GROUP" \
        --query "[?contains(name, 'qr-generator') || contains(name, 'func-qr')].name" \
        --output tsv)
    
    for app in $function_apps; do
        print_status "Deleting Function App: $app"
        az functionapp delete \
            --name "$app" \
            --resource-group "$RESOURCE_GROUP" \
            --output none
    done
    
    # Delete App Service Plans
    print_status "Deleting App Service Plans..."
    local service_plans
    service_plans=$(az appservice plan list \
        --resource-group "$RESOURCE_GROUP" \
        --query "[?contains(name, 'qr-generator') || contains(name, 'asp-qr')].name" \
        --output tsv)
    
    for plan in $service_plans; do
        print_status "Deleting App Service Plan: $plan"
        az appservice plan delete \
            --name "$plan" \
            --resource-group "$RESOURCE_GROUP" \
            --yes \
            --output none
    done
    
    # Delete Storage Accounts
    print_status "Deleting Storage Accounts..."
    local storage_accounts
    storage_accounts=$(az storage account list \
        --resource-group "$RESOURCE_GROUP" \
        --query "[?contains(name, 'qrgen') || contains(name, 'stqr')].name" \
        --output tsv)
    
    for account in $storage_accounts; do
        print_status "Deleting Storage Account: $account"
        az storage account delete \
            --name "$account" \
            --resource-group "$RESOURCE_GROUP" \
            --yes \
            --output none
    done
    
    # Delete Application Insights
    print_status "Deleting Application Insights..."
    local app_insights
    app_insights=$(az monitor app-insights component list \
        --resource-group "$RESOURCE_GROUP" \
        --query "[?contains(name, 'qr-generator') || contains(name, 'appi-qr')].name" \
        --output tsv)
    
    for insights in $app_insights; do
        print_status "Deleting Application Insights: $insights"
        az monitor app-insights component delete \
            --app "$insights" \
            --resource-group "$RESOURCE_GROUP" \
            --output none
    done
    
    print_status "Individual resource cleanup completed."
fi

# Verify cleanup
print_status "Verifying cleanup..."
if [[ "$DELETE_RESOURCE_GROUP" == "true" ]]; then
    if az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        print_warning "Resource group still exists (deletion may be in progress)."
        print_status "You can check the deletion status with:"
        echo "  az group show --name $RESOURCE_GROUP"
    else
        print_status "Resource group successfully deleted."
    fi
else
    local remaining_resources
    remaining_resources=$(az resource list \
        --resource-group "$RESOURCE_GROUP" \
        --query "length([])")
    
    if [[ "$remaining_resources" -eq 0 ]]; then
        print_status "All resources have been cleaned up successfully."
        print_status "You may now delete the empty resource group with:"
        echo "  az group delete --name $RESOURCE_GROUP --yes"
    else
        print_status "Cleanup completed. $remaining_resources resources remain in the resource group."
        print_status "Run the following command to see remaining resources:"
        echo "  az resource list --resource-group $RESOURCE_GROUP --output table"
    fi
fi

print_status "Cleanup script completed!"

# Display final summary
echo ""
print_header "Cleanup Summary"
echo "==============="
echo "Resource Group:    $RESOURCE_GROUP"
echo "Cleanup Type:      $(if [[ "$DELETE_RESOURCE_GROUP" == "true" ]]; then echo "Full Resource Group"; else echo "Individual Resources"; fi)"
echo "Backup Created:    $BACKUP_DATA"
echo "Completion Time:   $(date)"
echo ""

if [[ "$BACKUP_DATA" == "true" && -d "qr-backup-"* ]]; then
    echo "Backup files are stored in: $(ls -d qr-backup-* | head -1)"
    echo "Remember to clean up backup files when no longer needed."
fi