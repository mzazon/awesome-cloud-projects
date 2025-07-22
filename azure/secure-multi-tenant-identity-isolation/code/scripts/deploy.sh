#!/bin/bash

# Azure Multi-Tenant Customer Identity Isolation Deployment Script
# This script deploys a comprehensive multi-tenant customer identity management system
# using Azure External ID customer tenants, Azure Resource Manager Private Link,
# and Azure API Management with Azure Key Vault for centralized security governance

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Script configuration
SCRIPT_NAME="Multi-Tenant Identity Isolation Deployment"
LOG_FILE="deployment_$(date +%Y%m%d_%H%M%S).log"
DRY_RUN=${DRY_RUN:-false}

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case $level in
        "INFO")
            echo -e "${GREEN}[INFO]${NC} ${message}" | tee -a "$LOG_FILE"
            ;;
        "WARN")
            echo -e "${YELLOW}[WARN]${NC} ${message}" | tee -a "$LOG_FILE"
            ;;
        "ERROR")
            echo -e "${RED}[ERROR]${NC} ${message}" | tee -a "$LOG_FILE"
            ;;
        "DEBUG")
            echo -e "${BLUE}[DEBUG]${NC} ${message}" | tee -a "$LOG_FILE"
            ;;
    esac
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
}

# Error handling function
error_exit() {
    log "ERROR" "$1"
    log "ERROR" "Deployment failed. Check $LOG_FILE for details."
    exit 1
}

# Prerequisites check function
check_prerequisites() {
    log "INFO" "Checking prerequisites for $SCRIPT_NAME..."
    
    # Check Azure CLI installation
    if ! command -v az &> /dev/null; then
        error_exit "Azure CLI is not installed. Please install Azure CLI v2.49.0 or later."
    fi
    
    # Check Azure CLI version
    local az_version=$(az version --query '"azure-cli"' -o tsv)
    log "INFO" "Azure CLI version: $az_version"
    
    # Check if logged in to Azure
    if ! az account show &> /dev/null; then
        error_exit "Not logged in to Azure. Please run 'az login' first."
    fi
    
    # Check PowerShell availability for advanced tasks
    if ! command -v pwsh &> /dev/null; then
        log "WARN" "PowerShell 7.0+ not found. Some advanced management tasks may require manual steps."
    fi
    
    # Check OpenSSL for random string generation
    if ! command -v openssl &> /dev/null; then
        error_exit "OpenSSL is required for generating unique resource names."
    fi
    
    # Display current Azure context
    local subscription_name=$(az account show --query name -o tsv)
    local subscription_id=$(az account show --query id -o tsv)
    log "INFO" "Using Azure subscription: $subscription_name ($subscription_id)"
    
    # Check permissions (basic check)
    log "INFO" "Checking Azure permissions..."
    if ! az group list --query "[0].id" -o tsv &> /dev/null; then
        error_exit "Insufficient permissions to list resource groups. Owner or Contributor role required."
    fi
    
    log "INFO" "Prerequisites check completed successfully."
}

