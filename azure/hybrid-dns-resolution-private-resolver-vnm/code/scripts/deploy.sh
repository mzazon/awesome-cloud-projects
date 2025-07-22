#!/bin/bash

# Deploy Azure Hybrid DNS Resolution with DNS Private Resolver and Virtual Network Manager
# This script implements the complete infrastructure for hybrid DNS resolution

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

# Banner
echo "=========================================="
echo "Azure Hybrid DNS Resolution Deployment"
echo "DNS Private Resolver + Virtual Network Manager"
echo "=========================================="
echo

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        error "Azure CLI is not installed. Please install it first."
    fi
    
    # Check if user is logged in
    if ! az account show &> /dev/null; then
        error "Please log in to Azure using 'az login'"
    fi
    
    # Check Azure CLI version
    local az_version=$(az version --query '."azure-cli"' -o tsv)
    log "Azure CLI version: $az_version"
    
    # Verify required providers are registered
    log "Checking Azure resource providers..."
    local providers=("Microsoft.Network" "Microsoft.Storage" "Microsoft.Compute")
    for provider in "${providers[@]}"; do
        local state=$(az provider show --namespace "$provider" --query "registrationState" -o tsv 2>/dev/null || echo "NotRegistered")
        if [[ "$state" != "Registered" ]]; then
            warning "Provider $provider is not registered. Registering..."
            az provider register --namespace "$provider" --wait
        fi
    done
    
    success "Prerequisites check completed"
}

# Set environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    # Generate unique suffix for resource names
    export RANDOM_SUFFIX=$(openssl rand -hex 3)
    
    # Set core variables
    export RESOURCE_GROUP="rg-hybrid-dns-${RANDOM_SUFFIX}"
    export LOCATION="${AZURE_LOCATION:-eastus}"
    export SUBSCRIPTION_ID=$(az account show --query id --output tsv)
    
    # Set resource names with consistent naming convention
    export HUB_VNET_NAME="vnet-hub-${RANDOM_SUFFIX}"
    export SPOKE1_VNET_NAME="vnet-spoke1-${RANDOM_SUFFIX}"
    export SPOKE2_VNET_NAME="vnet-spoke2-${RANDOM_SUFFIX}"
    export DNS_RESOLVER_NAME="dns-resolver-${RANDOM_SUFFIX}"
    export NETWORK_MANAGER_NAME="avnm-${RANDOM_SUFFIX}"
    export PRIVATE_ZONE_NAME="azure.contoso.com"
    export STORAGE_ACCOUNT_NAME="st${RANDOM_SUFFIX}"
    
    # DNS configuration
    export ONPREM_DNS_IP="${ONPREM_DNS_IP:-10.100.0.2}"
    export ONPREM_DOMAIN="${ONPREM_DOMAIN:-contoso.com}"
    
    # Network CIDR blocks
    export HUB_VNET_CIDR="10.10.0.0/16"
    export SPOKE1_VNET_CIDR="10.20.0.0/16"
    export SPOKE2_VNET_CIDR="10.30.0.0/16"
    export DNS_INBOUND_SUBNET_CIDR="10.10.0.0/24"
    export DNS_OUTBOUND_SUBNET_CIDR="10.10.1.0/24"
    
    log "Environment variables configured:"
    log "  Resource Group: $RESOURCE_GROUP"
    log "  Location: $LOCATION"
    log "  Hub VNet: $HUB_VNET_NAME"
    log "  DNS Resolver: $DNS_RESOLVER_NAME"
    log "  Network Manager: $NETWORK_MANAGER_NAME"
    log "  On-premises DNS: $ONPREM_DNS_IP"
    
    success "Environment setup completed"
}

# Create resource group and hub virtual network
create_foundation() {
    log "Creating foundation resources..."
    
    # Create resource group
    log "Creating resource group: $RESOURCE_GROUP"
    az group create \
        --name "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --tags purpose=hybrid-dns environment=demo \
        --output table
    
    # Create hub virtual network with DNS resolver subnets
    log "Creating hub virtual network: $HUB_VNET_NAME"
    az network vnet create \
        --resource-group "$RESOURCE_GROUP" \
        --name "$HUB_VNET_NAME" \
        --address-prefix "$HUB_VNET_CIDR" \
        --subnet-name dns-inbound-subnet \
        --subnet-prefix "$DNS_INBOUND_SUBNET_CIDR" \
        --location "$LOCATION" \
        --output table
    
    # Create outbound subnet for DNS resolver
    log "Creating DNS outbound subnet..."
    az network vnet subnet create \
        --resource-group "$RESOURCE_GROUP" \
        --vnet-name "$HUB_VNET_NAME" \
        --name dns-outbound-subnet \
        --address-prefix "$DNS_OUTBOUND_SUBNET_CIDR" \
        --output table
    
    success "Foundation resources created"
}

# Create Azure Virtual Network Manager
create_network_manager() {
    log "Creating Azure Virtual Network Manager..."
    
    az network manager create \
        --name "$NETWORK_MANAGER_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --description "Centralized network management for hybrid DNS" \
        --network-manager-scopes subscriptions="$SUBSCRIPTION_ID" \
        --output table
    
    # Create spoke virtual networks
    log "Creating spoke virtual networks..."
    
    log "Creating spoke VNet 1: $SPOKE1_VNET_NAME"
    az network vnet create \
        --resource-group "$RESOURCE_GROUP" \
        --name "$SPOKE1_VNET_NAME" \
        --address-prefix "$SPOKE1_VNET_CIDR" \
        --subnet-name default \
        --subnet-prefix "10.20.0.0/24" \
        --location "$LOCATION" \
        --output table
    
    log "Creating spoke VNet 2: $SPOKE2_VNET_NAME"
    az network vnet create \
        --resource-group "$RESOURCE_GROUP" \
        --name "$SPOKE2_VNET_NAME" \
        --address-prefix "$SPOKE2_VNET_CIDR" \
        --subnet-name default \
        --subnet-prefix "10.30.0.0/24" \
        --location "$LOCATION" \
        --output table
    
    success "Virtual Network Manager and spoke networks created"
}

# Create private DNS zone
create_private_dns_zone() {
    log "Creating private DNS zone: $PRIVATE_ZONE_NAME"
    
    # Create private DNS zone
    az network private-dns zone create \
        --resource-group "$RESOURCE_GROUP" \
        --name "$PRIVATE_ZONE_NAME" \
        --output table
    
    # Create virtual network links to enable DNS resolution
    log "Creating virtual network links..."
    
    az network private-dns link vnet create \
        --resource-group "$RESOURCE_GROUP" \
        --zone-name "$PRIVATE_ZONE_NAME" \
        --name hub-vnet-link \
        --virtual-network "$HUB_VNET_NAME" \
        --registration-enabled false \
        --output table
    
    az network private-dns link vnet create \
        --resource-group "$RESOURCE_GROUP" \
        --zone-name "$PRIVATE_ZONE_NAME" \
        --name spoke1-vnet-link \
        --virtual-network "$SPOKE1_VNET_NAME" \
        --registration-enabled false \
        --output table
    
    az network private-dns link vnet create \
        --resource-group "$RESOURCE_GROUP" \
        --zone-name "$PRIVATE_ZONE_NAME" \
        --name spoke2-vnet-link \
        --virtual-network "$SPOKE2_VNET_NAME" \
        --registration-enabled false \
        --output table
    
    success "Private DNS zone created and linked to virtual networks"
}

# Deploy DNS Private Resolver
deploy_dns_private_resolver() {
    log "Deploying Azure DNS Private Resolver..."
    
    # Create DNS Private Resolver
    log "Creating DNS Private Resolver: $DNS_RESOLVER_NAME"
    az dns-resolver create \
        --name "$DNS_RESOLVER_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --virtual-network "$HUB_VNET_NAME" \
        --output table
    
    # Wait for resolver to be ready
    log "Waiting for DNS Private Resolver to be ready..."
    sleep 30
    
    # Create inbound endpoint for on-premises to Azure queries
    log "Creating inbound endpoint..."
    az dns-resolver inbound-endpoint create \
        --dns-resolver-name "$DNS_RESOLVER_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --name inbound-endpoint \
        --location "$LOCATION" \
        --subnet "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Network/virtualNetworks/$HUB_VNET_NAME/subnets/dns-inbound-subnet" \
        --output table
    
    # Create outbound endpoint for Azure to on-premises queries
    log "Creating outbound endpoint..."
    az dns-resolver outbound-endpoint create \
        --dns-resolver-name "$DNS_RESOLVER_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --name outbound-endpoint \
        --location "$LOCATION" \
        --subnet "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Network/virtualNetworks/$HUB_VNET_NAME/subnets/dns-outbound-subnet" \
        --output table
    
    success "DNS Private Resolver deployed with inbound and outbound endpoints"
}

