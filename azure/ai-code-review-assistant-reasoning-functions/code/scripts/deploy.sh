#!/bin/bash

# AI Code Review Assistant Deployment Script
# Deploy Azure OpenAI, Azure Functions, and Blob Storage for automated code reviews

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/deploy-$(date +%Y%m%d_%H%M%S).log"
CONFIG_FILE="${SCRIPT_DIR}/.deployment_config"

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

error_exit() {
    log "ERROR: $1"
    exit 1
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        error_exit "Azure CLI is not installed. Please install it from https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
    fi
    
    # Check Azure CLI version
    local az_version=$(az version --query '"azure-cli"' -o tsv)
    log "Azure CLI version: $az_version"
    
    # Check if logged in to Azure
    if ! az account show &> /dev/null; then
        error_exit "Not logged in to Azure. Run 'az login' first"
    fi
    
    # Check if Functions Core Tools is installed
    if ! command -v func &> /dev/null; then
        error_exit "Azure Functions Core Tools is not installed. Please install from https://docs.microsoft.com/en-us/azure/azure-functions/functions-run-local"
    fi
    
    # Check Functions Core Tools version
    local func_version=$(func --version 2>/dev/null || echo "unknown")
    log "Azure Functions Core Tools version: $func_version"
    
    # Check Python version
    if ! command -v python3 &> /dev/null; then
        error_exit "Python3 is not installed. Please install Python 3.11 or later"
    fi
    
    local python_version=$(python3 --version)
    log "Python version: $python_version"
    
    log "All prerequisites satisfied"
}

# Function to set default values and get user input
setup_configuration() {
    log "Setting up deployment configuration..."
    
    # Generate unique suffix
    RANDOM_SUFFIX=$(openssl rand -hex 3 2>/dev/null || date +%s | tail -c 6)
    
    # Set default values
    SUBSCRIPTION_ID=$(az account show --query id --output tsv)
    RESOURCE_GROUP="${RESOURCE_GROUP:-rg-ai-code-review-${RANDOM_SUFFIX}}"
    LOCATION="${LOCATION:-eastus}"
    STORAGE_ACCOUNT="${STORAGE_ACCOUNT:-stcodereview${RANDOM_SUFFIX}}"
    FUNCTION_APP="${FUNCTION_APP:-func-code-review-${RANDOM_SUFFIX}}"
    OPENAI_ACCOUNT="${OPENAI_ACCOUNT:-oai-code-review-${RANDOM_SUFFIX}}"
    
    # Display configuration
    log "Deployment Configuration:"
    log "  Subscription ID: $SUBSCRIPTION_ID"
    log "  Resource Group: $RESOURCE_GROUP"
    log "  Location: $LOCATION"
    log "  Storage Account: $STORAGE_ACCOUNT"
    log "  Function App: $FUNCTION_APP"
    log "  OpenAI Account: $OPENAI_ACCOUNT"
    log "  Random Suffix: $RANDOM_SUFFIX"
    
    # Save configuration for cleanup
    cat > "$CONFIG_FILE" << EOF
SUBSCRIPTION_ID=$SUBSCRIPTION_ID
RESOURCE_GROUP=$RESOURCE_GROUP
LOCATION=$LOCATION
STORAGE_ACCOUNT=$STORAGE_ACCOUNT
FUNCTION_APP=$FUNCTION_APP
OPENAI_ACCOUNT=$OPENAI_ACCOUNT
RANDOM_SUFFIX=$RANDOM_SUFFIX
DEPLOYMENT_TIMESTAMP=$(date +%Y%m%d_%H%M%S)
EOF
    
    log "Configuration saved to $CONFIG_FILE"
}

# Function to validate Azure OpenAI availability
validate_openai_availability() {
    log "Validating Azure OpenAI service availability in $LOCATION..."
    
    # Check if OpenAI service is available in the region
    if ! az cognitiveservices account list-kinds --location "$LOCATION" --query "[?contains(@, 'OpenAI')]" -o tsv &> /dev/null; then
        log "WARNING: Azure OpenAI may not be available in $LOCATION"
        log "Consider using: eastus, westus, westus2, northcentralus, or other supported regions"
        
        read -p "Do you want to continue anyway? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            error_exit "Deployment cancelled"
        fi
    fi
    
    log "Azure OpenAI availability validated"
}

