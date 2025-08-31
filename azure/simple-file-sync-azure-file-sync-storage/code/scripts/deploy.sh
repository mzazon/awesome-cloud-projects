#!/bin/bash

#################################################################################
# Azure File Sync Deployment Script
# 
# This script deploys Azure File Sync infrastructure including:
# - Storage Account with Azure Files
# - Storage Sync Service
# - Sync Group and Cloud Endpoint
# - Sample files for testing
#
# Usage: ./deploy.sh [--dry-run] [--help]
#################################################################################

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/deploy.log"
DRY_RUN=false

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

#################################################################################
# Logging Functions
#################################################################################

log() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case $level in
        "INFO")
            echo -e "${GREEN}[INFO]${NC} $message"
            ;;
        "WARN")
            echo -e "${YELLOW}[WARN]${NC} $message"
            ;;
        "ERROR")
            echo -e "${RED}[ERROR]${NC} $message"
            ;;
        "DEBUG")
            echo -e "${BLUE}[DEBUG]${NC} $message"
            ;;
    esac
    
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
}

#################################################################################
# Utility Functions
#################################################################################

show_help() {
    echo "Azure File Sync Deployment Script"
    echo ""
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --dry-run    Show what would be deployed without making changes"
    echo "  --help       Show this help message"
    echo ""
    echo "Environment Variables (optional):"
    echo "  AZURE_LOCATION        Azure region (default: eastus)"
    echo "  RESOURCE_GROUP_PREFIX Resource group prefix (default: rg-filesync)"
    echo "  STORAGE_PREFIX        Storage account prefix (default: filesync)"
    echo ""
}

check_prerequisites() {
    log "INFO" "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        log "ERROR" "Azure CLI is not installed. Please install it first."
        log "INFO" "Visit: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
        exit 1
    fi
    
    # Check if logged into Azure
    if ! az account show &> /dev/null; then
        log "ERROR" "Not logged into Azure. Please run 'az login' first."
        exit 1
    fi
    
    # Check if Azure File Sync extension is available
    if ! az extension list | grep -q "storagesync"; then
        log "INFO" "Installing Azure File Sync CLI extension..."
        if [[ "$DRY_RUN" == "false" ]]; then
            az extension add --name storagesync --only-show-errors || {
                log "ERROR" "Failed to install Azure File Sync extension"
                exit 1
            }
        fi
    fi
    
    # Check for required tools
    local tools=("openssl" "date")
    for tool in "${tools[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            log "ERROR" "$tool is required but not installed"
            exit 1
        fi
    done
    
    log "INFO" "Prerequisites check completed successfully"
}

generate_unique_suffix() {
    openssl rand -hex 3 2>/dev/null || echo "$(date +%s | tail -c 6)"
}

wait_for_deployment() {
    local resource_type=$1
    local resource_name=$2
    local max_attempts=30
    local attempt=1
    
    log "INFO" "Waiting for $resource_type '$resource_name' to be ready..."
    
    while [ $attempt -le $max_attempts ]; do
        if [[ "$DRY_RUN" == "true" ]]; then
            log "INFO" "[DRY-RUN] Would wait for $resource_type deployment"
            return 0
        fi
        
        sleep 10
        log "DEBUG" "Checking deployment status (attempt $attempt/$max_attempts)..."
        attempt=$((attempt + 1))
    done
    
    log "INFO" "$resource_type deployment completed"
}

#################################################################################
# Deployment Functions
#################################################################################

set_environment_variables() {
    log "INFO" "Setting up environment variables..."
    
    # Generate unique suffix for resource names
    export RANDOM_SUFFIX=$(generate_unique_suffix)
    
    # Set default values with environment variable overrides
    export LOCATION="${AZURE_LOCATION:-eastus}"
    export RESOURCE_GROUP="${RESOURCE_GROUP_PREFIX:-rg-filesync}-${RANDOM_SUFFIX}"
    export STORAGE_ACCOUNT="${STORAGE_PREFIX:-filesync}${RANDOM_SUFFIX}"
    export STORAGE_SYNC_SERVICE="filesync-service-${RANDOM_SUFFIX}"
    export FILE_SHARE_NAME="companyfiles"
    export SYNC_GROUP_NAME="main-sync-group"
    
    # Get subscription ID
    export SUBSCRIPTION_ID=$(az account show --query id --output tsv 2>/dev/null || echo "subscription-id")
    
    log "INFO" "Environment variables configured:"
    log "INFO" "  Resource Group: $RESOURCE_GROUP"
    log "INFO" "  Location: $LOCATION"
    log "INFO" "  Storage Account: $STORAGE_ACCOUNT"
    log "INFO" "  Storage Sync Service: $STORAGE_SYNC_SERVICE"
    log "INFO" "  File Share: $FILE_SHARE_NAME"
    log "INFO" "  Subscription: $SUBSCRIPTION_ID"
}

create_resource_group() {
    log "INFO" "Creating resource group '$RESOURCE_GROUP'..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "[DRY-RUN] Would create resource group: $RESOURCE_GROUP in $LOCATION"
        return 0
    fi
    
    if az group show --name "$RESOURCE_GROUP" &>/dev/null; then
        log "WARN" "Resource group '$RESOURCE_GROUP' already exists"
        return 0
    fi
    
    az group create \
        --name "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --tags purpose=recipe environment=demo created-by=azure-file-sync-recipe \
        --only-show-errors || {
        log "ERROR" "Failed to create resource group"
        exit 1
    }
    
    log "INFO" "Resource group created successfully"
}

create_storage_account() {
    log "INFO" "Creating storage account '$STORAGE_ACCOUNT'..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "[DRY-RUN] Would create storage account: $STORAGE_ACCOUNT"
        return 0
    fi
    
    # Check if storage account name is available
    local availability
    availability=$(az storage account check-name --name "$STORAGE_ACCOUNT" --query nameAvailable --output tsv 2>/dev/null || echo "false")
    
    if [[ "$availability" != "true" ]]; then
        log "ERROR" "Storage account name '$STORAGE_ACCOUNT' is not available"
        exit 1
    fi
    
    az storage account create \
        --name "$STORAGE_ACCOUNT" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --sku Standard_LRS \
        --kind StorageV2 \
        --enable-large-file-share \
        --allow-shared-key-access true \
        --https-only true \
        --min-tls-version TLS1_2 \
        --bypass AzureServices \
        --default-action Allow \
        --tags purpose=recipe environment=demo \
        --only-show-errors || {
        log "ERROR" "Failed to create storage account"
        exit 1
    }
    
    wait_for_deployment "Storage Account" "$STORAGE_ACCOUNT"
    log "INFO" "Storage account created successfully"
}

create_file_share() {
    log "INFO" "Creating Azure file share '$FILE_SHARE_NAME'..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "[DRY-RUN] Would create file share: $FILE_SHARE_NAME"
        log "INFO" "[DRY-RUN] Would upload sample files"
        return 0
    fi
    
    # Get storage account key
    local storage_key
    storage_key=$(az storage account keys list \
        --account-name "$STORAGE_ACCOUNT" \
        --resource-group "$RESOURCE_GROUP" \
        --query '[0].value' \
        --output tsv 2>/dev/null) || {
        log "ERROR" "Failed to retrieve storage account key"
        exit 1
    }
    
    # Create file share
    az storage share create \
        --account-name "$STORAGE_ACCOUNT" \
        --account-key "$storage_key" \
        --name "$FILE_SHARE_NAME" \
        --quota 1024 \
        --access-tier Hot \
        --only-show-errors || {
        log "ERROR" "Failed to create file share"
        exit 1
    }
    
    # Create sample files for testing
    local temp_dir=$(mktemp -d)
    cat > "$temp_dir/welcome.txt" << EOF
Welcome to Azure File Sync!

This file demonstrates the hybrid file synchronization capabilities of Azure File Sync.
Any changes made to this file will be synchronized across all connected servers.

Deployment completed on: $(date)
Resource Group: $RESOURCE_GROUP
Storage Account: $STORAGE_ACCOUNT
File Share: $FILE_SHARE_NAME
EOF
    
    cat > "$temp_dir/sync-test.txt" << EOF
Azure File Sync Test File

This file was created during the initial deployment to test synchronization functionality.
Created on: $(date)
Server: Cloud (Azure Files)
Status: Ready for synchronization

Test your sync by:
1. Registering a Windows Server with the Storage Sync Service
2. Creating a server endpoint pointing to a local folder
3. Modifying this file from either location
4. Observing the changes sync to the other location
EOF
    
    # Upload sample files
    az storage file upload \
        --account-name "$STORAGE_ACCOUNT" \
        --account-key "$storage_key" \
        --share-name "$FILE_SHARE_NAME" \
        --source "$temp_dir/welcome.txt" \
        --path "welcome.txt" \
        --only-show-errors || {
        log "WARN" "Failed to upload welcome.txt"
    }
    
    az storage file upload \
        --account-name "$STORAGE_ACCOUNT" \
        --account-key "$storage_key" \
        --share-name "$FILE_SHARE_NAME" \
        --source "$temp_dir/sync-test.txt" \
        --path "sync-test.txt" \
        --only-show-errors || {
        log "WARN" "Failed to upload sync-test.txt"
    }
    
    # Cleanup temporary files
    rm -rf "$temp_dir"
    
    log "INFO" "File share and sample files created successfully"
}

