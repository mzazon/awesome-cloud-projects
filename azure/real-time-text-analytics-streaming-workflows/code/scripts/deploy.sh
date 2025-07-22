#!/bin/bash

# Azure Multi-Modal Content Processing Workflow - Deployment Script
# This script deploys the complete infrastructure for orchestrating multi-modal content processing
# workflows with Azure Cognitive Services Text Analytics and Azure Event Hub

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
}

warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1${NC}"
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        error "Azure CLI is not installed. Please install Azure CLI first."
        exit 1
    fi
    
    # Check Azure CLI version
    local az_version=$(az version --query '"azure-cli"' -o tsv)
    log "Azure CLI version: $az_version"
    
    # Check if user is logged in
    if ! az account show &> /dev/null; then
        error "You are not logged in to Azure. Please run 'az login' first."
        exit 1
    fi
    
    # Check if Python 3 is available (needed for test scripts)
    if ! command -v python3 &> /dev/null; then
        warning "Python 3 is not available. Testing functionality will be limited."
    fi
    
    # Check if required Azure providers are registered
    log "Checking Azure provider registrations..."
    local providers=("Microsoft.CognitiveServices" "Microsoft.EventHub" "Microsoft.Logic" "Microsoft.Storage" "Microsoft.Web")
    
    for provider in "${providers[@]}"; do
        local status=$(az provider show --namespace "$provider" --query "registrationState" -o tsv 2>/dev/null || echo "NotRegistered")
        if [ "$status" != "Registered" ]; then
            warning "Provider $provider is not registered. Registering now..."
            az provider register --namespace "$provider"
        fi
    done
    
    log "Prerequisites check completed"
}

# Function to set default values and validate inputs
set_defaults() {
    log "Setting default values..."
    
    # Set default values
    export RESOURCE_GROUP="${RESOURCE_GROUP:-rg-content-processing-demo}"
    export LOCATION="${LOCATION:-eastus}"
    export SUBSCRIPTION_ID="${SUBSCRIPTION_ID:-$(az account show --query id --output tsv)}"
    
    # Generate unique suffix for globally unique resource names
    if [ -z "${RANDOM_SUFFIX:-}" ]; then
        export RANDOM_SUFFIX=$(openssl rand -hex 3 2>/dev/null || echo $(date +%s | tail -c 6))
    fi
    
    export STORAGE_ACCOUNT="${STORAGE_ACCOUNT:-stcontentproc${RANDOM_SUFFIX}}"
    export EVENT_HUB_NAMESPACE="${EVENT_HUB_NAMESPACE:-eh-content-proc-${RANDOM_SUFFIX}}"
    export COGNITIVE_SERVICE="${COGNITIVE_SERVICE:-cs-text-analytics-${RANDOM_SUFFIX}}"
    export LOGIC_APP="${LOGIC_APP:-la-content-workflow-${RANDOM_SUFFIX}}"
    
    # Validate required variables
    if [ -z "$SUBSCRIPTION_ID" ]; then
        error "Unable to determine subscription ID"
        exit 1
    fi
    
    info "Configuration:"
    info "  Resource Group: $RESOURCE_GROUP"
    info "  Location: $LOCATION"
    info "  Subscription ID: $SUBSCRIPTION_ID"
    info "  Random Suffix: $RANDOM_SUFFIX"
    info "  Storage Account: $STORAGE_ACCOUNT"
    info "  Event Hub Namespace: $EVENT_HUB_NAMESPACE"
    info "  Cognitive Service: $COGNITIVE_SERVICE"
    info "  Logic App: $LOGIC_APP"
}

# Function to create resource group
create_resource_group() {
    log "Creating resource group..."
    
    # Check if resource group already exists
    if az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        warning "Resource group $RESOURCE_GROUP already exists. Skipping creation."
        return 0
    fi
    
    az group create \
        --name "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --tags purpose=content-processing environment=demo created-by=deploy-script
    
    if [ $? -eq 0 ]; then
        log "Resource group $RESOURCE_GROUP created successfully"
    else
        error "Failed to create resource group $RESOURCE_GROUP"
        exit 1
    fi
}

