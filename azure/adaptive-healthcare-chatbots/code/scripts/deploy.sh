#!/bin/bash

# ==============================================================================
# DEPLOYMENT SCRIPT: Personalized Healthcare Chatbots
# ==============================================================================
# This script deploys Azure Health Bot with Azure Personalizer integration
# for personalized healthcare chatbot experiences.
#
# Recipe: Developing Personalized Healthcare Chatbots with Azure Health Bot 
#         and Azure Personalizer
# Version: 1.0
# Estimated Time: 120 minutes
# ==============================================================================

set -euo pipefail

# Color codes for output formatting
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Logging configuration
readonly LOG_FILE="healthcare-chatbot-deploy-$(date +%Y%m%d-%H%M%S).log"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Global variables for resource tracking
declare -a CREATED_RESOURCES=()
declare -a FAILED_OPERATIONS=()

# ==============================================================================
# UTILITY FUNCTIONS
# ==============================================================================

log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${timestamp} [${level}] ${message}" | tee -a "${LOG_FILE}"
}

log_info() {
    log "INFO" "$*"
    echo -e "${BLUE}ℹ️  $*${NC}"
}

log_success() {
    log "SUCCESS" "$*"
    echo -e "${GREEN}✅ $*${NC}"
}

log_warning() {
    log "WARNING" "$*"
    echo -e "${YELLOW}⚠️  $*${NC}"
}

log_error() {
    log "ERROR" "$*"
    echo -e "${RED}❌ $*${NC}"
}

track_resource() {
    local resource_type="$1"
    local resource_name="$2"
    local resource_group="$3"
    CREATED_RESOURCES+=("${resource_type}:${resource_name}:${resource_group}")
    log_info "Tracking resource: ${resource_type}/${resource_name} in ${resource_group}"
}

cleanup_on_error() {
    log_error "Deployment failed. Initiating cleanup of created resources..."
    
    for resource in "${CREATED_RESOURCES[@]}"; do
        IFS=':' read -r type name group <<< "$resource"
        log_warning "Cleaning up ${type}: ${name}"
        
        case "$type" in
            "healthbot")
                az healthbot delete --name "$name" --resource-group "$group" --yes --no-wait 2>/dev/null || true
                ;;
            "personalizer")
                az cognitiveservices account delete --name "$name" --resource-group "$group" 2>/dev/null || true
                ;;
            "sqlmi")
                az sql mi delete --name "$name" --resource-group "$group" --yes --no-wait 2>/dev/null || true
                ;;
            "functionapp")
                az functionapp delete --name "$name" --resource-group "$group" 2>/dev/null || true
                ;;
            "apim")
                az apim delete --name "$name" --resource-group "$group" --yes --no-wait 2>/dev/null || true
                ;;
            "keyvault")
                az keyvault delete --name "$name" --resource-group "$group" 2>/dev/null || true
                ;;
            "storage")
                az storage account delete --name "$name" --resource-group "$group" --yes 2>/dev/null || true
                ;;
            "vnet")
                az network vnet delete --name "$name" --resource-group "$group" 2>/dev/null || true
                ;;
        esac
    done
    
    log_error "Cleanup completed. Check logs for details: ${LOG_FILE}"
    exit 1
}

# Set error trap
trap cleanup_on_error ERR

# ==============================================================================
# PREREQUISITE CHECKS
# ==============================================================================

