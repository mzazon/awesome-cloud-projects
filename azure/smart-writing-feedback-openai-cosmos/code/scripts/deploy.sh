#!/bin/bash

# Deploy Smart Writing Feedback System with OpenAI and Cosmos
# This script deploys Azure OpenAI Service, Cosmos DB, and Azure Functions
# for intelligent writing analysis and feedback

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✅ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️ $1${NC}"
}

log_error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ❌ $1${NC}"
}

# Error handler
error_exit() {
    log_error "Deployment failed: $1"
    log_error "Check the Azure portal for partially created resources"
    log_error "Run destroy.sh to clean up any created resources"
    exit 1
}

# Trap errors
trap 'error_exit "Script failed at line $LINENO"' ERR

log "=== Azure Smart Writing Feedback System Deployment ==="
log "This script will deploy:"
log "  - Azure OpenAI Service with GPT-4 model"
log "  - Azure Cosmos DB with NoSQL API"
log "  - Azure Functions for serverless processing"
log "  - Azure Storage Account for Functions runtime"

# Check prerequisites
log "Checking prerequisites..."

# Check if Azure CLI is installed
if ! command -v az &> /dev/null; then
    error_exit "Azure CLI is not installed. Please install it first."
fi

# Check if user is logged in
if ! az account show &> /dev/null; then
    error_exit "Not logged into Azure CLI. Please run 'az login' first."
fi

# Check if required tools are available
if ! command -v openssl &> /dev/null; then
    error_exit "openssl is not installed. Required for generating random strings."
fi

# Get Azure subscription info
SUBSCRIPTION_ID=$(az account show --query id --output tsv)
SUBSCRIPTION_NAME=$(az account show --query name --output tsv)
log "Using Azure subscription: $SUBSCRIPTION_NAME ($SUBSCRIPTION_ID)"

# Set default configuration or prompt for customization
DEFAULT_LOCATION="eastus"
DEFAULT_PREFIX="writing-feedback"

echo
read -p "Enter Azure region (default: $DEFAULT_LOCATION): " LOCATION
LOCATION=${LOCATION:-$DEFAULT_LOCATION}

read -p "Enter resource prefix (default: $DEFAULT_PREFIX): " PREFIX
PREFIX=${PREFIX:-$DEFAULT_PREFIX}

# Generate unique suffix for resource names
RANDOM_SUFFIX=$(openssl rand -hex 3)
log "Generated unique suffix: $RANDOM_SUFFIX"

# Set environment variables for Azure resources
export RESOURCE_GROUP="rg-${PREFIX}-${RANDOM_SUFFIX}"
export LOCATION="$LOCATION"
export SUBSCRIPTION_ID="$SUBSCRIPTION_ID"

# Set resource names with unique suffix
export OPENAI_ACCOUNT="openai-${PREFIX}-${RANDOM_SUFFIX}"
export COSMOS_ACCOUNT="cosmos-${PREFIX}-${RANDOM_SUFFIX}"
export FUNCTION_APP="func-${PREFIX}-${RANDOM_SUFFIX}"
export STORAGE_ACCOUNT="st${PREFIX//-/}${RANDOM_SUFFIX}"

