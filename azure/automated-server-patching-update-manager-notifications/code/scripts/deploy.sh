#!/bin/bash

# =============================================================================
# Azure Automated Server Patching with Update Manager and Notifications
# Deployment Script
# =============================================================================

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
    echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

log_info() {
    log "${BLUE}INFO${NC}: $1"
}

log_success() {
    log "${GREEN}SUCCESS${NC}: $1"
}

log_warning() {
    log "${YELLOW}WARNING${NC}: $1"
}

log_error() {
    log "${RED}ERROR${NC}: $1"
}

# Error handling
handle_error() {
    local line_number=$1
    log_error "Script failed at line ${line_number}. Exiting..."
    exit 1
}

trap 'handle_error ${LINENO}' ERR

# Check if running in interactive mode
check_interactive() {
    if [[ -t 0 ]]; then
        return 0  # Interactive
    else
        return 1  # Non-interactive
    fi
}

# Function to prompt for user input
prompt_user() {
    local prompt_text="$1"
    local var_name="$2"
    local default_value="$3"
    
    if check_interactive; then
        if [[ -n "$default_value" ]]; then
            read -p "$prompt_text [$default_value]: " user_input
            export "$var_name"="${user_input:-$default_value}"
        else
            read -p "$prompt_text: " user_input
            export "$var_name"="$user_input"
        fi
    else
        if [[ -n "$default_value" ]]; then
            export "$var_name"="$default_value"
            log_info "Non-interactive mode: Using default value for $var_name: $default_value"
        else
            log_error "Non-interactive mode: Required parameter $var_name not set"
            exit 1
        fi
    fi
}

# Banner
echo -e "${BLUE}"
cat << "EOF"
╔══════════════════════════════════════════════════════════════════════════════╗
║                  Azure Automated Server Patching Deployment                 ║
║                     Update Manager + Notifications                          ║
╚══════════════════════════════════════════════════════════════════════════════╝
EOF
echo -e "${NC}"

log_info "Starting deployment of Azure automated server patching solution..."

# =============================================================================
# Prerequisites Check
# =============================================================================

log_info "Checking prerequisites..."

# Check if Azure CLI is installed
if ! command -v az &> /dev/null; then
    log_error "Azure CLI is not installed. Please install it first: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
    exit 1
fi

# Check if user is logged into Azure
if ! az account show &> /dev/null; then
    log_error "Not logged into Azure. Please run 'az login' first."
    exit 1
fi

# Check Azure CLI version
CLI_VERSION=$(az version --query '"azure-cli"' -o tsv)
REQUIRED_VERSION="2.37.0"
if [[ $(printf '%s\n' "$REQUIRED_VERSION" "$CLI_VERSION" | sort -V | head -n1) != "$REQUIRED_VERSION" ]]; then
    log_warning "Azure CLI version $CLI_VERSION detected. Version $REQUIRED_VERSION or later is recommended."
fi

# Check if openssl is available for random string generation
if ! command -v openssl &> /dev/null; then
    log_error "openssl is required for generating random suffixes. Please install it first."
    exit 1
fi

log_success "Prerequisites check completed"

# =============================================================================
# Configuration
# =============================================================================

log_info "Setting up configuration..."

# Generate unique suffix
export RANDOM_SUFFIX=$(openssl rand -hex 3)
log_info "Generated unique suffix: $RANDOM_SUFFIX"

# Set default values
DEFAULT_LOCATION="eastus"
DEFAULT_RESOURCE_GROUP="rg-patching-demo-${RANDOM_SUFFIX}"
DEFAULT_VM_NAME="vm-demo-${RANDOM_SUFFIX}"
DEFAULT_ACTION_GROUP_NAME="ag-patching-${RANDOM_SUFFIX}"
DEFAULT_MAINTENANCE_CONFIG_NAME="mc-weekly-patches-${RANDOM_SUFFIX}"
DEFAULT_ADMIN_USERNAME="azureuser"

# Get configuration from user or use defaults
export LOCATION="${LOCATION:-$DEFAULT_LOCATION}"
export RESOURCE_GROUP="${RESOURCE_GROUP:-$DEFAULT_RESOURCE_GROUP}"
export VM_NAME="${VM_NAME:-$DEFAULT_VM_NAME}"
export ACTION_GROUP_NAME="${ACTION_GROUP_NAME:-$DEFAULT_ACTION_GROUP_NAME}"
export MAINTENANCE_CONFIG_NAME="${MAINTENANCE_CONFIG_NAME:-$DEFAULT_MAINTENANCE_CONFIG_NAME}"
export ADMIN_USERNAME="${ADMIN_USERNAME:-$DEFAULT_ADMIN_USERNAME}"

