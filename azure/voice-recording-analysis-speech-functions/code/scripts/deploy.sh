#!/bin/bash

###################################################################################
# Azure Voice Recording Analysis Deployment Script
# 
# This script deploys the complete Azure infrastructure for voice recording analysis
# including Speech Services, Functions, and Blob Storage with proper error handling
# and idempotent operations.
###################################################################################

set -euo pipefail  # Exit on error, undefined vars, pipe failures

# Color codes for output formatting
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Script configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_FILE="${SCRIPT_DIR}/deploy.log"
readonly DEPLOYMENT_STATE_FILE="${SCRIPT_DIR}/.deployment_state"

# Initialize logging
exec 1> >(tee -a "$LOG_FILE")
exec 2> >(tee -a "$LOG_FILE" >&2)

###################################################################################
# Utility Functions
###################################################################################

log() {
    echo -e "[$(date +'%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

log_info() {
    log "${BLUE}[INFO]${NC} $*"
}

log_success() {
    log "${GREEN}[SUCCESS]${NC} $*"
}

log_warning() {
    log "${YELLOW}[WARNING]${NC} $*"
}

log_error() {
    log "${RED}[ERROR]${NC} $*"
}

cleanup_on_error() {
    log_error "Deployment failed. Cleaning up partial resources..."
    if [[ -f "$DEPLOYMENT_STATE_FILE" ]]; then
        source "$DEPLOYMENT_STATE_FILE"
        if [[ -n "${RESOURCE_GROUP:-}" ]]; then
            log_info "Removing resource group: $RESOURCE_GROUP"
            az group delete --name "$RESOURCE_GROUP" --yes --no-wait 2>/dev/null || true
        fi
        rm -f "$DEPLOYMENT_STATE_FILE"
    fi
    exit 1
}

trap cleanup_on_error ERR

save_deployment_state() {
    cat > "$DEPLOYMENT_STATE_FILE" << EOF
# Deployment state - DO NOT MODIFY MANUALLY
export RESOURCE_GROUP="$RESOURCE_GROUP"
export STORAGE_ACCOUNT="$STORAGE_ACCOUNT"
export SPEECH_SERVICE="$SPEECH_SERVICE"
export FUNCTION_APP="$FUNCTION_APP"
export LOCATION="$LOCATION"
export RANDOM_SUFFIX="$RANDOM_SUFFIX"
export DEPLOYMENT_TIMESTAMP="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
EOF
    log_info "Deployment state saved to $DEPLOYMENT_STATE_FILE"
}

###################################################################################
# Prerequisites Check
###################################################################################

check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        log_error "Azure CLI is not installed. Please install it from: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
        exit 1
    fi
    
    # Check if Azure Functions Core Tools is installed
    if ! command -v func &> /dev/null; then
        log_warning "Azure Functions Core Tools not found. Installing..."
        npm install -g azure-functions-core-tools@4 --unsafe-perm true || {
            log_error "Failed to install Azure Functions Core Tools. Please install manually: https://docs.microsoft.com/en-us/azure/azure-functions/functions-run-local"
            exit 1
        }
    fi
    
    # Check if user is logged in to Azure
    if ! az account show &> /dev/null; then
        log_error "Not logged in to Azure. Please run 'az login' first."
        exit 1
    fi
    
    # Check if required utilities are available
    for cmd in openssl curl jq; do
        if ! command -v "$cmd" &> /dev/null; then
            log_error "$cmd is required but not installed."
            exit 1
        fi
    done
    
    log_success "Prerequisites check completed"
}

###################################################################################
# Configuration Setup
###################################################################################

setup_configuration() {
    log_info "Setting up configuration..."
    
    # Set default location if not provided
    export LOCATION="${LOCATION:-eastus}"
    
    # Get subscription ID
    export SUBSCRIPTION_ID
    SUBSCRIPTION_ID=$(az account show --query id --output tsv)
    
    # Generate unique suffix for resource names
    export RANDOM_SUFFIX
    RANDOM_SUFFIX=$(openssl rand -hex 3)
    
    # Set resource names with unique suffix
    export RESOURCE_GROUP="rg-voice-analysis-${RANDOM_SUFFIX}"
    export STORAGE_ACCOUNT="voicestorage${RANDOM_SUFFIX}"
    export SPEECH_SERVICE="voice-speech-${RANDOM_SUFFIX}"
    export FUNCTION_APP="voice-function-${RANDOM_SUFFIX}"
    
    log_info "Configuration:"
    log_info "  Location: $LOCATION"
    log_info "  Subscription: $SUBSCRIPTION_ID"
    log_info "  Resource Group: $RESOURCE_GROUP"
    log_info "  Storage Account: $STORAGE_ACCOUNT"
    log_info "  Speech Service: $SPEECH_SERVICE"
    log_info "  Function App: $FUNCTION_APP"
    
    save_deployment_state
}

