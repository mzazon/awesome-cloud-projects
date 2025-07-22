#!/bin/bash

# deploy.sh - Deployment script for Azure Video Conferencing Application
# This script deploys a scalable video conferencing application using Azure Web App for Containers and Azure Communication Services

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/deploy.log"
DRY_RUN=${DRY_RUN:-false}

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}" | tee -a "$LOG_FILE"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}" | tee -a "$LOG_FILE"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}" | tee -a "$LOG_FILE"
    exit 1
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1${NC}" | tee -a "$LOG_FILE"
}

# Display script header
display_header() {
    echo -e "${BLUE}"
    echo "================================================================="
    echo "  Azure Video Conferencing Application Deployment Script"
    echo "================================================================="
    echo -e "${NC}"
    echo "This script deploys:"
    echo "- Azure Container Registry"
    echo "- Azure Communication Services"
    echo "- Azure Blob Storage for call recordings"
    echo "- Azure Web App for Containers"
    echo "- Application Insights for monitoring"
    echo "- Auto-scaling configuration"
    echo ""
}

# Prerequisites check
check_prerequisites() {
    info "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        error "Azure CLI is not installed. Please install it first."
    fi
    
    # Check Azure CLI version
    AZ_VERSION=$(az version --query '"azure-cli"' -o tsv 2>/dev/null || echo "unknown")
    if [[ "$AZ_VERSION" == "unknown" ]]; then
        error "Unable to determine Azure CLI version"
    fi
    log "Azure CLI version: $AZ_VERSION"
    
    # Check if logged in to Azure
    if ! az account show &> /dev/null; then
        error "Not logged in to Azure. Please run 'az login' first."
    fi
    
    # Check if Docker is installed
    if ! command -v docker &> /dev/null; then
        error "Docker is not installed. Please install it first."
    fi
    
    # Check if Docker daemon is running
    if ! docker info &> /dev/null; then
        error "Docker daemon is not running. Please start Docker first."
    fi
    
    # Check if Communication Services extension is available
    if ! az extension show --name communication &> /dev/null; then
        info "Installing Communication Services extension..."
        az extension add --name communication
    fi
    
    log "Prerequisites check completed successfully"
}

# Configuration setup
setup_configuration() {
    info "Setting up configuration..."
    
    # Set default values or get from environment
    export RESOURCE_GROUP="${RESOURCE_GROUP:-rg-video-conferencing-app}"
    export LOCATION="${LOCATION:-eastus}"
    export SUBSCRIPTION_ID="${SUBSCRIPTION_ID:-$(az account show --query id --output tsv)}"
    
    # Generate unique suffix for resource names
    if [[ -z "${RANDOM_SUFFIX:-}" ]]; then
        export RANDOM_SUFFIX=$(openssl rand -hex 3)
    fi
    
    # Set resource names
    export STORAGE_ACCOUNT="${STORAGE_ACCOUNT:-stvideoconf${RANDOM_SUFFIX}}"
    export COMMUNICATION_SERVICE="${COMMUNICATION_SERVICE:-cs-video-conferencing-${RANDOM_SUFFIX}}"
    export WEBAPP_NAME="${WEBAPP_NAME:-webapp-video-conferencing-${RANDOM_SUFFIX}}"
    export CONTAINER_REGISTRY="${CONTAINER_REGISTRY:-acrvideo${RANDOM_SUFFIX}}"
    export APP_SERVICE_PLAN="${APP_SERVICE_PLAN:-asp-video-conferencing-${RANDOM_SUFFIX}}"
    export AUTOSCALE_NAME="${AUTOSCALE_NAME:-video-conferencing-autoscale}"
    export APPINSIGHTS_NAME="${APPINSIGHTS_NAME:-video-conferencing-insights}"
    
    # Configuration summary
    log "Configuration:"
    log "  Resource Group: $RESOURCE_GROUP"
    log "  Location: $LOCATION"
    log "  Subscription ID: $SUBSCRIPTION_ID"
    log "  Random Suffix: $RANDOM_SUFFIX"
    log "  Storage Account: $STORAGE_ACCOUNT"
    log "  Communication Service: $COMMUNICATION_SERVICE"
    log "  Web App Name: $WEBAPP_NAME"
    log "  Container Registry: $CONTAINER_REGISTRY"
    log "  App Service Plan: $APP_SERVICE_PLAN"
}

