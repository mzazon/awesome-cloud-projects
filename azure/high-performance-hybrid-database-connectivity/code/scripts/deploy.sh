#!/bin/bash

# Azure ExpressRoute and Application Gateway Deployment Script
# Recipe: High-Performance Hybrid Database Connectivity with ExpressRoute
# Version: 1.0
# Last Updated: 2025-07-12

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING:${NC} $1"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1"
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO:${NC} $1"
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
    az_version=$(az version --query '"azure-cli"' -o tsv)
    log "Azure CLI version: $az_version"
    
    # Check if user is logged in
    if ! az account show &> /dev/null; then
        error "Not logged in to Azure. Please run 'az login' first."
        exit 1
    fi
    
    # Check if subscription is set
    subscription_id=$(az account show --query id -o tsv)
    subscription_name=$(az account show --query name -o tsv)
    log "Using subscription: $subscription_name ($subscription_id)"
    
    # Check if required providers are registered
    log "Checking required Azure resource providers..."
    
    providers=("Microsoft.Network" "Microsoft.DBforPostgreSQL" "Microsoft.Compute")
    for provider in "${providers[@]}"; do
        status=$(az provider show --namespace "$provider" --query "registrationState" -o tsv)
        if [ "$status" != "Registered" ]; then
            warn "Provider $provider is not registered. Registering now..."
            az provider register --namespace "$provider"
        else
            log "Provider $provider is registered"
        fi
    done
    
    # Check if openssl is available for random string generation
    if ! command -v openssl &> /dev/null; then
        error "OpenSSL is not installed. Required for generating random suffixes."
        exit 1
    fi
    
    log "Prerequisites check completed successfully"
}

# Function to set environment variables
set_environment_variables() {
    log "Setting up environment variables..."
    
    # Core resource naming
    export RESOURCE_GROUP="rg-hybrid-db-connectivity"
    export LOCATION="eastus"
    export SUBSCRIPTION_ID=$(az account show --query id --output tsv)
    
    # Generate unique suffix for resource names
    RANDOM_SUFFIX=$(openssl rand -hex 3)
    export VNET_NAME="vnet-hub-${RANDOM_SUFFIX}"
    export APPGW_NAME="appgw-db-${RANDOM_SUFFIX}"
    export POSTGRES_NAME="postgres-hybrid-${RANDOM_SUFFIX}"
    export ERGW_NAME="ergw-hub-${RANDOM_SUFFIX}"
    
    log "Environment variables set:"
    log "  Resource Group: $RESOURCE_GROUP"
    log "  Location: $LOCATION"
    log "  VNet Name: $VNET_NAME"
    log "  Application Gateway: $APPGW_NAME"
    log "  PostgreSQL Server: $POSTGRES_NAME"
    log "  ExpressRoute Gateway: $ERGW_NAME"
    log "  Random Suffix: $RANDOM_SUFFIX"
}

# Function to create resource group and networking
create_foundation_infrastructure() {
    log "Creating foundation infrastructure..."
    
    # Create resource group
    info "Creating resource group: $RESOURCE_GROUP"
    az group create \
        --name "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --tags purpose=hybrid-database-connectivity environment=production
    
    # Create hub virtual network with appropriate subnets
    info "Creating virtual network: $VNET_NAME"
    az network vnet create \
        --name "$VNET_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --address-prefixes 10.1.0.0/16 \
        --subnet-name GatewaySubnet \
        --subnet-prefixes 10.1.1.0/27
    
    # Create Application Gateway subnet
    info "Creating Application Gateway subnet"
    az network vnet subnet create \
        --name ApplicationGatewaySubnet \
        --resource-group "$RESOURCE_GROUP" \
        --vnet-name "$VNET_NAME" \
        --address-prefixes 10.1.2.0/24
    
    # Create database subnet with service endpoints
    info "Creating database subnet"
    az network vnet subnet create \
        --name DatabaseSubnet \
        --resource-group "$RESOURCE_GROUP" \
        --vnet-name "$VNET_NAME" \
        --address-prefixes 10.1.3.0/24 \
        --service-endpoints Microsoft.Storage
    
    # Create management subnet for bastion and jump box
    info "Creating management subnet"
    az network vnet subnet create \
        --name ManagementSubnet \
        --resource-group "$RESOURCE_GROUP" \
        --vnet-name "$VNET_NAME" \
        --address-prefixes 10.1.4.0/24
    
    log "Foundation infrastructure created successfully"
}

