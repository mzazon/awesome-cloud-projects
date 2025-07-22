#!/bin/bash

# Azure Multi-Language Content Localization Workflow Deployment Script
# This script deploys the complete localization workflow with Azure Translator and Document Intelligence

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

error() {
    echo -e "${RED}[ERROR] $1${NC}" >&2
}

success() {
    echo -e "${GREEN}[SUCCESS] $1${NC}"
}

warning() {
    echo -e "${YELLOW}[WARNING] $1${NC}"
}

# Check if running in dry-run mode
DRY_RUN=false
if [[ "$1" == "--dry-run" ]]; then
    DRY_RUN=true
    warning "Running in dry-run mode - no resources will be created"
fi

# Function to execute commands with dry-run support
execute_command() {
    local cmd="$1"
    log "Executing: $cmd"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "[DRY-RUN] Would execute: $cmd"
        return 0
    else
        eval "$cmd"
        return $?
    fi
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        error "Azure CLI is not installed. Please install it from https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
        exit 1
    fi
    
    # Check if user is logged in
    if ! az account show &> /dev/null; then
        error "Please log in to Azure CLI using 'az login'"
        exit 1
    fi
    
    # Check if jq is installed for JSON processing
    if ! command -v jq &> /dev/null; then
        error "jq is not installed. Please install it for JSON processing"
        exit 1
    fi
    
    # Check if openssl is available for random string generation
    if ! command -v openssl &> /dev/null; then
        error "openssl is not installed. Please install it for random string generation"
        exit 1
    fi
    
    success "All prerequisites met"
}

# Function to set environment variables
set_environment_variables() {
    log "Setting environment variables..."
    
    # Set default values if not already set
    export RESOURCE_GROUP="${RESOURCE_GROUP:-rg-localization-workflow}"
    export LOCATION="${LOCATION:-eastus}"
    export STORAGE_ACCOUNT="${STORAGE_ACCOUNT:-st$(openssl rand -hex 6)}"
    export TRANSLATOR_NAME="${TRANSLATOR_NAME:-translator-$(openssl rand -hex 4)}"
    export DOC_INTELLIGENCE_NAME="${DOC_INTELLIGENCE_NAME:-doc-intel-$(openssl rand -hex 4)}"
    export LOGIC_APP_NAME="${LOGIC_APP_NAME:-logic-localization-$(openssl rand -hex 4)}"
    
    # Display configuration
    log "Configuration:"
    log "  Resource Group: $RESOURCE_GROUP"
    log "  Location: $LOCATION"
    log "  Storage Account: $STORAGE_ACCOUNT"
    log "  Translator Name: $TRANSLATOR_NAME"
    log "  Document Intelligence Name: $DOC_INTELLIGENCE_NAME"
    log "  Logic App Name: $LOGIC_APP_NAME"
}

# Function to create resource group
create_resource_group() {
    log "Creating resource group..."
    
    execute_command "az group create \
        --name $RESOURCE_GROUP \
        --location $LOCATION \
        --tags project=localization environment=demo"
    
    if [[ $? -eq 0 ]]; then
        success "Resource group created: $RESOURCE_GROUP"
    else
        error "Failed to create resource group"
        exit 1
    fi
}

# Function to create storage account
create_storage_account() {
    log "Creating storage account..."
    
    execute_command "az storage account create \
        --name $STORAGE_ACCOUNT \
        --resource-group $RESOURCE_GROUP \
        --location $LOCATION \
        --sku Standard_LRS \
        --kind StorageV2 \
        --enable-hierarchical-namespace false"
    
    if [[ $? -eq 0 ]]; then
        success "Storage account created: $STORAGE_ACCOUNT"
        
        # Get storage account key
        if [[ "$DRY_RUN" == "false" ]]; then
            export STORAGE_KEY=$(az storage account keys list \
                --resource-group $RESOURCE_GROUP \
                --account-name $STORAGE_ACCOUNT \
                --query '[0].value' --output tsv)
            
            if [[ -z "$STORAGE_KEY" ]]; then
                error "Failed to retrieve storage account key"
                exit 1
            fi
        fi
    else
        error "Failed to create storage account"
        exit 1
    fi
}