###################################################################################
# Resource Group Creation
###################################################################################

create_resource_group() {
    log_info "Creating resource group: $RESOURCE_GROUP"
    
    # Check if resource group already exists
    if az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        log_warning "Resource group $RESOURCE_GROUP already exists"
        return 0
    fi
    
    az group create \
        --name "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --tags \
            purpose=recipe \
            environment=demo \
            created-by=voice-analysis-recipe \
            auto-cleanup=true
    
    log_success "Resource group created: $RESOURCE_GROUP"
}

###################################################################################
# Storage Account Setup
###################################################################################

create_storage_account() {
    log_info "Creating storage account: $STORAGE_ACCOUNT"
    
    # Check if storage account already exists
    if az storage account show --name "$STORAGE_ACCOUNT" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        log_warning "Storage account $STORAGE_ACCOUNT already exists"
    else
        az storage account create \
            --name "$STORAGE_ACCOUNT" \
            --resource-group "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --sku Standard_LRS \
            --kind StorageV2 \
            --access-tier Hot \
            --allow-blob-public-access false \
            --tags \
                purpose=voice-processing \
                environment=demo
        
        log_success "Storage account created: $STORAGE_ACCOUNT"
    fi
    
    # Get storage connection string
    export STORAGE_CONNECTION
    STORAGE_CONNECTION=$(az storage account show-connection-string \
        --name "$STORAGE_ACCOUNT" \
        --resource-group "$RESOURCE_GROUP" \
        --query connectionString --output tsv)
    
    # Create blob containers
    log_info "Creating blob containers..."
    
    # Create container for audio input files
    az storage container create \
        --name "audio-input" \
        --connection-string "$STORAGE_CONNECTION" \
        --public-access off \
        --fail-on-exist false
    
    # Create container for transcript output
    az storage container create \
        --name "transcripts" \
        --connection-string "$STORAGE_CONNECTION" \
        --public-access off \
        --fail-on-exist false
    
    log_success "Blob containers created for audio processing"
}

###################################################################################
# Speech Service Setup
###################################################################################

create_speech_service() {
    log_info "Creating Azure AI Speech service: $SPEECH_SERVICE"
    
    # Check if speech service already exists
    if az cognitiveservices account show --name "$SPEECH_SERVICE" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        log_warning "Speech service $SPEECH_SERVICE already exists"
    else
        az cognitiveservices account create \
            --name "$SPEECH_SERVICE" \
            --resource-group "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --kind SpeechServices \
            --sku F0 \
            --tags \
                purpose=voice-transcription \
                environment=demo
        
        log_success "Speech service created: $SPEECH_SERVICE"
    fi
    
    # Get Speech service key and endpoint
    export SPEECH_KEY
    SPEECH_KEY=$(az cognitiveservices account keys list \
        --name "$SPEECH_SERVICE" \
        --resource-group "$RESOURCE_GROUP" \
        --query key1 --output tsv)
    
    export SPEECH_ENDPOINT
    SPEECH_ENDPOINT=$(az cognitiveservices account show \
        --name "$SPEECH_SERVICE" \
        --resource-group "$RESOURCE_GROUP" \
        --query properties.endpoint --output tsv)
    
    log_success "Speech service configuration retrieved"
}

###################################################################################
# Function App Setup
###################################################################################

create_function_app() {
    log_info "Creating Azure Function App: $FUNCTION_APP"
    
    # Check if function app already exists
    if az functionapp show --name "$FUNCTION_APP" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        log_warning "Function App $FUNCTION_APP already exists"
    else
        az functionapp create \
            --name "$FUNCTION_APP" \
            --resource-group "$RESOURCE_GROUP" \
            --storage-account "$STORAGE_ACCOUNT" \
            --consumption-plan-location "$LOCATION" \
            --runtime python \
            --runtime-version 3.11 \
            --functions-version 4 \
            --os-type linux \
            --tags \
                purpose=voice-processing \
                environment=demo
        
        log_success "Function App created: $FUNCTION_APP"
    fi
    
    # Configure Function App settings
    log_info "Configuring Function App settings..."
    
    az functionapp config appsettings set \
        --name "$FUNCTION_APP" \
        --resource-group "$RESOURCE_GROUP" \
        --settings \
            "SPEECH_KEY=$SPEECH_KEY" \
            "SPEECH_REGION=$LOCATION" \
            "SPEECH_ENDPOINT=$SPEECH_ENDPOINT" \
            "STORAGE_CONNECTION=$STORAGE_CONNECTION" \
            "FUNCTIONS_WORKER_RUNTIME=python" \
            "PYTHON_ISOLATE_WORKER_DEPENDENCIES=1"
    
    log_success "Function App configured with service connections"
}