create_storage_sync_service() {
    log "INFO" "Creating Storage Sync Service '$STORAGE_SYNC_SERVICE'..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "[DRY-RUN] Would create Storage Sync Service: $STORAGE_SYNC_SERVICE"
        return 0
    fi
    
    az storagesync create \
        --resource-group "$RESOURCE_GROUP" \
        --name "$STORAGE_SYNC_SERVICE" \
        --location "$LOCATION" \
        --tags purpose=recipe environment=demo \
        --only-show-errors || {
        log "ERROR" "Failed to create Storage Sync Service"
        exit 1
    }
    
    wait_for_deployment "Storage Sync Service" "$STORAGE_SYNC_SERVICE"
    log "INFO" "Storage Sync Service created successfully"
}

create_sync_group_and_endpoint() {
    log "INFO" "Creating sync group and cloud endpoint..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "[DRY-RUN] Would create sync group: $SYNC_GROUP_NAME"
        log "INFO" "[DRY-RUN] Would create cloud endpoint"
        return 0
    fi
    
    # Create sync group
    az storagesync sync-group create \
        --resource-group "$RESOURCE_GROUP" \
        --storage-sync-service "$STORAGE_SYNC_SERVICE" \
        --name "$SYNC_GROUP_NAME" \
        --only-show-errors || {
        log "ERROR" "Failed to create sync group"
        exit 1
    }
    
    # Create cloud endpoint
    az storagesync sync-group cloud-endpoint create \
        --resource-group "$RESOURCE_GROUP" \
        --storage-sync-service "$STORAGE_SYNC_SERVICE" \
        --sync-group-name "$SYNC_GROUP_NAME" \
        --name "cloud-endpoint-${RANDOM_SUFFIX}" \
        --storage-account "$STORAGE_ACCOUNT" \
        --azure-file-share-name "$FILE_SHARE_NAME" \
        --only-show-errors || {
        log "ERROR" "Failed to create cloud endpoint"
        exit 1
    }
    
    log "INFO" "Sync group and cloud endpoint created successfully"
}

display_deployment_summary() {
    log "INFO" "Deployment completed successfully!"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "[DRY-RUN] Summary of resources that would be created:"
    else
        log "INFO" "Deployment Summary:"
    fi
    
    echo ""
    echo "============================================="
    echo "         Azure File Sync Deployment"
    echo "============================================="
    echo "Resource Group:        $RESOURCE_GROUP"
    echo "Location:              $LOCATION"
    echo "Storage Account:       $STORAGE_ACCOUNT"
    echo "File Share:            $FILE_SHARE_NAME"
    echo "Storage Sync Service:  $STORAGE_SYNC_SERVICE"
    echo "Sync Group:            $SYNC_GROUP_NAME"
    echo "Subscription ID:       $SUBSCRIPTION_ID"
    echo "============================================="
    echo ""
    
    if [[ "$DRY_RUN" == "false" ]]; then
        echo "Next Steps:"
        echo "1. Install Azure File Sync agent on your Windows Server"
        echo "2. Register the server with Storage Sync Service: $STORAGE_SYNC_SERVICE"
        echo "3. Create a server endpoint in sync group: $SYNC_GROUP_NAME"
        echo "4. Monitor sync health in the Azure portal"
        echo ""
        echo "Server Registration Information:"
        echo "- Storage Sync Service ID: $(az storagesync show --resource-group "$RESOURCE_GROUP" --name "$STORAGE_SYNC_SERVICE" --query id --output tsv 2>/dev/null || echo 'N/A')"
        echo "- Resource Group: $RESOURCE_GROUP"
        echo "- Subscription ID: $SUBSCRIPTION_ID"
        echo ""
        echo "To clean up resources, run: ./destroy.sh"
    fi
}

#################################################################################
# Main Execution
#################################################################################

main() {
    # Initialize log file
    echo "=== Azure File Sync Deployment Started at $(date) ===" > "$LOG_FILE"
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --dry-run)
                DRY_RUN=true
                log "INFO" "Running in dry-run mode - no resources will be created"
                shift
                ;;
            --help)
                show_help
                exit 0
                ;;
            *)
                log "ERROR" "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
    
    log "INFO" "Starting Azure File Sync deployment..."
    
    # Execute deployment steps
    check_prerequisites
    set_environment_variables
    create_resource_group
    create_storage_account
    create_file_share
    create_storage_sync_service
    create_sync_group_and_endpoint
    display_deployment_summary
    
    if [[ "$DRY_RUN" == "false" ]]; then
        log "INFO" "Deployment completed successfully. Check the Azure portal to verify resources."
        log "INFO" "Log file available at: $LOG_FILE"
    else
        log "INFO" "Dry-run completed. Use './deploy.sh' to execute the actual deployment."
    fi
}

# Handle script interruption
trap 'log "ERROR" "Script interrupted. Deployment may be incomplete."; exit 1' INT TERM

# Execute main function
main "$@"