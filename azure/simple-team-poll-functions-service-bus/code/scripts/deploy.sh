#!/bin/bash

set -euo pipefail

# Simple Team Poll System with Functions and Service Bus - Deployment Script
# This script deploys a complete serverless polling system using Azure Functions and Service Bus

# Color codes for output
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

# Error handling
trap 'log_error "Deployment failed at line $LINENO. Exit code: $?"' ERR

# Configuration and validation
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        log_error "Azure CLI is not installed. Please install Azure CLI first."
        exit 1
    fi
    
    # Check Azure CLI version
    az_version=$(az version --query '"azure-cli"' -o tsv)
    log_info "Azure CLI version: $az_version"
    
    # Check if logged in to Azure
    if ! az account show &> /dev/null; then
        log_error "Not logged in to Azure. Please run 'az login' first."
        exit 1
    fi
    
    # Check if required tools are available
    if ! command -v openssl &> /dev/null; then
        log_error "openssl is required for generating random suffixes."
        exit 1
    fi
    
    if ! command -v zip &> /dev/null; then
        log_error "zip utility is required for function deployment."
        exit 1
    fi
    
    log_success "Prerequisites check completed"
}

# Function to check if resource group exists
resource_group_exists() {
    az group show --name "$1" &> /dev/null
}

# Function to check if storage account exists
storage_account_exists() {
    az storage account show --name "$1" --resource-group "$2" &> /dev/null 2>&1
}

# Function to check if service bus namespace exists
servicebus_namespace_exists() {
    az servicebus namespace show --name "$1" --resource-group "$2" &> /dev/null 2>&1
}

# Function to check if function app exists
function_app_exists() {
    az functionapp show --name "$1" --resource-group "$2" &> /dev/null 2>&1
}

