#!/bin/bash

# =================================================================
# Azure Video Content Processing Workflows - Deployment Script
# =================================================================
# This script deploys an automated video processing pipeline using:
# - Azure Container Instances for FFmpeg video processing
# - Azure Logic Apps for workflow orchestration
# - Azure Event Grid for event-driven automation
# - Azure Blob Storage for video storage and management
# =================================================================

set -euo pipefail

# Color coding for output
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
    log_error "Deployment failed at line $1. Exit code: $2"
    log_error "Check the Azure portal and clean up any partially created resources"
    exit 1
}

# Set up error handling
trap 'handle_error ${LINENO} $?' ERR

# Script metadata
SCRIPT_VERSION="1.0"
DEPLOYMENT_NAME="video-processing-workflow"
TIMESTAMP=$(date +"%Y%m%d-%H%M%S")

log_info "Starting Azure Video Content Processing Workflows deployment"
log_info "Script version: ${SCRIPT_VERSION}"
log_info "Deployment timestamp: ${TIMESTAMP}"

# =================================================================
# PREREQUISITES VALIDATION
# =================================================================

log_info "Validating prerequisites..."

# Check if Azure CLI is installed
if ! command -v az &> /dev/null; then
    log_error "Azure CLI is not installed. Please install Azure CLI first."
    exit 1
fi

# Check if user is logged in to Azure
if ! az account show &> /dev/null; then
    log_error "Not logged in to Azure. Please run 'az login' first."
    exit 1
fi

# Check if OpenSSL is available for random string generation
if ! command -v openssl &> /dev/null; then
    log_error "OpenSSL is not installed. Required for generating unique resource names."
    exit 1
fi

# Check if FFmpeg is available (for test video generation)
if ! command -v ffmpeg &> /dev/null; then
    log_warning "FFmpeg not found. Test video generation may fail."
fi

log_success "Prerequisites validation completed"

# =================================================================
# ENVIRONMENT CONFIGURATION
# =================================================================

log_info "Configuring deployment environment..."

# Set default values with environment variable override support
AZURE_LOCATION=${AZURE_LOCATION:-"eastus"}
RESOURCE_GROUP_PREFIX=${RESOURCE_GROUP_PREFIX:-"rg-video-workflow"}
FORCE_DEPLOY=${FORCE_DEPLOY:-false}

# Generate unique suffix for resource names
RANDOM_SUFFIX=${RANDOM_SUFFIX:-$(openssl rand -hex 3)}

# Set resource names with unique suffix
RESOURCE_GROUP="${RESOURCE_GROUP_PREFIX}-${RANDOM_SUFFIX}"
STORAGE_ACCOUNT="stvario${RANDOM_SUFFIX}"
LOGIC_APP_NAME="la-video-processor-${RANDOM_SUFFIX}"
EVENT_GRID_TOPIC="egt-video-events-${RANDOM_SUFFIX}"
CONTAINER_GROUP_NAME="cg-video-ffmpeg-${RANDOM_SUFFIX}"

# Get subscription information
SUBSCRIPTION_ID=$(az account show --query id --output tsv)
SUBSCRIPTION_NAME=$(az account show --query name --output tsv)

log_info "Deployment configuration:"
log_info "  Subscription: ${SUBSCRIPTION_NAME} (${SUBSCRIPTION_ID})"
log_info "  Location: ${AZURE_LOCATION}"
log_info "  Resource Group: ${RESOURCE_GROUP}"
log_info "  Random Suffix: ${RANDOM_SUFFIX}"

# =================================================================
# RESOURCE VALIDATION
# =================================================================

log_info "Checking for existing resources..."

# Check if resource group already exists
if az group show --name "${RESOURCE_GROUP}" &> /dev/null; then
    if [[ "${FORCE_DEPLOY}" == "true" ]]; then
        log_warning "Resource group ${RESOURCE_GROUP} already exists. Force deployment enabled."
    else
        log_error "Resource group ${RESOURCE_GROUP} already exists."
        log_error "Use FORCE_DEPLOY=true to continue or choose a different suffix."
        exit 1
    fi
fi

# Check if storage account name is available
STORAGE_AVAILABLE=$(az storage account check-name --name "${STORAGE_ACCOUNT}" --query nameAvailable --output tsv 2>/dev/null || echo "false")
if [[ "${STORAGE_AVAILABLE}" != "true" ]] && [[ "${FORCE_DEPLOY}" != "true" ]]; then
    log_error "Storage account name ${STORAGE_ACCOUNT} is not available."
    log_error "Use FORCE_DEPLOY=true to continue or choose a different suffix."
    exit 1
fi

log_success "Resource validation completed"

