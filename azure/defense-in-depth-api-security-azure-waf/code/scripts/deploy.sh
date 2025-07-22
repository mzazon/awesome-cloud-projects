#!/bin/bash

# Deploy Azure Zero-Trust API Security Infrastructure
# This script deploys Azure API Management with Azure Web Application Firewall
# for comprehensive zero-trust API security architecture

set -e  # Exit on any error
set -o pipefail  # Exit on pipe failures

# Color codes for output formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Check if script is run with dry-run flag
DRY_RUN=false
if [[ "$1" == "--dry-run" ]]; then
    DRY_RUN=true
    warning "Running in DRY-RUN mode - no resources will be created"
fi

# Function to execute commands (respects dry-run mode)
execute() {
    if [[ "$DRY_RUN" == "true" ]]; then
        echo -e "${YELLOW}[DRY-RUN]${NC} Would execute: $1"
    else
        log "Executing: $1"
        eval "$1"
    fi
}

log "Starting Azure Zero-Trust API Security deployment..."

# Prerequisites validation
log "Validating prerequisites..."

# Check if Azure CLI is installed
if ! command -v az &> /dev/null; then
    error "Azure CLI is not installed. Please install it from https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
    exit 1
fi

# Check if user is logged in to Azure
if ! az account show &> /dev/null; then
    error "Not logged in to Azure. Please run 'az login' first"
    exit 1
fi

# Check if openssl is available for random generation
if ! command -v openssl &> /dev/null; then
    error "openssl is required for generating random suffixes"
    exit 1
fi

# Verify required permissions
log "Checking Azure permissions..."
SUBSCRIPTION_ID=$(az account show --query id --output tsv)
if [[ -z "$SUBSCRIPTION_ID" ]]; then
    error "Unable to retrieve subscription ID"
    exit 1
fi

success "Prerequisites validation completed"

# Set environment variables
log "Setting up environment variables..."

export RESOURCE_GROUP="rg-zero-trust-api-${RANDOM_SUFFIX:-$(openssl rand -hex 3)}"
export LOCATION="${AZURE_LOCATION:-eastus}"
export SUBSCRIPTION_ID

# Generate unique suffix for resource names if not provided
if [[ -z "$RANDOM_SUFFIX" ]]; then
    RANDOM_SUFFIX=$(openssl rand -hex 3)
fi

# Set resource names with unique suffix
export VNET_NAME="vnet-zerotrust-${RANDOM_SUFFIX}"
export APIM_NAME="apim-zerotrust-${RANDOM_SUFFIX}"
export AGW_NAME="agw-zerotrust-${RANDOM_SUFFIX}"
export WAF_POLICY_NAME="waf-zerotrust-${RANDOM_SUFFIX}"
export LOG_WORKSPACE_NAME="log-zerotrust-${RANDOM_SUFFIX}"
export APP_INSIGHTS_NAME="ai-zerotrust-${RANDOM_SUFFIX}"

log "Using resource group: $RESOURCE_GROUP"
log "Using location: $LOCATION"
log "Using suffix: $RANDOM_SUFFIX"

# Save environment variables for cleanup script
cat > .env << EOF
RESOURCE_GROUP="$RESOURCE_GROUP"
LOCATION="$LOCATION"
SUBSCRIPTION_ID="$SUBSCRIPTION_ID"
RANDOM_SUFFIX="$RANDOM_SUFFIX"
VNET_NAME="$VNET_NAME"
APIM_NAME="$APIM_NAME"
AGW_NAME="$AGW_NAME"
WAF_POLICY_NAME="$WAF_POLICY_NAME"
LOG_WORKSPACE_NAME="$LOG_WORKSPACE_NAME"
APP_INSIGHTS_NAME="$APP_INSIGHTS_NAME"
EOF

# Function to check if resource group exists
resource_group_exists() {
    az group exists --name "$RESOURCE_GROUP" --output tsv
}

# Create resource group
log "Creating resource group..."
if [[ "$(resource_group_exists)" == "false" ]]; then
    execute "az group create --name \${RESOURCE_GROUP} --location \${LOCATION} --tags purpose=zero-trust-api-security environment=demo"
    success "Resource group created: $RESOURCE_GROUP"
else
    warning "Resource group $RESOURCE_GROUP already exists"
fi

# Create Virtual Network with Security Subnets
log "Creating virtual network with security-segmented subnets..."