###################################################################################
# Function Code Deployment
###################################################################################

deploy_function_code() {
    log_info "Deploying function code..."
    
    # Create temporary directory for function code
    local temp_dir
    temp_dir=$(mktemp -d)
    trap "rm -rf '$temp_dir'" RETURN
    
    cd "$temp_dir"
    
    # Initialize Functions project
    func init . --python --name voice-function
    
    # Create requirements.txt for Python dependencies
    cat > requirements.txt << 'EOF'
azure-functions>=1.18.0
azure-storage-blob>=12.19.0
azure-cognitiveservices-speech>=1.40.0
requests>=2.31.0
EOF
    
    # Create function with HTTP trigger
    func new --name transcribe --template "HTTP trigger" --authlevel "function"
    
    # Create function_app.py with voice processing logic
    cat > function_app.py << 'EOF'
import azure.functions as func
import azure.cognitiveservices.speech as speechsdk
import json
import os
import tempfile
import logging
from azure.storage.blob import BlobServiceClient

app = func.FunctionApp()

@app.route(route="transcribe", methods=["POST"])
def transcribe_audio(req: func.HttpRequest) -> func.HttpResponse:
    """
    Process uploaded audio file and return transcription
    """
    try:
        # Get configuration from app settings
        speech_key = os.environ.get("SPEECH_KEY")
        speech_region = os.environ.get("SPEECH_REGION")
        storage_connection = os.environ.get("STORAGE_CONNECTION")
        
        if not all([speech_key, speech_region, storage_connection]):
            return func.HttpResponse(
                json.dumps({"error": "Missing required configuration"}),
                status_code=500,
                mimetype="application/json"
            )
        
        # Parse request for audio file info
        try:
            req_body = req.get_json()
            if not req_body:
                return func.HttpResponse(
                    json.dumps({"error": "Request body required"}),
                    status_code=400,
                    mimetype="application/json"
                )
            
            audio_filename = req_body.get('filename')
            language = req_body.get('language', 'en-US')
            
        except Exception as e:
            return func.HttpResponse(
                json.dumps({"error": f"Invalid JSON: {str(e)}"}),
                status_code=400,
                mimetype="application/json"
            )
        
        if not audio_filename:
            return func.HttpResponse(
                json.dumps({"error": "filename required"}),
                status_code=400,
                mimetype="application/json"
            )
        
        # Configure Speech service
        speech_config = speechsdk.SpeechConfig(
            subscription=speech_key, 
            region=speech_region
        )
        speech_config.speech_recognition_language = language
        speech_config.enable_dictation()
        
        # Download audio file from blob storage
        blob_service = BlobServiceClient.from_connection_string(
            storage_connection
        )
        blob_client = blob_service.get_blob_client(
            container="audio-input", 
            blob=audio_filename
        )
        
        # Check if blob exists
        if not blob_client.exists():
            return func.HttpResponse(
                json.dumps({"error": f"Audio file not found: {audio_filename}"}),
                status_code=404,
                mimetype="application/json"
            )
        
        # Create temporary file for processing
        with tempfile.NamedTemporaryFile(delete=False, suffix=".wav") as temp_file:
            temp_file.write(blob_client.download_blob().readall())
            temp_file_path = temp_file.name
        
        try:
            # Process audio with Speech service
            audio_input = speechsdk.AudioConfig(filename=temp_file_path)
            recognizer = speechsdk.SpeechRecognizer(
                speech_config=speech_config, 
                audio_config=audio_input
            )
            
            # Perform speech recognition
            result = recognizer.recognize_once()
            
            # Process recognition result
            if result.reason == speechsdk.ResultReason.RecognizedSpeech:
                # Calculate confidence score
                confidence_score = "high" if len(result.text) > 10 else "medium"
                
                transcript = {
                    "filename": audio_filename,
                    "transcript": result.text,
                    "language": language,
                    "confidence": confidence_score,
                    "status": "success",
                    "duration_processed": "N/A"
                }
                
                # Save transcript to output container
                transcript_filename = f"{os.path.splitext(audio_filename)[0]}_transcript.json"
                transcript_blob = blob_service.get_blob_client(
                    container="transcripts",
                    blob=transcript_filename
                )
                transcript_blob.upload_blob(
                    json.dumps(transcript, indent=2),
                    overwrite=True
                )
                
                return func.HttpResponse(
                    json.dumps(transcript),
                    status_code=200,
                    mimetype="application/json"
                )
            
            elif result.reason == speechsdk.ResultReason.NoMatch:
                return func.HttpResponse(
                    json.dumps({
                        "error": "No speech detected in audio file",
                        "reason": "NoMatch"
                    }),
                    status_code=400,
                    mimetype="application/json"
                )
            
            else:
                return func.HttpResponse(
                    json.dumps({
                        "error": "Speech recognition failed",
                        "reason": str(result.reason),
                        "details": result.error_details if hasattr(result, 'error_details') else None
                    }),
                    status_code=400,
                    mimetype="application/json"
                )
                
        finally:
            # Clean up temporary file
            try:
                os.unlink(temp_file_path)
            except Exception as cleanup_error:
                logging.warning(f"Failed to cleanup temp file: {cleanup_error}")
            
    except Exception as e:
        logging.error(f"Transcription error: {str(e)}")
        return func.HttpResponse(
            json.dumps({"error": f"Processing failed: {str(e)}"}),
            status_code=500,
            mimetype="application/json"
        )
EOF
    
    # Deploy function to Azure
    log_info "Publishing function to Azure..."
    func azure functionapp publish "$FUNCTION_APP" --python
    
    log_success "Function deployed successfully"
}