# Main deployment function
deploy_infrastructure() {
    log_info "Starting infrastructure deployment..."
    
    # Generate unique suffix for resource names (idempotent)
    if [[ -z "${RANDOM_SUFFIX:-}" ]]; then
        export RANDOM_SUFFIX=$(openssl rand -hex 3)
        log_info "Generated random suffix: $RANDOM_SUFFIX"
    fi
    
    # Set environment variables for Azure resources
    export RESOURCE_GROUP="rg-recipe-${RANDOM_SUFFIX}"
    export LOCATION="eastus"
    export SUBSCRIPTION_ID=$(az account show --query id --output tsv)
    export SERVICE_BUS_NAMESPACE="sb-poll-${RANDOM_SUFFIX}"
    export FUNCTION_APP_NAME="func-poll-${RANDOM_SUFFIX}"
    export STORAGE_ACCOUNT="sapoll${RANDOM_SUFFIX}"
    
    log_info "Deployment configuration:"
    log_info "  Resource Group: $RESOURCE_GROUP"
    log_info "  Location: $LOCATION"
    log_info "  Subscription: $SUBSCRIPTION_ID"
    log_info "  Service Bus: $SERVICE_BUS_NAMESPACE"
    log_info "  Function App: $FUNCTION_APP_NAME"
    log_info "  Storage Account: $STORAGE_ACCOUNT"
    
    # Create resource group (idempotent)
    if resource_group_exists "$RESOURCE_GROUP"; then
        log_warning "Resource group $RESOURCE_GROUP already exists, skipping creation"
    else
        log_info "Creating resource group..."
        az group create \
            --name "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --tags purpose=recipe environment=demo \
            --output table
        log_success "Resource group created: $RESOURCE_GROUP"
    fi
    
    # Create Service Bus namespace and queue
    if servicebus_namespace_exists "$SERVICE_BUS_NAMESPACE" "$RESOURCE_GROUP"; then
        log_warning "Service Bus namespace $SERVICE_BUS_NAMESPACE already exists, skipping creation"
    else
        log_info "Creating Service Bus namespace..."
        az servicebus namespace create \
            --name "$SERVICE_BUS_NAMESPACE" \
            --resource-group "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --sku Basic \
            --output table
        
        log_info "Waiting for Service Bus namespace to be ready..."
        az servicebus namespace wait \
            --name "$SERVICE_BUS_NAMESPACE" \
            --resource-group "$RESOURCE_GROUP" \
            --created \
            --timeout 300
        log_success "Service Bus namespace created and ready"
    fi
    
    # Create vote processing queue (idempotent)
    log_info "Creating/verifying vote processing queue..."
    az servicebus queue create \
        --name "votes" \
        --namespace-name "$SERVICE_BUS_NAMESPACE" \
        --resource-group "$RESOURCE_GROUP" \
        --max-size 1024 \
        --output table || log_warning "Queue may already exist"
    
    # Get Service Bus connection string
    log_info "Retrieving Service Bus connection string..."
    SERVICE_BUS_CONNECTION=$(az servicebus namespace \
        authorization-rule keys list \
        --name RootManageSharedAccessKey \
        --namespace-name "$SERVICE_BUS_NAMESPACE" \
        --resource-group "$RESOURCE_GROUP" \
        --query primaryConnectionString \
        --output tsv)
    log_success "Service Bus connection string retrieved"
    
    # Create storage account
    if storage_account_exists "$STORAGE_ACCOUNT" "$RESOURCE_GROUP"; then
        log_warning "Storage account $STORAGE_ACCOUNT already exists, skipping creation"
    else
        log_info "Creating storage account..."
        az storage account create \
            --name "$STORAGE_ACCOUNT" \
            --resource-group "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --sku Standard_LRS \
            --kind StorageV2 \
            --output table
        
        log_info "Waiting for storage account to be ready..."
        az storage account wait \
            --name "$STORAGE_ACCOUNT" \
            --resource-group "$RESOURCE_GROUP" \
            --created \
            --timeout 300
        log_success "Storage account created: $STORAGE_ACCOUNT"
    fi
    
    # Get storage connection string
    log_info "Retrieving storage connection string..."
    STORAGE_CONNECTION=$(az storage account show-connection-string \
        --name "$STORAGE_ACCOUNT" \
        --resource-group "$RESOURCE_GROUP" \
        --query connectionString \
        --output tsv)
    
    # Create Function App
    if function_app_exists "$FUNCTION_APP_NAME" "$RESOURCE_GROUP"; then
        log_warning "Function App $FUNCTION_APP_NAME already exists, skipping creation"
    else
        log_info "Creating Function App..."
        az functionapp create \
            --name "$FUNCTION_APP_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --storage-account "$STORAGE_ACCOUNT" \
            --consumption-plan-location "$LOCATION" \
            --runtime node \
            --runtime-version 18 \
            --functions-version 4 \
            --output table
        
        log_info "Waiting for Function App to be ready..."
        az functionapp wait \
            --name "$FUNCTION_APP_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --created \
            --timeout 300
        log_success "Function App created: $FUNCTION_APP_NAME"
    fi
    
    # Configure Service Bus connection
    log_info "Configuring Function App settings..."
    az functionapp config appsettings set \
        --name "$FUNCTION_APP_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --settings "ServiceBusConnection=${SERVICE_BUS_CONNECTION}" \
        --output table
    log_success "Function App configured with Service Bus connection"
}

# Function to create and deploy Azure Functions
deploy_functions() {
    log_info "Creating and deploying Azure Functions..."
    
    # Create temporary directory for functions
    TEMP_DIR=$(mktemp -d)
    FUNCTIONS_DIR="$TEMP_DIR/poll-functions"
    mkdir -p "$FUNCTIONS_DIR"
    
    log_info "Function deployment directory: $FUNCTIONS_DIR"
    
    # Create SubmitVote function
    log_info "Creating SubmitVote function..."
    mkdir -p "$FUNCTIONS_DIR/SubmitVote"
    
    cat > "$FUNCTIONS_DIR/SubmitVote/function.json" << 'EOF'
{
  "bindings": [
    {
      "authLevel": "anonymous",
      "type": "httpTrigger",
      "direction": "in",
      "name": "req",
      "methods": ["post"]
    },
    {
      "type": "http",
      "direction": "out",
      "name": "res"
    },
    {
      "type": "serviceBus",
      "direction": "out",
      "name": "outputSbMsg",
      "queueName": "votes",
      "connection": "ServiceBusConnection"
    }
  ]
}
EOF
    
    cat > "$FUNCTIONS_DIR/SubmitVote/index.js" << 'EOF'
module.exports = async function (context, req) {
    try {
        const { pollId, option, voterId } = req.body;
        
        if (!pollId || !option || !voterId) {
            context.res = {
                status: 400,
                body: { error: "Missing required fields: pollId, option, voterId" }
            };
            return;
        }
        
        const vote = {
            pollId,
            option,
            voterId,
            timestamp: new Date().toISOString(),
            id: `${pollId}-${voterId}-${Date.now()}`
        };
        
        context.bindings.outputSbMsg = vote;
        
        context.res = {
            status: 202,
            body: { 
                message: "Vote submitted successfully",
                voteId: vote.id
            }
        };
    } catch (error) {
        context.log.error('Error submitting vote:', error);
        context.res = {
            status: 500,
            body: { error: "Internal server error" }
        };
    }
};
EOF
    
    # Create ProcessVote function
    log_info "Creating ProcessVote function..."
    mkdir -p "$FUNCTIONS_DIR/ProcessVote"
    
    cat > "$FUNCTIONS_DIR/ProcessVote/function.json" << 'EOF'
{
  "bindings": [
    {
      "name": "mySbMsg",
      "type": "serviceBusTrigger",
      "direction": "in",
      "queueName": "votes",
      "connection": "ServiceBusConnection"
    },
    {
      "name": "outputBlob",
      "type": "blob",
      "direction": "out",
      "path": "poll-results/{pollId}.json",
      "connection": "AzureWebJobsStorage"
    }
  ]
}
EOF
    
    cat > "$FUNCTIONS_DIR/ProcessVote/index.js" << 'EOF'
module.exports = async function (context, mySbMsg) {
    try {
        const vote = mySbMsg;
        const { pollId, option, voterId } = vote;
        
        // Get existing results or initialize
        let results = {};
        try {
            const { BlobServiceClient } = require('@azure/storage-blob');
            const blobServiceClient = BlobServiceClient.fromConnectionString(
                process.env.AzureWebJobsStorage
            );
            const containerClient = blobServiceClient.getContainerClient('poll-results');
            
            // Ensure container exists
            await containerClient.createIfNotExists();
            
            const blobClient = containerClient.getBlobClient(`${pollId}.json`);
            
            if (await blobClient.exists()) {
                const downloadResponse = await blobClient.download();
                const downloaded = await streamToString(downloadResponse.readableStreamBody);
                results = JSON.parse(downloaded);
            }
        } catch (error) {
            context.log('No existing results found, creating new poll results');
        }
        
        // Initialize poll structure if needed
        if (!results.pollId) {
            results = {
                pollId,
                totalVotes: 0,
                options: {},
                voters: new Set(),
                lastUpdated: new Date().toISOString()
            };
        }
        
        // Convert voters back to Set if it was serialized
        results.voters = new Set(results.voters);
        
        // Check for duplicate vote from same voter
        if (!results.voters.has(voterId)) {
            results.voters.add(voterId);
            results.options[option] = (results.options[option] || 0) + 1;
            results.totalVotes++;
            results.lastUpdated = new Date().toISOString();
            
            // Convert Set back to Array for JSON serialization
            const outputResults = {
                ...results,
                voters: Array.from(results.voters)
            };
            
            context.bindings.outputBlob = JSON.stringify(outputResults, null, 2);
            context.log(`Vote processed for poll ${pollId}: ${option} by ${voterId}`);
        } else {
            context.log(`Duplicate vote ignored for poll ${pollId} by ${voterId}`);
        }
        
    } catch (error) {
        context.log.error('Error processing vote:', error);
        throw error;
    }
};

async function streamToString(readableStream) {
    return new Promise((resolve, reject) => {
        const chunks = [];
        readableStream.on('data', (data) => {
            chunks.push(data.toString());
        });
        readableStream.on('end', () => {
            resolve(chunks.join(''));
        });
        readableStream.on('error', reject);
    });
}
EOF
    
    # Create GetResults function
    log_info "Creating GetResults function..."
    mkdir -p "$FUNCTIONS_DIR/GetResults"
    
    cat > "$FUNCTIONS_DIR/GetResults/function.json" << 'EOF'
{
  "bindings": [
    {
      "authLevel": "anonymous",
      "type": "httpTrigger",
      "direction": "in",
      "name": "req",
      "methods": ["get"],
      "route": "results/{pollId}"
    },
    {
      "type": "http",
      "direction": "out",
      "name": "res"
    },
    {
      "name": "inputBlob",
      "type": "blob",
      "direction": "in",
      "path": "poll-results/{pollId}.json",
      "connection": "AzureWebJobsStorage"
    }
  ]
}
EOF
    
    cat > "$FUNCTIONS_DIR/GetResults/index.js" << 'EOF'
module.exports = async function (context, req) {
    try {
        const pollId = context.bindingData.pollId;
        
        if (!context.bindings.inputBlob) {
            context.res = {
                status: 404,
                headers: {
                    'Content-Type': 'application/json',
                    'Access-Control-Allow-Origin': '*'
                },
                body: { error: `Poll ${pollId} not found` }
            };
            return;
        }
        
        const results = JSON.parse(context.bindings.inputBlob);
        
        // Calculate percentages
        const optionsWithPercentages = {};
        Object.keys(results.options).forEach(option => {
            const count = results.options[option];
            const percentage = results.totalVotes > 0 
                ? Math.round((count / results.totalVotes) * 100) 
                : 0;
            optionsWithPercentages[option] = {
                count,
                percentage
            };
        });
        
        context.res = {
            status: 200,
            headers: {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            body: {
                pollId: results.pollId,
                totalVotes: results.totalVotes,
                options: optionsWithPercentages,
                lastUpdated: results.lastUpdated
            }
        };
        
    } catch (error) {
        context.log.error('Error retrieving poll results:', error);
        context.res = {
            status: 500,
            headers: {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            body: { error: "Error retrieving poll results" }
        };
    }
};
EOF
    
    # Create host.json configuration
    log_info "Creating Function App configuration..."
    cat > "$FUNCTIONS_DIR/host.json" << 'EOF'
{
  "version": "2.0",
  "functionTimeout": "00:05:00",
  "extensions": {
    "serviceBus": {
      "prefetchCount": 100,
      "autoCompleteMessages": true
    }
  }
}
EOF
    
    # Create package.json for dependencies
    cat > "$FUNCTIONS_DIR/package.json" << 'EOF'
{
  "name": "poll-functions",
  "version": "1.0.0",
  "dependencies": {
    "@azure/storage-blob": "^12.28.0"
  }
}
EOF
    
    # Create deployment package
    log_info "Creating deployment package..."
    cd "$FUNCTIONS_DIR"
    zip -r poll-functions.zip . > /dev/null
    
    # Deploy to Function App
    log_info "Deploying functions to Azure..."
    az functionapp deployment source config-zip \
        --name "$FUNCTION_APP_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --src poll-functions.zip \
        --build-remote true \
        --output table
    
    # Get Function App URL
    FUNCTION_APP_URL="https://${FUNCTION_APP_NAME}.azurewebsites.net"
    log_success "Functions deployed successfully to: $FUNCTION_APP_URL"
    
    # Clean up temporary directory
    cd - > /dev/null
    rm -rf "$TEMP_DIR"
    log_info "Temporary files cleaned up"
}

# Function to save deployment information
save_deployment_info() {
    log_info "Saving deployment information..."
    
    # Create deployment info file
    DEPLOYMENT_INFO_FILE="./azure-poll-deployment-info.txt"
    cat > "$DEPLOYMENT_INFO_FILE" << EOF
Azure Simple Team Poll System Deployment Information
Generated: $(date)

Resource Group: $RESOURCE_GROUP
Location: $LOCATION
Subscription ID: $SUBSCRIPTION_ID

Service Bus Namespace: $SERVICE_BUS_NAMESPACE
Function App Name: $FUNCTION_APP_NAME
Storage Account: $STORAGE_ACCOUNT
Function App URL: https://${FUNCTION_APP_NAME}.azurewebsites.net

API Endpoints:
- Submit Vote: POST https://${FUNCTION_APP_NAME}.azurewebsites.net/api/SubmitVote
- Get Results: GET https://${FUNCTION_APP_NAME}.azurewebsites.net/api/results/{pollId}

Environment Variables (for cleanup):
export RESOURCE_GROUP="$RESOURCE_GROUP"
export SERVICE_BUS_NAMESPACE="$SERVICE_BUS_NAMESPACE"
export FUNCTION_APP_NAME="$FUNCTION_APP_NAME"
export STORAGE_ACCOUNT="$STORAGE_ACCOUNT"

Test Commands:
# Submit a vote
curl -X POST "https://${FUNCTION_APP_NAME}.azurewebsites.net/api/SubmitVote" \\
    -H "Content-Type: application/json" \\
    -d '{
        "pollId": "team-lunch",
        "option": "Pizza",
        "voterId": "user@company.com"
    }'

# Get poll results
curl "https://${FUNCTION_APP_NAME}.azurewebsites.net/api/results/team-lunch"
EOF
    
    log_success "Deployment information saved to: $DEPLOYMENT_INFO_FILE"
}

# Function to run basic validation
validate_deployment() {
    log_info "Running deployment validation..."
    
    # Check Function App status
    log_info "Checking Function App status..."
    FUNCTION_STATUS=$(az functionapp show \
        --name "$FUNCTION_APP_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --query "state" \
        --output tsv)
    
    if [[ "$FUNCTION_STATUS" == "Running" ]]; then
        log_success "Function App is running successfully"
    else
        log_warning "Function App status: $FUNCTION_STATUS"
    fi
    
    # Check Service Bus queue
    log_info "Checking Service Bus queue..."
    QUEUE_STATUS=$(az servicebus queue show \
        --name votes \
        --namespace-name "$SERVICE_BUS_NAMESPACE" \
        --resource-group "$RESOURCE_GROUP" \
        --query "status" \
        --output tsv)
    
    if [[ "$QUEUE_STATUS" == "Active" ]]; then
        log_success "Service Bus queue is active"
    else
        log_warning "Service Bus queue status: $QUEUE_STATUS"
    fi
    
    log_success "Deployment validation completed"
}

# Main execution
main() {
    log_info "Starting Azure Simple Team Poll System deployment..."
    log_info "=============================================="
    
    # Check prerequisites
    check_prerequisites
    
    # Deploy infrastructure
    deploy_infrastructure
    
    # Deploy functions
    deploy_functions
    
    # Save deployment information
    save_deployment_info
    
    # Validate deployment
    validate_deployment
    
    log_success "=============================================="
    log_success "Deployment completed successfully!"
    log_info ""
    log_info "Your Azure Simple Team Poll System is now ready!"
    log_info "Function App URL: https://${FUNCTION_APP_NAME}.azurewebsites.net"
    log_info ""
    log_info "API Endpoints:"
    log_info "- Submit Vote: POST /api/SubmitVote"
    log_info "- Get Results: GET /api/results/{pollId}"
    log_info ""
    log_info "Deployment details saved to: ./azure-poll-deployment-info.txt"
    log_info "Run './destroy.sh' to clean up all resources when done."
}

# Execute main function
main "$@"