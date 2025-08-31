#!/bin/bash

# Customer Support Assistant with OpenAI Assistants and Functions - Deployment Script
# This script automates the deployment of the customer support assistant solution
# Uses Azure CLI to provision Azure OpenAI Service, Functions, and Storage resources

set -euo pipefail

# Color codes for output formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
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

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"
DEPLOYMENT_LOG="$SCRIPT_DIR/deployment.log"

# Initialize deployment log
exec > >(tee -a "$DEPLOYMENT_LOG")
exec 2>&1

log "Starting Customer Support Assistant deployment..."
log "Script directory: $SCRIPT_DIR"
log "Project root: $PROJECT_ROOT"

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        error "Azure CLI is not installed. Please install it from: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
        exit 1
    fi
    
    # Check if Node.js is installed
    if ! command -v node &> /dev/null; then
        error "Node.js is not installed. Please install Node.js 20+ from: https://nodejs.org/"
        exit 1
    fi
    
    # Check Node.js version
    NODE_VERSION=$(node --version | cut -d'v' -f2 | cut -d'.' -f1)
    if [ "$NODE_VERSION" -lt 20 ]; then
        error "Node.js version 20+ is required. Current version: $(node --version)"
        exit 1
    fi
    
    # Check if Azure Functions Core Tools is installed
    if ! command -v func &> /dev/null; then
        error "Azure Functions Core Tools is not installed. Please install from: https://docs.microsoft.com/en-us/azure/azure-functions/functions-run-local"
        exit 1
    fi
    
    # Check if jq is installed for JSON parsing
    if ! command -v jq &> /dev/null; then
        warning "jq is not installed. Installing via package manager..."
        if command -v apt-get &> /dev/null; then
            sudo apt-get update && sudo apt-get install -y jq
        elif command -v yum &> /dev/null; then
            sudo yum install -y jq
        elif command -v brew &> /dev/null; then
            brew install jq
        else
            error "Could not install jq. Please install it manually."
            exit 1
        fi
    fi
    
    # Check Azure CLI login status
    if ! az account show &> /dev/null; then
        error "Not logged into Azure CLI. Please run 'az login' first."
        exit 1
    fi
    
    success "Prerequisites check completed successfully"
}

# Function to set environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    # Generate unique suffix for resource names
    export RANDOM_SUFFIX=$(openssl rand -hex 3 | tr '[:upper:]' '[:lower:]')
    log "Generated random suffix: $RANDOM_SUFFIX"
    
    # Set default location if not provided
    export LOCATION="${LOCATION:-eastus}"
    
    # Get subscription ID
    export SUBSCRIPTION_ID=$(az account show --query id --output tsv)
    log "Using subscription: $SUBSCRIPTION_ID"
    
    # Set resource names with unique suffixes
    export RESOURCE_GROUP="rg-support-assistant-${RANDOM_SUFFIX}"
    export STORAGE_ACCOUNT="supportdata${RANDOM_SUFFIX}"
    export FUNCTION_APP="support-functions-${RANDOM_SUFFIX}"
    export OPENAI_ACCOUNT="support-openai-${RANDOM_SUFFIX}"
    
    # Create deployment state file
    STATE_FILE="$SCRIPT_DIR/deployment-state.json"
    cat > "$STATE_FILE" << EOF
{
    "deploymentId": "$(date +%s)",
    "randomSuffix": "$RANDOM_SUFFIX",
    "resourceGroup": "$RESOURCE_GROUP",
    "storageAccount": "$STORAGE_ACCOUNT",
    "functionApp": "$FUNCTION_APP",
    "openaiAccount": "$OPENAI_ACCOUNT",
    "location": "$LOCATION",
    "subscriptionId": "$SUBSCRIPTION_ID",
    "deploymentTime": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF
    
    log "Environment variables configured:"
    log "  Resource Group: $RESOURCE_GROUP"
    log "  Storage Account: $STORAGE_ACCOUNT"
    log "  Function App: $FUNCTION_APP"
    log "  OpenAI Account: $OPENAI_ACCOUNT"
    log "  Location: $LOCATION"
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
            --tags purpose=recipe environment=demo project=customer-support-assistant \
            --output none
        
        success "Resource group created: $RESOURCE_GROUP"
    fi
}

