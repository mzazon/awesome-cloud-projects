#!/bin/bash

# ================================================================================
# Azure Hybrid Network Security Deployment Script
# Recipe: Hybrid Network Threat Protection with Premium Firewall
# ================================================================================

set -e
set -o pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] INFO:${NC} $1"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARN:${NC} $1"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1" >&2
}

success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] SUCCESS:${NC} $1"
}

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to validate Azure CLI authentication
validate_azure_auth() {
    log "Validating Azure CLI authentication..."
    if ! az account show >/dev/null 2>&1; then
        error "Azure CLI not authenticated. Please run 'az login' first."
        exit 1
    fi
    success "Azure CLI authentication validated"
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command_exists az; then
        error "Azure CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check Azure CLI version
    local az_version=$(az version --query '."azure-cli"' -o tsv 2>/dev/null)
    if [ -z "$az_version" ]; then
        error "Unable to determine Azure CLI version"
        exit 1
    fi
    
    log "Azure CLI version: $az_version"
    
    # Validate authentication
    validate_azure_auth
    
    # Check if openssl is available for random string generation
    if ! command_exists openssl; then
        error "OpenSSL is not available. This is required for generating random strings."
        exit 1
    fi
    
    success "All prerequisites met"
}

# Function to set environment variables
set_environment_variables() {
    log "Setting environment variables..."
    
    # Generate unique suffix for resource names
    export RANDOM_SUFFIX=$(openssl rand -hex 3)
    
    # Set environment variables for Azure resources
    export RESOURCE_GROUP="rg-hybrid-security-${RANDOM_SUFFIX}"
    export LOCATION="eastus"
    export SUBSCRIPTION_ID=$(az account show --query id --output tsv)
    
    # Network configuration variables
    export HUB_VNET_NAME="vnet-hub-${RANDOM_SUFFIX}"
    export SPOKE_VNET_NAME="vnet-spoke-${RANDOM_SUFFIX}"
    export FIREWALL_NAME="azfw-premium-${RANDOM_SUFFIX}"
    export FIREWALL_POLICY_NAME="azfw-policy-${RANDOM_SUFFIX}"
    export EXPRESSROUTE_GW_NAME="ergw-${RANDOM_SUFFIX}"
    export LOG_ANALYTICS_NAME="laws-firewall-${RANDOM_SUFFIX}"
    
    # Network address spaces
    export HUB_VNET_PREFIX="10.0.0.0/16"
    export SPOKE_VNET_PREFIX="10.1.0.0/16"
    export FIREWALL_SUBNET_PREFIX="10.0.1.0/24"
    export GATEWAY_SUBNET_PREFIX="10.0.2.0/24"
    export WORKLOAD_SUBNET_PREFIX="10.1.1.0/24"
    
    log "Environment variables set:"
    log "  Resource Group: ${RESOURCE_GROUP}"
    log "  Location: ${LOCATION}"
    log "  Random Suffix: ${RANDOM_SUFFIX}"
    log "  Hub VNet: ${HUB_VNET_NAME}"
    log "  Spoke VNet: ${SPOKE_VNET_NAME}"
    log "  Firewall: ${FIREWALL_NAME}"
    log "  ExpressRoute Gateway: ${EXPRESSROUTE_GW_NAME}"
}

# Function to create resource group
create_resource_group() {
    log "Creating resource group: ${RESOURCE_GROUP}"
    
    az group create \
        --name "${RESOURCE_GROUP}" \
        --location "${LOCATION}" \
        --tags purpose=hybrid-security environment=production
    
    success "Resource group created: ${RESOURCE_GROUP}"
}

# Function to create hub virtual network
create_hub_vnet() {
    log "Creating hub virtual network and subnets..."
    
    # Create hub virtual network
    az network vnet create \
        --resource-group "${RESOURCE_GROUP}" \
        --name "${HUB_VNET_NAME}" \
        --address-prefixes "${HUB_VNET_PREFIX}" \
        --location "${LOCATION}" \
        --tags purpose=hub-network
    
    # Create AzureFirewallSubnet (name is required exactly as shown)
    az network vnet subnet create \
        --resource-group "${RESOURCE_GROUP}" \
        --vnet-name "${HUB_VNET_NAME}" \
        --name AzureFirewallSubnet \
        --address-prefixes "${FIREWALL_SUBNET_PREFIX}"
    
    # Create GatewaySubnet for ExpressRoute Gateway
    az network vnet subnet create \
        --resource-group "${RESOURCE_GROUP}" \
        --vnet-name "${HUB_VNET_NAME}" \
        --name GatewaySubnet \
        --address-prefixes "${GATEWAY_SUBNET_PREFIX}"
    
    success "Hub virtual network and subnets created successfully"
}

# Function to create spoke virtual network and peering
create_spoke_vnet() {
    log "Creating spoke virtual network and establishing peering..."
    
    # Create spoke virtual network
    az network vnet create \
        --resource-group "${RESOURCE_GROUP}" \
        --name "${SPOKE_VNET_NAME}" \
        --address-prefixes "${SPOKE_VNET_PREFIX}" \
        --location "${LOCATION}" \
        --tags purpose=spoke-network
    
    # Create workload subnet in spoke network
    az network vnet subnet create \
        --resource-group "${RESOURCE_GROUP}" \
        --vnet-name "${SPOKE_VNET_NAME}" \
        --name WorkloadSubnet \
        --address-prefixes "${WORKLOAD_SUBNET_PREFIX}"
    
    # Create hub-to-spoke peering
    az network vnet peering create \
        --resource-group "${RESOURCE_GROUP}" \
        --name hub-to-spoke \
        --vnet-name "${HUB_VNET_NAME}" \
        --remote-vnet "${SPOKE_VNET_NAME}" \
        --allow-vnet-access true \
        --allow-forwarded-traffic true \
        --allow-gateway-transit true
    
    # Create spoke-to-hub peering
    az network vnet peering create \
        --resource-group "${RESOURCE_GROUP}" \
        --name spoke-to-hub \
        --vnet-name "${SPOKE_VNET_NAME}" \
        --remote-vnet "${HUB_VNET_NAME}" \
        --allow-vnet-access true \
        --allow-forwarded-traffic true \
        --use-remote-gateways true
    
    success "Spoke virtual network and peering established"
}

# Function to create Log Analytics workspace
create_log_analytics() {
    log "Creating Log Analytics workspace for monitoring..."
    
    # Create Log Analytics workspace
    az monitor log-analytics workspace create \
        --resource-group "${RESOURCE_GROUP}" \
        --workspace-name "${LOG_ANALYTICS_NAME}" \
        --location "${LOCATION}" \
        --retention-time 30 \
        --sku PerGB2018
    
    # Get workspace ID for firewall configuration
    export WORKSPACE_ID=$(az monitor log-analytics workspace show \
        --resource-group "${RESOURCE_GROUP}" \
        --workspace-name "${LOG_ANALYTICS_NAME}" \
        --query id --output tsv)
    
    success "Log Analytics workspace created: ${LOG_ANALYTICS_NAME}"
    log "Workspace ID: ${WORKSPACE_ID}"
}

# Function to create Azure Firewall Premium
create_azure_firewall() {
    log "Creating Azure Firewall Premium public IP and firewall policy..."
    
    # Create public IP for Azure Firewall
    az network public-ip create \
        --resource-group "${RESOURCE_GROUP}" \
        --name "pip-${FIREWALL_NAME}" \
        --location "${LOCATION}" \
        --allocation-method Static \
        --sku Standard \
        --tier Regional
    
    # Create firewall policy for Premium features
    az network firewall policy create \
        --resource-group "${RESOURCE_GROUP}" \
        --name "${FIREWALL_POLICY_NAME}" \
        --location "${LOCATION}" \
        --sku Premium \
        --threat-intel-mode Alert \
        --enable-dns-proxy true \
        --enable-explicit-proxy false
    
    # Configure IDPS (Intrusion Detection and Prevention System)
    az network firewall policy update \
        --resource-group "${RESOURCE_GROUP}" \
        --name "${FIREWALL_POLICY_NAME}" \
        --idps-mode Alert
    
    log "Deploying Azure Firewall Premium (this may take 10-15 minutes)..."
    
    # Deploy Azure Firewall Premium
    az network firewall create \
        --resource-group "${RESOURCE_GROUP}" \
        --name "${FIREWALL_NAME}" \
        --location "${LOCATION}" \
        --vnet-name "${HUB_VNET_NAME}" \
        --public-ip "pip-${FIREWALL_NAME}" \
        --firewall-policy "${FIREWALL_POLICY_NAME}" \
        --sku AZFW_VNet \
        --tier Premium
    
    # Get firewall private IP for routing configuration
    export FIREWALL_PRIVATE_IP=$(az network firewall show \
        --resource-group "${RESOURCE_GROUP}" \
        --name "${FIREWALL_NAME}" \
        --query ipConfigurations[0].privateIPAddress \
        --output tsv)
    
    success "Azure Firewall Premium deployed successfully"
    log "Firewall private IP: ${FIREWALL_PRIVATE_IP}"
}

# Function to configure firewall diagnostics
configure_firewall_diagnostics() {
    log "Configuring diagnostic settings for Azure Firewall..."
    
    # Enable diagnostic settings for Azure Firewall
    az monitor diagnostic-settings create \
        --resource-group "${RESOURCE_GROUP}" \
        --name firewall-diagnostics \
        --resource "$(az network firewall show \
            --resource-group "${RESOURCE_GROUP}" \
            --name "${FIREWALL_NAME}" \
            --query id --output tsv)" \
        --workspace "${WORKSPACE_ID}" \
        --logs '[
            {
                "category": "AzureFirewallApplicationRule",
                "enabled": true,
                "retentionPolicy": {
                    "enabled": true,
                    "days": 30
                }
            },
            {
                "category": "AzureFirewallNetworkRule",
                "enabled": true,
                "retentionPolicy": {
                    "enabled": true,
                    "days": 30
                }
            },
            {
                "category": "AzureFirewallDnsProxy",
                "enabled": true,
                "retentionPolicy": {
                    "enabled": true,
                    "days": 30
                }
            },
            {
                "category": "AZFWIdpsSignature",
                "enabled": true,
                "retentionPolicy": {
                    "enabled": true,
                    "days": 30
                }
            },
            {
                "category": "AZFWThreatIntel",
                "enabled": true,
                "retentionPolicy": {
                    "enabled": true,
                    "days": 30
                }
            }
        ]' \
        --metrics '[
            {
                "category": "AllMetrics",
                "enabled": true,
                "retentionPolicy": {
                    "enabled": true,
                    "days": 30
                }
            }
        ]'
    
    success "Diagnostic settings configured for comprehensive monitoring"
}

# Function to create ExpressRoute Gateway
create_expressroute_gateway() {
    log "Creating ExpressRoute Virtual Network Gateway..."
    
    # Create public IP for ExpressRoute Gateway
    az network public-ip create \
        --resource-group "${RESOURCE_GROUP}" \
        --name "pip-${EXPRESSROUTE_GW_NAME}" \
        --location "${LOCATION}" \
        --allocation-method Static \
        --sku Standard \
        --tier Regional
    
    warn "ExpressRoute Gateway deployment will take 15-20 minutes. Starting deployment..."
    
    # Create ExpressRoute Gateway (this operation takes 15-20 minutes)
    az network vnet-gateway create \
        --resource-group "${RESOURCE_GROUP}" \
        --name "${EXPRESSROUTE_GW_NAME}" \
        --vnet "${HUB_VNET_NAME}" \
        --public-ip-addresses "pip-${EXPRESSROUTE_GW_NAME}" \
        --gateway-type ExpressRoute \
        --sku Standard \
        --location "${LOCATION}" \
        --no-wait
    
    success "ExpressRoute Gateway deployment initiated (15-20 minutes)"
    log "Gateway deployment running in background..."
}

# Function to create network security rules
create_network_security_rules() {
    log "Creating network security rules for hybrid traffic..."
    
    # Create network rule collection for hybrid connectivity
    az network firewall policy rule-collection-group create \
        --resource-group "${RESOURCE_GROUP}" \
        --policy-name "${FIREWALL_POLICY_NAME}" \
        --name HybridNetworkRules \
        --priority 1000
    
    # Add network rules for on-premises to Azure traffic
    az network firewall policy rule-collection-group collection add-filter-collection \
        --resource-group "${RESOURCE_GROUP}" \
        --policy-name "${FIREWALL_POLICY_NAME}" \
        --rule-collection-group-name HybridNetworkRules \
        --name OnPremToAzureRules \
        --collection-priority 1100 \
        --action Allow \
        --rule-name AllowOnPremToSpoke \
        --rule-type NetworkRule \
        --description "Allow on-premises traffic to spoke networks" \
        --destination-addresses "${SPOKE_VNET_PREFIX}" \
        --source-addresses 192.168.0.0/16 \
        --ip-protocols TCP UDP \
        --destination-ports 443 80 22 3389
    
    # Add application rules for web traffic inspection
    az network firewall policy rule-collection-group collection add-filter-collection \
        --resource-group "${RESOURCE_GROUP}" \
        --policy-name "${FIREWALL_POLICY_NAME}" \
        --rule-collection-group-name HybridNetworkRules \
        --name WebTrafficRules \
        --collection-priority 1200 \
        --action Allow \
        --rule-name AllowWebTraffic \
        --rule-type ApplicationRule \
        --description "Allow web traffic with TLS inspection" \
        --target-fqdns "*.microsoft.com" "*.azure.com" "*.office.com" \
        --source-addresses "${SPOKE_VNET_PREFIX}" 192.168.0.0/16 \
        --protocols "https=443" "http=80"
    
    success "Network security rules configured for hybrid traffic"
}

# Function to configure route tables
configure_route_tables() {
    log "Configuring route tables for traffic steering..."
    
    # Create route table for spoke network traffic steering
    az network route-table create \
        --resource-group "${RESOURCE_GROUP}" \
        --name rt-spoke-firewall \
        --location "${LOCATION}"
    
    # Add route to direct traffic through firewall
    az network route-table route create \
        --resource-group "${RESOURCE_GROUP}" \
        --route-table-name rt-spoke-firewall \
        --name route-to-onprem \
        --address-prefix 192.168.0.0/16 \
        --next-hop-type VirtualAppliance \
        --next-hop-ip-address "${FIREWALL_PRIVATE_IP}"
    
    # Add default route through firewall for internet traffic
    az network route-table route create \
        --resource-group "${RESOURCE_GROUP}" \
        --route-table-name rt-spoke-firewall \
        --name route-default \
        --address-prefix 0.0.0.0/0 \
        --next-hop-type VirtualAppliance \
        --next-hop-ip-address "${FIREWALL_PRIVATE_IP}"
    
    # Associate route table with spoke workload subnet
    az network vnet subnet update \
        --resource-group "${RESOURCE_GROUP}" \
        --vnet-name "${SPOKE_VNET_NAME}" \
        --name WorkloadSubnet \
        --route-table rt-spoke-firewall
    
    success "Route tables configured for traffic steering through firewall"
}

# Function to wait for ExpressRoute Gateway completion
wait_for_expressroute_gateway() {
    log "Waiting for ExpressRoute Gateway deployment to complete..."
    
    # Wait for ExpressRoute Gateway deployment to complete
    az network vnet-gateway wait \
        --resource-group "${RESOURCE_GROUP}" \
        --name "${EXPRESSROUTE_GW_NAME}" \
        --created \
        --timeout 1800
    
    success "ExpressRoute Gateway deployment completed"
    
    # Provide instructions for connecting ExpressRoute circuit
    log "To connect your ExpressRoute circuit, you'll need to:"
    log "1. Obtain your ExpressRoute circuit resource ID"
    log "2. Run the following command:"
    log "   az network vpn-connection create \\"
    log "       --resource-group ${RESOURCE_GROUP} \\"
    log "       --name connection-expressroute \\"
    log "       --vnet-gateway1 ${EXPRESSROUTE_GW_NAME} \\"
    log "       --express-route-circuit2 <YOUR_CIRCUIT_ID> \\"
    log "       --location ${LOCATION}"
}