# Create resource group
create_resource_group() {
    info "Creating resource group..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY RUN: Would create resource group $RESOURCE_GROUP"
        return
    fi
    
    if az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        warn "Resource group $RESOURCE_GROUP already exists"
    else
        az group create \
            --name "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --tags purpose=video-conferencing environment=demo
        
        log "Resource group created: $RESOURCE_GROUP"
    fi
}

# Create Azure Container Registry
create_container_registry() {
    info "Creating Azure Container Registry..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY RUN: Would create container registry $CONTAINER_REGISTRY"
        return
    fi
    
    if az acr show --name "$CONTAINER_REGISTRY" &> /dev/null; then
        warn "Container registry $CONTAINER_REGISTRY already exists"
    else
        az acr create \
            --resource-group "$RESOURCE_GROUP" \
            --name "$CONTAINER_REGISTRY" \
            --sku Basic \
            --admin-enabled true \
            --location "$LOCATION"
        
        log "Container registry created: $CONTAINER_REGISTRY"
    fi
    
    # Get registry login server
    export ACR_LOGIN_SERVER=$(az acr show \
        --name "$CONTAINER_REGISTRY" \
        --query loginServer --output tsv)
    
    log "Container registry login server: $ACR_LOGIN_SERVER"
}

# Create Azure Communication Services
create_communication_services() {
    info "Creating Azure Communication Services..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY RUN: Would create communication service $COMMUNICATION_SERVICE"
        return
    fi
    
    if az communication show --name "$COMMUNICATION_SERVICE" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        warn "Communication service $COMMUNICATION_SERVICE already exists"
    else
        az communication create \
            --name "$COMMUNICATION_SERVICE" \
            --resource-group "$RESOURCE_GROUP" \
            --location "Global" \
            --data-location "UnitedStates"
        
        log "Communication Services resource created: $COMMUNICATION_SERVICE"
    fi
    
    # Get connection string
    export ACS_CONNECTION_STRING=$(az communication list-key \
        --name "$COMMUNICATION_SERVICE" \
        --resource-group "$RESOURCE_GROUP" \
        --query primaryConnectionString --output tsv)
    
    log "Communication Services connection string retrieved"
}

# Create Azure Blob Storage
create_blob_storage() {
    info "Creating Azure Blob Storage..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY RUN: Would create storage account $STORAGE_ACCOUNT"
        return
    fi
    
    if az storage account show --name "$STORAGE_ACCOUNT" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        warn "Storage account $STORAGE_ACCOUNT already exists"
    else
        az storage account create \
            --name "$STORAGE_ACCOUNT" \
            --resource-group "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --sku Standard_LRS \
            --kind StorageV2 \
            --access-tier Hot
        
        log "Storage account created: $STORAGE_ACCOUNT"
    fi
    
    # Create container for recordings
    az storage container create \
        --name recordings \
        --account-name "$STORAGE_ACCOUNT" \
        --public-access off
    
    # Get storage connection string
    export STORAGE_CONNECTION_STRING=$(az storage account show-connection-string \
        --name "$STORAGE_ACCOUNT" \
        --resource-group "$RESOURCE_GROUP" \
        --query connectionString --output tsv)
    
    log "Storage container 'recordings' created"
}

# Create App Service Plan
create_app_service_plan() {
    info "Creating App Service Plan..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY RUN: Would create app service plan $APP_SERVICE_PLAN"
        return
    fi
    
    if az appservice plan show --name "$APP_SERVICE_PLAN" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        warn "App Service Plan $APP_SERVICE_PLAN already exists"
    else
        az appservice plan create \
            --name "$APP_SERVICE_PLAN" \
            --resource-group "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --is-linux \
            --sku P1V2 \
            --number-of-workers 1
        
        log "App Service Plan created: $APP_SERVICE_PLAN"
    fi
}