# Function to create Cognitive Services Language resource
create_cognitive_services() {
    log "Creating Cognitive Services Language resource..."
    
    # Check if resource already exists
    if az cognitiveservices account show --name "$COGNITIVE_SERVICE" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        warning "Cognitive Service $COGNITIVE_SERVICE already exists. Skipping creation."
    else
        az cognitiveservices account create \
            --name "$COGNITIVE_SERVICE" \
            --resource-group "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --kind TextAnalytics \
            --sku S \
            --custom-domain "$COGNITIVE_SERVICE" \
            --yes
        
        if [ $? -eq 0 ]; then
            log "Cognitive Services resource $COGNITIVE_SERVICE created successfully"
        else
            error "Failed to create Cognitive Services resource"
            exit 1
        fi
    fi
    
    # Wait for resource to be ready
    log "Waiting for Cognitive Services resource to be ready..."
    local max_attempts=30
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        local status=$(az cognitiveservices account show --name "$COGNITIVE_SERVICE" --resource-group "$RESOURCE_GROUP" --query "properties.provisioningState" -o tsv 2>/dev/null)
        
        if [ "$status" = "Succeeded" ]; then
            log "Cognitive Services resource is ready"
            break
        elif [ "$status" = "Failed" ]; then
            error "Cognitive Services resource provisioning failed"
            exit 1
        fi
        
        info "Attempt $attempt/$max_attempts: Cognitive Services status is $status. Waiting..."
        sleep 10
        ((attempt++))
    done
    
    if [ $attempt -gt $max_attempts ]; then
        error "Timeout waiting for Cognitive Services resource to be ready"
        exit 1
    fi
    
    # Get API key and endpoint
    export COGNITIVE_KEY=$(az cognitiveservices account keys list \
        --name "$COGNITIVE_SERVICE" \
        --resource-group "$RESOURCE_GROUP" \
        --query key1 --output tsv)
    
    export COGNITIVE_ENDPOINT=$(az cognitiveservices account show \
        --name "$COGNITIVE_SERVICE" \
        --resource-group "$RESOURCE_GROUP" \
        --query properties.endpoint --output tsv)
    
    log "Cognitive Services endpoint: $COGNITIVE_ENDPOINT"
}

# Function to create Event Hubs namespace and hub
create_event_hubs() {
    log "Creating Event Hubs namespace and hub..."
    
    # Check if namespace already exists
    if az eventhubs namespace show --name "$EVENT_HUB_NAMESPACE" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        warning "Event Hub namespace $EVENT_HUB_NAMESPACE already exists. Skipping creation."
    else
        az eventhubs namespace create \
            --name "$EVENT_HUB_NAMESPACE" \
            --resource-group "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --sku Standard \
            --enable-auto-inflate true \
            --maximum-throughput-units 10
        
        if [ $? -eq 0 ]; then
            log "Event Hub namespace $EVENT_HUB_NAMESPACE created successfully"
        else
            error "Failed to create Event Hub namespace"
            exit 1
        fi
    fi
    
    # Create Event Hub
    if az eventhubs eventhub show --name content-stream --namespace-name "$EVENT_HUB_NAMESPACE" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        warning "Event Hub content-stream already exists. Skipping creation."
    else
        az eventhubs eventhub create \
            --name content-stream \
            --namespace-name "$EVENT_HUB_NAMESPACE" \
            --resource-group "$RESOURCE_GROUP" \
            --partition-count 4 \
            --message-retention 7
        
        if [ $? -eq 0 ]; then
            log "Event Hub content-stream created successfully"
        else
            error "Failed to create Event Hub"
            exit 1
        fi
    fi
    
    # Create authorization rule for sending events
    if az eventhubs eventhub authorization-rule show --name SendPolicy --eventhub-name content-stream --namespace-name "$EVENT_HUB_NAMESPACE" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        warning "Event Hub authorization rule SendPolicy already exists. Skipping creation."
    else
        az eventhubs eventhub authorization-rule create \
            --name SendPolicy \
            --eventhub-name content-stream \
            --namespace-name "$EVENT_HUB_NAMESPACE" \
            --resource-group "$RESOURCE_GROUP" \
            --rights Send
        
        if [ $? -eq 0 ]; then
            log "Event Hub authorization rule created successfully"
        else
            error "Failed to create Event Hub authorization rule"
            exit 1
        fi
    fi
    
    # Get connection string
    export EVENT_HUB_CONNECTION=$(az eventhubs eventhub authorization-rule keys list \
        --name SendPolicy \
        --eventhub-name content-stream \
        --namespace-name "$EVENT_HUB_NAMESPACE" \
        --resource-group "$RESOURCE_GROUP" \
        --query primaryConnectionString --output tsv)
    
    log "Event Hub configured with 4 partitions for parallel processing"
}

# Function to create storage account
create_storage_account() {
    log "Creating storage account..."
    
    # Check if storage account already exists
    if az storage account show --name "$STORAGE_ACCOUNT" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        warning "Storage account $STORAGE_ACCOUNT already exists. Skipping creation."
    else
        az storage account create \
            --name "$STORAGE_ACCOUNT" \
            --resource-group "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --sku Standard_LRS \
            --kind StorageV2 \
            --access-tier Hot
        
        if [ $? -eq 0 ]; then
            log "Storage account $STORAGE_ACCOUNT created successfully"
        else
            error "Failed to create storage account"
            exit 1
        fi
    fi
    
    # Get storage connection string
    export STORAGE_CONNECTION=$(az storage account show-connection-string \
        --name "$STORAGE_ACCOUNT" \
        --resource-group "$RESOURCE_GROUP" \
        --query connectionString --output tsv)
    
    # Create containers for different data types
    local containers=("processed-insights" "raw-content" "sentiment-archives")
    
    for container in "${containers[@]}"; do
        if az storage container show --name "$container" --connection-string "$STORAGE_CONNECTION" &> /dev/null; then
            warning "Storage container $container already exists. Skipping creation."
        else
            az storage container create \
                --name "$container" \
                --connection-string "$STORAGE_CONNECTION"
            
            if [ $? -eq 0 ]; then
                log "Storage container $container created successfully"
            else
                error "Failed to create storage container $container"
                exit 1
            fi
        fi
    done
    
    log "Storage containers created for organized data management"
}