# Function to create storage account
create_storage_account() {
    log "Creating storage account: $STORAGE_ACCOUNT"
    
    # Check if storage account name is available
    if ! az storage account check-name --name "$STORAGE_ACCOUNT" --query nameAvailable --output tsv | grep -q "true"; then
        error "Storage account name $STORAGE_ACCOUNT is not available"
        exit 1
    fi
    
    az storage account create \
        --name "$STORAGE_ACCOUNT" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --sku Standard_LRS \
        --kind StorageV2 \
        --access-tier Hot \
        --tags purpose=recipe environment=demo \
        --output none
    
    # Get storage connection string
    export STORAGE_CONNECTION=$(az storage account show-connection-string \
        --name "$STORAGE_ACCOUNT" \
        --resource-group "$RESOURCE_GROUP" \
        --query connectionString --output tsv)
    
    success "Storage account created: $STORAGE_ACCOUNT"
}

# Function to initialize storage structures
initialize_storage() {
    log "Initializing storage data structures..."
    
    # Create Table Storage for tickets
    az storage table create \
        --name tickets \
        --connection-string "$STORAGE_CONNECTION" \
        --output none
    
    # Create Table Storage for customers
    az storage table create \
        --name customers \
        --connection-string "$STORAGE_CONNECTION" \
        --output none
    
    # Create Blob container for FAQ documents
    az storage container create \
        --name faqs \
        --connection-string "$STORAGE_CONNECTION" \
        --public-access off \
        --output none
    
    # Create Queue for escalations
    az storage queue create \
        --name escalations \
        --connection-string "$STORAGE_CONNECTION" \
        --output none
    
    success "Storage data structures initialized"
}

# Function to create Azure OpenAI Service
create_openai_service() {
    log "Creating Azure OpenAI Service: $OPENAI_ACCOUNT"
    
    # Check if cognitive services account name is available
    if az cognitiveservices account show --name "$OPENAI_ACCOUNT" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        warning "OpenAI account $OPENAI_ACCOUNT already exists"
    else
        az cognitiveservices account create \
            --name "$OPENAI_ACCOUNT" \
            --resource-group "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --kind OpenAI \
            --sku S0 \
            --custom-domain "$OPENAI_ACCOUNT" \
            --tags purpose=recipe environment=demo \
            --output none
        
        success "Azure OpenAI Service created: $OPENAI_ACCOUNT"
    fi
    
    # Get OpenAI endpoint and key
    export OPENAI_ENDPOINT=$(az cognitiveservices account show \
        --name "$OPENAI_ACCOUNT" \
        --resource-group "$RESOURCE_GROUP" \
        --query properties.endpoint --output tsv)
    
    export OPENAI_KEY=$(az cognitiveservices account keys list \
        --name "$OPENAI_ACCOUNT" \
        --resource-group "$RESOURCE_GROUP" \
        --query key1 --output tsv)
    
    log "OpenAI endpoint: $OPENAI_ENDPOINT"
}

# Function to deploy GPT-4o model
deploy_gpt4o_model() {
    log "Deploying GPT-4o model..."
    
    # Check if model deployment already exists
    if az cognitiveservices account deployment show \
        --name "$OPENAI_ACCOUNT" \
        --resource-group "$RESOURCE_GROUP" \
        --deployment-name gpt-4o &> /dev/null; then
        warning "GPT-4o model deployment already exists"
    else
        az cognitiveservices account deployment create \
            --name "$OPENAI_ACCOUNT" \
            --resource-group "$RESOURCE_GROUP" \
            --deployment-name gpt-4o \
            --model-name gpt-4o \
            --model-version "2024-11-20" \
            --model-format OpenAI \
            --scale-settings-scale-type Standard \
            --output none
        
        # Wait for deployment to complete
        log "Waiting for model deployment to complete..."
        sleep 30
        
        success "GPT-4o model deployed successfully"
    fi
}

