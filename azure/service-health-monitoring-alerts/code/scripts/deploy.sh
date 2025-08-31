#!/bin/bash

# Deploy script for Azure Service Health Monitoring with Azure Service Health and Monitor
# This script creates comprehensive service health monitoring with alert rules and action groups

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/deploy.log"
DEPLOYMENT_NAME="service-health-monitoring-$(date +%Y%m%d-%H%M%S)"

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

# Error handling
cleanup_on_error() {
    error "Deployment failed. Check ${LOG_FILE} for details."
    info "You can run the destroy script to clean up any partially created resources."
    exit 1
}

trap cleanup_on_error ERR

# Banner
echo -e "${BLUE}"
cat << 'EOF'
╔═══════════════════════════════════════════════════════════════╗
║                Azure Service Health Monitoring                ║
║                    Deployment Script                          ║
╚═══════════════════════════════════════════════════════════════╝
EOF
echo -e "${NC}"

info "Starting deployment: ${DEPLOYMENT_NAME}"
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

# Check if openssl is available for random string generation
if ! command -v openssl &> /dev/null; then
    warning "openssl not found. Using date-based suffix instead."
    RANDOM_SUFFIX=$(date +%s | tail -c 4)
else
    RANDOM_SUFFIX=$(openssl rand -hex 3)
fi

success "Prerequisites check completed"

# Configuration with user input or defaults
info "Configuring deployment parameters..."

# Get subscription info
SUBSCRIPTION_ID=$(az account show --query id --output tsv)
SUBSCRIPTION_NAME=$(az account show --query name --output tsv)

info "Using subscription: ${SUBSCRIPTION_NAME} (${SUBSCRIPTION_ID})"

# Resource configuration
RESOURCE_GROUP="${RESOURCE_GROUP:-rg-service-health-${RANDOM_SUFFIX}}"
LOCATION="${LOCATION:-eastus}"

# Get notification details with defaults
if [[ -z "${NOTIFICATION_EMAIL:-}" ]]; then
    read -p "Enter notification email address: " NOTIFICATION_EMAIL
    if [[ -z "${NOTIFICATION_EMAIL}" ]]; then
        error "Notification email is required"
        exit 1
    fi
fi

if [[ -z "${NOTIFICATION_PHONE:-}" ]]; then
    read -p "Enter notification phone number (with country code, e.g., +1234567890): " NOTIFICATION_PHONE
    if [[ -z "${NOTIFICATION_PHONE}" ]]; then
        warning "No phone number provided. SMS notifications will not be configured."
        NOTIFICATION_PHONE=""
    fi
fi

# Validate email format
if [[ ! "${NOTIFICATION_EMAIL}" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; then
    error "Invalid email format: ${NOTIFICATION_EMAIL}"
    exit 1
fi

# Export variables for consistency
export RESOURCE_GROUP
export LOCATION
export SUBSCRIPTION_ID
export NOTIFICATION_EMAIL
export NOTIFICATION_PHONE

info "Configuration:"
info "  Resource Group: ${RESOURCE_GROUP}"
info "  Location: ${LOCATION}"
info "  Notification Email: ${NOTIFICATION_EMAIL}"
info "  Notification Phone: ${NOTIFICATION_PHONE:-"Not configured"}"

# Confirmation prompt
read -p "Proceed with deployment? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    info "Deployment cancelled by user"
    exit 0
fi

# Start deployment
info "Starting resource deployment..."

# Check if resource group exists
if az group show --name "${RESOURCE_GROUP}" &> /dev/null; then
    warning "Resource group ${RESOURCE_GROUP} already exists. Continuing with existing group."
else
    info "Creating resource group: ${RESOURCE_GROUP}"
    az group create \
        --name "${RESOURCE_GROUP}" \
        --location "${LOCATION}" \
        --tags purpose=service-health-monitoring environment=production \
        --output none
    success "Resource group created successfully"
fi

# Create Action Group
info "Creating action group for notifications..."

# Build action group command
ACTION_GROUP_CMD="az monitor action-group create \
    --name ServiceHealthAlerts \
    --resource-group ${RESOURCE_GROUP} \
    --short-name SvcHealth \
    --email-receivers name=admin-email email=${NOTIFICATION_EMAIL}"

# Add SMS receiver if phone number is provided
if [[ -n "${NOTIFICATION_PHONE}" ]]; then
    # Extract country code and phone number
    if [[ "${NOTIFICATION_PHONE}" =~ ^\+([0-9]+)([0-9]{10})$ ]]; then
        COUNTRY_CODE="${BASH_REMATCH[1]}"
        PHONE_NUMBER="${BASH_REMATCH[2]}"
        ACTION_GROUP_CMD="${ACTION_GROUP_CMD} --sms-receivers name=admin-sms country-code=${COUNTRY_CODE} phone-number=${PHONE_NUMBER}"
    else
        warning "Phone number format not recognized. SMS notifications will be skipped."
    fi
fi

# Execute action group creation
eval "${ACTION_GROUP_CMD} --output none"

# Get action group resource ID
ACTION_GROUP_ID=$(az monitor action-group show \
    --name "ServiceHealthAlerts" \
    --resource-group "${RESOURCE_GROUP}" \
    --query id --output tsv)

success "Action group created with ID: ${ACTION_GROUP_ID}"

# Create Service Health Alert Rules
info "Creating service health alert rules..."

# Service Issues Alert
info "Creating service issue alert rule..."
az monitor activity-log alert create \
    --name "ServiceIssueAlert" \
    --resource-group "${RESOURCE_GROUP}" \
    --condition category=ServiceHealth \
    --action-group "${ACTION_GROUP_ID}" \
    --description "Alert for Azure service issues affecting subscription" \
    --output none

success "Service issue alert rule created"

# Planned Maintenance Alert
info "Creating planned maintenance alert rule..."
az monitor activity-log alert create \
    --name "PlannedMaintenanceAlert" \
    --resource-group "${RESOURCE_GROUP}" \
    --condition category=ServiceHealth operationName=Microsoft.ServiceHealth/incident/action \
    --action-group "${ACTION_GROUP_ID}" \
    --description "Alert for planned Azure maintenance events" \
    --output none

success "Planned maintenance alert rule created"

# Health Advisory Alert
info "Creating health advisory alert rule..."
az monitor activity-log alert create \
    --name "HealthAdvisoryAlert" \
    --resource-group "${RESOURCE_GROUP}" \
    --condition category=ServiceHealth operationName=Microsoft.ServiceHealth/incident/action \
    --action-group "${ACTION_GROUP_ID}" \
    --description "Alert for Azure health advisories and recommendations" \
    --output none

success "Health advisory alert rule created"

# Critical Services Alert
info "Creating critical services alert rule..."
az monitor activity-log alert create \
    --name "CriticalServicesAlert" \
    --resource-group "${RESOURCE_GROUP}" \
    --condition category=ServiceHealth \
    --action-group "${ACTION_GROUP_ID}" \
    --description "Alert for critical Azure services: Virtual Machines, Storage, Networking" \
    --scope "/subscriptions/${SUBSCRIPTION_ID}" \
    --output none

success "Critical services alert rule created"

# Validation
info "Validating deployment..."

# Check action group
if az monitor action-group show --name "ServiceHealthAlerts" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
    success "Action group validation passed"
else
    error "Action group validation failed"
    exit 1
fi

# Check alert rules
ALERT_RULES=("ServiceIssueAlert" "PlannedMaintenanceAlert" "HealthAdvisoryAlert" "CriticalServicesAlert")
for rule in "${ALERT_RULES[@]}"; do
    if az monitor activity-log alert show --name "${rule}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        success "Alert rule ${rule} validation passed"
    else
        error "Alert rule ${rule} validation failed"
        exit 1
    fi
done

# Test notification (optional)
read -p "Send test notification to verify action group? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    info "Sending test notification..."
    if az monitor action-group test-notifications create \
        --action-group-name "ServiceHealthAlerts" \
        --resource-group "${RESOURCE_GROUP}" \
        --alert-type servicehealth \
        --output none 2>/dev/null; then
        success "Test notification sent successfully"
        info "Check your email and SMS for the test notification"
    else
        warning "Test notification failed, but this doesn't affect the deployment"
    fi
fi

# Save deployment info
DEPLOYMENT_INFO_FILE="${SCRIPT_DIR}/deployment-info.txt"
cat > "${DEPLOYMENT_INFO_FILE}" << EOF
# Azure Service Health Monitoring Deployment Information
# Generated: $(date)

DEPLOYMENT_NAME=${DEPLOYMENT_NAME}
RESOURCE_GROUP=${RESOURCE_GROUP}
LOCATION=${LOCATION}
SUBSCRIPTION_ID=${SUBSCRIPTION_ID}
ACTION_GROUP_ID=${ACTION_GROUP_ID}
NOTIFICATION_EMAIL=${NOTIFICATION_EMAIL}
NOTIFICATION_PHONE=${NOTIFICATION_PHONE}

# Alert Rules Created:
# - ServiceIssueAlert
# - PlannedMaintenanceAlert
# - HealthAdvisoryAlert
# - CriticalServicesAlert

# To clean up this deployment, run:
# ./destroy.sh
EOF

success "Deployment information saved to: ${DEPLOYMENT_INFO_FILE}"

# Final summary
echo -e "${GREEN}"
cat << 'EOF'
╔═══════════════════════════════════════════════════════════════╗
║                    DEPLOYMENT SUCCESSFUL                      ║
╚═══════════════════════════════════════════════════════════════╝
EOF
echo -e "${NC}"

success "Azure Service Health Monitoring deployment completed successfully!"
info "Resources created:"
info "  • Resource Group: ${RESOURCE_GROUP}"
info "  • Action Group: ServiceHealthAlerts"
info "  • Alert Rules: 4 service health monitoring rules"
info ""
info "Next steps:"
info "  1. Verify you received the test notification (if sent)"
info "  2. Review alert rules in the Azure portal"
info "  3. Customize notification channels as needed"
info "  4. Monitor service health events in Azure Service Health dashboard"
info ""
info "To clean up resources: ./destroy.sh"
info "Deployment log: ${LOG_FILE}"

exit 0