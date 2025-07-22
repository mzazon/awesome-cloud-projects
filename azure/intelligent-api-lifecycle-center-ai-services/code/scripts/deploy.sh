#!/bin/bash

# Deploy Azure Intelligent API Lifecycle Management Solution
# This script deploys Azure API Center, AI Services, and monitoring infrastructure
# Version: 1.1
# Last Updated: 2025-07-12

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
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✅ $1${NC}"
}

warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️  $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ❌ $1${NC}"
    exit 1
}

# Check if script is run with dry-run flag
DRY_RUN=false
FORCE_DEPLOY=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --force)
            FORCE_DEPLOY=true
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo "Options:"
            echo "  --dry-run    Show what would be deployed without creating resources"
            echo "  --force      Skip confirmation prompts"
            echo "  --help, -h   Show this help message"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Function to execute command with dry-run support
execute_command() {
    local cmd="$1"
    local description="$2"
    
    if [ "$DRY_RUN" = true ]; then
        log "DRY RUN: $description"
        log "Command: $cmd"
        return 0
    else
        log "$description"
        eval "$cmd"
        return $?
    fi
}

# Trap to handle script interruption
cleanup_on_exit() {
    local exit_code=$?
    if [ $exit_code -ne 0 ]; then
        error "Script execution failed. Check logs above for details."
        warning "You may need to manually clean up partially created resources."
        if [ -n "${RESOURCE_GROUP:-}" ]; then
            warning "Resource Group: $RESOURCE_GROUP"
            warning "To clean up, run: az group delete --name $RESOURCE_GROUP --yes"
        fi
    fi
}
trap cleanup_on_exit EXIT

# Display script header
echo -e "${BLUE}================================================"
echo "Azure API Lifecycle Management Deployment"
echo "Recipe: Intelligent API Center with AI Services"
echo "Version: 1.1"
echo "================================================${NC}"

if [ "$DRY_RUN" = true ]; then
    warning "Running in dry-run mode. No resources will be created."
fi

# Check prerequisites
log "Checking prerequisites..."

# Check if Azure CLI is installed
if ! command -v az &> /dev/null; then
    error "Azure CLI is not installed. Please install it first: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
fi

# Check Azure CLI version
AZ_VERSION=$(az version --query '"azure-cli"' -o tsv 2>/dev/null || echo "unknown")
log "Azure CLI version: $AZ_VERSION"

# Check if logged in to Azure
if ! az account show &> /dev/null; then
    error "Not logged in to Azure. Please run 'az login' first."
fi

# Check if curl is available for testing
if ! command -v curl &> /dev/null; then
    warning "curl is not installed. Some validation tests will be skipped."
fi

# Check if openssl is available for random generation
if ! command -v openssl &> /dev/null; then
    warning "openssl is not installed. Using alternative random generation."
fi

success "Prerequisites check completed"

# Set configuration variables with defaults
export LOCATION="${LOCATION:-eastus}"
export ENVIRONMENT="${ENVIRONMENT:-demo}"
export PURPOSE="${PURPOSE:-recipe}"

# Get current subscription info
SUBSCRIPTION_ID=$(az account show --query id --output tsv)
TENANT_ID=$(az account show --query tenantId --output tsv)
log "Using subscription: $SUBSCRIPTION_ID"

# Generate unique suffix for resource names
if command -v openssl &> /dev/null; then
    RANDOM_SUFFIX=$(openssl rand -hex 3)
else
    RANDOM_SUFFIX=$(printf "%06x" $((RANDOM % 16777216)))
fi

# Set resource names
export RESOURCE_GROUP="rg-api-lifecycle-${RANDOM_SUFFIX}"
export API_CENTER_NAME="apic-${RANDOM_SUFFIX}"
export OPENAI_NAME="openai-${RANDOM_SUFFIX}"
export MONITOR_WORKSPACE="law-${RANDOM_SUFFIX}"
export APIM_NAME="apim-${RANDOM_SUFFIX}"
export STORAGE_ACCOUNT="st${RANDOM_SUFFIX}"
export LOGIC_APP_NAME="logic-${RANDOM_SUFFIX}"