check_prerequisites() {
    log_info "Checking deployment prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        log_error "Azure CLI is not installed. Please install Azure CLI and try again."
        exit 1
    fi
    
    # Check Azure CLI version
    local az_version=$(az version --query '"azure-cli"' -o tsv)
    log_info "Azure CLI version: ${az_version}"
    
    # Check if logged in to Azure
    if ! az account show &> /dev/null; then
        log_error "Not logged in to Azure. Please run 'az login' and try again."
        exit 1
    fi
    
    # Check if required utilities are available
    for cmd in jq openssl curl; do
        if ! command -v "$cmd" &> /dev/null; then
            log_error "Required utility '$cmd' is not installed."
            exit 1
        fi
    done
    
    # Check subscription permissions
    local subscription_id=$(az account show --query id --output tsv)
    log_info "Using subscription: ${subscription_id}"
    
    # Verify required resource providers are registered
    local providers=("Microsoft.HealthBot" "Microsoft.CognitiveServices" "Microsoft.Sql" "Microsoft.Web" "Microsoft.ApiManagement" "Microsoft.KeyVault")
    
    for provider in "${providers[@]}"; do
        local state=$(az provider show --namespace "$provider" --query registrationState --output tsv 2>/dev/null || echo "NotRegistered")
        if [[ "$state" != "Registered" ]]; then
            log_warning "Registering provider: $provider"
            az provider register --namespace "$provider" --wait
        fi
    done
    
    log_success "Prerequisites check completed successfully"
}

# ==============================================================================
# ENVIRONMENT SETUP
# ==============================================================================

setup_environment() {
    log_info "Setting up deployment environment..."
    
    # Set default values
    export RESOURCE_GROUP="${RESOURCE_GROUP:-rg-healthcare-chatbot}"
    export LOCATION="${LOCATION:-eastus}"
    export SUBSCRIPTION_ID=$(az account show --query id --output tsv)
    
    # Generate unique suffix for resource names
    if [[ -z "${RANDOM_SUFFIX:-}" ]]; then
        export RANDOM_SUFFIX=$(openssl rand -hex 3)
        log_info "Generated random suffix: ${RANDOM_SUFFIX}"
    fi
    
    # Set service-specific variables
    export HEALTH_BOT_NAME="${HEALTH_BOT_NAME:-healthbot-${RANDOM_SUFFIX}}"
    export PERSONALIZER_NAME="${PERSONALIZER_NAME:-personalizer-${RANDOM_SUFFIX}}"
    export SQL_MI_NAME="${SQL_MI_NAME:-sqlmi-${RANDOM_SUFFIX}}"
    export KEYVAULT_NAME="${KEYVAULT_NAME:-kv-${RANDOM_SUFFIX}}"
    export FUNCTION_APP_NAME="${FUNCTION_APP_NAME:-func-${RANDOM_SUFFIX}}"
    export APIM_NAME="${APIM_NAME:-apim-${RANDOM_SUFFIX}}"
    export STORAGE_ACCOUNT_NAME="st${RANDOM_SUFFIX}"
    export VNET_NAME="vnet-sqlmi"
    export SUBNET_NAME="subnet-sqlmi"
    
    # Save environment variables to file for cleanup script
    cat > "${SCRIPT_DIR}/.env" << EOF
RESOURCE_GROUP=${RESOURCE_GROUP}
LOCATION=${LOCATION}
SUBSCRIPTION_ID=${SUBSCRIPTION_ID}
RANDOM_SUFFIX=${RANDOM_SUFFIX}
HEALTH_BOT_NAME=${HEALTH_BOT_NAME}
PERSONALIZER_NAME=${PERSONALIZER_NAME}
SQL_MI_NAME=${SQL_MI_NAME}
KEYVAULT_NAME=${KEYVAULT_NAME}
FUNCTION_APP_NAME=${FUNCTION_APP_NAME}
APIM_NAME=${APIM_NAME}
STORAGE_ACCOUNT_NAME=${STORAGE_ACCOUNT_NAME}
VNET_NAME=${VNET_NAME}
SUBNET_NAME=${SUBNET_NAME}
EOF
    
    log_info "Environment variables configured:"
    log_info "  Resource Group: ${RESOURCE_GROUP}"
    log_info "  Location: ${LOCATION}"
    log_info "  Random Suffix: ${RANDOM_SUFFIX}"
    
    log_success "Environment setup completed"
}

# ==============================================================================
# RESOURCE DEPLOYMENT FUNCTIONS
# ==============================================================================

create_resource_group() {
    log_info "Creating resource group: ${RESOURCE_GROUP}"
    
    if az group show --name "${RESOURCE_GROUP}" &> /dev/null; then
        log_warning "Resource group ${RESOURCE_GROUP} already exists"
    else
        az group create \
            --name "${RESOURCE_GROUP}" \
            --location "${LOCATION}" \
            --tags purpose=healthcare-chatbot environment=development compliance=hipaa
        
        track_resource "resourcegroup" "${RESOURCE_GROUP}" "${RESOURCE_GROUP}"
        log_success "Resource group created: ${RESOURCE_GROUP}"
    fi
}