# =================================================================
# CORE INFRASTRUCTURE DEPLOYMENT
# =================================================================

log_info "Creating core infrastructure..."

# Create resource group with proper tags
log_info "Creating resource group: ${RESOURCE_GROUP}"
az group create \
    --name "${RESOURCE_GROUP}" \
    --location "${AZURE_LOCATION}" \
    --tags purpose=video-processing environment=demo deployment-script=azure-video-workflow created-by="${USER:-unknown}" deployment-time="${TIMESTAMP}" > /dev/null

log_success "Resource group created: ${RESOURCE_GROUP}"

# Create storage account for video files
log_info "Creating storage account: ${STORAGE_ACCOUNT}"
az storage account create \
    --name "${STORAGE_ACCOUNT}" \
    --resource-group "${RESOURCE_GROUP}" \
    --location "${AZURE_LOCATION}" \
    --sku Standard_LRS \
    --kind StorageV2 \
    --access-tier Hot \
    --allow-blob-public-access false \
    --tags purpose=video-storage > /dev/null

log_success "Storage account created: ${STORAGE_ACCOUNT}"

# Get storage account connection string
log_info "Retrieving storage account connection string..."
STORAGE_CONNECTION_STRING=$(az storage account show-connection-string \
    --name "${STORAGE_ACCOUNT}" \
    --resource-group "${RESOURCE_GROUP}" \
    --output tsv)

# Create containers for input and output videos
log_info "Creating storage containers..."
az storage container create \
    --name "input-videos" \
    --connection-string "${STORAGE_CONNECTION_STRING}" > /dev/null

az storage container create \
    --name "output-videos" \
    --connection-string "${STORAGE_CONNECTION_STRING}" > /dev/null

log_success "Storage containers created for video processing"

# =================================================================
# EVENT GRID CONFIGURATION
# =================================================================

log_info "Setting up Event Grid infrastructure..."

# Create Event Grid topic for video processing events
log_info "Creating Event Grid topic: ${EVENT_GRID_TOPIC}"
az eventgrid topic create \
    --name "${EVENT_GRID_TOPIC}" \
    --resource-group "${RESOURCE_GROUP}" \
    --location "${AZURE_LOCATION}" \
    --tags purpose=video-events > /dev/null

# Get Event Grid topic endpoint and access key
EVENTGRID_ENDPOINT=$(az eventgrid topic show \
    --name "${EVENT_GRID_TOPIC}" \
    --resource-group "${RESOURCE_GROUP}" \
    --query endpoint --output tsv)

EVENTGRID_KEY=$(az eventgrid topic key list \
    --name "${EVENT_GRID_TOPIC}" \
    --resource-group "${RESOURCE_GROUP}" \
    --query key1 --output tsv)

log_success "Event Grid topic created: ${EVENT_GRID_TOPIC}"

# =================================================================
# LOGIC APP DEPLOYMENT
# =================================================================

log_info "Deploying Logic App workflow..."

# Create Logic App for workflow orchestration
log_info "Creating Logic App: ${LOGIC_APP_NAME}"
az logic workflow create \
    --name "${LOGIC_APP_NAME}" \
    --resource-group "${RESOURCE_GROUP}" \
    --location "${AZURE_LOCATION}" \
    --definition '{
        "$schema": "https://schema.management.azure.com/schemas/2016-06-01/workflowdefinition.json#",
        "contentVersion": "1.0.0.0",
        "parameters": {},
        "triggers": {},
        "actions": {},
        "outputs": {}
    }' \
    --tags purpose=video-orchestration > /dev/null

# Get Logic App resource ID for Event Grid subscription
LOGIC_APP_ID=$(az logic workflow show \
    --name "${LOGIC_APP_NAME}" \
    --resource-group "${RESOURCE_GROUP}" \
    --query id --output tsv)

log_success "Logic App created: ${LOGIC_APP_NAME}"

