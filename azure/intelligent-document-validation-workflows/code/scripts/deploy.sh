#!/bin/bash

# =============================================================================
# Azure Enterprise Data Validation Workflow Deployment Script
# =============================================================================
# This script deploys the complete Azure infrastructure for orchestrating
# enterprise-grade data validation workflows using Azure Dataverse and
# Azure AI Document Intelligence.
#
# Recipe: Orchestrating Enterprise-Grade Data Validation Workflows
# Services: Azure Dataverse, Azure AI Document Intelligence, Logic Apps, Power Apps
# =============================================================================

set -euo pipefail  # Exit on error, undefined vars, pipe failures

# =============================================================================
# CONFIGURATION AND VARIABLES
# =============================================================================

# Script metadata
readonly SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
readonly LOG_FILE="${SCRIPT_DIR}/deploy_${TIMESTAMP}.log"

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Default configuration
readonly DEFAULT_LOCATION="eastus"
readonly DEFAULT_SKU="S0"
readonly REQUIRED_CLI_VERSION="2.50.0"

# =============================================================================
# LOGGING AND UTILITY FUNCTIONS
# =============================================================================

log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message" | tee -a "$LOG_FILE"
}

info() {
    echo -e "${BLUE}ℹ️  $*${NC}" | tee -a "$LOG_FILE"
}

success() {
    echo -e "${GREEN}✅ $*${NC}" | tee -a "$LOG_FILE"
}

warning() {
    echo -e "${YELLOW}⚠️  $*${NC}" | tee -a "$LOG_FILE"
}

error() {
    echo -e "${RED}❌ $*${NC}" | tee -a "$LOG_FILE"
}

fatal() {
    error "$*"
    exit 1
}

# =============================================================================
# PREREQUISITE CHECKS
# =============================================================================

check_prerequisites() {
    info "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        fatal "Azure CLI is not installed. Please install Azure CLI v${REQUIRED_CLI_VERSION} or later."
    fi
    
    # Check Azure CLI version
    local cli_version
    cli_version=$(az version --query '"azure-cli"' -o tsv 2>/dev/null || echo "0.0.0")
    if [[ "$(printf '%s\n' "$REQUIRED_CLI_VERSION" "$cli_version" | sort -V | head -n1)" != "$REQUIRED_CLI_VERSION" ]]; then
        fatal "Azure CLI version $REQUIRED_CLI_VERSION or later is required. Current version: $cli_version"
    fi
    
    # Check if user is logged in to Azure
    if ! az account show &>/dev/null; then
        fatal "Please log in to Azure using 'az login' before running this script."
    fi
    
    # Check if openssl is available for random string generation
    if ! command -v openssl &> /dev/null; then
        fatal "openssl is required for generating random suffixes. Please install openssl."
    fi
    
    success "Prerequisites check completed"
}

# =============================================================================
# ENVIRONMENT SETUP
# =============================================================================

setup_environment() {
    info "Setting up environment variables..."
    
    # Generate unique suffix for resource names
    export RANDOM_SUFFIX=$(openssl rand -hex 3)
    
    # Set Azure environment variables
    export RESOURCE_GROUP="${RESOURCE_GROUP:-rg-doc-validation-${RANDOM_SUFFIX}}"
    export LOCATION="${LOCATION:-$DEFAULT_LOCATION}"
    export SUBSCRIPTION_ID=$(az account show --query id --output tsv)
    export TENANT_ID=$(az account show --query tenantId --output tsv)
    
    # Set specific resource names with generated suffix
    export DOC_INTEL_NAME="docint-${RANDOM_SUFFIX}"
    export LOGIC_APP_NAME="logic-docvalidation-${RANDOM_SUFFIX}"
    export STORAGE_ACCOUNT="stdocval${RANDOM_SUFFIX}"
    export KEYVAULT_NAME="kv-docval-${RANDOM_SUFFIX}"
    export LOG_ANALYTICS_NAME="law-docvalidation-${RANDOM_SUFFIX}"
    export APP_INSIGHTS_NAME="ai-docvalidation-${RANDOM_SUFFIX}"
    
    # Power Platform environment variables
    export POWER_PLATFORM_ENV="${POWER_PLATFORM_ENV:-DocValidationProd}"
    export DATAVERSE_URL="${DATAVERSE_URL:-https://orgname.crm.dynamics.com}"
    
    # Log environment configuration
    log "INFO" "Environment configuration:"
    log "INFO" "  Resource Group: $RESOURCE_GROUP"
    log "INFO" "  Location: $LOCATION"
    log "INFO" "  Subscription ID: $SUBSCRIPTION_ID"
    log "INFO" "  Random Suffix: $RANDOM_SUFFIX"
    
    success "Environment setup completed"
}

