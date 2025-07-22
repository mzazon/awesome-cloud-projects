#!/bin/bash
# Deploy script for Global Traffic Distribution with Traffic Manager and Application Gateway
# This script deploys the complete infrastructure across multiple Azure regions

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING:${NC} $1"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1"
}

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        error "Azure CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if user is logged in
    if ! az account show &> /dev/null; then
        error "Not logged in to Azure. Please run 'az login' first."
        exit 1
    fi
    
    # Check if subscription is set
    SUBSCRIPTION_ID=$(az account show --query id -o tsv)
    if [ -z "$SUBSCRIPTION_ID" ]; then
        error "No Azure subscription selected. Please set a subscription."
        exit 1
    fi
    
    log "Prerequisites check passed"
    log "Using subscription: $SUBSCRIPTION_ID"
}

# Set environment variables
set_environment() {
    log "Setting environment variables..."
    
    # Resource group names
    export RESOURCE_GROUP_PRIMARY="rg-global-traffic-primary"
    export RESOURCE_GROUP_SECONDARY="rg-global-traffic-secondary"
    export RESOURCE_GROUP_TERTIARY="rg-global-traffic-tertiary"
    
    # Azure regions
    export LOCATION_PRIMARY="eastus"
    export LOCATION_SECONDARY="uksouth"
    export LOCATION_TERTIARY="southeastasia"
    
    # Generate unique suffix for globally unique resources
    RANDOM_SUFFIX=$(openssl rand -hex 3)
    export RANDOM_SUFFIX
    
    # Set Traffic Manager and Application Gateway names
    export TRAFFIC_MANAGER_PROFILE="tm-global-app-${RANDOM_SUFFIX}"
    export APP_GATEWAY_PRIMARY="agw-primary-${RANDOM_SUFFIX}"
    export APP_GATEWAY_SECONDARY="agw-secondary-${RANDOM_SUFFIX}"
    export APP_GATEWAY_TERTIARY="agw-tertiary-${RANDOM_SUFFIX}"
    
    log "Environment variables set with random suffix: $RANDOM_SUFFIX"
    log "Traffic Manager Profile: $TRAFFIC_MANAGER_PROFILE"
}

# Create resource groups
create_resource_groups() {
    log "Creating resource groups in all regions..."
    
    # Create primary resource group
    az group create \
        --name ${RESOURCE_GROUP_PRIMARY} \
        --location ${LOCATION_PRIMARY} \
        --tags environment=production purpose=global-traffic-distribution
    
    # Create secondary resource group
    az group create \
        --name ${RESOURCE_GROUP_SECONDARY} \
        --location ${LOCATION_SECONDARY} \
        --tags environment=production purpose=global-traffic-distribution
    
    # Create tertiary resource group
    az group create \
        --name ${RESOURCE_GROUP_TERTIARY} \
        --location ${LOCATION_TERTIARY} \
        --tags environment=production purpose=global-traffic-distribution
    
    log "Resource groups created successfully"
}

# Create virtual networks
create_virtual_networks() {
    log "Creating virtual networks and subnets in all regions..."
    
    # Create virtual network in primary region
    az network vnet create \
        --resource-group ${RESOURCE_GROUP_PRIMARY} \
        --name vnet-primary \
        --address-prefix 10.1.0.0/16 \
        --subnet-name subnet-appgw \
        --subnet-prefix 10.1.1.0/24 \
        --location ${LOCATION_PRIMARY}
    
    # Create backend subnet for primary region
    az network vnet subnet create \
        --resource-group ${RESOURCE_GROUP_PRIMARY} \
        --vnet-name vnet-primary \
        --name subnet-backend \
        --address-prefix 10.1.2.0/24
    
    # Create virtual network in secondary region
    az network vnet create \
        --resource-group ${RESOURCE_GROUP_SECONDARY} \
        --name vnet-secondary \
        --address-prefix 10.2.0.0/16 \
        --subnet-name subnet-appgw \
        --subnet-prefix 10.2.1.0/24 \
        --location ${LOCATION_SECONDARY}
    
    # Create backend subnet for secondary region
    az network vnet subnet create \
        --resource-group ${RESOURCE_GROUP_SECONDARY} \
        --vnet-name vnet-secondary \
        --name subnet-backend \
        --address-prefix 10.2.2.0/24
    
    # Create virtual network in tertiary region
    az network vnet create \
        --resource-group ${RESOURCE_GROUP_TERTIARY} \
        --name vnet-tertiary \
        --address-prefix 10.3.0.0/16 \
        --subnet-name subnet-appgw \
        --subnet-prefix 10.3.1.0/24 \
        --location ${LOCATION_TERTIARY}
    
    # Create backend subnet for tertiary region
    az network vnet subnet create \
        --resource-group ${RESOURCE_GROUP_TERTIARY} \
        --vnet-name vnet-tertiary \
        --name subnet-backend \
        --address-prefix 10.3.2.0/24
    
    log "Virtual networks and subnets created successfully"
}

# Create public IP addresses
create_public_ips() {
    log "Creating public IP addresses for Application Gateways..."
    
    # Create public IP for primary region
    az network public-ip create \
        --resource-group ${RESOURCE_GROUP_PRIMARY} \
        --name pip-appgw-primary \
        --location ${LOCATION_PRIMARY} \
        --allocation-method Static \
        --sku Standard \
        --zone 1 2 3
    
    # Create public IP for secondary region
    az network public-ip create \
        --resource-group ${RESOURCE_GROUP_SECONDARY} \
        --name pip-appgw-secondary \
        --location ${LOCATION_SECONDARY} \
        --allocation-method Static \
        --sku Standard \
        --zone 1 2 3
    
    # Create public IP for tertiary region
    az network public-ip create \
        --resource-group ${RESOURCE_GROUP_TERTIARY} \
        --name pip-appgw-tertiary \
        --location ${LOCATION_TERTIARY} \
        --allocation-method Static \
        --sku Standard \
        --zone 1 2 3
    
    # Store public IP addresses for later use
    export PIP_PRIMARY=$(az network public-ip show \
        --resource-group ${RESOURCE_GROUP_PRIMARY} \
        --name pip-appgw-primary \
        --query ipAddress --output tsv)
    
    export PIP_SECONDARY=$(az network public-ip show \
        --resource-group ${RESOURCE_GROUP_SECONDARY} \
        --name pip-appgw-secondary \
        --query ipAddress --output tsv)
    
    export PIP_TERTIARY=$(az network public-ip show \
        --resource-group ${RESOURCE_GROUP_TERTIARY} \
        --name pip-appgw-tertiary \
        --query ipAddress --output tsv)
    
    log "Public IP addresses created successfully"
    log "Primary IP: $PIP_PRIMARY"
    log "Secondary IP: $PIP_SECONDARY"
    log "Tertiary IP: $PIP_TERTIARY"
}

# Create VM scale sets
create_vm_scale_sets() {
    log "Creating Virtual Machine Scale Sets..."
    
    # Create VM Scale Set in primary region
    az vmss create \
        --resource-group ${RESOURCE_GROUP_PRIMARY} \
        --name vmss-primary \
        --image Ubuntu2204 \
        --instance-count 2 \
        --admin-username azureuser \
        --generate-ssh-keys \
        --vnet-name vnet-primary \
        --subnet subnet-backend \
        --vm-sku Standard_B2s \
        --zones 1 2 3 \
        --load-balancer "" \
        --public-ip-address ""
    
    # Create VM Scale Set in secondary region
    az vmss create \
        --resource-group ${RESOURCE_GROUP_SECONDARY} \
        --name vmss-secondary \
        --image Ubuntu2204 \
        --instance-count 2 \
        --admin-username azureuser \
        --generate-ssh-keys \
        --vnet-name vnet-secondary \
        --subnet subnet-backend \
        --vm-sku Standard_B2s \
        --zones 1 2 3 \
        --load-balancer "" \
        --public-ip-address ""
    
    # Create VM Scale Set in tertiary region
    az vmss create \
        --resource-group ${RESOURCE_GROUP_TERTIARY} \
        --name vmss-tertiary \
        --image Ubuntu2204 \
        --instance-count 2 \
        --admin-username azureuser \
        --generate-ssh-keys \
        --vnet-name vnet-tertiary \
        --subnet subnet-backend \
        --vm-sku Standard_B2s \
        --zones 1 2 3 \
        --load-balancer "" \
        --public-ip-address ""
    
    log "Virtual Machine Scale Sets created successfully"
}