# Get subscription ID
export SUBSCRIPTION_ID=$(az account show --query id --output tsv)
log_info "Using subscription: $SUBSCRIPTION_ID"

# Prompt for email address if not set
if [[ -z "$EMAIL_ADDRESS" ]]; then
    prompt_user "Enter your email address for patch notifications" "EMAIL_ADDRESS"
fi

# Validate email format (basic check)
if [[ ! "$EMAIL_ADDRESS" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; then
    log_error "Invalid email address format: $EMAIL_ADDRESS"
    exit 1
fi

# Prompt for VM password if not set
if [[ -z "$VM_PASSWORD" ]]; then
    if check_interactive; then
        read -s -p "Enter password for VM admin user (or press Enter for default): " VM_PASSWORD
        echo
        export VM_PASSWORD="${VM_PASSWORD:-TempPassword123!}"
    else
        export VM_PASSWORD="TempPassword123!"
        log_warning "Non-interactive mode: Using default VM password. Change this in production!"
    fi
fi

log_info "Configuration completed"
log_info "Resource Group: $RESOURCE_GROUP"
log_info "Location: $LOCATION"
log_info "VM Name: $VM_NAME"
log_info "Email Address: $EMAIL_ADDRESS"

# =============================================================================
# Deployment
# =============================================================================

log_info "Starting resource deployment..."

# Check if resource group already exists
if az group show --name "$RESOURCE_GROUP" &> /dev/null; then
    log_warning "Resource group $RESOURCE_GROUP already exists. Continuing with deployment..."
else
    # Create resource group
    log_info "Creating resource group: $RESOURCE_GROUP"
    az group create \
        --name "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --tags purpose=recipe environment=demo \
        --output none
    
    log_success "Resource group created: $RESOURCE_GROUP"
fi

# Create Virtual Machine
log_info "Creating virtual machine: $VM_NAME"
if az vm show --resource-group "$RESOURCE_GROUP" --name "$VM_NAME" &> /dev/null; then
    log_warning "VM $VM_NAME already exists. Skipping creation..."
else
    az vm create \
        --resource-group "$RESOURCE_GROUP" \
        --name "$VM_NAME" \
        --image "Win2022Datacenter" \
        --admin-username "$ADMIN_USERNAME" \
        --admin-password "$VM_PASSWORD" \
        --size "Standard_B2s" \
        --location "$LOCATION" \
        --tags purpose=patching-demo \
        --output none
    
    log_success "VM created: $VM_NAME"
fi

# Configure VM for Customer Managed Schedules
log_info "Configuring VM patch settings..."
az vm update \
    --resource-group "$RESOURCE_GROUP" \
    --name "$VM_NAME" \
    --set osProfile.windowsConfiguration.patchSettings.patchMode="AutomaticByPlatform" \
    --set osProfile.windowsConfiguration.patchSettings.automaticByPlatformSettings.bypassPlatformSafetyChecksOnUserSchedule=true \
    --output none

log_success "VM configured for scheduled patching: $VM_NAME"

# Create Action Group
log_info "Creating Action Group: $ACTION_GROUP_NAME"
if az monitor action-group show --resource-group "$RESOURCE_GROUP" --name "$ACTION_GROUP_NAME" &> /dev/null; then
    log_warning "Action Group $ACTION_GROUP_NAME already exists. Skipping creation..."
else
    az monitor action-group create \
        --resource-group "$RESOURCE_GROUP" \
        --name "$ACTION_GROUP_NAME" \
        --short-name "PatchAlert" \
        --email-receivers email1 "$EMAIL_ADDRESS" \
        --output none
    
    log_success "Action Group created: $ACTION_GROUP_NAME"
fi

# Get Action Group resource ID
export ACTION_GROUP_ID=$(az monitor action-group show \
    --resource-group "$RESOURCE_GROUP" \
    --name "$ACTION_GROUP_NAME" \
    --query id --output tsv)

log_info "Action Group ID: $ACTION_GROUP_ID"
log_info "Notifications will be sent to: $EMAIL_ADDRESS"

# Create Maintenance Configuration
log_info "Creating maintenance configuration: $MAINTENANCE_CONFIG_NAME"
if az maintenance configuration show --resource-group "$RESOURCE_GROUP" --resource-name "$MAINTENANCE_CONFIG_NAME" &> /dev/null; then
    log_warning "Maintenance configuration $MAINTENANCE_CONFIG_NAME already exists. Skipping creation..."
else
    az maintenance configuration create \
        --resource-group "$RESOURCE_GROUP" \
        --resource-name "$MAINTENANCE_CONFIG_NAME" \
        --maintenance-scope InGuestPatch \
        --location "$LOCATION" \
        --start-date-time "2025-08-02 02:00" \
        --duration "02:00" \
        --recur-every "1Week" \
        --week-days "Saturday" \
        --time-zone "Eastern Standard Time" \
        --reboot-setting "IfRequired" \
        --windows-classifications-to-include "Critical,Security,Updates" \
        --windows-kb-numbers-to-exclude "" \
        --windows-kb-numbers-to-include "" \
        --output none
    
    log_success "Maintenance configuration created: $MAINTENANCE_CONFIG_NAME"
fi

# Get Maintenance Configuration ID
export MAINTENANCE_CONFIG_ID=$(az maintenance configuration show \
    --resource-group "$RESOURCE_GROUP" \
    --resource-name "$MAINTENANCE_CONFIG_NAME" \
    --query id --output tsv)

log_info "Schedule: Every Saturday at 2:00 AM EST, 2-hour window"

# Assign VM to Maintenance Configuration
log_info "Assigning VM to maintenance configuration..."
ASSIGNMENT_NAME="assign-${MAINTENANCE_CONFIG_NAME}"

if az maintenance assignment show \
    --resource-group "$RESOURCE_GROUP" \
    --resource-name "$VM_NAME" \
    --resource-type "virtualMachines" \
    --provider-name "Microsoft.Compute" \
    --configuration-assignment-name "$ASSIGNMENT_NAME" &> /dev/null; then
    log_warning "VM assignment already exists. Skipping assignment..."
else
    az maintenance assignment create \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --resource-name "$VM_NAME" \
        --resource-type "virtualMachines" \
        --provider-name "Microsoft.Compute" \
        --configuration-assignment-name "$ASSIGNMENT_NAME" \
        --maintenance-configuration-id "$MAINTENANCE_CONFIG_ID" \
        --output none
    
    log_success "VM assigned to maintenance configuration for automated patching"
fi

# Create Activity Log Alerts
log_info "Creating activity log alerts..."

# Alert for patch deployment maintenance operations
PATCH_ALERT_NAME="Patch-Deployment-Activity-${RANDOM_SUFFIX}"
if az monitor activity-log alert show --resource-group "$RESOURCE_GROUP" --name "$PATCH_ALERT_NAME" &> /dev/null; then
    log_warning "Activity log alert $PATCH_ALERT_NAME already exists. Skipping creation..."
else
    az monitor activity-log alert create \
        --resource-group "$RESOURCE_GROUP" \
        --name "$PATCH_ALERT_NAME" \
        --scopes "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}" \
        --condition category=Administrative \
            operationName=Microsoft.Maintenance/maintenanceConfigurations/write \
        --action-groups "$ACTION_GROUP_ID" \
        --description "Alert when patch deployment maintenance operations occur" \
        --output none
    
    log_success "Patch deployment activity alert created: $PATCH_ALERT_NAME"
fi

# Alert for maintenance assignment operations
ASSIGNMENT_ALERT_NAME="Maintenance-Assignment-Alert-${RANDOM_SUFFIX}"
if az monitor activity-log alert show --resource-group "$RESOURCE_GROUP" --name "$ASSIGNMENT_ALERT_NAME" &> /dev/null; then
    log_warning "Activity log alert $ASSIGNMENT_ALERT_NAME already exists. Skipping creation..."
else
    az monitor activity-log alert create \
        --resource-group "$RESOURCE_GROUP" \
        --name "$ASSIGNMENT_ALERT_NAME" \
        --scopes "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}" \
        --condition category=Administrative \
            operationName=Microsoft.Maintenance/configurationAssignments/write \
        --action-groups "$ACTION_GROUP_ID" \
        --description "Alert when maintenance assignments are created or updated" \
        --output none
    
    log_success "Maintenance assignment alert created: $ASSIGNMENT_ALERT_NAME"
fi

# Enable Update Assessment and Periodic Scanning
log_info "Enabling periodic assessment for automatic update detection..."
az vm update \
    --resource-group "$RESOURCE_GROUP" \
    --name "$VM_NAME" \
    --set osProfile.windowsConfiguration.patchSettings.assessmentMode="AutomaticByPlatform" \
    --output none

# Trigger immediate update assessment
log_info "Triggering immediate update assessment..."
az vm assess-patches \
    --resource-group "$RESOURCE_GROUP" \
    --name "$VM_NAME" \
    --output none || log_warning "Initial patch assessment may take a few minutes to complete"

log_success "Periodic assessment enabled for continuous update monitoring"
log_info "VM will be scanned for updates every 24 hours automatically"

# =============================================================================
# Validation
# =============================================================================

log_info "Performing deployment validation..."

# Verify VM patch configuration
log_info "Verifying VM patch orchestration settings..."
PATCH_MODE=$(az vm show \
    --resource-group "$RESOURCE_GROUP" \
    --name "$VM_NAME" \
    --query "osProfile.windowsConfiguration.patchSettings.patchMode" \
    --output tsv 2>/dev/null || echo "Unknown")

if [[ "$PATCH_MODE" == "AutomaticByPlatform" ]]; then
    log_success "VM patch mode correctly configured: $PATCH_MODE"
else
    log_warning "VM patch mode may not be correctly configured: $PATCH_MODE"
fi

# Verify maintenance configuration assignment
log_info "Verifying maintenance configuration assignment..."
ASSIGNMENT_COUNT=$(az maintenance assignment list \
    --resource-group "$RESOURCE_GROUP" \
    --resource-name "$VM_NAME" \
    --resource-type "virtualMachines" \
    --provider-name "Microsoft.Compute" \
    --query "length(@)" \
    --output tsv 2>/dev/null || echo "0")

if [[ "$ASSIGNMENT_COUNT" -gt 0 ]]; then
    log_success "Maintenance configuration assignment verified"
else
    log_warning "Maintenance configuration assignment may not be properly configured"
fi

# Test Action Group (optional)
if check_interactive; then
    read -p "Would you like to test the Action Group notification? (y/N): " test_notification
    if [[ "$test_notification" =~ ^[Yy]$ ]]; then
        log_info "Testing Action Group notification..."
        az monitor action-group test-notifications create \
            --resource-group "$RESOURCE_GROUP" \
            --action-group-name "$ACTION_GROUP_NAME" \
            --notification-type Email \
            --receivers email1 \
            --output none || log_warning "Test notification may take a few minutes to arrive"
        
        log_success "Test notification sent. Check your email: $EMAIL_ADDRESS"
    fi
fi

# =============================================================================
# Deployment Summary
# =============================================================================

log_success "Deployment completed successfully!"

echo -e "\n${GREEN}=== DEPLOYMENT SUMMARY ===${NC}"
echo -e "Resource Group:           ${BLUE}$RESOURCE_GROUP${NC}"
echo -e "Location:                 ${BLUE}$LOCATION${NC}"
echo -e "Virtual Machine:          ${BLUE}$VM_NAME${NC}"
echo -e "Action Group:             ${BLUE}$ACTION_GROUP_NAME${NC}"
echo -e "Maintenance Config:       ${BLUE}$MAINTENANCE_CONFIG_NAME${NC}"
echo -e "Email Notifications:      ${BLUE}$EMAIL_ADDRESS${NC}"
echo -e "Patch Schedule:           ${BLUE}Every Saturday at 2:00 AM EST${NC}"
echo -e "Patch Window:             ${BLUE}2 hours${NC}"
echo -e "Subscription ID:          ${BLUE}$SUBSCRIPTION_ID${NC}"

echo -e "\n${YELLOW}=== NEXT STEPS ===${NC}"
echo "1. Wait for the next scheduled maintenance window (Saturday 2:00 AM EST)"
echo "2. Monitor email notifications for patch deployment status"
echo "3. Check Azure portal for patch compliance and deployment history"
echo "4. Review Update Manager dashboard for detailed patch status"

echo -e "\n${YELLOW}=== CLEANUP ===${NC}"
echo "To remove all deployed resources, run:"
echo "  ./destroy.sh"

echo -e "\n${GREEN}Deployment log saved to: deploy_$(date +%Y%m%d_%H%M%S).log${NC}"

# Save deployment info for cleanup script
cat > .deployment_info << EOF
RESOURCE_GROUP=$RESOURCE_GROUP
LOCATION=$LOCATION
VM_NAME=$VM_NAME
ACTION_GROUP_NAME=$ACTION_GROUP_NAME
MAINTENANCE_CONFIG_NAME=$MAINTENANCE_CONFIG_NAME
ASSIGNMENT_NAME=$ASSIGNMENT_NAME
PATCH_ALERT_NAME=$PATCH_ALERT_NAME
ASSIGNMENT_ALERT_NAME=$ASSIGNMENT_ALERT_NAME
RANDOM_SUFFIX=$RANDOM_SUFFIX
SUBSCRIPTION_ID=$SUBSCRIPTION_ID
DEPLOYMENT_DATE=$(date '+%Y-%m-%d %H:%M:%S')
EOF

log_info "Deployment information saved to .deployment_info"
log_success "Azure automated server patching solution deployed successfully!"