create_key_vault() {
    log_info "Creating Key Vault: ${KEYVAULT_NAME}"
    
    if az keyvault show --name "${KEYVAULT_NAME}" &> /dev/null; then
        log_warning "Key Vault ${KEYVAULT_NAME} already exists"
    else
        az keyvault create \
            --name "${KEYVAULT_NAME}" \
            --resource-group "${RESOURCE_GROUP}" \
            --location "${LOCATION}" \
            --sku standard \
            --enable-rbac-authorization true
        
        track_resource "keyvault" "${KEYVAULT_NAME}" "${RESOURCE_GROUP}"
        log_success "Key Vault created for secure credential storage"
    fi
}

create_health_bot() {
    log_info "Creating Azure Health Bot instance: ${HEALTH_BOT_NAME}"
    
    if az healthbot show --name "${HEALTH_BOT_NAME}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        log_warning "Health Bot ${HEALTH_BOT_NAME} already exists"
    else
        az healthbot create \
            --name "${HEALTH_BOT_NAME}" \
            --resource-group "${RESOURCE_GROUP}" \
            --location "${LOCATION}" \
            --sku F0 \
            --tags environment=development purpose=patient-engagement
        
        track_resource "healthbot" "${HEALTH_BOT_NAME}" "${RESOURCE_GROUP}"
        
        # Get Health Bot management portal URL
        local health_bot_url=$(az healthbot show \
            --name "${HEALTH_BOT_NAME}" \
            --resource-group "${RESOURCE_GROUP}" \
            --query properties.botManagementPortalLink \
            --output tsv)
        
        log_success "Azure Health Bot created successfully"
        log_info "Management Portal: ${health_bot_url}"
        
        # Save URL to environment file
        echo "HEALTH_BOT_URL=${health_bot_url}" >> "${SCRIPT_DIR}/.env"
    fi
}

create_personalizer() {
    log_info "Creating Azure Personalizer service: ${PERSONALIZER_NAME}"
    
    if az cognitiveservices account show --name "${PERSONALIZER_NAME}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        log_warning "Personalizer service ${PERSONALIZER_NAME} already exists"
    else
        az cognitiveservices account create \
            --name "${PERSONALIZER_NAME}" \
            --resource-group "${RESOURCE_GROUP}" \
            --location "${LOCATION}" \
            --kind Personalizer \
            --sku S0 \
            --custom-domain "${PERSONALIZER_NAME}"
        
        track_resource "personalizer" "${PERSONALIZER_NAME}" "${RESOURCE_GROUP}"
        
        # Retrieve Personalizer endpoint and key
        local personalizer_endpoint=$(az cognitiveservices account show \
            --name "${PERSONALIZER_NAME}" \
            --resource-group "${RESOURCE_GROUP}" \
            --query properties.endpoint \
            --output tsv)
        
        local personalizer_key=$(az cognitiveservices account keys list \
            --name "${PERSONALIZER_NAME}" \
            --resource-group "${RESOURCE_GROUP}" \
            --query key1 \
            --output tsv)
        
        log_success "Azure Personalizer service deployed successfully"
        log_info "Endpoint: ${personalizer_endpoint}"
        
        # Save credentials to Key Vault
        az keyvault secret set \
            --vault-name "${KEYVAULT_NAME}" \
            --name "PersonalizerEndpoint" \
            --value "${personalizer_endpoint}" > /dev/null
        
        az keyvault secret set \
            --vault-name "${KEYVAULT_NAME}" \
            --name "PersonalizerKey" \
            --value "${personalizer_key}" > /dev/null
        
        # Save to environment file
        echo "PERSONALIZER_ENDPOINT=${personalizer_endpoint}" >> "${SCRIPT_DIR}/.env"
        echo "PERSONALIZER_KEY=${personalizer_key}" >> "${SCRIPT_DIR}/.env"
    fi
}

create_network_infrastructure() {
    log_info "Creating network infrastructure for SQL Managed Instance"
    
    # Create virtual network
    if az network vnet show --name "${VNET_NAME}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        log_warning "Virtual network ${VNET_NAME} already exists"
    else
        az network vnet create \
            --name "${VNET_NAME}" \
            --resource-group "${RESOURCE_GROUP}" \
            --location "${LOCATION}" \
            --address-prefix 10.0.0.0/16
        
        track_resource "vnet" "${VNET_NAME}" "${RESOURCE_GROUP}"
        log_success "Virtual network created: ${VNET_NAME}"
    fi
    
    # Create subnet for SQL Managed Instance
    if az network vnet subnet show --name "${SUBNET_NAME}" --vnet-name "${VNET_NAME}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        log_warning "Subnet ${SUBNET_NAME} already exists"
    else
        az network vnet subnet create \
            --name "${SUBNET_NAME}" \
            --resource-group "${RESOURCE_GROUP}" \
            --vnet-name "${VNET_NAME}" \
            --address-prefix 10.0.1.0/24 \
            --delegations Microsoft.Sql/managedInstances
        
        log_success "Subnet created for SQL Managed Instance: ${SUBNET_NAME}"
    fi
}

create_sql_managed_instance() {
    log_info "Creating Azure SQL Managed Instance: ${SQL_MI_NAME}"
    log_warning "SQL Managed Instance deployment will take 4-6 hours to complete"
    
    if az sql mi show --name "${SQL_MI_NAME}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        log_warning "SQL Managed Instance ${SQL_MI_NAME} already exists"
    else
        # Generate strong password
        local sql_password="ComplexP@ssw0rd$(openssl rand -hex 4)!"
        
        az sql mi create \
            --name "${SQL_MI_NAME}" \
            --resource-group "${RESOURCE_GROUP}" \
            --location "${LOCATION}" \
            --admin-user sqladmin \
            --admin-password "${sql_password}" \
            --subnet "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.Network/virtualNetworks/${VNET_NAME}/subnets/${SUBNET_NAME}" \
            --capacity 4 \
            --edition GeneralPurpose \
            --family Gen5 \
            --storage 32GB \
            --no-wait
        
        track_resource "sqlmi" "${SQL_MI_NAME}" "${RESOURCE_GROUP}"
        
        # Save SQL credentials to Key Vault
        az keyvault secret set \
            --vault-name "${KEYVAULT_NAME}" \
            --name "SqlAdminPassword" \
            --value "${sql_password}" > /dev/null
        
        # Save to environment file
        local sql_connection_string="Server=${SQL_MI_NAME}.database.windows.net;Database=HealthBotDB;User Id=sqladmin;Password=${sql_password};Encrypt=true;TrustServerCertificate=false;"
        echo "SQL_CONNECTION_STRING=${sql_connection_string}" >> "${SCRIPT_DIR}/.env"
        
        log_success "SQL Managed Instance deployment initiated"
        log_info "Note: Deployment will take 4-6 hours to complete"
    fi
}

create_storage_account() {
    log_info "Creating storage account: ${STORAGE_ACCOUNT_NAME}"
    
    if az storage account show --name "${STORAGE_ACCOUNT_NAME}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        log_warning "Storage account ${STORAGE_ACCOUNT_NAME} already exists"
    else
        az storage account create \
            --name "${STORAGE_ACCOUNT_NAME}" \
            --resource-group "${RESOURCE_GROUP}" \
            --location "${LOCATION}" \
            --sku Standard_LRS \
            --kind StorageV2
        
        track_resource "storage" "${STORAGE_ACCOUNT_NAME}" "${RESOURCE_GROUP}"
        log_success "Storage account created: ${STORAGE_ACCOUNT_NAME}"
    fi
}