# Install web server applications
install_web_applications() {
    log "Installing web server applications on scale sets..."
    
    # Install nginx on primary region scale set
    az vmss extension set \
        --resource-group ${RESOURCE_GROUP_PRIMARY} \
        --vmss-name vmss-primary \
        --name customScript \
        --publisher Microsoft.Azure.Extensions \
        --version 2.1 \
        --settings '{
            "commandToExecute": "apt-get update && apt-get install -y nginx && systemctl start nginx && systemctl enable nginx && echo \"<h1>Primary Region - East US</h1><p>Server: $(hostname)</p><p>Region: East US</p>\" > /var/www/html/index.html"
        }'
    
    # Install nginx on secondary region scale set
    az vmss extension set \
        --resource-group ${RESOURCE_GROUP_SECONDARY} \
        --vmss-name vmss-secondary \
        --name customScript \
        --publisher Microsoft.Azure.Extensions \
        --version 2.1 \
        --settings '{
            "commandToExecute": "apt-get update && apt-get install -y nginx && systemctl start nginx && systemctl enable nginx && echo \"<h1>Secondary Region - UK South</h1><p>Server: $(hostname)</p><p>Region: UK South</p>\" > /var/www/html/index.html"
        }'
    
    # Install nginx on tertiary region scale set
    az vmss extension set \
        --resource-group ${RESOURCE_GROUP_TERTIARY} \
        --vmss-name vmss-tertiary \
        --name customScript \
        --publisher Microsoft.Azure.Extensions \
        --version 2.1 \
        --settings '{
            "commandToExecute": "apt-get update && apt-get install -y nginx && systemctl start nginx && systemctl enable nginx && echo \"<h1>Tertiary Region - Southeast Asia</h1><p>Server: $(hostname)</p><p>Region: Southeast Asia</p>\" > /var/www/html/index.html"
        }'
    
    log "Web server applications installed successfully"
}

# Create Application Gateways
create_application_gateways() {
    log "Creating Application Gateways with WAF protection..."
    
    # Create Application Gateway in primary region
    az network application-gateway create \
        --resource-group ${RESOURCE_GROUP_PRIMARY} \
        --name ${APP_GATEWAY_PRIMARY} \
        --location ${LOCATION_PRIMARY} \
        --vnet-name vnet-primary \
        --subnet subnet-appgw \
        --public-ip-address pip-appgw-primary \
        --capacity 2 \
        --sku WAF_v2 \
        --http-settings-cookie-based-affinity Disabled \
        --frontend-port 80 \
        --routing-rule-type Basic \
        --http-settings-port 80 \
        --http-settings-protocol Http \
        --zones 1 2 3
    
    # Create Application Gateway in secondary region
    az network application-gateway create \
        --resource-group ${RESOURCE_GROUP_SECONDARY} \
        --name ${APP_GATEWAY_SECONDARY} \
        --location ${LOCATION_SECONDARY} \
        --vnet-name vnet-secondary \
        --subnet subnet-appgw \
        --public-ip-address pip-appgw-secondary \
        --capacity 2 \
        --sku WAF_v2 \
        --http-settings-cookie-based-affinity Disabled \
        --frontend-port 80 \
        --routing-rule-type Basic \
        --http-settings-port 80 \
        --http-settings-protocol Http \
        --zones 1 2 3
    
    # Create Application Gateway in tertiary region
    az network application-gateway create \
        --resource-group ${RESOURCE_GROUP_TERTIARY} \
        --name ${APP_GATEWAY_TERTIARY} \
        --location ${LOCATION_TERTIARY} \
        --vnet-name vnet-tertiary \
        --subnet subnet-appgw \
        --public-ip-address pip-appgw-tertiary \
        --capacity 2 \
        --sku WAF_v2 \
        --http-settings-cookie-based-affinity Disabled \
        --frontend-port 80 \
        --routing-rule-type Basic \
        --http-settings-port 80 \
        --http-settings-protocol Http \
        --zones 1 2 3
    
    log "Application Gateways created successfully"
}