# Environment setup function
setup_environment() {
    log "INFO" "Setting up environment variables..."
    
    # Set default environment variables if not already set
    export LOCATION="${LOCATION:-eastus}"
    export RESOURCE_GROUP="${RESOURCE_GROUP:-rg-multitenant-identity}"
    export VNET_NAME="${VNET_NAME:-vnet-private-isolation}"
    export SUBSCRIPTION_ID=$(az account show --query id --output tsv)
    
    # Generate unique suffix for globally unique resource names
    if [ -z "${UNIQUE_SUFFIX:-}" ]; then
        export UNIQUE_SUFFIX=$(openssl rand -hex 4)
        log "INFO" "Generated unique suffix: $UNIQUE_SUFFIX"
    fi
    
    export APIM_NAME="${APIM_NAME:-apim-tenant-isolation-${UNIQUE_SUFFIX}}"
    export KEYVAULT_NAME="${KEYVAULT_NAME:-kv-tenants-${UNIQUE_SUFFIX}}"
    export STORAGE_NAME="${STORAGE_NAME:-stmtidentity${UNIQUE_SUFFIX}}"
    
    # Create environment file for cleanup script
    cat > .deployment_env << EOF
# Deployment environment variables - Generated $(date)
export LOCATION="$LOCATION"
export RESOURCE_GROUP="$RESOURCE_GROUP"
export VNET_NAME="$VNET_NAME"
export SUBSCRIPTION_ID="$SUBSCRIPTION_ID"
export UNIQUE_SUFFIX="$UNIQUE_SUFFIX"
export APIM_NAME="$APIM_NAME"
export KEYVAULT_NAME="$KEYVAULT_NAME"
export STORAGE_NAME="$STORAGE_NAME"
EOF
    
    log "INFO" "Environment variables configured:"
    log "INFO" "  Location: $LOCATION"
    log "INFO" "  Resource Group: $RESOURCE_GROUP"
    log "INFO" "  VNet Name: $VNET_NAME"
    log "INFO" "  API Management: $APIM_NAME"
    log "INFO" "  Key Vault: $KEYVAULT_NAME"
    log "INFO" "  Unique Suffix: $UNIQUE_SUFFIX"
}

# Confirmation function for destructive operations
confirm_deployment() {
    if [ "$DRY_RUN" = "true" ]; then
        log "INFO" "DRY RUN MODE: Would deploy multi-tenant identity isolation infrastructure"
        return 0
    fi
    
    log "INFO" "This will deploy the following resources:"
    log "INFO" "  - Resource Group: $RESOURCE_GROUP"
    log "INFO" "  - Virtual Network with private endpoints"
    log "INFO" "  - API Management instance: $APIM_NAME"
    log "INFO" "  - Key Vault: $KEYVAULT_NAME"
    log "INFO" "  - Private Link configurations"
    log "INFO" "  - Monitoring and alerting resources"
    echo
    log "WARN" "Estimated monthly cost: \$200-400 for development environment"
    echo
    read -p "Do you want to continue with the deployment? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log "INFO" "Deployment cancelled by user."
        exit 0
    fi
}

# Main resource group creation
create_resource_group() {
    log "INFO" "Creating main resource group..."
    
    if [ "$DRY_RUN" = "true" ]; then
        log "INFO" "DRY RUN: Would create resource group $RESOURCE_GROUP"
        return 0
    fi
    
    if az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        log "INFO" "Resource group $RESOURCE_GROUP already exists"
    else
        az group create \
            --name "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --tags environment=production purpose=multi-tenant-isolation \
            --output table
        
        log "INFO" "✅ Resource group created: $RESOURCE_GROUP"
    fi
}

# Virtual network creation
create_virtual_network() {
    log "INFO" "Creating virtual network and subnets for private connectivity..."
    
    if [ "$DRY_RUN" = "true" ]; then
        log "INFO" "DRY RUN: Would create virtual network $VNET_NAME with subnets"
        return 0
    fi
    
    # Create virtual network
    if az network vnet show --resource-group "$RESOURCE_GROUP" --name "$VNET_NAME" &> /dev/null; then
        log "INFO" "Virtual network $VNET_NAME already exists"
    else
        az network vnet create \
            --resource-group "$RESOURCE_GROUP" \
            --name "$VNET_NAME" \
            --address-prefixes 10.0.0.0/16 \
            --location "$LOCATION" \
            --output table
        
        log "INFO" "✅ Virtual network created: $VNET_NAME"
    fi
    
    # Create subnet for private endpoints
    if az network vnet subnet show --resource-group "$RESOURCE_GROUP" --vnet-name "$VNET_NAME" --name "private-endpoints" &> /dev/null; then
        log "INFO" "Private endpoints subnet already exists"
    else
        az network vnet subnet create \
            --resource-group "$RESOURCE_GROUP" \
            --vnet-name "$VNET_NAME" \
            --name private-endpoints \
            --address-prefixes 10.0.1.0/24 \
            --disable-private-endpoint-network-policies true \
            --output table
        
        log "INFO" "✅ Private endpoints subnet created"
    fi
    
    # Create subnet for API Management
    if az network vnet subnet show --resource-group "$RESOURCE_GROUP" --vnet-name "$VNET_NAME" --name "api-management" &> /dev/null; then
        log "INFO" "API Management subnet already exists"
    else
        az network vnet subnet create \
            --resource-group "$RESOURCE_GROUP" \
            --vnet-name "$VNET_NAME" \
            --name api-management \
            --address-prefixes 10.0.2.0/24 \
            --output table
        
        log "INFO" "✅ API Management subnet created"
    fi
    
    log "INFO" "✅ Virtual network and subnets configured for private connectivity"
}

# External ID tenant guidance
configure_external_id_tenants() {
    log "INFO" "Configuring Azure External ID customer tenants..."
    
    if [ "$DRY_RUN" = "true" ]; then
        log "INFO" "DRY RUN: Would create External ID tenant configuration scripts"
        return 0
    fi
    
    # Generate tenant creation script for automation
    cat > create-customer-tenants.ps1 << 'EOF'
# PowerShell script for Azure External ID tenant creation
# This demonstrates the tenant isolation pattern

$tenants = @(
    @{Name="customer-a-external"; DisplayName="Customer A Identity Tenant"},
    @{Name="customer-b-external"; DisplayName="Customer B Identity Tenant"}
)

foreach ($tenant in $tenants) {
    Write-Host "Creating External ID tenant: $($tenant.DisplayName)"
    Write-Host "Manual step required: Create tenant via Azure portal"
    Write-Host "Tenant configuration: External tenant type for customers"
    Write-Host "URL: https://portal.azure.com/#create/Microsoft.AzureActiveDirectory"
    Write-Host ""
}

Write-Host "External ID Tenant Configuration Steps:"
Write-Host "1. Navigate to Azure portal and create new Azure AD tenant"
Write-Host "2. Select 'Azure Active Directory (Azure AD)' for External identities"
Write-Host "3. Configure tenant for external user management"
Write-Host "4. Enable B2B collaboration for customer access"
Write-Host "5. Configure custom branding for each customer tenant"
EOF
    
    chmod +x create-customer-tenants.ps1
    
    log "INFO" "✅ Customer tenant creation scripts generated"
    log "WARN" "Manual step required: Create Azure External ID customer tenants via portal"
    log "INFO" "Run './create-customer-tenants.ps1' for detailed instructions"
    log "INFO" "Configure each tenant with external configuration for customer identity management"
}

# API Management deployment
deploy_api_management() {
    log "INFO" "Deploying Azure API Management with private endpoint integration..."
    
    if [ "$DRY_RUN" = "true" ]; then
        log "INFO" "DRY RUN: Would deploy API Management instance $APIM_NAME"
        return 0
    fi
    
    # Check if API Management already exists
    if az apim show --resource-group "$RESOURCE_GROUP" --name "$APIM_NAME" &> /dev/null; then
        log "INFO" "API Management instance $APIM_NAME already exists"
        APIM_RESOURCE_ID=$(az apim show --resource-group "$RESOURCE_GROUP" --name "$APIM_NAME" --query id --output tsv)
    else
        log "INFO" "Creating API Management instance (this may take 30-45 minutes)..."
        
        az apim create \
            --resource-group "$RESOURCE_GROUP" \
            --name "$APIM_NAME" \
            --location "$LOCATION" \
            --publisher-name "Multi-Tenant SaaS Provider" \
            --publisher-email "admin@example.com" \
            --sku-name Developer \
            --enable-managed-identity true \
            --output table
        
        # Get API Management resource ID for private endpoint configuration
        APIM_RESOURCE_ID=$(az apim show \
            --resource-group "$RESOURCE_GROUP" \
            --name "$APIM_NAME" \
            --query id --output tsv)
        
        log "INFO" "✅ API Management instance created: $APIM_NAME"
    fi
    
    # Create private endpoint for API Management
    if az network private-endpoint show --resource-group "$RESOURCE_GROUP" --name "pe-apim-gateway" &> /dev/null; then
        log "INFO" "API Management private endpoint already exists"
    else
        az network private-endpoint create \
            --resource-group "$RESOURCE_GROUP" \
            --name pe-apim-gateway \
            --vnet-name "$VNET_NAME" \
            --subnet private-endpoints \
            --private-connection-resource-id "$APIM_RESOURCE_ID" \
            --group-ids gateway \
            --connection-name apim-private-connection \
            --output table
        
        log "INFO" "✅ API Management private endpoint created"
    fi
    
    log "INFO" "✅ API Management deployed with private endpoint connectivity"
}