create_function_app() {
    log_info "Creating Function App: ${FUNCTION_APP_NAME}"
    
    if az functionapp show --name "${FUNCTION_APP_NAME}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        log_warning "Function App ${FUNCTION_APP_NAME} already exists"
    else
        az functionapp create \
            --name "${FUNCTION_APP_NAME}" \
            --resource-group "${RESOURCE_GROUP}" \
            --storage-account "${STORAGE_ACCOUNT_NAME}" \
            --consumption-plan-location "${LOCATION}" \
            --runtime dotnet \
            --functions-version 4 \
            --os-type Windows
        
        track_resource "functionapp" "${FUNCTION_APP_NAME}" "${RESOURCE_GROUP}"
        
        # Get Personalizer credentials from environment
        local personalizer_endpoint=$(grep "PERSONALIZER_ENDPOINT" "${SCRIPT_DIR}/.env" | cut -d'=' -f2)
        local personalizer_key=$(grep "PERSONALIZER_KEY" "${SCRIPT_DIR}/.env" | cut -d'=' -f2)
        local sql_connection_string=$(grep "SQL_CONNECTION_STRING" "${SCRIPT_DIR}/.env" | cut -d'=' -f2)
        
        # Configure Function App settings
        az functionapp config appsettings set \
            --name "${FUNCTION_APP_NAME}" \
            --resource-group "${RESOURCE_GROUP}" \
            --settings \
            "PersonalizerEndpoint=${personalizer_endpoint}" \
            "PersonalizerKey=${personalizer_key}" \
            "SqlConnectionString=${sql_connection_string}"
        
        log_success "Function App configured for Health Bot integration"
    fi
}

create_api_management() {
    log_info "Creating API Management service: ${APIM_NAME}"
    log_warning "API Management deployment will take 30-45 minutes"
    
    if az apim show --name "${APIM_NAME}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        log_warning "API Management service ${APIM_NAME} already exists"
    else
        az apim create \
            --name "${APIM_NAME}" \
            --resource-group "${RESOURCE_GROUP}" \
            --location "${LOCATION}" \
            --publisher-name "Healthcare Organization" \
            --publisher-email "admin@healthcare.org" \
            --sku-name Developer \
            --enable-managed-identity true
        
        track_resource "apim" "${APIM_NAME}" "${RESOURCE_GROUP}"
        
        # Configure API Management policies for healthcare compliance
        local policy_xml='<policies>
            <inbound>
                <rate-limit calls="100" renewal-period="60" />
                <cors allow-credentials="true">
                    <allowed-origins>
                        <origin>*</origin>
                    </allowed-origins>
                    <allowed-methods>
                        <method>GET</method>
                        <method>POST</method>
                    </allowed-methods>
                </cors>
            </inbound>
            <outbound>
                <set-header name="X-Healthcare-Disclaimer" exists-action="override">
                    <value>This chatbot provides general information only. Consult healthcare professionals for medical advice.</value>
                </set-header>
            </outbound>
        </policies>'
        
        az apim policy create \
            --resource-group "${RESOURCE_GROUP}" \
            --service-name "${APIM_NAME}" \
            --policy-format xml \
            --value "${policy_xml}"
        
        log_success "API Management service configured with healthcare policies"
    fi
}

create_health_bot_scenarios() {
    log_info "Creating Health Bot scenarios configuration"
    
    # Create scenario configuration JSON
    cat > "${SCRIPT_DIR}/scenario-config.json" << 'EOF'
{
    "scenarios": [
        {
            "name": "PersonalizedTriage",
            "description": "Personalized patient triage with AI recommendations",
            "triggers": ["help", "symptoms", "feeling unwell"],
            "actions": [
                {
                    "type": "PersonalizerRank",
                    "endpoint": "https://func-REPLACE_SUFFIX.azurewebsites.net/api/GetPersonalizedContent",
                    "context": {
                        "age": "user.age",
                        "location": "user.location",
                        "previousInteractions": "user.history"
                    }
                },
                {
                    "type": "Statement",
                    "text": "Based on your profile, here's personalized health guidance..."
                }
            ]
        }
    ]
}
EOF
    
    # Replace suffix in scenario configuration
    sed -i "s/REPLACE_SUFFIX/${RANDOM_SUFFIX}/g" "${SCRIPT_DIR}/scenario-config.json"
    
    log_success "Health Bot scenarios configured for personalization"
    log_info "Scenario configuration created: ${SCRIPT_DIR}/scenario-config.json"
}