execute "az network vnet create \\
    --resource-group \${RESOURCE_GROUP} \\
    --name \${VNET_NAME} \\
    --address-prefixes 10.0.0.0/16 \\
    --location \${LOCATION}"

# Create subnets
log "Creating application gateway subnet..."
execute "az network vnet subnet create \\
    --resource-group \${RESOURCE_GROUP} \\
    --vnet-name \${VNET_NAME} \\
    --name agw-subnet \\
    --address-prefixes 10.0.1.0/24"

log "Creating API management subnet..."
execute "az network vnet subnet create \\
    --resource-group \${RESOURCE_GROUP} \\
    --vnet-name \${VNET_NAME} \\
    --name apim-subnet \\
    --address-prefixes 10.0.2.0/24"

log "Creating private endpoints subnet..."
execute "az network vnet subnet create \\
    --resource-group \${RESOURCE_GROUP} \\
    --vnet-name \${VNET_NAME} \\
    --name pe-subnet \\
    --address-prefixes 10.0.3.0/24"

success "Virtual network created with security-segmented subnets"

# Create Log Analytics Workspace and Application Insights
log "Creating monitoring infrastructure..."

execute "az monitor log-analytics workspace create \\
    --resource-group \${RESOURCE_GROUP} \\
    --workspace-name \${LOG_WORKSPACE_NAME} \\
    --location \${LOCATION} \\
    --retention-time 30"

# Get workspace ID
if [[ "$DRY_RUN" == "false" ]]; then
    WORKSPACE_ID=$(az monitor log-analytics workspace show \
        --resource-group ${RESOURCE_GROUP} \
        --workspace-name ${LOG_WORKSPACE_NAME} \
        --query id --output tsv)
    
    if [[ -z "$WORKSPACE_ID" ]]; then
        error "Failed to retrieve workspace ID"
        exit 1
    fi
    
    echo "WORKSPACE_ID=\"$WORKSPACE_ID\"" >> .env
else
    WORKSPACE_ID="/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.OperationalInsights/workspaces/${LOG_WORKSPACE_NAME}"
fi

execute "az monitor app-insights component create \\
    --resource-group \${RESOURCE_GROUP} \\
    --app \${APP_INSIGHTS_NAME} \\
    --location \${LOCATION} \\
    --workspace \${WORKSPACE_ID}"

# Get Application Insights instrumentation key
if [[ "$DRY_RUN" == "false" ]]; then
    APPINSIGHTS_KEY=$(az monitor app-insights component show \
        --resource-group ${RESOURCE_GROUP} \
        --app ${APP_INSIGHTS_NAME} \
        --query instrumentationKey --output tsv)
    
    if [[ -z "$APPINSIGHTS_KEY" ]]; then
        error "Failed to retrieve Application Insights key"
        exit 1
    fi
    
    echo "APPINSIGHTS_KEY=\"$APPINSIGHTS_KEY\"" >> .env
fi

success "Monitoring infrastructure created"

# Create Web Application Firewall Policy
log "Creating WAF policy with OWASP protection..."

execute "az network application-gateway waf-policy create \\
    --resource-group \${RESOURCE_GROUP} \\
    --name \${WAF_POLICY_NAME} \\
    --location \${LOCATION} \\
    --type OWASP \\
    --version 3.2"

# Configure WAF policy settings
execute "az network application-gateway waf-policy policy-setting update \\
    --resource-group \${RESOURCE_GROUP} \\
    --policy-name \${WAF_POLICY_NAME} \\
    --state Enabled \\
    --mode Prevention \\
    --max-request-body-size-in-kb 128 \\
    --file-upload-limit-in-mb 100 \\
    --request-body-check true"

# Add custom rate limiting rule
execute "az network application-gateway waf-policy custom-rule create \\
    --resource-group \${RESOURCE_GROUP} \\
    --policy-name \${WAF_POLICY_NAME} \\
    --name RateLimitRule \\
    --priority 100 \\
    --rule-type RateLimitRule \\
    --action Block \\
    --rate-limit-duration OneMinute \\
    --rate-limit-threshold 100"

success "WAF policy created with OWASP protection and rate limiting"

# Create API Management Service
log "Creating API Management service (this may take 20-30 minutes)..."
warning "API Management creation is a long-running operation. Please be patient."