# Configure DNS forwarding ruleset
configure_dns_forwarding() {
    log "Configuring DNS forwarding ruleset..."
    
    # Create DNS forwarding ruleset
    log "Creating DNS forwarding ruleset..."
    az dns-resolver forwarding-ruleset create \
        --name "onprem-forwarding-ruleset" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --outbound-endpoints "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Network/dnsResolvers/$DNS_RESOLVER_NAME/outboundEndpoints/outbound-endpoint" \
        --output table
    
    # Create forwarding rule for on-premises domain
    log "Creating forwarding rule for domain: $ONPREM_DOMAIN"
    az dns-resolver forwarding-rule create \
        --name "contoso-com-rule" \
        --resource-group "$RESOURCE_GROUP" \
        --ruleset-name "onprem-forwarding-ruleset" \
        --domain-name "$ONPREM_DOMAIN" \
        --forwarding-rule-state "Enabled" \
        --target-dns-servers "[{\"ipAddress\":\"$ONPREM_DNS_IP\",\"port\":53}]" \
        --output table
    
    # Link the ruleset to virtual networks
    log "Linking ruleset to virtual networks..."
    
    az dns-resolver forwarding-ruleset virtual-network-link create \
        --name "hub-vnet-link" \
        --resource-group "$RESOURCE_GROUP" \
        --ruleset-name "onprem-forwarding-ruleset" \
        --virtual-network "$HUB_VNET_NAME" \
        --output table
    
    az dns-resolver forwarding-ruleset virtual-network-link create \
        --name "spoke1-vnet-link" \
        --resource-group "$RESOURCE_GROUP" \
        --ruleset-name "onprem-forwarding-ruleset" \
        --virtual-network "$SPOKE1_VNET_NAME" \
        --output table
    
    success "DNS forwarding ruleset configured for on-premises resolution"
}

# Create network groups and connectivity configuration
configure_network_connectivity() {
    log "Configuring network groups and connectivity..."
    
    # Create network group for hub-spoke topology
    log "Creating network group..."
    az network manager group create \
        --name "hub-spoke-group" \
        --resource-group "$RESOURCE_GROUP" \
        --network-manager-name "$NETWORK_MANAGER_NAME" \
        --description "Network group for hub-spoke DNS topology" \
        --output table
    
    # Add virtual networks to the network group
    log "Adding virtual networks to network group..."
    
    az network manager group static-member create \
        --resource-group "$RESOURCE_GROUP" \
        --network-manager-name "$NETWORK_MANAGER_NAME" \
        --network-group-name "hub-spoke-group" \
        --name "hub-member" \
        --resource-id "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Network/virtualNetworks/$HUB_VNET_NAME" \
        --output table
    
    az network manager group static-member create \
        --resource-group "$RESOURCE_GROUP" \
        --network-manager-name "$NETWORK_MANAGER_NAME" \
        --network-group-name "hub-spoke-group" \
        --name "spoke1-member" \
        --resource-id "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Network/virtualNetworks/$SPOKE1_VNET_NAME" \
        --output table
    
    az network manager group static-member create \
        --resource-group "$RESOURCE_GROUP" \
        --network-manager-name "$NETWORK_MANAGER_NAME" \
        --network-group-name "hub-spoke-group" \
        --name "spoke2-member" \
        --resource-id "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Network/virtualNetworks/$SPOKE2_VNET_NAME" \
        --output table
    
    # Create connectivity configuration
    log "Creating hub-spoke connectivity configuration..."
    az network manager connect-config create \
        --name "hub-spoke-connectivity" \
        --resource-group "$RESOURCE_GROUP" \
        --network-manager-name "$NETWORK_MANAGER_NAME" \
        --description "Hub-spoke connectivity for DNS resolution" \
        --applies-to-groups "[{\"networkGroupId\":\"/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Network/networkManagers/$NETWORK_MANAGER_NAME/networkGroups/hub-spoke-group\",\"useHubGateway\":\"False\",\"isGlobal\":\"False\",\"groupConnectivity\":\"None\"}]" \
        --connectivity-topology "HubAndSpoke" \
        --hub-resource-id "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Network/virtualNetworks/$HUB_VNET_NAME" \
        --output table
    
    # Deploy the connectivity configuration
    log "Deploying connectivity configuration..."
    az network manager post-commit \
        --resource-group "$RESOURCE_GROUP" \
        --network-manager-name "$NETWORK_MANAGER_NAME" \
        --commit-type "Connectivity" \
        --configuration-ids "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Network/networkManagers/$NETWORK_MANAGER_NAME/connectivityConfigurations/hub-spoke-connectivity" \
        --target-locations "$LOCATION" \
        --output table
    
    success "Network connectivity configuration deployed"
}

# Create Azure resources with private endpoints
create_azure_resources() {
    log "Creating Azure resources with private endpoints..."
    
    # Create storage account for private endpoint demonstration
    log "Creating storage account: $STORAGE_ACCOUNT_NAME"
    az storage account create \
        --name "$STORAGE_ACCOUNT_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --sku Standard_LRS \
        --kind StorageV2 \
        --public-network-access Disabled \
        --output table
    
    # Create private DNS zone for storage
    log "Creating private DNS zone for storage..."
    az network private-dns zone create \
        --resource-group "$RESOURCE_GROUP" \
        --name "privatelink.blob.core.windows.net" \
        --output table
    
    # Link storage private DNS zone to virtual networks
    az network private-dns link vnet create \
        --resource-group "$RESOURCE_GROUP" \
        --zone-name "privatelink.blob.core.windows.net" \
        --name hub-storage-link \
        --virtual-network "$HUB_VNET_NAME" \
        --registration-enabled false \
        --output table
    
    # Create private endpoint for storage account
    log "Creating private endpoint for storage account..."
    az network private-endpoint create \
        --name "pe-storage-$RANDOM_SUFFIX" \
        --resource-group "$RESOURCE_GROUP" \
        --vnet-name "$SPOKE1_VNET_NAME" \
        --subnet default \
        --connection-name "storage-connection" \
        --private-connection-resource-id "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Storage/storageAccounts/$STORAGE_ACCOUNT_NAME" \
        --group-id blob \
        --output table
    
    # Create private DNS zone group for automatic registration
    log "Configuring private DNS zone group..."
    az network private-endpoint dns-zone-group create \
        --resource-group "$RESOURCE_GROUP" \
        --endpoint-name "pe-storage-$RANDOM_SUFFIX" \
        --name "storage-zone-group" \
        --private-dns-zone "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Network/privateDnsZones/privatelink.blob.core.windows.net" \
        --zone-name privatelink.blob.core.windows.net \
        --output table
    
    success "Azure resources with private endpoints created"
}

# Add test DNS records
add_test_dns_records() {
    log "Adding test DNS records..."
    
    # Add test A record to private DNS zone
    log "Creating test-vm DNS record..."
    az network private-dns record-set a create \
        --resource-group "$RESOURCE_GROUP" \
        --zone-name "$PRIVATE_ZONE_NAME" \
        --name test-vm \
        --output table
    
    az network private-dns record-set a add-record \
        --resource-group "$RESOURCE_GROUP" \
        --zone-name "$PRIVATE_ZONE_NAME" \
        --record-set-name test-vm \
        --ipv4-address 10.20.0.100 \
        --output table
    
    # Add additional test record
    log "Creating app-server DNS record..."
    az network private-dns record-set a create \
        --resource-group "$RESOURCE_GROUP" \
        --zone-name "$PRIVATE_ZONE_NAME" \
        --name app-server \
        --output table
    
    az network private-dns record-set a add-record \
        --resource-group "$RESOURCE_GROUP" \
        --zone-name "$PRIVATE_ZONE_NAME" \
        --record-set-name app-server \
        --ipv4-address 10.30.0.50 \
        --output table
    
    success "Test DNS records added to private DNS zone"
}

# Perform validation tests
validate_deployment() {
    log "Performing validation tests..."
    
    # Check DNS Private Resolver status
    log "Checking DNS Private Resolver status..."
    local resolver_state=$(az dns-resolver show \
        --name "$DNS_RESOLVER_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --query "provisioningState" \
        --output tsv)
    
    if [[ "$resolver_state" == "Succeeded" ]]; then
        success "DNS Private Resolver is in Succeeded state"
    else
        warning "DNS Private Resolver state: $resolver_state"
    fi
    
    # Get inbound endpoint IP address
    log "Retrieving inbound endpoint IP address..."
    local inbound_ip=$(az dns-resolver inbound-endpoint show \
        --dns-resolver-name "$DNS_RESOLVER_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --name inbound-endpoint \
        --query "ipConfigurations[0].privateIpAddress" \
        --output tsv 2>/dev/null || echo "Not available")
    
    if [[ "$inbound_ip" != "Not available" ]]; then
        success "Inbound endpoint IP: $inbound_ip"
    else
        warning "Could not retrieve inbound endpoint IP"
    fi
    
    # Check Virtual Network Manager deployment status
    log "Checking Virtual Network Manager connectivity configurations..."
    az network manager list-active-connectivity-config \
        --resource-group "$RESOURCE_GROUP" \
        --network-manager-name "$NETWORK_MANAGER_NAME" \
        --regions "$LOCATION" \
        --output table || warning "Could not retrieve active connectivity configurations"
    
    success "Validation completed"
}

# Save deployment information
save_deployment_info() {
    local info_file="deployment-info-$RANDOM_SUFFIX.txt"
    
    log "Saving deployment information to $info_file..."
    
    cat > "$info_file" << EOF
Azure Hybrid DNS Resolution Deployment Information
=================================================

Deployment Date: $(date)
Resource Group: $RESOURCE_GROUP
Location: $LOCATION
Subscription ID: $SUBSCRIPTION_ID

Resource Names:
- Hub VNet: $HUB_VNET_NAME
- Spoke VNet 1: $SPOKE1_VNET_NAME
- Spoke VNet 2: $SPOKE2_VNET_NAME
- DNS Private Resolver: $DNS_RESOLVER_NAME
- Virtual Network Manager: $NETWORK_MANAGER_NAME
- Storage Account: $STORAGE_ACCOUNT_NAME

Network Configuration:
- Hub VNet CIDR: $HUB_VNET_CIDR
- Spoke 1 VNet CIDR: $SPOKE1_VNET_CIDR
- Spoke 2 VNet CIDR: $SPOKE2_VNET_CIDR
- DNS Inbound Subnet: $DNS_INBOUND_SUBNET_CIDR
- DNS Outbound Subnet: $DNS_OUTBOUND_SUBNET_CIDR

DNS Configuration:
- Private DNS Zone: $PRIVATE_ZONE_NAME
- On-premises DNS: $ONPREM_DNS_IP
- On-premises Domain: $ONPREM_DOMAIN

Test Commands:
- Check resolver status: az dns-resolver show --name $DNS_RESOLVER_NAME --resource-group $RESOURCE_GROUP
- Get inbound IP: az dns-resolver inbound-endpoint show --dns-resolver-name $DNS_RESOLVER_NAME --resource-group $RESOURCE_GROUP --name inbound-endpoint --query "ipConfigurations[0].privateIpAddress" -o tsv

Cleanup:
- Run ./destroy.sh to remove all resources
- Or delete the resource group: az group delete --name $RESOURCE_GROUP --yes

EOF

    success "Deployment information saved to $info_file"
}

# Main execution
main() {
    log "Starting Azure Hybrid DNS Resolution deployment..."
    
    check_prerequisites
    setup_environment
    create_foundation
    create_network_manager
    create_private_dns_zone
    deploy_dns_private_resolver
    configure_dns_forwarding
    configure_network_connectivity
    create_azure_resources
    add_test_dns_records
    validate_deployment
    save_deployment_info
    
    echo
    echo "=========================================="
    success "Azure Hybrid DNS Resolution deployment completed successfully!"
    echo "=========================================="
    echo
    echo "Key Information:"
    echo "- Resource Group: $RESOURCE_GROUP"
    echo "- DNS Private Resolver: $DNS_RESOLVER_NAME"
    echo "- Private DNS Zone: $PRIVATE_ZONE_NAME"
    echo "- Virtual Network Manager: $NETWORK_MANAGER_NAME"
    echo
    echo "Next Steps:"
    echo "1. Configure your on-premises DNS server to forward queries to the inbound endpoint"
    echo "2. Test DNS resolution from on-premises to Azure private zone"
    echo "3. Test DNS resolution from Azure VMs to on-premises domain"
    echo "4. Monitor DNS query patterns using Azure Monitor"
    echo
    echo "For cleanup, run: ./destroy.sh"
    echo
}

# Run main function
main "$@"