create_database_schema() {
    log_info "Creating database schema configuration"
    
    # Create SQL script for database schema
    cat > "${SCRIPT_DIR}/create-schema.sql" << 'EOF'
CREATE DATABASE HealthBotDB;
GO

USE HealthBotDB;
GO

CREATE TABLE PatientInteractions (
    InteractionId UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),
    PatientId NVARCHAR(255) NOT NULL,
    ConversationId NVARCHAR(255) NOT NULL,
    ActionSelected NVARCHAR(255),
    ContextData NVARCHAR(MAX),
    RewardScore FLOAT,
    InteractionDate DATETIME2 DEFAULT GETUTCDATE(),
    INDEX IX_PatientInteractions_PatientId (PatientId),
    INDEX IX_PatientInteractions_ConversationId (ConversationId)
);

CREATE TABLE PersonalizationPreferences (
    PreferenceId UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),
    PatientId NVARCHAR(255) NOT NULL,
    PreferenceType NVARCHAR(100),
    PreferenceValue NVARCHAR(MAX),
    LastUpdated DATETIME2 DEFAULT GETUTCDATE(),
    INDEX IX_PersonalizationPreferences_PatientId (PatientId)
);

-- Enable row-level security for HIPAA compliance
ALTER TABLE PatientInteractions ENABLE ROW_LEVEL_SECURITY;
ALTER TABLE PersonalizationPreferences ENABLE ROW_LEVEL_SECURITY;
EOF
    
    log_success "Database schema script created"
    log_info "Schema includes HIPAA-compliant patient data tables"
}

create_function_code() {
    log_info "Creating Function App integration code"
    
    # Create Function App code for Personalizer integration
    cat > "${SCRIPT_DIR}/PersonalizerIntegration.cs" << 'EOF'
using System;
using System.IO;
using System.Net.Http;
using System.Text;
using System.Threading.Tasks;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Azure.WebJobs;
using Microsoft.Azure.WebJobs.Extensions.Http;
using Microsoft.AspNetCore.Http;
using Microsoft.Extensions.Logging;
using Newtonsoft.Json;

public static class PersonalizerIntegration
{
    private static readonly HttpClient client = new HttpClient();
    
    [FunctionName("GetPersonalizedContent")]
    public static async Task<IActionResult> GetPersonalizedContent(
        [HttpTrigger(AuthorizationLevel.Function, "post", Route = null)] HttpRequest req,
        ILogger log)
    {
        try
        {
            string requestBody = await new StreamReader(req.Body).ReadToEndAsync();
            dynamic data = JsonConvert.DeserializeObject(requestBody);
            
            // Prepare context for Personalizer
            var context = new
            {
                age = data.age,
                location = data.location,
                timeOfDay = DateTime.Now.Hour,
                previousInteractions = data.previousInteractions
            };
            
            // Call Personalizer Rank API
            var rankRequest = new
            {
                contextFeatures = new[] { context },
                actions = new[]
                {
                    new { id = "symptom-checker", features = new[] { new { type = "medical-tool" } } },
                    new { id = "appointment-scheduling", features = new[] { new { type = "scheduling" } } },
                    new { id = "medication-reminder", features = new[] { new { type = "reminder" } } },
                    new { id = "health-tips", features = new[] { new { type = "educational" } } }
                },
                excludedActions = new string[] { },
                eventId = Guid.NewGuid().ToString()
            };
            
            var json = JsonConvert.SerializeObject(rankRequest);
            var content = new StringContent(json, Encoding.UTF8, "application/json");
            
            var endpoint = Environment.GetEnvironmentVariable("PersonalizerEndpoint");
            var key = Environment.GetEnvironmentVariable("PersonalizerKey");
            
            client.DefaultRequestHeaders.Clear();
            client.DefaultRequestHeaders.Add("Ocp-Apim-Subscription-Key", key);
            
            var response = await client.PostAsync($"{endpoint}/personalizer/v1.0/rank", content);
            var responseContent = await response.Content.ReadAsStringAsync();
            
            return new OkObjectResult(responseContent);
        }
        catch (Exception ex)
        {
            log.LogError($"Error in GetPersonalizedContent: {ex.Message}");
            return new BadRequestObjectResult("Error processing personalization request");
        }
    }
}
EOF
    
    log_success "Personalizer integration functions created"
}

