#!/bin/bash

# File Upload Processing with Azure Functions and Blob Storage - Deployment Script
# This script deploys all Azure resources needed for serverless file processing
# Recipe: file-upload-processing-functions-blob

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Color codes for output formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Error handling function
handle_error() {
    log_error "Deployment failed at line $1"
    log_error "Cleaning up any partially created resources..."
    cleanup_on_error
    exit 1
}

# Set up error trap
trap 'handle_error $LINENO' ERR

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        log_error "Azure CLI is not installed. Please install it first."
        log_error "Visit: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
        exit 1
    fi
    
    # Check Azure CLI version (minimum 2.4.0)
    local az_version=$(az version --query '"azure-cli"' -o tsv)
    log_info "Azure CLI version: $az_version"
    
    # Check if logged in to Azure
    if ! az account show &> /dev/null; then
        log_error "Not logged in to Azure. Please run 'az login' first."
        exit 1
    fi
    
    # Check if openssl is available for random string generation
    if ! command -v openssl &> /dev/null; then
        log_error "openssl is required for generating unique resource names."
        exit 1
    fi
    
    # Check if zip is available for function deployment
    if ! command -v zip &> /dev/null; then
        log_error "zip is required for function deployment."
        exit 1
    fi
    
    log_success "Prerequisites check passed"
}

# Function to set environment variables
setup_environment() {
    log_info "Setting up environment variables..."
    
    # Generate unique suffix for resource names
    RANDOM_SUFFIX=$(openssl rand -hex 3)
    
    # Export environment variables
    export RESOURCE_GROUP="rg-file-processing-${RANDOM_SUFFIX}"
    export LOCATION="${AZURE_LOCATION:-eastus}"
    export SUBSCRIPTION_ID=$(az account show --query id --output tsv)
    export STORAGE_ACCOUNT="stfileproc${RANDOM_SUFFIX}"
    export FUNCTION_APP="func-file-processing-${RANDOM_SUFFIX}"
    export CONTAINER_NAME="uploads"
    
    # Create deployment info file
    cat > deployment_info.txt << EOF
Deployment Information
=====================
Resource Group: ${RESOURCE_GROUP}
Location: ${LOCATION}
Subscription: ${SUBSCRIPTION_ID}
Storage Account: ${STORAGE_ACCOUNT}
Function App: ${FUNCTION_APP}
Container Name: ${CONTAINER_NAME}
Random Suffix: ${RANDOM_SUFFIX}
Deployment Time: $(date)
EOF
    
    log_info "Resource Group: ${RESOURCE_GROUP}"
    log_info "Storage Account: ${STORAGE_ACCOUNT}"
    log_info "Function App: ${FUNCTION_APP}"
    log_info "Location: ${LOCATION}"
    log_success "Environment variables configured"
}

# Function to create resource group
create_resource_group() {
    log_info "Creating resource group: ${RESOURCE_GROUP}"
    
    # Check if resource group already exists
    if az group show --name "${RESOURCE_GROUP}" &> /dev/null; then
        log_warning "Resource group ${RESOURCE_GROUP} already exists"
        return 0
    fi
    
    az group create \
        --name "${RESOURCE_GROUP}" \
        --location "${LOCATION}" \
        --tags purpose=recipe environment=demo recipe=file-upload-processing \
        --output none
    
    log_success "Resource group created: ${RESOURCE_GROUP}"
}