# Function to validate deployment
validate_deployment() {
    log "Validating deployment..."
    
    # Check resource group exists
    if ! az group show --name "${RESOURCE_GROUP}" >/dev/null 2>&1; then
        error "Resource group ${RESOURCE_GROUP} not found"
        return 1
    fi
    
    # Check firewall status
    local firewall_state=$(az network firewall show \
        --resource-group "${RESOURCE_GROUP}" \
        --name "${FIREWALL_NAME}" \
        --query provisioningState --output tsv 2>/dev/null)
    
    if [ "$firewall_state" != "Succeeded" ]; then
        error "Azure Firewall is not in Succeeded state: ${firewall_state}"
        return 1
    fi
    
    # Check ExpressRoute Gateway status
    local gateway_state=$(az network vnet-gateway show \
        --resource-group "${RESOURCE_GROUP}" \
        --name "${EXPRESSROUTE_GW_NAME}" \
        --query provisioningState --output tsv 2>/dev/null)
    
    if [ "$gateway_state" != "Succeeded" ]; then
        error "ExpressRoute Gateway is not in Succeeded state: ${gateway_state}"
        return 1
    fi
    
    success "Deployment validation completed successfully"
    return 0
}

# Function to display deployment summary
display_deployment_summary() {
    log "Deployment Summary:"
    log "==================="
    log "Resource Group: ${RESOURCE_GROUP}"
    log "Location: ${LOCATION}"
    log "Hub Virtual Network: ${HUB_VNET_NAME}"
    log "Spoke Virtual Network: ${SPOKE_VNET_NAME}"
    log "Azure Firewall Premium: ${FIREWALL_NAME}"
    log "ExpressRoute Gateway: ${EXPRESSROUTE_GW_NAME}"
    log "Log Analytics Workspace: ${LOG_ANALYTICS_NAME}"
    log "Firewall Private IP: ${FIREWALL_PRIVATE_IP}"
    log ""
    log "Next Steps:"
    log "1. Connect your ExpressRoute circuit to the gateway"
    log "2. Configure on-premises routing to use the ExpressRoute circuit"
    log "3. Test connectivity between on-premises and Azure resources"
    log "4. Review firewall logs in the Log Analytics workspace"
    log "5. Consider implementing additional security rules based on your requirements"
    log ""
    warn "IMPORTANT: This deployment creates premium Azure resources that incur significant costs."
    warn "Monitor your Azure costs and clean up resources when testing is complete."
}

# Function to handle script errors
handle_error() {
    error "An error occurred during deployment. Check the logs above for details."
    error "You may need to run the cleanup script to remove partially created resources."
    exit 1
}

# Function to show help
show_help() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Deploy Azure Hybrid Network Security with Azure Firewall Premium and ExpressRoute"
    echo ""
    echo "Options:"
    echo "  -h, --help         Show this help message"
    echo "  --dry-run          Validate prerequisites and show what would be deployed"
    echo "  --skip-gateway     Skip ExpressRoute Gateway deployment (for testing)"
    echo ""
    echo "Example:"
    echo "  $0                 # Deploy complete solution"
    echo "  $0 --dry-run       # Validate prerequisites only"
    echo "  $0 --skip-gateway  # Deploy without ExpressRoute Gateway"
    echo ""
}

# Parse command line arguments
DRY_RUN=false
SKIP_GATEWAY=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --skip-gateway)
            SKIP_GATEWAY=true
            shift
            ;;
        *)
            error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Set error handler
trap handle_error ERR

# Main deployment function
main() {
    log "Starting Azure Hybrid Network Security deployment..."
    log "Script version: 1.0"
    log "Date: $(date)"
    log ""
    
    # Check prerequisites
    check_prerequisites
    
    # Set environment variables
    set_environment_variables
    
    if [ "$DRY_RUN" = true ]; then
        log "DRY RUN MODE: Prerequisites validated successfully"
        log "The following resources would be created:"
        display_deployment_summary
        exit 0
    fi
    
    # Create resources
    create_resource_group
    create_hub_vnet
    create_spoke_vnet
    create_log_analytics
    create_azure_firewall
    configure_firewall_diagnostics
    
    if [ "$SKIP_GATEWAY" = false ]; then
        create_expressroute_gateway
    fi
    
    create_network_security_rules
    configure_route_tables
    
    if [ "$SKIP_GATEWAY" = false ]; then
        wait_for_expressroute_gateway
    fi
    
    # Validate deployment
    if validate_deployment; then
        success "Deployment completed successfully!"
        display_deployment_summary
    else
        error "Deployment validation failed"
        exit 1
    fi
}

# Run main function
main "$@"