# ==============================================================================
# DEPLOYMENT VALIDATION
# ==============================================================================

validate_deployment() {
    log_info "Validating deployment..."
    
    local validation_errors=0
    
    # Check Health Bot
    if az healthbot show --name "${HEALTH_BOT_NAME}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        log_success "Health Bot validation passed"
    else
        log_error "Health Bot validation failed"
        ((validation_errors++))
    fi
    
    # Check Personalizer
    if az cognitiveservices account show --name "${PERSONALIZER_NAME}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        log_success "Personalizer service validation passed"
    else
        log_error "Personalizer service validation failed"
        ((validation_errors++))
    fi
    
    # Check Function App
    if az functionapp show --name "${FUNCTION_APP_NAME}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        log_success "Function App validation passed"
    else
        log_error "Function App validation failed"
        ((validation_errors++))
    fi
    
    # Check Key Vault
    if az keyvault show --name "${KEYVAULT_NAME}" &> /dev/null; then
        log_success "Key Vault validation passed"
    else
        log_error "Key Vault validation failed"
        ((validation_errors++))
    fi
    
    if [[ $validation_errors -eq 0 ]]; then
        log_success "All core services deployed successfully"
        return 0
    else
        log_error "Deployment validation failed with $validation_errors errors"
        return 1
    fi
}

# ==============================================================================
# MAIN DEPLOYMENT WORKFLOW
# ==============================================================================

print_banner() {
    echo "========================================================================"
    echo "  Azure Healthcare Chatbot Deployment Script"
    echo "========================================================================"
    echo "  Recipe: Personalized Healthcare Chatbots"
    echo "  Services: Health Bot, Personalizer, SQL MI, Functions, API Management"
    echo "  Estimated Time: 120 minutes"
    echo "========================================================================"
    echo ""
}

print_deployment_summary() {
    log_info "Deployment Summary:"
    log_info "==================="
    log_info "Resource Group: ${RESOURCE_GROUP}"
    log_info "Location: ${LOCATION}"
    log_info "Random Suffix: ${RANDOM_SUFFIX}"
    echo ""
    log_info "Created Resources:"
    for resource in "${CREATED_RESOURCES[@]}"; do
        IFS=':' read -r type name group <<< "$resource"
        log_info "  - ${type}: ${name}"
    done
    echo ""
    log_info "Configuration Files Created:"
    log_info "  - Environment: ${SCRIPT_DIR}/.env"
    log_info "  - Scenarios: ${SCRIPT_DIR}/scenario-config.json"
    log_info "  - Database Schema: ${SCRIPT_DIR}/create-schema.sql"
    log_info "  - Function Code: ${SCRIPT_DIR}/PersonalizerIntegration.cs"
    echo ""
    log_info "Next Steps:"
    log_info "1. Wait for SQL Managed Instance deployment (4-6 hours)"
    log_info "2. Execute database schema using create-schema.sql"
    log_info "3. Deploy Function App code using PersonalizerIntegration.cs"
    log_info "4. Configure Health Bot scenarios using scenario-config.json"
    log_info "5. Test end-to-end integration"
    echo ""
    log_success "Deployment completed successfully!"
    log_info "Deployment log saved to: ${LOG_FILE}"
}

main() {
    print_banner
    
    # Core deployment steps
    check_prerequisites
    setup_environment
    
    # Infrastructure deployment
    create_resource_group
    create_key_vault
    create_health_bot
    create_personalizer
    create_network_infrastructure
    create_sql_managed_instance
    create_storage_account
    create_function_app
    create_api_management
    
    # Configuration files
    create_health_bot_scenarios
    create_database_schema
    create_function_code
    
    # Validation
    validate_deployment
    
    # Summary
    print_deployment_summary
}

# Run main function
main "$@"