# Function to create Function App
create_function_app() {
    log "Creating Function App: $FUNCTION_APP"
    
    if az functionapp show --name "$FUNCTION_APP" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        warning "Function App $FUNCTION_APP already exists"
    else
        az functionapp create \
            --name "$FUNCTION_APP" \
            --resource-group "$RESOURCE_GROUP" \
            --storage-account "$STORAGE_ACCOUNT" \
            --consumption-plan-location "$LOCATION" \
            --runtime node \
            --runtime-version 20 \
            --functions-version 4 \
            --tags purpose=recipe environment=demo \
            --output none
        
        success "Function App created: $FUNCTION_APP"
    fi
    
    # Configure Function App settings
    log "Configuring Function App settings..."
    az functionapp config appsettings set \
        --name "$FUNCTION_APP" \
        --resource-group "$RESOURCE_GROUP" \
        --settings \
            "STORAGE_CONNECTION=$STORAGE_CONNECTION" \
            "OPENAI_ENDPOINT=$OPENAI_ENDPOINT" \
            "OPENAI_KEY=$OPENAI_KEY" \
        --output none
    
    success "Function App configured with required settings"
}

# Function to create and deploy functions
deploy_support_functions() {
    log "Creating and deploying support functions..."
    
    # Create temporary directory for function development
    FUNCTIONS_DIR="$SCRIPT_DIR/temp-functions"
    rm -rf "$FUNCTIONS_DIR"
    mkdir -p "$FUNCTIONS_DIR"
    cd "$FUNCTIONS_DIR"
    
    # Initialize Function App project
    func init --javascript --worker-runtime node
    
    # Create function templates
    func new --name ticketLookup --template "HTTP trigger" --authlevel function
    func new --name faqRetrieval --template "HTTP trigger" --authlevel function
    func new --name ticketCreation --template "HTTP trigger" --authlevel function
    func new --name escalation --template "HTTP trigger" --authlevel function
    
    # Implement ticket lookup function
    cat > ticketLookup/index.js << 'EOF'
const { TableClient } = require("@azure/data-tables");

module.exports = async function (context, req) {
    const ticketId = req.body.ticketId;
    
    if (!ticketId) {
        context.res = {
            status: 400,
            body: { error: "Ticket ID is required" }
        };
        return;
    }

    try {
        const tableClient = TableClient.fromConnectionString(
            process.env.STORAGE_CONNECTION,
            "tickets"
        );

        const ticket = await tableClient.getEntity("ticket", ticketId);
        
        context.res = {
            status: 200,
            body: {
                ticketId: ticket.rowKey,
                status: ticket.status,
                priority: ticket.priority,
                subject: ticket.subject,
                description: ticket.description,
                createdDate: ticket.createdDate,
                lastUpdated: ticket.lastUpdated
            }
        };
    } catch (error) {
        if (error.statusCode === 404) {
            context.res = {
                status: 404,
                body: { error: "Ticket not found" }
            };
        } else {
            context.res = {
                status: 500,
                body: { error: "Internal server error" }
            };
        }
    }
};
EOF

    # Update function.json for ticket lookup
    cat > ticketLookup/function.json << 'EOF'
{
  "bindings": [
    {
      "authLevel": "function",
      "type": "httpTrigger",
      "direction": "in",
      "name": "req",
      "methods": ["post"]
    },
    {
      "type": "http",
      "direction": "out",
      "name": "res"
    }
  ]
}
EOF

    # Implement FAQ retrieval function
    cat > faqRetrieval/index.js << 'EOF'
const { BlobServiceClient } = require("@azure/storage-blob");

module.exports = async function (context, req) {
    const query = req.body.query || "";
    
    try {
        const blobServiceClient = BlobServiceClient.fromConnectionString(
            process.env.STORAGE_CONNECTION
        );
        
        const containerClient = blobServiceClient.getContainerClient("faqs");
        
        // Simple FAQ matching based on query keywords
        const faqs = [
            {
                question: "How do I reset my password?",
                answer: "Click 'Forgot Password' on the login page and follow the email instructions.",
                category: "account"
            },
            {
                question: "What are your business hours?",
                answer: "We're open Monday-Friday 9am-6pm EST. Weekend support available via chat.",
                category: "general"
            },
            {
                question: "How do I cancel my subscription?",
                answer: "Go to Account Settings > Billing > Cancel Subscription. Contact support if you need assistance.",
                category: "billing"
            },
            {
                question: "Is my data secure?",
                answer: "Yes, we use enterprise-grade encryption and comply with SOC2 and GDPR standards.",
                category: "security"
            }
        ];
        
        // Filter FAQs based on query
        const matchingFaqs = faqs.filter(faq => 
            faq.question.toLowerCase().includes(query.toLowerCase()) ||
            faq.answer.toLowerCase().includes(query.toLowerCase()) ||
            faq.category.toLowerCase().includes(query.toLowerCase())
        );
        
        context.res = {
            status: 200,
            body: {
                query: query,
                results: matchingFaqs.slice(0, 3) // Return top 3 matches
            }
        };
    } catch (error) {
        context.res = {
            status: 500,
            body: { error: "Failed to retrieve FAQs" }
        };
    }
};
EOF

    # Update function.json for FAQ retrieval
    cat > faqRetrieval/function.json << 'EOF'
{
  "bindings": [
    {
      "authLevel": "function",
      "type": "httpTrigger",  
      "direction": "in",
      "name": "req",
      "methods": ["post"]
    },
    {
      "type": "http",
      "direction": "out",
      "name": "res"
    }
  ]
}
EOF

    # Implement ticket creation function
    cat > ticketCreation/index.js << 'EOF'
const { TableClient } = require("@azure/data-tables");

module.exports = async function (context, req) {
    const { subject, description, priority = "medium", customerId } = req.body;
    
    if (!subject || !description) {
        context.res = {
            status: 400,
            body: { error: "Subject and description are required" }
        };
        return;
    }

    try {
        const tableClient = TableClient.fromConnectionString(
            process.env.STORAGE_CONNECTION,
            "tickets"
        );

        const ticketId = `TKT-${Date.now()}`;
        const ticket = {
            partitionKey: "ticket",
            rowKey: ticketId,
            subject: subject,
            description: description,
            priority: priority,
            status: "open",
            customerId: customerId || "anonymous",
            createdDate: new Date().toISOString(),
            lastUpdated: new Date().toISOString()
        };

        await tableClient.createEntity(ticket);
        
        context.res = {
            status: 201,
            body: {
                ticketId: ticketId,
                status: "created",
                message: `Ticket ${ticketId} has been created successfully`
            }
        };
    } catch (error) {
        context.res = {
            status: 500,
            body: { error: "Failed to create ticket" }
        };
    }
};
EOF

    # Update function.json for ticket creation
    cat > ticketCreation/function.json << 'EOF'
{
  "bindings": [
    {
      "authLevel": "function",
      "type": "httpTrigger",
      "direction": "in", 
      "name": "req",
      "methods": ["post"]
    },
    {
      "type": "http",
      "direction": "out",
      "name": "res"
    }
  ]
}
EOF

    # Implement escalation function
    cat > escalation/index.js << 'EOF'
const { QueueServiceClient } = require("@azure/storage-queue");

module.exports = async function (context, req) {
    const { ticketId, reason, priority = "high" } = req.body;
    
    if (!ticketId || !reason) {
        context.res = {
            status: 400,
            body: { error: "Ticket ID and reason are required" }
        };
        return;
    }

    try {
        const queueServiceClient = QueueServiceClient.fromConnectionString(
            process.env.STORAGE_CONNECTION
        );
        
        const queueClient = queueServiceClient.getQueueClient("escalations");
        
        const escalationMessage = {
            ticketId: ticketId,
            reason: reason,
            priority: priority,
            escalatedAt: new Date().toISOString(),
            escalatedBy: "support-assistant"
        };

        await queueClient.sendMessage(Buffer.from(JSON.stringify(escalationMessage)).toString('base64'));
        
        context.res = {
            status: 200,
            body: {
                ticketId: ticketId,
                status: "escalated",
                message: `Ticket ${ticketId} has been escalated successfully`
            }
        };
    } catch (error) {
        context.res = {
            status: 500,
            body: { error: "Failed to escalate ticket" }
        };
    }
};
EOF

    # Update function.json for escalation
    cat > escalation/function.json << 'EOF'
{
  "bindings": [
    {
      "authLevel": "function",
      "type": "httpTrigger",
      "direction": "in",
      "name": "req", 
      "methods": ["post"]
    },
    {
      "type": "http",
      "direction": "out",
      "name": "res"
    }
  ]
}
EOF

    # Install dependencies
    npm init -y
    npm install @azure/data-tables @azure/storage-blob @azure/storage-queue
    
    # Deploy functions to Azure
    log "Deploying functions to Azure..."
    func azure functionapp publish "$FUNCTION_APP" --javascript
    
    # Get function app details
    export FUNCTION_HOST=$(az functionapp show \
        --name "$FUNCTION_APP" \
        --resource-group "$RESOURCE_GROUP" \
        --query defaultHostName --output tsv)
    
    # Get function key for authentication
    export FUNCTION_KEY=$(az functionapp keys list \
        --name "$FUNCTION_APP" \
        --resource-group "$RESOURCE_GROUP" \
        --query functionKeys.default --output tsv)
    
    cd "$SCRIPT_DIR"
    rm -rf "$FUNCTIONS_DIR"
    
    success "Functions deployed to: https://$FUNCTION_HOST"
}

