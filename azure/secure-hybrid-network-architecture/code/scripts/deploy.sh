#!/bin/bash

# =============================================================================
# Azure Hybrid Network Security Deployment Script
# Recipe: Secure Hybrid Network Architecture with VPN Gateway and Private Link
# Description: Deploys Azure VPN Gateway and Private Link infrastructure for secure hybrid connectivity
# =============================================================================

set -e  # Exit on any error

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1${NC}"
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        error "Azure CLI is not installed. Please install Azure CLI first."
        exit 1
    fi
    
    # Check Azure CLI version
    AZ_VERSION=$(az version --query '"azure-cli"' -o tsv)
    info "Azure CLI version: $AZ_VERSION"
    
    # Check if user is logged in
    if ! az account show &> /dev/null; then
        error "Not logged in to Azure. Please run 'az login' first."
        exit 1
    fi
    
    # Display current subscription
    CURRENT_SUB=$(az account show --query name -o tsv)
    info "Current subscription: $CURRENT_SUB"
    
    # Check if openssl is available for random generation
    if ! command -v openssl &> /dev/null; then
        error "OpenSSL is not installed. Required for generating random suffixes."
        exit 1
    fi
    
    log "Prerequisites check completed successfully"
}

# Function to set environment variables
set_environment_variables() {
    log "Setting up environment variables..."
    
    # Generate unique suffix for resource names
    export RANDOM_SUFFIX=$(openssl rand -hex 3)
    
    # Set environment variables for Azure resources
    export RESOURCE_GROUP="rg-hybrid-network-${RANDOM_SUFFIX}"
    export LOCATION="${AZURE_LOCATION:-eastus}"
    export SUBSCRIPTION_ID=$(az account show --query id --output tsv)
    
    # Set resource names with consistent naming convention
    export HUB_VNET_NAME="vnet-hub-${RANDOM_SUFFIX}"
    export SPOKE_VNET_NAME="vnet-spoke-${RANDOM_SUFFIX}"
    export VPN_GATEWAY_NAME="vpngw-${RANDOM_SUFFIX}"
    export KEY_VAULT_NAME="kv-${RANDOM_SUFFIX}"
    export STORAGE_ACCOUNT_NAME="st${RANDOM_SUFFIX}"
    export PRIVATE_DNS_ZONE="privatelink.vault.azure.net"
    
    info "Resource group: $RESOURCE_GROUP"
    info "Location: $LOCATION"
    info "Random suffix: $RANDOM_SUFFIX"
    
    log "Environment variables configured successfully"
}

# Function to create resource group
create_resource_group() {
    log "Creating resource group..."
    
    if az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        warn "Resource group $RESOURCE_GROUP already exists"
    else
        az group create \
            --name "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --tags purpose=hybrid-network environment=demo recipe=vpn-private-link \
            > /dev/null
        
        log "Resource group created: $RESOURCE_GROUP"
    fi
    
    # Verify Azure CLI authentication and subscription
    SUBSCRIPTION_NAME=$(az account show --query name --output tsv)
    info "Using subscription: $SUBSCRIPTION_NAME"
}

# Function to create hub virtual network
create_hub_vnet() {
    log "Creating hub virtual network with gateway subnet..."
    
    # Create hub virtual network for VPN Gateway
    az network vnet create \
        --resource-group "$RESOURCE_GROUP" \
        --name "$HUB_VNET_NAME" \
        --address-prefixes 10.0.0.0/16 \
        --location "$LOCATION" \
        --tags purpose=hub-network \
        > /dev/null
    
    # Create gateway subnet with /27 prefix for VPN Gateway
    az network vnet subnet create \
        --resource-group "$RESOURCE_GROUP" \
        --vnet-name "$HUB_VNET_NAME" \
        --name GatewaySubnet \
        --address-prefixes 10.0.1.0/27 \
        > /dev/null
    
    log "Hub virtual network and gateway subnet created successfully"
}

# Function to create spoke virtual network
create_spoke_vnet() {
    log "Creating spoke virtual network with application and private endpoint subnets..."
    
    # Create spoke virtual network for applications
    az network vnet create \
        --resource-group "$RESOURCE_GROUP" \
        --name "$SPOKE_VNET_NAME" \
        --address-prefixes 10.1.0.0/16 \
        --location "$LOCATION" \
        --tags purpose=spoke-network \
        > /dev/null
    
    # Create application subnet
    az network vnet subnet create \
        --resource-group "$RESOURCE_GROUP" \
        --vnet-name "$SPOKE_VNET_NAME" \
        --name ApplicationSubnet \
        --address-prefixes 10.1.1.0/24 \
        > /dev/null
    
    # Create private endpoint subnet with private endpoint policies disabled
    az network vnet subnet create \
        --resource-group "$RESOURCE_GROUP" \
        --vnet-name "$SPOKE_VNET_NAME" \
        --name PrivateEndpointSubnet \
        --address-prefixes 10.1.2.0/24 \
        --private-endpoint-network-policies Disabled \
        > /dev/null
    
    log "Spoke virtual network with application and private endpoint subnets created successfully"
}

