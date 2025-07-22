#!/bin/bash

#################################################################
# Azure Intelligent Video Content Moderation - Deployment Script
#################################################################
# This script deploys Azure AI Vision, Event Hubs, Stream Analytics,
# Logic Apps, and supporting services for video content moderation
#################################################################

set -e  # Exit on any error
set -o pipefail  # Exit on pipe failure

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

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to validate Azure CLI login
validate_azure_login() {
    log_info "Validating Azure CLI authentication..."
    if ! az account show >/dev/null 2>&1; then
        log_error "Azure CLI is not authenticated. Please run 'az login' first."
        exit 1
    fi
    
    local subscription=$(az account show --query name -o tsv)
    log_success "Authenticated to Azure subscription: $subscription"
}

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command_exists az; then
        log_error "Azure CLI is not installed. Please install it from https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
        exit 1
    fi
    
    # Check Azure CLI version
    local az_version=$(az version --query '"azure-cli"' -o tsv)
    log_info "Azure CLI version: $az_version"
    
    # Validate Azure authentication
    validate_azure_login
    
    # Check if jq is available for JSON parsing
    if ! command_exists jq; then
        log_warning "jq is not installed. Some output formatting may be limited."
    fi
    
    log_success "Prerequisites check completed"
}

# Function to set environment variables
set_environment_variables() {
    log_info "Setting up environment variables..."
    
    # Generate unique suffix for resource names
    RANDOM_SUFFIX=$(openssl rand -hex 3 2>/dev/null || echo $(date +%s | tail -c 6))
    
    # Core configuration
    export LOCATION=${AZURE_LOCATION:-"eastus"}
    export SUBSCRIPTION_ID=$(az account show --query id --output tsv)
    
    # Resource names with unique suffix
    export RESOURCE_GROUP="rg-video-moderation-${RANDOM_SUFFIX}"
    export EVENT_HUB_NAMESPACE="eh-videomod-${RANDOM_SUFFIX}"
    export EVENT_HUB_NAME="video-frames"
    export STORAGE_ACCOUNT="stvideomod${RANDOM_SUFFIX}"
    export AI_VISION_NAME="aivision-contentmod-${RANDOM_SUFFIX}"
    export STREAM_ANALYTICS_JOB="sa-videomod-${RANDOM_SUFFIX}"
    export LOGIC_APP_NAME="la-videomod-${RANDOM_SUFFIX}"
    
    # Validate location
    if ! az account list-locations --query "[?name=='$LOCATION']" -o tsv | grep -q "$LOCATION"; then
        log_error "Invalid Azure location: $LOCATION"
        log_info "Available locations can be listed with: az account list-locations -o table"
        exit 1
    fi
    
    log_success "Environment variables configured"
    log_info "Resource Group: $RESOURCE_GROUP"
    log_info "Location: $LOCATION"
    log_info "Unique Suffix: $RANDOM_SUFFIX"
}

# Function to create resource group
create_resource_group() {
    log_info "Creating resource group: $RESOURCE_GROUP"
    
    if az group show --name "$RESOURCE_GROUP" >/dev/null 2>&1; then
        log_warning "Resource group $RESOURCE_GROUP already exists"
    else
        az group create \
            --name "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --tags purpose=video-moderation environment=demo
        
        log_success "Resource group created: $RESOURCE_GROUP"
    fi
}

# Function to create storage account
create_storage_account() {
    log_info "Creating storage account: $STORAGE_ACCOUNT"
    
    if az storage account show --name "$STORAGE_ACCOUNT" --resource-group "$RESOURCE_GROUP" >/dev/null 2>&1; then
        log_warning "Storage account $STORAGE_ACCOUNT already exists"
    else
        az storage account create \
            --name "$STORAGE_ACCOUNT" \
            --resource-group "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --sku Standard_LRS \
            --kind StorageV2 \
            --tags purpose=video-moderation
        
        log_success "Storage account created: $STORAGE_ACCOUNT"
    fi
    
    # Create storage container for moderation results
    log_info "Creating storage container for moderation results..."
    local storage_key=$(az storage account keys list \
        --account-name "$STORAGE_ACCOUNT" \
        --resource-group "$RESOURCE_GROUP" \
        --query '[0].value' --output tsv)
    
    az storage container create \
        --name "moderation-results" \
        --account-name "$STORAGE_ACCOUNT" \
        --account-key "$storage_key" >/dev/null 2>&1 || log_warning "Container may already exist"
    
    log_success "Storage container configured"
}