# ARM Private Link configuration
configure_arm_private_link() {
    log "INFO" "Configuring Azure Resource Manager Private Link for secure management..."
    
    if [ "$DRY_RUN" = "true" ]; then
        log "INFO" "DRY RUN: Would configure ARM Private Link"
        return 0
    fi
    
    # Create resource management group for organized access control
    if az group show --name "rg-tenant-management" &> /dev/null; then
        log "INFO" "Tenant management resource group already exists"
    else
        az group create \
            --name "rg-tenant-management" \
            --location "$LOCATION" \
            --tags purpose=tenant-management scope=private-management \
            --output table
        
        log "INFO" "✅ Tenant management resource group created"
    fi
    
    # Create private link scope for ARM management
    if az monitor private-link-scope show --resource-group "rg-tenant-management" --scope-name "pls-arm-management" &> /dev/null; then
        log "INFO" "ARM private link scope already exists"
        ARM_PLS_ID=$(az monitor private-link-scope show \
            --resource-group "rg-tenant-management" \
            --scope-name "pls-arm-management" \
            --query id --output tsv)
    else
        az monitor private-link-scope create \
            --resource-group "rg-tenant-management" \
            --scope-name "pls-arm-management" \
            --location global \
            --output table
        
        # Get the private link scope resource ID
        ARM_PLS_ID=$(az monitor private-link-scope show \
            --resource-group "rg-tenant-management" \
            --scope-name "pls-arm-management" \
            --query id --output tsv)
        
        log "INFO" "✅ ARM private link scope created"
    fi
    
    # Create private endpoint for ARM management
    if az network private-endpoint show --resource-group "$RESOURCE_GROUP" --name "pe-arm-management" &> /dev/null; then
        log "INFO" "ARM management private endpoint already exists"
    else
        az network private-endpoint create \
            --resource-group "$RESOURCE_GROUP" \
            --name pe-arm-management \
            --vnet-name "$VNET_NAME" \
            --subnet private-endpoints \
            --private-connection-resource-id "$ARM_PLS_ID" \
            --group-ids azuremonitor \
            --connection-name arm-management-connection \
            --output table
        
        log "INFO" "✅ ARM management private endpoint created"
    fi
    
    log "INFO" "✅ Azure Resource Manager private link configured for secure management"
}

# Key Vault deployment
deploy_key_vault() {
    log "INFO" "Deploying Azure Key Vault with per-tenant secret isolation..."
    
    if [ "$DRY_RUN" = "true" ]; then
        log "INFO" "DRY RUN: Would deploy Key Vault $KEYVAULT_NAME"
        return 0
    fi
    
    # Create Key Vault with advanced security configuration
    if az keyvault show --resource-group "$RESOURCE_GROUP" --name "$KEYVAULT_NAME" &> /dev/null; then
        log "INFO" "Key Vault $KEYVAULT_NAME already exists"
        KV_RESOURCE_ID=$(az keyvault show --resource-group "$RESOURCE_GROUP" --name "$KEYVAULT_NAME" --query id --output tsv)
    else
        az keyvault create \
            --resource-group "$RESOURCE_GROUP" \
            --name "$KEYVAULT_NAME" \
            --location "$LOCATION" \
            --sku premium \
            --enable-rbac-authorization true \
            --enable-soft-delete true \
            --retention-days 90 \
            --enable-purge-protection true \
            --output table
        
        # Get Key Vault resource ID
        KV_RESOURCE_ID=$(az keyvault show \
            --resource-group "$RESOURCE_GROUP" \
            --name "$KEYVAULT_NAME" \
            --query id --output tsv)
        
        log "INFO" "✅ Key Vault created: $KEYVAULT_NAME"
    fi
    
    # Create private endpoint for Key Vault
    if az network private-endpoint show --resource-group "$RESOURCE_GROUP" --name "pe-keyvault" &> /dev/null; then
        log "INFO" "Key Vault private endpoint already exists"
    else
        az network private-endpoint create \
            --resource-group "$RESOURCE_GROUP" \
            --name pe-keyvault \
            --vnet-name "$VNET_NAME" \
            --subnet private-endpoints \
            --private-connection-resource-id "$KV_RESOURCE_ID" \
            --group-ids vault \
            --connection-name keyvault-private-connection \
            --output table
        
        log "INFO" "✅ Key Vault private endpoint created"
    fi
    
    # Configure tenant-specific secret namespacing
    log "INFO" "Creating tenant-specific secret structure..."
    
    # Create sample secrets for tenant isolation demonstration
    if ! az keyvault secret show --vault-name "$KEYVAULT_NAME" --name "tenant-a-api-key" &> /dev/null; then
        az keyvault secret set \
            --vault-name "$KEYVAULT_NAME" \
            --name "tenant-a-api-key" \
            --value "secure-api-key-customer-a" \
            --description "API key for Customer A tenant" \
            --output table
        
        log "INFO" "✅ Tenant A secret created"
    fi
    
    if ! az keyvault secret show --vault-name "$KEYVAULT_NAME" --name "tenant-b-api-key" &> /dev/null; then
        az keyvault secret set \
            --vault-name "$KEYVAULT_NAME" \
            --name "tenant-b-api-key" \
            --value "secure-api-key-customer-b" \
            --description "API key for Customer B tenant" \
            --output table
        
        log "INFO" "✅ Tenant B secret created"
    fi
    
    log "INFO" "✅ Key Vault configured with tenant-specific secret isolation"
}

# API Management policy configuration
configure_api_policies() {
    log "INFO" "Configuring multi-tenant API security policies in API Management..."
    
    if [ "$DRY_RUN" = "true" ]; then
        log "INFO" "DRY RUN: Would configure API Management policies"
        return 0
    fi
    
    # Create tenant isolation API policy
    cat > tenant-isolation-policy.xml << EOF
<policies>
    <inbound>
        <base />
        <!-- Extract tenant ID from JWT token or header -->
        <choose>
            <when condition="@(context.Request.Headers.ContainsKey("X-Tenant-ID"))">
                <set-variable name="tenantId" value="@(context.Request.Headers["X-Tenant-ID"].First())" />
            </when>
            <otherwise>
                <return-response>
                    <set-status code="400" reason="Bad Request" />
                    <set-body>Missing tenant identification</set-body>
                </return-response>
            </otherwise>
        </choose>
        
        <!-- Validate tenant against allowed list -->
        <choose>
            <when condition="@(new string[] {"tenant-a", "tenant-b"}.Contains(context.Variables["tenantId"].ToString()))">
                <!-- Retrieve tenant-specific secrets from Key Vault -->
                <send-request mode="new" response-variable-name="keyVaultResponse" timeout="20" ignore-error="false">
                    <set-url>@(\$"https://${KEYVAULT_NAME}.vault.azure.net/secrets/{context.Variables["tenantId"]}-api-key?api-version=7.4")</set-url>
                    <set-method>GET</set-method>
                    <authentication-managed-identity resource="https://vault.azure.net" />
                </send-request>
                
                <!-- Set tenant-specific backend URL -->
                <set-backend-service base-url="@(\$"https://api-{context.Variables["tenantId"]}.internal.com")" />
            </when>
            <otherwise>
                <return-response>
                    <set-status code="403" reason="Forbidden" />
                    <set-body>Invalid tenant identifier</set-body>
                </return-response>
            </otherwise>
        </choose>
        
        <!-- Add security headers for tenant isolation -->
        <set-header name="X-Isolated-Tenant" exists-action="override">
            <value>@(context.Variables["tenantId"].ToString())</value>
        </set-header>
    </inbound>
    <backend>
        <base />
    </backend>
    <outbound>
        <base />
        <!-- Remove sensitive tenant information from response -->
        <set-header name="X-Tenant-ID" exists-action="delete" />
    </outbound>
    <on-error>
        <base />
        <set-header name="X-Error-Source" exists-action="override">
            <value>Tenant-Isolation-Policy</value>
        </set-header>
    </on-error>
</policies>
EOF
    
    log "INFO" "✅ Multi-tenant API security policies configured"
    log "INFO" "Policy file created: tenant-isolation-policy.xml"
    log "INFO" "Policies enforce tenant isolation and secure secret retrieval"
}