# Function to create VNet peering
create_vnet_peering() {
    log "Creating VNet peering between hub and spoke networks..."
    
    # Create peering from hub to spoke with gateway transit
    az network vnet peering create \
        --resource-group "$RESOURCE_GROUP" \
        --name HubToSpoke \
        --vnet-name "$HUB_VNET_NAME" \
        --remote-vnet "$SPOKE_VNET_NAME" \
        --allow-gateway-transit true \
        --allow-forwarded-traffic true \
        > /dev/null
    
    # Create peering from spoke to hub with remote gateway use
    az network vnet peering create \
        --resource-group "$RESOURCE_GROUP" \
        --name SpokeToHub \
        --vnet-name "$SPOKE_VNET_NAME" \
        --remote-vnet "$HUB_VNET_NAME" \
        --use-remote-gateways true \
        --allow-forwarded-traffic true \
        > /dev/null
    
    log "VNet peering established between hub and spoke networks successfully"
}

# Function to create VPN Gateway
create_vpn_gateway() {
    log "Creating VPN Gateway (this will take 20-45 minutes)..."
    
    # Create public IP for VPN Gateway with Standard SKU
    az network public-ip create \
        --resource-group "$RESOURCE_GROUP" \
        --name "${VPN_GATEWAY_NAME}-pip" \
        --allocation-method Static \
        --sku Standard \
        --location "$LOCATION" \
        > /dev/null
    
    info "Public IP created for VPN Gateway"
    
    # Create VPN Gateway (this takes 20-45 minutes)
    warn "Creating VPN Gateway... This will take 20-45 minutes"
    az network vnet-gateway create \
        --resource-group "$RESOURCE_GROUP" \
        --name "$VPN_GATEWAY_NAME" \
        --public-ip-address "${VPN_GATEWAY_NAME}-pip" \
        --vnet "$HUB_VNET_NAME" \
        --gateway-type Vpn \
        --vpn-type RouteBased \
        --sku Basic \
        --location "$LOCATION" \
        --no-wait \
        > /dev/null
    
    log "VPN Gateway creation initiated (running in background)"
}

# Function to create Key Vault
create_key_vault() {
    log "Creating Key Vault for centralized secret management..."
    
    # Create Key Vault with RBAC authorization
    az keyvault create \
        --resource-group "$RESOURCE_GROUP" \
        --name "$KEY_VAULT_NAME" \
        --location "$LOCATION" \
        --enable-rbac-authorization true \
        --sku standard \
        --tags purpose=secret-management \
        > /dev/null
    
    # Get current user object ID for Key Vault access
    USER_OBJECT_ID=$(az ad signed-in-user show --query id --output tsv)
    
    # Assign Key Vault Administrator role to current user
    az role assignment create \
        --assignee "$USER_OBJECT_ID" \
        --role "Key Vault Administrator" \
        --scope "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.KeyVault/vaults/${KEY_VAULT_NAME}" \
        > /dev/null
    
    log "Key Vault created with RBAC authorization successfully"
}

# Function to create Storage Account
create_storage_account() {
    log "Creating Storage Account for testing Private Link..."
    
    # Create storage account for private endpoint testing
    az storage account create \
        --resource-group "$RESOURCE_GROUP" \
        --name "$STORAGE_ACCOUNT_NAME" \
        --location "$LOCATION" \
        --sku Standard_LRS \
        --kind StorageV2 \
        --allow-blob-public-access false \
        --default-action Deny \
        --tags purpose=private-endpoint-demo \
        > /dev/null
    
    log "Storage account created with public access disabled successfully"
}

# Function to create Private DNS Zones
create_private_dns_zones() {
    log "Creating private DNS zones for service resolution..."
    
    # Create private DNS zone for Key Vault
    az network private-dns zone create \
        --resource-group "$RESOURCE_GROUP" \
        --name "$PRIVATE_DNS_ZONE" \
        > /dev/null
    
    # Create additional private DNS zones for other services
    az network private-dns zone create \
        --resource-group "$RESOURCE_GROUP" \
        --name privatelink.blob.core.windows.net \
        > /dev/null
    
    # Link private DNS zones to both hub and spoke VNets
    az network private-dns link vnet create \
        --resource-group "$RESOURCE_GROUP" \
        --zone-name "$PRIVATE_DNS_ZONE" \
        --name hub-link \
        --virtual-network "$HUB_VNET_NAME" \
        --registration-enabled false \
        > /dev/null
    
    az network private-dns link vnet create \
        --resource-group "$RESOURCE_GROUP" \
        --zone-name "$PRIVATE_DNS_ZONE" \
        --name spoke-link \
        --virtual-network "$SPOKE_VNET_NAME" \
        --registration-enabled false \
        > /dev/null
    
    # Link blob storage DNS zone to VNets
    az network private-dns link vnet create \
        --resource-group "$RESOURCE_GROUP" \
        --zone-name privatelink.blob.core.windows.net \
        --name hub-blob-link \
        --virtual-network "$HUB_VNET_NAME" \
        --registration-enabled false \
        > /dev/null
    
    az network private-dns link vnet create \
        --resource-group "$RESOURCE_GROUP" \
        --zone-name privatelink.blob.core.windows.net \
        --name spoke-blob-link \
        --virtual-network "$SPOKE_VNET_NAME" \
        --registration-enabled false \
        > /dev/null
    
    log "Private DNS zones created and linked to virtual networks successfully"
}

# Function to wait for VPN Gateway and create private endpoints
create_private_endpoints() {
    log "Waiting for VPN Gateway completion and creating private endpoints..."
    
    # Check VPN Gateway status
    info "Checking VPN Gateway status..."
    VPN_STATUS=$(az network vnet-gateway show \
        --resource-group "$RESOURCE_GROUP" \
        --name "$VPN_GATEWAY_NAME" \
        --query provisioningState --output tsv 2>/dev/null || echo "Creating")
    
    if [ "$VPN_STATUS" != "Succeeded" ]; then
        warn "VPN Gateway is still being created. Status: $VPN_STATUS"
        warn "Continuing with private endpoint creation..."
    fi
    
    # Create private endpoint for Key Vault
    az network private-endpoint create \
        --resource-group "$RESOURCE_GROUP" \
        --name "pe-keyvault-${RANDOM_SUFFIX}" \
        --vnet-name "$SPOKE_VNET_NAME" \
        --subnet PrivateEndpointSubnet \
        --private-connection-resource-id "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.KeyVault/vaults/${KEY_VAULT_NAME}" \
        --group-ids vault \
        --connection-name keyvault-connection \
        --location "$LOCATION" \
        > /dev/null
    
    # Create private endpoint for Storage Account
    az network private-endpoint create \
        --resource-group "$RESOURCE_GROUP" \
        --name "pe-storage-${RANDOM_SUFFIX}" \
        --vnet-name "$SPOKE_VNET_NAME" \
        --subnet PrivateEndpointSubnet \
        --private-connection-resource-id "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.Storage/storageAccounts/${STORAGE_ACCOUNT_NAME}" \
        --group-ids blob \
        --connection-name storage-connection \
        --location "$LOCATION" \
        > /dev/null
    
    log "Private endpoints created for Key Vault and Storage Account successfully"
}

# Function to configure Private DNS Records
configure_private_dns_records() {
    log "Configuring private DNS records for service resolution..."
    
    # Get Key Vault private endpoint IP
    KV_PE_IP=$(az network private-endpoint show \
        --resource-group "$RESOURCE_GROUP" \
        --name "pe-keyvault-${RANDOM_SUFFIX}" \
        --query 'customDnsConfigs[0].ipAddresses[0]' --output tsv)
    
    # Create DNS records for Key Vault private endpoint
    az network private-dns record-set a create \
        --resource-group "$RESOURCE_GROUP" \
        --zone-name "$PRIVATE_DNS_ZONE" \
        --name "$KEY_VAULT_NAME" \
        > /dev/null
    
    az network private-dns record-set a add-record \
        --resource-group "$RESOURCE_GROUP" \
        --zone-name "$PRIVATE_DNS_ZONE" \
        --record-set-name "$KEY_VAULT_NAME" \
        --ipv4-address "$KV_PE_IP" \
        > /dev/null
    
    # Get Storage Account private endpoint IP
    STORAGE_PE_IP=$(az network private-endpoint show \
        --resource-group "$RESOURCE_GROUP" \
        --name "pe-storage-${RANDOM_SUFFIX}" \
        --query 'customDnsConfigs[0].ipAddresses[0]' --output tsv)
    
    # Create DNS records for Storage Account private endpoint
    az network private-dns record-set a create \
        --resource-group "$RESOURCE_GROUP" \
        --zone-name privatelink.blob.core.windows.net \
        --name "$STORAGE_ACCOUNT_NAME" \
        > /dev/null
    
    az network private-dns record-set a add-record \
        --resource-group "$RESOURCE_GROUP" \
        --zone-name privatelink.blob.core.windows.net \
        --record-set-name "$STORAGE_ACCOUNT_NAME" \
        --ipv4-address "$STORAGE_PE_IP" \
        > /dev/null
    
    log "Private DNS records configured for service resolution successfully"
}

