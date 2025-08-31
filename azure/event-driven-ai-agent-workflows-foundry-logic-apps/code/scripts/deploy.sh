#!/bin/bash

# Event-Driven AI Agent Workflows with AI Foundry and Logic Apps - Deployment Script
# Recipe: azure/event-driven-ai-agent-workflows-foundry-logic-apps
# Version: 1.1
# 
# This script deploys the complete infrastructure for event-driven AI agent workflows
# using Azure AI Foundry Agent Service, Logic Apps, and Service Bus

set -euo pipefail

# Color codes for output formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO:${NC} $1"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARN:${NC} $1"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1"
}

success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] SUCCESS:${NC} $1"
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        error "Azure CLI is not installed. Please install it from https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
        exit 1
    fi
    
    # Check if user is logged in to Azure
    if ! az account show &> /dev/null; then
        error "You are not logged in to Azure. Please run 'az login' first."
        exit 1
    fi
    
    # Check if required Azure CLI extensions are available
    log "Checking Azure CLI extensions..."
    
    # Install Logic Apps extension if not present
    if ! az extension list --query "[?name=='logic']" | grep -q logic; then
        log "Installing Azure CLI Logic Apps extension..."
        az extension add --name logic --only-show-errors
    fi
    
    # Check if openssl is available for random generation
    if ! command -v openssl &> /dev/null; then
        error "openssl is required for generating random suffixes. Please install it."
        exit 1
    fi
    
    success "All prerequisites check passed"
}

# Function to set environment variables
set_environment_variables() {
    log "Setting environment variables..."
    
    # Generate unique suffix for resource names
    export RANDOM_SUFFIX=$(openssl rand -hex 3)
    log "Generated random suffix: ${RANDOM_SUFFIX}"
    
    # Set Azure resource configuration
    export RESOURCE_GROUP="rg-ai-workflows-${RANDOM_SUFFIX}"
    export LOCATION="${AZURE_LOCATION:-eastus}"
    export SUBSCRIPTION_ID=$(az account show --query id --output tsv)
    
    # Set resource names with unique suffix
    export AI_FOUNDRY_HUB="aihub-workflows-${RANDOM_SUFFIX}"
    export AI_FOUNDRY_PROJECT="aiproject-workflows-${RANDOM_SUFFIX}"
    export SERVICE_BUS_NAMESPACE="sb-workflows-${RANDOM_SUFFIX}"
    export LOGIC_APP_NAME="la-ai-workflows-${RANDOM_SUFFIX}"
    
    log "Environment variables configured:"
    log "  Resource Group: ${RESOURCE_GROUP}"
    log "  Location: ${LOCATION}"
    log "  AI Foundry Hub: ${AI_FOUNDRY_HUB}"
    log "  AI Foundry Project: ${AI_FOUNDRY_PROJECT}"
    log "  Service Bus Namespace: ${SERVICE_BUS_NAMESPACE}"
    log "  Logic App Name: ${LOGIC_APP_NAME}"
}

# Function to create resource group
create_resource_group() {
    log "Creating resource group: ${RESOURCE_GROUP}"
    
    az group create \
        --name "${RESOURCE_GROUP}" \
        --location "${LOCATION}" \
        --tags purpose=recipe environment=demo \
        --output none
    
    success "Resource group created: ${RESOURCE_GROUP}"
}

# Function to create Service Bus namespace
create_service_bus() {
    log "Creating Service Bus namespace: ${SERVICE_BUS_NAMESPACE}"
    
    az servicebus namespace create \
        --name "${SERVICE_BUS_NAMESPACE}" \
        --resource-group "${RESOURCE_GROUP}" \
        --location "${LOCATION}" \
        --sku Standard \
        --tags purpose=recipe environment=demo \
        --output none
    
    success "Service Bus namespace created: ${SERVICE_BUS_NAMESPACE}"
    
    # Wait for namespace to be fully provisioned
    log "Waiting for Service Bus namespace to be ready..."
    az servicebus namespace wait \
        --name "${SERVICE_BUS_NAMESPACE}" \
        --resource-group "${RESOURCE_GROUP}" \
        --created \
        --timeout 300
    
    success "Service Bus namespace is ready"
}