# Function to create Azure AI Vision service
create_ai_vision_service() {
    log_info "Creating Azure AI Vision service: $AI_VISION_NAME"
    
    if az cognitiveservices account show --name "$AI_VISION_NAME" --resource-group "$RESOURCE_GROUP" >/dev/null 2>&1; then
        log_warning "AI Vision service $AI_VISION_NAME already exists"
    else
        az cognitiveservices account create \
            --name "$AI_VISION_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --kind ComputerVision \
            --sku S1 \
            --custom-domain "$AI_VISION_NAME" \
            --tags purpose=content-moderation
        
        log_success "Azure AI Vision service created: $AI_VISION_NAME"
    fi
    
    # Get AI Vision endpoint and key
    export AI_VISION_ENDPOINT=$(az cognitiveservices account show \
        --name "$AI_VISION_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --query properties.endpoint --output tsv)
    
    export AI_VISION_KEY=$(az cognitiveservices account keys list \
        --name "$AI_VISION_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --query key1 --output tsv)
    
    log_success "AI Vision service configured with endpoint: $AI_VISION_ENDPOINT"
}

# Function to create Event Hubs namespace and hub
create_event_hubs() {
    log_info "Creating Event Hubs namespace: $EVENT_HUB_NAMESPACE"
    
    if az eventhubs namespace show --name "$EVENT_HUB_NAMESPACE" --resource-group "$RESOURCE_GROUP" >/dev/null 2>&1; then
        log_warning "Event Hubs namespace $EVENT_HUB_NAMESPACE already exists"
    else
        az eventhubs namespace create \
            --name "$EVENT_HUB_NAMESPACE" \
            --resource-group "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --sku Standard \
            --enable-auto-inflate true \
            --maximum-throughput-units 10 \
            --tags purpose=video-frame-streaming
        
        log_success "Event Hubs namespace created: $EVENT_HUB_NAMESPACE"
    fi
    
    # Create event hub
    log_info "Creating event hub: $EVENT_HUB_NAME"
    
    if az eventhubs eventhub show --name "$EVENT_HUB_NAME" --namespace-name "$EVENT_HUB_NAMESPACE" --resource-group "$RESOURCE_GROUP" >/dev/null 2>&1; then
        log_warning "Event hub $EVENT_HUB_NAME already exists"
    else
        az eventhubs eventhub create \
            --name "$EVENT_HUB_NAME" \
            --namespace-name "$EVENT_HUB_NAMESPACE" \
            --resource-group "$RESOURCE_GROUP" \
            --partition-count 4 \
            --message-retention 1
        
        log_success "Event hub created: $EVENT_HUB_NAME"
    fi
    
    # Get Event Hubs connection string
    export EH_CONNECTION_STRING=$(az eventhubs namespace authorization-rule keys list \
        --name RootManageSharedAccessKey \
        --namespace-name "$EVENT_HUB_NAMESPACE" \
        --resource-group "$RESOURCE_GROUP" \
        --query primaryConnectionString --output tsv)
    
    log_success "Event Hubs configured with 4 partitions"
}

# Function to create Stream Analytics job
create_stream_analytics_job() {
    log_info "Creating Stream Analytics job: $STREAM_ANALYTICS_JOB"
    
    if az stream-analytics job show --name "$STREAM_ANALYTICS_JOB" --resource-group "$RESOURCE_GROUP" >/dev/null 2>&1; then
        log_warning "Stream Analytics job $STREAM_ANALYTICS_JOB already exists"
    else
        az stream-analytics job create \
            --name "$STREAM_ANALYTICS_JOB" \
            --resource-group "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --streaming-units 3 \
            --output-error-policy "stop" \
            --tags purpose=real-time-processing
        
        log_success "Stream Analytics job created: $STREAM_ANALYTICS_JOB"
    fi
    
    # Create Stream Analytics input from Event Hubs
    log_info "Configuring Stream Analytics input from Event Hubs..."
    
    local eh_key=$(echo "$EH_CONNECTION_STRING" | cut -d';' -f3 | cut -d'=' -f2)
    
    az stream-analytics input create \
        --job-name "$STREAM_ANALYTICS_JOB" \
        --resource-group "$RESOURCE_GROUP" \
        --name "VideoFrameInput" \
        --type "Stream" \
        --datasource '{
            "type": "Microsoft.ServiceBus/EventHub",
            "properties": {
                "eventHubName": "'$EVENT_HUB_NAME'",
                "serviceBusNamespace": "'$EVENT_HUB_NAMESPACE'",
                "sharedAccessPolicyName": "RootManageSharedAccessKey",
                "sharedAccessPolicyKey": "'$eh_key'"
            }
        }' \
        --serialization '{
            "type": "Json",
            "properties": {
                "encoding": "UTF8"
            }
        }' >/dev/null 2>&1 || log_warning "Input may already exist"
    
    log_success "Stream Analytics input configured"
}

# Function to configure Stream Analytics output
configure_stream_analytics_output() {
    log_info "Configuring Stream Analytics output to storage..."
    
    local storage_key=$(az storage account keys list \
        --account-name "$STORAGE_ACCOUNT" \
        --resource-group "$RESOURCE_GROUP" \
        --query '[0].value' --output tsv)
    
    az stream-analytics output create \
        --job-name "$STREAM_ANALYTICS_JOB" \
        --resource-group "$RESOURCE_GROUP" \
        --name "ModerationOutput" \
        --datasource '{
            "type": "Microsoft.Storage/Blob",
            "properties": {
                "storageAccounts": [{
                    "accountName": "'$STORAGE_ACCOUNT'",
                    "accountKey": "'$storage_key'"
                }],
                "container": "moderation-results",
                "pathPattern": "year={datetime:yyyy}/month={datetime:MM}/day={datetime:dd}/hour={datetime:HH}",
                "dateFormat": "yyyy/MM/dd",
                "timeFormat": "HH"
            }
        }' \
        --serialization '{
            "type": "Json",
            "properties": {
                "encoding": "UTF8",
                "format": "LineSeparated"
            }
        }' >/dev/null 2>&1 || log_warning "Output may already exist"
    
    log_success "Stream Analytics output configured with time-based partitioning"
}

