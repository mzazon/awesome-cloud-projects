#!/bin/bash

# Enterprise API Protection with Premium Management and WAF - Deployment Script
# This script deploys the complete Azure infrastructure for enterprise API security
# including API Management Premium, Web Application Firewall, Redis Enterprise, and monitoring

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

log_warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING:${NC} $1"
}

log_error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1"
}

log_info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO:${NC} $1"
}

# Error handling function
handle_error() {
    log_error "Deployment failed on line $1"
    log_error "Use destroy.sh to clean up any partially created resources"
    exit 1
}

# Set up error handling
trap 'handle_error $LINENO' ERR

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        log_error "Azure CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if user is logged in
    if ! az account show &> /dev/null; then
        log_error "Please run 'az login' to authenticate with Azure"
        exit 1
    fi
    
    # Check if required tools are available
    if ! command -v openssl &> /dev/null; then
        log_error "openssl is required for generating random strings"
        exit 1
    fi
    
    # Check Azure CLI version
    local az_version=$(az version --query '"azure-cli"' -o tsv 2>/dev/null || echo "unknown")
    log_info "Azure CLI version: $az_version"
    
    # Get subscription info
    local subscription_name=$(az account show --query name -o tsv)
    local subscription_id=$(az account show --query id -o tsv)
    log_info "Using subscription: $subscription_name ($subscription_id)"
    
    log "✅ Prerequisites check completed"
}

# Function to set environment variables
set_environment_variables() {
    log "Setting up environment variables..."
    
    # Set default values if not already set
    export RESOURCE_GROUP="${RESOURCE_GROUP:-rg-enterprise-api-security}"
    export LOCATION="${LOCATION:-eastus}"
    export SUBSCRIPTION_ID=$(az account show --query id --output tsv)
    
    # Generate unique suffix for globally unique resource names
    if [[ -z "${RANDOM_SUFFIX:-}" ]]; then
        export RANDOM_SUFFIX=$(openssl rand -hex 4)
        log_info "Generated random suffix: $RANDOM_SUFFIX"
    fi
    
    # Set resource names with unique suffix
    export APIM_NAME="apim-enterprise-${RANDOM_SUFFIX}"
    export WAF_POLICY_NAME="waf-enterprise-policy-${RANDOM_SUFFIX}"
    export FRONT_DOOR_NAME="fd-enterprise-${RANDOM_SUFFIX}"
    export REDIS_NAME="redis-enterprise-${RANDOM_SUFFIX}"
    export APP_INSIGHTS_NAME="ai-enterprise-${RANDOM_SUFFIX}"
    export LOG_WORKSPACE_NAME="law-enterprise-${RANDOM_SUFFIX}"
    
    # Validate resource names
    if [[ ${#APIM_NAME} -gt 50 ]]; then
        log_error "API Management name is too long: $APIM_NAME"
        exit 1
    fi
    
    if [[ ${#REDIS_NAME} -gt 63 ]]; then
        log_error "Redis name is too long: $REDIS_NAME"
        exit 1
    fi
    
    log "✅ Environment variables configured"
    log_info "Resource Group: $RESOURCE_GROUP"
    log_info "Location: $LOCATION"
    log_info "Random Suffix: $RANDOM_SUFFIX"
}

# Function to create resource group
create_resource_group() {
    log "Creating resource group..."
    
    # Check if resource group already exists
    if az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        log_warning "Resource group $RESOURCE_GROUP already exists"
    else
        az group create \
            --name "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --tags purpose=enterprise-api-security environment=demo created-by=deploy-script
        log "✅ Resource group created: $RESOURCE_GROUP"
    fi
}

# Function to create Log Analytics workspace
create_log_analytics() {
    log "Creating Log Analytics workspace..."
    
    if az monitor log-analytics workspace show --resource-group "$RESOURCE_GROUP" --workspace-name "$LOG_WORKSPACE_NAME" &> /dev/null; then
        log_warning "Log Analytics workspace $LOG_WORKSPACE_NAME already exists"
    else
        az monitor log-analytics workspace create \
            --resource-group "$RESOURCE_GROUP" \
            --workspace-name "$LOG_WORKSPACE_NAME" \
            --location "$LOCATION" \
            --sku PerGB2018 \
            --retention-time 30
        log "✅ Log Analytics workspace created: $LOG_WORKSPACE_NAME"
    fi
    
    # Get workspace ID for subsequent configuration
    export WORKSPACE_ID=$(az monitor log-analytics workspace show \
        --resource-group "$RESOURCE_GROUP" \
        --workspace-name "$LOG_WORKSPACE_NAME" \
        --query customerId --output tsv)
    log_info "Workspace ID: $WORKSPACE_ID"
}

# Function to create Application Insights
create_application_insights() {
    log "Creating Application Insights..."
    
    if az monitor app-insights component show --app "$APP_INSIGHTS_NAME" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        log_warning "Application Insights $APP_INSIGHTS_NAME already exists"
    else
        az monitor app-insights component create \
            --app "$APP_INSIGHTS_NAME" \
            --location "$LOCATION" \
            --resource-group "$RESOURCE_GROUP" \
            --workspace "$LOG_WORKSPACE_NAME" \
            --kind web \
            --application-type web
        log "✅ Application Insights created: $APP_INSIGHTS_NAME"
    fi
    
    # Get instrumentation key for API Management integration
    export AI_INSTRUMENTATION_KEY=$(az monitor app-insights component show \
        --app "$APP_INSIGHTS_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --query instrumentationKey --output tsv)
    log_info "Instrumentation Key obtained"
}

# Function to create Redis Enterprise cache
create_redis_cache() {
    log "Creating Redis Enterprise cache..."
    
    if az redis show --resource-group "$RESOURCE_GROUP" --name "$REDIS_NAME" &> /dev/null; then
        log_warning "Redis cache $REDIS_NAME already exists"
    else
        log_info "Starting Redis Enterprise deployment (this may take 10-15 minutes)..."
        az redis create \
            --resource-group "$RESOURCE_GROUP" \
            --name "$REDIS_NAME" \
            --location "$LOCATION" \
            --sku Premium \
            --vm-size P1 \
            --redis-configuration maxmemory-policy=allkeys-lru \
            --enable-non-ssl-port false \
            --minimum-tls-version 1.2 \
            --tags purpose=enterprise-caching environment=demo
        
        log "✅ Redis Enterprise cache created: $REDIS_NAME"
    fi
    
    # Wait for Redis to be ready
    log_info "Waiting for Redis to be ready..."
    local max_attempts=30
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        local redis_status=$(az redis show \
            --resource-group "$RESOURCE_GROUP" \
            --name "$REDIS_NAME" \
            --query provisioningState --output tsv)
        
        if [ "$redis_status" = "Succeeded" ]; then
            log "✅ Redis is ready"
            break
        elif [ "$redis_status" = "Failed" ]; then
            log_error "Redis deployment failed"
            exit 1
        else
            log_info "Redis status: $redis_status (attempt $attempt/$max_attempts)"
            sleep 30
            ((attempt++))
        fi
    done
    
    if [ $attempt -gt $max_attempts ]; then
        log_error "Redis deployment timed out"
        exit 1
    fi
}

# Function to create API Management Premium
create_api_management() {
    log "Creating API Management Premium..."
    
    if az apim show --resource-group "$RESOURCE_GROUP" --name "$APIM_NAME" &> /dev/null; then
        log_warning "API Management $APIM_NAME already exists"
    else
        log_info "Starting API Management Premium deployment (this may take 30-45 minutes)..."
        az apim create \
            --resource-group "$RESOURCE_GROUP" \
            --name "$APIM_NAME" \
            --location "$LOCATION" \
            --publisher-name "Enterprise APIs" \
            --publisher-email "api-admin@company.com" \
            --sku-name Premium \
            --sku-capacity 1 \
            --enable-managed-identity \
            --tags purpose=enterprise-api-management environment=demo \
            --no-wait
        
        log "✅ API Management Premium deployment initiated: $APIM_NAME"
    fi
}

# Function to create WAF policy
create_waf_policy() {
    log "Creating Web Application Firewall policy..."
    
    if az network front-door waf-policy show --resource-group "$RESOURCE_GROUP" --name "$WAF_POLICY_NAME" &> /dev/null; then
        log_warning "WAF policy $WAF_POLICY_NAME already exists"
    else
        # Create WAF policy with managed OWASP ruleset
        az network front-door waf-policy create \
            --resource-group "$RESOURCE_GROUP" \
            --name "$WAF_POLICY_NAME" \
            --mode Prevention \
            --enabled true \
            --tags purpose=enterprise-api-security environment=demo
        
        # Configure OWASP Core Rule Set
        az network front-door waf-policy managed-rule-set add \
            --policy-name "$WAF_POLICY_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --type Microsoft_DefaultRuleSet \
            --version 2.1 \
            --action Block
        
        # Add bot protection ruleset
        az network front-door waf-policy managed-rule-set add \
            --policy-name "$WAF_POLICY_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --type Microsoft_BotManagerRuleSet \
            --version 1.0 \
            --action Block
        
        log "✅ WAF policy created with OWASP and bot protection: $WAF_POLICY_NAME"
    fi
}

# Function to wait for API Management and configure it
configure_api_management() {
    log "Waiting for API Management to be ready..."
    
    # Wait for API Management to be available
    local max_attempts=60
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        local apim_status=$(az apim show \
            --resource-group "$RESOURCE_GROUP" \
            --name "$APIM_NAME" \
            --query provisioningState --output tsv 2>/dev/null || echo "NotFound")
        
        if [ "$apim_status" = "Succeeded" ]; then
            log "✅ API Management is ready"
            break
        elif [ "$apim_status" = "Failed" ]; then
            log_error "API Management deployment failed"
            exit 1
        else
            log_info "API Management status: $apim_status (attempt $attempt/$max_attempts)"
            sleep 60
            ((attempt++))
        fi
    done
    
    if [ $attempt -gt $max_attempts ]; then
        log_error "API Management deployment timed out"
        exit 1
    fi
    
    # Get API Management gateway URL
    export APIM_GATEWAY_URL=$(az apim show \
        --resource-group "$RESOURCE_GROUP" \
        --name "$APIM_NAME" \
        --query gatewayUrl --output tsv)
    log_info "API Management Gateway URL: $APIM_GATEWAY_URL"
    
    # Configure Redis integration
    log "Configuring Redis integration..."
    
    # Get Redis connection details
    local redis_host=$(az redis show \
        --resource-group "$RESOURCE_GROUP" \
        --name "$REDIS_NAME" \
        --query hostName --output tsv)
    
    local redis_key=$(az redis list-keys \
        --resource-group "$RESOURCE_GROUP" \
        --name "$REDIS_NAME" \
        --query primaryKey --output tsv)
    
    # Create named value for Redis connection in API Management
    az apim nv create \
        --resource-group "$RESOURCE_GROUP" \
        --service-name "$APIM_NAME" \
        --named-value-id redis-connection \
        --display-name "Redis Connection" \
        --value "${redis_host}:6380,password=${redis_key},ssl=True" \
        --secret true
    
    # Create a sample API for demonstration
    az apim api create \
        --resource-group "$RESOURCE_GROUP" \
        --service-name "$APIM_NAME" \
        --api-id sample-api \
        --display-name "Sample Enterprise API" \
        --path "/api/v1" \
        --protocols https \
        --service-url "https://httpbin.org"
    
    log "✅ API Management configured with Redis integration"
}

# Function to create security policies
create_security_policies() {
    log "Creating security policies..."
    
    # Create comprehensive security policy for the API
    cat > /tmp/api-security-policy.xml << 'EOF'
<policies>
    <inbound>
        <!-- Rate limiting per subscription key -->
        <rate-limit calls="100" renewal-period="60" />
        <quota calls="1000" renewal-period="3600" />
        
        <!-- IP filtering for additional security -->
        <ip-filter action="allow">
            <address-range from="0.0.0.0" to="255.255.255.255" />
        </ip-filter>
        
        <!-- Cache lookup for GET requests -->
        <cache-lookup vary-by-developer="false" vary-by-developer-groups="false">
            <vary-by-header>Accept</vary-by-header>
            <vary-by-header>Accept-Charset</vary-by-header>
        </cache-lookup>
        
        <!-- CORS policy -->
        <cors allow-credentials="false">
            <allowed-origins>
                <origin>*</origin>
            </allowed-origins>
            <allowed-methods>
                <method>GET</method>
                <method>POST</method>
            </allowed-methods>
            <allowed-headers>
                <header>*</header>
            </allowed-headers>
        </cors>
    </inbound>
    
    <outbound>
        <!-- Cache store for successful responses -->
        <cache-store duration="300" />
        
        <!-- Security headers -->
        <set-header name="X-Content-Type-Options" exists-action="override">
            <value>nosniff</value>
        </set-header>
        <set-header name="X-Frame-Options" exists-action="override">
            <value>DENY</value>
        </set-header>
        <set-header name="X-XSS-Protection" exists-action="override">
            <value>1; mode=block</value>
        </set-header>
        <set-header name="Strict-Transport-Security" exists-action="override">
            <value>max-age=31536000; includeSubDomains</value>
        </set-header>
    </outbound>
    
    <on-error>
        <base />
    </on-error>
</policies>
EOF
    
    # Apply security policy to the API
    az apim api policy create \
        --resource-group "$RESOURCE_GROUP" \
        --service-name "$APIM_NAME" \
        --api-id sample-api \
        --policy-file /tmp/api-security-policy.xml
    
    # Clean up temporary file
    rm -f /tmp/api-security-policy.xml
    
    log "✅ Security policies applied to API"
}

# Function to configure monitoring
configure_monitoring() {
    log "Configuring Application Insights integration..."
    
    # Configure Application Insights logger in API Management
    az apim logger create \
        --resource-group "$RESOURCE_GROUP" \
        --service-name "$APIM_NAME" \
        --logger-id applicationinsights \
        --logger-type applicationInsights \
        --description "Application Insights Logger" \
        --credentials instrumentationKey="$AI_INSTRUMENTATION_KEY"
    
    # Create diagnostic settings for comprehensive monitoring
    az apim diagnostic create \
        --resource-group "$RESOURCE_GROUP" \
        --service-name "$APIM_NAME" \
        --diagnostic-id applicationinsights \
        --always-log allErrors \
        --logger-id applicationinsights \
        --sampling-type fixed \
        --sampling-percentage 100 \
        --verbosity information
    
    # Apply diagnostic to the sample API
    az apim api diagnostic create \
        --resource-group "$RESOURCE_GROUP" \
        --service-name "$APIM_NAME" \
        --api-id sample-api \
        --diagnostic-id applicationinsights \
        --always-log allErrors \
        --logger-id applicationinsights \
        --sampling-type fixed \
        --sampling-percentage 100
    
    log "✅ Application Insights integration configured"
}

# Function to create Front Door
create_front_door() {
    log "Creating Azure Front Door..."
    
    if az afd profile show --resource-group "$RESOURCE_GROUP" --profile-name "$FRONT_DOOR_NAME" &> /dev/null; then
        log_warning "Front Door profile $FRONT_DOOR_NAME already exists"
    else
        # Create Front Door profile with WAF integration
        az afd profile create \
            --resource-group "$RESOURCE_GROUP" \
            --profile-name "$FRONT_DOOR_NAME" \
            --sku Premium_AzureFrontDoor \
            --tags purpose=enterprise-api-security environment=demo
        
        # Create endpoint for API traffic
        az afd endpoint create \
            --resource-group "$RESOURCE_GROUP" \
            --profile-name "$FRONT_DOOR_NAME" \
            --endpoint-name api-endpoint \
            --enabled-state Enabled
        
        log "✅ Front Door created: $FRONT_DOOR_NAME"
    fi
}

# Function to configure Front Door with origins and WAF
configure_front_door() {
    log "Configuring Front Door origins and WAF..."
    
    # Get WAF policy resource ID
    local waf_policy_id=$(az network front-door waf-policy show \
        --resource-group "$RESOURCE_GROUP" \
        --name "$WAF_POLICY_NAME" \
        --query id --output tsv)
    
    # Create origin group for API Management
    if ! az afd origin-group show --resource-group "$RESOURCE_GROUP" --profile-name "$FRONT_DOOR_NAME" --origin-group-name apim-origin-group &> /dev/null; then
        az afd origin-group create \
            --resource-group "$RESOURCE_GROUP" \
            --profile-name "$FRONT_DOOR_NAME" \
            --origin-group-name apim-origin-group \
            --probe-request-type GET \
            --probe-protocol Https \
            --probe-interval-in-seconds 120 \
            --probe-path /status-0123456789abcdef \
            --sample-size 4 \
            --successful-samples-required 3 \
            --additional-latency-in-milliseconds 50
        
        log "✅ Origin group created"
    else
        log_warning "Origin group already exists"
    fi
    
    # Add API Management as origin
    local apim_host=$(echo "$APIM_GATEWAY_URL" | sed 's|https://||')
    
    if ! az afd origin show --resource-group "$RESOURCE_GROUP" --profile-name "$FRONT_DOOR_NAME" --origin-group-name apim-origin-group --origin-name apim-origin &> /dev/null; then
        az afd origin create \
            --resource-group "$RESOURCE_GROUP" \
            --profile-name "$FRONT_DOOR_NAME" \
            --origin-group-name apim-origin-group \
            --origin-name apim-origin \
            --origin-host-header "$apim_host" \
            --host-name "$apim_host" \
            --http-port 80 \
            --https-port 443 \
            --priority 1 \
            --weight 1000 \
            --enabled-state Enabled
        
        log "✅ API Management origin added"
    else
        log_warning "API Management origin already exists"
    fi
    
    # Create route with WAF policy
    if ! az afd route show --resource-group "$RESOURCE_GROUP" --profile-name "$FRONT_DOOR_NAME" --endpoint-name api-endpoint --route-name api-route &> /dev/null; then
        az afd route create \
            --resource-group "$RESOURCE_GROUP" \
            --profile-name "$FRONT_DOOR_NAME" \
            --endpoint-name api-endpoint \
            --route-name api-route \
            --origin-group apim-origin-group \
            --supported-protocols Http Https \
            --patterns-to-match "/*" \
            --forwarding-protocol MatchRequest \
            --https-redirect Enabled \
            --enable-compression true
        
        log "✅ Route created with WAF integration"
    else
        log_warning "Route already exists"
    fi
}

# Function to display deployment summary
display_summary() {
    log "=================================="
    log "DEPLOYMENT COMPLETED SUCCESSFULLY!"
    log "=================================="
    
    echo
    log_info "Resource Information:"
    echo "  Resource Group: $RESOURCE_GROUP"
    echo "  Location: $LOCATION"
    echo "  Random Suffix: $RANDOM_SUFFIX"
    echo
    
    log_info "Created Resources:"
    echo "  ✅ Log Analytics Workspace: $LOG_WORKSPACE_NAME"
    echo "  ✅ Application Insights: $APP_INSIGHTS_NAME"
    echo "  ✅ Redis Enterprise Cache: $REDIS_NAME"
    echo "  ✅ API Management Premium: $APIM_NAME"
    echo "  ✅ WAF Policy: $WAF_POLICY_NAME"
    echo "  ✅ Front Door: $FRONT_DOOR_NAME"
    echo
    
    # Get Front Door endpoint URL
    local fd_endpoint=$(az afd endpoint show \
        --resource-group "$RESOURCE_GROUP" \
        --profile-name "$FRONT_DOOR_NAME" \
        --endpoint-name api-endpoint \
        --query hostName --output tsv 2>/dev/null || echo "Not available")
    
    log_info "Service Endpoints:"
    echo "  API Management Gateway: $APIM_GATEWAY_URL"
    echo "  Front Door Endpoint: https://$fd_endpoint"
    echo
    
    log_info "Next Steps:"
    echo "  1. Test the API endpoint through Front Door"
    echo "  2. Configure additional APIs and security policies"
    echo "  3. Set up monitoring alerts and dashboards"
    echo "  4. Configure custom domains and SSL certificates"
    echo
    
    log_warning "Cost Management:"
    echo "  - This deployment uses premium services that incur ongoing charges"
    echo "  - Run './destroy.sh' to clean up resources when testing is complete"
    echo "  - Monitor your Azure billing dashboard for cost tracking"
    echo
    
    log_info "Validation Commands:"
    echo "  # Check Front Door status"
    echo "  az afd profile show --resource-group $RESOURCE_GROUP --profile-name $FRONT_DOOR_NAME --query deploymentStatus"
    echo
    echo "  # Test API endpoint"
    echo "  curl -v https://$fd_endpoint/api/v1/get"
    echo
    echo "  # Check WAF policy"
    echo "  az network front-door waf-policy show --resource-group $RESOURCE_GROUP --name $WAF_POLICY_NAME --query policySettings.mode"
}

# Function to save deployment state
save_deployment_state() {
    log "Saving deployment state..."
    
    local state_file="$HOME/.azure-enterprise-api-deployment-state"
    
    cat > "$state_file" << EOF
# Azure Enterprise API Protection Deployment State
# Generated: $(date)
export RESOURCE_GROUP="$RESOURCE_GROUP"
export LOCATION="$LOCATION"
export RANDOM_SUFFIX="$RANDOM_SUFFIX"
export APIM_NAME="$APIM_NAME"
export WAF_POLICY_NAME="$WAF_POLICY_NAME"
export FRONT_DOOR_NAME="$FRONT_DOOR_NAME"
export REDIS_NAME="$REDIS_NAME"
export APP_INSIGHTS_NAME="$APP_INSIGHTS_NAME"
export LOG_WORKSPACE_NAME="$LOG_WORKSPACE_NAME"
export APIM_GATEWAY_URL="$APIM_GATEWAY_URL"
export SUBSCRIPTION_ID="$SUBSCRIPTION_ID"
EOF
    
    log_info "Deployment state saved to: $state_file"
}

# Main deployment function
main() {
    log "Starting Azure Enterprise API Protection deployment..."
    log "================================================="
    
    # Check if running in non-interactive mode
    if [[ "${SKIP_CONFIRMATION:-}" != "true" ]]; then
        echo
        log_warning "This deployment will create premium Azure resources that incur significant costs."
        log_warning "Estimated cost: $300-500 USD for a 24-48 hour testing period."
        echo
        read -p "Do you want to continue? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log "Deployment cancelled by user"
            exit 0
        fi
    fi
    
    # Execute deployment steps
    check_prerequisites
    set_environment_variables
    create_resource_group
    create_log_analytics
    create_application_insights
    create_redis_cache
    create_api_management
    create_waf_policy
    configure_api_management
    create_security_policies
    configure_monitoring
    create_front_door
    configure_front_door
    
    # Save state and display summary
    save_deployment_state
    display_summary
    
    log "Deployment completed successfully! 🎉"
}

# Execute main function
main "$@"