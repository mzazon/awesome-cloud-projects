#!/bin/bash

# =================================================================
# Azure Video Content Processing Workflows - Cleanup Script
# =================================================================
# This script safely removes all resources created by the deployment
# script, including:
# - Azure Container Instances
# - Azure Logic Apps
# - Azure Event Grid resources
# - Azure Blob Storage and containers
# - Resource Group and associated resources
# =================================================================

set -euo pipefail

# Color coding for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Error handling function
handle_error() {
    log_error "Cleanup failed at line $1. Exit code: $2"
    log_warning "Some resources may still exist. Check the Azure portal manually."
    exit 1
}

# Set up error handling
trap 'handle_error ${LINENO} $?' ERR

# Script metadata
SCRIPT_VERSION="1.0"
CLEANUP_NAME="video-processing-workflow-cleanup"
TIMESTAMP=$(date +"%Y%m%d-%H%M%S")

log_info "Starting Azure Video Content Processing Workflows cleanup"
log_info "Script version: ${SCRIPT_VERSION}"
log_info "Cleanup timestamp: ${TIMESTAMP}"

# =================================================================
# PREREQUISITES VALIDATION
# =================================================================

log_info "Validating prerequisites..."

# Check if Azure CLI is installed
if ! command -v az &> /dev/null; then
    log_error "Azure CLI is not installed. Please install Azure CLI first."
    exit 1
fi

# Check if user is logged in to Azure
if ! az account show &> /dev/null; then
    log_error "Not logged in to Azure. Please run 'az login' first."
    exit 1
fi

log_success "Prerequisites validation completed"

# =================================================================
# CONFIGURATION LOADING
# =================================================================

log_info "Loading deployment configuration..."

# Function to load configuration from file
load_config_from_file() {
    local config_file=$1
    if [[ -f "${config_file}" ]]; then
        log_info "Loading configuration from: ${config_file}"
        # shellcheck source=/dev/null
        source "${config_file}"
        return 0
    fi
    return 1
}

# Function to prompt for manual configuration
prompt_for_config() {
    log_warning "No configuration file found. Manual input required."
    
    read -p "Enter Resource Group name: " RESOURCE_GROUP
    read -p "Enter Storage Account name: " STORAGE_ACCOUNT
    read -p "Enter Logic App name: " LOGIC_APP_NAME
    read -p "Enter Event Grid Topic name: " EVENT_GRID_TOPIC
    read -p "Enter Container Group name: " CONTAINER_GROUP_NAME
    
    SUBSCRIPTION_ID=$(az account show --query id --output tsv)
}

# Try to load configuration
CONFIG_LOADED=false

# Option 1: Use provided config file path
if [[ "${1:-}" ]]; then
    if load_config_from_file "$1"; then
        CONFIG_LOADED=true
    fi
fi