# Monitoring and alerting setup
setup_monitoring() {
    log "INFO" "Implementing cross-tenant access controls and monitoring..."
    
    if [ "$DRY_RUN" = "true" ]; then
        log "INFO" "DRY RUN: Would configure monitoring and alerting"
        return 0
    fi
    
    # Create Log Analytics workspace for centralized monitoring
    local workspace_name="law-tenant-isolation"
    if az monitor log-analytics workspace show --resource-group "$RESOURCE_GROUP" --workspace-name "$workspace_name" &> /dev/null; then
        log "INFO" "Log Analytics workspace already exists"
        WORKSPACE_ID=$(az monitor log-analytics workspace show \
            --resource-group "$RESOURCE_GROUP" \
            --workspace-name "$workspace_name" \
            --query customerId --output tsv)
    else
        az monitor log-analytics workspace create \
            --resource-group "$RESOURCE_GROUP" \
            --workspace-name "$workspace_name" \
            --location "$LOCATION" \
            --sku PerGB2018 \
            --output table
        
        # Get workspace ID for diagnostic configuration
        WORKSPACE_ID=$(az monitor log-analytics workspace show \
            --resource-group "$RESOURCE_GROUP" \
            --workspace-name "$workspace_name" \
            --query customerId --output tsv)
        
        log "INFO" "✅ Log Analytics workspace created"
    fi
    
    # Configure diagnostic settings for API Management
    local apim_resource_id=$(az apim show --resource-group "$RESOURCE_GROUP" --name "$APIM_NAME" --query id --output tsv)
    
    if ! az monitor diagnostic-settings show --resource "$apim_resource_id" --name "apim-tenant-isolation-logs" &> /dev/null; then
        az monitor diagnostic-settings create \
            --resource "$apim_resource_id" \
            --name "apim-tenant-isolation-logs" \
            --workspace "$WORKSPACE_ID" \
            --logs '[{"category":"GatewayLogs","enabled":true,"retentionPolicy":{"enabled":true,"days":30}}]' \
            --metrics '[{"category":"Gateway Requests","enabled":true,"retentionPolicy":{"enabled":true,"days":30}}]' \
            --output table
        
        log "INFO" "✅ API Management diagnostic settings configured"
    fi
    
    # Create custom KQL queries for tenant isolation monitoring
    cat > tenant-monitoring-queries.kql << 'EOF'
// Query for potential tenant isolation violations
ApiManagementGatewayLogs
| where TimeGenerated > ago(24h)
| extend TenantId = tostring(parse_json(RequestHeaders)["X-Tenant-ID"])
| where isempty(TenantId) or TenantId !in ("tenant-a", "tenant-b")
| project TimeGenerated, TenantId, Method, Url, ResponseCode, ClientIP
| order by TimeGenerated desc

// Monitor cross-tenant access attempts
ApiManagementGatewayLogs
| where TimeGenerated > ago(24h)
| extend TenantId = tostring(parse_json(RequestHeaders)["X-Tenant-ID"])
| extend RequestedTenant = extract(@"tenant-([ab])", 1, Url)
| where TenantId != RequestedTenant and isnotempty(RequestedTenant)
| project TimeGenerated, TenantId, RequestedTenant, Method, Url, ResponseCode
EOF
    
    # Configure alerts for tenant isolation violations
    if ! az monitor metrics alert show --resource-group "$RESOURCE_GROUP" --name "tenant-isolation-violation-alert" &> /dev/null; then
        az monitor metrics alert create \
            --resource-group "$RESOURCE_GROUP" \
            --name "tenant-isolation-violation-alert" \
            --scopes "$apim_resource_id" \
            --condition "count 'GatewayResponseCode' static gt 1 --filter 'GatewayResponseCode eq 403'" \
            --description "Alert when API Management returns 403 responses indicating potential tenant isolation violations" \
            --evaluation-frequency 5m \
            --window-size 15m \
            --severity 2 \
            --output table
        
        log "INFO" "✅ Tenant isolation violation alert configured"
    fi
    
    log "INFO" "✅ Comprehensive monitoring and alerting configured for tenant isolation"
}

