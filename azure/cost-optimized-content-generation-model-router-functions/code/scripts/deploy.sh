#!/bin/bash

# Cost-Optimized Content Generation Deployment Script
# This script deploys the complete Azure infrastructure for intelligent content generation
# using Model Router for cost optimization and Azure Functions for serverless processing

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        error "Azure CLI is not installed. Please install it from https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
        exit 1
    fi
    
    # Check if logged into Azure
    if ! az account show &> /dev/null; then
        error "Not logged into Azure. Please run 'az login' first"
        exit 1
    fi
    
    # Check if Functions Core Tools is installed
    if ! command -v func &> /dev/null; then
        warning "Azure Functions Core Tools not found. Function deployment may require manual steps."
        warning "Install from: https://docs.microsoft.com/en-us/azure/azure-functions/functions-run-local"
    fi
    
    # Check if Node.js is installed
    if ! command -v node &> /dev/null; then
        warning "Node.js not found. Required for Function App development."
        warning "Install Node.js 18+ from: https://nodejs.org/"
    else
        NODE_VERSION=$(node --version | cut -d'v' -f2 | cut -d'.' -f1)
        if [ "$NODE_VERSION" -lt 18 ]; then
            warning "Node.js version $NODE_VERSION detected. Version 18+ recommended for Azure Functions."
        fi
    fi
    
    # Check if jq is installed for JSON processing
    if ! command -v jq &> /dev/null; then
        warning "jq not found. Some operations may require manual JSON parsing."
        warning "Install jq from: https://stedolan.github.io/jq/"
    fi
    
    success "Prerequisites check completed"
}

# Function to set environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    # Generate random suffix for unique resource names
    if ! command -v openssl &> /dev/null; then
        RANDOM_SUFFIX=$(date +%s | tail -c 6)
        warning "openssl not found, using timestamp for random suffix"
    else
        RANDOM_SUFFIX=$(openssl rand -hex 3)
    fi
    
    # Set environment variables
    export RESOURCE_GROUP="rg-content-generation-${RANDOM_SUFFIX}"
    export LOCATION="${AZURE_LOCATION:-eastus}"
    export SUBSCRIPTION_ID=$(az account show --query id --output tsv)
    export STORAGE_ACCOUNT="stcontentgen${RANDOM_SUFFIX}"
    export FUNCTION_APP="func-content-gen-${RANDOM_SUFFIX}"
    export AI_FOUNDRY_RESOURCE="aif-content-gen-${RANDOM_SUFFIX}"
    
    # Validate location
    if ! az account list-locations --query "[?name=='$LOCATION']" --output tsv | grep -q "$LOCATION"; then
        warning "Location '$LOCATION' may not be valid. Using 'eastus' as fallback."
        export LOCATION="eastus"
    fi
    
    log "Environment variables configured:"
    log "  Resource Group: $RESOURCE_GROUP"
    log "  Location: $LOCATION"
    log "  Storage Account: $STORAGE_ACCOUNT"
    log "  Function App: $FUNCTION_APP"
    log "  AI Foundry Resource: $AI_FOUNDRY_RESOURCE"
    log "  Subscription ID: $SUBSCRIPTION_ID"
}

# Function to create resource group
create_resource_group() {
    log "Creating resource group: $RESOURCE_GROUP"
    
    if az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        warning "Resource group $RESOURCE_GROUP already exists"
    else
        az group create \
            --name "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --tags purpose=content-generation environment=demo created-by=deployment-script
        
        success "Resource group created: $RESOURCE_GROUP"
    fi
}

# Function to create AI Foundry resource
create_ai_foundry() {
    log "Creating Azure AI Foundry resource: $AI_FOUNDRY_RESOURCE"
    
    # Check if resource already exists
    if az cognitiveservices account show --name "$AI_FOUNDRY_RESOURCE" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        warning "AI Foundry resource $AI_FOUNDRY_RESOURCE already exists"
    else
        az cognitiveservices account create \
            --name "$AI_FOUNDRY_RESOURCE" \
            --resource-group "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --kind AIServices \
            --sku S0 \
            --custom-domain "$AI_FOUNDRY_RESOURCE" \
            --tags workload=content-generation cost-center=marketing
        
        success "AI Foundry resource created: $AI_FOUNDRY_RESOURCE"
    fi
    
    # Get AI Foundry endpoint and keys
    export AI_FOUNDRY_ENDPOINT=$(az cognitiveservices account show \
        --name "$AI_FOUNDRY_RESOURCE" \
        --resource-group "$RESOURCE_GROUP" \
        --query properties.endpoint --output tsv)
    
    export AI_FOUNDRY_KEY=$(az cognitiveservices account keys list \
        --name "$AI_FOUNDRY_RESOURCE" \
        --resource-group "$RESOURCE_GROUP" \
        --query key1 --output tsv)
    
    log "AI Foundry endpoint: $AI_FOUNDRY_ENDPOINT"
    log "AI Foundry key: [HIDDEN]"
}

