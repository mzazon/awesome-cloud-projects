#!/bin/bash

#########################################################################
# Simple Image Resizing with Azure Functions and Blob Storage
# Deployment Script
#
# This script deploys the complete image resizing solution including:
# - Resource Group
# - Storage Account with blob containers
# - Function App with runtime configuration
# - Function deployment with dependencies
#
# Requirements:
# - Azure CLI 2.0.80+
# - Node.js 20+
# - Azure Functions Core Tools v4
# - Contributor permissions in Azure subscription
#########################################################################

set -euo pipefail  # Exit on error, undefined vars, pipe failures

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1" >&2
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" >&2
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" >&2
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

# Configuration with defaults
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_NAME="${PROJECT_NAME:-image-resize}"
readonly LOCATION="${LOCATION:-eastus}"
readonly RANDOM_SUFFIX="${RANDOM_SUFFIX:-$(openssl rand -hex 3)}"

# Resource names
readonly RESOURCE_GROUP="${PROJECT_NAME}-rg-${RANDOM_SUFFIX}"
readonly STORAGE_ACCOUNT="${PROJECT_NAME}st${RANDOM_SUFFIX}"
readonly FUNCTION_APP="${PROJECT_NAME}-func-${RANDOM_SUFFIX}"

# Image processing settings
readonly THUMBNAIL_WIDTH="${THUMBNAIL_WIDTH:-150}"
readonly THUMBNAIL_HEIGHT="${THUMBNAIL_HEIGHT:-150}"
readonly MEDIUM_WIDTH="${MEDIUM_WIDTH:-800}"
readonly MEDIUM_HEIGHT="${MEDIUM_HEIGHT:-600}"

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check Azure CLI
    if ! command -v az &> /dev/null; then
        log_error "Azure CLI is not installed. Please install from: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
        exit 1
    fi
    
    # Check Azure CLI version
    local az_version
    az_version=$(az version --query '."azure-cli"' -o tsv)
    if [[ "$(printf '%s\n' "2.0.80" "$az_version" | sort -V | head -n1)" != "2.0.80" ]]; then
        log_error "Azure CLI version 2.0.80+ required. Current version: $az_version"
        exit 1
    fi
    
    # Check Azure login
    if ! az account show &> /dev/null; then
        log_error "Not logged into Azure. Run 'az login' first."
        exit 1
    fi
    
    # Check Node.js
    if ! command -v node &> /dev/null; then
        log_error "Node.js is not installed. Please install Node.js 20+ from: https://nodejs.org/"
        exit 1
    fi
    
    # Check Node.js version
    local node_version
    node_version=$(node --version | sed 's/v//')
    if [[ "$(printf '%s\n' "20.0.0" "$node_version" | sort -V | head -n1)" != "20.0.0" ]]; then
        log_error "Node.js version 20+ required. Current version: $node_version"
        exit 1
    fi
    
    # Check Azure Functions Core Tools
    if ! command -v func &> /dev/null; then
        log_error "Azure Functions Core Tools not installed. Install with: npm install -g azure-functions-core-tools@4 --unsafe-perm true"
        exit 1
    fi
    
    # Check Functions Core Tools version
    local func_version
    func_version=$(func --version)
    if [[ ! "$func_version" =~ ^4\. ]]; then
        log_error "Azure Functions Core Tools v4 required. Current version: $func_version"
        exit 1
    fi
    
    log_success "All prerequisites met"
}

# Function to validate Azure subscription and permissions
validate_azure_environment() {
    log_info "Validating Azure environment..."
    
    # Get subscription details
    local subscription_id
    local subscription_name
    subscription_id=$(az account show --query id -o tsv)
    subscription_name=$(az account show --query name -o tsv)
    
    log_info "Using subscription: $subscription_name ($subscription_id)"
    
    # Check if location is valid
    if ! az account list-locations --query "[?name=='$LOCATION']" -o tsv | grep -q "$LOCATION"; then
        log_error "Invalid location: $LOCATION"
        log_info "Available locations: $(az account list-locations --query '[].name' -o tsv | tr '\n' ', ')"
        exit 1
    fi
    
    # Check resource group existence (for idempotency)
    if az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        log_warning "Resource group $RESOURCE_GROUP already exists. Deployment will update existing resources."
    fi
    
    log_success "Azure environment validated"
}

# Function to create resource group
create_resource_group() {
    log_info "Creating resource group: $RESOURCE_GROUP"
    
    if az group create \
        --name "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --tags purpose=recipe environment=demo component=image-processing \
        --output none; then
        log_success "Resource group created: $RESOURCE_GROUP"
    else
        log_error "Failed to create resource group"
        exit 1
    fi
}

# Function to create storage account
create_storage_account() {
    log_info "Creating storage account: $STORAGE_ACCOUNT"
    
    # Check if storage account name is available
    if ! az storage account check-name --name "$STORAGE_ACCOUNT" --query nameAvailable -o tsv | grep -q "true"; then
        log_error "Storage account name $STORAGE_ACCOUNT is not available"
        exit 1
    fi
    
    if az storage account create \
        --name "$STORAGE_ACCOUNT" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --sku Standard_LRS \
        --kind StorageV2 \
        --access-tier Hot \
        --allow-blob-public-access true \
        --output none; then
        log_success "Storage account created: $STORAGE_ACCOUNT"
    else
        log_error "Failed to create storage account"
        exit 1
    fi
    
    # Wait for storage account to be ready
    log_info "Waiting for storage account to be ready..."
    local max_attempts=30
    local attempt=1
    
    while [[ $attempt -le $max_attempts ]]; do
        if az storage account show --name "$STORAGE_ACCOUNT" --resource-group "$RESOURCE_GROUP" --query provisioningState -o tsv | grep -q "Succeeded"; then
            break
        fi
        sleep 5
        ((attempt++))
    done
    
    if [[ $attempt -gt $max_attempts ]]; then
        log_error "Storage account failed to provision within expected time"
        exit 1
    fi
}

# Function to create blob containers
create_blob_containers() {
    log_info "Creating blob containers..."
    
    # Get storage connection string
    local storage_connection
    storage_connection=$(az storage account show-connection-string \
        --name "$STORAGE_ACCOUNT" \
        --resource-group "$RESOURCE_GROUP" \
        --query connectionString \
        --output tsv)
    
    # Create containers with public blob access
    local containers=("original-images" "thumbnails" "medium-images")
    
    for container in "${containers[@]}"; do
        log_info "Creating container: $container"
        
        if az storage container create \
            --name "$container" \
            --connection-string "$storage_connection" \
            --public-access blob \
            --output none; then
            log_success "Container created: $container"
        else
            log_error "Failed to create container: $container"
            exit 1
        fi
    done
}

# Function to create function app
create_function_app() {
    log_info "Creating Function App: $FUNCTION_APP"
    
    if az functionapp create \
        --name "$FUNCTION_APP" \
        --resource-group "$RESOURCE_GROUP" \
        --storage-account "$STORAGE_ACCOUNT" \
        --consumption-plan-location "$LOCATION" \
        --runtime node \
        --runtime-version 20 \
        --functions-version 4 \
        --os-type Linux \
        --output none; then
        log_success "Function App created: $FUNCTION_APP"
    else
        log_error "Failed to create Function App"
        exit 1
    fi
    
    # Wait for function app to be ready
    log_info "Waiting for Function App to be ready..."
    local max_attempts=30
    local attempt=1
    
    while [[ $attempt -le $max_attempts ]]; do
        if az functionapp show --name "$FUNCTION_APP" --resource-group "$RESOURCE_GROUP" --query state -o tsv | grep -q "Running"; then
            break
        fi
        sleep 10
        ((attempt++))
    done
    
    if [[ $attempt -gt $max_attempts ]]; then
        log_error "Function App failed to start within expected time"
        exit 1
    fi
}

# Function to configure function app settings
configure_function_settings() {
    log_info "Configuring Function App settings..."
    
    # Get storage connection string
    local storage_connection
    storage_connection=$(az storage account show-connection-string \
        --name "$STORAGE_ACCOUNT" \
        --resource-group "$RESOURCE_GROUP" \
        --query connectionString \
        --output tsv)
    
    # Configure storage connections
    if az functionapp config appsettings set \
        --name "$FUNCTION_APP" \
        --resource-group "$RESOURCE_GROUP" \
        --settings \
            "AzureWebJobsStorage=$storage_connection" \
            "WEBSITE_CONTENTAZUREFILECONNECTIONSTRING=$storage_connection" \
            "StorageConnection=$storage_connection" \
        --output none; then
        log_success "Storage connection configured"
    else
        log_error "Failed to configure storage connection"
        exit 1
    fi
    
    # Configure image processing settings
    if az functionapp config appsettings set \
        --name "$FUNCTION_APP" \
        --resource-group "$RESOURCE_GROUP" \
        --settings \
            "THUMBNAIL_WIDTH=$THUMBNAIL_WIDTH" \
            "THUMBNAIL_HEIGHT=$THUMBNAIL_HEIGHT" \
            "MEDIUM_WIDTH=$MEDIUM_WIDTH" \
            "MEDIUM_HEIGHT=$MEDIUM_HEIGHT" \
        --output none; then
        log_success "Image processing settings configured"
    else
        log_error "Failed to configure image processing settings"
        exit 1
    fi
}

# Function to create and deploy function code
deploy_function_code() {
    log_info "Creating and deploying function code..."
    
    # Create temporary directory for function project
    local temp_dir
    temp_dir=$(mktemp -d)
    
    cleanup_temp_dir() {
        rm -rf "$temp_dir"
    }
    trap cleanup_temp_dir EXIT
    
    cd "$temp_dir"
    
    # Initialize function project
    log_info "Initializing function project..."
    if ! func init . --javascript --model V4 --output none 2>/dev/null; then
        log_error "Failed to initialize function project"
        exit 1
    fi
    
    # Create blob trigger function
    log_info "Creating blob trigger function..."
    if ! func new --name ImageResize --template "Azure Blob Storage trigger" --output none 2>/dev/null; then
        log_error "Failed to create blob trigger function"
        exit 1
    fi
    
    # Install dependencies
    log_info "Installing function dependencies..."
    cat > package.json << 'EOF'
{
  "name": "image-resize-function",
  "version": "1.0.0",
  "description": "Azure Function for automatic image resizing",
  "main": "src/functions/ImageResize.js",
  "scripts": {
    "start": "func start",
    "test": "echo \"No tests yet\""
  },
  "dependencies": {
    "@azure/functions": "^4.0.0",
    "@azure/storage-blob": "^12.17.0",
    "sharp": "^0.33.2"
  },
  "devDependencies": {},
  "engines": {
    "node": ">=20.0.0"
  }
}
EOF
    
    if ! npm install --silent; then
        log_error "Failed to install npm dependencies"
        exit 1
    fi
    
    # Create the image resizing function code
    log_info "Creating function implementation..."
    mkdir -p src/functions
    cat > src/functions/ImageResize.js << 'EOF'
const { app } = require('@azure/functions');
const sharp = require('sharp');
const { BlobServiceClient } = require('@azure/storage-blob');

app.storageBlob('ImageResize', {
    path: 'original-images/{name}',
    connection: 'StorageConnection',
    source: 'EventGrid',
    handler: async (blob, context) => {
        try {
            context.log(`Processing image: ${context.triggerMetadata.name}`);
            
            // Initialize blob service client
            const blobServiceClient = BlobServiceClient.fromConnectionString(
                process.env.StorageConnection
            );
            
            // Get image dimensions from environment
            const thumbnailWidth = parseInt(process.env.THUMBNAIL_WIDTH) || 150;
            const thumbnailHeight = parseInt(process.env.THUMBNAIL_HEIGHT) || 150;
            const mediumWidth = parseInt(process.env.MEDIUM_WIDTH) || 800;
            const mediumHeight = parseInt(process.env.MEDIUM_HEIGHT) || 600;
            
            // Extract file information
            const fileName = context.triggerMetadata.name;
            const fileExtension = fileName.split('.').pop().toLowerCase();
            const baseName = fileName.replace(/\.[^/.]+$/, "");
            
            // Validate supported image formats
            const supportedFormats = ['jpg', 'jpeg', 'png', 'webp'];
            if (!supportedFormats.includes(fileExtension)) {
                context.log(`Unsupported format: ${fileExtension}`);
                return;
            }
            
            // Process thumbnail image
            const thumbnailBuffer = await sharp(blob)
                .resize(thumbnailWidth, thumbnailHeight, {
                    fit: 'cover',
                    position: 'center'
                })
                .jpeg({ quality: 85, progressive: true })
                .toBuffer();
            
            // Upload thumbnail
            const thumbnailContainer = blobServiceClient.getContainerClient('thumbnails');
            const thumbnailBlob = thumbnailContainer.getBlockBlobClient(`${baseName}-thumb.jpg`);
            await thumbnailBlob.upload(thumbnailBuffer, thumbnailBuffer.length, {
                blobHTTPHeaders: { blobContentType: 'image/jpeg' }
            });
            
            // Process medium-sized image
            const mediumBuffer = await sharp(blob)
                .resize(mediumWidth, mediumHeight, {
                    fit: 'inside',
                    withoutEnlargement: true
                })
                .jpeg({ quality: 90, progressive: true })
                .toBuffer();
            
            // Upload medium image
            const mediumContainer = blobServiceClient.getContainerClient('medium-images');
            const mediumBlob = mediumContainer.getBlockBlobClient(`${baseName}-medium.jpg`);
            await mediumBlob.upload(mediumBuffer, mediumBuffer.length, {
                blobHTTPHeaders: { blobContentType: 'image/jpeg' }
            });
            
            context.log(`Successfully processed: ${fileName}`);
            context.log(`Created thumbnail: ${baseName}-thumb.jpg`);
            context.log(`Created medium: ${baseName}-medium.jpg`);
            
        } catch (error) {
            context.log.error(`Error processing image: ${error.message}`);
            throw error;
        }
    }
});
EOF
    
    # Deploy function to Azure
    log_info "Deploying function to Azure..."
    if func azure functionapp publish "$FUNCTION_APP" --output none; then
        log_success "Function deployed successfully"
    else
        log_error "Failed to deploy function"
        exit 1
    fi
    
    # Return to original directory
    cd - > /dev/null
}

# Function to verify deployment
verify_deployment() {
    log_info "Verifying deployment..."
    
    # Check Function App status
    local func_state
    func_state=$(az functionapp show \
        --name "$FUNCTION_APP" \
        --resource-group "$RESOURCE_GROUP" \
        --query state \
        --output tsv)
    
    if [[ "$func_state" != "Running" ]]; then
        log_error "Function App is not running. Current state: $func_state"
        exit 1
    fi
    
    # Check if function exists
    if az functionapp function show \
        --name "$FUNCTION_APP" \
        --resource-group "$RESOURCE_GROUP" \
        --function-name ImageResize \
        --output none 2>/dev/null; then
        log_success "Image resize function is deployed and configured"
    else
        log_error "Image resize function not found"
        exit 1
    fi
    
    # Check blob containers
    local storage_connection
    storage_connection=$(az storage account show-connection-string \
        --name "$STORAGE_ACCOUNT" \
        --resource-group "$RESOURCE_GROUP" \
        --query connectionString \
        --output tsv)
    
    local containers=("original-images" "thumbnails" "medium-images")
    for container in "${containers[@]}"; do
        if az storage container show \
            --name "$container" \
            --connection-string "$storage_connection" \
            --output none 2>/dev/null; then
            log_success "Container verified: $container"
        else
            log_error "Container not found: $container"
            exit 1
        fi
    done
}

# Function to display deployment summary
display_summary() {
    log_success "=========================================="
    log_success "DEPLOYMENT COMPLETED SUCCESSFULLY"
    log_success "=========================================="
    echo
    log_info "Resource Details:"
    echo "  Resource Group:    $RESOURCE_GROUP"
    echo "  Storage Account:   $STORAGE_ACCOUNT"
    echo "  Function App:      $FUNCTION_APP"
    echo "  Location:          $LOCATION"
    echo
    log_info "Image Processing Settings:"
    echo "  Thumbnail Size:    ${THUMBNAIL_WIDTH}x${THUMBNAIL_HEIGHT}"
    echo "  Medium Size:       ${MEDIUM_WIDTH}x${MEDIUM_HEIGHT}"
    echo
    log_info "Blob Containers:"
    echo "  Original Images:   original-images"
    echo "  Thumbnails:        thumbnails"
    echo "  Medium Images:     medium-images"
    echo
    log_info "Next Steps:"
    echo "  1. Upload test images to the 'original-images' container"
    echo "  2. Check the 'thumbnails' and 'medium-images' containers for processed images"
    echo "  3. Monitor function logs with: az functionapp log tail --name $FUNCTION_APP --resource-group $RESOURCE_GROUP"
    echo "  4. Clean up resources when done with: ./destroy.sh"
    echo
    log_info "Estimated Monthly Cost: \$0.50 - \$2.00 (for development usage)"
    echo
}

# Main execution function
main() {
    log_info "Starting Azure Image Resizing Function deployment..."
    log_info "Project: $PROJECT_NAME | Location: $LOCATION | Suffix: $RANDOM_SUFFIX"
    echo
    
    check_prerequisites
    validate_azure_environment
    create_resource_group
    create_storage_account
    create_blob_containers
    create_function_app
    configure_function_settings
    deploy_function_code
    verify_deployment
    display_summary
    
    log_success "Deployment completed successfully!"
}

# Error handling
handle_error() {
    local exit_code=$?
    log_error "Deployment failed with exit code: $exit_code"
    log_info "Check the logs above for specific error details"
    log_info "You may need to run the destroy script to clean up partial deployment"
    exit $exit_code
}

trap handle_error ERR

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi