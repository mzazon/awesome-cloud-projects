#!/bin/bash

# Destroy script for Azure Service Health Monitoring with Azure Service Health and Monitor
# This script safely removes all service health monitoring resources

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/destroy.log"
DEPLOYMENT_INFO_FILE="${SCRIPT_DIR}/deployment-info.txt"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${timestamp} [${level}] ${message}" | tee -a "${LOG_FILE}"
}

info() { log "INFO" "${BLUE}$*${NC}"; }
success() { log "SUCCESS" "${GREEN}$*${NC}"; }
warning() { log "WARNING" "${YELLOW}$*${NC}"; }
error() { log "ERROR" "${RED}$*${NC}"; }

# Banner
echo -e "${RED}"
cat << 'EOF'
╔═══════════════════════════════════════════════════════════════╗
║                Azure Service Health Monitoring                ║
║                    Destruction Script                         ║
╚═══════════════════════════════════════════════════════════════╝
EOF
echo -e "${NC}"

info "Starting resource cleanup"
info "Log file: ${LOG_FILE}"

# Prerequisites check
info "Checking prerequisites..."

# Check if Azure CLI is installed
if ! command -v az &> /dev/null; then
    error "Azure CLI is not installed. Please install it from https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
    exit 1
fi

# Check if user is logged in
if ! az account show &> /dev/null; then
    error "Not logged in to Azure. Please run 'az login' first."
    exit 1
fi

# Load deployment info if available
RESOURCE_GROUP=""
SUBSCRIPTION_ID=""
DEPLOYMENT_NAME=""

if [[ -f "${DEPLOYMENT_INFO_FILE}" ]]; then
    info "Loading deployment information from: ${DEPLOYMENT_INFO_FILE}"
    # Source the deployment info file safely
    while IFS='=' read -r key value; do
        # Skip comments and empty lines
        [[ $key =~ ^#.*$ ]] && continue
        [[ -z $key ]] && continue
        
        # Remove leading/trailing whitespace
        key=$(echo "$key" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        value=$(echo "$value" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        
        case $key in
            RESOURCE_GROUP) RESOURCE_GROUP="$value" ;;
            SUBSCRIPTION_ID) SUBSCRIPTION_ID="$value" ;;
            DEPLOYMENT_NAME) DEPLOYMENT_NAME="$value" ;;
        esac
    done < "${DEPLOYMENT_INFO_FILE}"
    
    success "Loaded deployment information"
    info "  Deployment: ${DEPLOYMENT_NAME}"
    info "  Resource Group: ${RESOURCE_GROUP}"
    info "  Subscription: ${SUBSCRIPTION_ID}"
else
    warning "Deployment info file not found: ${DEPLOYMENT_INFO_FILE}"
    info "You will need to specify the resource group manually"
fi

# Get resource group from user if not loaded
if [[ -z "${RESOURCE_GROUP}" ]]; then
    read -p "Enter the resource group name to delete: " RESOURCE_GROUP
    if [[ -z "${RESOURCE_GROUP}" ]]; then
        error "Resource group name is required"
        exit 1
    fi
fi

# Get current subscription if not loaded
if [[ -z "${SUBSCRIPTION_ID}" ]]; then
    SUBSCRIPTION_ID=$(az account show --query id --output tsv)
fi

# Verify resource group exists
if ! az group show --name "${RESOURCE_GROUP}" &> /dev/null; then
    warning "Resource group '${RESOURCE_GROUP}' does not exist or is not accessible"
    info "Cleanup may have already been completed or the resource group was manually deleted"
    exit 0
fi

# Show what will be deleted
info "Resources to be deleted:"
info "  Resource Group: ${RESOURCE_GROUP}"

# List resources in the group
RESOURCES=$(az resource list --resource-group "${RESOURCE_GROUP}" --query "[].{Name:name, Type:type}" --output table 2>/dev/null || echo "Unable to list resources")
if [[ "${RESOURCES}" != "Unable to list resources" ]] && [[ -n "${RESOURCES}" ]]; then
    echo "${RESOURCES}"
else
    warning "Unable to enumerate resources in the resource group"
fi

# Safety confirmation
echo ""
warning "This action will permanently delete all resources in the resource group!"
warning "This action cannot be undone!"
echo ""

read -p "Are you sure you want to delete resource group '${RESOURCE_GROUP}'? (yes/no): " CONFIRMATION
if [[ "${CONFIRMATION}" != "yes" ]]; then
    info "Destruction cancelled by user"
    exit 0
fi

# Additional confirmation for safety
read -p "Type the resource group name to confirm deletion: ${RESOURCE_GROUP}: " TYPED_NAME
if [[ "${TYPED_NAME}" != "${RESOURCE_GROUP}" ]]; then
    error "Resource group name mismatch. Destruction cancelled for safety."
    exit 1
fi

# Start cleanup process
info "Starting resource cleanup process..."

# Method 1: Delete individual alert rules first (graceful cleanup)
info "Attempting graceful cleanup of alert rules..."

ALERT_RULES=("ServiceIssueAlert" "PlannedMaintenanceAlert" "HealthAdvisoryAlert" "CriticalServicesAlert")
for rule in "${ALERT_RULES[@]}"; do
    if az monitor activity-log alert show --name "${rule}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        info "Deleting alert rule: ${rule}"
        if az monitor activity-log alert delete \
            --name "${rule}" \
            --resource-group "${RESOURCE_GROUP}" \
            --yes \
            --output none 2>/dev/null; then
            success "Alert rule ${rule} deleted successfully"
        else
            warning "Failed to delete alert rule ${rule}, will be cleaned up with resource group"
        fi
    else
        info "Alert rule ${rule} not found or already deleted"
    fi
done

# Delete action group
if az monitor action-group show --name "ServiceHealthAlerts" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
    info "Deleting action group: ServiceHealthAlerts"
    if az monitor action-group delete \
        --name "ServiceHealthAlerts" \
        --resource-group "${RESOURCE_GROUP}" \
        --yes \
        --output none 2>/dev/null; then
        success "Action group deleted successfully"
    else
        warning "Failed to delete action group, will be cleaned up with resource group"
    fi
else
    info "Action group ServiceHealthAlerts not found or already deleted"
fi

# Method 2: Delete entire resource group (ensures complete cleanup)
info "Deleting resource group: ${RESOURCE_GROUP}"
info "This may take several minutes..."

# Use --no-wait for faster script completion, but provide status check
if az group delete \
    --name "${RESOURCE_GROUP}" \
    --yes \
    --no-wait \
    --output none; then
    
    success "Resource group deletion initiated successfully"
    
    # Optional: Wait for completion with progress updates
    read -p "Wait for deletion to complete? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        info "Waiting for resource group deletion to complete..."
        local wait_count=0
        local max_wait=60  # Maximum wait time in minutes
        
        while az group exists --name "${RESOURCE_GROUP}" 2>/dev/null; do
            wait_count=$((wait_count + 1))
            if [[ $wait_count -gt $max_wait ]]; then
                warning "Deletion is taking longer than expected (${max_wait} minutes)"
                info "You can check the status in the Azure portal or continue waiting"
                read -p "Continue waiting? (y/N): " -n 1 -r
                echo
                if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                    break
                fi
                wait_count=0
            fi
            
            info "Deletion in progress... (${wait_count} minutes elapsed)"
            sleep 60
        done
        
        if az group exists --name "${RESOURCE_GROUP}" 2>/dev/null; then
            warning "Resource group still exists. Deletion may still be in progress."
            info "Check the Azure portal for deletion status"
        else
            success "Resource group deleted successfully"
        fi
    else
        info "Resource group deletion is running in the background"
        info "You can check the status with: az group exists --name ${RESOURCE_GROUP}"
    fi
else
    error "Failed to initiate resource group deletion"
    exit 1
fi

# Cleanup local files
info "Cleaning up local deployment files..."

# Remove deployment info file
if [[ -f "${DEPLOYMENT_INFO_FILE}" ]]; then
    rm -f "${DEPLOYMENT_INFO_FILE}"
    success "Deployment info file removed"
fi

# Archive log file with timestamp
if [[ -f "${SCRIPT_DIR}/deploy.log" ]]; then
    TIMESTAMP=$(date +%Y%m%d-%H%M%S)
    mv "${SCRIPT_DIR}/deploy.log" "${SCRIPT_DIR}/deploy-${TIMESTAMP}.log"
    info "Deploy log archived as: deploy-${TIMESTAMP}.log"
fi

# Verification
info "Performing final verification..."

if az group exists --name "${RESOURCE_GROUP}" 2>/dev/null; then
    warning "Resource group still exists - deletion may be in progress"
    info "Run 'az group exists --name ${RESOURCE_GROUP}' to check status"
else
    success "Resource group deletion confirmed"
fi

# Final summary
echo ""
echo -e "${GREEN}"
cat << 'EOF'
╔═══════════════════════════════════════════════════════════════╗
║                    CLEANUP COMPLETED                          ║
╚═══════════════════════════════════════════════════════════════╝
EOF
echo -e "${NC}"

success "Azure Service Health Monitoring cleanup completed!"
info "Resources cleaned up:"
info "  • Alert Rules: ServiceIssueAlert, PlannedMaintenanceAlert, HealthAdvisoryAlert, CriticalServicesAlert"
info "  • Action Group: ServiceHealthAlerts"
info "  • Resource Group: ${RESOURCE_GROUP}"
info ""
info "Local files cleaned up:"
info "  • Deployment information file"
info "  • Deploy log archived"
info ""
info "Cleanup log: ${LOG_FILE}"

# Final resource verification
if az group exists --name "${RESOURCE_GROUP}" 2>/dev/null; then
    echo ""
    warning "Note: Resource group deletion may still be in progress."
    info "To verify complete deletion, run: az group exists --name ${RESOURCE_GROUP}"
    info "Or check the Azure portal for deletion status."
fi

exit 0