# Update Logic App with complete workflow definition
log_info "Updating Logic App workflow definition..."
az logic workflow update \
    --name "${LOGIC_APP_NAME}" \
    --resource-group "${RESOURCE_GROUP}" \
    --definition "{
        \"\$schema\": \"https://schema.management.azure.com/schemas/2016-06-01/workflowdefinition.json#\",
        \"contentVersion\": \"1.0.0.0\",
        \"parameters\": {
            \"storageAccountName\": {
                \"type\": \"string\",
                \"defaultValue\": \"${STORAGE_ACCOUNT}\"
            },
            \"containerGroupName\": {
                \"type\": \"string\", 
                \"defaultValue\": \"${CONTAINER_GROUP_NAME}\"
            }
        },
        \"triggers\": {
            \"manual\": {
                \"type\": \"Request\",
                \"kind\": \"Http\",
                \"inputs\": {
                    \"schema\": {
                        \"type\": \"object\",
                        \"properties\": {
                            \"subject\": {\"type\": \"string\"},
                            \"data\": {\"type\": \"object\"}
                        }
                    }
                }
            }
        },
        \"actions\": {
            \"ParseEventData\": {
                \"type\": \"ParseJson\",
                \"inputs\": {
                    \"content\": \"@triggerBody()\",
                    \"schema\": {
                        \"type\": \"object\",
                        \"properties\": {
                            \"subject\": {\"type\": \"string\"},
                            \"data\": {
                                \"type\": \"object\",
                                \"properties\": {
                                    \"url\": {\"type\": \"string\"}
                                }
                            }
                        }
                    }
                }
            },
            \"ProcessVideo\": {
                \"type\": \"Http\",
                \"inputs\": {
                    \"method\": \"POST\",
                    \"uri\": \"https://management.azure.com/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.ContainerInstance/containerGroups/${CONTAINER_GROUP_NAME}/restart\",
                    \"headers\": {
                        \"Authorization\": \"Bearer @{body('GetAccessToken')?.access_token}\"
                    }
                },
                \"runAfter\": {
                    \"ParseEventData\": [\"Succeeded\"]
                }
            }
        }
    }" > /dev/null

log_success "Logic App workflow definition updated"

# =================================================================
# CONTAINER INSTANCES DEPLOYMENT
# =================================================================

log_info "Deploying container infrastructure..."

# Create container group with FFmpeg for video processing
log_info "Creating container group: ${CONTAINER_GROUP_NAME}"
az container create \
    --name "${CONTAINER_GROUP_NAME}" \
    --resource-group "${RESOURCE_GROUP}" \
    --location "${AZURE_LOCATION}" \
    --image "jrottenberg/ffmpeg:latest" \
    --restart-policy Never \
    --cpu 2 \
    --memory 4 \
    --environment-variables \
        STORAGE_ACCOUNT="${STORAGE_ACCOUNT}" \
        STORAGE_CONNECTION_STRING="${STORAGE_CONNECTION_STRING}" \
    --command-line "tail -f /dev/null" \
    --tags purpose=video-processing > /dev/null

log_success "Container group created: ${CONTAINER_GROUP_NAME}"

# =================================================================
# EVENT INTEGRATION SETUP
# =================================================================

log_info "Configuring event-driven integration..."

# Create Event Grid subscription for blob created events
log_info "Creating Event Grid subscription for blob storage events..."
az eventgrid event-subscription create \
    --name "video-upload-subscription" \
    --source-resource-id "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.Storage/storageAccounts/${STORAGE_ACCOUNT}" \
    --endpoint "${LOGIC_APP_ID}/triggers/manual/paths/invoke" \
    --endpoint-type webhook \
    --included-event-types "Microsoft.Storage.BlobCreated" \
    --subject-begins-with "/blobServices/default/containers/input-videos/" > /dev/null

log_success "Event Grid subscription created for blob storage events"

# =================================================================
# VIDEO PROCESSING SCRIPT SETUP
# =================================================================

log_info "Setting up video processing capabilities..."

# Create video processing script
cat > /tmp/video-processor.sh << 'EOF'
#!/bin/bash

# Video processing script for Azure Container Instances
INPUT_URL=$1
OUTPUT_CONTAINER="output-videos"

# Download input video from blob storage
INPUT_FILE="/tmp/input_video.mp4"
OUTPUT_FILE="/tmp/output_video.mp4"

echo "Downloading video from: $INPUT_URL"
curl -o "$INPUT_FILE" "$INPUT_URL"

# Process video with FFmpeg - create multiple formats
echo "Processing video with FFmpeg..."

# Create 720p MP4 output
ffmpeg -i "$INPUT_FILE" \
       -vcodec libx264 \
       -acodec aac \
       -vf scale=1280:720 \
       -crf 23 \
       -preset medium \
       "$OUTPUT_FILE"

# Upload processed video to output container
echo "Uploading processed video to storage..."

# Upload using Azure CLI (requires authentication)
az storage blob upload \
    --file "$OUTPUT_FILE" \
    --container-name "$OUTPUT_CONTAINER" \
    --name "processed_$(basename $INPUT_FILE)" \
    --connection-string "$STORAGE_CONNECTION_STRING"

echo "Video processing completed successfully"
EOF

log_success "Video processing script created"

# =================================================================
# TESTING AND VALIDATION
# =================================================================

log_info "Performing deployment validation..."

# Test video generation and upload (if FFmpeg available)
if command -v ffmpeg &> /dev/null; then
    log_info "Creating test video file for validation..."
    
    # Generate a simple test video using FFmpeg
    ffmpeg -f lavfi -i testsrc=duration=10:size=640x480:rate=30 \
           -f lavfi -i sine=frequency=1000:duration=10 \
           -c:v libx264 -c:a aac -shortest test-video.mp4 -y &> /dev/null

    # Upload test video to trigger the workflow
    log_info "Uploading test video to trigger processing workflow..."
    az storage blob upload \
        --file test-video.mp4 \
        --container-name "input-videos" \
        --name "test-upload-${TIMESTAMP}.mp4" \
        --connection-string "${STORAGE_CONNECTION_STRING}" > /dev/null

    # Clean up test file
    rm -f test-video.mp4

    log_success "Test video uploaded successfully"
else
    log_warning "Skipping test video upload (FFmpeg not available)"
fi

# Validate resource deployment
log_info "Validating deployed resources..."

# Check Event Grid topic status
EVENTGRID_STATUS=$(az eventgrid topic show \
    --name "${EVENT_GRID_TOPIC}" \
    --resource-group "${RESOURCE_GROUP}" \
    --query provisioningState --output tsv)

if [[ "${EVENTGRID_STATUS}" != "Succeeded" ]]; then
    log_error "Event Grid topic deployment failed. Status: ${EVENTGRID_STATUS}"
    exit 1
fi

# Check Logic App status
LOGIC_APP_STATUS=$(az logic workflow show \
    --name "${LOGIC_APP_NAME}" \
    --resource-group "${RESOURCE_GROUP}" \
    --query state --output tsv)

if [[ "${LOGIC_APP_STATUS}" != "Enabled" ]]; then
    log_warning "Logic App is not enabled. Status: ${LOGIC_APP_STATUS}"
fi

# Check container group status
CONTAINER_STATUS=$(az container show \
    --name "${CONTAINER_GROUP_NAME}" \
    --resource-group "${RESOURCE_GROUP}" \
    --query containers[0].instanceView.currentState.state --output tsv 2>/dev/null || echo "Unknown")

log_info "Container group status: ${CONTAINER_STATUS}"

log_success "Resource validation completed"

# =================================================================
# DEPLOYMENT SUMMARY
# =================================================================

log_success "Azure Video Content Processing Workflows deployment completed successfully!"

echo ""
echo "=========================================="
echo "DEPLOYMENT SUMMARY"
echo "=========================================="
echo "Resource Group: ${RESOURCE_GROUP}"
echo "Location: ${AZURE_LOCATION}"
echo "Deployment Time: ${TIMESTAMP}"
echo ""
echo "Created Resources:"
echo "  • Storage Account: ${STORAGE_ACCOUNT}"
echo "  • Logic App: ${LOGIC_APP_NAME}"
echo "  • Event Grid Topic: ${EVENT_GRID_TOPIC}"
echo "  • Container Group: ${CONTAINER_GROUP_NAME}"
echo ""
echo "Storage Containers:"
echo "  • input-videos (for video uploads)"
echo "  • output-videos (for processed videos)"
echo ""
echo "Management URLs:"
echo "  • Resource Group: https://portal.azure.com/#@/resource/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/overview"
echo "  • Logic App: https://portal.azure.com/#@/resource/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.Logic/workflows/${LOGIC_APP_NAME}/overview"
echo "  • Storage Account: https://portal.azure.com/#@/resource/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.Storage/storageAccounts/${STORAGE_ACCOUNT}/overview"
echo ""
echo "Next Steps:"
echo "  1. Upload video files to the 'input-videos' container to trigger processing"
echo "  2. Monitor Logic App runs in the Azure portal"
echo "  3. Check processed videos in the 'output-videos' container"
echo "  4. Review container logs for processing details"
echo ""
echo "Estimated monthly cost: \$20-50 (varies by usage)"
echo "=========================================="
echo ""

# Save deployment configuration for cleanup script
cat > "/tmp/video-workflow-deployment-${RANDOM_SUFFIX}.env" << EOF
RESOURCE_GROUP=${RESOURCE_GROUP}
STORAGE_ACCOUNT=${STORAGE_ACCOUNT}
LOGIC_APP_NAME=${LOGIC_APP_NAME}
EVENT_GRID_TOPIC=${EVENT_GRID_TOPIC}
CONTAINER_GROUP_NAME=${CONTAINER_GROUP_NAME}
SUBSCRIPTION_ID=${SUBSCRIPTION_ID}
DEPLOYMENT_TIMESTAMP=${TIMESTAMP}
EOF

log_info "Deployment configuration saved to: /tmp/video-workflow-deployment-${RANDOM_SUFFIX}.env"
log_info "Use this file with the destroy.sh script for cleanup"

log_success "Deployment completed successfully! 🎉"