###################################################################################
# Deployment Validation
###################################################################################

validate_deployment() {
    log_info "Validating deployment..."
    
    # Wait for Function App to be ready
    log_info "Waiting for Function App to be ready..."
    local max_attempts=30
    local attempt=1
    
    while [[ $attempt -le $max_attempts ]]; do
        if az functionapp show --name "$FUNCTION_APP" --resource-group "$RESOURCE_GROUP" --query "state" --output tsv | grep -q "Running"; then
            log_success "Function App is running"
            break
        fi
        
        if [[ $attempt -eq $max_attempts ]]; then
            log_error "Function App failed to start within expected time"
            return 1
        fi
        
        log_info "Attempt $attempt/$max_attempts - Function App not ready yet, waiting..."
        sleep 10
        ((attempt++))
    done
    
    # Get function URL and key for testing
    local function_url
    function_url=$(az functionapp function show \
        --name "$FUNCTION_APP" \
        --resource-group "$RESOURCE_GROUP" \
        --function-name transcribe \
        --query invokeUrlTemplate --output tsv 2>/dev/null || echo "")
    
    local function_key
    function_key=$(az functionapp keys list \
        --name "$FUNCTION_APP" \
        --resource-group "$RESOURCE_GROUP" \
        --query functionKeys.default --output tsv 2>/dev/null || echo "")
    
    if [[ -n "$function_url" && -n "$function_key" ]]; then
        log_success "Function endpoint ready: ${function_url}?code=${function_key:0:8}..."
    else
        log_warning "Could not retrieve function endpoint details"
    fi
    
    # Validate storage containers
    local containers
    containers=$(az storage container list \
        --connection-string "$STORAGE_CONNECTION" \
        --query "[].name" --output tsv)
    
    if echo "$containers" | grep -q "audio-input" && echo "$containers" | grep -q "transcripts"; then
        log_success "Storage containers validated"
    else
        log_error "Storage containers validation failed"
        return 1
    fi
    
    log_success "Deployment validation completed"
}

###################################################################################
# Main Deployment Function
###################################################################################

main() {
    log_info "Starting Azure Voice Recording Analysis deployment..."
    log_info "Timestamp: $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    
    # Check if deployment already exists
    if [[ -f "$DEPLOYMENT_STATE_FILE" ]]; then
        log_warning "Existing deployment found. Loading state..."
        source "$DEPLOYMENT_STATE_FILE"
        log_info "Loaded existing deployment: $RESOURCE_GROUP"
    fi
    
    check_prerequisites
    setup_configuration
    create_resource_group
    create_storage_account
    create_speech_service
    create_function_app
    deploy_function_code
    validate_deployment
    
    log_success "🎉 Deployment completed successfully!"
    log_info ""
    log_info "📋 Deployment Summary:"
    log_info "  Resource Group: $RESOURCE_GROUP"
    log_info "  Location: $LOCATION"
    log_info "  Storage Account: $STORAGE_ACCOUNT"
    log_info "  Speech Service: $SPEECH_SERVICE"
    log_info "  Function App: $FUNCTION_APP"
    log_info ""
    log_info "🔧 Next Steps:"
    log_info "  1. Upload audio files to the 'audio-input' container"
    log_info "  2. Call the transcribe function with audio filename"
    log_info "  3. Retrieve transcripts from the 'transcripts' container"
    log_info ""
    log_info "📁 Deployment state saved to: $DEPLOYMENT_STATE_FILE"
    log_info "📝 Full deployment log available at: $LOG_FILE"
    log_info ""
    log_warning "⚠️  Remember to run destroy.sh when done to avoid ongoing charges"
}

# Run main function
main "$@"