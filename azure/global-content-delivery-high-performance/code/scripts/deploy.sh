#!/bin/bash

# =============================================================================
# Azure Front Door Premium + NetApp Files Deployment Script
# Creates high-performance multi-regional content delivery infrastructure
# =============================================================================

set -e # Exit on any error
set -u # Exit on undefined variables

# Colors for output
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
}

# Cleanup function for error handling
cleanup_on_error() {
    error "Deployment failed. Cleaning up resources..."
    if [[ -n "${RESOURCE_GROUP:-}" ]]; then
        az group delete --name "${RESOURCE_GROUP}" --yes --no-wait || true
    fi
    exit 1
}

# Trap errors
trap cleanup_on_error ERR

# =============================================================================
# PREREQUISITES CHECK
# =============================================================================

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

# Check if jq is installed (for JSON parsing)
if ! command -v jq &> /dev/null; then
    error "jq is not installed. Please install it first."
    exit 1
fi

# Check if openssl is available for random string generation
if ! command -v openssl &> /dev/null; then
    error "openssl is not available. Please install it first."
    exit 1
fi

success "Prerequisites check passed"

# =============================================================================
# CONFIGURATION
# =============================================================================

log "Setting up configuration..."

# Generate unique suffix for resource names
RANDOM_SUFFIX=$(openssl rand -hex 3)

# Set environment variables for Azure resources
export RESOURCE_GROUP="rg-content-delivery-${RANDOM_SUFFIX}"
export LOCATION_PRIMARY="eastus"
export LOCATION_SECONDARY="westeurope"
export SUBSCRIPTION_ID=$(az account show --query id --output tsv)

# NetApp Files specific variables
export ANF_ACCOUNT_PRIMARY="anf-primary-${RANDOM_SUFFIX}"
export ANF_ACCOUNT_SECONDARY="anf-secondary-${RANDOM_SUFFIX}"
export CAPACITY_POOL_NAME="pool-premium"
export VOLUME_NAME="content-volume"

# Front Door and networking variables
export FRONT_DOOR_NAME="fd-content-${RANDOM_SUFFIX}"
export VNET_PRIMARY="vnet-primary-${RANDOM_SUFFIX}"
export VNET_SECONDARY="vnet-secondary-${RANDOM_SUFFIX}"
export PRIVATE_LINK_NAME="pl-content-${RANDOM_SUFFIX}"

# Additional variables
export LOAD_BALANCER_NAME="lb-content-${RANDOM_SUFFIX}"
export WAF_POLICY_NAME="waf-content-${RANDOM_SUFFIX}"
export LOG_ANALYTICS_NAME="law-content-${RANDOM_SUFFIX}"

log "Configuration set with suffix: ${RANDOM_SUFFIX}"

# =============================================================================
# RESOURCE PROVIDERS REGISTRATION
# =============================================================================

log "Registering required resource providers..."

# Register required resource providers
az provider register --namespace Microsoft.NetApp --wait
az provider register --namespace Microsoft.Cdn --wait
az provider register --namespace Microsoft.Network --wait
az provider register --namespace Microsoft.Insights --wait

success "Resource providers registered successfully"

# =============================================================================
# RESOURCE GROUP CREATION
# =============================================================================

log "Creating resource group..."

az group create \
    --name "${RESOURCE_GROUP}" \
    --location "${LOCATION_PRIMARY}" \
    --tags purpose=content-delivery environment=production

success "Resource group created: ${RESOURCE_GROUP}"

# =============================================================================
# VIRTUAL NETWORKS CREATION
# =============================================================================

log "Creating virtual networks and subnets..."

# Create primary region virtual network
az network vnet create \
    --name "${VNET_PRIMARY}" \
    --resource-group "${RESOURCE_GROUP}" \
    --location "${LOCATION_PRIMARY}" \
    --address-prefix 10.1.0.0/16 \
    --subnet-name anf-subnet \
    --subnet-prefix 10.1.1.0/24