# Create Application Insights
create_application_insights() {
    info "Creating Application Insights..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY RUN: Would create application insights $APPINSIGHTS_NAME"
        return
    fi
    
    if az monitor app-insights component show --app "$APPINSIGHTS_NAME" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        warn "Application Insights $APPINSIGHTS_NAME already exists"
    else
        az monitor app-insights component create \
            --app "$APPINSIGHTS_NAME" \
            --location "$LOCATION" \
            --resource-group "$RESOURCE_GROUP" \
            --application-type web \
            --kind web
        
        log "Application Insights created: $APPINSIGHTS_NAME"
    fi
    
    # Get instrumentation key
    export APPINSIGHTS_INSTRUMENTATION_KEY=$(az monitor app-insights component show \
        --app "$APPINSIGHTS_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --query instrumentationKey --output tsv)
    
    log "Application Insights instrumentation key retrieved"
}

# Create sample application
create_sample_application() {
    info "Creating sample application..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY RUN: Would create sample application"
        return
    fi
    
    # Create application directory
    local APP_DIR="$SCRIPT_DIR/../video-conferencing-app"
    mkdir -p "$APP_DIR/src"
    mkdir -p "$APP_DIR/public"
    
    # Create package.json
    cat > "$APP_DIR/package.json" << 'EOF'
{
  "name": "video-conferencing-app",
  "version": "1.0.0",
  "description": "Scalable video conferencing with Azure Communication Services",
  "main": "src/server.js",
  "scripts": {
    "start": "node src/server.js",
    "dev": "nodemon src/server.js"
  },
  "dependencies": {
    "express": "^4.18.2",
    "@azure/communication-common": "^2.3.0",
    "@azure/communication-identity": "^1.3.0",
    "@azure/communication-calling": "^1.13.1",
    "@azure/storage-blob": "^12.17.0",
    "applicationinsights": "^2.9.1",
    "dotenv": "^16.3.1"
  },
  "engines": {
    "node": ">=18.0.0"
  }
}
EOF
    
    # Create server.js
    cat > "$APP_DIR/src/server.js" << 'EOF'
const express = require('express');
const { CommunicationIdentityClient } = require('@azure/communication-identity');
const { BlobServiceClient } = require('@azure/storage-blob');
const appInsights = require('applicationinsights');
require('dotenv').config();

// Initialize Application Insights
appInsights.setup(process.env.APPINSIGHTS_INSTRUMENTATION_KEY);
appInsights.start();

const app = express();
const port = process.env.PORT || 3000;

// Initialize clients
const identityClient = new CommunicationIdentityClient(process.env.ACS_CONNECTION_STRING);
const blobServiceClient = BlobServiceClient.fromConnectionString(process.env.STORAGE_CONNECTION_STRING);

app.use(express.json());
app.use(express.static('public'));

// Generate Communication Services access token
app.post('/token', async (req, res) => {
  try {
    const user = await identityClient.createUser();
    const tokenResponse = await identityClient.getToken(user, ['voip']);
    res.json({
      token: tokenResponse.token,
      expiresOn: tokenResponse.expiresOn,
      user: user
    });
  } catch (error) {
    console.error('Token generation failed:', error);
    res.status(500).json({ error: 'Failed to generate token' });
  }
});

// Start call recording
app.post('/start-recording', async (req, res) => {
  try {
    const { serverCallId } = req.body;
    // Call recording logic would be implemented here
    res.json({ success: true, recordingId: 'sample-recording-id' });
  } catch (error) {
    console.error('Recording start failed:', error);
    res.status(500).json({ error: 'Failed to start recording' });
  }
});

// Health check endpoint
app.get('/health', (req, res) => {
  res.json({ status: 'healthy', timestamp: new Date().toISOString() });
});

app.listen(port, () => {
  console.log(`Video conferencing app listening on port ${port}`);
});
EOF
    
    # Create index.html
    cat > "$APP_DIR/public/index.html" << 'EOF'
<!DOCTYPE html>
<html>
<head>
  <title>Video Conferencing App</title>
  <script src="https://skype.azureedge.net/sdk/calling/1.13.1/calling.js"></script>
</head>
<body>
  <h1>Azure Communication Services Video Conferencing</h1>
  <div id="call-container">
    <button id="start-call">Start Call</button>
    <button id="end-call">End Call</button>
    <button id="start-recording">Start Recording</button>
    <div id="video-container"></div>
  </div>
  <script>
    // Video conferencing client logic would be implemented here
    console.log('Video conferencing application loaded');
  </script>
</body>
</html>
EOF
    
    # Create Dockerfile
    cat > "$APP_DIR/Dockerfile" << 'EOF'
FROM node:18-alpine AS build

# Set working directory
WORKDIR /app

# Copy package files
COPY package*.json ./

# Install dependencies
RUN npm ci --only=production

# Copy application files
COPY . .

# Create production image
FROM node:18-alpine

# Install dumb-init for proper signal handling
RUN apk add --no-cache dumb-init

# Create non-root user
RUN addgroup -g 1001 -S nodejs
RUN adduser -S nodejs -u 1001

# Set working directory
WORKDIR /app

# Copy application and dependencies
COPY --from=build --chown=nodejs:nodejs /app .

# Switch to non-root user
USER nodejs

# Expose port
EXPOSE 3000

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
  CMD node -e "require('http').get('http://localhost:3000/health', (res) => { process.exit(res.statusCode === 200 ? 0 : 1) })"

# Start application
ENTRYPOINT ["dumb-init", "--"]
CMD ["node", "src/server.js"]
EOF
    
    # Create .dockerignore
    cat > "$APP_DIR/.dockerignore" << 'EOF'
node_modules
.git
.gitignore
README.md
.env
.nyc_output
coverage
.vscode
EOF
    
    log "Sample application created in $APP_DIR"
}

# Build and push container image
build_and_push_container() {
    info "Building and pushing container image..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY RUN: Would build and push container image"
        return
    fi
    
    local APP_DIR="$SCRIPT_DIR/../video-conferencing-app"
    
    # Build container image
    cd "$APP_DIR"
    docker build -t "$ACR_LOGIN_SERVER/video-conferencing-app:latest" .
    
    # Login to Azure Container Registry
    az acr login --name "$CONTAINER_REGISTRY"
    
    # Push image to registry
    docker push "$ACR_LOGIN_SERVER/video-conferencing-app:latest"
    
    log "Container image pushed to registry"
    cd "$SCRIPT_DIR"
}

# Deploy Web App for Containers
deploy_web_app() {
    info "Deploying Web App for Containers..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY RUN: Would deploy web app $WEBAPP_NAME"
        return
    fi
    
    if az webapp show --name "$WEBAPP_NAME" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        warn "Web App $WEBAPP_NAME already exists"
    else
        az webapp create \
            --resource-group "$RESOURCE_GROUP" \
            --plan "$APP_SERVICE_PLAN" \
            --name "$WEBAPP_NAME" \
            --deployment-container-image-name "$ACR_LOGIN_SERVER/video-conferencing-app:latest"
        
        log "Web App for Containers created: $WEBAPP_NAME"
    fi
    
    # Configure container registry credentials
    local ACR_PASSWORD=$(az acr credential show --name "$CONTAINER_REGISTRY" --query passwords[0].value --output tsv)
    
    az webapp config container set \
        --name "$WEBAPP_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --container-image-name "$ACR_LOGIN_SERVER/video-conferencing-app:latest" \
        --container-registry-url "https://$ACR_LOGIN_SERVER" \
        --container-registry-user "$CONTAINER_REGISTRY" \
        --container-registry-password "$ACR_PASSWORD"
    
    log "Web App container configuration updated"
}

# Configure application settings
configure_application_settings() {
    info "Configuring application settings..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY RUN: Would configure application settings"
        return
    fi
    
    # Configure application settings
    az webapp config appsettings set \
        --resource-group "$RESOURCE_GROUP" \
        --name "$WEBAPP_NAME" \
        --settings \
        ACS_CONNECTION_STRING="$ACS_CONNECTION_STRING" \
        STORAGE_CONNECTION_STRING="$STORAGE_CONNECTION_STRING" \
        APPINSIGHTS_INSTRUMENTATION_KEY="$APPINSIGHTS_INSTRUMENTATION_KEY" \
        NODE_ENV="production"
    
    # Enable container logging
    az webapp log config \
        --resource-group "$RESOURCE_GROUP" \
        --name "$WEBAPP_NAME" \
        --docker-container-logging filesystem
    
    # Get application URL
    export WEBAPP_URL=$(az webapp show \
        --resource-group "$RESOURCE_GROUP" \
        --name "$WEBAPP_NAME" \
        --query defaultHostName --output tsv)
    
    log "Application configured and available at: https://$WEBAPP_URL"
}

# Configure auto-scaling
configure_auto_scaling() {
    info "Configuring auto-scaling..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY RUN: Would configure auto-scaling"
        return
    fi
    
    # Create auto-scaling profile
    if az monitor autoscale show --resource-group "$RESOURCE_GROUP" --name "$AUTOSCALE_NAME" &> /dev/null; then
        warn "Auto-scaling profile $AUTOSCALE_NAME already exists"
    else
        az monitor autoscale create \
            --resource-group "$RESOURCE_GROUP" \
            --resource "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Web/serverfarms/$APP_SERVICE_PLAN" \
            --name "$AUTOSCALE_NAME" \
            --min-count 1 \
            --max-count 10 \
            --count 2
        
        # Add CPU-based scaling rule (scale out)
        az monitor autoscale rule create \
            --resource-group "$RESOURCE_GROUP" \
            --autoscale-name "$AUTOSCALE_NAME" \
            --condition "Percentage CPU > 70 avg 5m" \
            --scale out 1
        
        # Add CPU-based scaling rule (scale in)
        az monitor autoscale rule create \
            --resource-group "$RESOURCE_GROUP" \
            --autoscale-name "$AUTOSCALE_NAME" \
            --condition "Percentage CPU < 30 avg 5m" \
            --scale in 1
        
        log "Auto-scaling rules configured"
    fi
}

# Verify deployment
verify_deployment() {
    info "Verifying deployment..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY RUN: Would verify deployment"
        return
    fi
    
    # Wait for application to be ready
    info "Waiting for application to be ready..."
    local max_attempts=30
    local attempt=1
    
    while [[ $attempt -le $max_attempts ]]; do
        if curl -f -s "https://$WEBAPP_URL/health" > /dev/null 2>&1; then
            log "Application health check passed"
            break
        fi
        
        if [[ $attempt -eq $max_attempts ]]; then
            error "Application failed to respond after $max_attempts attempts"
        fi
        
        info "Attempt $attempt/$max_attempts: Waiting for application to be ready..."
        sleep 10
        ((attempt++))
    done
    
    # Test token generation endpoint
    if curl -f -s -X POST "https://$WEBAPP_URL/token" -H "Content-Type: application/json" > /dev/null 2>&1; then
        log "Token generation endpoint is working"
    else
        warn "Token generation endpoint test failed"
    fi
}

# Save deployment configuration
save_deployment_config() {
    info "Saving deployment configuration..."
    
    local CONFIG_FILE="$SCRIPT_DIR/../deployment-config.json"
    
    cat > "$CONFIG_FILE" << EOF
{
  "resourceGroup": "$RESOURCE_GROUP",
  "location": "$LOCATION",
  "subscriptionId": "$SUBSCRIPTION_ID",
  "storageAccount": "$STORAGE_ACCOUNT",
  "communicationService": "$COMMUNICATION_SERVICE",
  "webAppName": "$WEBAPP_NAME",
  "containerRegistry": "$CONTAINER_REGISTRY",
  "appServicePlan": "$APP_SERVICE_PLAN",
  "autoscaleName": "$AUTOSCALE_NAME",
  "appInsightsName": "$APPINSIGHTS_NAME",
  "webAppUrl": "https://$WEBAPP_URL",
  "deploymentTime": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF
    
    log "Deployment configuration saved to $CONFIG_FILE"
}

# Display deployment summary
display_summary() {
    echo ""
    echo -e "${GREEN}================================================================="
    echo "                    DEPLOYMENT SUCCESSFUL"
    echo -e "=================================================================${NC}"
    echo ""
    echo "Application URL: https://$WEBAPP_URL"
    echo "Resource Group: $RESOURCE_GROUP"
    echo "Location: $LOCATION"
    echo ""
    echo "Resources created:"
    echo "  - Container Registry: $CONTAINER_REGISTRY"
    echo "  - Communication Service: $COMMUNICATION_SERVICE"
    echo "  - Storage Account: $STORAGE_ACCOUNT"
    echo "  - App Service Plan: $APP_SERVICE_PLAN"
    echo "  - Web App: $WEBAPP_NAME"
    echo "  - Application Insights: $APPINSIGHTS_NAME"
    echo "  - Auto-scaling: $AUTOSCALE_NAME"
    echo ""
    echo "Next steps:"
    echo "  1. Access the application at: https://$WEBAPP_URL"
    echo "  2. Monitor performance in Application Insights"
    echo "  3. Review call recordings in the storage account"
    echo "  4. Configure additional scaling rules if needed"
    echo ""
    echo "To clean up resources, run: ./destroy.sh"
    echo ""
}

# Main deployment function
main() {
    # Initialize log file
    echo "Deployment started at $(date)" > "$LOG_FILE"
    
    display_header
    
    # Check for dry run mode
    if [[ "$DRY_RUN" == "true" ]]; then
        warn "Running in DRY RUN mode - no resources will be created"
    fi
    
    # Execute deployment steps
    check_prerequisites
    setup_configuration
    create_resource_group
    create_container_registry
    create_communication_services
    create_blob_storage
    create_app_service_plan
    create_application_insights
    create_sample_application
    build_and_push_container
    deploy_web_app
    configure_application_settings
    configure_auto_scaling
    verify_deployment
    save_deployment_config
    display_summary
    
    log "Deployment completed successfully!"
}

# Handle script interruption
trap 'error "Deployment interrupted by user"' INT TERM

# Run main function
main "$@"