# Validate storage account name (must be 3-24 characters, lowercase, numbers only)
if [[ ${#STORAGE_ACCOUNT} -gt 24 ]]; then
    STORAGE_ACCOUNT="st${RANDOM_SUFFIX}wf$(openssl rand -hex 4)"
    log_warning "Storage account name was too long, using: $STORAGE_ACCOUNT"
fi

log "=== Deployment Configuration ==="
log "Resource Group: $RESOURCE_GROUP"
log "Location: $LOCATION"
log "OpenAI Account: $OPENAI_ACCOUNT"
log "Cosmos Account: $COSMOS_ACCOUNT"
log "Function App: $FUNCTION_APP"
log "Storage Account: $STORAGE_ACCOUNT"

echo
read -p "Continue with deployment? (y/N): " CONFIRM
if [[ ! $CONFIRM =~ ^[Yy]$ ]]; then
    log "Deployment cancelled by user"
    exit 0
fi

# Save configuration for destroy script
cat > .deployment_config << EOF
RESOURCE_GROUP="$RESOURCE_GROUP"
LOCATION="$LOCATION"
OPENAI_ACCOUNT="$OPENAI_ACCOUNT"
COSMOS_ACCOUNT="$COSMOS_ACCOUNT"
FUNCTION_APP="$FUNCTION_APP"
STORAGE_ACCOUNT="$STORAGE_ACCOUNT"
DEPLOYMENT_TIME="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
EOF

log "=== Starting Deployment ==="

# Step 1: Create Resource Group
log "Creating resource group: $RESOURCE_GROUP"
az group create \
    --name "$RESOURCE_GROUP" \
    --location "$LOCATION" \
    --tags purpose=writing-feedback environment=demo deployment-script=true \
    --output none

log_success "Resource group created: $RESOURCE_GROUP"

# Step 2: Create Azure OpenAI Service
log "Creating Azure OpenAI Service: $OPENAI_ACCOUNT"
log "This may take 2-3 minutes..."

az cognitiveservices account create \
    --name "$OPENAI_ACCOUNT" \
    --resource-group "$RESOURCE_GROUP" \
    --location "$LOCATION" \
    --kind OpenAI \
    --sku S0 \
    --tags purpose=writing-analysis deployment-script=true \
    --output none

# Get OpenAI endpoint and key
export OPENAI_ENDPOINT=$(az cognitiveservices account show \
    --name "$OPENAI_ACCOUNT" \
    --resource-group "$RESOURCE_GROUP" \
    --query "properties.endpoint" --output tsv)

export OPENAI_KEY=$(az cognitiveservices account keys list \
    --name "$OPENAI_ACCOUNT" \
    --resource-group "$RESOURCE_GROUP" \
    --query "key1" --output tsv)

log_success "Azure OpenAI Service created: $OPENAI_ACCOUNT"

# Step 3: Deploy GPT-4 model
log "Deploying GPT-4 model for text analysis..."
log "This may take 3-5 minutes..."

az cognitiveservices account deployment create \
    --name "$OPENAI_ACCOUNT" \
    --resource-group "$RESOURCE_GROUP" \
    --deployment-name gpt-4-writing-analysis \
    --model-name gpt-4o \
    --model-version "2024-11-20" \
    --model-format OpenAI \
    --sku-capacity 10 \
    --sku-name Standard \
    --output none

# Wait for deployment to be ready
log "Waiting for GPT-4 model deployment to complete..."
sleep 30

# Verify deployment status
DEPLOYMENT_STATUS=$(az cognitiveservices account deployment show \
    --name "$OPENAI_ACCOUNT" \
    --resource-group "$RESOURCE_GROUP" \
    --deployment-name gpt-4-writing-analysis \
    --query "properties.provisioningState" --output tsv)

if [[ "$DEPLOYMENT_STATUS" != "Succeeded" ]]; then
    log_warning "GPT-4 deployment status: $DEPLOYMENT_STATUS"
    log "Continuing with deployment, model may still be provisioning..."
fi

log_success "GPT-4 model deployed for writing analysis"

# Step 4: Create Azure Cosmos DB
log "Creating Azure Cosmos DB: $COSMOS_ACCOUNT"
log "This may take 3-5 minutes..."

az cosmosdb create \
    --name "$COSMOS_ACCOUNT" \
    --resource-group "$RESOURCE_GROUP" \
    --locations regionName="$LOCATION" \
    --default-consistency-level Session \
    --enable-automatic-failover false \
    --tags purpose=feedback-storage deployment-script=true \
    --output none

# Get Cosmos DB connection details
export COSMOS_ENDPOINT=$(az cosmosdb show \
    --name "$COSMOS_ACCOUNT" \
    --resource-group "$RESOURCE_GROUP" \
    --query "documentEndpoint" --output tsv)

export COSMOS_KEY=$(az cosmosdb keys list \
    --name "$COSMOS_ACCOUNT" \
    --resource-group "$RESOURCE_GROUP" \
    --query "primaryMasterKey" --output tsv)

log_success "Cosmos DB account created: $COSMOS_ACCOUNT"

# Step 5: Configure Cosmos DB database and container
log "Creating Cosmos DB database and container..."

az cosmosdb sql database create \
    --account-name "$COSMOS_ACCOUNT" \
    --resource-group "$RESOURCE_GROUP" \
    --name WritingFeedbackDB \
    --throughput 400 \
    --output none

az cosmosdb sql container create \
    --account-name "$COSMOS_ACCOUNT" \
    --resource-group "$RESOURCE_GROUP" \
    --database-name WritingFeedbackDB \
    --name FeedbackContainer \
    --partition-key-path "/userId" \
    --throughput 400 \
    --output none

log_success "Cosmos DB database and container configured"

# Step 6: Create Azure Storage Account
log "Creating Storage Account: $STORAGE_ACCOUNT"

az storage account create \
    --name "$STORAGE_ACCOUNT" \
    --resource-group "$RESOURCE_GROUP" \
    --location "$LOCATION" \
    --sku Standard_LRS \
    --kind StorageV2 \
    --tags purpose=functions-runtime deployment-script=true \
    --output none

# Get storage connection string
export STORAGE_CONNECTION=$(az storage account show-connection-string \
    --name "$STORAGE_ACCOUNT" \
    --resource-group "$RESOURCE_GROUP" \
    --query "connectionString" --output tsv)

log_success "Storage account created: $STORAGE_ACCOUNT"

# Step 7: Create Azure Functions App
log "Creating Azure Functions App: $FUNCTION_APP"

az functionapp create \
    --name "$FUNCTION_APP" \
    --resource-group "$RESOURCE_GROUP" \
    --storage-account "$STORAGE_ACCOUNT" \
    --consumption-plan-location "$LOCATION" \
    --runtime node \
    --runtime-version 20 \
    --functions-version 4 \
    --tags purpose=writing-feedback-api deployment-script=true \
    --output none

log_success "Function App created: $FUNCTION_APP"

# Step 8: Configure Function App settings
log "Configuring Function App settings..."

az functionapp config appsettings set \
    --name "$FUNCTION_APP" \
    --resource-group "$RESOURCE_GROUP" \
    --settings \
    "OPENAI_ENDPOINT=$OPENAI_ENDPOINT" \
    "OPENAI_KEY=$OPENAI_KEY" \
    "COSMOS_ENDPOINT=$COSMOS_ENDPOINT" \
    "COSMOS_KEY=$COSMOS_KEY" \
    "COSMOS_DATABASE=WritingFeedbackDB" \
    "COSMOS_CONTAINER=FeedbackContainer" \
    --output none

log_success "Function App configured with service connections"

# Step 9: Create function code structure
log "Preparing function code deployment..."

# Create temporary directory for function code
TEMP_DIR=$(mktemp -d)
FUNCTION_DIR="$TEMP_DIR/writing-feedback-function"
mkdir -p "$FUNCTION_DIR/src"

# Create package.json
cat > "$FUNCTION_DIR/package.json" << 'EOF'
{
  "name": "writing-feedback-function",
  "version": "1.0.0",
  "description": "Smart writing feedback using Azure OpenAI and Cosmos DB",
  "main": "src/index.js",
  "dependencies": {
    "@azure/functions": "^4.5.0",
    "@azure/cosmos": "^4.1.1",
    "axios": "^1.7.0"
  }
}
EOF

# Create the main function code
cat > "$FUNCTION_DIR/src/index.js" << 'EOF'
const { app } = require('@azure/functions');
const { CosmosClient } = require('@azure/cosmos');
const axios = require('axios');

// Initialize Cosmos DB client
const cosmosClient = new CosmosClient({
    endpoint: process.env.COSMOS_ENDPOINT,
    key: process.env.COSMOS_KEY
});

const database = cosmosClient.database(process.env.COSMOS_DATABASE);
const container = database.container(process.env.COSMOS_CONTAINER);

app.http('analyzeWriting', {
    methods: ['POST'],
    authLevel: 'function',
    handler: async (request, context) => {
        try {
            const requestBody = await request.json();
            const { text, userId, documentId } = requestBody;
            
            if (!text || !userId) {
                return {
                    status: 400,
                    jsonBody: {
                        error: 'Missing required fields: text and userId'
                    }
                };
            }

            // Analyze writing with OpenAI
            const analysis = await analyzeTextWithOpenAI(text);
            
            // Create feedback document
            const feedbackDoc = {
                id: documentId || `feedback_${Date.now()}`,
                userId: userId,
                originalText: text,
                analysis: analysis,
                timestamp: new Date().toISOString(),
                wordCount: text.split(/\s+/).length,
                characterCount: text.length
            };
            
            // Store in Cosmos DB
            await container.items.create(feedbackDoc);
            
            context.log(`Writing analysis completed for user: ${userId}`);
            
            return {
                status: 200,
                jsonBody: {
                    success: true,
                    analysis: analysis,
                    documentId: feedbackDoc.id,
                    timestamp: feedbackDoc.timestamp
                }
            };
            
        } catch (error) {
            context.log.error('Error processing writing analysis:', error);
            return {
                status: 500,
                jsonBody: {
                    error: 'Internal server error during analysis'
                }
            };
        }
    }
});

async function analyzeTextWithOpenAI(text) {
    const prompt = `Analyze the following text for writing quality and provide feedback in JSON format:

TEXT: "${text}"

Please provide analysis in this exact JSON structure:
{
    "sentiment": {
        "overall": "positive/negative/neutral",
        "confidence": 0.0-1.0,
        "details": "explanation"
    },
    "tone": {
        "primary": "professional/casual/formal/friendly/etc",
        "confidence": 0.0-1.0,
        "secondary_tones": ["tone1", "tone2"]
    },
    "clarity": {
        "score": 1-10,
        "issues": ["specific clarity problems"],
        "suggestions": ["specific improvements"]
    },
    "readability": {
        "grade_level": "estimated grade level",
        "complexity": "low/medium/high",
        "recommendations": ["readability improvements"]
    },
    "overall_feedback": {
        "strengths": ["positive aspects"],
        "areas_for_improvement": ["specific suggestions"],
        "overall_score": 1-10
    }
}`;

    try {
        const response = await axios.post(
            `${process.env.OPENAI_ENDPOINT}/openai/deployments/gpt-4-writing-analysis/chat/completions?api-version=2024-10-21`,
            {
                messages: [
                    {
                        role: "system",
                        content: "You are an expert writing analyst. Provide detailed, actionable feedback in valid JSON format only."
                    },
                    {
                        role: "user",
                        content: prompt
                    }
                ],
                max_tokens: 1500,
                temperature: 0.3
            },
            {
                headers: {
                    'Content-Type': 'application/json',
                    'api-key': process.env.OPENAI_KEY
                }
            }
        );
        
        const content = response.data.choices[0].message.content;
        return JSON.parse(content);
        
    } catch (error) {
        console.error('OpenAI API error:', error);
        throw new Error('Failed to analyze text with OpenAI');
    }
}
EOF

# Create host.json
cat > "$FUNCTION_DIR/host.json" << 'EOF'
{
    "version": "2.0",
    "extensionBundle": {
        "id": "Microsoft.Azure.Functions.ExtensionBundle",
        "version": "[4.*, 5.0.0)"
    },
    "functionTimeout": "00:05:00",
    "logging": {
        "applicationInsights": {
            "samplingSettings": {
                "isEnabled": true
            }
        }
    }
}
EOF

# Create .funcignore
cat > "$FUNCTION_DIR/.funcignore" << 'EOF'
.git*
.vscode
local.settings.json
test
.DS_Store
EOF

log_success "Function code structure created"

# Step 10: Deploy function code
log "Deploying function code to Azure Functions..."
log "This may take 2-3 minutes..."

# Change to function directory and deploy
cd "$FUNCTION_DIR"

# Deploy function code using func CLI if available, otherwise use az functionapp deployment
if command -v func &> /dev/null; then
    log "Using Azure Functions Core Tools for deployment..."
    func azure functionapp publish "$FUNCTION_APP" --javascript
else
    log_warning "Azure Functions Core Tools not found, using zip deployment..."
    
    # Create deployment package
    zip -r function-app.zip . -x "*.git*" "*node_modules*" "*.vscode*"
    
    # Deploy using az functionapp deployment
    az functionapp deployment source config-zip \
        --name "$FUNCTION_APP" \
        --resource-group "$RESOURCE_GROUP" \
        --src function-app.zip \
        --output none
fi

# Return to original directory
cd - > /dev/null

# Clean up temporary directory
rm -rf "$TEMP_DIR"

log_success "Function code deployed successfully"

# Step 11: Get deployment outputs
log "=== Deployment Complete ==="

# Get function app URL and keys
FUNCTION_URL=$(az functionapp function show \
    --name "$FUNCTION_APP" \
    --resource-group "$RESOURCE_GROUP" \
    --function-name analyzeWriting \
    --query "invokeUrlTemplate" --output tsv 2>/dev/null || echo "Function URL not available yet")

FUNCTION_KEY=$(az functionapp keys list \
    --name "$FUNCTION_APP" \
    --resource-group "$RESOURCE_GROUP" \
    --query "functionKeys.default" --output tsv 2>/dev/null || echo "Function key not available yet")

# Save deployment outputs
cat >> .deployment_config << EOF
OPENAI_ENDPOINT="$OPENAI_ENDPOINT"
COSMOS_ENDPOINT="$COSMOS_ENDPOINT"
FUNCTION_URL="$FUNCTION_URL"
FUNCTION_KEY="$FUNCTION_KEY"
EOF

log_success "=== Smart Writing Feedback System Deployed Successfully ==="
echo
log "📋 Deployment Summary:"
log "  Resource Group: $RESOURCE_GROUP"
log "  Azure OpenAI: $OPENAI_ACCOUNT"
log "  Cosmos DB: $COSMOS_ACCOUNT"
log "  Function App: $FUNCTION_APP"
log "  Storage Account: $STORAGE_ACCOUNT"
echo
log "🔗 Service Endpoints:"
log "  OpenAI Endpoint: $OPENAI_ENDPOINT"
log "  Cosmos Endpoint: $COSMOS_ENDPOINT"
if [[ "$FUNCTION_URL" != "Function URL not available yet" ]]; then
    log "  Function URL: $FUNCTION_URL"
fi
echo
log "🧪 Test your deployment:"
echo "  curl -X POST \"$FUNCTION_URL?code=$FUNCTION_KEY\" \\"
echo "    -H \"Content-Type: application/json\" \\"
echo "    -d '{\"text\": \"Sample text for analysis\", \"userId\": \"test-user\"}'"
echo
log "💰 Cost Management:"
log "  Monitor costs in Azure Portal under Cost Management"
log "  Consider setting up budget alerts for unexpected charges"
log "  Run destroy.sh when finished testing to avoid ongoing costs"
echo
log "📚 Next Steps:"
log "  1. Test the writing analysis function with sample text"
log "  2. Verify data storage in Cosmos DB"
log "  3. Monitor function execution in Application Insights"
log "  4. Customize the analysis prompts for your use case"
echo
log_success "Deployment configuration saved to .deployment_config"
log_warning "Keep this file for running destroy.sh to clean up resources"

# Final status check
log "Running final status check..."

# Check OpenAI service status
OPENAI_STATUS=$(az cognitiveservices account show \
    --name "$OPENAI_ACCOUNT" \
    --resource-group "$RESOURCE_GROUP" \
    --query "properties.provisioningState" --output tsv)

# Check Cosmos DB status
COSMOS_STATUS=$(az cosmosdb show \
    --name "$COSMOS_ACCOUNT" \
    --resource-group "$RESOURCE_GROUP" \
    --query "provisioningState" --output tsv)

# Check Function App status
FUNCTION_STATUS=$(az functionapp show \
    --name "$FUNCTION_APP" \
    --resource-group "$RESOURCE_GROUP" \
    --query "state" --output tsv)

if [[ "$OPENAI_STATUS" == "Succeeded" && "$COSMOS_STATUS" == "Succeeded" && "$FUNCTION_STATUS" == "Running" ]]; then
    log_success "All services are running successfully! 🎉"
else
    log_warning "Some services may still be starting up:"
    log "  OpenAI Status: $OPENAI_STATUS"
    log "  Cosmos DB Status: $COSMOS_STATUS"
    log "  Function App Status: $FUNCTION_STATUS"
fi

log "Deployment completed at $(date)"