# Function to create storage account
create_storage_account() {
    log_info "Creating storage account: ${STORAGE_ACCOUNT}"
    
    # Check if storage account already exists
    if az storage account show --name "${STORAGE_ACCOUNT}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        log_warning "Storage account ${STORAGE_ACCOUNT} already exists"
    else
        az storage account create \
            --name "${STORAGE_ACCOUNT}" \
            --resource-group "${RESOURCE_GROUP}" \
            --location "${LOCATION}" \
            --sku Standard_LRS \
            --kind StorageV2 \
            --access-tier Hot \
            --tags purpose=file-processing environment=demo \
            --output none
        
        log_success "Storage account created: ${STORAGE_ACCOUNT}"
    fi
    
    # Get storage connection string
    log_info "Retrieving storage connection string..."
    STORAGE_CONNECTION=$(az storage account show-connection-string \
        --name "${STORAGE_ACCOUNT}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query connectionString \
        --output tsv)
    
    if [ -z "${STORAGE_CONNECTION}" ]; then
        log_error "Failed to retrieve storage connection string"
        exit 1
    fi
    
    log_success "Storage connection string retrieved"
}

# Function to create blob container
create_blob_container() {
    log_info "Creating blob container: ${CONTAINER_NAME}"
    
    # Check if container already exists
    if az storage container show \
        --name "${CONTAINER_NAME}" \
        --connection-string "${STORAGE_CONNECTION}" &> /dev/null; then
        log_warning "Container ${CONTAINER_NAME} already exists"
        return 0
    fi
    
    az storage container create \
        --name "${CONTAINER_NAME}" \
        --connection-string "${STORAGE_CONNECTION}" \
        --public-access off \
        --output none
    
    log_success "Blob container created: ${CONTAINER_NAME}"
}

# Function to create function app
create_function_app() {
    log_info "Creating Function App: ${FUNCTION_APP}"
    
    # Check if function app already exists
    if az functionapp show --name "${FUNCTION_APP}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        log_warning "Function App ${FUNCTION_APP} already exists"
    else
        az functionapp create \
            --name "${FUNCTION_APP}" \
            --resource-group "${RESOURCE_GROUP}" \
            --storage-account "${STORAGE_ACCOUNT}" \
            --consumption-plan-location "${LOCATION}" \
            --runtime node \
            --runtime-version 18 \
            --functions-version 4 \
            --tags purpose=file-processing environment=demo \
            --output none
        
        log_success "Function App created: ${FUNCTION_APP}"
        
        # Wait for function app to be fully provisioned
        log_info "Waiting for Function App to be fully provisioned..."
        sleep 30
    fi
}

# Function to configure function app settings
configure_function_app() {
    log_info "Configuring Function App settings..."
    
    az functionapp config appsettings set \
        --name "${FUNCTION_APP}" \
        --resource-group "${RESOURCE_GROUP}" \
        --settings "STORAGE_CONNECTION_STRING=${STORAGE_CONNECTION}" \
        --output none
    
    log_success "Function App configured with storage connection"
}

# Function to create and deploy function code
deploy_function_code() {
    log_info "Creating function code..."
    
    # Create directory for function code
    mkdir -p function-code
    
    # Create function.json configuration
    cat > function-code/function.json << 'EOF'
{
  "bindings": [
    {
      "name": "myBlob",
      "type": "blobTrigger",
      "direction": "in",
      "path": "uploads/{name}",
      "connection": "STORAGE_CONNECTION_STRING"
    }
  ]
}
EOF
    
    # Create JavaScript function code
    cat > function-code/index.js << 'EOF'
module.exports = async function (context, myBlob) {
    const fileName = context.bindingData.name;
    const fileSize = myBlob.length;
    const timestamp = new Date().toISOString();
    
    context.log(`🔥 Processing file: ${fileName}`);
    context.log(`📊 File size: ${fileSize} bytes`);
    context.log(`⏰ Processing time: ${timestamp}`);
    
    // Simulate file processing logic
    if (fileName.toLowerCase().includes('.jpg') || fileName.toLowerCase().includes('.png')) {
        context.log(`🖼️  Image file detected: ${fileName}`);
        context.log(`✅ Image processing completed successfully`);
    } else if (fileName.toLowerCase().includes('.pdf')) {
        context.log(`📄 PDF document detected: ${fileName}`);
        context.log(`✅ PDF processing completed successfully`);
    } else {
        context.log(`📁 Generic file detected: ${fileName}`);
        context.log(`✅ File processing completed successfully`);
    }
    
    context.log(`🎉 File processing workflow completed for: ${fileName}`);
};
EOF
    
    log_success "Function code created"
    
    # Create ZIP package for deployment
    log_info "Creating deployment package..."
    cd function-code
    zip -r ../function-deploy.zip . > /dev/null
    cd ..
    
    # Deploy function code to Azure
    log_info "Deploying function code to Azure..."
    az functionapp deployment source config-zip \
        --name "${FUNCTION_APP}" \
        --resource-group "${RESOURCE_GROUP}" \
        --src function-deploy.zip \
        --output none
    
    log_success "Function deployed successfully"
    
    # Wait for deployment to complete
    log_info "Waiting for deployment to complete..."
    sleep 15
}

# Function to verify deployment
verify_deployment() {
    log_info "Verifying deployment..."
    
    # Check resource group
    if ! az group show --name "${RESOURCE_GROUP}" &> /dev/null; then
        log_error "Resource group verification failed"
        return 1
    fi
    
    # Check storage account
    local storage_state=$(az storage account show \
        --name "${STORAGE_ACCOUNT}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query "provisioningState" \
        --output tsv)
    
    if [ "${storage_state}" != "Succeeded" ]; then
        log_error "Storage account is not in Succeeded state: ${storage_state}"
        return 1
    fi
    
    # Check function app
    local function_state=$(az functionapp show \
        --name "${FUNCTION_APP}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query "state" \
        --output tsv)
    
    if [ "${function_state}" != "Running" ]; then
        log_error "Function App is not in Running state: ${function_state}"
        return 1
    fi
    
    # Check if function exists
    local function_count=$(az functionapp function list \
        --name "${FUNCTION_APP}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query "length(@)" \
        --output tsv)
    
    if [ "${function_count}" -eq 0 ]; then
        log_error "No functions found in Function App"
        return 1
    fi
    
    log_success "All resources verified successfully"
}

# Function to create test files and demonstrate functionality
create_test_files() {
    log_info "Creating test files for demonstration..."
    
    # Create test files
    echo "This is a test file for Azure Functions processing - $(date)" > test-file.txt
    echo "Test image content simulation - $(date)" > test-image.jpg
    echo "Test PDF document content - $(date)" > test-document.pdf
    
    log_success "Test files created"
}

# Function to run basic functionality test
test_functionality() {
    log_info "Testing file upload and processing..."
    
    # Upload test files to trigger function execution
    local timestamp=$(date +%s)
    
    az storage blob upload \
        --file test-file.txt \
        --name "test-document-${timestamp}.txt" \
        --container-name "${CONTAINER_NAME}" \
        --connection-string "${STORAGE_CONNECTION}" \
        --output none
    
    az storage blob upload \
        --file test-image.jpg \
        --name "test-image-${timestamp}.jpg" \
        --container-name "${CONTAINER_NAME}" \
        --connection-string "${STORAGE_CONNECTION}" \
        --output none
    
    az storage blob upload \
        --file test-document.pdf \
        --name "test-pdf-${timestamp}.pdf" \
        --container-name "${CONTAINER_NAME}" \
        --connection-string "${STORAGE_CONNECTION}" \
        --output none
    
    log_success "Test files uploaded successfully"
    log_info "Functions should be triggered automatically"
    log_info "Check the Azure portal or use 'az webapp log tail' to view execution logs"
}

# Function to clean up on error
cleanup_on_error() {
    log_warning "Cleaning up partially created resources..."
    
    if [ -n "${RESOURCE_GROUP:-}" ]; then
        if az group show --name "${RESOURCE_GROUP}" &> /dev/null; then
            log_info "Deleting resource group: ${RESOURCE_GROUP}"
            az group delete --name "${RESOURCE_GROUP}" --yes --no-wait || true
        fi
    fi
    
    # Clean up local files
    rm -f function-deploy.zip test-file.txt test-image.jpg test-document.pdf
    rm -rf function-code
}

# Function to display deployment summary
display_summary() {
    log_success "=== DEPLOYMENT COMPLETED SUCCESSFULLY ==="
    echo
    log_info "Resource Information:"
    echo "  Resource Group: ${RESOURCE_GROUP}"
    echo "  Storage Account: ${STORAGE_ACCOUNT}"
    echo "  Function App: ${FUNCTION_APP}"
    echo "  Blob Container: ${CONTAINER_NAME}"
    echo "  Location: ${LOCATION}"
    echo
    log_info "Test files uploaded to container '${CONTAINER_NAME}'"
    echo
    log_info "Next Steps:"
    echo "  1. View function logs: az webapp log tail --name ${FUNCTION_APP} --resource-group ${RESOURCE_GROUP}"
    echo "  2. Upload more files to test: az storage blob upload --file <your-file> --name <blob-name> --container-name ${CONTAINER_NAME} --connection-string '<connection-string>'"
    echo "  3. View in Azure Portal: https://portal.azure.com/#@/resource/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}"
    echo
    log_info "Deployment information saved to: deployment_info.txt"
    echo
    log_warning "Remember to run ./destroy.sh when you're done to avoid ongoing charges!"
}

# Main deployment function
main() {
    log_info "Starting Azure File Upload Processing deployment..."
    log_info "Recipe: file-upload-processing-functions-blob"
    echo
    
    check_prerequisites
    setup_environment
    create_resource_group
    create_storage_account
    create_blob_container
    create_function_app
    configure_function_app
    deploy_function_code
    verify_deployment
    create_test_files
    test_functionality
    
    # Clean up local function deployment files
    rm -f function-deploy.zip
    rm -rf function-code
    
    display_summary
}

# Script entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi