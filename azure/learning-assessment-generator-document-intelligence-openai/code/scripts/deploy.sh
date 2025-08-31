#!/bin/bash

# Azure Learning Assessment Generator - Deployment Script
# This script deploys Azure AI Document Intelligence, OpenAI, Functions, and Cosmos DB
# for automated educational assessment generation from documents.

set -euo pipefail

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/deploy.log"
DEPLOYMENT_START_TIME=$(date +%s)

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${timestamp} [${level}] ${message}" | tee -a "${LOG_FILE}"
}

log_info() { log "INFO" "$@"; }
log_warn() { log "WARN" "${YELLOW}$*${NC}"; }
log_error() { log "ERROR" "${RED}$*${NC}"; }
log_success() { log "SUCCESS" "${GREEN}$*${NC}"; }

# Error handling
cleanup_on_error() {
    local exit_code=$?
    log_error "Deployment failed with exit code ${exit_code}"
    log_info "Check the log file at: ${LOG_FILE}"
    
    if [[ "${CLEANUP_ON_FAILURE:-false}" == "true" ]]; then
        log_warn "Cleaning up resources due to failure..."
        "${SCRIPT_DIR}/destroy.sh" --force
    fi
    
    exit $exit_code
}

trap cleanup_on_error ERR

# Display banner
show_banner() {
    echo -e "${BLUE}"
    echo "=================================================================="
    echo "   Azure Learning Assessment Generator - Deployment Script"
    echo "=================================================================="
    echo -e "${NC}"
    log_info "Starting deployment of Learning Assessment Generator"
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        log_error "Azure CLI is not installed. Please install it from: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
        exit 1
    fi
    
    # Check if logged in to Azure
    if ! az account show &> /dev/null; then
        log_error "Not logged in to Azure. Please run 'az login' first."
        exit 1
    fi
    
    # Check if jq is available for JSON parsing
    if ! command -v jq &> /dev/null; then
        log_warn "jq is not installed. Some features may be limited."
    fi
    
    # Check if zip is available for function deployment
    if ! command -v zip &> /dev/null; then
        log_error "zip command is not available. Please install zip utility."
        exit 1
    fi
    
    # Check Azure subscription
    local subscription_name=$(az account show --query name -o tsv 2>/dev/null || echo "Unknown")
    local subscription_id=$(az account show --query id -o tsv 2>/dev/null || echo "Unknown")
    log_success "Connected to Azure subscription: ${subscription_name} (${subscription_id})"
    
    # Check for required providers
    log_info "Checking Azure provider registrations..."
    local providers=("Microsoft.CognitiveServices" "Microsoft.DocumentDB" "Microsoft.Web" "Microsoft.Storage" "Microsoft.Insights")
    
    for provider in "${providers[@]}"; do
        local state=$(az provider show --namespace "${provider}" --query registrationState -o tsv 2>/dev/null || echo "NotRegistered")
        if [[ "${state}" != "Registered" ]]; then
            log_warn "Provider ${provider} is not registered. Registering..."
            az provider register --namespace "${provider}" --no-wait
        else
            log_success "Provider ${provider} is registered"
        fi
    done
}