# Function to create Azure Translator service
create_translator_service() {
    log "Creating Azure Translator service..."
    
    execute_command "az cognitiveservices account create \
        --name $TRANSLATOR_NAME \
        --resource-group $RESOURCE_GROUP \
        --location $LOCATION \
        --kind TextTranslation \
        --sku S1 \
        --custom-domain $TRANSLATOR_NAME"
    
    if [[ $? -eq 0 ]]; then
        success "Translator service created: $TRANSLATOR_NAME"
        
        # Get Translator credentials
        if [[ "$DRY_RUN" == "false" ]]; then
            export TRANSLATOR_KEY=$(az cognitiveservices account keys list \
                --name $TRANSLATOR_NAME \
                --resource-group $RESOURCE_GROUP \
                --query 'key1' --output tsv)
            
            export TRANSLATOR_ENDPOINT=$(az cognitiveservices account show \
                --name $TRANSLATOR_NAME \
                --resource-group $RESOURCE_GROUP \
                --query 'properties.endpoint' --output tsv)
            
            if [[ -z "$TRANSLATOR_KEY" || -z "$TRANSLATOR_ENDPOINT" ]]; then
                error "Failed to retrieve Translator credentials"
                exit 1
            fi
            
            log "Translator endpoint: $TRANSLATOR_ENDPOINT"
        fi
    else
        error "Failed to create Translator service"
        exit 1
    fi
}

# Function to create Document Intelligence service
create_document_intelligence_service() {
    log "Creating Document Intelligence service..."
    
    execute_command "az cognitiveservices account create \
        --name $DOC_INTELLIGENCE_NAME \
        --resource-group $RESOURCE_GROUP \
        --location $LOCATION \
        --kind FormRecognizer \
        --sku S0 \
        --custom-domain $DOC_INTELLIGENCE_NAME"
    
    if [[ $? -eq 0 ]]; then
        success "Document Intelligence service created: $DOC_INTELLIGENCE_NAME"
        
        # Get Document Intelligence credentials
        if [[ "$DRY_RUN" == "false" ]]; then
            export DOC_INTEL_KEY=$(az cognitiveservices account keys list \
                --name $DOC_INTELLIGENCE_NAME \
                --resource-group $RESOURCE_GROUP \
                --query 'key1' --output tsv)
            
            export DOC_INTEL_ENDPOINT=$(az cognitiveservices account show \
                --name $DOC_INTELLIGENCE_NAME \
                --resource-group $RESOURCE_GROUP \
                --query 'properties.endpoint' --output tsv)
            
            if [[ -z "$DOC_INTEL_KEY" || -z "$DOC_INTEL_ENDPOINT" ]]; then
                error "Failed to retrieve Document Intelligence credentials"
                exit 1
            fi
            
            log "Document Intelligence endpoint: $DOC_INTEL_ENDPOINT"
        fi
    else
        error "Failed to create Document Intelligence service"
        exit 1
    fi
}

# Function to create storage containers
create_storage_containers() {
    log "Creating storage containers..."
    
    if [[ "$DRY_RUN" == "false" ]]; then
        containers=("source-documents" "processing-workspace" "localized-output" "workflow-logs")
        
        for container in "${containers[@]}"; do
            execute_command "az storage container create \
                --name $container \
                --account-name $STORAGE_ACCOUNT \
                --account-key $STORAGE_KEY \
                --public-access off"
            
            if [[ $? -eq 0 ]]; then
                success "Created container: $container"
            else
                error "Failed to create container: $container"
                exit 1
            fi
        done
    else
        log "[DRY-RUN] Would create containers: source-documents, processing-workspace, localized-output, workflow-logs"
    fi
}

# Function to create Logic App
create_logic_app() {
    log "Creating Logic App..."
    
    # Basic Logic App creation
    execute_command "az logic workflow create \
        --name $LOGIC_APP_NAME \
        --resource-group $RESOURCE_GROUP \
        --location $LOCATION \
        --definition '{
            \"\$schema\": \"https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#\",
            \"contentVersion\": \"1.0.0.0\",
            \"parameters\": {},
            \"triggers\": {
                \"manual\": {
                    \"type\": \"Request\",
                    \"kind\": \"Http\"
                }
            },
            \"actions\": {},
            \"outputs\": {}
        }'"
    
    if [[ $? -eq 0 ]]; then
        success "Logic App created: $LOGIC_APP_NAME"
    else
        error "Failed to create Logic App"
        exit 1
    fi
}

# Function to create API connections
create_api_connections() {
    log "Creating API connections..."
    
    if [[ "$DRY_RUN" == "false" ]]; then
        # Get subscription ID
        SUBSCRIPTION_ID=$(az account show --query id -o tsv)
        
        # Create Azure Blob Storage connection
        execute_command "az resource create \
            --resource-group $RESOURCE_GROUP \
            --resource-type Microsoft.Web/connections \
            --name azureblob-connection \
            --properties '{
                \"displayName\": \"Azure Blob Storage Connection\",
                \"api\": {
                    \"id\": \"/subscriptions/$SUBSCRIPTION_ID/providers/Microsoft.Web/locations/$LOCATION/managedApis/azureblob\"
                },
                \"parameterValues\": {
                    \"accountName\": \"$STORAGE_ACCOUNT\",
                    \"accessKey\": \"$STORAGE_KEY\"
                }
            }'"
        
        if [[ $? -eq 0 ]]; then
            success "Created Azure Blob Storage connection"
        else
            error "Failed to create Azure Blob Storage connection"
            exit 1
        fi
    else
        log "[DRY-RUN] Would create API connections"
    fi
}

# Function to deploy workflow definition
deploy_workflow_definition() {
    log "Deploying workflow definition..."
    
    if [[ "$DRY_RUN" == "false" ]]; then
        # Create workflow definition file
        cat > /tmp/workflow-definition.json << 'EOF'
{
    "$schema": "https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#",
    "contentVersion": "1.0.0.0",
    "parameters": {
        "$connections": {
            "defaultValue": {},
            "type": "Object"
        },
        "documentIntelligenceEndpoint": {
            "defaultValue": "",
            "type": "String"
        },
        "documentIntelligenceKey": {
            "defaultValue": "",
            "type": "String"
        },
        "translatorEndpoint": {
            "defaultValue": "",
            "type": "String"
        },
        "translatorKey": {
            "defaultValue": "",
            "type": "String"
        }
    },
    "triggers": {
        "When_a_blob_is_added_or_modified": {
            "type": "ApiConnection",
            "inputs": {
                "host": {
                    "connection": {
                        "name": "@parameters('$connections')['azureblob']['connectionId']"
                    }
                },
                "method": "get",
                "path": "/datasets/default/triggers/batch/onupdatedfile",
                "queries": {
                    "folderId": "source-documents",
                    "maxFileCount": 1
                }
            },
            "recurrence": {
                "frequency": "Minute",
                "interval": 5
            }
        }
    },
    "actions": {
        "Get_blob_content": {
            "type": "ApiConnection",
            "inputs": {
                "host": {
                    "connection": {
                        "name": "@parameters('$connections')['azureblob']['connectionId']"
                    }
                },
                "method": "get",
                "path": "/datasets/default/files/@{encodeURIComponent(encodeURIComponent(triggerBody()['Id']))}/content"
            }
        },
        "Create_processing_log": {
            "type": "ApiConnection",
            "inputs": {
                "host": {
                    "connection": {
                        "name": "@parameters('$connections')['azureblob']['connectionId']"
                    }
                },
                "method": "post",
                "path": "/datasets/default/files",
                "queries": {
                    "folderPath": "/workflow-logs",
                    "name": "processing-@{formatDateTime(utcNow(), 'yyyy-MM-dd-HH-mm-ss')}.json"
                },
                "body": {
                    "timestamp": "@utcNow()",
                    "source_file": "@triggerBody()['Name']",
                    "status": "processing_started"
                }
            },
            "runAfter": {
                "Get_blob_content": ["Succeeded"]
            }
        }
    }
}
EOF
        
        # Get subscription ID
        SUBSCRIPTION_ID=$(az account show --query id -o tsv)
        
        # Update Logic App with workflow definition
        execute_command "az logic workflow update \
            --name $LOGIC_APP_NAME \
            --resource-group $RESOURCE_GROUP \
            --definition @/tmp/workflow-definition.json \
            --parameters '{
                \"\$connections\": {
                    \"azureblob\": {
                        \"connectionId\": \"/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Web/connections/azureblob-connection\",
                        \"connectionName\": \"azureblob\",
                        \"id\": \"/subscriptions/$SUBSCRIPTION_ID/providers/Microsoft.Web/locations/$LOCATION/managedApis/azureblob\"
                    }
                },
                \"documentIntelligenceEndpoint\": \"$DOC_INTEL_ENDPOINT\",
                \"documentIntelligenceKey\": \"$DOC_INTEL_KEY\",
                \"translatorEndpoint\": \"$TRANSLATOR_ENDPOINT\",
                \"translatorKey\": \"$TRANSLATOR_KEY\"
            }'"
        
        if [[ $? -eq 0 ]]; then
            success "Workflow definition deployed"
            
            # Enable the Logic App
            execute_command "az logic workflow enable \
                --name $LOGIC_APP_NAME \
                --resource-group $RESOURCE_GROUP"
            
            if [[ $? -eq 0 ]]; then
                success "Logic App enabled"
            else
                error "Failed to enable Logic App"
                exit 1
            fi
        else
            error "Failed to deploy workflow definition"
            exit 1
        fi
        
        # Clean up temporary file
        rm -f /tmp/workflow-definition.json
    else
        log "[DRY-RUN] Would deploy workflow definition and enable Logic App"
    fi
}