# Function to create ExpressRoute Gateway
create_expressroute_gateway() {
    log "Creating ExpressRoute Gateway..."
    
    # Create public IP for ExpressRoute Gateway
    info "Creating public IP for ExpressRoute Gateway"
    az network public-ip create \
        --name "pip-$ERGW_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --allocation-method Static \
        --sku Standard \
        --zone 1 2 3
    
    # Create ExpressRoute Gateway (this takes 15-20 minutes)
    info "Creating ExpressRoute Gateway (this may take 15-20 minutes)..."
    az network vnet-gateway create \
        --name "$ERGW_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --vnet "$VNET_NAME" \
        --gateway-type ExpressRoute \
        --sku Standard \
        --public-ip-addresses "pip-$ERGW_NAME" \
        --no-wait
    
    log "ExpressRoute Gateway deployment initiated"
}

# Function to deploy PostgreSQL Flexible Server
deploy_postgresql_server() {
    log "Deploying PostgreSQL Flexible Server..."
    
    info "Creating PostgreSQL Flexible Server with private access"
    az postgres flexible-server create \
        --name "$POSTGRES_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --admin-user dbadmin \
        --admin-password 'ComplexPassword123!' \
        --sku-name Standard_D2s_v3 \
        --tier GeneralPurpose \
        --version 14 \
        --storage-size 128 \
        --vnet "$VNET_NAME" \
        --subnet DatabaseSubnet \
        --private-dns-zone "$POSTGRES_NAME.private.postgres.database.azure.com" \
        --yes
    
    # Configure database parameters for optimal performance
    info "Configuring PostgreSQL parameters"
    az postgres flexible-server parameter set \
        --name "$POSTGRES_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --parameter-name max_connections \
        --value 200
    
    az postgres flexible-server parameter set \
        --name "$POSTGRES_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --parameter-name shared_preload_libraries \
        --value 'pg_stat_statements'
    
    log "PostgreSQL Flexible Server deployed successfully"
}

# Function to create Application Gateway
create_application_gateway() {
    log "Creating Application Gateway..."
    
    # Create public IP for Application Gateway
    info "Creating public IP for Application Gateway"
    az network public-ip create \
        --name "pip-$APPGW_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --allocation-method Static \
        --sku Standard \
        --zone 1 2 3
    
    # Create Application Gateway with WAF enabled
    info "Creating Application Gateway with WAF"
    az network application-gateway create \
        --name "$APPGW_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --vnet-name "$VNET_NAME" \
        --subnet ApplicationGatewaySubnet \
        --public-ip-address "pip-$APPGW_NAME" \
        --sku WAF_v2 \
        --capacity 2 \
        --http-settings-cookie-based-affinity Enabled \
        --frontend-port 443 \
        --http-settings-port 5432 \
        --http-settings-protocol Https \
        --priority 1000
    
    # Get PostgreSQL FQDN for backend pool
    POSTGRES_FQDN=$(az postgres flexible-server show \
        --name "$POSTGRES_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --query "fullyQualifiedDomainName" \
        --output tsv)
    
    # Configure backend address pool for PostgreSQL
    info "Configuring backend address pool"
    az network application-gateway address-pool create \
        --resource-group "$RESOURCE_GROUP" \
        --gateway-name "$APPGW_NAME" \
        --name PostgreSQLBackendPool \
        --servers "$POSTGRES_FQDN"
    
    log "Application Gateway created successfully"
}

# Function to wait for ExpressRoute Gateway and configure connection
configure_expressroute_connection() {
    log "Configuring ExpressRoute connection..."
    
    # Wait for ExpressRoute Gateway to complete deployment
    info "Waiting for ExpressRoute Gateway deployment to complete..."
    az network vnet-gateway wait \
        --name "$ERGW_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --created
    
    # Note: This is a placeholder for ExpressRoute circuit connection
    # In a real scenario, you would replace CIRCUIT_ID with your actual ExpressRoute circuit
    warn "ExpressRoute circuit connection configuration required:"
    warn "Please update the script with your actual ExpressRoute circuit ID"
    warn "Example command:"
    warn "az network vpn-connection create \\"
    warn "    --name connection-$ERGW_NAME \\"
    warn "    --resource-group $RESOURCE_GROUP \\"
    warn "    --location $LOCATION \\"
    warn "    --vnet-gateway1 $ERGW_NAME \\"
    warn "    --express-route-circuit2 /subscriptions/YOUR_SUBSCRIPTION/resourceGroups/YOUR_RG/providers/Microsoft.Network/expressRouteCircuits/YOUR_CIRCUIT \\"
    warn "    --connection-type ExpressRoute"
    
    log "ExpressRoute Gateway ready for circuit connection"
}

# Function to configure private DNS
configure_private_dns() {
    log "Configuring private DNS resolution..."
    
    # Create private DNS zone for PostgreSQL
    info "Creating private DNS zone"
    az network private-dns zone create \
        --name "$POSTGRES_NAME.private.postgres.database.azure.com" \
        --resource-group "$RESOURCE_GROUP"
    
    # Link private DNS zone to virtual network
    info "Linking private DNS zone to virtual network"
    az network private-dns link vnet create \
        --name "link-$VNET_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --zone-name "$POSTGRES_NAME.private.postgres.database.azure.com" \
        --virtual-network "$VNET_NAME" \
        --registration-enabled false
    
    # Create A record for PostgreSQL server
    info "Creating DNS A record for PostgreSQL server"
    az network private-dns record-set a create \
        --name "$POSTGRES_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --zone-name "$POSTGRES_NAME.private.postgres.database.azure.com"
    
    log "Private DNS resolution configured successfully"
}

# Function to configure Application Gateway advanced settings
configure_application_gateway_advanced() {
    log "Configuring Application Gateway advanced settings..."
    
    # Create custom health probe for PostgreSQL
    info "Creating custom health probe"
    az network application-gateway probe create \
        --resource-group "$RESOURCE_GROUP" \
        --gateway-name "$APPGW_NAME" \
        --name PostgreSQLHealthProbe \
        --protocol Https \
        --port 5432 \
        --path / \
        --interval 30 \
        --timeout 30 \
        --threshold 3
    
    # Configure SSL policy for enhanced security
    info "Configuring SSL policy"
    az network application-gateway ssl-policy set \
        --resource-group "$RESOURCE_GROUP" \
        --gateway-name "$APPGW_NAME" \
        --policy-type Custom \
        --cipher-suites TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384 \
        --min-protocol-version TLSv1_2
    
    # Configure WAF policy for database protection
    info "Creating WAF policy"
    az network application-gateway waf-policy create \
        --name waf-policy-db \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --type OWASP \
        --version 3.2
    
    log "Application Gateway advanced settings configured successfully"
}

# Function to implement network security
implement_network_security() {
    log "Implementing network security groups and route tables..."
    
    # Create NSG for database subnet
    info "Creating network security group for database subnet"
    az network nsg create \
        --name nsg-database-subnet \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION"
    
    # Configure NSG rules for database access
    info "Configuring NSG rules"
    az network nsg rule create \
        --name AllowApplicationGatewayToPostgreSQL \
        --resource-group "$RESOURCE_GROUP" \
        --nsg-name nsg-database-subnet \
        --priority 1000 \
        --source-address-prefixes 10.1.2.0/24 \
        --destination-port-ranges 5432 \
        --access Allow \
        --protocol Tcp \
        --direction Inbound
    
    az network nsg rule create \
        --name AllowExpressRouteToPostgreSQL \
        --resource-group "$RESOURCE_GROUP" \
        --nsg-name nsg-database-subnet \
        --priority 1100 \
        --source-address-prefixes 10.0.0.0/8 \
        --destination-port-ranges 5432 \
        --access Allow \
        --protocol Tcp \
        --direction Inbound
    
    # Associate NSG with database subnet
    info "Associating NSG with database subnet"
    az network vnet subnet update \
        --name DatabaseSubnet \
        --resource-group "$RESOURCE_GROUP" \
        --vnet-name "$VNET_NAME" \
        --network-security-group nsg-database-subnet
    
    # Create route table for database subnet
    info "Creating route table"
    az network route-table create \
        --name rt-database-subnet \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION"
    
    # Create route for on-premises traffic via ExpressRoute
    info "Creating route for on-premises traffic"
    az network route-table route create \
        --name route-onpremises \
        --resource-group "$RESOURCE_GROUP" \
        --route-table-name rt-database-subnet \
        --address-prefix 10.0.0.0/8 \
        --next-hop-type VnetLocal
    
    log "Network security implementation completed"
}

# Function to validate deployment
validate_deployment() {
    log "Validating deployment..."
    
    # Check ExpressRoute Gateway status
    info "Checking ExpressRoute Gateway status"
    ergw_status=$(az network vnet-gateway show \
        --name "$ERGW_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --query "provisioningState" \
        --output tsv)
    log "ExpressRoute Gateway status: $ergw_status"
    
    # Check PostgreSQL server status
    info "Checking PostgreSQL server status"
    postgres_status=$(az postgres flexible-server show \
        --name "$POSTGRES_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --query "state" \
        --output tsv)
    log "PostgreSQL server status: $postgres_status"
    
    # Check Application Gateway status
    info "Checking Application Gateway status"
    appgw_status=$(az network application-gateway show \
        --name "$APPGW_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --query "operationalState" \
        --output tsv)
    log "Application Gateway status: $appgw_status"
    
    log "Deployment validation completed"
}

# Function to display deployment summary
display_summary() {
    log "=== DEPLOYMENT SUMMARY ==="
    log "Resource Group: $RESOURCE_GROUP"
    log "Location: $LOCATION"
    log "Virtual Network: $VNET_NAME"
    log "ExpressRoute Gateway: $ERGW_NAME"
    log "PostgreSQL Server: $POSTGRES_NAME"
    log "Application Gateway: $APPGW_NAME"
    log ""
    log "Next Steps:"
    log "1. Configure your ExpressRoute circuit connection"
    log "2. Update DNS settings for your on-premises applications"
    log "3. Test database connectivity through the Application Gateway"
    log "4. Configure monitoring and alerting"
    log ""
    warn "IMPORTANT: Remember to configure your ExpressRoute circuit connection!"
    warn "Estimated monthly cost: $800-1200 (depending on usage and ExpressRoute circuit)"
    log "=== DEPLOYMENT COMPLETED ==="
}

# Main deployment function
main() {
    log "Starting Azure ExpressRoute and Application Gateway deployment..."
    
    # Check prerequisites
    check_prerequisites
    
    # Set environment variables
    set_environment_variables
    
    # Create foundation infrastructure
    create_foundation_infrastructure
    
    # Create ExpressRoute Gateway
    create_expressroute_gateway
    
    # Deploy PostgreSQL server
    deploy_postgresql_server
    
    # Create Application Gateway
    create_application_gateway
    
    # Configure ExpressRoute connection (placeholder)
    configure_expressroute_connection
    
    # Configure private DNS
    configure_private_dns
    
    # Configure Application Gateway advanced settings
    configure_application_gateway_advanced
    
    # Implement network security
    implement_network_security
    
    # Validate deployment
    validate_deployment
    
    # Display summary
    display_summary
}

# Handle script interruption
trap 'error "Deployment interrupted! Run destroy.sh to clean up partial deployment."; exit 1' INT TERM

# Execute main function
main "$@"