execute "az apim create \\
    --resource-group \${RESOURCE_GROUP} \\
    --name \${APIM_NAME} \\
    --publisher-email \"admin@contoso.com\" \\
    --publisher-name \"Contoso API Security\" \\
    --sku-name Standard \\
    --location \${LOCATION} \\
    --enable-managed-identity \\
    --virtual-network Internal \\
    --subnet-id \"/subscriptions/\${SUBSCRIPTION_ID}/resourceGroups/\${RESOURCE_GROUP}/providers/Microsoft.Network/virtualNetworks/\${VNET_NAME}/subnets/apim-subnet\""

# Wait for API Management provisioning
if [[ "$DRY_RUN" == "false" ]]; then
    log "Waiting for API Management provisioning to complete..."
    az apim wait \
        --resource-group ${RESOURCE_GROUP} \
        --name ${APIM_NAME} \
        --created \
        --timeout 2400
    
    # Get API Management gateway URL
    APIM_GATEWAY_URL=$(az apim show \
        --resource-group ${RESOURCE_GROUP} \
        --name ${APIM_NAME} \
        --query gatewayUrl --output tsv)
    
    if [[ -z "$APIM_GATEWAY_URL" ]]; then
        error "Failed to retrieve API Management gateway URL"
        exit 1
    fi
    
    echo "APIM_GATEWAY_URL=\"$APIM_GATEWAY_URL\"" >> .env
    success "API Management created with internal virtual network integration"
else
    APIM_GATEWAY_URL="https://${APIM_NAME}.azure-api.net"
fi

# Configure Application Insights Integration
log "Configuring Application Insights integration..."

if [[ "$DRY_RUN" == "false" ]]; then
    execute "az apim logger create \\
        --resource-group \${RESOURCE_GROUP} \\
        --service-name \${APIM_NAME} \\
        --logger-id appInsights \\
        --logger-type applicationInsights \\
        --description \"Application Insights Logger\" \\
        --credentials \"instrumentationKey=\${APPINSIGHTS_KEY}\""
    
    execute "az apim diagnostic create \\
        --resource-group \${RESOURCE_GROUP} \\
        --service-name \${APIM_NAME} \\
        --diagnostic-id applicationinsights \\
        --logger-id appInsights \\
        --always-log allErrors \\
        --sampling-percentage 100"
    
    success "Application Insights integration configured"
fi

# Create public IP for Application Gateway
log "Creating public IP for Application Gateway..."

execute "az network public-ip create \\
    --resource-group \${RESOURCE_GROUP} \\
    --name \${AGW_NAME}-pip \\
    --location \${LOCATION} \\
    --allocation-method Static \\
    --sku Standard"

# Get public IP address
if [[ "$DRY_RUN" == "false" ]]; then
    PUBLIC_IP=$(az network public-ip show \
        --resource-group ${RESOURCE_GROUP} \
        --name ${AGW_NAME}-pip \
        --query ipAddress --output tsv)
    
    if [[ -z "$PUBLIC_IP" ]]; then
        error "Failed to retrieve public IP address"
        exit 1
    fi
    
    echo "PUBLIC_IP=\"$PUBLIC_IP\"" >> .env
    log "Public IP created: $PUBLIC_IP"
fi

# Create Application Gateway with WAF
log "Creating Application Gateway with WAF integration..."

# Extract hostname from APIM gateway URL for backend pool
APIM_HOSTNAME=${APIM_GATEWAY_URL#https://}

execute "az network application-gateway create \\
    --resource-group \${RESOURCE_GROUP} \\
    --name \${AGW_NAME} \\
    --location \${LOCATION} \\
    --capacity 2 \\
    --sku WAF_v2 \\
    --vnet-name \${VNET_NAME} \\
    --subnet agw-subnet \\
    --public-ip-address \${AGW_NAME}-pip \\
    --waf-policy \${WAF_POLICY_NAME} \\
    --frontend-port 80 \\
    --routing-rule-type Basic \\
    --servers \${APIM_HOSTNAME} \\
    --priority 100"

success "Application Gateway created with WAF protection"

# Create sample API with security policies
log "Creating sample API with comprehensive security policies..."

# Create security policy file
cat > security-policy.xml << 'EOF'
<policies>
    <inbound>
        <base />
        <validate-jwt header-name="Authorization" failed-validation-httpcode="401" failed-validation-error-message="Unauthorized">
            <openid-config url="https://login.microsoftonline.com/common/v2.0/.well-known/openid_configuration" />
            <required-claims>
                <claim name="aud" match="any">
                    <value>api://your-api-id</value>
                </claim>
            </required-claims>
        </validate-jwt>
        <rate-limit calls="100" renewal-period="60" />
        <rate-limit-by-key calls="10" renewal-period="60" counter-key="@(context.Request.IpAddress)" />
        <ip-filter action="allow">
            <address-range from="0.0.0.0" to="255.255.255.255" />
        </ip-filter>
        <log-to-eventhub logger-id="appInsights" partition-id="0">
            @{
                return new JObject(
                    new JProperty("timestamp", DateTime.UtcNow.ToString()),
                    new JProperty("operation", context.Operation.Name),
                    new JProperty("clientIp", context.Request.IpAddress),
                    new JProperty("userAgent", context.Request.Headers.GetValueOrDefault("User-Agent", "")),
                    new JProperty("requestId", context.RequestId)
                ).ToString();
            }
        </log-to-eventhub>
    </inbound>
    <backend>
        <base />
    </backend>
    <outbound>
        <base />
        <set-header name="X-Powered-By" exists-action="delete" />
        <set-header name="Server" exists-action="delete" />
    </outbound>
    <on-error>
        <base />
    </on-error>
</policies>
EOF

if [[ "$DRY_RUN" == "false" ]]; then
    # Create sample API
    execute "az apim api create \\
        --resource-group \${RESOURCE_GROUP} \\
        --service-name \${APIM_NAME} \\
        --api-id sample-api \\
        --display-name \"Sample Secure API\" \\
        --path \"/secure\" \\
        --service-url \"https://httpbin.org\" \\
        --protocols https"
    
    # Add GET operation
    execute "az apim api operation create \\
        --resource-group \${RESOURCE_GROUP} \\
        --service-name \${APIM_NAME} \\
        --api-id sample-api \\
        --operation-id get-secure-data \\
        --display-name \"Get Secure Data\" \\
        --method GET \\
        --url-template \"/data\""
    
    # Apply security policy
    execute "az apim api policy create \\
        --resource-group \${RESOURCE_GROUP} \\
        --service-name \${APIM_NAME} \\
        --api-id sample-api \\
        --policy-content @security-policy.xml"
    
    success "Sample API created with comprehensive zero-trust security policies"
fi

# Configure Private Link for Backend Connectivity
log "Configuring Private Link for secure backend connectivity..."

execute "az network private-endpoint create \\
    --resource-group \${RESOURCE_GROUP} \\
    --name pe-backend \\
    --vnet-name \${VNET_NAME} \\
    --subnet pe-subnet \\
    --private-connection-resource-id \"/subscriptions/\${SUBSCRIPTION_ID}/resourceGroups/\${RESOURCE_GROUP}/providers/Microsoft.ApiManagement/service/\${APIM_NAME}\" \\
    --group-ids gateway \\
    --connection-name backend-connection"

execute "az network private-dns zone create \\
    --resource-group \${RESOURCE_GROUP} \\
    --name privatelink.azure-api.net"

execute "az network private-dns link vnet create \\
    --resource-group \${RESOURCE_GROUP} \\
    --zone-name privatelink.azure-api.net \\
    --name dns-link \\
    --virtual-network \${VNET_NAME} \\
    --registration-enabled false"

success "Private Link configured for secure backend connectivity"

# Clean up temporary files
rm -f security-policy.xml

# Display deployment summary
echo ""
success "=== DEPLOYMENT COMPLETED SUCCESSFULLY ==="
echo ""
log "Resource Summary:"
log "  Resource Group: $RESOURCE_GROUP"
log "  Location: $LOCATION"
log "  Virtual Network: $VNET_NAME"
log "  API Management: $APIM_NAME"
log "  Application Gateway: $AGW_NAME"
log "  WAF Policy: $WAF_POLICY_NAME"

if [[ "$DRY_RUN" == "false" && -n "$PUBLIC_IP" ]]; then
    log "  Public IP: $PUBLIC_IP"
    echo ""
    log "Test your deployment:"
    log "  WAF Test: curl -X GET \"http://$PUBLIC_IP/secure/data\" -H \"User-Agent: <script>alert('xss')</script>\" -v"
    log "  Rate Limit Test: for i in {1..15}; do curl -X GET \"http://$PUBLIC_IP/secure/data\" -w \"%{http_code}\n\" -s -o /dev/null; done"
fi

echo ""
log "Environment variables saved to .env file for cleanup script"
warning "Remember to run ./destroy.sh when you're done to avoid ongoing charges"

if [[ "$DRY_RUN" == "true" ]]; then
    echo ""
    warning "This was a DRY-RUN. No resources were actually created."
    log "Run without --dry-run flag to deploy the infrastructure"
fi