# Function to create test VM
create_test_vm() {
    log "Creating test virtual machine for validation..."
    
    # Create test VM in the spoke network
    az vm create \
        --resource-group "$RESOURCE_GROUP" \
        --name "vm-test-${RANDOM_SUFFIX}" \
        --vnet-name "$SPOKE_VNET_NAME" \
        --subnet ApplicationSubnet \
        --image Ubuntu2204 \
        --admin-username azureuser \
        --generate-ssh-keys \
        --size Standard_B2s \
        --assign-identity \
        --location "$LOCATION" \
        --tags purpose=testing \
        > /dev/null
    
    # Get VM managed identity
    VM_IDENTITY=$(az vm identity show \
        --resource-group "$RESOURCE_GROUP" \
        --name "vm-test-${RANDOM_SUFFIX}" \
        --query principalId --output tsv)
    
    # Grant VM access to Key Vault
    az role assignment create \
        --assignee "$VM_IDENTITY" \
        --role "Key Vault Secrets User" \
        --scope "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.KeyVault/vaults/${KEY_VAULT_NAME}" \
        > /dev/null
    
    log "Test VM created with managed identity and Key Vault access successfully"
}

# Function to display deployment summary
display_summary() {
    log "Deployment Summary"
    echo "=================="
    echo "Resource Group: $RESOURCE_GROUP"
    echo "Location: $LOCATION"
    echo "Hub VNet: $HUB_VNET_NAME"
    echo "Spoke VNet: $SPOKE_VNET_NAME"
    echo "VPN Gateway: $VPN_GATEWAY_NAME"
    echo "Key Vault: $KEY_VAULT_NAME"
    echo "Storage Account: $STORAGE_ACCOUNT_NAME"
    echo "Test VM: vm-test-${RANDOM_SUFFIX}"
    echo ""
    
    # Get VPN Gateway public IP
    VPN_PUBLIC_IP=$(az network public-ip show \
        --resource-group "$RESOURCE_GROUP" \
        --name "${VPN_GATEWAY_NAME}-pip" \
        --query ipAddress --output tsv 2>/dev/null || echo "Creating...")
    
    echo "VPN Gateway Public IP: $VPN_PUBLIC_IP"
    echo ""
    
    # Check VPN Gateway status
    VPN_STATUS=$(az network vnet-gateway show \
        --resource-group "$RESOURCE_GROUP" \
        --name "$VPN_GATEWAY_NAME" \
        --query provisioningState --output tsv 2>/dev/null || echo "Creating")
    
    if [ "$VPN_STATUS" = "Succeeded" ]; then
        log "VPN Gateway is ready for configuration"
    else
        warn "VPN Gateway is still being created. Status: $VPN_STATUS"
        warn "You can monitor progress with: az network vnet-gateway show --resource-group $RESOURCE_GROUP --name $VPN_GATEWAY_NAME --query provisioningState"
    fi
    
    echo ""
    info "To clean up resources, run: ./destroy.sh"
    
    # Save environment variables for cleanup script
    cat > .env << EOF
export RESOURCE_GROUP="$RESOURCE_GROUP"
export LOCATION="$LOCATION"
export RANDOM_SUFFIX="$RANDOM_SUFFIX"
export HUB_VNET_NAME="$HUB_VNET_NAME"
export SPOKE_VNET_NAME="$SPOKE_VNET_NAME"
export VPN_GATEWAY_NAME="$VPN_GATEWAY_NAME"
export KEY_VAULT_NAME="$KEY_VAULT_NAME"
export STORAGE_ACCOUNT_NAME="$STORAGE_ACCOUNT_NAME"
export PRIVATE_DNS_ZONE="$PRIVATE_DNS_ZONE"
export SUBSCRIPTION_ID="$SUBSCRIPTION_ID"
EOF
    
    info "Environment variables saved to .env file for cleanup script"
}

# Main deployment function
main() {
    log "Starting Azure Hybrid Network Security deployment..."
    
    check_prerequisites
    set_environment_variables
    create_resource_group
    create_hub_vnet
    create_spoke_vnet
    create_vnet_peering
    create_vpn_gateway
    create_key_vault
    create_storage_account
    create_private_dns_zones
    create_private_endpoints
    configure_private_dns_records
    create_test_vm
    display_summary
    
    log "Azure Hybrid Network Security deployment completed successfully!"
    warn "Note: VPN Gateway creation may still be in progress. Monitor status as shown above."
}

# Handle script interruption
trap 'error "Script interrupted. Some resources may have been created."; exit 1' INT TERM

# Run main function
main "$@"