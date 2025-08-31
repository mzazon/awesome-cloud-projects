#!/bin/bash

# =============================================================================
# Azure Automated Video Analysis with Video Indexer and Functions - Deploy Script
# =============================================================================
# This script deploys a complete automated video analysis pipeline using:
# - Azure AI Video Indexer for AI-powered video insights
# - Azure Functions for serverless event-driven processing
# - Azure Blob Storage for video and insights storage
#
# Prerequisites:
# - Azure CLI installed and logged in (az login)
# - Azure subscription with Owner or Contributor permissions
# - OpenSSL for generating random suffixes
# - Zip utility for function deployment
#
# Usage: ./deploy.sh [options]
# Options:
#   -g, --resource-group    Specify resource group name (optional)
#   -l, --location         Specify Azure region (default: eastus)
#   -h, --help             Show help message
#   --dry-run              Show what would be deployed without executing
#
# =============================================================================

set -euo pipefail  # Exit on any error, undefined variables, or pipe failures

# =============================================================================
# CONFIGURATION AND DEFAULTS
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/deploy_$(date +%Y%m%d_%H%M%S).log"

# Default configuration
DEFAULT_LOCATION="eastus"
DEFAULT_TAGS="purpose=video-analysis environment=demo recipe=automated-video-analysis"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Global variables
RESOURCE_GROUP=""
LOCATION="$DEFAULT_LOCATION"
DRY_RUN=false
CLEANUP_ON_ERROR=true

# =============================================================================
# LOGGING AND OUTPUT FUNCTIONS
# =============================================================================

log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message" | tee -a "$LOG_FILE"
}

log_info() {
    log "INFO" "$@"
    echo -e "${BLUE}ℹ️  $*${NC}"
}

log_success() {
    log "SUCCESS" "$@"
    echo -e "${GREEN}✅ $*${NC}"
}

log_warning() {
    log "WARNING" "$@"
    echo -e "${YELLOW}⚠️  $*${NC}"
}

log_error() {
    log "ERROR" "$@"
    echo -e "${RED}❌ $*${NC}" >&2
}

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

show_help() {
    cat << EOF
Azure Automated Video Analysis Deployment Script

This script deploys a complete automated video analysis pipeline using Azure AI
Video Indexer, Azure Functions, and Azure Blob Storage.

USAGE:
    $0 [OPTIONS]

OPTIONS:
    -g, --resource-group NAME    Specify resource group name
    -l, --location REGION        Specify Azure region (default: eastus)
    -h, --help                  Show this help message
    --dry-run                   Show what would be deployed without executing
    --no-cleanup                Don't cleanup resources on deployment failure

EXAMPLES:
    $0                                          # Deploy with default settings
    $0 -g my-video-rg -l westus2               # Deploy to specific RG and region
    $0 --dry-run                               # Preview deployment without executing

ESTIMATED COST:
    \$15-25 for testing (includes Video Indexer processing, Functions execution, 
    and Blob Storage costs)

EOF
}

check_prerequisites() {
    log_info "Checking prerequisites"
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        log_error "Azure CLI is not installed. Please install it from: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
        exit 1
    fi

    # Check Azure CLI version (minimum 2.50.0)
    local az_version=$(az version --query '"azure-cli"' -o tsv)
    log_info "Azure CLI version: $az_version"
    
    # Check if logged in
    if ! az account show &> /dev/null; then
        log_error "Not logged in to Azure. Please run 'az login' first"
        exit 1
    fi

    # Check if openssl is available for random generation
    if ! command -v openssl &> /dev/null; then
        log_error "OpenSSL is required for generating unique resource names"
        exit 1
    fi

    # Check if zip is available for function deployment
    if ! command -v zip &> /dev/null; then
        log_error "Zip utility is required for function deployment"
        exit 1
    fi

    local subscription_name=$(az account show --query name -o tsv)
    local subscription_id=$(az account show --query id -o tsv)
    log_success "Logged in to Azure subscription: $subscription_name ($subscription_id)"
}