# Function to create Logic App
create_logic_app() {
    log_info "Creating Logic App: $LOGIC_APP_NAME"
    
    if az logic workflow show --name "$LOGIC_APP_NAME" --resource-group "$RESOURCE_GROUP" >/dev/null 2>&1; then
        log_warning "Logic App $LOGIC_APP_NAME already exists"
    else
        az logic workflow create \
            --name "$LOGIC_APP_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --definition '{
                "$schema": "https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#",
                "contentVersion": "1.0.0.0",
                "parameters": {},
                "triggers": {
                    "manual": {
                        "type": "Request",
                        "kind": "Http",
                        "inputs": {
                            "schema": {
                                "type": "object",
                                "properties": {
                                    "videoId": {"type": "string"},
                                    "frameTimestamp": {"type": "string"},
                                    "moderationScore": {"type": "number"},
                                    "contentFlags": {"type": "array"}
                                }
                            }
                        }
                    }
                },
                "actions": {
                    "Send_notification": {
                        "type": "Http",
                        "inputs": {
                            "method": "POST",
                            "uri": "https://httpbin.org/post",
                            "headers": {
                                "Content-Type": "application/json"
                            },
                            "body": {
                                "message": "Inappropriate content detected",
                                "videoId": "@{triggerBody()[\"videoId\"]}",
                                "score": "@{triggerBody()[\"moderationScore\"]}"
                            }
                        }
                    }
                }
            }' \
            --tags purpose=content-moderation-response
        
        log_success "Logic App created: $LOGIC_APP_NAME"
    fi
    
    # Get Logic App trigger URL
    export LOGIC_APP_URL=$(az logic workflow show \
        --name "$LOGIC_APP_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --query "accessEndpoint" --output tsv)
    
    log_success "Logic App configured with HTTP trigger"
}