# Function to create AI Foundry resources
create_ai_foundry() {
    log "Creating AI Foundry Hub: ${AI_FOUNDRY_HUB}"
    
    az ml workspace create \
        --name "${AI_FOUNDRY_HUB}" \
        --resource-group "${RESOURCE_GROUP}" \
        --location "${LOCATION}" \
        --kind Hub \
        --tags purpose=recipe environment=demo \
        --output none
    
    success "AI Foundry Hub created: ${AI_FOUNDRY_HUB}"
    
    # Wait for hub to be ready before creating project
    log "Waiting for AI Foundry Hub to be ready..."
    sleep 30
    
    log "Creating AI Foundry Project: ${AI_FOUNDRY_PROJECT}"
    
    az ml workspace create \
        --name "${AI_FOUNDRY_PROJECT}" \
        --resource-group "${RESOURCE_GROUP}" \
        --location "${LOCATION}" \
        --kind Project \
        --hub-id "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.MachineLearningServices/workspaces/${AI_FOUNDRY_HUB}" \
        --tags purpose=recipe environment=demo \
        --output none
    
    success "AI Foundry Project created: ${AI_FOUNDRY_PROJECT}"
}

# Function to configure Service Bus messaging
configure_service_bus_messaging() {
    log "Configuring Service Bus queues and topics..."
    
    # Create queue for direct event processing
    az servicebus queue create \
        --name "event-processing-queue" \
        --namespace-name "${SERVICE_BUS_NAMESPACE}" \
        --resource-group "${RESOURCE_GROUP}" \
        --max-size 1024 \
        --default-message-time-to-live "P14D" \
        --output none
    
    log "Created event processing queue"
    
    # Create topic for event distribution
    az servicebus topic create \
        --name "business-events-topic" \
        --namespace-name "${SERVICE_BUS_NAMESPACE}" \
        --resource-group "${RESOURCE_GROUP}" \
        --max-size 1024 \
        --default-message-time-to-live "P14D" \
        --output none
    
    log "Created business events topic"
    
    # Create subscription for AI agent processing
    az servicebus topic subscription create \
        --name "ai-agent-subscription" \
        --topic-name "business-events-topic" \
        --namespace-name "${SERVICE_BUS_NAMESPACE}" \
        --resource-group "${RESOURCE_GROUP}" \
        --max-delivery-count 10 \
        --output none
    
    log "Created AI agent subscription"
    
    # Get Service Bus connection string
    SERVICE_BUS_CONNECTION=$(az servicebus namespace \
        authorization-rule keys list \
        --name RootManageSharedAccessKey \
        --namespace-name "${SERVICE_BUS_NAMESPACE}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query primaryConnectionString --output tsv)
    
    success "Service Bus messaging infrastructure configured"
    log "Service Bus connection string obtained (stored in variable)"
}

# Function to create Logic App workflow
create_logic_app() {
    log "Creating Logic App workflow definition..."
    
    # Create workflow definition file
    cat > /tmp/logic-app-definition.json << 'EOF'
{
    "$schema": "https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#",
    "contentVersion": "1.0.0.0",
    "parameters": {},
    "triggers": {
        "When_a_message_is_received_in_a_queue": {
            "type": "ServiceBus",
            "inputs": {
                "host": {
                    "connection": {
                        "name": "@parameters('$connections')['servicebus']['connectionId']"
                    }
                },
                "method": "get",
                "path": "//@{encodeURIComponent(encodeURIComponent('event-processing-queue'))}/messages/head",
                "queries": {
                    "queueType": "Main"
                }
            },
            "recurrence": {
                "frequency": "Minute",
                "interval": 1
            }
        }
    },
    "actions": {
        "Parse_Event_Content": {
            "type": "ParseJson",
            "inputs": {
                "content": "@base64ToString(triggerBody()?['ContentData'])",
                "schema": {
                    "type": "object",
                    "properties": {
                        "eventType": {"type": "string"},
                        "content": {"type": "string"},
                        "metadata": {"type": "object"}
                    }
                }
            }
        },
        "HTTP_Call_to_AI_Agent": {
            "type": "Http",
            "inputs": {
                "method": "POST",
                "uri": "https://api.example.com/process-event",
                "headers": {
                    "Content-Type": "application/json"
                },
                "body": {
                    "eventData": "@body('Parse_Event_Content')",
                    "timestamp": "@utcNow()"
                }
            },
            "runAfter": {
                "Parse_Event_Content": ["Succeeded"]
            }
        }
    },
    "outputs": {}
}
EOF
    
    log "Creating Logic App workflow: ${LOGIC_APP_NAME}"
    
    az logic workflow create \
        --resource-group "${RESOURCE_GROUP}" \
        --location "${LOCATION}" \
        --name "${LOGIC_APP_NAME}" \
        --definition /tmp/logic-app-definition.json \
        --tags purpose=recipe environment=demo \
        --output none
    
    # Clean up temporary file
    rm -f /tmp/logic-app-definition.json
    
    success "Logic App workflow created: ${LOGIC_APP_NAME}"
}

# Function to display next steps
display_next_steps() {
    success "Infrastructure deployment completed successfully!"
    
    echo ""
    echo "=================================================="
    echo "          NEXT STEPS FOR CONFIGURATION"
    echo "=================================================="
    echo ""
    
    # Get AI project endpoint
    AI_PROJECT_ENDPOINT=$(az ml workspace show \
        --name "${AI_FOUNDRY_PROJECT}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query discovery_url --output tsv 2>/dev/null || echo "Not available")
    
    echo "📋 Manual Configuration Required:"
    echo ""
    echo "1. Configure AI Agent in Azure AI Foundry:"
    echo "   - Navigate to: https://ai.azure.com"
    echo "   - Select project: ${AI_FOUNDRY_PROJECT}"
    echo "   - Create agent: BusinessEventProcessor"
    echo "   - Model: GPT-4o (or latest available)"
    echo "   - Tools: Enable Grounding with Bing Search, Azure Logic Apps"
    echo ""
    echo "2. Test the event processing pipeline:"
    echo "   - Send test messages to the Service Bus queue"
    echo "   - Monitor Logic App execution in Azure portal"
    echo "   - Verify AI agent processing in AI Foundry"
    echo ""
    echo "3. Resource Information:"
    echo "   - Resource Group: ${RESOURCE_GROUP}"
    echo "   - Service Bus Namespace: ${SERVICE_BUS_NAMESPACE}"
    echo "   - Logic App: ${LOGIC_APP_NAME}"
    echo "   - AI Foundry Hub: ${AI_FOUNDRY_HUB}"
    echo "   - AI Foundry Project: ${AI_FOUNDRY_PROJECT}"
    echo ""
    echo "4. AI Project Endpoint: ${AI_PROJECT_ENDPOINT}"
    echo ""
    echo "=================================================="
}

# Function to send test messages
send_test_messages() {
    if [[ "${SEND_TEST_MESSAGES:-false}" == "true" ]]; then
        log "Sending test messages to Service Bus queue..."
        
        # Send test message for support request
        az servicebus message send \
            --namespace-name "${SERVICE_BUS_NAMESPACE}" \
            --queue-name "event-processing-queue" \
            --body '{
                "eventType": "support-request",
                "content": "Customer reporting login issues with urgent priority",
                "metadata": {
                    "customerId": "CUST-12345",
                    "timestamp": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'",
                    "priority": "high"
                }
            }' \
            --output none
        
        # Send test message for document upload
        az servicebus message send \
            --namespace-name "${SERVICE_BUS_NAMESPACE}" \
            --queue-name "event-processing-queue" \
            --body '{
                "eventType": "document-upload",
                "content": "New contract document uploaded requiring review and approval",
                "metadata": {
                    "documentId": "DOC-67890",
                    "uploadedBy": "user@company.com",
                    "timestamp": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'",
                    "category": "legal"
                }
            }' \
            --output none
        
        success "Test messages sent to Service Bus queue"
    fi
}

# Function to handle script interruption
cleanup_on_error() {
    error "Deployment interrupted. Cleaning up temporary files..."
    rm -f /tmp/logic-app-definition.json
    exit 1
}

# Function to validate deployment
validate_deployment() {
    log "Validating deployment..."
    
    # Check resource group exists
    if ! az group show --name "${RESOURCE_GROUP}" --output none 2>/dev/null; then
        error "Resource group ${RESOURCE_GROUP} not found"
        return 1
    fi
    
    # Check Service Bus namespace exists
    if ! az servicebus namespace show --name "${SERVICE_BUS_NAMESPACE}" --resource-group "${RESOURCE_GROUP}" --output none 2>/dev/null; then
        error "Service Bus namespace ${SERVICE_BUS_NAMESPACE} not found"
        return 1
    fi
    
    # Check AI Foundry resources exist
    if ! az ml workspace show --name "${AI_FOUNDRY_HUB}" --resource-group "${RESOURCE_GROUP}" --output none 2>/dev/null; then
        error "AI Foundry Hub ${AI_FOUNDRY_HUB} not found"
        return 1
    fi
    
    if ! az ml workspace show --name "${AI_FOUNDRY_PROJECT}" --resource-group "${RESOURCE_GROUP}" --output none 2>/dev/null; then
        error "AI Foundry Project ${AI_FOUNDRY_PROJECT} not found"
        return 1
    fi
    
    # Check Logic App exists
    if ! az logic workflow show --name "${LOGIC_APP_NAME}" --resource-group "${RESOURCE_GROUP}" --output none 2>/dev/null; then
        error "Logic App ${LOGIC_APP_NAME} not found"
        return 1
    fi
    
    success "Deployment validation passed"
    return 0
}

# Main execution function
main() {
    log "Starting deployment of Event-Driven AI Agent Workflows"
    log "Recipe: azure/event-driven-ai-agent-workflows-foundry-logic-apps"
    
    # Set up error handling
    trap cleanup_on_error INT TERM
    
    # Execute deployment steps
    check_prerequisites
    set_environment_variables
    create_resource_group
    create_service_bus
    create_ai_foundry
    configure_service_bus_messaging
    create_logic_app
    send_test_messages
    
    # Validate deployment
    if validate_deployment; then
        display_next_steps
        success "Deployment completed successfully!"
        
        # Export variables for later use
        echo ""
        log "Environment variables saved to deployment.env:"
        cat > deployment.env << EOF
export RESOURCE_GROUP="${RESOURCE_GROUP}"
export LOCATION="${LOCATION}"
export SUBSCRIPTION_ID="${SUBSCRIPTION_ID}"
export RANDOM_SUFFIX="${RANDOM_SUFFIX}"
export AI_FOUNDRY_HUB="${AI_FOUNDRY_HUB}"
export AI_FOUNDRY_PROJECT="${AI_FOUNDRY_PROJECT}"
export SERVICE_BUS_NAMESPACE="${SERVICE_BUS_NAMESPACE}"
export LOGIC_APP_NAME="${LOGIC_APP_NAME}"
EOF
        
        log "To load these variables in future sessions, run: source deployment.env"
        
    else
        error "Deployment validation failed"
        exit 1
    fi
}

# Script usage information
usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -l, --location LOCATION    Azure region for deployment (default: eastus)"
    echo "  -t, --test                 Send test messages after deployment"
    echo "  -h, --help                 Show this help message"
    echo ""
    echo "Environment Variables:"
    echo "  AZURE_LOCATION            Azure region (overrides --location)"
    echo "  SEND_TEST_MESSAGES        Send test messages (true/false)"
    echo ""
    echo "Examples:"
    echo "  $0                         Deploy with default settings"
    echo "  $0 --location westus2      Deploy to West US 2 region"
    echo "  $0 --test                  Deploy and send test messages"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -l|--location)
            export AZURE_LOCATION="$2"
            shift 2
            ;;
        -t|--test)
            export SEND_TEST_MESSAGES="true"
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            error "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# Execute main function
main "$@"