#!/bin/bash

# Intelligent DDoS Protection with Adaptive BGP Routing
# Deployment Script
# 
# This script deploys an adaptive network security architecture that combines 
# Azure DDoS Protection Standard with Azure Route Server for dynamic BGP-based 
# traffic routing and intelligent threat mitigation.

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Color codes for output
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

# Error handling
error_exit() {
    log_error "$1"
    log_error "Deployment failed. Check the logs above for details."
    exit 1
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        error_exit "Azure CLI is not installed. Please install Azure CLI before running this script."
    fi
    
    # Check Azure CLI version
    local az_version=$(az version --query '"azure-cli"' -o tsv 2>/dev/null || echo "unknown")
    log_info "Azure CLI version: $az_version"
    
    # Check if user is logged in
    if ! az account show &> /dev/null; then
        error_exit "Not logged in to Azure. Please run 'az login' before running this script."
    fi
    
    # Get current subscription info
    local subscription_name=$(az account show --query name -o tsv)
    local subscription_id=$(az account show --query id -o tsv)
    log_info "Using subscription: $subscription_name ($subscription_id)"
    
    # Check if openssl is available for random string generation
    if ! command -v openssl &> /dev/null; then
        error_exit "openssl is required for generating random suffixes. Please install openssl."
    fi
    
    log_success "Prerequisites check completed"
}

# Set environment variables
setup_environment() {
    log_info "Setting up environment variables..."
    
    # Core configuration
    export RESOURCE_GROUP="rg-adaptive-network-security"
    export LOCATION="eastus"
    export SUBSCRIPTION_ID=$(az account show --query id --output tsv)
    
    # Generate unique suffix for resource names
    RANDOM_SUFFIX=$(openssl rand -hex 3)
    log_info "Using random suffix: $RANDOM_SUFFIX"
    
    # Set resource naming variables
    export HUB_VNET_NAME="vnet-hub-${RANDOM_SUFFIX}"
    export SPOKE_VNET_NAME="vnet-spoke-${RANDOM_SUFFIX}"
    export ROUTE_SERVER_NAME="rs-adaptive-${RANDOM_SUFFIX}"
    export DDOS_PLAN_NAME="ddos-plan-${RANDOM_SUFFIX}"
    export FIREWALL_NAME="fw-adaptive-${RANDOM_SUFFIX}"
    export LOG_ANALYTICS_NAME="law-adaptive-${RANDOM_SUFFIX}"
    
    # Export variables for cleanup script
    echo "RESOURCE_GROUP=$RESOURCE_GROUP" > .env
    echo "HUB_VNET_NAME=$HUB_VNET_NAME" >> .env
    echo "SPOKE_VNET_NAME=$SPOKE_VNET_NAME" >> .env
    echo "ROUTE_SERVER_NAME=$ROUTE_SERVER_NAME" >> .env
    echo "DDOS_PLAN_NAME=$DDOS_PLAN_NAME" >> .env
    echo "FIREWALL_NAME=$FIREWALL_NAME" >> .env
    echo "LOG_ANALYTICS_NAME=$LOG_ANALYTICS_NAME" >> .env
    echo "RANDOM_SUFFIX=$RANDOM_SUFFIX" >> .env
    
    log_success "Environment variables configured"
}

# Create resource group and register providers
create_resource_group() {
    log_info "Creating resource group and registering providers..."
    
    # Create resource group
    az group create \
        --name "${RESOURCE_GROUP}" \
        --location "${LOCATION}" \
        --tags purpose=adaptive-network-security environment=production \
        || error_exit "Failed to create resource group"
    
    log_success "Resource group created: ${RESOURCE_GROUP}"
    
    # Register required resource providers
    log_info "Registering resource providers..."
    az provider register --namespace Microsoft.Network --wait || log_warning "Microsoft.Network provider registration failed"
    az provider register --namespace Microsoft.Security --wait || log_warning "Microsoft.Security provider registration failed"
    az provider register --namespace Microsoft.OperationalInsights --wait || log_warning "Microsoft.OperationalInsights provider registration failed"
    
    log_success "Resource providers registered"
}

# Create DDoS Protection Plan
create_ddos_protection() {
    log_info "Creating DDoS Protection Plan..."
    
    # Create DDoS Protection Plan
    az network ddos-protection create \
        --name "${DDOS_PLAN_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --location "${LOCATION}" \
        --tags purpose=ddos-protection tier=standard \
        || error_exit "Failed to create DDoS Protection Plan"
    
    # Store DDoS Protection Plan ID for later use
    DDOS_PLAN_ID=$(az network ddos-protection show \
        --name "${DDOS_PLAN_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query id --output tsv) \
        || error_exit "Failed to get DDoS Protection Plan ID"
    
    echo "DDOS_PLAN_ID=$DDOS_PLAN_ID" >> .env
    
    log_success "DDoS Protection Plan created: ${DDOS_PLAN_NAME}"
}

# Create hub virtual network with DDoS protection
create_hub_network() {
    log_info "Creating hub virtual network with DDoS Protection..."
    
    # Create hub virtual network with DDoS Protection
    az network vnet create \
        --name "${HUB_VNET_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --location "${LOCATION}" \
        --address-prefix 10.0.0.0/16 \
        --ddos-protection-plan "${DDOS_PLAN_ID}" \
        --enable-ddos-protection true \
        --tags purpose=hub-network tier=production \
        || error_exit "Failed to create hub virtual network"
    
    # Create Route Server subnet (required for Azure Route Server)
    az network vnet subnet create \
        --name RouteServerSubnet \
        --resource-group "${RESOURCE_GROUP}" \
        --vnet-name "${HUB_VNET_NAME}" \
        --address-prefix 10.0.1.0/27 \
        || error_exit "Failed to create RouteServerSubnet"
    
    # Create Azure Firewall subnet
    az network vnet subnet create \
        --name AzureFirewallSubnet \
        --resource-group "${RESOURCE_GROUP}" \
        --vnet-name "${HUB_VNET_NAME}" \
        --address-prefix 10.0.2.0/26 \
        || error_exit "Failed to create AzureFirewallSubnet"
    
    # Create management subnet for network appliances
    az network vnet subnet create \
        --name ManagementSubnet \
        --resource-group "${RESOURCE_GROUP}" \
        --vnet-name "${HUB_VNET_NAME}" \
        --address-prefix 10.0.3.0/24 \
        || error_exit "Failed to create ManagementSubnet"
    
    log_success "Hub VNet created with DDoS Protection enabled"
}

# Create spoke virtual network and peering
create_spoke_network() {
    log_info "Creating spoke virtual network and establishing peering..."
    
    # Create spoke virtual network
    az network vnet create \
        --name "${SPOKE_VNET_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --location "${LOCATION}" \
        --address-prefix 10.1.0.0/16 \
        --tags purpose=spoke-network tier=application \
        || error_exit "Failed to create spoke virtual network"
    
    # Create application subnet
    az network vnet subnet create \
        --name ApplicationSubnet \
        --resource-group "${RESOURCE_GROUP}" \
        --vnet-name "${SPOKE_VNET_NAME}" \
        --address-prefix 10.1.1.0/24 \
        || error_exit "Failed to create ApplicationSubnet"
    
    # Create database subnet
    az network vnet subnet create \
        --name DatabaseSubnet \
        --resource-group "${RESOURCE_GROUP}" \
        --vnet-name "${SPOKE_VNET_NAME}" \
        --address-prefix 10.1.2.0/24 \
        || error_exit "Failed to create DatabaseSubnet"
    
    # Create VNet peering from hub to spoke
    az network vnet peering create \
        --name "hub-to-spoke" \
        --resource-group "${RESOURCE_GROUP}" \
        --vnet-name "${HUB_VNET_NAME}" \
        --remote-vnet "${SPOKE_VNET_NAME}" \
        --allow-vnet-access \
        --allow-forwarded-traffic \
        --use-remote-gateways false \
        || error_exit "Failed to create hub-to-spoke peering"
    
    # Create VNet peering from spoke to hub
    az network vnet peering create \
        --name "spoke-to-hub" \
        --resource-group "${RESOURCE_GROUP}" \
        --vnet-name "${SPOKE_VNET_NAME}" \
        --remote-vnet "${HUB_VNET_NAME}" \
        --allow-vnet-access \
        --allow-forwarded-traffic \
        --use-remote-gateways false \
        || error_exit "Failed to create spoke-to-hub peering"
    
    log_success "Spoke VNet created and peered with hub"
}

# Deploy Azure Route Server
deploy_route_server() {
    log_info "Deploying Azure Route Server..."
    
    # Create public IP for Route Server
    az network public-ip create \
        --name "pip-${ROUTE_SERVER_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --location "${LOCATION}" \
        --allocation-method Static \
        --sku Standard \
        --tier Regional \
        || error_exit "Failed to create Route Server public IP"
    
    # Create Azure Route Server
    az network routeserver create \
        --name "${ROUTE_SERVER_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --location "${LOCATION}" \
        --hosted-subnet $(az network vnet subnet show \
            --name RouteServerSubnet \
            --resource-group "${RESOURCE_GROUP}" \
            --vnet-name "${HUB_VNET_NAME}" \
            --query id --output tsv) \
        --public-ip-address "pip-${ROUTE_SERVER_NAME}" \
        --tags purpose=dynamic-routing tier=production \
        || error_exit "Failed to create Azure Route Server"
    
    # Wait for Route Server deployment
    log_info "Waiting for Route Server deployment..."
    az network routeserver wait \
        --name "${ROUTE_SERVER_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --created \
        || error_exit "Route Server deployment failed"
    
    log_success "Azure Route Server deployed and ready"
}

# Configure Azure Firewall
configure_firewall() {
    log_info "Configuring Azure Firewall for traffic inspection..."
    
    # Create public IP for Azure Firewall
    az network public-ip create \
        --name "pip-${FIREWALL_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --location "${LOCATION}" \
        --allocation-method Static \
        --sku Standard \
        --tier Regional \
        || error_exit "Failed to create Firewall public IP"
    
    # Create Azure Firewall
    az network firewall create \
        --name "${FIREWALL_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --location "${LOCATION}" \
        --tier Standard \
        --sku AZFW_VNet \
        --tags purpose=network-security tier=production \
        || error_exit "Failed to create Azure Firewall"
    
    # Configure Azure Firewall IP configuration
    az network firewall ip-config create \
        --name "fw-ipconfig" \
        --resource-group "${RESOURCE_GROUP}" \
        --firewall-name "${FIREWALL_NAME}" \
        --public-ip-address "pip-${FIREWALL_NAME}" \
        --vnet-name "${HUB_VNET_NAME}" \
        || error_exit "Failed to configure Firewall IP"
    
    # Create network rule collection for traffic inspection
    az network firewall network-rule create \
        --collection-name "adaptive-security-rules" \
        --destination-addresses "*" \
        --destination-ports 80 443 \
        --firewall-name "${FIREWALL_NAME}" \
        --name "allow-web-traffic" \
        --protocols TCP \
        --resource-group "${RESOURCE_GROUP}" \
        --rule-type NetworkRule \
        --source-addresses 10.1.0.0/16 \
        --action Allow \
        --priority 100 \
        || error_exit "Failed to create firewall rules"
    
    log_success "Azure Firewall configured with traffic inspection rules"
}

# Create monitoring infrastructure
create_monitoring() {
    log_info "Creating Log Analytics workspace and monitoring infrastructure..."
    
    # Create Log Analytics workspace
    az monitor log-analytics workspace create \
        --name "${LOG_ANALYTICS_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --location "${LOCATION}" \
        --sku PerGB2018 \
        --retention-time 30 \
        --tags purpose=security-monitoring tier=production \
        || error_exit "Failed to create Log Analytics workspace"
    
    # Get workspace ID for configuration
    WORKSPACE_ID=$(az monitor log-analytics workspace show \
        --name "${LOG_ANALYTICS_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query id --output tsv) \
        || error_exit "Failed to get workspace ID"
    
    echo "WORKSPACE_ID=$WORKSPACE_ID" >> .env
    
    log_success "Log Analytics workspace created: ${LOG_ANALYTICS_NAME}"
}

# Configure Network Watcher and flow logs
configure_network_watcher() {
    log_info "Configuring Network Watcher and flow logs..."
    
    # Enable Network Watcher
    az network watcher configure \
        --resource-group "${RESOURCE_GROUP}" \
        --location "${LOCATION}" \
        --enabled true \
        || log_warning "Failed to configure Network Watcher (may already be enabled)"
    
    # Create storage account for flow logs
    STORAGE_ACCOUNT="stflowlogs${RANDOM_SUFFIX}"
    az storage account create \
        --name "${STORAGE_ACCOUNT}" \
        --resource-group "${RESOURCE_GROUP}" \
        --location "${LOCATION}" \
        --sku Standard_LRS \
        --kind StorageV2 \
        || error_exit "Failed to create storage account"
    
    echo "STORAGE_ACCOUNT=$STORAGE_ACCOUNT" >> .env
    
    # Get Network Security Group ID for spoke network (if exists)
    NSG_ID=$(az network nsg list \
        --resource-group "${RESOURCE_GROUP}" \
        --query "[?contains(name,'${SPOKE_VNET_NAME}')].id" \
        --output tsv 2>/dev/null || echo "")
    
    # Configure flow logs if NSG exists
    if [ ! -z "$NSG_ID" ]; then
        az network watcher flow-log create \
            --name "flowlog-${RANDOM_SUFFIX}" \
            --resource-group "${RESOURCE_GROUP}" \
            --location "${LOCATION}" \
            --nsg "${NSG_ID}" \
            --storage-account "${STORAGE_ACCOUNT}" \
            --workspace "${WORKSPACE_ID}" \
            --enabled true \
            --format JSON \
            --log-version 2 \
            || log_warning "Flow logs configuration failed"
        
        log_success "Flow logs configured for network monitoring"
    else
        log_info "No NSG found, skipping flow log configuration"
    fi
    
    log_success "Network Watcher enabled and configured"
}

# Configure DDoS monitoring and alerts
configure_ddos_monitoring() {
    log_info "Configuring DDoS Protection monitoring and alerts..."
    
    # Create action group for DDoS alerts
    az monitor action-group create \
        --name "ddos-alerts-${RANDOM_SUFFIX}" \
        --resource-group "${RESOURCE_GROUP}" \
        --short-name "ddos-ag" \
        --tags purpose=ddos-alerting \
        || error_exit "Failed to create action group"
    
    # Get DDoS Protection Plan resource ID
    DDOS_RESOURCE_ID=$(az network ddos-protection show \
        --name "${DDOS_PLAN_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query id --output tsv) \
        || error_exit "Failed to get DDoS resource ID"
    
    # Create alert rule for DDoS attack detection
    az monitor metrics alert create \
        --name "DDoS-Attack-Alert" \
        --resource-group "${RESOURCE_GROUP}" \
        --scopes "${DDOS_RESOURCE_ID}" \
        --condition "avg DDoSAttack > 0" \
        --window-size 5m \
        --evaluation-frequency 1m \
        --severity 1 \
        --action "ddos-alerts-${RANDOM_SUFFIX}" \
        --description "Alert when DDoS attack is detected" \
        || error_exit "Failed to create DDoS attack alert"
    
    # Create alert rule for traffic volume monitoring
    az monitor metrics alert create \
        --name "High-Traffic-Volume-Alert" \
        --resource-group "${RESOURCE_GROUP}" \
        --scopes "${DDOS_RESOURCE_ID}" \
        --condition "avg PacketsInboundTotal > 100000" \
        --window-size 5m \
        --evaluation-frequency 1m \
        --severity 2 \
        --action "ddos-alerts-${RANDOM_SUFFIX}" \
        --description "Alert when traffic volume exceeds threshold" \
        || error_exit "Failed to create traffic volume alert"
    
    log_success "DDoS monitoring and alerting configured"
}

# Validate deployment
validate_deployment() {
    log_info "Validating deployment..."
    
    # Check DDoS Protection Plan status
    local ddos_status=$(az network ddos-protection show \
        --name "${DDOS_PLAN_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query "provisioningState" \
        --output tsv 2>/dev/null || echo "Unknown")
    
    if [ "$ddos_status" = "Succeeded" ]; then
        log_success "DDoS Protection Plan is active"
    else
        log_warning "DDoS Protection Plan status: $ddos_status"
    fi
    
    # Check Route Server status
    local rs_status=$(az network routeserver show \
        --name "${ROUTE_SERVER_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query "provisioningState" \
        --output tsv 2>/dev/null || echo "Unknown")
    
    if [ "$rs_status" = "Succeeded" ]; then
        log_success "Azure Route Server is active"
    else
        log_warning "Azure Route Server status: $rs_status"
    fi
    
    # Check VNet DDoS Protection status
    local vnet_ddos=$(az network vnet show \
        --name "${HUB_VNET_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query "enableDdosProtection" \
        --output tsv 2>/dev/null || echo "false")
    
    if [ "$vnet_ddos" = "true" ]; then
        log_success "Hub VNet has DDoS Protection enabled"
    else
        log_warning "Hub VNet DDoS Protection not enabled"
    fi
    
    log_info "Deployment validation completed"
}

# Display deployment summary
display_summary() {
    log_info "Deployment Summary"
    echo "===================="
    echo "Resource Group: ${RESOURCE_GROUP}"
    echo "Location: ${LOCATION}"
    echo "Hub VNet: ${HUB_VNET_NAME}"
    echo "Spoke VNet: ${SPOKE_VNET_NAME}"
    echo "Route Server: ${ROUTE_SERVER_NAME}"
    echo "DDoS Plan: ${DDOS_PLAN_NAME}"
    echo "Firewall: ${FIREWALL_NAME}"
    echo "Log Analytics: ${LOG_ANALYTICS_NAME}"
    echo "Random Suffix: ${RANDOM_SUFFIX}"
    echo ""
    log_success "Adaptive network security architecture deployed successfully!"
    echo ""
    log_info "Next steps:"
    echo "1. Configure BGP peering with your network virtual appliances"
    echo "2. Test DDoS protection by monitoring metrics in Azure Monitor"
    echo "3. Review and customize firewall rules based on your requirements"
    echo "4. Set up additional alerting and monitoring as needed"
    echo ""
    log_warning "Remember to run ./destroy.sh when you want to clean up resources"
}

# Main deployment function
main() {
    log_info "Starting deployment of Adaptive Network Security with Azure DDoS Protection and Route Server"
    
    check_prerequisites
    setup_environment
    create_resource_group
    create_ddos_protection
    create_hub_network
    create_spoke_network
    deploy_route_server
    configure_firewall
    create_monitoring
    configure_network_watcher
    configure_ddos_monitoring
    validate_deployment
    display_summary
    
    log_success "Deployment completed successfully!"
}

# Run main function
main "$@"