# Function to create test document
create_test_document() {
    log "Creating test document..."
    
    if [[ "$DRY_RUN" == "false" ]]; then
        # Create test document
        cat > /tmp/test-document.txt << 'EOF'
Welcome to our global organization. This document contains important business information that needs to be translated into multiple languages for our international teams.

Key Features:
- Automated document processing
- Multi-language translation
- Workflow orchestration
- Quality assurance processes

This solution demonstrates the power of Azure AI services for enterprise content localization.
EOF
        
        # Upload test document
        execute_command "az storage blob upload \
            --file /tmp/test-document.txt \
            --name test-document.txt \
            --container-name source-documents \
            --account-name $STORAGE_ACCOUNT \
            --account-key $STORAGE_KEY"
        
        if [[ $? -eq 0 ]]; then
            success "Test document uploaded"
        else
            error "Failed to upload test document"
            exit 1
        fi
        
        # Clean up temporary file
        rm -f /tmp/test-document.txt
    else
        log "[DRY-RUN] Would create and upload test document"
    fi
}

# Function to display deployment summary
display_summary() {
    log "Deployment Summary"
    echo "===================="
    echo "Resource Group: $RESOURCE_GROUP"
    echo "Location: $LOCATION"
    echo "Storage Account: $STORAGE_ACCOUNT"
    echo "Translator Service: $TRANSLATOR_NAME"
    echo "Document Intelligence: $DOC_INTELLIGENCE_NAME"
    echo "Logic App: $LOGIC_APP_NAME"
    echo ""
    echo "Next Steps:"
    echo "1. Navigate to the Azure portal to monitor your Logic App"
    echo "2. Upload documents to the 'source-documents' container"
    echo "3. Check the 'localized-output' container for translated documents"
    echo "4. Monitor workflow execution in the Logic App runs history"
    echo ""
    echo "To clean up resources, run: ./destroy.sh"
}

# Main deployment function
main() {
    log "Starting Azure Multi-Language Content Localization Workflow deployment..."
    
    check_prerequisites
    set_environment_variables
    create_resource_group
    create_storage_account
    create_translator_service
    create_document_intelligence_service
    create_storage_containers
    create_logic_app
    create_api_connections
    deploy_workflow_definition
    create_test_document
    
    success "Deployment completed successfully!"
    display_summary
}

# Handle script interruption
cleanup_on_error() {
    error "Deployment interrupted. You may need to manually clean up resources."
    exit 1
}

# Set up signal handlers
trap cleanup_on_error INT TERM

# Run main function
main "$@"