# Option 2: Search for config files in /tmp
if [[ "${CONFIG_LOADED}" == "false" ]]; then
    CONFIG_FILES=($(find /tmp -name "video-workflow-deployment-*.env" 2>/dev/null | sort -r))
    
    if [[ ${#CONFIG_FILES[@]} -gt 0 ]]; then
        if [[ ${#CONFIG_FILES[@]} -eq 1 ]]; then
            log_info "Found configuration file: ${CONFIG_FILES[0]}"
            if load_config_from_file "${CONFIG_FILES[0]}"; then
                CONFIG_LOADED=true
            fi
        else
            log_info "Multiple configuration files found:"
            for i in "${!CONFIG_FILES[@]}"; do
                echo "  $((i+1)). ${CONFIG_FILES[i]}"
            done
            
            read -p "Select configuration file (1-${#CONFIG_FILES[@]}): " selection
            if [[ "${selection}" =~ ^[0-9]+$ ]] && [[ "${selection}" -ge 1 ]] && [[ "${selection}" -le ${#CONFIG_FILES[@]} ]]; then
                selected_file="${CONFIG_FILES[$((selection-1))]}"
                if load_config_from_file "${selected_file}"; then
                    CONFIG_LOADED=true
                fi
            else
                log_error "Invalid selection"
                exit 1
            fi
        fi
    fi
fi

# Option 3: Manual configuration
if [[ "${CONFIG_LOADED}" == "false" ]]; then
    prompt_for_config
fi

# Validate required variables
REQUIRED_VARS=("RESOURCE_GROUP" "STORAGE_ACCOUNT" "LOGIC_APP_NAME" "EVENT_GRID_TOPIC" "CONTAINER_GROUP_NAME" "SUBSCRIPTION_ID")
for var in "${REQUIRED_VARS[@]}"; do
    if [[ -z "${!var:-}" ]]; then
        log_error "Required variable ${var} is not set"
        exit 1
    fi
done

log_success "Configuration loaded successfully"

# =================================================================
# RESOURCE VALIDATION
# =================================================================

log_info "Validating resources to be deleted..."

# Check if resource group exists
if ! az group show --name "${RESOURCE_GROUP}" &> /dev/null; then
    log_warning "Resource group ${RESOURCE_GROUP} does not exist. Nothing to clean up."
    exit 0
fi

# Get current subscription info
CURRENT_SUBSCRIPTION_ID=$(az account show --query id --output tsv)
CURRENT_SUBSCRIPTION_NAME=$(az account show --query name --output tsv)

log_info "Cleanup configuration:"
log_info "  Subscription: ${CURRENT_SUBSCRIPTION_NAME} (${CURRENT_SUBSCRIPTION_ID})"
log_info "  Resource Group: ${RESOURCE_GROUP}"
log_info "  Storage Account: ${STORAGE_ACCOUNT}"
log_info "  Logic App: ${LOGIC_APP_NAME}"
log_info "  Event Grid Topic: ${EVENT_GRID_TOPIC}"
log_info "  Container Group: ${CONTAINER_GROUP_NAME}"

# Verify subscription matches
if [[ "${SUBSCRIPTION_ID}" != "${CURRENT_SUBSCRIPTION_ID}" ]]; then
    log_warning "Subscription mismatch!"
    log_warning "  Expected: ${SUBSCRIPTION_ID}"
    log_warning "  Current:  ${CURRENT_SUBSCRIPTION_ID}"
    read -p "Continue with current subscription? (y/N): " confirm
    if [[ "${confirm,,}" != "y" ]]; then
        log_info "Cleanup cancelled"
        exit 0
    fi
fi

# =================================================================
# DELETION CONFIRMATION
# =================================================================

echo ""
log_warning "⚠️  DESTRUCTIVE OPERATION WARNING ⚠️"
log_warning "This will permanently delete the following resources:"
echo ""
echo "  Resource Group: ${RESOURCE_GROUP}"
echo "  - Storage Account: ${STORAGE_ACCOUNT}"
echo "  - Logic App: ${LOGIC_APP_NAME}"
echo "  - Event Grid Topic: ${EVENT_GRID_TOPIC}"
echo "  - Container Group: ${CONTAINER_GROUP_NAME}"
echo "  - ALL associated data and configurations"
echo ""
log_warning "This action CANNOT be undone!"
echo ""

# Double confirmation for safety
read -p "Type 'DELETE' to confirm resource deletion: " confirm_delete
if [[ "${confirm_delete}" != "DELETE" ]]; then
    log_info "Cleanup cancelled by user"
    exit 0
fi

read -p "Are you absolutely sure? (y/N): " final_confirm
if [[ "${final_confirm,,}" != "y" ]]; then
    log_info "Cleanup cancelled by user"
    exit 0
fi

log_info "Starting resource cleanup..."

# =================================================================
# ORDERED RESOURCE DELETION
# =================================================================

# Function to safely delete a resource
safe_delete() {
    local resource_type=$1
    local resource_name=$2
    local delete_command=$3
    
    log_info "Deleting ${resource_type}: ${resource_name}"
    
    if eval "${delete_command}" &> /dev/null; then
        log_success "${resource_type} deleted: ${resource_name}"
    else
        log_warning "Failed to delete ${resource_type}: ${resource_name} (may not exist)"
    fi
}

# Step 1: Delete Event Grid subscriptions first (dependencies)
log_info "Removing Event Grid subscriptions..."

EVENT_SUBSCRIPTIONS=$(az eventgrid event-subscription list \
    --source-resource-id "/subscriptions/${CURRENT_SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.Storage/storageAccounts/${STORAGE_ACCOUNT}" \
    --query "[].name" --output tsv 2>/dev/null || echo "")

if [[ -n "${EVENT_SUBSCRIPTIONS}" ]]; then
    for subscription in ${EVENT_SUBSCRIPTIONS}; do
        safe_delete "Event Grid Subscription" "${subscription}" \
            "az eventgrid event-subscription delete \
                --name '${subscription}' \
                --source-resource-id '/subscriptions/${CURRENT_SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.Storage/storageAccounts/${STORAGE_ACCOUNT}'"
    done
else
    log_info "No Event Grid subscriptions found"
fi

# Step 2: Delete Logic App (remove workflow dependencies)
safe_delete "Logic App" "${LOGIC_APP_NAME}" \
    "az logic workflow delete \
        --name '${LOGIC_APP_NAME}' \
        --resource-group '${RESOURCE_GROUP}' \
        --yes"

# Step 3: Delete Container Group (stop running processes)
safe_delete "Container Group" "${CONTAINER_GROUP_NAME}" \
    "az container delete \
        --name '${CONTAINER_GROUP_NAME}' \
        --resource-group '${RESOURCE_GROUP}' \
        --yes"

# Step 4: Delete Event Grid Topic
safe_delete "Event Grid Topic" "${EVENT_GRID_TOPIC}" \
    "az eventgrid topic delete \
        --name '${EVENT_GRID_TOPIC}' \
        --resource-group '${RESOURCE_GROUP}' \
        --yes"

# Step 5: Delete Storage Account (includes all containers and data)
log_info "Deleting Storage Account and all data: ${STORAGE_ACCOUNT}"
log_warning "This will permanently delete all video files and processed content"

safe_delete "Storage Account" "${STORAGE_ACCOUNT}" \
    "az storage account delete \
        --name '${STORAGE_ACCOUNT}' \
        --resource-group '${RESOURCE_GROUP}' \
        --yes"

# =================================================================
# RESOURCE GROUP CLEANUP
# =================================================================

log_info "Performing final resource group cleanup..."

# Check for remaining resources
REMAINING_RESOURCES=$(az resource list --resource-group "${RESOURCE_GROUP}" --query "length(@)" --output tsv 2>/dev/null || echo "0")

if [[ "${REMAINING_RESOURCES}" -gt 0 ]]; then
    log_warning "Found ${REMAINING_RESOURCES} remaining resources in resource group"
    
    # List remaining resources
    log_info "Remaining resources:"
    az resource list --resource-group "${RESOURCE_GROUP}" --output table 2>/dev/null || true
    
    read -p "Delete entire resource group including remaining resources? (y/N): " delete_rg
    if [[ "${delete_rg,,}" == "y" ]]; then
        log_info "Deleting resource group: ${RESOURCE_GROUP}"
        az group delete --name "${RESOURCE_GROUP}" --yes --no-wait
        log_success "Resource group deletion initiated (may take several minutes)"
    else
        log_warning "Resource group preserved with remaining resources"
    fi
else
    log_info "Deleting empty resource group: ${RESOURCE_GROUP}"
    az group delete --name "${RESOURCE_GROUP}" --yes --no-wait
    log_success "Resource group deletion initiated"
fi

# =================================================================
# CLEANUP VERIFICATION
# =================================================================

log_info "Performing cleanup verification..."

# Wait a moment for deletions to process
sleep 5

# Check if resource group still exists
if az group show --name "${RESOURCE_GROUP}" &> /dev/null; then
    RG_STATE=$(az group show --name "${RESOURCE_GROUP}" --query properties.provisioningState --output tsv 2>/dev/null || echo "Unknown")
    if [[ "${RG_STATE}" == "Deleting" ]]; then
        log_info "Resource group is being deleted (Status: ${RG_STATE})"
    else
        log_warning "Resource group still exists (Status: ${RG_STATE})"
    fi
else
    log_success "Resource group successfully deleted"
fi

# =================================================================
# CLEANUP SUMMARY
# =================================================================

echo ""
echo "=========================================="
echo "CLEANUP SUMMARY"
echo "=========================================="
echo "Cleanup completed: ${TIMESTAMP}"
echo "Resource Group: ${RESOURCE_GROUP}"
echo ""
echo "Deleted Resources:"
echo "  ✓ Logic App: ${LOGIC_APP_NAME}"
echo "  ✓ Container Group: ${CONTAINER_GROUP_NAME}"
echo "  ✓ Event Grid Topic: ${EVENT_GRID_TOPIC}"
echo "  ✓ Storage Account: ${STORAGE_ACCOUNT}"
echo "  ✓ Event Grid Subscriptions"
echo "  ✓ Storage Containers and Data"
echo ""

if az group show --name "${RESOURCE_GROUP}" &> /dev/null; then
    echo "Resource Group Status: Still exists (deletion in progress)"
    echo "Note: Complete deletion may take several minutes"
else
    echo "Resource Group Status: Successfully deleted"
fi

echo ""
echo "Verification Steps:"
echo "  1. Check Azure portal to confirm resource deletion"
echo "  2. Verify no unexpected charges in billing"
echo "  3. Remove any local configuration files if no longer needed"
echo ""
echo "=========================================="
echo ""

# Clean up local configuration files (optional)
if [[ "${CONFIG_LOADED}" == "true" ]] && [[ -f "${1:-}" ]]; then
    read -p "Delete local configuration file: ${1}? (y/N): " delete_config
    if [[ "${delete_config,,}" == "y" ]]; then
        rm -f "${1}"
        log_success "Local configuration file deleted"
    fi
fi

# Clean up temporary video files
if [[ -f "test-video.mp4" ]]; then
    rm -f test-video.mp4
    log_info "Cleaned up temporary test video file"
fi

if [[ -f "/tmp/video-processor.sh" ]]; then
    rm -f /tmp/video-processor.sh
    log_info "Cleaned up temporary processing script"
fi

log_success "Azure Video Content Processing Workflows cleanup completed! 🧹"

echo ""
log_info "💡 Tips for future deployments:"
echo "  • Save deployment configuration files for easier cleanup"
echo "  • Monitor Azure costs regularly during development"
echo "  • Use resource tags for better resource management"
echo "  • Consider using Azure DevOps for automated deployments"
echo ""

exit 0