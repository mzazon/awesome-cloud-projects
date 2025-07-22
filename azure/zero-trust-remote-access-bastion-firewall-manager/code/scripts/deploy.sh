#!/bin/bash

# Azure Zero-Trust Remote Access Deployment Script
# Recipe: Zero-Trust Remote Access with Bastion and Firewall Manager
# Version: 1.0
# Description: Deploys complete zero-trust remote access solution with Azure Bastion and Firewall Manager

set -e  # Exit on any error
set -u  # Exit on undefined variables
set -o pipefail  # Exit on pipe failures

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/deploy.log"
ERROR_LOG="${SCRIPT_DIR}/deploy_errors.log"

# Initialize logging
exec 1> >(tee -a "${LOG_FILE}")
exec 2> >(tee -a "${ERROR_LOG}" >&2)

# Color codes for output
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

# Error handling function
handle_error() {
    local exit_code=$?
    local line_number=$1
    log_error "Script failed at line ${line_number} with exit code ${exit_code}"
    log_error "Check ${ERROR_LOG} for detailed error information"
    cleanup_on_error
    exit ${exit_code}
}

# Set error trap
trap 'handle_error ${LINENO}' ERR

# Cleanup function for errors
cleanup_on_error() {
    log_warning "Performing emergency cleanup due to deployment failure..."
    # Add any specific cleanup logic here if needed
}

# Default configuration values
DEFAULT_LOCATION="eastus"
DEFAULT_RESOURCE_GROUP_PREFIX="rg-zerotrust"
DEFAULT_HUB_VNET="vnet-hub"
DEFAULT_SPOKE1_VNET="vnet-spoke-prod"
DEFAULT_SPOKE2_VNET="vnet-spoke-dev"

# Function to display usage
usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -l, --location LOCATION           Azure region (default: ${DEFAULT_LOCATION})"
    echo "  -g, --resource-group PREFIX       Resource group prefix (default: ${DEFAULT_RESOURCE_GROUP_PREFIX})"
    echo "  -h, --help                        Display this help message"
    echo "  --dry-run                         Validate configuration without deploying"
    echo "  --skip-prerequisites              Skip prerequisites check"
    echo ""
    echo "Environment Variables:"
    echo "  AZURE_LOCATION                    Override default location"
    echo "  AZURE_RESOURCE_GROUP_PREFIX       Override default resource group prefix"
    echo ""
    echo "Examples:"
    echo "  $0                                Deploy with default settings"
    echo "  $0 -l westus2 -g rg-prod         Deploy to West US 2 with custom prefix"
    echo "  $0 --dry-run                      Validate without deploying"
}

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        log_error "Azure CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check Azure CLI version
    local az_version
    az_version=$(az version --query '"azure-cli"' --output tsv)
    log_info "Azure CLI version: ${az_version}"
    
    # Check if user is logged in
    if ! az account show &> /dev/null; then
        log_error "Not logged in to Azure. Please run 'az login' first."
        exit 1
    fi
    
    # Get current subscription info
    local subscription_id
    local subscription_name
    subscription_id=$(az account show --query id --output tsv)
    subscription_name=$(az account show --query name --output tsv)
    log_info "Using subscription: ${subscription_name} (${subscription_id})"
    
    # Check required permissions
    log_info "Verifying permissions..."
    if ! az group list --query "[0]" --output tsv &> /dev/null; then
        log_error "Insufficient permissions to list resource groups"
        exit 1
    fi
    
    log_success "Prerequisites check completed"
}

# Function to validate deployment parameters
validate_parameters() {
    log_info "Validating deployment parameters..."
    
    # Validate location
    if ! az account list-locations --query "[?name=='${LOCATION}']" --output tsv | grep -q "${LOCATION}"; then
        log_error "Invalid Azure region: ${LOCATION}"
        exit 1
    fi
    
    # Validate resource group name
    if [[ ${#RESOURCE_GROUP} -gt 90 ]]; then
        log_error "Resource group name too long (max 90 characters): ${RESOURCE_GROUP}"
        exit 1
    fi
    
    # Check if resource group already exists
    if az group show --name "${RESOURCE_GROUP}" &> /dev/null; then
        log_warning "Resource group ${RESOURCE_GROUP} already exists"
        read -p "Do you want to continue and use existing resource group? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Deployment cancelled by user"
            exit 0
        fi
    fi
    
    log_success "Parameter validation completed"
}

# Function to generate unique suffix
generate_unique_suffix() {
    if command -v openssl &> /dev/null; then
        RANDOM_SUFFIX=$(openssl rand -hex 3)
    else
        RANDOM_SUFFIX=$(printf "%06x" $((RANDOM * RANDOM % 16777216)))
    fi
    log_info "Generated unique suffix: ${RANDOM_SUFFIX}"
}

# Function to create resource group
create_resource_group() {
    log_info "Creating resource group: ${RESOURCE_GROUP}"
    
    az group create \
        --name "${RESOURCE_GROUP}" \
        --location "${LOCATION}" \
        --tags purpose=zero-trust-demo environment=production \
        --output none
    
    log_success "Resource group created: ${RESOURCE_GROUP}"
}

# Function to create hub virtual network
create_hub_vnet() {
    log_info "Creating hub virtual network: ${HUB_VNET}"
    
    # Create hub virtual network
    az network vnet create \
        --resource-group "${RESOURCE_GROUP}" \
        --name "${HUB_VNET}" \
        --address-prefix 10.0.0.0/16 \
        --location "${LOCATION}" \
        --output none
    
    # Create Azure Bastion subnet
    az network vnet subnet create \
        --resource-group "${RESOURCE_GROUP}" \
        --vnet-name "${HUB_VNET}" \
        --name AzureBastionSubnet \
        --address-prefix 10.0.1.0/26 \
        --output none
    
    # Create Azure Firewall subnet
    az network vnet subnet create \
        --resource-group "${RESOURCE_GROUP}" \
        --vnet-name "${HUB_VNET}" \
        --name AzureFirewallSubnet \
        --address-prefix 10.0.2.0/24 \
        --output none
    
    log_success "Hub VNet created with required subnets"
}

# Function to deploy Azure Bastion
deploy_bastion() {
    log_info "Deploying Azure Bastion..."
    
    local bastion_pip_name="pip-bastion-${RANDOM_SUFFIX}"
    local bastion_name="bastion-${RANDOM_SUFFIX}"
    
    # Create public IP for Bastion
    az network public-ip create \
        --resource-group "${RESOURCE_GROUP}" \
        --name "${bastion_pip_name}" \
        --sku Standard \
        --allocation-method Static \
        --location "${LOCATION}" \
        --output none
    
    # Deploy Azure Bastion with Standard SKU
    az network bastion create \
        --name "${bastion_name}" \
        --resource-group "${RESOURCE_GROUP}" \
        --vnet-name "${HUB_VNET}" \
        --public-ip-address "${bastion_pip_name}" \
        --location "${LOCATION}" \
        --sku Standard \
        --scale-units 2 \
        --output none
    
    # Store bastion name for later use
    echo "${bastion_name}" > "${SCRIPT_DIR}/.bastion_name"
    
    log_success "Azure Bastion deployed: ${bastion_name}"
}

# Function to create spoke virtual networks
create_spoke_vnets() {
    log_info "Creating spoke virtual networks..."
    
    # Create production spoke VNet
    az network vnet create \
        --resource-group "${RESOURCE_GROUP}" \
        --name "${SPOKE1_VNET}" \
        --address-prefix 10.1.0.0/16 \
        --location "${LOCATION}" \
        --output none
    
    # Create subnet for production workloads
    az network vnet subnet create \
        --resource-group "${RESOURCE_GROUP}" \
        --vnet-name "${SPOKE1_VNET}" \
        --name snet-prod-workload \
        --address-prefix 10.1.1.0/24 \
        --output none
    
    # Create development spoke VNet
    az network vnet create \
        --resource-group "${RESOURCE_GROUP}" \
        --name "${SPOKE2_VNET}" \
        --address-prefix 10.2.0.0/16 \
        --location "${LOCATION}" \
        --output none
    
    # Create subnet for development workloads
    az network vnet subnet create \
        --resource-group "${RESOURCE_GROUP}" \
        --vnet-name "${SPOKE2_VNET}" \
        --name snet-dev-workload \
        --address-prefix 10.2.1.0/24 \
        --output none
    
    log_success "Spoke VNets created for workload isolation"
}

# Function to configure VNet peering
configure_vnet_peering() {
    log_info "Configuring VNet peering..."
    
    # Get VNet resource IDs
    local hub_vnet_id
    local spoke1_vnet_id
    local spoke2_vnet_id
    
    hub_vnet_id=$(az network vnet show \
        --resource-group "${RESOURCE_GROUP}" \
        --name "${HUB_VNET}" \
        --query id --output tsv)
    
    spoke1_vnet_id=$(az network vnet show \
        --resource-group "${RESOURCE_GROUP}" \
        --name "${SPOKE1_VNET}" \
        --query id --output tsv)
    
    spoke2_vnet_id=$(az network vnet show \
        --resource-group "${RESOURCE_GROUP}" \
        --name "${SPOKE2_VNET}" \
        --query id --output tsv)
    
    # Create peering from hub to spoke1
    az network vnet peering create \
        --resource-group "${RESOURCE_GROUP}" \
        --name hub-to-spoke1 \
        --vnet-name "${HUB_VNET}" \
        --remote-vnet "${spoke1_vnet_id}" \
        --allow-vnet-access \
        --allow-forwarded-traffic \
        --output none
    
    # Create peering from spoke1 to hub
    az network vnet peering create \
        --resource-group "${RESOURCE_GROUP}" \
        --name spoke1-to-hub \
        --vnet-name "${SPOKE1_VNET}" \
        --remote-vnet "${hub_vnet_id}" \
        --allow-vnet-access \
        --allow-forwarded-traffic \
        --output none
    
    # Create peering from hub to spoke2
    az network vnet peering create \
        --resource-group "${RESOURCE_GROUP}" \
        --name hub-to-spoke2 \
        --vnet-name "${HUB_VNET}" \
        --remote-vnet "${spoke2_vnet_id}" \
        --allow-vnet-access \
        --allow-forwarded-traffic \
        --output none
    
    # Create peering from spoke2 to hub
    az network vnet peering create \
        --resource-group "${RESOURCE_GROUP}" \
        --name spoke2-to-hub \
        --vnet-name "${SPOKE2_VNET}" \
        --remote-vnet "${hub_vnet_id}" \
        --allow-vnet-access \
        --allow-forwarded-traffic \
        --output none
    
    log_success "VNet peering established between hub and spokes"
}

# Function to deploy Azure Firewall
deploy_firewall() {
    log_info "Deploying Azure Firewall Premium..."
    
    local firewall_pip_name="pip-firewall-${RANDOM_SUFFIX}"
    local firewall_name="fw-${RANDOM_SUFFIX}"
    
    # Create public IP for firewall
    az network public-ip create \
        --resource-group "${RESOURCE_GROUP}" \
        --name "${firewall_pip_name}" \
        --sku Standard \
        --allocation-method Static \
        --location "${LOCATION}" \
        --output none
    
    # Create Azure Firewall with Premium SKU
    az network firewall create \
        --name "${firewall_name}" \
        --resource-group "${RESOURCE_GROUP}" \
        --location "${LOCATION}" \
        --vnet-name "${HUB_VNET}" \
        --public-ip-address "${firewall_pip_name}" \
        --sku AZFW_VNet \
        --tier Premium \
        --threat-intel-mode Alert \
        --output none
    
    # Get firewall private IP for routing
    local fw_private_ip
    fw_private_ip=$(az network firewall show \
        --name "${firewall_name}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query "ipConfigurations[0].privateIpAddress" \
        --output tsv)
    
    # Store firewall info for later use
    echo "${firewall_name}" > "${SCRIPT_DIR}/.firewall_name"
    echo "${fw_private_ip}" > "${SCRIPT_DIR}/.firewall_private_ip"
    
    log_success "Azure Firewall deployed with private IP: ${fw_private_ip}"
}

# Function to create firewall policy
create_firewall_policy() {
    log_info "Creating firewall policy with zero-trust rules..."
    
    local policy_name="fwpolicy-zerotrust-${RANDOM_SUFFIX}"
    
    # Create base firewall policy
    az network firewall policy create \
        --name "${policy_name}" \
        --resource-group "${RESOURCE_GROUP}" \
        --location "${LOCATION}" \
        --sku Premium \
        --threat-intel-mode Alert \
        --intrusion-detection Alert \
        --output none
    
    # Create rule collection group
    az network firewall policy rule-collection-group create \
        --name rcg-zerotrust \
        --policy-name "${policy_name}" \
        --resource-group "${RESOURCE_GROUP}" \
        --priority 100 \
        --output none
    
    # Add application rule for Windows Update
    az network firewall policy rule-collection-group collection add-filter-collection \
        --collection-priority 100 \
        --name app-rules-windows \
        --policy-name "${policy_name}" \
        --resource-group "${RESOURCE_GROUP}" \
        --rule-collection-group-name rcg-zerotrust \
        --action Allow \
        --rule-name AllowWindowsUpdate \
        --rule-type ApplicationRule \
        --source-addresses "10.1.0.0/16" "10.2.0.0/16" \
        --protocols Http=80 Https=443 \
        --target-fqdns "*.update.microsoft.com" "*.windowsupdate.com" \
        --output none
    
    # Add network rule for Azure services
    az network firewall policy rule-collection-group collection add-filter-collection \
        --collection-priority 200 \
        --name net-rules-azure \
        --policy-name "${policy_name}" \
        --resource-group "${RESOURCE_GROUP}" \
        --rule-collection-group-name rcg-zerotrust \
        --action Allow \
        --rule-name AllowAzureServices \
        --rule-type NetworkRule \
        --source-addresses "10.1.0.0/16" "10.2.0.0/16" \
        --destination-addresses "AzureCloud.${LOCATION}" \
        --destination-ports 443 \
        --protocols TCP \
        --output none
    
    # Associate policy with firewall
    local firewall_name
    firewall_name=$(cat "${SCRIPT_DIR}/.firewall_name")
    
    az network firewall update \
        --name "${firewall_name}" \
        --resource-group "${RESOURCE_GROUP}" \
        --firewall-policy "${policy_name}" \
        --output none
    
    # Store policy name for cleanup
    echo "${policy_name}" > "${SCRIPT_DIR}/.firewall_policy_name"
    
    log_success "Firewall policy created with zero-trust rules"
}

# Function to configure network security groups
configure_network_security_groups() {
    log_info "Configuring Network Security Groups..."
    
    local nsg_name="nsg-prod-workload"
    
    # Create NSG for production workloads
    az network nsg create \
        --resource-group "${RESOURCE_GROUP}" \
        --name "${nsg_name}" \
        --location "${LOCATION}" \
        --output none
    
    # Allow Bastion RDP only from AzureBastionSubnet
    az network nsg rule create \
        --resource-group "${RESOURCE_GROUP}" \
        --nsg-name "${nsg_name}" \
        --name AllowBastionRDP \
        --priority 100 \
        --direction Inbound \
        --access Allow \
        --protocol Tcp \
        --source-address-prefixes 10.0.1.0/26 \
        --source-port-ranges '*' \
        --destination-address-prefixes '*' \
        --destination-port-ranges 3389 \
        --output none
    
    # Allow Bastion SSH only from AzureBastionSubnet
    az network nsg rule create \
        --resource-group "${RESOURCE_GROUP}" \
        --nsg-name "${nsg_name}" \
        --name AllowBastionSSH \
        --priority 110 \
        --direction Inbound \
        --access Allow \
        --protocol Tcp \
        --source-address-prefixes 10.0.1.0/26 \
        --source-port-ranges '*' \
        --destination-address-prefixes '*' \
        --destination-port-ranges 22 \
        --output none
    
    # Deny all other inbound traffic
    az network nsg rule create \
        --resource-group "${RESOURCE_GROUP}" \
        --nsg-name "${nsg_name}" \
        --name DenyAllInbound \
        --priority 4096 \
        --direction Inbound \
        --access Deny \
        --protocol '*' \
        --source-address-prefixes '*' \
        --source-port-ranges '*' \
        --destination-address-prefixes '*' \
        --destination-port-ranges '*' \
        --output none
    
    # Associate NSG with subnet
    az network vnet subnet update \
        --resource-group "${RESOURCE_GROUP}" \
        --vnet-name "${SPOKE1_VNET}" \
        --name snet-prod-workload \
        --network-security-group "${nsg_name}" \
        --output none
    
    log_success "Network security groups configured for zero-trust access"
}

# Function to implement Azure Policy
implement_azure_policy() {
    log_info "Implementing Azure Policy for compliance..."
    
    # Create policy definition for requiring NSGs on subnets
    local policy_name="require-nsg-on-subnet"
    
    cat > "${SCRIPT_DIR}/.policy_rules.json" << 'EOF'
{
  "if": {
    "allOf": [
      {
        "field": "type",
        "equals": "Microsoft.Network/virtualNetworks/subnets"
      },
      {
        "field": "Microsoft.Network/virtualNetworks/subnets/networkSecurityGroup.id",
        "exists": "false"
      },
      {
        "field": "name",
        "notIn": ["AzureBastionSubnet", "AzureFirewallSubnet"]
      }
    ]
  },
  "then": {
    "effect": "deny"
  }
}
EOF
    
    az policy definition create \
        --name "${policy_name}" \
        --resource-group "${RESOURCE_GROUP}" \
        --rules "${SCRIPT_DIR}/.policy_rules.json" \
        --description "Require NSG on all subnets except Bastion and Firewall" \
        --output none
    
    # Create policy assignment
    az policy assignment create \
        --name nsg-enforcement \
        --resource-group "${RESOURCE_GROUP}" \
        --policy "${policy_name}" \
        --display-name "Enforce NSG on Subnets" \
        --output none
    
    # Store policy info for cleanup
    echo "${policy_name}" > "${SCRIPT_DIR}/.policy_definition_name"
    
    # Cleanup temporary file
    rm -f "${SCRIPT_DIR}/.policy_rules.json"
    
    log_success "Azure Policy configured for security compliance"
}

# Function to configure route tables
configure_route_tables() {
    log_info "Configuring route tables for forced tunneling..."
    
    local route_table_name="rt-spoke-workloads"
    local fw_private_ip
    fw_private_ip=$(cat "${SCRIPT_DIR}/.firewall_private_ip")
    
    # Create route table for spoke subnets
    az network route-table create \
        --resource-group "${RESOURCE_GROUP}" \
        --name "${route_table_name}" \
        --location "${LOCATION}" \
        --output none
    
    # Add route to force traffic through firewall
    az network route-table route create \
        --resource-group "${RESOURCE_GROUP}" \
        --route-table-name "${route_table_name}" \
        --name route-to-firewall \
        --address-prefix 0.0.0.0/0 \
        --next-hop-type VirtualAppliance \
        --next-hop-ip-address "${fw_private_ip}" \
        --output none
    
    # Associate route table with production subnet
    az network vnet subnet update \
        --resource-group "${RESOURCE_GROUP}" \
        --vnet-name "${SPOKE1_VNET}" \
        --name snet-prod-workload \
        --route-table "${route_table_name}" \
        --output none
    
    log_success "Route tables configured for forced tunneling"
}

# Function to enable monitoring
enable_monitoring() {
    log_info "Enabling monitoring and threat detection..."
    
    local workspace_name="law-zerotrust-${RANDOM_SUFFIX}"
    
    # Create Log Analytics workspace
    az monitor log-analytics workspace create \
        --resource-group "${RESOURCE_GROUP}" \
        --workspace-name "${workspace_name}" \
        --location "${LOCATION}" \
        --output none
    
    # Get workspace ID
    local workspace_id
    workspace_id=$(az monitor log-analytics workspace show \
        --resource-group "${RESOURCE_GROUP}" \
        --workspace-name "${workspace_name}" \
        --query id --output tsv)
    
    # Enable diagnostic settings for Bastion
    local bastion_name
    bastion_name=$(cat "${SCRIPT_DIR}/.bastion_name")
    
    local bastion_id
    bastion_id=$(az network bastion show \
        --name "${bastion_name}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query id --output tsv)
    
    az monitor diagnostic-settings create \
        --name diag-bastion \
        --resource "${bastion_id}" \
        --workspace "${workspace_id}" \
        --logs '[{"category": "BastionAuditLogs", "enabled": true}]' \
        --metrics '[{"category": "AllMetrics", "enabled": true}]' \
        --output none
    
    # Enable diagnostic settings for Firewall
    local firewall_name
    firewall_name=$(cat "${SCRIPT_DIR}/.firewall_name")
    
    local firewall_id
    firewall_id=$(az network firewall show \
        --name "${firewall_name}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query id --output tsv)
    
    az monitor diagnostic-settings create \
        --name diag-firewall \
        --resource "${firewall_id}" \
        --workspace "${workspace_id}" \
        --logs '[
            {"category": "AzureFirewallApplicationRule", "enabled": true},
            {"category": "AzureFirewallNetworkRule", "enabled": true},
            {"category": "AzureFirewallDnsProxy", "enabled": true}
        ]' \
        --metrics '[{"category": "AllMetrics", "enabled": true}]' \
        --output none
    
    # Store workspace name for cleanup
    echo "${workspace_name}" > "${SCRIPT_DIR}/.workspace_name"
    
    log_success "Monitoring and logging enabled for all security components"
}

# Function to save deployment information
save_deployment_info() {
    log_info "Saving deployment information..."
    
    local deployment_info_file="${SCRIPT_DIR}/.deployment_info"
    
    cat > "${deployment_info_file}" << EOF
# Zero-Trust Remote Access Deployment Information
# Generated: $(date)

RESOURCE_GROUP=${RESOURCE_GROUP}
LOCATION=${LOCATION}
HUB_VNET=${HUB_VNET}
SPOKE1_VNET=${SPOKE1_VNET}
SPOKE2_VNET=${SPOKE2_VNET}
RANDOM_SUFFIX=${RANDOM_SUFFIX}

# Azure Resources
BASTION_NAME=$(cat "${SCRIPT_DIR}/.bastion_name" 2>/dev/null || echo "")
FIREWALL_NAME=$(cat "${SCRIPT_DIR}/.firewall_name" 2>/dev/null || echo "")
FIREWALL_PRIVATE_IP=$(cat "${SCRIPT_DIR}/.firewall_private_ip" 2>/dev/null || echo "")
FIREWALL_POLICY_NAME=$(cat "${SCRIPT_DIR}/.firewall_policy_name" 2>/dev/null || echo "")
POLICY_DEFINITION_NAME=$(cat "${SCRIPT_DIR}/.policy_definition_name" 2>/dev/null || echo "")
WORKSPACE_NAME=$(cat "${SCRIPT_DIR}/.workspace_name" 2>/dev/null || echo "")

# Deployment Status
DEPLOYMENT_COMPLETED=true
DEPLOYMENT_DATE=$(date -u '+%Y-%m-%d %H:%M:%S UTC')
EOF

    log_success "Deployment information saved to ${deployment_info_file}"
}

# Function to display deployment summary
display_deployment_summary() {
    echo ""
    echo "================================================================"
    echo "           ZERO-TRUST REMOTE ACCESS DEPLOYMENT COMPLETE"
    echo "================================================================"
    echo ""
    echo "Resource Group: ${RESOURCE_GROUP}"
    echo "Location: ${LOCATION}"
    echo "Unique Suffix: ${RANDOM_SUFFIX}"
    echo ""
    echo "Deployed Components:"
    echo "  ✅ Hub Virtual Network (${HUB_VNET})"
    echo "  ✅ Spoke Virtual Networks (${SPOKE1_VNET}, ${SPOKE2_VNET})"
    echo "  ✅ Azure Bastion Standard SKU"
    echo "  ✅ Azure Firewall Premium"
    echo "  ✅ Firewall Policy with Zero-Trust Rules"
    echo "  ✅ Network Security Groups"
    echo "  ✅ Azure Policy for Compliance"
    echo "  ✅ Route Tables for Forced Tunneling"
    echo "  ✅ Monitoring and Logging"
    echo ""
    echo "Next Steps:"
    echo "  1. Access Azure portal to view deployed resources"
    echo "  2. Create VMs in spoke VNets for testing"
    echo "  3. Test remote access via Bastion"
    echo "  4. Review firewall logs in Log Analytics"
    echo ""
    echo "Estimated Monthly Cost: ~$1,015 USD"
    echo "  - Azure Bastion Standard: ~$140"
    echo "  - Azure Firewall Premium: ~$875"
    echo ""
    echo "To clean up resources: ./destroy.sh"
    echo "================================================================"
}

# Main deployment function
main() {
    local dry_run=false
    local skip_prerequisites=false
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -l|--location)
                LOCATION="$2"
                shift 2
                ;;
            -g|--resource-group)
                RESOURCE_GROUP_PREFIX="$2"
                shift 2
                ;;
            --dry-run)
                dry_run=true
                shift
                ;;
            --skip-prerequisites)
                skip_prerequisites=true
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done
    
    # Set environment variables with defaults
    LOCATION="${AZURE_LOCATION:-${LOCATION:-$DEFAULT_LOCATION}}"
    RESOURCE_GROUP_PREFIX="${AZURE_RESOURCE_GROUP_PREFIX:-${RESOURCE_GROUP_PREFIX:-$DEFAULT_RESOURCE_GROUP_PREFIX}}"
    HUB_VNET="${HUB_VNET:-$DEFAULT_HUB_VNET}"
    SPOKE1_VNET="${SPOKE1_VNET:-$DEFAULT_SPOKE1_VNET}"
    SPOKE2_VNET="${SPOKE2_VNET:-$DEFAULT_SPOKE2_VNET}"
    
    # Generate unique suffix and resource group name
    generate_unique_suffix
    RESOURCE_GROUP="${RESOURCE_GROUP_PREFIX}-${RANDOM_SUFFIX}"
    
    log_info "Starting Zero-Trust Remote Access deployment..."
    log_info "Parameters: Location=${LOCATION}, ResourceGroup=${RESOURCE_GROUP}"
    
    # Check prerequisites
    if [[ "${skip_prerequisites}" != "true" ]]; then
        check_prerequisites
    fi
    
    # Validate parameters
    validate_parameters
    
    # Dry run mode
    if [[ "${dry_run}" == "true" ]]; then
        log_info "DRY RUN MODE - No resources will be created"
        log_info "Validation completed successfully"
        exit 0
    fi
    
    # Start deployment
    log_info "Beginning infrastructure deployment..."
    
    # Create foundational resources
    create_resource_group
    
    # Create networking infrastructure
    create_hub_vnet
    create_spoke_vnets
    configure_vnet_peering
    
    # Deploy security services
    deploy_bastion
    deploy_firewall
    create_firewall_policy
    
    # Configure security controls
    configure_network_security_groups
    implement_azure_policy
    configure_route_tables
    
    # Enable monitoring
    enable_monitoring
    
    # Save deployment information
    save_deployment_info
    
    # Display summary
    display_deployment_summary
    
    log_success "Zero-Trust Remote Access deployment completed successfully!"
}

# Execute main function with all arguments
main "$@"