# Function to create OpenAI Assistant
create_assistant() {
    log "Creating OpenAI Assistant with function definitions..."
    
    # Create assistant configuration in temporary directory
    TEMP_DIR="$SCRIPT_DIR/temp-assistant"
    mkdir -p "$TEMP_DIR"
    cd "$TEMP_DIR"
    
    # Create package.json and install OpenAI SDK
    cat > package.json << 'EOF'
{
  "name": "support-assistant-creator",
  "version": "1.0.0",
  "description": "Creates OpenAI Assistant for customer support",
  "main": "create-assistant.js",
  "type": "module",
  "dependencies": {
    "openai": "^4.0.0"
  }
}
EOF

    npm install

    # Create assistant creation script
    cat > create-assistant.js << EOF
import { OpenAI } from 'openai';

const client = new OpenAI({
    apiKey: process.env.OPENAI_KEY,
    baseURL: \`\${process.env.OPENAI_ENDPOINT}/openai/deployments/gpt-4o\`,
    defaultQuery: { 'api-version': '2024-10-21' },
    defaultHeaders: {
        'api-key': process.env.OPENAI_KEY,
    },
});

async function createAssistant() {
    try {
        const assistant = await client.beta.assistants.create({
            name: "Customer Support Assistant",
            instructions: \`You are a helpful customer support assistant. You can help customers with:
            - Looking up existing support tickets
            - Finding answers in our FAQ database  
            - Creating new support tickets
            - Escalating urgent issues
            
            Always be polite, professional, and try to resolve issues efficiently. 
            Use the available functions when customers need specific actions performed.\`,
            model: "gpt-4o",
            tools: [
                {
                    type: "function",
                    function: {
                        name: "lookup_ticket",
                        description: "Look up information about an existing support ticket",
                        parameters: {
                            type: "object",
                            properties: {
                                ticketId: {
                                    type: "string",
                                    description: "The ticket ID to look up"
                                }
                            },
                            required: ["ticketId"]
                        }
                    }
                },
                {
                    type: "function", 
                    function: {
                        name: "search_faq",
                        description: "Search the FAQ database for answers to common questions",
                        parameters: {
                            type: "object",
                            properties: {
                                query: {
                                    type: "string",
                                    description: "Search query for FAQ lookup"
                                }
                            },
                            required: ["query"]
                        }
                    }
                },
                {
                    type: "function",
                    function: {
                        name: "create_ticket",
                        description: "Create a new support ticket",
                        parameters: {
                            type: "object",
                            properties: {
                                subject: {
                                    type: "string",
                                    description: "Subject line for the ticket"
                                },
                                description: {
                                    type: "string",
                                    description: "Detailed description of the issue"
                                },
                                priority: {
                                    type: "string",
                                    description: "Priority level (low, medium, high)",
                                    enum: ["low", "medium", "high"]
                                }
                            },
                            required: ["subject", "description"]
                        }
                    }
                },
                {
                    type: "function",
                    function: {
                        name: "escalate_ticket",
                        description: "Escalate a ticket to higher level support",
                        parameters: {
                            type: "object",
                            properties: {
                                ticketId: {
                                    type: "string",
                                    description: "The ticket ID to escalate"
                                },
                                reason: {
                                    type: "string",
                                    description: "Reason for escalation"
                                }
                            },
                            required: ["ticketId", "reason"]
                        }
                    }
                }
            ]
        });
        
        console.log('ASSISTANT_ID:' + assistant.id);
        return assistant.id;
    } catch (error) {
        console.error('Error creating assistant:', error);
        process.exit(1);
    }
}

createAssistant();
EOF

    # Set environment variables and create assistant
    export OPENAI_KEY="$OPENAI_KEY"
    export OPENAI_ENDPOINT="$OPENAI_ENDPOINT"
    
    ASSISTANT_OUTPUT=$(node create-assistant.js)
    export ASSISTANT_ID=$(echo "$ASSISTANT_OUTPUT" | grep "ASSISTANT_ID:" | cut -d':' -f2)
    
    # Clean up temporary directory
    cd "$SCRIPT_DIR"
    rm -rf "$TEMP_DIR"
    
    success "OpenAI Assistant created: $ASSISTANT_ID"
    
    # Update state file with assistant ID
    jq ".assistantId = \"$ASSISTANT_ID\"" "$SCRIPT_DIR/deployment-state.json" > "$SCRIPT_DIR/deployment-state.tmp" && mv "$SCRIPT_DIR/deployment-state.tmp" "$SCRIPT_DIR/deployment-state.json"
}

# Function to run validation tests
run_validation() {
    log "Running deployment validation tests..."
    
    # Test Function App endpoints
    log "Testing Function App endpoints..."
    
    # Test FAQ retrieval function
    FAQ_RESPONSE=$(curl -s -X POST "https://$FUNCTION_HOST/api/faqRetrieval?code=$FUNCTION_KEY" \
        -H "Content-Type: application/json" \
        -d '{"query": "password"}' || echo "ERROR")
    
    if echo "$FAQ_RESPONSE" | jq -e '.results' > /dev/null 2>&1; then
        success "FAQ retrieval function is working correctly"
    else
        error "FAQ retrieval function test failed"
        echo "Response: $FAQ_RESPONSE"
    fi
    
    # Test ticket lookup function (expect 404 for non-existent ticket)
    TICKET_RESPONSE=$(curl -s -X POST "https://$FUNCTION_HOST/api/ticketLookup?code=$FUNCTION_KEY" \
        -H "Content-Type: application/json" \
        -d '{"ticketId": "test-123"}' || echo "ERROR")
        
    if echo "$TICKET_RESPONSE" | jq -e '.error' > /dev/null 2>&1; then
        success "Ticket lookup function is working correctly (404 expected for non-existent ticket)"
    else
        warning "Ticket lookup function may have issues"
        echo "Response: $TICKET_RESPONSE"
    fi
    
    # Verify OpenAI Assistant
    if [ -n "$ASSISTANT_ID" ]; then
        success "OpenAI Assistant created successfully: $ASSISTANT_ID"
    else
        error "OpenAI Assistant creation may have failed"
    fi
    
    success "Validation tests completed"
}

# Function to display deployment summary
display_summary() {
    log "Deployment Summary"
    echo "==================="
    echo ""
    echo "Resources Created:"
    echo "  Resource Group: $RESOURCE_GROUP"
    echo "  Storage Account: $STORAGE_ACCOUNT"
    echo "  Function App: $FUNCTION_APP"
    echo "  OpenAI Account: $OPENAI_ACCOUNT"
    echo "  Assistant ID: $ASSISTANT_ID"
    echo ""
    echo "Endpoints:"
    echo "  Function App: https://$FUNCTION_HOST"
    echo "  OpenAI Endpoint: $OPENAI_ENDPOINT"
    echo ""
    echo "Next Steps:"
    echo "  1. Access your Function App at: https://portal.azure.com/#resource/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Web/sites/$FUNCTION_APP"
    echo "  2. Access your OpenAI Service at: https://portal.azure.com/#resource/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.CognitiveServices/accounts/$OPENAI_ACCOUNT"
    echo "  3. Test the assistant using the OpenAI Studio or API calls"
    echo ""
    echo "Deployment state saved to: $SCRIPT_DIR/deployment-state.json"
    echo "Logs saved to: $DEPLOYMENT_LOG"
}

# Main deployment function
main() {
    log "Customer Support Assistant Deployment Started"
    
    # Run all deployment steps
    check_prerequisites
    setup_environment
    create_resource_group
    create_storage_account
    initialize_storage
    create_openai_service
    deploy_gpt4o_model
    create_function_app
    deploy_support_functions
    create_assistant
    run_validation
    display_summary
    
    success "Customer Support Assistant deployment completed successfully!"
    log "Total deployment time: $SECONDS seconds"
}

# Error handling
trap 'error "Deployment failed at line $LINENO. Check the logs for details: $DEPLOYMENT_LOG"' ERR

# Run main function
main "$@"