# Function to deploy Model Router
deploy_model_router() {
    log "Deploying Model Router for cost-optimized selection..."
    
    # Check if deployment already exists
    if az cognitiveservices account deployment show \
        --name "$AI_FOUNDRY_RESOURCE" \
        --resource-group "$RESOURCE_GROUP" \
        --deployment-name model-router-deployment &> /dev/null; then
        warning "Model Router deployment already exists"
    else
        # Deploy Model Router
        az cognitiveservices account deployment create \
            --name "$AI_FOUNDRY_RESOURCE" \
            --resource-group "$RESOURCE_GROUP" \
            --deployment-name model-router-deployment \
            --model-name model-router \
            --model-version "2025-01-25" \
            --model-format OpenAI \
            --sku-name Standard \
            --sku-capacity 10
        
        # Wait for deployment to complete
        log "Waiting for Model Router deployment to complete..."
        sleep 30
        
        # Verify deployment status
        local deployment_status
        deployment_status=$(az cognitiveservices account deployment show \
            --name "$AI_FOUNDRY_RESOURCE" \
            --resource-group "$RESOURCE_GROUP" \
            --deployment-name model-router-deployment \
            --query properties.provisioningState --output tsv)
        
        if [ "$deployment_status" = "Succeeded" ]; then
            success "Model Router deployed successfully"
        else
            error "Model Router deployment failed with status: $deployment_status"
            exit 1
        fi
    fi
}

# Function to create storage account
create_storage_account() {
    log "Creating storage account: $STORAGE_ACCOUNT"
    
    # Check if storage account already exists
    if az storage account show --name "$STORAGE_ACCOUNT" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        warning "Storage account $STORAGE_ACCOUNT already exists"
    else
        az storage account create \
            --name "$STORAGE_ACCOUNT" \
            --resource-group "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --sku Standard_LRS \
            --kind StorageV2 \
            --access-tier Hot \
            --enable-hierarchical-namespace false
        
        success "Storage account created: $STORAGE_ACCOUNT"
    fi
    
    # Get storage account connection string
    export STORAGE_CONNECTION_STRING=$(az storage account show-connection-string \
        --name "$STORAGE_ACCOUNT" \
        --resource-group "$RESOURCE_GROUP" \
        --query connectionString --output tsv)
    
    # Create containers
    log "Creating storage containers..."
    
    az storage container create \
        --name content-requests \
        --connection-string "$STORAGE_CONNECTION_STRING" \
        --public-access off \
        --fail-on-exist false
    
    az storage container create \
        --name generated-content \
        --connection-string "$STORAGE_CONNECTION_STRING" \
        --public-access off \
        --fail-on-exist false
    
    success "Storage containers created successfully"
}

# Function to create Function App
create_function_app() {
    log "Creating Function App: $FUNCTION_APP"
    
    # Check if Function App already exists
    if az functionapp show --name "$FUNCTION_APP" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        warning "Function App $FUNCTION_APP already exists"
    else
        az functionapp create \
            --name "$FUNCTION_APP" \
            --resource-group "$RESOURCE_GROUP" \
            --storage-account "$STORAGE_ACCOUNT" \
            --consumption-plan-location "$LOCATION" \
            --runtime node \
            --runtime-version 18 \
            --functions-version 4 \
            --os-type Linux
        
        success "Function App created: $FUNCTION_APP"
    fi
    
    # Configure application settings
    log "Configuring Function App settings..."
    
    az functionapp config appsettings set \
        --name "$FUNCTION_APP" \
        --resource-group "$RESOURCE_GROUP" \
        --settings \
        "AI_FOUNDRY_ENDPOINT=$AI_FOUNDRY_ENDPOINT" \
        "AI_FOUNDRY_KEY=$AI_FOUNDRY_KEY" \
        "STORAGE_CONNECTION_STRING=$STORAGE_CONNECTION_STRING" \
        "MODEL_DEPLOYMENT_NAME=model-router-deployment"
    
    success "Function App configured with AI integration settings"
}