# Function to configure Stream Analytics query
configure_stream_analytics_query() {
    log_info "Configuring Stream Analytics transformation query..."
    
    # Create the query content
    cat > /tmp/query.sql << 'EOF'
WITH ProcessedFrames AS (
    SELECT 
        videoId,
        frameUrl,
        timestamp,
        userId,
        channelId,
        System.Timestamp() AS ProcessingTime
    FROM VideoFrameInput
    WHERE frameUrl IS NOT NULL
),
ModerationResults AS (
    SELECT 
        videoId,
        frameUrl,
        timestamp,
        userId,
        channelId,
        ProcessingTime,
        -- Simulate AI Vision API call results
        CASE 
            WHEN LEN(videoId) % 10 < 2 THEN 0.85  -- 20% flagged content
            ELSE 0.15 
        END AS adultScore,
        CASE 
            WHEN LEN(videoId) % 10 < 1 THEN 0.75  -- 10% racy content
            ELSE 0.05 
        END AS racyScore
    FROM ProcessedFrames
)
SELECT 
    videoId,
    frameUrl,
    timestamp,
    userId,
    channelId,
    ProcessingTime,
    adultScore,
    racyScore,
    CASE 
        WHEN adultScore > 0.7 OR racyScore > 0.6 THEN 'BLOCKED'
        WHEN adultScore > 0.5 OR racyScore > 0.4 THEN 'REVIEW'
        ELSE 'APPROVED'
    END AS moderationDecision,
    CASE 
        WHEN adultScore > 0.7 OR racyScore > 0.6 THEN 1
        ELSE 0
    END AS requiresAction
INTO ModerationOutput
FROM ModerationResults
EOF
    
    # Update Stream Analytics job with the query
    az stream-analytics transformation create \
        --job-name "$STREAM_ANALYTICS_JOB" \
        --resource-group "$RESOURCE_GROUP" \
        --name "ModerationTransformation" \
        --streaming-units 3 \
        --query "$(cat /tmp/query.sql)" >/dev/null 2>&1 || log_warning "Transformation may already exist"
    
    # Clean up temporary file
    rm -f /tmp/query.sql
    
    log_success "Stream Analytics transformation configured with content moderation logic"
}

# Function to start Stream Analytics job
start_stream_analytics_job() {
    log_info "Starting Stream Analytics job..."
    
    local job_state=$(az stream-analytics job show \
        --name "$STREAM_ANALYTICS_JOB" \
        --resource-group "$RESOURCE_GROUP" \
        --query "jobState" --output tsv)
    
    if [ "$job_state" = "Running" ]; then
        log_warning "Stream Analytics job is already running"
    else
        az stream-analytics job start \
            --name "$STREAM_ANALYTICS_JOB" \
            --resource-group "$RESOURCE_GROUP" \
            --output-start-mode "JobStartTime"
        
        log_info "Waiting for Stream Analytics job to start..."
        sleep 30
        
        local new_state=$(az stream-analytics job show \
            --name "$STREAM_ANALYTICS_JOB" \
            --resource-group "$RESOURCE_GROUP" \
            --query "jobState" --output tsv)
        
        log_success "Stream Analytics job status: $new_state"
    fi
}

# Function to display deployment summary
display_deployment_summary() {
    log_success "=== DEPLOYMENT COMPLETED SUCCESSFULLY ==="
    echo
    log_info "Resource Group: $RESOURCE_GROUP"
    log_info "Location: $LOCATION"
    echo
    log_info "Deployed Resources:"
    log_info "  • Azure AI Vision: $AI_VISION_NAME"
    log_info "  • Event Hubs Namespace: $EVENT_HUB_NAMESPACE"
    log_info "  • Event Hub: $EVENT_HUB_NAME"
    log_info "  • Storage Account: $STORAGE_ACCOUNT"
    log_info "  • Stream Analytics Job: $STREAM_ANALYTICS_JOB"
    log_info "  • Logic App: $LOGIC_APP_NAME"
    echo
    log_info "Testing:"
    log_info "  • Send test events to Event Hub: $EVENT_HUB_NAME"
    log_info "  • Monitor results in storage container: moderation-results"
    log_info "  • Logic App trigger URL: $LOGIC_APP_URL"
    echo
    log_warning "IMPORTANT: Remember to run destroy.sh when testing is complete to avoid ongoing charges!"
}

# Function to handle script interruption
cleanup_on_exit() {
    if [ $? -ne 0 ]; then
        log_error "Deployment failed or was interrupted"
        log_info "You may need to manually clean up partially created resources"
        log_info "Run './destroy.sh' to clean up any created resources"
    fi
}

# Set trap for cleanup on exit
trap cleanup_on_exit EXIT

# Main deployment function
main() {
    log_info "=== Azure Intelligent Video Content Moderation - Deployment ==="
    log_info "Starting deployment process..."
    echo
    
    check_prerequisites
    set_environment_variables
    
    log_info "=== Creating Infrastructure ==="
    create_resource_group
    create_storage_account
    create_ai_vision_service
    create_event_hubs
    create_stream_analytics_job
    configure_stream_analytics_output
    create_logic_app
    configure_stream_analytics_query
    start_stream_analytics_job
    
    display_deployment_summary
}

# Execute main function
main "$@"