# Function to create API connections
create_api_connections() {
    log "Creating API connections for Logic Apps..."
    
    # Create Event Hub API connection
    if az resource show --resource-group "$RESOURCE_GROUP" --resource-type Microsoft.Web/connections --name eventhub-connection &> /dev/null; then
        warning "Event Hub connection already exists. Skipping creation."
    else
        az resource create \
            --resource-group "$RESOURCE_GROUP" \
            --resource-type Microsoft.Web/connections \
            --name eventhub-connection \
            --properties "{
                \"displayName\": \"Event Hub Connection\",
                \"api\": {
                    \"id\": \"/subscriptions/$SUBSCRIPTION_ID/providers/Microsoft.Web/locations/$LOCATION/managedApis/eventhubs\"
                },
                \"parameterValues\": {
                    \"connectionString\": \"$EVENT_HUB_CONNECTION\"
                }
            }"
        
        if [ $? -eq 0 ]; then
            log "Event Hub connection created successfully"
        else
            error "Failed to create Event Hub connection"
            exit 1
        fi
    fi
    
    # Create Cognitive Services API connection
    if az resource show --resource-group "$RESOURCE_GROUP" --resource-type Microsoft.Web/connections --name cognitiveservices-connection &> /dev/null; then
        warning "Cognitive Services connection already exists. Skipping creation."
    else
        az resource create \
            --resource-group "$RESOURCE_GROUP" \
            --resource-type Microsoft.Web/connections \
            --name cognitiveservices-connection \
            --properties "{
                \"displayName\": \"Text Analytics Connection\",
                \"api\": {
                    \"id\": \"/subscriptions/$SUBSCRIPTION_ID/providers/Microsoft.Web/locations/$LOCATION/managedApis/cognitiveservicestextanalytics\"
                },
                \"parameterValues\": {
                    \"apiKey\": \"$COGNITIVE_KEY\",
                    \"siteUrl\": \"$COGNITIVE_ENDPOINT\"
                }
            }"
        
        if [ $? -eq 0 ]; then
            log "Cognitive Services connection created successfully"
        else
            error "Failed to create Cognitive Services connection"
            exit 1
        fi
    fi
    
    # Create Azure Blob Storage connection
    if az resource show --resource-group "$RESOURCE_GROUP" --resource-type Microsoft.Web/connections --name azureblob-connection &> /dev/null; then
        warning "Azure Blob Storage connection already exists. Skipping creation."
    else
        az resource create \
            --resource-group "$RESOURCE_GROUP" \
            --resource-type Microsoft.Web/connections \
            --name azureblob-connection \
            --properties "{
                \"displayName\": \"Azure Blob Storage Connection\",
                \"api\": {
                    \"id\": \"/subscriptions/$SUBSCRIPTION_ID/providers/Microsoft.Web/locations/$LOCATION/managedApis/azureblob\"
                },
                \"parameterValues\": {
                    \"connectionString\": \"$STORAGE_CONNECTION\"
                }
            }"
        
        if [ $? -eq 0 ]; then
            log "Azure Blob Storage connection created successfully"
        else
            error "Failed to create Azure Blob Storage connection"
            exit 1
        fi
    fi
    
    # Get connection resource IDs
    export EVENTHUB_CONNECTION_ID=$(az resource show \
        --resource-group "$RESOURCE_GROUP" \
        --resource-type Microsoft.Web/connections \
        --name eventhub-connection \
        --query id --output tsv)
    
    export COGNITIVE_CONNECTION_ID=$(az resource show \
        --resource-group "$RESOURCE_GROUP" \
        --resource-type Microsoft.Web/connections \
        --name cognitiveservices-connection \
        --query id --output tsv)
    
    export STORAGE_CONNECTION_ID=$(az resource show \
        --resource-group "$RESOURCE_GROUP" \
        --resource-type Microsoft.Web/connections \
        --name azureblob-connection \
        --query id --output tsv)
    
    log "All API connections created successfully"
}

# Function to create Logic App workflow
create_logic_app() {
    log "Creating Logic App workflow..."
    
    # Create workflow definition file
    cat > /tmp/workflow-definition.json << 'EOF'
{
  "$schema": "https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {
    "$connections": {
      "defaultValue": {},
      "type": "Object"
    }
  },
  "triggers": {
    "When_events_are_available_in_Event_Hub": {
      "type": "ApiConnection",
      "inputs": {
        "host": {
          "connection": {
            "name": "@parameters('$connections')['eventhubs']['connectionId']"
          }
        },
        "method": "get",
        "path": "/messages/head",
        "queries": {
          "eventHubName": "content-stream"
        }
      },
      "recurrence": {
        "frequency": "Second",
        "interval": 30
      }
    }
  },
  "actions": {
    "Parse_Event_Content": {
      "type": "ParseJson",
      "inputs": {
        "content": "@triggerBody()",
        "schema": {
          "type": "object",
          "properties": {
            "content": {"type": "string"},
            "source": {"type": "string"},
            "timestamp": {"type": "string"}
          }
        }
      }
    },
    "Detect_Language": {
      "type": "ApiConnection",
      "inputs": {
        "host": {
          "connection": {
            "name": "@parameters('$connections')['cognitiveservicestextanalytics']['connectionId']"
          }
        },
        "method": "post",
        "path": "/text/analytics/v3.0/languages",
        "body": {
          "documents": [{
            "id": "1",
            "text": "@body('Parse_Event_Content')?['content']"
          }]
        }
      },
      "runAfter": {
        "Parse_Event_Content": ["Succeeded"]
      }
    },
    "Analyze_Sentiment": {
      "type": "ApiConnection",
      "inputs": {
        "host": {
          "connection": {
            "name": "@parameters('$connections')['cognitiveservicestextanalytics']['connectionId']"
          }
        },
        "method": "post",
        "path": "/text/analytics/v3.0/sentiment",
        "body": {
          "documents": [{
            "id": "1",
            "text": "@body('Parse_Event_Content')?['content']",
            "language": "@first(body('Detect_Language')?['documents'])?['detectedLanguage']?['iso6391Name']"
          }]
        }
      },
      "runAfter": {
        "Detect_Language": ["Succeeded"]
      }
    },
    "Extract_Key_Phrases": {
      "type": "ApiConnection",
      "inputs": {
        "host": {
          "connection": {
            "name": "@parameters('$connections')['cognitiveservicestextanalytics']['connectionId']"
          }
        },
        "method": "post",
        "path": "/text/analytics/v3.0/keyPhrases",
        "body": {
          "documents": [{
            "id": "1",
            "text": "@body('Parse_Event_Content')?['content']",
            "language": "@first(body('Detect_Language')?['documents'])?['detectedLanguage']?['iso6391Name']"
          }]
        }
      },
      "runAfter": {
        "Detect_Language": ["Succeeded"]
      }
    },
    "Store_Analysis_Results": {
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
          "folderPath": "/processed-insights",
          "name": "analysis-@{utcNow('yyyyMMddHHmmss')}.json"
        },
        "body": {
          "timestamp": "@utcNow()",
          "source": "@body('Parse_Event_Content')?['source']",
          "language": "@first(body('Detect_Language')?['documents'])?['detectedLanguage']?['name']",
          "sentiment": "@first(body('Analyze_Sentiment')?['documents'])?['sentiment']",
          "confidence": "@first(body('Analyze_Sentiment')?['documents'])?['confidenceScores']",
          "keyPhrases": "@first(body('Extract_Key_Phrases')?['documents'])?['keyPhrases']",
          "originalContent": "@body('Parse_Event_Content')?['content']"
        }
      },
      "runAfter": {
        "Analyze_Sentiment": ["Succeeded"],
        "Extract_Key_Phrases": ["Succeeded"]
      }
    }
  }
}
EOF
    
    # Check if Logic App already exists
    if az logic workflow show --name "$LOGIC_APP" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        warning "Logic App $LOGIC_APP already exists. Updating workflow..."
        
        az logic workflow update \
            --name "$LOGIC_APP" \
            --resource-group "$RESOURCE_GROUP" \
            --definition @/tmp/workflow-definition.json
    else
        az logic workflow create \
            --name "$LOGIC_APP" \
            --resource-group "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --definition @/tmp/workflow-definition.json
    fi
    
    if [ $? -eq 0 ]; then
        log "Logic App workflow created/updated successfully"
    else
        error "Failed to create Logic App workflow"
        exit 1
    fi
    
    # Update Logic App connections
    az logic workflow update \
        --name "$LOGIC_APP" \
        --resource-group "$RESOURCE_GROUP" \
        --parameters "{
            \"\$connections\": {
                \"value\": {
                    \"eventhubs\": {
                        \"connectionId\": \"$EVENTHUB_CONNECTION_ID\",
                        \"connectionName\": \"eventhub-connection\",
                        \"id\": \"/subscriptions/$SUBSCRIPTION_ID/providers/Microsoft.Web/locations/$LOCATION/managedApis/eventhubs\"
                    },
                    \"cognitiveservicestextanalytics\": {
                        \"connectionId\": \"$COGNITIVE_CONNECTION_ID\",
                        \"connectionName\": \"cognitiveservices-connection\",
                        \"id\": \"/subscriptions/$SUBSCRIPTION_ID/providers/Microsoft.Web/locations/$LOCATION/managedApis/cognitiveservicestextanalytics\"
                    },
                    \"azureblob\": {
                        \"connectionId\": \"$STORAGE_CONNECTION_ID\",
                        \"connectionName\": \"azureblob-connection\",
                        \"id\": \"/subscriptions/$SUBSCRIPTION_ID/providers/Microsoft.Web/locations/$LOCATION/managedApis/azureblob\"
                    }
                }
            }
        }"
    
    if [ $? -eq 0 ]; then
        log "Logic App connections configured successfully"
    else
        error "Failed to configure Logic App connections"
        exit 1
    fi
    
    # Clean up temporary file
    rm -f /tmp/workflow-definition.json
}

# Function to create test script
create_test_script() {
    log "Creating test script for Event Hub..."
    
    cat > /tmp/test_content.py << 'EOF'
import json
import os
import sys

try:
    from azure.eventhub import EventHubProducerClient, EventData
except ImportError:
    print("azure-eventhub package not installed. Installing...")
    import subprocess
    subprocess.check_call([sys.executable, "-m", "pip", "install", "azure-eventhub"])
    from azure.eventhub import EventHubProducerClient, EventData

def send_test_messages():
    connection_str = os.environ.get('EVENT_HUB_CONNECTION')
    if not connection_str:
        print("ERROR: EVENT_HUB_CONNECTION environment variable not set")
        return False
    
    eventhub_name = "content-stream"
    
    try:
        producer = EventHubProducerClient.from_connection_string(
            conn_str=connection_str,
            eventhub_name=eventhub_name
        )
        
        test_messages = [
            {
                "content": "This product is absolutely fantastic! Excellent customer service.",
                "source": "product-review",
                "timestamp": "2025-07-12T10:00:00Z"
            },
            {
                "content": "Very disappointed with the service. Poor quality and late delivery.",
                "source": "customer-feedback",
                "timestamp": "2025-07-12T10:05:00Z"
            },
            {
                "content": "The new features are interesting but need more documentation.",
                "source": "user-forum",
                "timestamp": "2025-07-12T10:10:00Z"
            }
        ]
        
        with producer:
            for message in test_messages:
                event_data = EventData(json.dumps(message))
                producer.send_event(event_data)
                print(f"✅ Sent: {message['content'][:50]}...")
        
        print("✅ All test messages sent successfully")
        return True
        
    except Exception as e:
        print(f"❌ Error sending test messages: {e}")
        return False

if __name__ == "__main__":
    success = send_test_messages()
    sys.exit(0 if success else 1)
EOF
    
    log "Test script created at /tmp/test_content.py"
}

# Function to run deployment validation
run_validation() {
    log "Running deployment validation..."
    
    # Test Cognitive Services endpoint
    info "Testing Cognitive Services endpoint..."
    local test_result=$(curl -s -X POST "${COGNITIVE_ENDPOINT}/text/analytics/v3.1/sentiment" \
        -H "Ocp-Apim-Subscription-Key: ${COGNITIVE_KEY}" \
        -H "Content-Type: application/json" \
        -d '{
            "documents": [{
                "id": "1",
                "text": "I love Azure Cognitive Services! This is amazing technology."
            }]
        }' || echo "FAILED")
    
    if [[ "$test_result" == *"positive"* ]]; then
        log "✅ Cognitive Services endpoint is working correctly"
    else
        error "❌ Cognitive Services endpoint test failed"
        warning "Response: $test_result"
    fi
    
    # Test Event Hub status
    info "Verifying Event Hub status..."
    local eh_status=$(az eventhubs eventhub show \
        --name content-stream \
        --namespace-name "$EVENT_HUB_NAMESPACE" \
        --resource-group "$RESOURCE_GROUP" \
        --query status --output tsv)
    
    if [ "$eh_status" = "Active" ]; then
        log "✅ Event Hub is active and ready"
    else
        error "❌ Event Hub is not active. Status: $eh_status"
    fi
    
    # Test storage containers
    info "Verifying storage containers..."
    local containers=("processed-insights" "raw-content" "sentiment-archives")
    
    for container in "${containers[@]}"; do
        if az storage container show --name "$container" --connection-string "$STORAGE_CONNECTION" &> /dev/null; then
            log "✅ Storage container $container is available"
        else
            error "❌ Storage container $container is not available"
        fi
    done
    
    # Test Logic App status
    info "Verifying Logic App status..."
    local la_status=$(az logic workflow show \
        --name "$LOGIC_APP" \
        --resource-group "$RESOURCE_GROUP" \
        --query state --output tsv)
    
    if [ "$la_status" = "Enabled" ]; then
        log "✅ Logic App is enabled and ready"
    else
        error "❌ Logic App is not enabled. Status: $la_status"
    fi
    
    # Send test messages if Python is available
    if command -v python3 &> /dev/null; then
        info "Sending test messages to Event Hub..."
        if python3 /tmp/test_content.py; then
            log "✅ Test messages sent successfully"
        else
            warning "❌ Failed to send test messages"
        fi
    else
        warning "Python 3 not available. Skipping test message sending."
    fi
    
    log "Deployment validation completed"
}

# Function to save deployment information
save_deployment_info() {
    log "Saving deployment information..."
    
    local info_file="/tmp/deployment-info.json"
    
    cat > "$info_file" << EOF
{
    "deployment_timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
    "resource_group": "$RESOURCE_GROUP",
    "location": "$LOCATION",
    "subscription_id": "$SUBSCRIPTION_ID",
    "random_suffix": "$RANDOM_SUFFIX",
    "resources": {
        "storage_account": "$STORAGE_ACCOUNT",
        "event_hub_namespace": "$EVENT_HUB_NAMESPACE",
        "cognitive_service": "$COGNITIVE_SERVICE",
        "logic_app": "$LOGIC_APP"
    },
    "endpoints": {
        "cognitive_endpoint": "$COGNITIVE_ENDPOINT",
        "event_hub_connection": "***REDACTED***"
    },
    "storage_containers": [
        "processed-insights",
        "raw-content", 
        "sentiment-archives"
    ]
}
EOF
    
    log "Deployment information saved to $info_file"
    
    # Display summary
    echo ""
    echo "=== DEPLOYMENT SUMMARY ==="
    echo "Resource Group: $RESOURCE_GROUP"
    echo "Location: $LOCATION"
    echo "Random Suffix: $RANDOM_SUFFIX"
    echo ""
    echo "Created Resources:"
    echo "  - Storage Account: $STORAGE_ACCOUNT"
    echo "  - Event Hub Namespace: $EVENT_HUB_NAMESPACE"
    echo "  - Cognitive Service: $COGNITIVE_SERVICE"
    echo "  - Logic App: $LOGIC_APP"
    echo ""
    echo "Cognitive Services Endpoint: $COGNITIVE_ENDPOINT"
    echo ""
    echo "Next Steps:"
    echo "1. Test the deployment using the validation commands"
    echo "2. Monitor Logic App runs in the Azure portal"
    echo "3. Check processed results in the storage containers"
    echo "4. Use the destroy.sh script to clean up resources when done"
    echo ""
    echo "==========================="
}

# Main deployment function
main() {
    log "Starting Azure Multi-Modal Content Processing Workflow deployment..."
    
    # Check if dry run mode
    if [ "${DRY_RUN:-false}" = "true" ]; then
        log "DRY RUN MODE: No actual resources will be created"
        exit 0
    fi
    
    # Run all deployment steps
    check_prerequisites
    set_defaults
    create_resource_group
    create_cognitive_services
    create_event_hubs
    create_storage_account
    create_api_connections
    create_logic_app
    create_test_script
    run_validation
    save_deployment_info
    
    log "✅ Deployment completed successfully!"
    log "Resources are ready for multi-modal content processing"
    
    # Clean up temporary files
    rm -f /tmp/test_content.py
}

# Handle script interruption
trap 'error "Deployment interrupted"; exit 1' INT TERM

# Run main function
main "$@"