# Function to create function code
create_function_code() {
    log "Creating Function App code..."
    
    # Create temporary directory for function code
    local temp_dir="/tmp/content-functions-$$"
    mkdir -p "$temp_dir"
    cd "$temp_dir"
    
    # Initialize function project
    if command -v func &> /dev/null; then
        func init --javascript --name ContentAnalyzer
        cd ContentAnalyzer
        
        # Create ContentAnalyzer function
        func new --template "Blob trigger" --name ContentAnalyzer
        
        # Create ContentAnalyzer function code
        cat > ContentAnalyzer/index.js << 'EOF'
const { app } = require('@azure/functions');

app.storageBlob('ContentAnalyzer', {
    path: 'content-requests/{name}',
    connection: 'STORAGE_CONNECTION_STRING',
    source: 'EventGrid',
    handler: async (blob, context) => {
        try {
            const contentRequest = JSON.parse(blob.toString());
            
            // Analyze content complexity
            const complexity = analyzeComplexity(contentRequest);
            
            // Determine optimal model based on complexity
            const modelSelection = selectOptimalModel(complexity);
            
            context.log(`Content analyzed: ${contentRequest.title}, Complexity: ${complexity.level}, Model: ${modelSelection.model}`);
            
            // Add analysis results to request
            contentRequest.analysis = {
                complexity: complexity,
                modelSelection: modelSelection,
                timestamp: new Date().toISOString()
            };
            
            // Store analyzed request for processing
            await storeAnalyzedRequest(contentRequest, context);
            
        } catch (error) {
            context.log.error('Content analysis failed:', error);
            throw error;
        }
    }
});

function analyzeComplexity(request) {
    let score = 0;
    
    // Content length factor
    const wordCount = request.content ? request.content.split(' ').length : 0;
    if (wordCount > 1000) score += 3;
    else if (wordCount > 500) score += 2;
    else score += 1;
    
    // Content type factor
    const contentType = request.type || 'general';
    if (contentType.includes('technical') || contentType.includes('research')) score += 2;
    if (contentType.includes('creative') || contentType.includes('marketing')) score += 1;
    
    // Complexity indicators
    const complexityKeywords = ['analysis', 'detailed', 'comprehensive', 'technical', 'professional'];
    const hasComplexKeywords = complexityKeywords.some(keyword => 
        request.instructions?.toLowerCase().includes(keyword) || 
        request.content?.toLowerCase().includes(keyword)
    );
    if (hasComplexKeywords) score += 1;
    
    return {
        score: score,
        level: score >= 5 ? 'high' : score >= 3 ? 'medium' : 'low',
        factors: { wordCount, contentType, hasComplexKeywords }
    };
}

function selectOptimalModel(complexity) {
    switch (complexity.level) {
        case 'high':
            return { 
                model: 'gpt-4o', 
                reasoning: 'Complex content requiring advanced capabilities',
                estimatedCost: 'high'
            };
        case 'medium':
            return { 
                model: 'gpt-4o-mini', 
                reasoning: 'Balanced performance and cost for standard content',
                estimatedCost: 'medium'
            };
        default:
            return { 
                model: 'gpt-3.5-turbo', 
                reasoning: 'Cost-optimized for simple content',
                estimatedCost: 'low'
            };
    }
}

async function storeAnalyzedRequest(request, context) {
    // In production, store in a queue or database for processing
    context.log('Analyzed request ready for content generation:', JSON.stringify(request.analysis));
}
EOF
        
        # Create ContentGenerator function
        func new --template "Queue trigger" --name ContentGenerator
        
        # Create ContentGenerator function code
        cat > ContentGenerator/index.js << 'EOF'
const { app } = require('@azure/functions');
const axios = require('axios');

app.storageQueue('ContentGenerator', {
    queueName: 'content-generation-queue',
    connection: 'STORAGE_CONNECTION_STRING',
    handler: async (queueItem, context) => {
        try {
            const request = typeof queueItem === 'string' ? JSON.parse(queueItem) : queueItem;
            
            context.log(`Generating content with model: ${request.analysis.modelSelection.model}`);
            
            // Generate content using Model Router
            const generatedContent = await generateContent(request, context);
            
            // Store generated content
            await storeGeneratedContent(request, generatedContent, context);
            
            // Log cost metrics
            logCostMetrics(request, generatedContent, context);
            
        } catch (error) {
            context.log.error('Content generation failed:', error);
            throw error;
        }
    }
});

async function generateContent(request, context) {
    const endpoint = process.env.AI_FOUNDRY_ENDPOINT;
    const apiKey = process.env.AI_FOUNDRY_KEY;
    const deploymentName = process.env.MODEL_DEPLOYMENT_NAME;
    
    const prompt = buildPrompt(request);
    
    const response = await axios.post(`${endpoint}/openai/deployments/${deploymentName}/chat/completions?api-version=2024-10-21`, {
        messages: [
            {
                role: "system",
                content: "You are a professional content creator. Generate high-quality content based on the user's requirements."
            },
            {
                role: "user",
                content: prompt
            }
        ],
        max_tokens: calculateMaxTokens(request.analysis.complexity.level),
        temperature: 0.7
    }, {
        headers: {
            'api-key': apiKey,
            'Content-Type': 'application/json'
        }
    });
    
    return {
        content: response.data.choices[0].message.content,
        model: response.data.model || 'model-router',
        usage: response.data.usage,
        cost: calculateCost(response.data.usage, request.analysis.modelSelection.model)
    };
}

function buildPrompt(request) {
    return `
Content Type: ${request.type || 'General'}
Title: ${request.title || 'Untitled'}
Instructions: ${request.instructions || 'Create engaging content'}
Target Audience: ${request.audience || 'General audience'}
Tone: ${request.tone || 'Professional'}

${request.content ? `Reference Content: ${request.content}` : ''}

Please generate content according to these specifications.
    `.trim();
}

function calculateMaxTokens(complexityLevel) {
    switch (complexityLevel) {
        case 'high': return 2000;
        case 'medium': return 1000;
        default: return 500;
    }
}

function calculateCost(usage, model) {
    // Current Azure OpenAI pricing per 1K tokens (as of 2025)
    const pricing = {
        'gpt-4o': { input: 0.005, output: 0.015 },
        'gpt-4o-mini': { input: 0.00015, output: 0.0006 },
        'gpt-3.5-turbo': { input: 0.0005, output: 0.0015 }
    };
    
    const modelPricing = pricing[model] || pricing['gpt-4o-mini'];
    const inputCost = (usage.prompt_tokens / 1000) * modelPricing.input;
    const outputCost = (usage.completion_tokens / 1000) * modelPricing.output;
    
    return {
        inputCost: inputCost,
        outputCost: outputCost,
        totalCost: inputCost + outputCost,
        savings: calculateSavings(usage, model)
    };
}

function calculateSavings(usage, selectedModel) {
    const baselineCost = calculateCost(usage, 'gpt-4o').totalCost;
    const actualCost = calculateCost(usage, selectedModel).totalCost;
    
    return {
        amount: baselineCost - actualCost,
        percentage: ((baselineCost - actualCost) / baselineCost) * 100
    };
}

async function storeGeneratedContent(request, content, context) {
    const result = {
        originalRequest: request,
        generatedContent: content.content,
        metadata: {
            modelUsed: content.model,
            usage: content.usage,
            cost: content.cost,
            timestamp: new Date().toISOString()
        }
    };
    
    context.log('Content generated successfully', {
        model: content.model,
        cost: content.cost.totalCost,
        savings: content.cost.savings
    });
}

function logCostMetrics(request, content, context) {
    context.log('Cost Metrics:', {
        modelSelected: request.analysis.modelSelection.model,
        actualCost: content.cost.totalCost,
        estimatedSavings: content.cost.savings.amount,
        savingsPercentage: content.cost.savings.percentage.toFixed(2) + '%'
    });
}
EOF
        
        # Install required npm packages
        npm init -y
        npm install axios @azure/storage-blob
        
        success "Function code created successfully"
        
        # Deploy functions if possible
        log "Attempting to deploy functions..."
        if func azure functionapp publish "$FUNCTION_APP"; then
            success "Functions deployed successfully"
        else
            warning "Function deployment failed. Manual deployment may be required."
        fi
        
    else
        warning "Azure Functions Core Tools not available. Skipping function code creation."
        warning "Manual function deployment will be required."
    fi
    
    # Return to original directory
    cd - > /dev/null
    rm -rf "$temp_dir"
}

# Function to configure Event Grid
configure_event_grid() {
    log "Configuring Event Grid subscription..."
    
    # Get storage account ID
    local storage_account_id
    storage_account_id=$(az storage account show \
        --name "$STORAGE_ACCOUNT" \
        --resource-group "$RESOURCE_GROUP" \
        --query id --output tsv)
    
    # Create Event Grid subscription
    local subscription_name="content-processing-subscription"
    
    if az eventgrid event-subscription show \
        --name "$subscription_name" \
        --source-resource-id "$storage_account_id" &> /dev/null; then
        warning "Event Grid subscription already exists"
    else
        az eventgrid event-subscription create \
            --name "$subscription_name" \
            --source-resource-id "$storage_account_id" \
            --endpoint-type azurefunction \
            --endpoint "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Web/sites/$FUNCTION_APP/functions/ContentAnalyzer" \
            --included-event-types Microsoft.Storage.BlobCreated \
            --subject-begins-with /blobServices/default/containers/content-requests/
        
        success "Event Grid subscription configured"
    fi
}

# Function to configure monitoring
configure_monitoring() {
    log "Configuring cost monitoring and alerts..."
    
    # Create budget for content generation workload
    local budget_name="content-generation-budget"
    
    if az consumption budget show --budget-name "$budget_name" &> /dev/null; then
        warning "Budget already exists"
    else
        # Note: Budget creation may require additional permissions
        local start_date
        start_date=$(date -d 'first day of this month' '+%Y-%m-%d' 2>/dev/null || date -v1d '+%Y-%m-%d')
        
        az consumption budget create \
            --amount 100 \
            --budget-name "$budget_name" \
            --category Cost \
            --time-grain Monthly \
            --time-period start-date="$start_date" \
            --notifications amount=80 \
            --notifications threshold-type=Actual \
            --notifications contact-emails="admin@company.com" || {
            warning "Budget creation failed. May require Billing Administrator role."
        }
    fi
    
    # Create alerts for AI service costs
    local alert_name="ai-foundry-cost-alert"
    
    if az monitor metrics alert show \
        --name "$alert_name" \
        --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        warning "Cost alert already exists"
    else
        az monitor metrics alert create \
            --name "$alert_name" \
            --resource-group "$RESOURCE_GROUP" \
            --description "Alert when AI Foundry costs exceed threshold" \
            --severity 2 \
            --evaluation-frequency 5m \
            --window-size 15m \
            --auto-mitigate true || {
            warning "Alert creation failed. Monitor configuration may need manual setup."
        }
    fi
    
    success "Monitoring configuration completed"
}