validate_location() {
    local location="$1"
    log_info "Validating Azure region: $location"
    
    if ! az account list-locations --query "[?name=='$location'].name" -o tsv | grep -q "$location"; then
        log_error "Invalid Azure region: $location"
        log_info "Available regions: $(az account list-locations --query '[].name' -o tsv | tr '\n' ', ')"
        exit 1
    fi
    
    # Check Video Indexer availability in region
    local vi_available_regions=("eastus" "westus2" "northeurope" "westeurope" "eastasia" "southeastasia")
    if [[ ! " ${vi_available_regions[@]} " =~ " ${location} " ]]; then
        log_warning "Video Indexer may not be available in region: $location"
        log_info "Recommended regions for Video Indexer: ${vi_available_regions[*]}"
        read -p "Continue anyway? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
    
    log_success "Region validated: $location"
}

generate_resource_names() {
    log_info "Generating unique resource names"
    
    # Generate unique suffix
    RANDOM_SUFFIX=$(openssl rand -hex 3)
    
    # Set resource names with generated suffix
    RESOURCE_GROUP="${RESOURCE_GROUP:-rg-video-analysis-${RANDOM_SUFFIX}}"
    STORAGE_ACCOUNT="savideo${RANDOM_SUFFIX}"
    FUNCTION_APP="func-video-analysis-${RANDOM_SUFFIX}"
    VI_ACCOUNT="vi-account-${RANDOM_SUFFIX}"
    
    # Validate storage account name (3-24 chars, lowercase alphanumeric)
    if [[ ${#STORAGE_ACCOUNT} -gt 24 ]]; then
        STORAGE_ACCOUNT="savideo$(openssl rand -hex 2)"
    fi
    
    log_info "Resource names generated:"
    log_info "  Resource Group: $RESOURCE_GROUP"
    log_info "  Storage Account: $STORAGE_ACCOUNT"
    log_info "  Function App: $FUNCTION_APP"
    log_info "  Video Indexer Account: $VI_ACCOUNT"
    log_info "  Random Suffix: $RANDOM_SUFFIX"
}

cleanup_on_error() {
    if [[ "$CLEANUP_ON_ERROR" == "true" ]]; then
        log_warning "Deployment failed. Cleaning up created resources..."
        
        # Check if resource group exists and delete it
        if az group show --name "$RESOURCE_GROUP" &> /dev/null; then
            log_info "Deleting resource group: $RESOURCE_GROUP"
            az group delete --name "$RESOURCE_GROUP" --yes --no-wait
            log_success "Resource group deletion initiated"
        fi
        
        # Clean up local files
        rm -f video-analysis-function.zip
        rm -rf video-analysis-function
    fi
}

# =============================================================================
# DEPLOYMENT FUNCTIONS
# =============================================================================

create_resource_group() {
    log_info "Creating resource group: $RESOURCE_GROUP in $LOCATION"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would create resource group: $RESOURCE_GROUP"
        return 0
    fi
    
    az group create \
        --name "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --tags $DEFAULT_TAGS
    
    log_success "Resource group created: $RESOURCE_GROUP"
}

create_storage_account() {
    log_info "Creating storage account: $STORAGE_ACCOUNT"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would create storage account: $STORAGE_ACCOUNT"
        return 0
    fi
    
    az storage account create \
        --name "$STORAGE_ACCOUNT" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --sku Standard_LRS \
        --kind StorageV2 \
        --min-tls-version TLS1_2 \
        --allow-blob-public-access false \
        --tags $DEFAULT_TAGS
    
    # Get storage connection string
    STORAGE_CONNECTION=$(az storage account show-connection-string \
        --name "$STORAGE_ACCOUNT" \
        --resource-group "$RESOURCE_GROUP" \
        --query connectionString --output tsv)
    
    log_success "Storage account created: $STORAGE_ACCOUNT"
}

create_blob_containers() {
    log_info "Creating blob storage containers"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would create containers: videos, insights"
        return 0
    fi
    
    # Create container for video uploads
    az storage container create \
        --name videos \
        --account-name "$STORAGE_ACCOUNT" \
        --connection-string "$STORAGE_CONNECTION" \
        --public-access off
    
    # Create container for analysis results
    az storage container create \
        --name insights \
        --account-name "$STORAGE_ACCOUNT" \
        --connection-string "$STORAGE_CONNECTION" \
        --public-access off
    
    log_success "Blob containers created: videos, insights"
}

create_video_indexer_account() {
    log_info "Creating Azure AI Video Indexer account: $VI_ACCOUNT"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would create Video Indexer account: $VI_ACCOUNT"
        return 0
    fi
    
    # Create Video Indexer ARM-based account
    az cognitiveservices account create \
        --name "$VI_ACCOUNT" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --kind VideoIndexer \
        --sku S0 \
        --custom-domain "$VI_ACCOUNT" \
        --tags $DEFAULT_TAGS
    
    # Get Video Indexer account ID
    VI_ACCOUNT_ID=$(az cognitiveservices account show \
        --name "$VI_ACCOUNT" \
        --resource-group "$RESOURCE_GROUP" \
        --query properties.accountId --output tsv)
    
    log_success "Video Indexer account created: $VI_ACCOUNT (ID: $VI_ACCOUNT_ID)"
}

create_function_app() {
    log_info "Creating Function App: $FUNCTION_APP"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would create Function App: $FUNCTION_APP"
        return 0
    fi
    
    # Create Function App with consumption plan
    az functionapp create \
        --name "$FUNCTION_APP" \
        --resource-group "$RESOURCE_GROUP" \
        --storage-account "$STORAGE_ACCOUNT" \
        --consumption-plan-location "$LOCATION" \
        --runtime python \
        --runtime-version 3.11 \
        --functions-version 4 \
        --tags $DEFAULT_TAGS
    
    log_success "Function App created: $FUNCTION_APP"
}

configure_function_settings() {
    log_info "Configuring Function App settings"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would configure Function App settings"
        return 0
    fi
    
    # Get Video Indexer access key
    VI_ACCESS_KEY=$(az cognitiveservices account keys list \
        --name "$VI_ACCOUNT" \
        --resource-group "$RESOURCE_GROUP" \
        --query key1 --output tsv)
    
    # Configure Function App settings
    az functionapp config appsettings set \
        --name "$FUNCTION_APP" \
        --resource-group "$RESOURCE_GROUP" \
        --settings \
            "STORAGE_CONNECTION_STRING=$STORAGE_CONNECTION" \
            "VIDEO_INDEXER_ACCOUNT_ID=$VI_ACCOUNT_ID" \
            "VIDEO_INDEXER_ACCESS_KEY=$VI_ACCESS_KEY" \
            "VIDEO_INDEXER_LOCATION=$LOCATION" \
            "RESOURCE_GROUP=$RESOURCE_GROUP"
    
    log_success "Function App configured with Video Indexer integration"
}

create_function_code() {
    log_info "Creating Function code structure"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would create Function code structure"
        return 0
    fi
    
    # Clean up any existing directory
    rm -rf video-analysis-function
    
    # Create function code directory
    mkdir -p video-analysis-function/VideoAnalyzer
    cd video-analysis-function
    
    # Create host.json
    cat > host.json << 'EOF'
{
  "version": "2.0",
  "extensionBundle": {
    "id": "Microsoft.Azure.Functions.ExtensionBundle",
    "version": "[4.0.0, 5.0.0)"
  },
  "functionTimeout": "00:10:00",
  "logging": {
    "applicationInsights": {
      "samplingSettings": {
        "isEnabled": true
      }
    }
  }
}
EOF
    
    # Create requirements.txt
    cat > requirements.txt << 'EOF'
azure-functions>=1.18.0
azure-storage-blob>=12.17.0
requests>=2.31.0
azure-functions-worker>=1.2.0
EOF
    
    # Create function.json
    cat > VideoAnalyzer/function.json << 'EOF'
{
  "scriptFile": "__init__.py",
  "bindings": [
    {
      "name": "myblob",
      "type": "blobTrigger",
      "direction": "in",
      "path": "videos/{name}",
      "connection": "STORAGE_CONNECTION_STRING"
    },
    {
      "name": "outputBlob",
      "type": "blob",
      "direction": "out",
      "path": "insights/{name}.json",
      "connection": "STORAGE_CONNECTION_STRING"
    }
  ]
}
EOF
    
    # Create the main function implementation
    cat > VideoAnalyzer/__init__.py << 'EOF'
import logging
import json
import os
import requests
import time
from urllib.parse import quote
from azure.storage.blob import BlobServiceClient
import azure.functions as func

def main(myblob: func.InputStream, outputBlob: func.Out[str]):
    logging.info(f"Processing video: {myblob.name}")
    
    # Get configuration from environment variables
    vi_account_id = os.environ['VIDEO_INDEXER_ACCOUNT_ID']
    vi_access_key = os.environ['VIDEO_INDEXER_ACCESS_KEY']
    vi_location = os.environ['VIDEO_INDEXER_LOCATION']
    storage_connection = os.environ['STORAGE_CONNECTION_STRING']
    
    try:
        # Create video name from blob name
        video_name = os.path.basename(myblob.name)
        
        # For ARM accounts, use management API for token generation
        token_url = f"https://api.videoindexer.ai/auth/{vi_location}/Accounts/{vi_account_id}/AccessToken?allowEdit=true"
        auth_headers = {
            'Ocp-Apim-Subscription-Key': vi_access_key
        }
        
        auth_response = requests.get(token_url, headers=auth_headers)
        
        if auth_response.status_code == 200:
            access_token = auth_response.json()
        else:
            raise Exception(f"Failed to get Video Indexer access token: {auth_response.text}")
            
        logging.info("Successfully obtained Video Indexer access token")
        
        # Create blob service client and generate SAS URL for video access
        blob_service_client = BlobServiceClient.from_connection_string(storage_connection)
        blob_client = blob_service_client.get_blob_client(
            container="videos", 
            blob=os.path.basename(myblob.name)
        )
        
        # Generate SAS token for Video Indexer to access the video
        from azure.storage.blob import generate_blob_sas, BlobSasPermissions
        from datetime import datetime, timedelta
        
        sas_token = generate_blob_sas(
            account_name=blob_client.account_name,
            container_name=blob_client.container_name,
            blob_name=blob_client.blob_name,
            account_key=storage_connection.split('AccountKey=')[1].split(';')[0],
            permission=BlobSasPermissions(read=True),
            expiry=datetime.utcnow() + timedelta(hours=2)
        )
        
        video_url = f"{blob_client.url}?{sas_token}"
        
        # Upload video to Video Indexer
        upload_url = f"https://api.videoindexer.ai/{vi_location}/Accounts/{vi_account_id}/Videos"
        upload_params = {
            'accessToken': access_token,
            'name': video_name,
            'videoUrl': video_url,
            'privacy': 'Private',
            'partition': 'default'
        }
        
        upload_response = requests.post(upload_url, params=upload_params)
        
        if upload_response.status_code != 200:
            raise Exception(f"Video upload failed: {upload_response.text}")
            
        video_id = upload_response.json()['id']
        logging.info(f"Video uploaded successfully. Video ID: {video_id}")
        
        # Poll for processing completion with exponential backoff
        processing_state = "Processing"
        max_attempts = 20
        attempt = 0
        wait_time = 30
        
        while processing_state in ["Processing", "Uploaded"] and attempt < max_attempts:
            time.sleep(wait_time)
            
            status_url = f"https://api.videoindexer.ai/{vi_location}/Accounts/{vi_account_id}/Videos/{video_id}/Index"
            status_params = {'accessToken': access_token}
            
            status_response = requests.get(status_url, params=status_params)
            
            if status_response.status_code == 200:
                status_data = status_response.json()
                processing_state = status_data.get('state', 'Processing')
                logging.info(f"Processing state: {processing_state}")
            else:
                logging.warning(f"Status check failed: {status_response.text}")
            
            attempt += 1
            # Exponential backoff with max 60 seconds
            wait_time = min(wait_time * 1.2, 60)
        
        if processing_state == "Processed":
            # Get video insights
            insights_url = f"https://api.videoindexer.ai/{vi_location}/Accounts/{vi_account_id}/Videos/{video_id}/Index"
            insights_params = {'accessToken': access_token}
            
            insights_response = requests.get(insights_url, params=insights_params)
            
            if insights_response.status_code == 200:
                insights_data = insights_response.json()
                
                # Create comprehensive summary of insights
                summary = {
                    'video_name': video_name,
                    'video_id': video_id,
                    'duration_seconds': insights_data.get('durationInSeconds', 0),
                    'transcript': extract_transcript(insights_data),
                    'faces': extract_faces(insights_data),
                    'objects': extract_objects(insights_data),
                    'emotions': extract_emotions(insights_data),
                    'keywords': extract_keywords(insights_data),
                    'processing_completed': datetime.utcnow().isoformat(),
                    'full_insights': insights_data
                }
                
                # Output insights to blob storage
                outputBlob.set(json.dumps(summary, indent=2))
                logging.info("Video analysis completed and insights saved")
            else:
                raise Exception(f"Failed to retrieve video insights: {insights_response.text}")
        else:
            logging.warning(f"Video processing did not complete within timeout. Final state: {processing_state}")
            # Still save partial results
            partial_result = {
                'video_name': video_name,
                'video_id': video_id,
                'status': processing_state,
                'message': 'Processing timeout - partial results may be available later'
            }
            outputBlob.set(json.dumps(partial_result, indent=2))
            
    except Exception as e:
        logging.error(f"Error processing video: {str(e)}")
        error_result = {
            'video_name': myblob.name,
            'error': str(e),
            'status': 'failed',
            'timestamp': datetime.utcnow().isoformat()
        }
        outputBlob.set(json.dumps(error_result, indent=2))

def extract_transcript(insights_data):
    """Extract transcript from Video Indexer insights"""
    try:
        videos = insights_data.get('videos', [])
        if videos and 'insights' in videos[0]:
            transcript_items = videos[0]['insights'].get('transcript', [])
            return [{'text': item.get('text', ''), 
                    'confidence': item.get('confidence', 0),
                    'start': item.get('instances', [{}])[0].get('start', ''),
                    'end': item.get('instances', [{}])[0].get('end', '')} 
                   for item in transcript_items]
    except Exception as e:
        logging.warning(f"Error extracting transcript: {e}")
    return []

def extract_faces(insights_data):
    """Extract face detection results"""
    try:
        videos = insights_data.get('videos', [])
        if videos and 'insights' in videos[0]:
            faces = videos[0]['insights'].get('faces', [])
            return [{'name': face.get('name', 'Unknown'), 
                    'confidence': face.get('confidence', 0),
                    'description': face.get('description', ''),
                    'thumbnail_id': face.get('thumbnailId', '')} 
                   for face in faces]
    except Exception as e:
        logging.warning(f"Error extracting faces: {e}")
    return []

def extract_objects(insights_data):
    """Extract object detection results"""
    try:
        videos = insights_data.get('videos', [])
        if videos and 'insights' in videos[0]:
            labels = videos[0]['insights'].get('labels', [])
            return [{'name': label.get('name', ''), 
                    'confidence': label.get('confidence', 0),
                    'language': label.get('language', 'en-US')} 
                   for label in labels]
    except Exception as e:
        logging.warning(f"Error extracting objects: {e}")
    return []

def extract_emotions(insights_data):
    """Extract emotion analysis results"""
    try:
        videos = insights_data.get('videos', [])
        if videos and 'insights' in videos[0]:
            emotions = videos[0]['insights'].get('emotions', [])
            return [{'type': emotion.get('type', ''), 
                    'confidence': emotion.get('confidence', 0)} 
                   for emotion in emotions]
    except Exception as e:
        logging.warning(f"Error extracting emotions: {e}")
    return []

def extract_keywords(insights_data):
    """Extract keywords from video insights"""
    try:
        videos = insights_data.get('videos', [])
        if videos and 'insights' in videos[0]:
            keywords = videos[0]['insights'].get('keywords', [])
            return [{'name': keyword.get('name', ''), 
                    'confidence': keyword.get('confidence', 0)} 
                   for keyword in keywords]
    except Exception as e:
        logging.warning(f"Error extracting keywords: {e}")
    return []
EOF
    
    cd ..
    log_success "Function code structure created"
}

deploy_function_code() {
    log_info "Deploying Function code to Azure"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would deploy Function code"
        return 0
    fi
    
    cd video-analysis-function
    
    # Create deployment package
    zip -r ../video-analysis-function.zip . -x "*.git*" "*.DS_Store*"
    
    cd ..
    
    # Deploy function code to Azure
    az functionapp deployment source config-zip \
        --name "$FUNCTION_APP" \
        --resource-group "$RESOURCE_GROUP" \
        --src video-analysis-function.zip
    
    # Wait for deployment to complete
    log_info "Waiting for function deployment to complete..."
    sleep 60
    
    log_success "Function deployed successfully to Azure"
}

verify_deployment() {
    log_info "Verifying deployment"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would verify deployment"
        return 0
    fi
    
    # Check Function App status
    local func_state=$(az functionapp show \
        --name "$FUNCTION_APP" \
        --resource-group "$RESOURCE_GROUP" \
        --query state --output tsv)
    
    if [[ "$func_state" == "Running" ]]; then
        log_success "Function App is running: $FUNCTION_APP"
    else
        log_warning "Function App state: $func_state"
    fi
    
    # Verify function configuration
    local vi_config=$(az functionapp config appsettings list \
        --name "$FUNCTION_APP" \
        --resource-group "$RESOURCE_GROUP" \
        --query "[?name=='VIDEO_INDEXER_ACCOUNT_ID'].value" --output tsv)
    
    if [[ -n "$vi_config" ]]; then
        log_success "Video Indexer configuration verified"
    else
        log_warning "Video Indexer configuration not found"
    fi
}

# =============================================================================
# MAIN DEPLOYMENT LOGIC
# =============================================================================

main() {
    log_info "Starting Azure Automated Video Analysis deployment"
    log_info "Log file: $LOG_FILE"
    
    # Set up error handling
    trap cleanup_on_error ERR
    
    # Check prerequisites
    check_prerequisites
    
    # Validate and set up configuration
    validate_location "$LOCATION"
    generate_resource_names
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "=== DRY RUN MODE - No resources will be created ==="
        log_info "Resource Group: $RESOURCE_GROUP"
        log_info "Location: $LOCATION"
        log_info "Storage Account: $STORAGE_ACCOUNT"
        log_info "Function App: $FUNCTION_APP"
        log_info "Video Indexer Account: $VI_ACCOUNT"
        log_info "=== END DRY RUN PREVIEW ==="
        return 0
    fi
    
    # Main deployment steps
    log_info "=== DEPLOYMENT STARTED ==="
    
    create_resource_group
    create_storage_account
    create_blob_containers
    create_video_indexer_account
    create_function_app
    configure_function_settings
    create_function_code
    deploy_function_code
    verify_deployment
    
    # Clean up deployment artifacts
    rm -f video-analysis-function.zip
    rm -rf video-analysis-function
    
    log_success "=== DEPLOYMENT COMPLETED SUCCESSFULLY ==="
    echo
    echo -e "${GREEN}🎉 Azure Automated Video Analysis Pipeline Deployed Successfully!${NC}"
    echo
    echo "📋 Deployment Summary:"
    echo "  Resource Group: $RESOURCE_GROUP"
    echo "  Location: $LOCATION"
    echo "  Storage Account: $STORAGE_ACCOUNT"
    echo "  Function App: $FUNCTION_APP"
    echo "  Video Indexer Account: $VI_ACCOUNT"
    echo
    echo "🧪 To test the pipeline:"
    echo "  1. Upload a video file to the 'videos' container in storage account: $STORAGE_ACCOUNT"
    echo "  2. Check the 'insights' container for analysis results"
    echo "  3. Monitor function logs in Azure portal for processing status"
    echo
    echo "💰 Estimated cost: \$15-25 for testing"
    echo "📖 Log file saved: $LOG_FILE"
    echo
    echo "🧹 To clean up resources, run: ./destroy.sh -g $RESOURCE_GROUP"
}

# =============================================================================
# COMMAND LINE ARGUMENT PARSING
# =============================================================================

while [[ $# -gt 0 ]]; do
    case $1 in
        -g|--resource-group)
            RESOURCE_GROUP="$2"
            shift 2
            ;;
        -l|--location)
            LOCATION="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --no-cleanup)
            CLEANUP_ON_ERROR=false
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Run main deployment
main