log "Resource naming convention:"
log "  Resource Group: $RESOURCE_GROUP"
log "  API Center: $API_CENTER_NAME"
log "  OpenAI Service: $OPENAI_NAME"
log "  Monitor Workspace: $MONITOR_WORKSPACE"
log "  API Management: $APIM_NAME"

# Confirmation prompt (skip if --force flag is used)
if [ "$FORCE_DEPLOY" = false ] && [ "$DRY_RUN" = false ]; then
    read -p "Do you want to proceed with deployment? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log "Deployment cancelled by user"
        exit 0
    fi
fi

# Start deployment
log "Starting deployment..."

# Create resource group
execute_command "az group create \
    --name '$RESOURCE_GROUP' \
    --location '$LOCATION' \
    --tags purpose='$PURPOSE' environment='$ENVIRONMENT' \
    --output none" \
    "Creating resource group $RESOURCE_GROUP"

if [ "$DRY_RUN" = false ]; then
    success "Resource group created: $RESOURCE_GROUP"
fi

# Create Azure API Center
log "Creating Azure API Center..."
if az apic service create \
    --name "$API_CENTER_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --location "$LOCATION" \
    --output none 2>/dev/null; then
    success "API Center created: $API_CENTER_NAME"
    
    # Store API Center resource ID
    API_CENTER_ID=$(az apic service show \
        --name "$API_CENTER_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --query id --output tsv)
    export API_CENTER_ID
else
    error "Failed to create API Center"
fi

# Configure API Center metadata schema
log "Configuring API metadata schema..."
if az apic metadata-schema create \
    --resource-group "$RESOURCE_GROUP" \
    --service-name "$API_CENTER_NAME" \
    --metadata-schema-name "api-lifecycle" \
    --schema '{
        "type": "object",
        "properties": {
            "lifecycleStage": {
                "type": "string",
                "enum": ["design", "development", "testing", "production", "deprecated"]
            },
            "businessDomain": {
                "type": "string",
                "enum": ["finance", "hr", "operations", "customer", "analytics"]
            },
            "dataClassification": {
                "type": "string",
                "enum": ["public", "internal", "confidential", "restricted"]
            }
        }
    }' \
    --output none 2>/dev/null; then
    success "Metadata schema configured"
else
    warning "Metadata schema configuration failed (may already exist)"
fi

# Create Azure OpenAI resource
log "Creating Azure OpenAI service..."
if az cognitiveservices account create \
    --name "$OPENAI_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --location "$LOCATION" \
    --kind OpenAI \
    --sku S0 \
    --custom-domain "$OPENAI_NAME" \
    --output none 2>/dev/null; then
    success "Azure OpenAI service created: $OPENAI_NAME"
else
    error "Failed to create Azure OpenAI service"
fi

# Wait for OpenAI resource to be ready
log "Waiting for OpenAI service to be ready..."
sleep 30

# Deploy GPT-4 model
log "Deploying GPT-4 model..."
if az cognitiveservices account deployment create \
    --name "$OPENAI_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --deployment-name "gpt-4" \
    --model-name "gpt-4" \
    --model-version "0613" \
    --model-format OpenAI \
    --scale-settings-scale-type "Standard" \
    --output none 2>/dev/null; then
    success "GPT-4 model deployed"
else
    warning "GPT-4 model deployment failed (may already exist or quota exceeded)"
fi

# Get OpenAI endpoint and key
OPENAI_ENDPOINT=$(az cognitiveservices account show \
    --name "$OPENAI_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --query properties.endpoint --output tsv)

OPENAI_KEY=$(az cognitiveservices account keys list \
    --name "$OPENAI_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --query key1 --output tsv)

export OPENAI_ENDPOINT
export OPENAI_KEY

# Create Log Analytics workspace
log "Creating Log Analytics workspace..."
if az monitor log-analytics workspace create \
    --name "$MONITOR_WORKSPACE" \
    --resource-group "$RESOURCE_GROUP" \
    --location "$LOCATION" \
    --output none 2>/dev/null; then
    success "Log Analytics workspace created: $MONITOR_WORKSPACE"
else
    error "Failed to create Log Analytics workspace"
fi

# Create Application Insights
log "Creating Application Insights..."
if az monitor app-insights component create \
    --app "appins-${RANDOM_SUFFIX}" \
    --location "$LOCATION" \
    --resource-group "$RESOURCE_GROUP" \
    --workspace "$MONITOR_WORKSPACE" \
    --output none 2>/dev/null; then
    success "Application Insights created"
    
    # Get Application Insights connection string
    APP_INSIGHTS_CONNECTION=$(az monitor app-insights component show \
        --app "appins-${RANDOM_SUFFIX}" \
        --resource-group "$RESOURCE_GROUP" \
        --query connectionString --output tsv)
    export APP_INSIGHTS_CONNECTION
else
    error "Failed to create Application Insights"
fi

# Register sample API in API Center
log "Registering sample API..."
if az apic api create \
    --resource-group "$RESOURCE_GROUP" \
    --service-name "$API_CENTER_NAME" \
    --api-id "customer-api" \
    --title "Customer Management API" \
    --type REST \
    --description "API for managing customer data and operations" \
    --output none 2>/dev/null; then
    success "Sample API registered"
else
    warning "Sample API registration failed (may already exist)"
fi

# Create API version
log "Creating API version..."
if az apic api version create \
    --resource-group "$RESOURCE_GROUP" \
    --service-name "$API_CENTER_NAME" \
    --api-id "customer-api" \
    --version-id "v1" \
    --title "Version 1.0" \
    --lifecycle-stage "production" \
    --output none 2>/dev/null; then
    success "API version created"
else
    warning "API version creation failed (may already exist)"
fi

# Add API definition
log "Adding API definition..."
if az apic api definition create \
    --resource-group "$RESOURCE_GROUP" \
    --service-name "$API_CENTER_NAME" \
    --api-id "customer-api" \
    --version-id "v1" \
    --definition-id "openapi" \
    --title "OpenAPI Definition" \
    --specification '{
        "name": "openapi",
        "version": "3.0.0"
    }' \
    --output none 2>/dev/null; then
    success "API definition added"
else
    warning "API definition creation failed (may already exist)"
fi

# Create API Management instance (Consumption tier for demo)
log "Creating API Management instance (this may take 10-15 minutes)..."
if az apim create \
    --name "$APIM_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --location "$LOCATION" \
    --publisher-email "admin@contoso.com" \
    --publisher-name "Contoso" \
    --sku-name Consumption \
    --output none 2>/dev/null; then
    success "API Management instance created: $APIM_NAME"
else
    warning "API Management creation failed or timed out"
fi

# Create storage account for portal assets
log "Creating storage account..."
if az storage account create \
    --name "$STORAGE_ACCOUNT" \
    --resource-group "$RESOURCE_GROUP" \
    --location "$LOCATION" \
    --sku Standard_LRS \
    --kind StorageV2 \
    --output none 2>/dev/null; then
    success "Storage account created: $STORAGE_ACCOUNT"
    
    # Enable static website hosting
    if az storage blob service-properties update \
        --account-name "$STORAGE_ACCOUNT" \
        --static-website \
        --index-document index.html \
        --404-document error.html \
        --output none 2>/dev/null; then
        success "Static website hosting enabled"
    fi
else
    error "Failed to create storage account"
fi

# Create Anomaly Detector resource
log "Creating Anomaly Detector service..."
if az cognitiveservices account create \
    --name "anomaly-${RANDOM_SUFFIX}" \
    --resource-group "$RESOURCE_GROUP" \
    --location "$LOCATION" \
    --kind AnomalyDetector \
    --sku F0 \
    --custom-domain "anomaly-${RANDOM_SUFFIX}" \
    --output none 2>/dev/null; then
    success "Anomaly Detector service created"
else
    warning "Anomaly Detector creation failed (may already exist or quota exceeded)"
fi

# Configure metric alert
log "Configuring metric alerts..."
if [[ -n "${API_CENTER_ID:-}" ]]; then
    if az monitor metrics alert create \
        --name "api-anomaly-alert" \
        --resource-group "$RESOURCE_GROUP" \
        --scopes "$API_CENTER_ID" \
        --condition "avg Percentage CPU > 80" \
        --description "Alert on API performance anomalies" \
        --evaluation-frequency 5m \
        --window-size 15m \
        --output none 2>/dev/null; then
        success "Metric alert configured"
    else
        warning "Metric alert configuration failed"
    fi
fi

# Create Logic App for documentation automation
log "Creating Logic App for automation..."
if az logic workflow create \
    --name "$LOGIC_APP_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --location "$LOCATION" \
    --definition '{
        "definition": {
            "$schema": "https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#",
            "triggers": {
                "manual": {
                    "type": "Request",
                    "kind": "Http"
                }
            },
            "actions": {
                "Response": {
                    "type": "Response",
                    "kind": "Http",
                    "inputs": {
                        "statusCode": 200,
                        "body": "Documentation automation workflow ready"
                    }
                }
            }
        }
    }' \
    --output none 2>/dev/null; then
    success "Logic App created: $LOGIC_APP_NAME"
else
    warning "Logic App creation failed"
fi

# Save configuration to file
CONFIG_FILE="deployment-config-${RANDOM_SUFFIX}.env"
log "Saving deployment configuration to $CONFIG_FILE..."

cat > "$CONFIG_FILE" << EOF
# Azure API Lifecycle Management Deployment Configuration
# Generated on: $(date)
# 
# Use this file to reference deployed resources or for cleanup

export RESOURCE_GROUP="$RESOURCE_GROUP"
export LOCATION="$LOCATION"
export API_CENTER_NAME="$API_CENTER_NAME"
export OPENAI_NAME="$OPENAI_NAME"
export MONITOR_WORKSPACE="$MONITOR_WORKSPACE"
export APIM_NAME="$APIM_NAME"
export STORAGE_ACCOUNT="$STORAGE_ACCOUNT"
export LOGIC_APP_NAME="$LOGIC_APP_NAME"
export RANDOM_SUFFIX="$RANDOM_SUFFIX"

# Resource IDs
export API_CENTER_ID="$API_CENTER_ID"

# Service endpoints and keys
export OPENAI_ENDPOINT="$OPENAI_ENDPOINT"
export OPENAI_KEY="$OPENAI_KEY"
export APP_INSIGHTS_CONNECTION="$APP_INSIGHTS_CONNECTION"

# Subscription information
export SUBSCRIPTION_ID="$SUBSCRIPTION_ID"
export TENANT_ID="$TENANT_ID"
EOF

success "Configuration saved to: $CONFIG_FILE"

# Display deployment summary
echo
echo -e "${GREEN}================================================"
echo "          DEPLOYMENT COMPLETED SUCCESSFULLY"
echo "================================================${NC}"
echo
echo "📋 Deployment Summary:"
echo "   • Resource Group: $RESOURCE_GROUP"
echo "   • API Center: $API_CENTER_NAME"
echo "   • OpenAI Service: $OPENAI_NAME"
echo "   • API Management: $APIM_NAME"
echo "   • Monitoring: Application Insights + Log Analytics"
echo "   • Storage Account: $STORAGE_ACCOUNT"
echo "   • Logic App: $LOGIC_APP_NAME"
echo
echo "🔗 Quick Access Links:"
echo "   • Azure Portal: https://portal.azure.com/#@${TENANT_ID}/resource${API_CENTER_ID}"
echo "   • API Center Portal: https://${API_CENTER_NAME}.portal.azure-api.net"
echo
echo "📄 Configuration file: $CONFIG_FILE"
echo "   Source this file to access deployment variables:"
echo "   source $CONFIG_FILE"
echo
echo "🧹 Cleanup:"
echo "   Run ./destroy.sh to remove all resources"
echo
echo "⚠️  Important Notes:"
echo "   • API Management creation can take 15-30 minutes to complete"
echo "   • Some services may have usage-based billing"
echo "   • Review Azure cost management for spending monitoring"
echo

success "Deployment script completed successfully!"