# Set environment variables
set_environment_variables() {
    log_info "Setting up environment variables..."
    
    # Generate unique suffix for resource names
    if [[ -z "${RANDOM_SUFFIX:-}" ]]; then
        export RANDOM_SUFFIX=$(openssl rand -hex 3 2>/dev/null || echo $(date +%s | tail -c 6))
    fi
    
    # Core configuration
    export RESOURCE_GROUP="${RESOURCE_GROUP:-rg-learning-assessment-${RANDOM_SUFFIX}}"
    export LOCATION="${LOCATION:-eastus}"
    export SUBSCRIPTION_ID=$(az account show --query id --output tsv)
    
    # Resource names
    export STORAGE_ACCOUNT="${STORAGE_ACCOUNT:-assessstorage${RANDOM_SUFFIX}}"
    export COSMOSDB_ACCOUNT="${COSMOSDB_ACCOUNT:-assess-cosmos-${RANDOM_SUFFIX}}"
    export FUNCTION_APP="${FUNCTION_APP:-assess-functions-${RANDOM_SUFFIX}}"
    export DOCUMENT_INTELLIGENCE="${DOCUMENT_INTELLIGENCE:-assess-doc-intel-${RANDOM_SUFFIX}}"
    export OPENAI_ACCOUNT="${OPENAI_ACCOUNT:-assess-openai-${RANDOM_SUFFIX}}"
    export INSIGHTS_NAME="${INSIGHTS_NAME:-${FUNCTION_APP}-insights}"
    
    # Validation
    if [[ ${#STORAGE_ACCOUNT} -gt 24 ]]; then
        log_error "Storage account name '${STORAGE_ACCOUNT}' is too long (max 24 characters)"
        exit 1
    fi
    
    log_success "Environment variables configured:"
    log_info "  Resource Group: ${RESOURCE_GROUP}"
    log_info "  Location: ${LOCATION}"
    log_info "  Random Suffix: ${RANDOM_SUFFIX}"
}

# Create resource group
create_resource_group() {
    log_info "Creating resource group: ${RESOURCE_GROUP}"
    
    if az group show --name "${RESOURCE_GROUP}" &>/dev/null; then
        log_warn "Resource group ${RESOURCE_GROUP} already exists, skipping creation"
        return 0
    fi
    
    az group create \
        --name "${RESOURCE_GROUP}" \
        --location "${LOCATION}" \
        --tags purpose=learning-assessment environment=demo created-by=deployment-script \
        --output none
    
    log_success "Resource group created successfully"
}

# Create storage account
create_storage_account() {
    log_info "Creating storage account: ${STORAGE_ACCOUNT}"
    
    # Check if storage account already exists
    if az storage account show --name "${STORAGE_ACCOUNT}" --resource-group "${RESOURCE_GROUP}" &>/dev/null; then
        log_warn "Storage account ${STORAGE_ACCOUNT} already exists, skipping creation"
    else
        az storage account create \
            --name "${STORAGE_ACCOUNT}" \
            --resource-group "${RESOURCE_GROUP}" \
            --location "${LOCATION}" \
            --sku Standard_LRS \
            --kind StorageV2 \
            --output none
        
        log_success "Storage account created successfully"
    fi
    
    # Create container for documents
    log_info "Creating documents container..."
    
    local storage_key=$(az storage account keys list \
        --account-name "${STORAGE_ACCOUNT}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query '[0].value' \
        --output tsv)
    
    az storage container create \
        --name "documents" \
        --account-name "${STORAGE_ACCOUNT}" \
        --account-key "${storage_key}" \
        --public-access off \
        --output none 2>/dev/null || log_warn "Documents container may already exist"
    
    # Get storage connection string
    export STORAGE_CONNECTION=$(az storage account show-connection-string \
        --name "${STORAGE_ACCOUNT}" \
        --resource-group "${RESOURCE_GROUP}" \
        --output tsv)
    
    log_success "Storage account configured with documents container"
}

# Create Document Intelligence service
create_document_intelligence() {
    log_info "Creating Azure AI Document Intelligence service: ${DOCUMENT_INTELLIGENCE}"
    
    if az cognitiveservices account show --name "${DOCUMENT_INTELLIGENCE}" --resource-group "${RESOURCE_GROUP}" &>/dev/null; then
        log_warn "Document Intelligence service ${DOCUMENT_INTELLIGENCE} already exists, skipping creation"
    else
        az cognitiveservices account create \
            --name "${DOCUMENT_INTELLIGENCE}" \
            --resource-group "${RESOURCE_GROUP}" \
            --location "${LOCATION}" \
            --kind FormRecognizer \
            --sku S0 \
            --custom-domain "${DOCUMENT_INTELLIGENCE}" \
            --output none
        
        log_success "Document Intelligence service created successfully"
    fi
    
    # Get endpoint and key
    export DOC_INTEL_ENDPOINT=$(az cognitiveservices account show \
        --name "${DOCUMENT_INTELLIGENCE}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query properties.endpoint \
        --output tsv)
    
    export DOC_INTEL_KEY=$(az cognitiveservices account keys list \
        --name "${DOCUMENT_INTELLIGENCE}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query key1 \
        --output tsv)
    
    log_success "Document Intelligence service configured"
    log_info "  Endpoint: ${DOC_INTEL_ENDPOINT}"
}

# Create Azure OpenAI service
create_openai_service() {
    log_info "Creating Azure OpenAI service: ${OPENAI_ACCOUNT}"
    
    if az cognitiveservices account show --name "${OPENAI_ACCOUNT}" --resource-group "${RESOURCE_GROUP}" &>/dev/null; then
        log_warn "Azure OpenAI service ${OPENAI_ACCOUNT} already exists, skipping creation"
    else
        az cognitiveservices account create \
            --name "${OPENAI_ACCOUNT}" \
            --resource-group "${RESOURCE_GROUP}" \
            --location "${LOCATION}" \
            --kind OpenAI \
            --sku S0 \
            --custom-domain "${OPENAI_ACCOUNT}" \
            --output none
        
        log_success "Azure OpenAI service created successfully"
    fi
    
    # Deploy GPT-4o model
    log_info "Deploying GPT-4o model..."
    
    if az cognitiveservices account deployment show \
        --name "${OPENAI_ACCOUNT}" \
        --resource-group "${RESOURCE_GROUP}" \
        --deployment-name "gpt-4o" &>/dev/null; then
        log_warn "GPT-4o model deployment already exists, skipping"
    else
        az cognitiveservices account deployment create \
            --name "${OPENAI_ACCOUNT}" \
            --resource-group "${RESOURCE_GROUP}" \
            --deployment-name "gpt-4o" \
            --model-name "gpt-4o" \
            --model-version "2024-08-06" \
            --model-format OpenAI \
            --sku-capacity 20 \
            --sku-name "Standard" \
            --output none
        
        log_success "GPT-4o model deployed successfully"
    fi
    
    # Get endpoint and key
    export OPENAI_ENDPOINT=$(az cognitiveservices account show \
        --name "${OPENAI_ACCOUNT}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query properties.endpoint \
        --output tsv)
    
    export OPENAI_KEY=$(az cognitiveservices account keys list \
        --name "${OPENAI_ACCOUNT}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query key1 \
        --output tsv)
    
    log_success "Azure OpenAI service configured"
    log_info "  Endpoint: ${OPENAI_ENDPOINT}"
}

# Create Cosmos DB
create_cosmos_db() {
    log_info "Creating Azure Cosmos DB: ${COSMOSDB_ACCOUNT}"
    
    if az cosmosdb show --name "${COSMOSDB_ACCOUNT}" --resource-group "${RESOURCE_GROUP}" &>/dev/null; then
        log_warn "Cosmos DB ${COSMOSDB_ACCOUNT} already exists, skipping creation"
    else
        az cosmosdb create \
            --name "${COSMOSDB_ACCOUNT}" \
            --resource-group "${RESOURCE_GROUP}" \
            --locations regionName="${LOCATION}" failoverPriority=0 \
            --capabilities EnableServerless \
            --enable-automatic-failover false \
            --output none
        
        log_success "Cosmos DB account created successfully"
    fi
    
    # Create database
    log_info "Creating AssessmentDB database..."
    
    az cosmosdb sql database create \
        --account-name "${COSMOSDB_ACCOUNT}" \
        --resource-group "${RESOURCE_GROUP}" \
        --name "AssessmentDB" \
        --output none 2>/dev/null || log_warn "AssessmentDB may already exist"
    
    # Create containers
    log_info "Creating containers..."
    
    az cosmosdb sql container create \
        --account-name "${COSMOSDB_ACCOUNT}" \
        --resource-group "${RESOURCE_GROUP}" \
        --database-name "AssessmentDB" \
        --name "Documents" \
        --partition-key-path "/documentId" \
        --output none 2>/dev/null || log_warn "Documents container may already exist"
    
    az cosmosdb sql container create \
        --account-name "${COSMOSDB_ACCOUNT}" \
        --resource-group "${RESOURCE_GROUP}" \
        --database-name "AssessmentDB" \
        --name "Assessments" \
        --partition-key-path "/documentId" \
        --output none 2>/dev/null || log_warn "Assessments container may already exist"
    
    # Get connection details
    export COSMOS_ENDPOINT=$(az cosmosdb show \
        --name "${COSMOSDB_ACCOUNT}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query documentEndpoint \
        --output tsv)
    
    export COSMOS_KEY=$(az cosmosdb keys list \
        --name "${COSMOSDB_ACCOUNT}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query primaryMasterKey \
        --output tsv)
    
    log_success "Cosmos DB configured with assessment containers"
    log_info "  Endpoint: ${COSMOS_ENDPOINT}"
}

# Create Application Insights
create_application_insights() {
    log_info "Creating Application Insights: ${INSIGHTS_NAME}"
    
    if az monitor app-insights component show --app "${INSIGHTS_NAME}" --resource-group "${RESOURCE_GROUP}" &>/dev/null; then
        log_warn "Application Insights ${INSIGHTS_NAME} already exists, skipping creation"
    else
        az monitor app-insights component create \
            --app "${INSIGHTS_NAME}" \
            --location "${LOCATION}" \
            --resource-group "${RESOURCE_GROUP}" \
            --kind web \
            --output none
        
        log_success "Application Insights created successfully"
    fi
    
    # Get instrumentation key
    export INSIGHTS_KEY=$(az monitor app-insights component show \
        --app "${INSIGHTS_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query instrumentationKey \
        --output tsv)
    
    log_success "Application Insights configured"
}

# Create Function App
create_function_app() {
    log_info "Creating Function App: ${FUNCTION_APP}"
    
    if az functionapp show --name "${FUNCTION_APP}" --resource-group "${RESOURCE_GROUP}" &>/dev/null; then
        log_warn "Function App ${FUNCTION_APP} already exists, skipping creation"
    else
        az functionapp create \
            --name "${FUNCTION_APP}" \
            --resource-group "${RESOURCE_GROUP}" \
            --storage-account "${STORAGE_ACCOUNT}" \
            --consumption-plan-location "${LOCATION}" \
            --runtime python \
            --runtime-version 3.12 \
            --functions-version 4 \
            --os-type linux \
            --output none
        
        log_success "Function App created successfully"
    fi
    
    # Configure application settings
    log_info "Configuring Function App settings..."
    
    az functionapp config appsettings set \
        --name "${FUNCTION_APP}" \
        --resource-group "${RESOURCE_GROUP}" \
        --settings \
        "DOC_INTEL_ENDPOINT=${DOC_INTEL_ENDPOINT}" \
        "DOC_INTEL_KEY=${DOC_INTEL_KEY}" \
        "OPENAI_ENDPOINT=${OPENAI_ENDPOINT}" \
        "OPENAI_KEY=${OPENAI_KEY}" \
        "COSMOS_ENDPOINT=${COSMOS_ENDPOINT}" \
        "COSMOS_KEY=${COSMOS_KEY}" \
        "COSMOS_DATABASE=AssessmentDB" \
        "APPINSIGHTS_INSTRUMENTATIONKEY=${INSIGHTS_KEY}" \
        --output none
    
    log_success "Function App configured with AI service connections"
}

# Deploy function code
deploy_function_code() {
    log_info "Preparing function code for deployment..."
    
    local temp_dir=$(mktemp -d)
    local function_dir="${temp_dir}/assess-functions"
    
    # Create function directory structure
    mkdir -p "${function_dir}"
    cd "${function_dir}"
    
    # Create requirements.txt
    cat > requirements.txt << 'EOF'
azure-functions
azure-storage-blob
azure-cosmos
azure-ai-documentintelligence
openai
aiohttp
EOF
    
    # Create function_app.py with all three functions
    cat > function_app.py << 'EOF'
import azure.functions as func
import json
import logging
import os
from azure.ai.documentintelligence import DocumentIntelligenceClient
from azure.core.credentials import AzureKeyCredential
from azure.cosmos import CosmosClient
from datetime import datetime

app = func.FunctionApp()

@app.blob_trigger(arg_name="myblob", path="documents/{name}",
                 connection="AzureWebJobsStorage")
def document_processor(myblob: func.InputStream) -> None:
    logging.info(f"Processing document: {myblob.name}")
    
    # Initialize Document Intelligence client
    doc_intel_client = DocumentIntelligenceClient(
        endpoint=os.environ["DOC_INTEL_ENDPOINT"],
        credential=AzureKeyCredential(os.environ["DOC_INTEL_KEY"])
    )
    
    # Initialize Cosmos DB client
    cosmos_client = CosmosClient(
        os.environ["COSMOS_ENDPOINT"],
        os.environ["COSMOS_KEY"]
    )
    database = cosmos_client.get_database_client("AssessmentDB")
    container = database.get_container_client("Documents")
    
    try:
        # Process document with Layout model for comprehensive extraction
        poller = doc_intel_client.begin_analyze_document(
            "prebuilt-layout",
            analyze_request=myblob.read(),
            features=["keyValuePairs", "queryFields"]
        )
        result = poller.result()
        
        # Extract structured content
        extracted_content = {
            "documentId": myblob.name.split("/")[-1],
            "fileName": myblob.name,
            "extractedText": result.content,
            "sections": [],
            "tables": [],
            "figures": [],
            "keyValuePairs": [],
            "processedDate": datetime.utcnow().isoformat(),
            "status": "processed"
        }
        
        # Process sections with hierarchical structure
        if result.sections:
            for section in result.sections:
                extracted_content["sections"].append({
                    "spans": [{"offset": span.offset, "length": span.length} 
                             for span in section.spans] if section.spans else [],
                    "elements": section.elements if hasattr(section, 'elements') else []
                })
        
        # Process tables for structured data
        if result.tables:
            for table in result.tables:
                table_data = {
                    "rowCount": table.row_count,
                    "columnCount": table.column_count,
                    "cells": []
                }
                for cell in table.cells:
                    table_data["cells"].append({
                        "content": cell.content,
                        "rowIndex": cell.row_index,
                        "columnIndex": cell.column_index
                    })
                extracted_content["tables"].append(table_data)
        
        # Process key-value pairs for metadata
        if result.key_value_pairs:
            for kv_pair in result.key_value_pairs:
                if kv_pair.key and kv_pair.value:
                    extracted_content["keyValuePairs"].append({
                        "key": kv_pair.key.content,
                        "value": kv_pair.value.content
                    })
        
        # Store in Cosmos DB
        container.create_item(extracted_content)
        logging.info(f"Document processed and stored: {myblob.name}")
        
    except Exception as e:
        logging.error(f"Error processing document {myblob.name}: {str(e)}")
        # Store error status
        error_record = {
            "documentId": myblob.name.split("/")[-1],
            "fileName": myblob.name,
            "status": "error",
            "error": str(e),
            "processedDate": datetime.utcnow().isoformat()
        }
        container.create_item(error_record)

@app.timer_trigger(schedule="0 */5 * * * *", arg_name="myTimer", run_on_startup=False,
              use_monitor=False) 
def assessment_generator(myTimer: func.TimerRequest) -> None:
    logging.info("Starting assessment generation process")
    
    from openai import AzureOpenAI
    
    # Initialize clients
    openai_client = AzureOpenAI(
        api_key=os.environ["OPENAI_KEY"],
        api_version="2024-10-21",
        azure_endpoint=os.environ["OPENAI_ENDPOINT"]
    )
    
    cosmos_client = CosmosClient(
        os.environ["COSMOS_ENDPOINT"],
        os.environ["COSMOS_KEY"]
    )
    database = cosmos_client.get_database_client("AssessmentDB")
    docs_container = database.get_container_client("Documents")
    assess_container = database.get_container_client("Assessments")
    
    try:
        # Query for processed documents without assessments
        query = "SELECT * FROM c WHERE c.status = 'processed'"
        documents = list(docs_container.query_items(query=query, enable_cross_partition_query=True))
        
        for doc in documents:
            # Check if assessment already exists
            existing_assessment = list(assess_container.query_items(
                query="SELECT * FROM c WHERE c.documentId = @docId",
                parameters=[{"name": "@docId", "value": doc["documentId"]}],
                enable_cross_partition_query=True
            ))
            
            if existing_assessment:
                continue
                
            # Generate assessment using GPT-4o
            content_summary = doc["extractedText"][:4000]  # Limit for token constraints
            
            assessment_prompt = f"""
            You are an expert educational assessment creator. Based on the following educational content, 
            create a comprehensive assessment with 5 high-quality questions. Each question should test 
            understanding of key concepts from the material.

            Content: {content_summary}

            Generate exactly 5 questions in the following JSON format:
            {{
                "questions": [
                    {{
                        "id": 1,
                        "type": "multiple_choice",
                        "question": "Question text here",
                        "options": ["A) Option 1", "B) Option 2", "C) Option 3", "D) Option 4"],
                        "correct_answer": "A",
                        "explanation": "Detailed explanation of why this is correct",
                        "difficulty": "medium",
                        "learning_objective": "What concept this tests"
                    }}
                ]
            }}

            Ensure questions are:
            - Pedagogically sound and test real understanding
            - Clear and unambiguous
            - Varied in difficulty (easy, medium, hard)
            - Include detailed explanations
            - Cover different aspects of the content
            """
            
            response = openai_client.chat.completions.create(
                model="gpt-4o",
                messages=[
                    {"role": "system", "content": "You are an expert educational assessment creator focused on creating high-quality, pedagogically sound questions."},
                    {"role": "user", "content": assessment_prompt}
                ],
                temperature=0.7,
                max_tokens=2000
            )
            
            # Parse and store assessment
            try:
                assessment_data = json.loads(response.choices[0].message.content)
                
                assessment_record = {
                    "documentId": doc["documentId"],
                    "fileName": doc["fileName"],
                    "questions": assessment_data["questions"],
                    "generatedDate": datetime.utcnow().isoformat(),
                    "status": "completed",
                    "totalQuestions": len(assessment_data["questions"])
                }
                
                assess_container.create_item(assessment_record)
                logging.info(f"Assessment generated for document: {doc['documentId']}")
                
            except json.JSONDecodeError as e:
                logging.error(f"Failed to parse assessment JSON for {doc['documentId']}: {str(e)}")
                continue
                
    except Exception as e:
        logging.error(f"Error in assessment generation: {str(e)}")

@app.route(route="assessments/{document_id?}", auth_level=func.AuthLevel.FUNCTION)
def get_assessments(req: func.HttpRequest) -> func.HttpResponse:
    logging.info('Assessment API request received')
    
    cosmos_client = CosmosClient(
        os.environ["COSMOS_ENDPOINT"],
        os.environ["COSMOS_KEY"]
    )
    database = cosmos_client.get_database_client("AssessmentDB")
    assess_container = database.get_container_client("Assessments")
    
    try:
        document_id = req.route_params.get('document_id')
        
        if document_id:
            # Get specific assessment
            query = "SELECT * FROM c WHERE c.documentId = @docId"
            parameters = [{"name": "@docId", "value": document_id}]
        else:
            # Get all assessments with pagination
            query = "SELECT * FROM c ORDER BY c.generatedDate DESC"
            parameters = []
        
        assessments = list(assess_container.query_items(
            query=query,
            parameters=parameters,
            enable_cross_partition_query=True
        ))
        
        # Format response
        response_data = {
            "assessments": assessments,
            "count": len(assessments),
            "status": "success"
        }
        
        return func.HttpResponse(
            json.dumps(response_data, default=str),
            mimetype="application/json",
            status_code=200
        )
        
    except Exception as e:
        logging.error(f"Error retrieving assessments: {str(e)}")
        return func.HttpResponse(
            json.dumps({"error": str(e), "status": "error"}),
            mimetype="application/json",
            status_code=500
        )
EOF
    
    # Create host.json for function configuration
    cat > host.json << 'EOF'
{
  "version": "2.0",
  "functionTimeout": "00:10:00",
  "logging": {
    "applicationInsights": {
      "samplingSettings": {
        "isEnabled": true
      }
    }
  },
  "extensions": {
    "http": {
      "routePrefix": "api"
    }
  }
}
EOF
    
    # Create package and deploy
    log_info "Creating deployment package..."
    zip -r function-package.zip . -x "*.git*" "*.DS_Store*" > /dev/null
    
    log_info "Deploying function package to Azure..."
    az functionapp deployment source config-zip \
        --name "${FUNCTION_APP}" \
        --resource-group "${RESOURCE_GROUP}" \
        --src function-package.zip \
        --output none
    
    # Wait for deployment to complete
    log_info "Waiting for deployment to complete..."
    sleep 30
    
    # Enable managed identity
    log_info "Enabling managed identity..."
    az functionapp identity assign \
        --name "${FUNCTION_APP}" \
        --resource-group "${RESOURCE_GROUP}" \
        --output none
    
    # Get function URL
    export FUNCTION_URL=$(az functionapp show \
        --name "${FUNCTION_APP}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query defaultHostName \
        --output tsv)
    
    log_success "Functions deployed successfully"
    log_info "  Function URL: https://${FUNCTION_URL}"
    
    # Cleanup temporary directory
    cd - > /dev/null
    rm -rf "${temp_dir}"
}

# Save deployment configuration
save_deployment_config() {
    log_info "Saving deployment configuration..."
    
    local config_file="${SCRIPT_DIR}/deployment-config.json"
    
    cat > "${config_file}" << EOF
{
  "deploymentInfo": {
    "deploymentDate": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "deploymentDuration": "$(($(date +%s) - DEPLOYMENT_START_TIME)) seconds",
    "resourceGroup": "${RESOURCE_GROUP}",
    "location": "${LOCATION}",
    "randomSuffix": "${RANDOM_SUFFIX}"
  },
  "resources": {
    "storageAccount": "${STORAGE_ACCOUNT}",
    "cosmosdbAccount": "${COSMOSDB_ACCOUNT}",
    "functionApp": "${FUNCTION_APP}",
    "documentIntelligence": "${DOCUMENT_INTELLIGENCE}",
    "openaiAccount": "${OPENAI_ACCOUNT}",
    "applicationInsights": "${INSIGHTS_NAME}"
  },
  "endpoints": {
    "functionUrl": "https://${FUNCTION_URL}",
    "documentIntelligenceEndpoint": "${DOC_INTEL_ENDPOINT}",
    "openaiEndpoint": "${OPENAI_ENDPOINT}",
    "cosmosEndpoint": "${COSMOS_ENDPOINT}"
  }
}
EOF
    
    log_success "Deployment configuration saved to: ${config_file}"
}

# Verify deployment
verify_deployment() {
    log_info "Verifying deployment..."
    
    local all_healthy=true
    
    # Check each service
    local services=(
        "Storage Account:az storage account show --name ${STORAGE_ACCOUNT} --resource-group ${RESOURCE_GROUP}"
        "Document Intelligence:az cognitiveservices account show --name ${DOCUMENT_INTELLIGENCE} --resource-group ${RESOURCE_GROUP}"
        "Azure OpenAI:az cognitiveservices account show --name ${OPENAI_ACCOUNT} --resource-group ${RESOURCE_GROUP}"
        "Cosmos DB:az cosmosdb show --name ${COSMOSDB_ACCOUNT} --resource-group ${RESOURCE_GROUP}"
        "Function App:az functionapp show --name ${FUNCTION_APP} --resource-group ${RESOURCE_GROUP}"
        "Application Insights:az monitor app-insights component show --app ${INSIGHTS_NAME} --resource-group ${RESOURCE_GROUP}"
    )
    
    for service_check in "${services[@]}"; do
        local service_name="${service_check%%:*}"
        local check_command="${service_check##*:}"
        
        if eval "${check_command} --query provisioningState -o tsv 2>/dev/null | grep -i succeeded" > /dev/null; then
            log_success "✓ ${service_name} is healthy"
        else
            log_error "✗ ${service_name} verification failed"
            all_healthy=false
        fi
    done
    
    if [ "$all_healthy" = true ]; then
        log_success "All services verified successfully!"
    else
        log_error "Some services failed verification. Check the logs for details."
        return 1
    fi
}

# Display deployment summary
show_deployment_summary() {
    local deployment_time=$(($(date +%s) - DEPLOYMENT_START_TIME))
    
    echo -e "${GREEN}"
    echo "=================================================================="
    echo "             DEPLOYMENT COMPLETED SUCCESSFULLY!"
    echo "=================================================================="
    echo -e "${NC}"
    
    echo "📊 Deployment Summary:"
    echo "  • Resource Group: ${RESOURCE_GROUP}"
    echo "  • Location: ${LOCATION}"
    echo "  • Deployment Time: ${deployment_time} seconds"
    echo ""
    echo "🔗 Service Endpoints:"
    echo "  • Function App: https://${FUNCTION_URL}"
    echo "  • Document Intelligence: ${DOC_INTEL_ENDPOINT}"
    echo "  • Azure OpenAI: ${OPENAI_ENDPOINT}"
    echo "  • Cosmos DB: ${COSMOS_ENDPOINT}"
    echo ""
    echo "📋 Next Steps:"
    echo "  1. Upload educational documents to the 'documents' container in ${STORAGE_ACCOUNT}"
    echo "  2. Monitor function execution in the Azure portal"
    echo "  3. Query assessments using the API endpoint"
    echo ""
    echo "📄 Configuration saved to: ${SCRIPT_DIR}/deployment-config.json"
    echo "📝 Deployment log: ${LOG_FILE}"
    echo ""
    echo "🧹 To cleanup resources, run: ${SCRIPT_DIR}/destroy.sh"
}

# Parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --resource-group)
                RESOURCE_GROUP="$2"
                shift 2
                ;;
            --location)
                LOCATION="$2"
                shift 2
                ;;
            --suffix)
                RANDOM_SUFFIX="$2"
                shift 2
                ;;
            --cleanup-on-failure)
                CLEANUP_ON_FAILURE=true
                shift
                ;;
            --help|-h)
                echo "Usage: $0 [OPTIONS]"
                echo ""
                echo "Options:"
                echo "  --resource-group NAME    Resource group name (default: auto-generated)"
                echo "  --location REGION        Azure region (default: eastus)"
                echo "  --suffix SUFFIX          Random suffix for resources (default: auto-generated)"
                echo "  --cleanup-on-failure     Clean up resources if deployment fails"
                echo "  --help, -h              Show this help message"
                echo ""
                exit 0
                ;;
            *)
                log_error "Unknown argument: $1"
                exit 1
                ;;
        esac
    done
}

# Main execution
main() {
    parse_arguments "$@"
    show_banner
    
    # Initialize log file
    echo "Azure Learning Assessment Generator Deployment Log" > "${LOG_FILE}"
    echo "Started at: $(date)" >> "${LOG_FILE}"
    echo "=========================================" >> "${LOG_FILE}"
    
    check_prerequisites
    set_environment_variables
    create_resource_group
    create_storage_account
    create_document_intelligence
    create_openai_service
    create_cosmos_db
    create_application_insights
    create_function_app
    deploy_function_code
    save_deployment_config
    verify_deployment
    show_deployment_summary
    
    log_success "Deployment completed successfully in $(($(date +%s) - DEPLOYMENT_START_TIME)) seconds"
}

# Run main function with all arguments
main "$@"