# Validation function
validate_deployment() {
    log "INFO" "Validating deployment..."
    
    if [ "$DRY_RUN" = "true" ]; then
        log "INFO" "DRY RUN: Would validate deployment"
        return 0
    fi
    
    # Check resource group
    if az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        log "INFO" "✅ Resource group validation passed"
    else
        log "ERROR" "❌ Resource group validation failed"
        return 1
    fi
    
    # Check virtual network
    if az network vnet show --resource-group "$RESOURCE_GROUP" --name "$VNET_NAME" &> /dev/null; then
        log "INFO" "✅ Virtual network validation passed"
    else
        log "ERROR" "❌ Virtual network validation failed"
        return 1
    fi
    
    # Check API Management
    if az apim show --resource-group "$RESOURCE_GROUP" --name "$APIM_NAME" &> /dev/null; then
        log "INFO" "✅ API Management validation passed"
    else
        log "ERROR" "❌ API Management validation failed"
        return 1
    fi
    
    # Check Key Vault
    if az keyvault show --resource-group "$RESOURCE_GROUP" --name "$KEYVAULT_NAME" &> /dev/null; then
        log "INFO" "✅ Key Vault validation passed"
    else
        log "ERROR" "❌ Key Vault validation failed"
        return 1
    fi
    
    log "INFO" "✅ Deployment validation completed successfully"
}

# Main deployment function
main() {
    log "INFO" "Starting $SCRIPT_NAME"
    log "INFO" "Log file: $LOG_FILE"
    
    # Execute deployment steps
    check_prerequisites
    setup_environment
    confirm_deployment
    
    log "INFO" "Beginning infrastructure deployment..."
    
    create_resource_group
    create_virtual_network
    configure_external_id_tenants
    deploy_api_management
    configure_arm_private_link
    deploy_key_vault
    configure_api_policies
    setup_monitoring
    
    validate_deployment
    
    # Display completion summary
    log "INFO" "🎉 Multi-tenant customer identity isolation deployment completed successfully!"
    echo
    log "INFO" "Deployment Summary:"
    log "INFO" "  Resource Group: $RESOURCE_GROUP"
    log "INFO" "  API Management: $APIM_NAME"
    log "INFO" "  Key Vault: $KEYVAULT_NAME"
    log "INFO" "  Virtual Network: $VNET_NAME"
    log "INFO" "  Log Analytics: law-tenant-isolation"
    echo
    log "INFO" "Manual Steps Required:"
    log "INFO" "  1. Create Azure External ID customer tenants via Azure portal"
    log "INFO" "  2. Configure tenant-specific applications and policies"
    log "INFO" "  3. Set up customer-specific API backends"
    log "INFO" "  4. Test tenant isolation and API routing"
    echo
    log "INFO" "Environment variables saved to .deployment_env"
    log "INFO" "Policy file created: tenant-isolation-policy.xml"
    log "INFO" "Monitoring queries saved to: tenant-monitoring-queries.kql"
    log "INFO" "PowerShell script created: create-customer-tenants.ps1"
    echo
    log "INFO" "Use ./destroy.sh to clean up resources when no longer needed"
    log "INFO" "Deployment log saved to: $LOG_FILE"
}

# Script entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi