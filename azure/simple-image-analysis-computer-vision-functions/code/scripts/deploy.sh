#!/bin/bash

# Azure Simple Image Analysis Deployment Script
# Recipe: Simple Image Analysis with Computer Vision and Functions
# Description: Deploy Azure Functions with Computer Vision for image analysis

set -euo pipefail  # Exit on any error, undefined variable, or pipe failure

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

# Cleanup function for script termination
cleanup() {
    local exit_code=$?
    if [ $exit_code -ne 0 ]; then
        log_error "Deployment failed with exit code $exit_code"
        log_info "Run './destroy.sh' to clean up any partially created resources"
    fi
    exit $exit_code
}

# Set trap for cleanup
trap cleanup EXIT

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check Azure CLI login status
check_azure_auth() {
    log_info "Checking Azure CLI authentication..."
    if ! az account show >/dev/null 2>&1; then
        log_error "Not logged into Azure CLI. Please run 'az login' first."
        exit 1
    fi
    
    local subscription_name=$(az account show --query name --output tsv 2>/dev/null)
    local subscription_id=$(az account show --query id --output tsv 2>/dev/null)
    log_success "Authenticated to Azure subscription: $subscription_name ($subscription_id)"
}

# Function to validate required permissions
check_permissions() {
    log_info "Validating Azure permissions..."
    
    # Check if user can create resource groups
    local test_location="eastus"
    if ! az provider list --query "[?namespace=='Microsoft.Resources']" --output tsv >/dev/null 2>&1; then
        log_error "Insufficient permissions to access Azure Resource Manager"
        exit 1
    fi
    
    # Check Cognitive Services provider registration
    local cv_provider_status=$(az provider show --namespace Microsoft.CognitiveServices --query registrationState --output tsv 2>/dev/null || echo "NotRegistered")
    if [ "$cv_provider_status" != "Registered" ]; then
        log_warning "Microsoft.CognitiveServices provider not registered. Attempting to register..."
        if ! az provider register --namespace Microsoft.CognitiveServices --wait; then
            log_error "Failed to register Microsoft.CognitiveServices provider"
            exit 1
        fi
        log_success "Microsoft.CognitiveServices provider registered successfully"
    fi
    
    # Check Web/Sites provider registration for Function Apps
    local web_provider_status=$(az provider show --namespace Microsoft.Web --query registrationState --output tsv 2>/dev/null || echo "NotRegistered")
    if [ "$web_provider_status" != "Registered" ]; then
        log_warning "Microsoft.Web provider not registered. Attempting to register..."
        if ! az provider register --namespace Microsoft.Web --wait; then
            log_error "Failed to register Microsoft.Web provider"
            exit 1
        fi
        log_success "Microsoft.Web provider registered successfully"
    fi
    
    log_success "Required permissions validated"
}

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check Azure CLI
    if ! command_exists az; then
        log_error "Azure CLI is not installed. Please install it from: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
        exit 1
    fi
    
    local az_version=$(az version --query '"azure-cli"' --output tsv 2>/dev/null)
    log_success "Azure CLI version $az_version installed"
    
    # Check Azure Functions Core Tools
    if ! command_exists func; then
        log_error "Azure Functions Core Tools not installed. Please install from: https://docs.microsoft.com/en-us/azure/azure-functions/functions-run-local"
        exit 1
    fi
    
    local func_version=$(func --version 2>/dev/null)
    log_success "Azure Functions Core Tools version $func_version installed"
    
    # Check Python (required for Functions)
    if ! command_exists python3; then
        log_error "Python 3 is not installed. Please install Python 3.8 or later"
        exit 1
    fi
    
    local python_version=$(python3 --version 2>/dev/null)
    log_success "$python_version installed"
    
    # Check pip
    if ! command_exists pip3; then
        log_error "pip3 is not installed. Please install pip for Python 3"
        exit 1
    fi
    
    # Check required tools
    local required_tools=("openssl" "curl")
    for tool in "${required_tools[@]}"; do
        if ! command_exists "$tool"; then
            log_error "$tool is not installed. Please install it before proceeding"
            exit 1
        fi
    done
    
    log_success "All prerequisites validated"
}

# Function to set up environment variables
setup_environment() {
    log_info "Setting up environment variables..."
    
    # Set default values
    export LOCATION="${LOCATION:-eastus}"
    export SUBSCRIPTION_ID=$(az account show --query id --output tsv)
    
    # Generate unique suffix for resource names
    if [ -z "${RANDOM_SUFFIX:-}" ]; then
        export RANDOM_SUFFIX=$(openssl rand -hex 3)
        log_info "Generated random suffix: $RANDOM_SUFFIX"
    fi
    
    # Set resource names with unique suffix
    export RESOURCE_GROUP="${RESOURCE_GROUP:-rg-image-analysis-${RANDOM_SUFFIX}}"
    export FUNCTION_APP_NAME="${FUNCTION_APP_NAME:-func-imageanalysis-${RANDOM_SUFFIX}}"
    export STORAGE_ACCOUNT_NAME="${STORAGE_ACCOUNT_NAME:-sa${RANDOM_SUFFIX}imageanalysis}"
    export COMPUTER_VISION_NAME="${COMPUTER_VISION_NAME:-cv-imageanalysis-${RANDOM_SUFFIX}}"
    
    # Validate storage account name length (3-24 characters, lowercase alphanumeric)
    if [ ${#STORAGE_ACCOUNT_NAME} -gt 24 ]; then
        log_error "Storage account name too long: $STORAGE_ACCOUNT_NAME (max 24 characters)"
        exit 1
    fi
    
    log_success "Environment variables configured:"
    log_info "  Resource Group: $RESOURCE_GROUP"
    log_info "  Location: $LOCATION"
    log_info "  Function App: $FUNCTION_APP_NAME"
    log_info "  Storage Account: $STORAGE_ACCOUNT_NAME"
    log_info "  Computer Vision: $COMPUTER_VISION_NAME"
    
    # Save environment for cleanup script
    cat > .env.deploy << EOF
RESOURCE_GROUP=$RESOURCE_GROUP
LOCATION=$LOCATION
FUNCTION_APP_NAME=$FUNCTION_APP_NAME
STORAGE_ACCOUNT_NAME=$STORAGE_ACCOUNT_NAME
COMPUTER_VISION_NAME=$COMPUTER_VISION_NAME
SUBSCRIPTION_ID=$SUBSCRIPTION_ID
RANDOM_SUFFIX=$RANDOM_SUFFIX
EOF
    log_info "Environment saved to .env.deploy for cleanup script"
}

# Function to create resource group
create_resource_group() {
    log_info "Creating resource group: $RESOURCE_GROUP"
    
    if az group show --name "$RESOURCE_GROUP" >/dev/null 2>&1; then
        log_warning "Resource group $RESOURCE_GROUP already exists, skipping creation"
        return 0
    fi
    
    if az group create \
        --name "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --tags purpose=recipe environment=demo recipe=image-analysis >/dev/null; then
        log_success "Resource group created: $RESOURCE_GROUP"
    else
        log_error "Failed to create resource group: $RESOURCE_GROUP"
        exit 1
    fi
}

# Function to create Computer Vision service
create_computer_vision() {
    log_info "Creating Computer Vision service: $COMPUTER_VISION_NAME"
    
    if az cognitiveservices account show \
        --name "$COMPUTER_VISION_NAME" \
        --resource-group "$RESOURCE_GROUP" >/dev/null 2>&1; then
        log_warning "Computer Vision service $COMPUTER_VISION_NAME already exists, skipping creation"
    else
        if az cognitiveservices account create \
            --name "$COMPUTER_VISION_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --kind ComputerVision \
            --sku F0 \
            --location "$LOCATION" \
            --custom-domain "$COMPUTER_VISION_NAME" \
            --tags purpose=recipe environment=demo >/dev/null; then
            log_success "Computer Vision service created: $COMPUTER_VISION_NAME"
        else
            log_error "Failed to create Computer Vision service: $COMPUTER_VISION_NAME"
            log_info "Note: F0 (free) tier allows only one instance per subscription"
            exit 1
        fi
    fi
    
    # Get Computer Vision endpoint and key
    log_info "Retrieving Computer Vision credentials..."
    CV_ENDPOINT=$(az cognitiveservices account show \
        --name "$COMPUTER_VISION_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --query properties.endpoint \
        --output tsv)
    
    CV_KEY=$(az cognitiveservices account keys list \
        --name "$COMPUTER_VISION_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --query key1 \
        --output tsv)
    
    if [ -z "$CV_ENDPOINT" ] || [ -z "$CV_KEY" ]; then
        log_error "Failed to retrieve Computer Vision credentials"
        exit 1
    fi
    
    export CV_ENDPOINT
    export CV_KEY
    log_success "Computer Vision credentials retrieved"
}

# Function to create storage account
create_storage_account() {
    log_info "Creating storage account: $STORAGE_ACCOUNT_NAME"
    
    if az storage account show \
        --name "$STORAGE_ACCOUNT_NAME" \
        --resource-group "$RESOURCE_GROUP" >/dev/null 2>&1; then
        log_warning "Storage account $STORAGE_ACCOUNT_NAME already exists, skipping creation"
        return 0
    fi
    
    if az storage account create \
        --name "$STORAGE_ACCOUNT_NAME" \
        --location "$LOCATION" \
        --resource-group "$RESOURCE_GROUP" \
        --sku Standard_LRS \
        --kind StorageV2 \
        --tags purpose=recipe environment=demo >/dev/null; then
        log_success "Storage account created: $STORAGE_ACCOUNT_NAME"
    else
        log_error "Failed to create storage account: $STORAGE_ACCOUNT_NAME"
        exit 1
    fi
}

# Function to create Function App
create_function_app() {
    log_info "Creating Function App: $FUNCTION_APP_NAME"
    
    if az functionapp show \
        --name "$FUNCTION_APP_NAME" \
        --resource-group "$RESOURCE_GROUP" >/dev/null 2>&1; then
        log_warning "Function App $FUNCTION_APP_NAME already exists, skipping creation"
    else
        if az functionapp create \
            --resource-group "$RESOURCE_GROUP" \
            --consumption-plan-location "$LOCATION" \
            --runtime python \
            --runtime-version 3.11 \
            --functions-version 4 \
            --name "$FUNCTION_APP_NAME" \
            --storage-account "$STORAGE_ACCOUNT_NAME" \
            --os-type linux \
            --tags purpose=recipe environment=demo >/dev/null; then
            log_success "Function App created: $FUNCTION_APP_NAME"
        else
            log_error "Failed to create Function App: $FUNCTION_APP_NAME"
            exit 1
        fi
    fi
    
    # Configure Function App settings
    log_info "Configuring Function App settings..."
    if az functionapp config appsettings set \
        --name "$FUNCTION_APP_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --settings "COMPUTER_VISION_ENDPOINT=$CV_ENDPOINT" \
                   "COMPUTER_VISION_KEY=$CV_KEY" >/dev/null; then
        log_success "Function App settings configured"
    else
        log_error "Failed to configure Function App settings"
        exit 1
    fi
}

# Function to create local function project
create_function_project() {
    log_info "Creating local Function project..."
    
    local project_dir="image-analysis-function"
    
    # Clean up existing project directory if it exists
    if [ -d "$project_dir" ]; then
        log_warning "Removing existing project directory: $project_dir"
        rm -rf "$project_dir"
    fi
    
    # Create and initialize Function project
    mkdir "$project_dir"
    cd "$project_dir"
    
    if func init . --worker-runtime python --model V2 >/dev/null 2>&1; then
        log_success "Function project initialized"
    else
        log_error "Failed to initialize Function project"
        cd ..
        exit 1
    fi
    
    # Create requirements.txt
    cat > requirements.txt << 'EOF'
azure-functions>=1.20.0
azure-ai-vision-imageanalysis>=1.0.0
requests>=2.31.0
Pillow>=10.0.0
EOF
    log_success "Requirements.txt created"
    
    # Create function_app.py with comprehensive image analysis logic
    cat > function_app.py << 'EOF'
import azure.functions as func
import logging
import json
import os
import base64
from azure.ai.vision.imageanalysis import ImageAnalysisClient
from azure.ai.vision.imageanalysis.models import VisualFeatures
from azure.core.credentials import AzureKeyCredential

# Initialize Function App
app = func.FunctionApp(http_auth_level=func.AuthLevel.ANONYMOUS)

@app.route(route="analyze", methods=["POST"])
def analyze_image(req: func.HttpRequest) -> func.HttpResponse:
    """
    Analyze uploaded image using Azure Computer Vision
    Accepts: multipart/form-data with 'image' field or JSON with base64 image
    Returns: JSON with analysis results
    """
    logging.info('Image analysis request received')
    
    try:
        # Get Computer Vision credentials from environment
        endpoint = os.environ["COMPUTER_VISION_ENDPOINT"]
        key = os.environ["COMPUTER_VISION_KEY"]
        
        # Initialize Computer Vision client
        client = ImageAnalysisClient(
            endpoint=endpoint,
            credential=AzureKeyCredential(key)
        )
        
        # Parse uploaded image from request
        image_data = None
        content_type = req.headers.get('content-type', '')
        
        if 'multipart/form-data' in content_type:
            # Handle multipart form data
            files = req.files
            if 'image' in files:
                image_file = files['image']
                image_data = image_file.read()
            else:
                return func.HttpResponse(
                    json.dumps({"error": "No 'image' field found in form data"}),
                    status_code=400,
                    mimetype="application/json"
                )
        elif 'application/json' in content_type:
            # Handle JSON with base64 encoded image
            try:
                req_body = req.get_json()
                if 'image_base64' in req_body:
                    image_data = base64.b64decode(req_body['image_base64'])
                else:
                    return func.HttpResponse(
                        json.dumps({"error": "No 'image_base64' field found"}),
                        status_code=400,
                        mimetype="application/json"
                    )
            except ValueError:
                return func.HttpResponse(
                    json.dumps({"error": "Invalid JSON in request body"}),
                    status_code=400,
                    mimetype="application/json"
                )
        else:
            return func.HttpResponse(
                json.dumps({"error": "Unsupported content type. Use multipart/form-data or application/json"}),
                status_code=400,
                mimetype="application/json"
            )
        
        if not image_data:
            return func.HttpResponse(
                json.dumps({"error": "No image data received"}),
                status_code=400,
                mimetype="application/json"
            )
        
        # Analyze image with Computer Vision
        # Using multiple visual features for comprehensive analysis
        result = client.analyze(
            image_data=image_data,
            visual_features=[
                VisualFeatures.CAPTION,     # Generate image description
                VisualFeatures.READ,        # Extract text (OCR)
                VisualFeatures.TAGS,        # Identify objects and concepts
                VisualFeatures.OBJECTS,     # Detect and locate objects
                VisualFeatures.PEOPLE       # Detect people in image
            ]
        )
        
        # Structure analysis results
        analysis_results = {
            "success": True,
            "analysis": {}
        }
        
        # Extract caption/description
        if result.caption:
            analysis_results["analysis"]["description"] = {
                "text": result.caption.text,
                "confidence": result.caption.confidence
            }
        
        # Extract detected text (OCR)
        if result.read:
            extracted_text = []
            for block in result.read.blocks or []:
                for line in block.lines:
                    extracted_text.append({
                        "text": line.text,
                        "bounding_box": [{"x": point.x, "y": point.y} 
                                       for point in line.bounding_polygon]
                    })
            analysis_results["analysis"]["text"] = extracted_text
        
        # Extract tags
        if result.tags:
            tags = [{"name": tag.name, "confidence": tag.confidence} 
                   for tag in result.tags.list]
            analysis_results["analysis"]["tags"] = tags
        
        # Extract detected objects
        if result.objects:
            objects = []
            for obj in result.objects.list:
                objects.append({
                    "name": obj.tags[0].name if obj.tags else "unknown",
                    "confidence": obj.tags[0].confidence if obj.tags else 0,
                    "bounding_box": {
                        "x": obj.bounding_box.x,
                        "y": obj.bounding_box.y,
                        "width": obj.bounding_box.width,
                        "height": obj.bounding_box.height
                    }
                })
            analysis_results["analysis"]["objects"] = objects
        
        # Extract detected people
        if result.people:
            people = []
            for person in result.people.list:
                people.append({
                    "confidence": person.confidence,
                    "bounding_box": {
                        "x": person.bounding_box.x,
                        "y": person.bounding_box.y,
                        "width": person.bounding_box.width,
                        "height": person.bounding_box.height
                    }
                })
            analysis_results["analysis"]["people"] = people
        
        logging.info('Image analysis completed successfully')
        
        return func.HttpResponse(
            json.dumps(analysis_results, indent=2),
            status_code=200,
            mimetype="application/json"
        )
        
    except Exception as e:
        logging.error(f'Error analyzing image: {str(e)}')
        return func.HttpResponse(
            json.dumps({
                "success": False,
                "error": f"Analysis failed: {str(e)}"
            }),
            status_code=500,
            mimetype="application/json"
        )

@app.route(route="health", methods=["GET"])
def health_check(req: func.HttpRequest) -> func.HttpResponse:
    """Health check endpoint for monitoring"""
    return func.HttpResponse(
        json.dumps({"status": "healthy", "service": "image-analysis"}),
        status_code=200,
        mimetype="application/json"
    )
EOF
    log_success "Function code created"
    
    cd ..
}

# Function to deploy function to Azure
deploy_function() {
    log_info "Deploying function to Azure..."
    
    cd image-analysis-function
    
    if func azure functionapp publish "$FUNCTION_APP_NAME" >/dev/null 2>&1; then
        log_success "Function deployed successfully"
    else
        log_error "Failed to deploy function"
        cd ..
        exit 1
    fi
    
    # Get function URL
    FUNCTION_URL=$(az functionapp function show \
        --resource-group "$RESOURCE_GROUP" \
        --name "$FUNCTION_APP_NAME" \
        --function-name analyze \
        --query invokeUrlTemplate \
        --output tsv 2>/dev/null)
    
    if [ -n "$FUNCTION_URL" ]; then
        export FUNCTION_URL
        log_success "Function URL: $FUNCTION_URL"
        
        # Save function URL to environment file
        echo "FUNCTION_URL=$FUNCTION_URL" >> ../.env.deploy
    else
        log_warning "Could not retrieve function URL"
    fi
    
    cd ..
}

# Function to run basic validation
run_validation() {
    log_info "Running deployment validation..."
    
    # Check if resource group exists
    if ! az group show --name "$RESOURCE_GROUP" >/dev/null 2>&1; then
        log_error "Resource group validation failed"
        return 1
    fi
    
    # Check if Computer Vision service is running
    local cv_state=$(az cognitiveservices account show \
        --name "$COMPUTER_VISION_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --query properties.provisioningState \
        --output tsv 2>/dev/null)
    
    if [ "$cv_state" != "Succeeded" ]; then
        log_error "Computer Vision service validation failed (state: $cv_state)"
        return 1
    fi
    
    # Check if Function App is running
    local func_state=$(az functionapp show \
        --name "$FUNCTION_APP_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --query state \
        --output tsv 2>/dev/null)
    
    if [ "$func_state" != "Running" ]; then
        log_error "Function App validation failed (state: $func_state)"
        return 1
    fi
    
    # Test health endpoint if URL is available
    if [ -n "${FUNCTION_URL:-}" ]; then
        local health_url="${FUNCTION_URL/analyze/health}"
        log_info "Testing health endpoint..."
        
        if curl -s "$health_url" | grep -q "healthy" >/dev/null 2>&1; then
            log_success "Health endpoint responding correctly"
        else
            log_warning "Health endpoint test failed, but this may be due to cold start delay"
        fi
    fi
    
    log_success "Deployment validation completed"
}

# Function to display deployment summary
display_summary() {
    log_success "=== DEPLOYMENT COMPLETED SUCCESSFULLY ==="
    echo
    log_info "Resource Summary:"
    log_info "  Resource Group: $RESOURCE_GROUP"
    log_info "  Computer Vision: $COMPUTER_VISION_NAME"
    log_info "  Storage Account: $STORAGE_ACCOUNT_NAME"
    log_info "  Function App: $FUNCTION_APP_NAME"
    
    if [ -n "${FUNCTION_URL:-}" ]; then
        echo
        log_info "Function Endpoints:"
        log_info "  Analyze: $FUNCTION_URL"
        log_info "  Health: ${FUNCTION_URL/analyze/health}"
    fi
    
    echo
    log_info "Next Steps:"
    log_info "1. Test the health endpoint: curl '${FUNCTION_URL/analyze/health}'"
    log_info "2. Test image analysis with sample image"
    log_info "3. Review function logs in Azure portal"
    log_info "4. Run './destroy.sh' when finished to clean up resources"
    
    echo
    log_info "Estimated monthly cost: \$1-5 (Functions Consumption + Computer Vision Free tier)"
    log_warning "Remember to clean up resources to avoid ongoing charges"
}

# Main deployment function
main() {
    log_info "Starting Azure Image Analysis Function deployment..."
    echo
    
    # Run all deployment steps
    check_prerequisites
    check_azure_auth
    check_permissions
    setup_environment
    create_resource_group
    create_computer_vision
    create_storage_account
    create_function_app
    create_function_project
    deploy_function
    run_validation
    
    echo
    display_summary
    
    log_success "Deployment completed successfully!"
}

# Run main function if script is executed directly
if [ "${BASH_SOURCE[0]}" == "${0}" ]; then
    main "$@"
fi