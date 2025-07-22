#!/bin/bash

# =============================================================================
# Azure App Service Environment v3 Enterprise Deployment Script
# =============================================================================
# This script deploys an enterprise-grade isolated web application hosting
# solution using Azure App Service Environment v3, Azure Private DNS, and
# Azure NAT Gateway for predictable outbound connectivity.
#
# Prerequisites:
# - Azure CLI v2.50.0 or later installed and configured
# - Azure subscription with Owner or Contributor permissions
# - Sufficient quota for App Service Environment deployment
#
# Estimated deployment time: 90-120 minutes
# Estimated cost: $1,000-$2,000 per month for dedicated infrastructure
# =============================================================================

set -euo pipefail

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

# Error handling
error_exit() {
    log_error "$1"
    exit 1
}

# Cleanup function for partial deployments
cleanup_on_error() {
    log_warning "Deployment failed. Cleaning up partial resources..."
    if [[ -n "${RESOURCE_GROUP:-}" ]]; then
        az group delete --name "${RESOURCE_GROUP}" --yes --no-wait 2>/dev/null || true
    fi
    exit 1
}

# Trap errors and call cleanup
trap cleanup_on_error ERR

# =============================================================================
# PREREQUISITE CHECKS
# =============================================================================

log_info "Starting prerequisite checks..."

# Check if Azure CLI is installed
if ! command -v az &> /dev/null; then
    error_exit "Azure CLI is not installed. Please install Azure CLI v2.50.0 or later."
fi

# Check Azure CLI version
AZ_VERSION=$(az version --query '"azure-cli"' -o tsv)
log_info "Azure CLI version: ${AZ_VERSION}"

# Check if user is logged in
if ! az account show &> /dev/null; then
    error_exit "Not logged in to Azure. Please run 'az login' first."
fi

# Get subscription information
SUBSCRIPTION_ID=$(az account show --query id --output tsv)
SUBSCRIPTION_NAME=$(az account show --query name --output tsv)
log_info "Using subscription: ${SUBSCRIPTION_NAME} (${SUBSCRIPTION_ID})"

# Check for required resource providers
log_info "Checking required resource providers..."
REQUIRED_PROVIDERS=(
    "Microsoft.Web"
    "Microsoft.Network"
    "Microsoft.Storage"
    "Microsoft.KeyVault"
    "Microsoft.Compute"
)

for provider in "${REQUIRED_PROVIDERS[@]}"; do
    if ! az provider show --namespace "${provider}" --query "registrationState" -o tsv | grep -q "Registered"; then
        log_info "Registering provider: ${provider}"
        az provider register --namespace "${provider}"
    fi
done

# =============================================================================
# CONFIGURATION VARIABLES
# =============================================================================

log_info "Setting up configuration variables..."

# Generate unique suffix for resource names
RANDOM_SUFFIX=$(openssl rand -hex 3)

# Core configuration
export RESOURCE_GROUP="rg-ase-enterprise-${RANDOM_SUFFIX}"
export LOCATION="${AZURE_LOCATION:-eastus}"
export SUBSCRIPTION_ID

# Resource naming with enterprise conventions
export VNET_NAME="vnet-ase-enterprise-${RANDOM_SUFFIX}"
export ASE_SUBNET_NAME="snet-ase-${RANDOM_SUFFIX}"
export NAT_SUBNET_NAME="snet-nat-${RANDOM_SUFFIX}"
export SUPPORT_SUBNET_NAME="snet-support-${RANDOM_SUFFIX}"
export BASTION_SUBNET_NAME="AzureBastionSubnet"
export ASE_NAME="ase-enterprise-${RANDOM_SUFFIX}"
export NAT_GATEWAY_NAME="nat-gateway-${RANDOM_SUFFIX}"
export PUBLIC_IP_NAME="pip-nat-${RANDOM_SUFFIX}"
export PRIVATE_DNS_ZONE="enterprise.internal"
export APP_SERVICE_PLAN_NAME="asp-enterprise-${RANDOM_SUFFIX}"
export WEB_APP_NAME="webapp-enterprise-${RANDOM_SUFFIX}"
export BASTION_NAME="bastion-${RANDOM_SUFFIX}"
export BASTION_PIP_NAME="pip-bastion-${RANDOM_SUFFIX}"
export MANAGEMENT_VM_NAME="vm-management-${RANDOM_SUFFIX}"

# Configuration summary
log_info "Deployment Configuration:"
log_info "  Resource Group: ${RESOURCE_GROUP}"
log_info "  Location: ${LOCATION}"
log_info "  ASE Name: ${ASE_NAME}"
log_info "  Random Suffix: ${RANDOM_SUFFIX}"

# =============================================================================
# RESOURCE GROUP CREATION
# =============================================================================

log_info "Creating resource group..."

if az group show --name "${RESOURCE_GROUP}" &> /dev/null; then
    log_warning "Resource group ${RESOURCE_GROUP} already exists. Continuing..."
else
    az group create \
        --name "${RESOURCE_GROUP}" \
        --location "${LOCATION}" \
        --tags purpose=enterprise-isolation environment=production deployment=ase-v3 \
        --output none
    log_success "Resource group created: ${RESOURCE_GROUP}"
fi

# =============================================================================
# VIRTUAL NETWORK AND SUBNETS
# =============================================================================

log_info "Creating virtual network and subnets..."

# Create virtual network
if az network vnet show --name "${VNET_NAME}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
    log_warning "Virtual network ${VNET_NAME} already exists. Continuing..."
else
    az network vnet create \
        --name "${VNET_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --location "${LOCATION}" \
        --address-prefix 10.0.0.0/16 \
        --tags purpose=enterprise-isolation tier=network \
        --output none
    log_success "Virtual network created: ${VNET_NAME}"
fi

# Create ASE subnet
if az network vnet subnet show --name "${ASE_SUBNET_NAME}" --vnet-name "${VNET_NAME}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
    log_warning "ASE subnet ${ASE_SUBNET_NAME} already exists. Continuing..."
else
    az network vnet subnet create \
        --vnet-name "${VNET_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --name "${ASE_SUBNET_NAME}" \
        --address-prefix 10.0.1.0/24 \
        --service-endpoints Microsoft.Storage Microsoft.KeyVault \
        --output none
    log_success "ASE subnet created: ${ASE_SUBNET_NAME}"
fi

# Create NAT Gateway subnet
if az network vnet subnet show --name "${NAT_SUBNET_NAME}" --vnet-name "${VNET_NAME}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
    log_warning "NAT subnet ${NAT_SUBNET_NAME} already exists. Continuing..."
else
    az network vnet subnet create \
        --vnet-name "${VNET_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --name "${NAT_SUBNET_NAME}" \
        --address-prefix 10.0.2.0/24 \
        --output none
    log_success "NAT subnet created: ${NAT_SUBNET_NAME}"
fi

# Create support subnet
if az network vnet subnet show --name "${SUPPORT_SUBNET_NAME}" --vnet-name "${VNET_NAME}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
    log_warning "Support subnet ${SUPPORT_SUBNET_NAME} already exists. Continuing..."
else
    az network vnet subnet create \
        --vnet-name "${VNET_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --name "${SUPPORT_SUBNET_NAME}" \
        --address-prefix 10.0.3.0/24 \
        --output none
    log_success "Support subnet created: ${SUPPORT_SUBNET_NAME}"
fi

# Create Bastion subnet
if az network vnet subnet show --name "${BASTION_SUBNET_NAME}" --vnet-name "${VNET_NAME}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
    log_warning "Bastion subnet ${BASTION_SUBNET_NAME} already exists. Continuing..."
else
    az network vnet subnet create \
        --vnet-name "${VNET_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --name "${BASTION_SUBNET_NAME}" \
        --address-prefix 10.0.4.0/26 \
        --output none
    log_success "Bastion subnet created: ${BASTION_SUBNET_NAME}"
fi

# =============================================================================
# NAT GATEWAY AND PUBLIC IP
# =============================================================================

log_info "Creating NAT Gateway for predictable outbound connectivity..."

# Create public IP for NAT Gateway
if az network public-ip show --name "${PUBLIC_IP_NAME}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
    log_warning "Public IP ${PUBLIC_IP_NAME} already exists. Continuing..."
else
    az network public-ip create \
        --name "${PUBLIC_IP_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --location "${LOCATION}" \
        --allocation-method Static \
        --sku Standard \
        --tags purpose=nat-gateway tier=network \
        --output none
    log_success "Public IP created: ${PUBLIC_IP_NAME}"
fi

# Create NAT Gateway
if az network nat gateway show --name "${NAT_GATEWAY_NAME}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
    log_warning "NAT Gateway ${NAT_GATEWAY_NAME} already exists. Continuing..."
else
    az network nat gateway create \
        --name "${NAT_GATEWAY_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --location "${LOCATION}" \
        --public-ip-addresses "${PUBLIC_IP_NAME}" \
        --idle-timeout 10 \
        --tags purpose=outbound-connectivity tier=network \
        --output none
    log_success "NAT Gateway created: ${NAT_GATEWAY_NAME}"
fi

# Associate NAT Gateway with ASE subnet
log_info "Associating NAT Gateway with ASE subnet..."
az network vnet subnet update \
    --name "${ASE_SUBNET_NAME}" \
    --resource-group "${RESOURCE_GROUP}" \
    --vnet-name "${VNET_NAME}" \
    --nat-gateway "${NAT_GATEWAY_NAME}" \
    --output none

# Get NAT Gateway public IP
NAT_PUBLIC_IP=$(az network public-ip show \
    --name "${PUBLIC_IP_NAME}" \
    --resource-group "${RESOURCE_GROUP}" \
    --query ipAddress --output tsv)

log_success "NAT Gateway configured with static IP: ${NAT_PUBLIC_IP}"

# =============================================================================
# PRIVATE DNS ZONE
# =============================================================================

log_info "Creating Private DNS zone for internal service discovery..."

# Create private DNS zone
if az network private-dns zone show --name "${PRIVATE_DNS_ZONE}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
    log_warning "Private DNS zone ${PRIVATE_DNS_ZONE} already exists. Continuing..."
else
    az network private-dns zone create \
        --name "${PRIVATE_DNS_ZONE}" \
        --resource-group "${RESOURCE_GROUP}" \
        --tags purpose=internal-dns tier=network \
        --output none
    log_success "Private DNS zone created: ${PRIVATE_DNS_ZONE}"
fi

# Link private DNS zone to virtual network
if az network private-dns link vnet show --name "link-${VNET_NAME}" --resource-group "${RESOURCE_GROUP}" --zone-name "${PRIVATE_DNS_ZONE}" &> /dev/null; then
    log_warning "DNS zone link already exists. Continuing..."
else
    az network private-dns link vnet create \
        --name "link-${VNET_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --zone-name "${PRIVATE_DNS_ZONE}" \
        --virtual-network "${VNET_NAME}" \
        --registration-enabled false \
        --output none
    log_success "Private DNS zone linked to virtual network"
fi

# =============================================================================
# APP SERVICE ENVIRONMENT V3
# =============================================================================

log_info "Creating App Service Environment v3 (this will take 60-90 minutes)..."

# Check if ASE already exists
if az appservice ase show --name "${ASE_NAME}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
    log_warning "App Service Environment ${ASE_NAME} already exists. Checking status..."
    ASE_STATE=$(az appservice ase show --name "${ASE_NAME}" --resource-group "${RESOURCE_GROUP}" --query "provisioningState" --output tsv)
    if [[ "${ASE_STATE}" == "Succeeded" ]]; then
        log_success "App Service Environment is already deployed successfully"
    else
        log_info "App Service Environment is in state: ${ASE_STATE}. Waiting for completion..."
    fi
else
    log_info "Starting App Service Environment v3 deployment..."
    az appservice ase create \
        --name "${ASE_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --subnet "${ASE_SUBNET_NAME}" \
        --vnet-name "${VNET_NAME}" \
        --kind ASEv3 \
        --virtual-ip-type Internal \
        --front-end-scale-factor 15 \
        --tags purpose=enterprise-isolation tier=compute \
        --output none
    log_success "App Service Environment deployment initiated"
fi

# Wait for ASE to be ready with progress indicator
log_info "Waiting for App Service Environment to be ready (this may take up to 90 minutes)..."
START_TIME=$(date +%s)
TIMEOUT=5400  # 90 minutes in seconds
CHECK_INTERVAL=60  # Check every minute

while true; do
    ASE_STATE=$(az appservice ase show --name "${ASE_NAME}" --resource-group "${RESOURCE_GROUP}" --query "provisioningState" --output tsv 2>/dev/null || echo "NotFound")
    
    if [[ "${ASE_STATE}" == "Succeeded" ]]; then
        log_success "App Service Environment is ready!"
        break
    elif [[ "${ASE_STATE}" == "Failed" ]]; then
        error_exit "App Service Environment deployment failed"
    fi
    
    CURRENT_TIME=$(date +%s)
    ELAPSED_TIME=$((CURRENT_TIME - START_TIME))
    
    if [[ ${ELAPSED_TIME} -gt ${TIMEOUT} ]]; then
        error_exit "App Service Environment deployment timed out after 90 minutes"
    fi
    
    ELAPSED_MINUTES=$((ELAPSED_TIME / 60))
    log_info "ASE Status: ${ASE_STATE} (${ELAPSED_MINUTES} minutes elapsed)"
    sleep ${CHECK_INTERVAL}
done

# Get ASE internal IP address
ASE_INTERNAL_IP=$(az appservice ase show \
    --name "${ASE_NAME}" \
    --resource-group "${RESOURCE_GROUP}" \
    --query "internalInboundIpAddress" \
    --output tsv)

log_success "App Service Environment deployed with internal IP: ${ASE_INTERNAL_IP}"

# =============================================================================
# APP SERVICE PLAN AND WEB APPLICATION
# =============================================================================

log_info "Creating App Service Plan and Web Application..."

# Create App Service Plan
if az appservice plan show --name "${APP_SERVICE_PLAN_NAME}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
    log_warning "App Service Plan ${APP_SERVICE_PLAN_NAME} already exists. Continuing..."
else
    az appservice plan create \
        --name "${APP_SERVICE_PLAN_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --ase "${ASE_NAME}" \
        --sku I1v2 \
        --is-linux false \
        --tags purpose=enterprise-app tier=compute \
        --output none
    log_success "App Service Plan created: ${APP_SERVICE_PLAN_NAME}"
fi

# Create web application
if az webapp show --name "${WEB_APP_NAME}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
    log_warning "Web application ${WEB_APP_NAME} already exists. Continuing..."
else
    az webapp create \
        --name "${WEB_APP_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --plan "${APP_SERVICE_PLAN_NAME}" \
        --runtime "dotnet:8" \
        --tags purpose=enterprise-app tier=application \
        --output none
    log_success "Web application created: ${WEB_APP_NAME}"
fi

# Configure application settings
log_info "Configuring application settings..."
az webapp config appsettings set \
    --name "${WEB_APP_NAME}" \
    --resource-group "${RESOURCE_GROUP}" \
    --settings \
        "WEBSITE_DNS_SERVER=168.63.129.16" \
        "WEBSITE_VNET_ROUTE_ALL=1" \
        "ASPNETCORE_ENVIRONMENT=Production" \
    --output none

log_success "Application settings configured"

# =============================================================================
# PRIVATE DNS RECORDS
# =============================================================================

log_info "Creating Private DNS records..."

# Create webapp DNS record
if az network private-dns record-set a show --name "webapp" --resource-group "${RESOURCE_GROUP}" --zone-name "${PRIVATE_DNS_ZONE}" &> /dev/null; then
    log_warning "DNS record for webapp already exists. Updating..."
    az network private-dns record-set a update \
        --name "webapp" \
        --resource-group "${RESOURCE_GROUP}" \
        --zone-name "${PRIVATE_DNS_ZONE}" \
        --set aRecords=[{ipv4Address:\"${ASE_INTERNAL_IP}\"}] \
        --output none
else
    az network private-dns record-set a create \
        --name "webapp" \
        --resource-group "${RESOURCE_GROUP}" \
        --zone-name "${PRIVATE_DNS_ZONE}" \
        --ttl 300 \
        --output none
    
    az network private-dns record-set a add-record \
        --record-set-name "webapp" \
        --resource-group "${RESOURCE_GROUP}" \
        --zone-name "${PRIVATE_DNS_ZONE}" \
        --ipv4-address "${ASE_INTERNAL_IP}" \
        --output none
fi

# Create API DNS record
if az network private-dns record-set a show --name "api" --resource-group "${RESOURCE_GROUP}" --zone-name "${PRIVATE_DNS_ZONE}" &> /dev/null; then
    log_warning "DNS record for api already exists. Updating..."
    az network private-dns record-set a update \
        --name "api" \
        --resource-group "${RESOURCE_GROUP}" \
        --zone-name "${PRIVATE_DNS_ZONE}" \
        --set aRecords=[{ipv4Address:\"${ASE_INTERNAL_IP}\"}] \
        --output none
else
    az network private-dns record-set a create \
        --name "api" \
        --resource-group "${RESOURCE_GROUP}" \
        --zone-name "${PRIVATE_DNS_ZONE}" \
        --ttl 300 \
        --output none
    
    az network private-dns record-set a add-record \
        --record-set-name "api" \
        --resource-group "${RESOURCE_GROUP}" \
        --zone-name "${PRIVATE_DNS_ZONE}" \
        --ipv4-address "${ASE_INTERNAL_IP}" \
        --output none
fi

# Create wildcard DNS record
if az network private-dns record-set a show --name "*" --resource-group "${RESOURCE_GROUP}" --zone-name "${PRIVATE_DNS_ZONE}" &> /dev/null; then
    log_warning "Wildcard DNS record already exists. Updating..."
    az network private-dns record-set a update \
        --name "*" \
        --resource-group "${RESOURCE_GROUP}" \
        --zone-name "${PRIVATE_DNS_ZONE}" \
        --set aRecords=[{ipv4Address:\"${ASE_INTERNAL_IP}\"}] \
        --output none
else
    az network private-dns record-set a create \
        --name "*" \
        --resource-group "${RESOURCE_GROUP}" \
        --zone-name "${PRIVATE_DNS_ZONE}" \
        --ttl 300 \
        --output none
    
    az network private-dns record-set a add-record \
        --record-set-name "*" \
        --resource-group "${RESOURCE_GROUP}" \
        --zone-name "${PRIVATE_DNS_ZONE}" \
        --ipv4-address "${ASE_INTERNAL_IP}" \
        --output none
fi

log_success "Private DNS records configured"

# =============================================================================
# AZURE BASTION
# =============================================================================

log_info "Creating Azure Bastion for secure management access..."

# Create public IP for Bastion
if az network public-ip show --name "${BASTION_PIP_NAME}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
    log_warning "Bastion public IP ${BASTION_PIP_NAME} already exists. Continuing..."
else
    az network public-ip create \
        --name "${BASTION_PIP_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --location "${LOCATION}" \
        --allocation-method Static \
        --sku Standard \
        --tags purpose=bastion tier=management \
        --output none
    log_success "Bastion public IP created: ${BASTION_PIP_NAME}"
fi

# Create Azure Bastion
if az network bastion show --name "${BASTION_NAME}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
    log_warning "Azure Bastion ${BASTION_NAME} already exists. Continuing..."
else
    az network bastion create \
        --name "${BASTION_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --location "${LOCATION}" \
        --public-ip-address "${BASTION_PIP_NAME}" \
        --vnet-name "${VNET_NAME}" \
        --sku Standard \
        --tags purpose=secure-management tier=management \
        --output none
    log_success "Azure Bastion created: ${BASTION_NAME}"
fi

# =============================================================================
# MANAGEMENT VIRTUAL MACHINE
# =============================================================================

log_info "Creating management virtual machine..."

# Check if VM already exists
if az vm show --name "${MANAGEMENT_VM_NAME}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
    log_warning "Management VM ${MANAGEMENT_VM_NAME} already exists. Continuing..."
else
    az vm create \
        --name "${MANAGEMENT_VM_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --location "${LOCATION}" \
        --image "Win2022Datacenter" \
        --size "Standard_D2s_v3" \
        --subnet "${SUPPORT_SUBNET_NAME}" \
        --vnet-name "${VNET_NAME}" \
        --admin-username "azureuser" \
        --admin-password "P@ssw0rd123!" \
        --nsg "" \
        --public-ip-address "" \
        --tags purpose=management tier=compute \
        --output none
    log_success "Management VM created: ${MANAGEMENT_VM_NAME}"
fi

# Install web server on management VM
log_info "Installing web server on management VM..."
az vm extension set \
    --name "CustomScriptExtension" \
    --publisher "Microsoft.Compute" \
    --resource-group "${RESOURCE_GROUP}" \
    --vm-name "${MANAGEMENT_VM_NAME}" \
    --settings '{"commandToExecute":"powershell.exe Install-WindowsFeature -Name Web-Server -IncludeManagementTools"}' \
    --output none

log_success "Management VM configured with web server"

# =============================================================================
# DEPLOYMENT SUMMARY
# =============================================================================

log_success "=== DEPLOYMENT COMPLETED SUCCESSFULLY ==="
log_info "Deployment Summary:"
log_info "  Resource Group: ${RESOURCE_GROUP}"
log_info "  Location: ${LOCATION}"
log_info "  App Service Environment: ${ASE_NAME}"
log_info "  ASE Internal IP: ${ASE_INTERNAL_IP}"
log_info "  Web Application: ${WEB_APP_NAME}"
log_info "  NAT Gateway Public IP: ${NAT_PUBLIC_IP}"
log_info "  Private DNS Zone: ${PRIVATE_DNS_ZONE}"
log_info "  Azure Bastion: ${BASTION_NAME}"
log_info "  Management VM: ${MANAGEMENT_VM_NAME}"

log_info ""
log_info "Next Steps:"
log_info "1. Connect to the management VM via Azure Bastion"
log_info "2. Test internal DNS resolution: nslookup webapp.${PRIVATE_DNS_ZONE}"
log_info "3. Access the web application at: https://webapp.${PRIVATE_DNS_ZONE}"
log_info "4. Deploy your application code to the App Service"

log_info ""
log_warning "Important: This deployment incurs significant costs (~$1,000/month base)."
log_warning "Run the destroy.sh script to clean up resources when no longer needed."

log_success "Deployment completed successfully!"