# =============================================================================
# RESOURCE GROUP CREATION
# =============================================================================

create_resource_group() {
    info "Creating resource group..."
    
    if az group show --name "$RESOURCE_GROUP" &>/dev/null; then
        warning "Resource group '$RESOURCE_GROUP' already exists. Using existing group."
    else
        az group create \
            --name "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --tags purpose=document-validation environment=production \
            --output none
        
        success "Resource group created: $RESOURCE_GROUP"
    fi
}

# =============================================================================
# STORAGE ACCOUNT CREATION
# =============================================================================

create_storage_account() {
    info "Creating storage account..."
    
    # Check if storage account already exists
    if az storage account show --name "$STORAGE_ACCOUNT" --resource-group "$RESOURCE_GROUP" &>/dev/null; then
        warning "Storage account '$STORAGE_ACCOUNT' already exists. Using existing account."
    else
        az storage account create \
            --name "$STORAGE_ACCOUNT" \
            --resource-group "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --sku Standard_LRS \
            --kind StorageV2 \
            --access-tier Hot \
            --https-only true \
            --allow-blob-public-access false \
            --output none
        
        success "Storage account created: $STORAGE_ACCOUNT"
    fi
    
    # Create training data container
    info "Creating training data container..."
    az storage container create \
        --name training-data \
        --account-name "$STORAGE_ACCOUNT" \
        --public-access off \
        --auth-mode login \
        --output none
    
    success "Training data container created"
}

# =============================================================================
# AZURE AI DOCUMENT INTELLIGENCE SERVICE
# =============================================================================

create_document_intelligence() {
    info "Creating Azure AI Document Intelligence service..."
    
    # Check if service already exists
    if az cognitiveservices account show --name "$DOC_INTEL_NAME" --resource-group "$RESOURCE_GROUP" &>/dev/null; then
        warning "Document Intelligence service '$DOC_INTEL_NAME' already exists. Using existing service."
    else
        az cognitiveservices account create \
            --name "$DOC_INTEL_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --kind FormRecognizer \
            --sku "$DEFAULT_SKU" \
            --tags purpose=document-processing \
            --output none
        
        success "Document Intelligence service created: $DOC_INTEL_NAME"
    fi
    
    # Get service endpoint and key
    export DOC_INTEL_ENDPOINT=$(az cognitiveservices account show \
        --name "$DOC_INTEL_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --query properties.endpoint --output tsv)
    
    export DOC_INTEL_KEY=$(az cognitiveservices account keys list \
        --name "$DOC_INTEL_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --query key1 --output tsv)
    
    info "Document Intelligence endpoint: $DOC_INTEL_ENDPOINT"
    success "Document Intelligence service configuration completed"
}

# =============================================================================
# AZURE KEY VAULT
# =============================================================================

create_key_vault() {
    info "Creating Azure Key Vault..."
    
    # Check if Key Vault already exists
    if az keyvault show --name "$KEYVAULT_NAME" --resource-group "$RESOURCE_GROUP" &>/dev/null; then
        warning "Key Vault '$KEYVAULT_NAME' already exists. Using existing vault."
    else
        az keyvault create \
            --name "$KEYVAULT_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --sku standard \
            --enabled-for-template-deployment true \
            --enable-rbac-authorization false \
            --output none
        
        success "Key Vault created: $KEYVAULT_NAME"
    fi
    
    # Store Document Intelligence credentials
    info "Storing credentials in Key Vault..."
    
    az keyvault secret set \
        --vault-name "$KEYVAULT_NAME" \
        --name "DocumentIntelligenceEndpoint" \
        --value "$DOC_INTEL_ENDPOINT" \
        --output none
    
    az keyvault secret set \
        --vault-name "$KEYVAULT_NAME" \
        --name "DocumentIntelligenceKey" \
        --value "$DOC_INTEL_KEY" \
        --output none
    
    success "Credentials stored securely in Key Vault"
}

# =============================================================================
# LOGIC APPS WORKFLOW
# =============================================================================

create_logic_app() {
    info "Creating Azure Logic Apps workflow..."
    
    # Create the Logic App workflow definition
    local workflow_definition='{
        "$schema": "https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#",
        "contentVersion": "1.0.0.0",
        "parameters": {
            "documentIntelligenceEndpoint": {
                "type": "string",
                "defaultValue": "'$DOC_INTEL_ENDPOINT'"
            },
            "documentIntelligenceKey": {
                "type": "securestring"
            },
            "dataverseUrl": {
                "type": "string",
                "defaultValue": "'$DATAVERSE_URL'"
            }
        },
        "triggers": {
            "When_a_file_is_created": {
                "type": "SharePointOnline",
                "kind": "trigger",
                "inputs": {
                    "host": {
                        "connectionName": "sharepoint",
                        "operationId": "OnNewFile",
                        "apiId": "/providers/Microsoft.PowerApps/apis/sharepointonline"
                    },
                    "parameters": {
                        "dataset": "https://company.sharepoint.com/sites/documents",
                        "folderId": "Shared Documents"
                    }
                }
            }
        },
        "actions": {
            "Analyze_document": {
                "type": "Http",
                "inputs": {
                    "method": "POST",
                    "uri": "@{parameters(\"documentIntelligenceEndpoint\")}/formrecognizer/v2.1/prebuilt/invoice/analyze",
                    "headers": {
                        "Ocp-Apim-Subscription-Key": "@{parameters(\"documentIntelligenceKey\")}"
                    },
                    "body": "@triggerOutputs()"
                }
            },
            "Create_Dataverse_record": {
                "type": "CommonDataService",
                "inputs": {
                    "host": {
                        "connectionName": "commondataservice",
                        "operationId": "CreateRecord",
                        "apiId": "/providers/Microsoft.PowerApps/apis/commondataservice"
                    },
                    "parameters": {
                        "entityName": "new_documents",
                        "item": {
                            "new_documentname": "@{body(\"Analyze_document\")[\"analyzeResult\"][\"documents\"][0][\"fields\"][\"InvoiceId\"][\"value\"]}",
                            "new_extracteddata": "@{string(body(\"Analyze_document\"))}"
                        }
                    }
                }
            }
        }
    }'
    
    # Check if Logic App already exists
    if az logic workflow show --name "$LOGIC_APP_NAME" --resource-group "$RESOURCE_GROUP" &>/dev/null; then
        warning "Logic App '$LOGIC_APP_NAME' already exists. Updating definition."
        
        az logic workflow update \
            --name "$LOGIC_APP_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --definition "$workflow_definition" \
            --output none
    else
        az logic workflow create \
            --name "$LOGIC_APP_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --definition "$workflow_definition" \
            --output none
    fi
    
    success "Logic App workflow created/updated: $LOGIC_APP_NAME"
}

# =============================================================================
# MONITORING AND ALERTING
# =============================================================================

create_monitoring() {
    info "Setting up monitoring and alerting..."
    
    # Create Log Analytics workspace
    if az monitor log-analytics workspace show --resource-group "$RESOURCE_GROUP" --workspace-name "$LOG_ANALYTICS_NAME" &>/dev/null; then
        warning "Log Analytics workspace '$LOG_ANALYTICS_NAME' already exists. Using existing workspace."
    else
        az monitor log-analytics workspace create \
            --resource-group "$RESOURCE_GROUP" \
            --workspace-name "$LOG_ANALYTICS_NAME" \
            --location "$LOCATION" \
            --sku PerGB2018 \
            --output none
        
        success "Log Analytics workspace created: $LOG_ANALYTICS_NAME"
    fi
    
    # Create Application Insights
    if az monitor app-insights component show --app "$APP_INSIGHTS_NAME" --resource-group "$RESOURCE_GROUP" &>/dev/null; then
        warning "Application Insights '$APP_INSIGHTS_NAME' already exists. Using existing component."
    else
        az monitor app-insights component create \
            --app "$APP_INSIGHTS_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --kind web \
            --application-type web \
            --output none
        
        success "Application Insights created: $APP_INSIGHTS_NAME"
    fi
    
    # Create alert rule for failed document processing
    local alert_name="Document Processing Failures"
    if az monitor metrics alert show --name "$alert_name" --resource-group "$RESOURCE_GROUP" &>/dev/null; then
        warning "Alert rule '$alert_name' already exists. Skipping creation."
    else
        az monitor metrics alert create \
            --name "$alert_name" \
            --resource-group "$RESOURCE_GROUP" \
            --scopes "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Logic/workflows/$LOGIC_APP_NAME" \
            --condition "count static microsoft.logic/workflows runsfailed > 5" \
            --window-size 5m \
            --evaluation-frequency 1m \
            --severity 2 \
            --description "Alert when document processing fails more than 5 times" \
            --output none
        
        success "Alert rule created: $alert_name"
    fi
}

# =============================================================================
# VALIDATION CONFIGURATION
# =============================================================================

create_validation_config() {
    info "Creating validation configuration files..."
    
    # Create validation rules configuration
    cat > "${SCRIPT_DIR}/validation-rules.json" << 'EOF'
{
    "invoiceValidation": {
        "requiredFields": ["invoiceNumber", "vendorName", "totalAmount"],
        "businessRules": [
            {
                "rule": "totalAmount > 0",
                "errorMessage": "Invoice total must be greater than zero"
            },
            {
                "rule": "invoiceNumber.length > 0",
                "errorMessage": "Invoice number is required"
            },
            {
                "rule": "vendorName.length > 0",
                "errorMessage": "Vendor name is required"
            }
        ],
        "approvalThreshold": 1000
    },
    "contractValidation": {
        "requiredFields": ["contractNumber", "parties", "effectiveDate"],
        "businessRules": [
            {
                "rule": "effectiveDate != null",
                "errorMessage": "Effective date is required"
            },
            {
                "rule": "parties.length >= 2",
                "errorMessage": "At least two parties required"
            }
        ],
        "approvalThreshold": 10000
    }
}
EOF
    
    # Create Power Apps configuration
    cat > "${SCRIPT_DIR}/powerapp-config.json" << 'EOF'
{
    "appName": "Document Validation App",
    "version": "1.0",
    "description": "Enterprise document validation and approval interface",
    "screens": [
        {
            "name": "DocumentReview",
            "purpose": "Review extracted document data",
            "controls": ["DataCard", "Gallery", "Button", "TextInput"],
            "dataSource": "Dataverse",
            "permissions": ["Read", "Write"]
        },
        {
            "name": "ApprovalDashboard",
            "purpose": "Manage pending approvals",
            "controls": ["Gallery", "Chart", "Filter", "SearchBox"],
            "dataSource": "Dataverse",
            "permissions": ["Read", "Approve"]
        },
        {
            "name": "ReportsView",
            "purpose": "View processing analytics",
            "controls": ["Chart", "Table", "DatePicker"],
            "dataSource": "Dataverse",
            "permissions": ["Read"]
        }
    ],
    "connections": [
        {
            "name": "SharePoint",
            "purpose": "Document source"
        },
        {
            "name": "Dataverse",
            "purpose": "Data storage and business logic"
        },
        {
            "name": "LogicApps",
            "purpose": "Workflow orchestration"
        }
    ]
}
EOF
    
    success "Validation configuration files created"
}

# =============================================================================
# DEPLOYMENT SUMMARY
# =============================================================================

display_deployment_summary() {
    info "Deployment Summary"
    echo "===========================================" | tee -a "$LOG_FILE"
    echo "Resource Group: $RESOURCE_GROUP" | tee -a "$LOG_FILE"
    echo "Location: $LOCATION" | tee -a "$LOG_FILE"
    echo "Random Suffix: $RANDOM_SUFFIX" | tee -a "$LOG_FILE"
    echo "" | tee -a "$LOG_FILE"
    echo "Created Resources:" | tee -a "$LOG_FILE"
    echo "  • Storage Account: $STORAGE_ACCOUNT" | tee -a "$LOG_FILE"
    echo "  • Document Intelligence: $DOC_INTEL_NAME" | tee -a "$LOG_FILE"
    echo "  • Key Vault: $KEYVAULT_NAME" | tee -a "$LOG_FILE"
    echo "  • Logic App: $LOGIC_APP_NAME" | tee -a "$LOG_FILE"
    echo "  • Log Analytics: $LOG_ANALYTICS_NAME" | tee -a "$LOG_FILE"
    echo "  • Application Insights: $APP_INSIGHTS_NAME" | tee -a "$LOG_FILE"
    echo "" | tee -a "$LOG_FILE"
    echo "Next Steps:" | tee -a "$LOG_FILE"
    echo "  1. Configure Power Platform environment: $POWER_PLATFORM_ENV" | tee -a "$LOG_FILE"
    echo "  2. Set up SharePoint document library connections" | tee -a "$LOG_FILE"
    echo "  3. Configure Dataverse custom tables and business rules" | tee -a "$LOG_FILE"
    echo "  4. Build Power Apps validation interface" | tee -a "$LOG_FILE"
    echo "  5. Test end-to-end document processing workflow" | tee -a "$LOG_FILE"
    echo "" | tee -a "$LOG_FILE"
    echo "Configuration files created in: $SCRIPT_DIR" | tee -a "$LOG_FILE"
    echo "Log file: $LOG_FILE" | tee -a "$LOG_FILE"
    echo "===========================================" | tee -a "$LOG_FILE"
}

# =============================================================================
# MAIN DEPLOYMENT FUNCTION
# =============================================================================

main() {
    echo "=========================================="
    echo "Azure Enterprise Data Validation Workflow"
    echo "Deployment Script v1.0"
    echo "=========================================="
    echo ""
    
    # Check if running in dry-run mode
    if [[ "${1:-}" == "--dry-run" ]]; then
        info "Running in dry-run mode. No resources will be created."
        export DRY_RUN=true
    fi
    
    # Initialize log file
    echo "Deployment started at $(date)" > "$LOG_FILE"
    
    # Execute deployment steps
    check_prerequisites
    setup_environment
    create_resource_group
    create_storage_account
    create_document_intelligence
    create_key_vault
    create_logic_app
    create_monitoring
    create_validation_config
    
    # Display summary
    display_deployment_summary
    
    success "Deployment completed successfully!"
    success "Log file saved to: $LOG_FILE"
    
    warning "Important: Manual configuration required for:"
    warning "  • Power Platform environment setup"
    warning "  • Dataverse custom tables and business rules"
    warning "  • SharePoint document library connections"
    warning "  • Power Apps interface development"
}

# =============================================================================
# SCRIPT EXECUTION
# =============================================================================

# Handle script interruption
trap 'error "Script interrupted. Check log file: $LOG_FILE"; exit 1' INT TERM

# Execute main function with all arguments
main "$@"