# Create subnet for private endpoints in primary region
az network vnet subnet create \
    --name pe-subnet \
    --resource-group "${RESOURCE_GROUP}" \
    --vnet-name "${VNET_PRIMARY}" \
    --address-prefix 10.1.2.0/24

# Create secondary region virtual network
az network vnet create \
    --name "${VNET_SECONDARY}" \
    --resource-group "${RESOURCE_GROUP}" \
    --location "${LOCATION_SECONDARY}" \
    --address-prefix 10.2.0.0/16 \
    --subnet-name anf-subnet \
    --subnet-prefix 10.2.1.0/24

# Create subnet for private endpoints in secondary region
az network vnet subnet create \
    --name pe-subnet \
    --resource-group "${RESOURCE_GROUP}" \
    --vnet-name "${VNET_SECONDARY}" \
    --address-prefix 10.2.2.0/24

success "Virtual networks and subnets created in both regions"

# =============================================================================
# SUBNET DELEGATION
# =============================================================================

log "Delegating subnets to Azure NetApp Files..."

# Delegate subnet to NetApp Files in primary region
az network vnet subnet update \
    --name anf-subnet \
    --resource-group "${RESOURCE_GROUP}" \
    --vnet-name "${VNET_PRIMARY}" \
    --delegations Microsoft.NetApp/volumes

# Delegate subnet to NetApp Files in secondary region
az network vnet subnet update \
    --name anf-subnet \
    --resource-group "${RESOURCE_GROUP}" \
    --vnet-name "${VNET_SECONDARY}" \
    --delegations Microsoft.NetApp/volumes

success "Subnets delegated to Azure NetApp Files"

# =============================================================================
# AZURE NETAPP FILES SETUP
# =============================================================================

log "Creating Azure NetApp Files accounts and capacity pools..."

# Create NetApp Files account in primary region
az netappfiles account create \
    --resource-group "${RESOURCE_GROUP}" \
    --location "${LOCATION_PRIMARY}" \
    --account-name "${ANF_ACCOUNT_PRIMARY}"

# Create NetApp Files account in secondary region
az netappfiles account create \
    --resource-group "${RESOURCE_GROUP}" \
    --location "${LOCATION_SECONDARY}" \
    --account-name "${ANF_ACCOUNT_SECONDARY}"

# Create capacity pool in primary region (Premium tier)
az netappfiles pool create \
    --resource-group "${RESOURCE_GROUP}" \
    --location "${LOCATION_PRIMARY}" \
    --account-name "${ANF_ACCOUNT_PRIMARY}" \
    --pool-name "${CAPACITY_POOL_NAME}" \
    --size 4 \
    --service-level Premium

# Create capacity pool in secondary region (Premium tier)
az netappfiles pool create \
    --resource-group "${RESOURCE_GROUP}" \
    --location "${LOCATION_SECONDARY}" \
    --account-name "${ANF_ACCOUNT_SECONDARY}" \
    --pool-name "${CAPACITY_POOL_NAME}" \
    --size 4 \
    --service-level Premium

success "NetApp Files accounts and capacity pools created"

# =============================================================================
# AZURE NETAPP FILES VOLUMES
# =============================================================================

log "Creating Azure NetApp Files volumes..."

# Get subnet ID for primary region
SUBNET_ID_PRIMARY=$(az network vnet subnet show \
    --name anf-subnet \
    --resource-group "${RESOURCE_GROUP}" \
    --vnet-name "${VNET_PRIMARY}" \
    --query id --output tsv)

# Get subnet ID for secondary region
SUBNET_ID_SECONDARY=$(az network vnet subnet show \
    --name anf-subnet \
    --resource-group "${RESOURCE_GROUP}" \
    --vnet-name "${VNET_SECONDARY}" \
    --query id --output tsv)

# Create volume in primary region
az netappfiles volume create \
    --resource-group "${RESOURCE_GROUP}" \
    --location "${LOCATION_PRIMARY}" \
    --account-name "${ANF_ACCOUNT_PRIMARY}" \
    --pool-name "${CAPACITY_POOL_NAME}" \
    --volume-name "${VOLUME_NAME}" \
    --service-level Premium \
    --usage-threshold 1000 \
    --file-path "content-primary" \
    --subnet "${SUBNET_ID_PRIMARY}" \
    --protocol-types NFSv3

# Create volume in secondary region
az netappfiles volume create \
    --resource-group "${RESOURCE_GROUP}" \
    --location "${LOCATION_SECONDARY}" \
    --account-name "${ANF_ACCOUNT_SECONDARY}" \
    --pool-name "${CAPACITY_POOL_NAME}" \
    --volume-name "${VOLUME_NAME}" \
    --service-level Premium \
    --usage-threshold 1000 \
    --file-path "content-secondary" \
    --subnet "${SUBNET_ID_SECONDARY}" \
    --protocol-types NFSv3

success "NetApp Files volumes created with NFS protocol"

# =============================================================================
# LOAD BALANCER SETUP
# =============================================================================

log "Creating load balancer for Private Link Service..."

# Create load balancer for Private Link Service
az network lb create \
    --resource-group "${RESOURCE_GROUP}" \
    --name "${LOAD_BALANCER_NAME}" \
    --location "${LOCATION_PRIMARY}" \
    --sku Standard \
    --vnet-name "${VNET_PRIMARY}" \
    --subnet anf-subnet \
    --frontend-ip-name frontend-ip \
    --private-ip-address 10.1.1.10

# Create backend pool
az network lb address-pool create \
    --resource-group "${RESOURCE_GROUP}" \
    --lb-name "${LOAD_BALANCER_NAME}" \
    --name backend-pool

# Create health probe
az network lb probe create \
    --resource-group "${RESOURCE_GROUP}" \
    --lb-name "${LOAD_BALANCER_NAME}" \
    --name health-probe \
    --protocol tcp \
    --port 80

# Create load balancing rule
az network lb rule create \
    --resource-group "${RESOURCE_GROUP}" \
    --lb-name "${LOAD_BALANCER_NAME}" \
    --name content-rule \
    --protocol tcp \
    --frontend-port 80 \
    --backend-port 80 \
    --frontend-ip-name frontend-ip \
    --backend-pool-name backend-pool \
    --probe-name health-probe

success "Load balancer configured for Private Link Service"

# =============================================================================
# AZURE FRONT DOOR SETUP
# =============================================================================

log "Creating Azure Front Door Premium profile..."

# Create Front Door Premium profile
az afd profile create \
    --resource-group "${RESOURCE_GROUP}" \
    --profile-name "${FRONT_DOOR_NAME}" \
    --sku Premium_AzureFrontDoor

# Create endpoint for content delivery
az afd endpoint create \
    --resource-group "${RESOURCE_GROUP}" \
    --profile-name "${FRONT_DOOR_NAME}" \
    --endpoint-name "content-endpoint" \
    --enabled-state Enabled

success "Front Door Premium profile and endpoint created"

# =============================================================================
# FRONT DOOR ORIGIN CONFIGURATION
# =============================================================================

log "Configuring Front Door origins and origin groups..."

# Create origin group
az afd origin-group create \
    --resource-group "${RESOURCE_GROUP}" \
    --profile-name "${FRONT_DOOR_NAME}" \
    --origin-group-name "content-origins" \
    --probe-request-type GET \
    --probe-protocol Http \
    --probe-interval-in-seconds 60 \
    --probe-path "/" \
    --sample-size 4 \
    --successful-samples-required 3 \
    --additional-latency-in-milliseconds 50

# Create primary origin
az afd origin create \
    --resource-group "${RESOURCE_GROUP}" \
    --profile-name "${FRONT_DOOR_NAME}" \
    --origin-group-name "content-origins" \
    --origin-name "primary-origin" \
    --enabled-state Enabled \
    --host-name "10.1.1.10" \
    --http-port 80 \
    --https-port 443 \
    --origin-host-header "content.example.com" \
    --priority 1 \
    --weight 1000

# Create secondary origin for failover
az afd origin create \
    --resource-group "${RESOURCE_GROUP}" \
    --profile-name "${FRONT_DOOR_NAME}" \
    --origin-group-name "content-origins" \
    --origin-name "secondary-origin" \
    --enabled-state Enabled \
    --host-name "10.2.1.10" \
    --http-port 80 \
    --https-port 443 \
    --origin-host-header "content.example.com" \
    --priority 2 \
    --weight 1000

success "Origin groups and origins configured"

# =============================================================================
# FRONT DOOR ROUTING CONFIGURATION
# =============================================================================

log "Configuring Front Door routes and caching rules..."

# Create route for content delivery
az afd route create \
    --resource-group "${RESOURCE_GROUP}" \
    --profile-name "${FRONT_DOOR_NAME}" \
    --endpoint-name "content-endpoint" \
    --route-name "content-route" \
    --origin-group "content-origins" \
    --supported-protocols Http Https \
    --patterns-to-match "/*" \
    --forwarding-protocol HttpsOnly \
    --link-to-default-domain Enabled \
    --https-redirect Enabled

# Create rule set for caching
az afd rule-set create \
    --resource-group "${RESOURCE_GROUP}" \
    --profile-name "${FRONT_DOOR_NAME}" \
    --rule-set-name "caching-rules"

# Create caching rule for static content
az afd rule create \
    --resource-group "${RESOURCE_GROUP}" \
    --profile-name "${FRONT_DOOR_NAME}" \
    --rule-set-name "caching-rules" \
    --rule-name "static-content" \
    --order 1 \
    --conditions '[{"name":"UrlFileExtension","parameters":{"operator":"Equal","matchValues":["jpg","jpeg","png","gif","css","js","pdf","mp4","mp3"],"transforms":["Lowercase"]}}]' \
    --actions '[{"name":"ModifyResponseHeader","parameters":{"headerAction":"Overwrite","headerName":"Cache-Control","value":"public, max-age=31536000"}}]'

success "Routes and caching rules configured"

# =============================================================================
# WAF POLICY SETUP
# =============================================================================

log "Creating Web Application Firewall policy..."

# Create WAF policy
az network front-door waf-policy create \
    --resource-group "${RESOURCE_GROUP}" \
    --name "${WAF_POLICY_NAME}" \
    --mode Prevention \
    --enabled true \
    --sku Premium_AzureFrontDoor

# Create managed rule set
az network front-door waf-policy managed-rules add \
    --resource-group "${RESOURCE_GROUP}" \
    --policy-name "${WAF_POLICY_NAME}" \
    --type Microsoft_DefaultRuleSet \
    --version 2.1 \
    --action Block

# Create rate limiting rule
az network front-door waf-policy rule create \
    --resource-group "${RESOURCE_GROUP}" \
    --policy-name "${WAF_POLICY_NAME}" \
    --name "RateLimitRule" \
    --priority 100 \
    --rule-type RateLimitRule \
    --action Block \
    --rate-limit-duration-in-minutes 1 \
    --rate-limit-threshold 100

success "WAF policy configured with managed rules"

# =============================================================================
# MONITORING SETUP
# =============================================================================

log "Setting up monitoring and diagnostics..."

# Create Log Analytics workspace
az monitor log-analytics workspace create \
    --resource-group "${RESOURCE_GROUP}" \
    --workspace-name "${LOG_ANALYTICS_NAME}" \
    --location "${LOCATION_PRIMARY}" \
    --sku PerGB2018

# Get workspace ID
WORKSPACE_ID=$(az monitor log-analytics workspace show \
    --resource-group "${RESOURCE_GROUP}" \
    --workspace-name "${LOG_ANALYTICS_NAME}" \
    --query id --output tsv)

# Get Front Door profile ID
FRONT_DOOR_ID=$(az afd profile show \
    --resource-group "${RESOURCE_GROUP}" \
    --profile-name "${FRONT_DOOR_NAME}" \
    --query id --output tsv)

# Enable diagnostic settings for Front Door
az monitor diagnostic-settings create \
    --resource-group "${RESOURCE_GROUP}" \
    --name "fd-diagnostics" \
    --resource "${FRONT_DOOR_ID}" \
    --workspace "${WORKSPACE_ID}" \
    --logs '[{"category":"FrontDoorAccessLog","enabled":true}]' \
    --metrics '[{"category":"AllMetrics","enabled":true}]'

success "Monitoring and diagnostics configured"

# =============================================================================
# DEPLOYMENT VALIDATION
# =============================================================================

log "Validating deployment..."

# Check NetApp Files volume status
ANF_STATUS=$(az netappfiles volume show \
    --resource-group "${RESOURCE_GROUP}" \
    --account-name "${ANF_ACCOUNT_PRIMARY}" \
    --pool-name "${CAPACITY_POOL_NAME}" \
    --volume-name "${VOLUME_NAME}" \
    --query "provisioningState" --output tsv)

if [[ "${ANF_STATUS}" == "Succeeded" ]]; then
    success "NetApp Files volume is ready"
else
    warning "NetApp Files volume status: ${ANF_STATUS}"
fi

# Get Front Door endpoint hostname
ENDPOINT_HOSTNAME=$(az afd endpoint show \
    --resource-group "${RESOURCE_GROUP}" \
    --profile-name "${FRONT_DOOR_NAME}" \
    --endpoint-name "content-endpoint" \
    --query "hostName" --output tsv)

# Check WAF policy status
WAF_STATUS=$(az network front-door waf-policy show \
    --resource-group "${RESOURCE_GROUP}" \
    --name "${WAF_POLICY_NAME}" \
    --query "policySettings.enabledState" --output tsv)

if [[ "${WAF_STATUS}" == "Enabled" ]]; then
    success "WAF policy is enabled"
else
    warning "WAF policy status: ${WAF_STATUS}"
fi

# =============================================================================
# DEPLOYMENT SUMMARY
# =============================================================================

log "Deployment completed successfully!"

echo ""
echo "==============================================================================" 
echo "DEPLOYMENT SUMMARY"
echo "=============================================================================="
echo ""
echo "Resource Group: ${RESOURCE_GROUP}"
echo "Primary Region: ${LOCATION_PRIMARY}"
echo "Secondary Region: ${LOCATION_SECONDARY}"
echo ""
echo "Azure NetApp Files:"
echo "  Primary Account: ${ANF_ACCOUNT_PRIMARY}"
echo "  Secondary Account: ${ANF_ACCOUNT_SECONDARY}"
echo "  Volume Name: ${VOLUME_NAME}"
echo ""
echo "Azure Front Door:"
echo "  Profile Name: ${FRONT_DOOR_NAME}"
echo "  Endpoint URL: https://${ENDPOINT_HOSTNAME}"
echo ""
echo "WAF Policy: ${WAF_POLICY_NAME}"
echo "Log Analytics: ${LOG_ANALYTICS_NAME}"
echo ""
echo "=============================================================================="
echo "NEXT STEPS:"
echo "=============================================================================="
echo ""
echo "1. Configure your origin servers to use the NetApp Files volumes"
echo "2. Upload content to the NetApp Files volumes"
echo "3. Test the Front Door endpoint: https://${ENDPOINT_HOSTNAME}"
echo "4. Monitor performance through Azure Monitor"
echo "5. Review WAF logs for security events"
echo ""
echo "To clean up resources, run: ./destroy.sh"
echo ""

success "Deployment script completed!"