# Function to verify deployment
verify_deployment() {
    log "Verifying deployment..."
    
    local errors=0
    
    # Check resource group
    if ! az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        error "Resource group not found"
        ((errors++))
    fi
    
    # Check AI Foundry resource
    if ! az cognitiveservices account show --name "$AI_FOUNDRY_RESOURCE" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        error "AI Foundry resource not found"
        ((errors++))
    fi
    
    # Check storage account
    if ! az storage account show --name "$STORAGE_ACCOUNT" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        error "Storage account not found"
        ((errors++))
    fi
    
    # Check Function App
    if ! az functionapp show --name "$FUNCTION_APP" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        error "Function App not found"
        ((errors++))
    fi
    
    if [ $errors -eq 0 ]; then
        success "All resources deployed successfully!"
        success "Deployment verification completed"
        
        log "Deployment Summary:"
        log "  Resource Group: $RESOURCE_GROUP"
        log "  AI Foundry Resource: $AI_FOUNDRY_RESOURCE"
        log "  Storage Account: $STORAGE_ACCOUNT"
        log "  Function App: $FUNCTION_APP"
        log "  Location: $LOCATION"
        
        log "Next Steps:"
        log "1. Test content generation by uploading a JSON request to the 'content-requests' container"
        log "2. Monitor function logs in Azure Portal"
        log "3. Review cost metrics in Azure Cost Management"
        log "4. Configure additional monitoring as needed"
        
    else
        error "Deployment verification failed with $errors errors"
        exit 1
    fi
}

# Main deployment function
main() {
    log "Starting Azure Cost-Optimized Content Generation deployment..."
    
    check_prerequisites
    setup_environment
    create_resource_group
    create_ai_foundry
    deploy_model_router
    create_storage_account
    create_function_app
    create_function_code
    configure_event_grid
    configure_monitoring
    verify_deployment
    
    success "Deployment completed successfully!"
    
    # Save deployment information
    cat > "deployment-info-${RANDOM_SUFFIX}.txt" << EOF
Azure Cost-Optimized Content Generation Deployment
Deployment Date: $(date)
Resource Group: $RESOURCE_GROUP
Location: $LOCATION
AI Foundry Resource: $AI_FOUNDRY_RESOURCE
Storage Account: $STORAGE_ACCOUNT
Function App: $FUNCTION_APP
Subscription ID: $SUBSCRIPTION_ID

To clean up this deployment, run:
./destroy.sh $RESOURCE_GROUP
EOF
    
    log "Deployment information saved to: deployment-info-${RANDOM_SUFFIX}.txt"
}

# Run main function
main "$@"