# Function to create resource group
create_resource_group() {
    log "Creating resource group: $RESOURCE_GROUP"
    
    if az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        log "Resource group $RESOURCE_GROUP already exists"
    else
        az group create \
            --name "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --tags purpose=recipe environment=demo \
            --output table >> "$LOG_FILE" 2>&1
        
        if [ $? -eq 0 ]; then
            log "✅ Resource group created successfully"
        else
            error_exit "Failed to create resource group"
        fi
    fi
}

# Function to create storage account
create_storage_account() {
    log "Creating storage account: $STORAGE_ACCOUNT"
    
    if az storage account show --name "$STORAGE_ACCOUNT" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        log "Storage account $STORAGE_ACCOUNT already exists"
    else
        az storage account create \
            --name "$STORAGE_ACCOUNT" \
            --resource-group "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --sku Standard_LRS \
            --kind StorageV2 \
            --access-tier Hot \
            --output table >> "$LOG_FILE" 2>&1
        
        if [ $? -eq 0 ]; then
            log "✅ Storage account created successfully"
        else
            error_exit "Failed to create storage account"
        fi
    fi
    
    # Get storage connection string
    STORAGE_CONNECTION=$(az storage account show-connection-string \
        --name "$STORAGE_ACCOUNT" \
        --resource-group "$RESOURCE_GROUP" \
        --query connectionString --output tsv)
    
    if [ -z "$STORAGE_CONNECTION" ]; then
        error_exit "Failed to get storage connection string"
    fi
    
    log "Storage connection string retrieved"
}

# Function to create blob containers
create_blob_containers() {
    log "Creating blob containers..."
    
    # Create container for code files
    az storage container create \
        --name "code-files" \
        --connection-string "$STORAGE_CONNECTION" \
        --public-access off \
        --output table >> "$LOG_FILE" 2>&1
    
    # Create container for review reports
    az storage container create \
        --name "review-reports" \
        --connection-string "$STORAGE_CONNECTION" \
        --public-access off \
        --output table >> "$LOG_FILE" 2>&1
    
    if [ $? -eq 0 ]; then
        log "✅ Blob containers created successfully"
    else
        error_exit "Failed to create blob containers"
    fi
}

# Function to create Azure OpenAI service
create_openai_service() {
    log "Creating Azure OpenAI service: $OPENAI_ACCOUNT"
    
    if az cognitiveservices account show --name "$OPENAI_ACCOUNT" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        log "Azure OpenAI account $OPENAI_ACCOUNT already exists"
    else
        az cognitiveservices account create \
            --name "$OPENAI_ACCOUNT" \
            --resource-group "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --kind OpenAI \
            --sku S0 \
            --custom-domain "$OPENAI_ACCOUNT" \
            --output table >> "$LOG_FILE" 2>&1
        
        if [ $? -eq 0 ]; then
            log "✅ Azure OpenAI service created successfully"
        else
            error_exit "Failed to create Azure OpenAI service"
        fi
        
        # Wait for service to be fully provisioned
        log "Waiting for OpenAI service to be fully provisioned..."
        sleep 30
    fi
    
    # Get OpenAI endpoint and key
    OPENAI_ENDPOINT=$(az cognitiveservices account show \
        --name "$OPENAI_ACCOUNT" \
        --resource-group "$RESOURCE_GROUP" \
        --query properties.endpoint --output tsv)
    
    OPENAI_KEY=$(az cognitiveservices account keys list \
        --name "$OPENAI_ACCOUNT" \
        --resource-group "$RESOURCE_GROUP" \
        --query key1 --output tsv)
    
    if [ -z "$OPENAI_ENDPOINT" ] || [ -z "$OPENAI_KEY" ]; then
        error_exit "Failed to get OpenAI endpoint or key"
    fi
    
    log "OpenAI endpoint and key retrieved"
}

# Function to deploy o1-mini model
deploy_openai_model() {
    log "Deploying o1-mini model for code analysis..."
    
    # Check if deployment already exists
    if az cognitiveservices account deployment show \
        --name "$OPENAI_ACCOUNT" \
        --resource-group "$RESOURCE_GROUP" \
        --deployment-name "o1-mini-code-review" &> /dev/null; then
        log "o1-mini model deployment already exists"
    else
        # Deploy o1-mini model
        az cognitiveservices account deployment create \
            --name "$OPENAI_ACCOUNT" \
            --resource-group "$RESOURCE_GROUP" \
            --deployment-name "o1-mini-code-review" \
            --model-name "o1-mini" \
            --model-version "2024-09-12" \
            --model-format OpenAI \
            --sku-capacity 10 \
            --sku-name "Standard" \
            --output table >> "$LOG_FILE" 2>&1
        
        if [ $? -eq 0 ]; then
            log "✅ o1-mini model deployed successfully"
        else
            log "WARNING: Failed to deploy o1-mini model. You may need to deploy it manually"
            log "This could be due to quota limitations or regional availability"
        fi
        
        # Wait for model deployment to complete
        log "Waiting for model deployment to complete..."
        sleep 60
    fi
}

# Function to create Function App
create_function_app() {
    log "Creating Function App: $FUNCTION_APP"
    
    if az functionapp show --name "$FUNCTION_APP" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        log "Function App $FUNCTION_APP already exists"
    else
        az functionapp create \
            --name "$FUNCTION_APP" \
            --resource-group "$RESOURCE_GROUP" \
            --storage-account "$STORAGE_ACCOUNT" \
            --consumption-plan-location "$LOCATION" \
            --runtime python \
            --runtime-version 3.11 \
            --functions-version 4 \
            --os-type Linux \
            --output table >> "$LOG_FILE" 2>&1
        
        if [ $? -eq 0 ]; then
            log "✅ Function App created successfully"
        else
            error_exit "Failed to create Function App"
        fi
        
        # Wait for Function App to be ready
        log "Waiting for Function App to be ready..."
        sleep 45
    fi
}

# Function to configure Function App settings
configure_function_app() {
    log "Configuring Function App settings..."
    
    az functionapp config appsettings set \
        --name "$FUNCTION_APP" \
        --resource-group "$RESOURCE_GROUP" \
        --settings \
        "AZURE_OPENAI_ENDPOINT=$OPENAI_ENDPOINT" \
        "AZURE_OPENAI_KEY=$OPENAI_KEY" \
        "AZURE_STORAGE_CONNECTION_STRING=$STORAGE_CONNECTION" \
        "OPENAI_DEPLOYMENT_NAME=o1-mini-code-review" \
        --output table >> "$LOG_FILE" 2>&1
    
    if [ $? -eq 0 ]; then
        log "✅ Function App settings configured successfully"
    else
        error_exit "Failed to configure Function App settings"
    fi
}

# Function to create and deploy function code
deploy_function_code() {
    log "Creating and deploying Function code..."
    
    # Create temporary directory for function code
    TEMP_FUNC_DIR=$(mktemp -d)
    cd "$TEMP_FUNC_DIR"
    
    # Initialize Function App project
    func init . --python --model V2 >> "$LOG_FILE" 2>&1
    
    # Create requirements.txt
    cat << 'EOF' > requirements.txt
azure-functions
azure-storage-blob>=12.19.0
azure-identity>=1.15.0
openai>=1.40.0
python-dotenv>=1.0.0
EOF
    
    # Create the main function code
    cat << 'EOF' > function_app.py
import azure.functions as func
import json
import logging
import os
from azure.storage.blob import BlobServiceClient
from azure.identity import DefaultAzureCredential
from openai import AzureOpenAI
import datetime

app = func.FunctionApp(http_auth_level=func.AuthLevel.FUNCTION)

# Initialize clients
def get_openai_client():
    return AzureOpenAI(
        azure_endpoint=os.environ["AZURE_OPENAI_ENDPOINT"],
        api_key=os.environ["AZURE_OPENAI_KEY"],
        api_version="2024-10-21"
    )

def get_blob_client():
    return BlobServiceClient.from_connection_string(
        os.environ["AZURE_STORAGE_CONNECTION_STRING"]
    )

@app.route(route="review-code", methods=["POST"])
def review_code(req: func.HttpRequest) -> func.HttpResponse:
    """
    HTTP trigger function to analyze code and generate review reports
    Expects JSON payload with 'filename' and 'code_content' fields
    """
    logging.info('Code review request received')
    
    try:
        # Parse request data
        req_body = req.get_json()
        filename = req_body.get('filename')
        code_content = req_body.get('code_content')
        
        if not filename or not code_content:
            return func.HttpResponse(
                json.dumps({"error": "Missing filename or code_content"}),
                status_code=400,
                mimetype="application/json"
            )
        
        # Store code file in blob storage
        blob_client = get_blob_client()
        code_blob = blob_client.get_blob_client(
            container="code-files", 
            blob=filename
        )
        code_blob.upload_blob(code_content, overwrite=True)
        
        # Analyze code with OpenAI o1-mini
        openai_client = get_openai_client()
        
        system_prompt = """You are an expert code reviewer with deep knowledge of software engineering best practices, security vulnerabilities, performance optimization, and maintainability principles. 

Analyze the provided code systematically and provide a comprehensive review covering:
1. Code quality and style adherence
2. Potential bugs and logical errors
3. Security vulnerabilities and concerns
4. Performance optimization opportunities
5. Maintainability and readability improvements
6. Architecture and design pattern suggestions

Use chain-of-thought reasoning to work through each aspect methodically. Provide specific, actionable recommendations with code examples when appropriate."""

        user_prompt = f"""Please review the following code file: {filename}

Code content:
```
{code_content}
```

Provide a detailed analysis with severity levels (High, Medium, Low) for each issue found. Include positive aspects of the code as well as areas for improvement."""

        response = openai_client.chat.completions.create(
            model=os.environ["OPENAI_DEPLOYMENT_NAME"],
            messages=[
                {"role": "user", "content": user_prompt}
            ],
            max_completion_tokens=4000,
            temperature=0.1
        )
        
        review_content = response.choices[0].message.content
        
        # Create structured review report
        review_report = {
            "filename": filename,
            "review_timestamp": datetime.datetime.utcnow().isoformat(),
            "model_used": "o1-mini",
            "review_content": review_content,
            "metadata": {
                "code_length": len(code_content),
                "file_type": filename.split('.')[-1] if '.' in filename else "unknown"
            }
        }
        
        # Store review report in blob storage
        report_filename = f"review-{filename}-{datetime.datetime.utcnow().strftime('%Y%m%d_%H%M%S')}.json"
        report_blob = blob_client.get_blob_client(
            container="review-reports", 
            blob=report_filename
        )
        report_blob.upload_blob(
            json.dumps(review_report, indent=2), 
            overwrite=True
        )
        
        logging.info(f'Code review completed for {filename}')
        
        return func.HttpResponse(
            json.dumps({
                "status": "success",
                "filename": filename,
                "report_filename": report_filename,
                "review_summary": review_content[:500] + "..." if len(review_content) > 500 else review_content
            }),
            status_code=200,
            mimetype="application/json"
        )
        
    except Exception as e:
        logging.error(f'Error processing code review: {str(e)}')
        return func.HttpResponse(
            json.dumps({"error": f"Internal server error: {str(e)}"}),
            status_code=500,
            mimetype="application/json"
        )

@app.route(route="get-report", methods=["GET"])
def get_report(req: func.HttpRequest) -> func.HttpResponse:
    """
    HTTP trigger function to retrieve code review reports
    Expects 'report_filename' as query parameter
    """
    logging.info('Report retrieval request received')
    
    try:
        report_filename = req.params.get('report_filename')
        
        if not report_filename:
            return func.HttpResponse(
                json.dumps({"error": "Missing report_filename parameter"}),
                status_code=400,
                mimetype="application/json"
            )
        
        # Retrieve report from blob storage
        blob_client = get_blob_client()
        report_blob = blob_client.get_blob_client(
            container="review-reports", 
            blob=report_filename
        )
        
        report_content = report_blob.download_blob().readall()
        report_data = json.loads(report_content)
        
        logging.info(f'Report retrieved: {report_filename}')
        
        return func.HttpResponse(
            json.dumps(report_data, indent=2),
            status_code=200,
            mimetype="application/json"
        )
        
    except Exception as e:
        logging.error(f'Error retrieving report: {str(e)}')
        return func.HttpResponse(
            json.dumps({"error": f"Report not found or error: {str(e)}"}),
            status_code=404,
            mimetype="application/json"
        )
EOF
    
    # Deploy function code to Azure
    log "Deploying function code to Azure..."
    func azure functionapp publish "$FUNCTION_APP" --python >> "$LOG_FILE" 2>&1
    
    if [ $? -eq 0 ]; then
        log "✅ Function code deployed successfully"
    else
        error_exit "Failed to deploy function code"
    fi
    
    # Clean up temporary directory
    cd "$SCRIPT_DIR"
    rm -rf "$TEMP_FUNC_DIR"
}

# Function to validate deployment
validate_deployment() {
    log "Validating deployment..."
    
    # Get Function App URL and key
    FUNCTION_URL=$(az functionapp show \
        --name "$FUNCTION_APP" \
        --resource-group "$RESOURCE_GROUP" \
        --query defaultHostName --output tsv)
    
    FUNCTION_KEY=$(az functionapp keys list \
        --name "$FUNCTION_APP" \
        --resource-group "$RESOURCE_GROUP" \
        --query functionKeys.default --output tsv)
    
    if [ -z "$FUNCTION_URL" ] || [ -z "$FUNCTION_KEY" ]; then
        error_exit "Failed to get Function App URL or key"
    fi
    
    log "✅ Deployment validation completed"
    log "Function App URL: https://$FUNCTION_URL"
    
    # Save deployment info
    cat >> "$CONFIG_FILE" << EOF
FUNCTION_URL=$FUNCTION_URL
FUNCTION_KEY=$FUNCTION_KEY
OPENAI_ENDPOINT=$OPENAI_ENDPOINT
EOF
}

# Function to display deployment summary
display_summary() {
    log "=== DEPLOYMENT SUMMARY ==="
    log "Resource Group: $RESOURCE_GROUP"
    log "Storage Account: $STORAGE_ACCOUNT"
    log "Function App: $FUNCTION_APP"
    log "OpenAI Account: $OPENAI_ACCOUNT"
    log "Function URL: https://$FUNCTION_URL"
    log "Deployment Config: $CONFIG_FILE"
    log "Deployment Log: $LOG_FILE"
    log ""
    log "=== TESTING INSTRUCTIONS ==="
    log "Test the code review function with:"
    log "curl -X POST \"https://$FUNCTION_URL/api/review-code?code=$FUNCTION_KEY\" \\"
    log "  -H \"Content-Type: application/json\" \\"
    log "  -d '{\"filename\": \"test.py\", \"code_content\": \"def hello():\\n    print(\\\"Hello World\\\")\\nhello()\"}'"
    log ""
    log "✅ Deployment completed successfully!"
}

# Main deployment function
main() {
    log "=== AI Code Review Assistant Deployment Started ==="
    log "Deployment log: $LOG_FILE"
    
    check_prerequisites
    setup_configuration
    validate_openai_availability
    create_resource_group
    create_storage_account
    create_blob_containers
    create_openai_service
    deploy_openai_model
    create_function_app
    configure_function_app
    deploy_function_code
    validate_deployment
    display_summary
    
    log "=== Deployment Completed Successfully ==="
}

# Handle script interruption
trap 'log "Deployment interrupted"; exit 1' INT TERM

# Run main function
main "$@"