# Configure backend pools
configure_backend_pools() {
    log "Configuring Application Gateway backend pools..."
    
    # Wait for VM scale sets to be ready
    sleep 30
    
    # Configure backend pool for primary region
    BACKEND_IPS_PRIMARY=$(az vmss nic list \
        --resource-group ${RESOURCE_GROUP_PRIMARY} \
        --vmss-name vmss-primary \
        --query "[].ipConfigurations[0].privateIpAddress" \
        --output tsv | tr '\n' ' ')
    
    if [ -n "$BACKEND_IPS_PRIMARY" ]; then
        az network application-gateway address-pool update \
            --resource-group ${RESOURCE_GROUP_PRIMARY} \
            --gateway-name ${APP_GATEWAY_PRIMARY} \
            --name appGatewayBackendPool \
            --servers $BACKEND_IPS_PRIMARY
    fi
    
    # Configure backend pool for secondary region
    BACKEND_IPS_SECONDARY=$(az vmss nic list \
        --resource-group ${RESOURCE_GROUP_SECONDARY} \
        --vmss-name vmss-secondary \
        --query "[].ipConfigurations[0].privateIpAddress" \
        --output tsv | tr '\n' ' ')
    
    if [ -n "$BACKEND_IPS_SECONDARY" ]; then
        az network application-gateway address-pool update \
            --resource-group ${RESOURCE_GROUP_SECONDARY} \
            --gateway-name ${APP_GATEWAY_SECONDARY} \
            --name appGatewayBackendPool \
            --servers $BACKEND_IPS_SECONDARY
    fi
    
    # Configure backend pool for tertiary region
    BACKEND_IPS_TERTIARY=$(az vmss nic list \
        --resource-group ${RESOURCE_GROUP_TERTIARY} \
        --vmss-name vmss-tertiary \
        --query "[].ipConfigurations[0].privateIpAddress" \
        --output tsv | tr '\n' ' ')
    
    if [ -n "$BACKEND_IPS_TERTIARY" ]; then
        az network application-gateway address-pool update \
            --resource-group ${RESOURCE_GROUP_TERTIARY} \
            --gateway-name ${APP_GATEWAY_TERTIARY} \
            --name appGatewayBackendPool \
            --servers $BACKEND_IPS_TERTIARY
    fi
    
    log "Backend pools configured successfully"
}

# Create Traffic Manager
create_traffic_manager() {
    log "Creating Traffic Manager profile..."
    
    # Create Traffic Manager profile with performance routing
    az network traffic-manager profile create \
        --resource-group ${RESOURCE_GROUP_PRIMARY} \
        --name ${TRAFFIC_MANAGER_PROFILE} \
        --routing-method Performance \
        --unique-dns-name ${TRAFFIC_MANAGER_PROFILE} \
        --ttl 30 \
        --protocol HTTP \
        --port 80 \
        --path "/" \
        --interval 30 \
        --timeout 10 \
        --max-failures 3
    
    # Get Traffic Manager profile FQDN
    export TRAFFIC_MANAGER_FQDN=$(az network traffic-manager profile show \
        --resource-group ${RESOURCE_GROUP_PRIMARY} \
        --name ${TRAFFIC_MANAGER_PROFILE} \
        --query dnsConfig.fqdn \
        --output tsv)
    
    log "Traffic Manager profile created: $TRAFFIC_MANAGER_FQDN"
}

# Add Traffic Manager endpoints
add_traffic_manager_endpoints() {
    log "Adding regional endpoints to Traffic Manager..."
    
    # Add primary region endpoint
    az network traffic-manager endpoint create \
        --resource-group ${RESOURCE_GROUP_PRIMARY} \
        --profile-name ${TRAFFIC_MANAGER_PROFILE} \
        --name endpoint-primary \
        --type externalEndpoints \
        --target ${PIP_PRIMARY} \
        --endpoint-location "East US" \
        --priority 1 \
        --weight 100
    
    # Add secondary region endpoint
    az network traffic-manager endpoint create \
        --resource-group ${RESOURCE_GROUP_PRIMARY} \
        --profile-name ${TRAFFIC_MANAGER_PROFILE} \
        --name endpoint-secondary \
        --type externalEndpoints \
        --target ${PIP_SECONDARY} \
        --endpoint-location "UK South" \
        --priority 2 \
        --weight 100
    
    # Add tertiary region endpoint
    az network traffic-manager endpoint create \
        --resource-group ${RESOURCE_GROUP_PRIMARY} \
        --profile-name ${TRAFFIC_MANAGER_PROFILE} \
        --name endpoint-tertiary \
        --type externalEndpoints \
        --target ${PIP_TERTIARY} \
        --endpoint-location "Southeast Asia" \
        --priority 3 \
        --weight 100
    
    log "Traffic Manager endpoints added successfully"
}

# Create WAF policies
create_waf_policies() {
    log "Creating Web Application Firewall policies..."
    
    # Create WAF policy for primary region
    az network application-gateway waf-policy create \
        --resource-group ${RESOURCE_GROUP_PRIMARY} \
        --name waf-policy-primary \
        --location ${LOCATION_PRIMARY} \
        --type OWASP \
        --version 3.2 \
        --mode Prevention \
        --state Enabled
    
    # Create WAF policy for secondary region
    az network application-gateway waf-policy create \
        --resource-group ${RESOURCE_GROUP_SECONDARY} \
        --name waf-policy-secondary \
        --location ${LOCATION_SECONDARY} \
        --type OWASP \
        --version 3.2 \
        --mode Prevention \
        --state Enabled
    
    # Create WAF policy for tertiary region
    az network application-gateway waf-policy create \
        --resource-group ${RESOURCE_GROUP_TERTIARY} \
        --name waf-policy-tertiary \
        --location ${LOCATION_TERTIARY} \
        --type OWASP \
        --version 3.2 \
        --mode Prevention \
        --state Enabled
    
    log "WAF policies created successfully"
}

# Enable monitoring
enable_monitoring() {
    log "Enabling monitoring and diagnostics..."
    
    # Create Log Analytics workspace
    az monitor log-analytics workspace create \
        --resource-group ${RESOURCE_GROUP_PRIMARY} \
        --workspace-name law-global-traffic \
        --location ${LOCATION_PRIMARY} \
        --sku PerGB2018
    
    # Get Log Analytics workspace ID
    export WORKSPACE_ID=$(az monitor log-analytics workspace show \
        --resource-group ${RESOURCE_GROUP_PRIMARY} \
        --workspace-name law-global-traffic \
        --query id --output tsv)
    
    # Enable diagnostics for Traffic Manager
    az monitor diagnostic-settings create \
        --resource $(az network traffic-manager profile show \
            --resource-group ${RESOURCE_GROUP_PRIMARY} \
            --name ${TRAFFIC_MANAGER_PROFILE} \
            --query id --output tsv) \
        --name traffic-manager-diagnostics \
        --workspace ${WORKSPACE_ID} \
        --metrics '[{"category": "AllMetrics", "enabled": true}]' \
        --logs '[{"category": "ProbeHealthStatusEvents", "enabled": true}]'
    
    # Enable diagnostics for Application Gateway (primary)
    az monitor diagnostic-settings create \
        --resource $(az network application-gateway show \
            --resource-group ${RESOURCE_GROUP_PRIMARY} \
            --name ${APP_GATEWAY_PRIMARY} \
            --query id --output tsv) \
        --name appgw-primary-diagnostics \
        --workspace ${WORKSPACE_ID} \
        --metrics '[{"category": "AllMetrics", "enabled": true}]' \
        --logs '[{"category": "ApplicationGatewayAccessLog", "enabled": true}, {"category": "ApplicationGatewayPerformanceLog", "enabled": true}, {"category": "ApplicationGatewayFirewallLog", "enabled": true}]'
    
    log "Monitoring and diagnostics enabled successfully"
}

# Validation
validate_deployment() {
    log "Validating deployment..."
    
    # Check Traffic Manager profile status
    log "Checking Traffic Manager profile status..."
    TM_STATUS=$(az network traffic-manager profile show \
        --resource-group ${RESOURCE_GROUP_PRIMARY} \
        --name ${TRAFFIC_MANAGER_PROFILE} \
        --query profileStatus --output tsv)
    
    if [ "$TM_STATUS" == "Enabled" ]; then
        log "Traffic Manager profile is enabled"
    else
        warning "Traffic Manager profile status: $TM_STATUS"
    fi
    
    # Check endpoint health
    log "Checking endpoint health (may take a few minutes)..."
    sleep 60
    
    # Test Application Gateway responses
    log "Testing Application Gateway endpoints..."
    
    if curl -s -I "http://${PIP_PRIMARY}" | grep -q "200 OK"; then
        log "Primary region Application Gateway is responding"
    else
        warning "Primary region Application Gateway may not be ready yet"
    fi
    
    if curl -s -I "http://${PIP_SECONDARY}" | grep -q "200 OK"; then
        log "Secondary region Application Gateway is responding"
    else
        warning "Secondary region Application Gateway may not be ready yet"
    fi
    
    if curl -s -I "http://${PIP_TERTIARY}" | grep -q "200 OK"; then
        log "Tertiary region Application Gateway is responding"
    else
        warning "Tertiary region Application Gateway may not be ready yet"
    fi
    
    log "Deployment validation completed"
}

# Display deployment summary
display_summary() {
    log "Deployment Summary:"
    echo "===================="
    echo "Traffic Manager Profile: $TRAFFIC_MANAGER_PROFILE"
    echo "Traffic Manager FQDN: $TRAFFIC_MANAGER_FQDN"
    echo "Primary Region IP: $PIP_PRIMARY"
    echo "Secondary Region IP: $PIP_SECONDARY"
    echo "Tertiary Region IP: $PIP_TERTIARY"
    echo "===================="
    echo ""
    echo "You can now access your application at:"
    echo "http://$TRAFFIC_MANAGER_FQDN"
    echo ""
    echo "Note: It may take a few minutes for all endpoints to become fully healthy."
}

# Main deployment function
main() {
    log "Starting deployment of Global Traffic Distribution solution..."
    
    check_prerequisites
    set_environment
    create_resource_groups
    create_virtual_networks
    create_public_ips
    create_vm_scale_sets
    install_web_applications
    create_application_gateways
    configure_backend_pools
    create_traffic_manager
    add_traffic_manager_endpoints
    create_waf_policies
    enable_monitoring
    validate_deployment
    display_summary
    
    log "Deployment completed successfully!"
}

# Error handling
trap 'error "Deployment failed at line $LINENO. Exit code: $?"' ERR

# Run main function
main "$@"