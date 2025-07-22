#!/bin/bash

# Industrial Training Platform Deployment Script
# Deploys Azure Remote Rendering, Azure Object Anchors, and Azure Spatial Anchors
# for immersive industrial training on HoloLens 2

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✅ $1${NC}"
}

warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️ $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ❌ $1${NC}"
}

# Default values
LOCATION="eastus"
RESOURCE_GROUP=""
DEPLOYMENT_NAME="industrial-training-$(date +%s)"
SKIP_PREREQUISITES=false
DRY_RUN=false

# Function to display usage
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Deploy Industrial Training Platform with Azure Remote Rendering and Object Anchors

OPTIONS:
    -g, --resource-group <name>    Resource group name (required)
    -l, --location <location>      Azure location (default: eastus)
    -n, --deployment-name <name>   Deployment name (default: industrial-training-<timestamp>)
    -s, --skip-prerequisites       Skip prerequisites check
    -d, --dry-run                  Validate deployment without creating resources
    -h, --help                     Show this help message

EXAMPLES:
    $0 --resource-group rg-industrial-training-demo
    $0 -g rg-training -l westus2 --deployment-name my-training-platform
    $0 -g rg-training --dry-run

EOF
}

# Parse command line arguments
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
        -n|--deployment-name)
            DEPLOYMENT_NAME="$2"
            shift 2
            ;;
        -s|--skip-prerequisites)
            SKIP_PREREQUISITES=true
            shift
            ;;
        -d|--dry-run)
            DRY_RUN=true
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

# Validate required parameters
if [[ -z "$RESOURCE_GROUP" ]]; then
    error "Resource group name is required. Use -g or --resource-group"
    usage
    exit 1
fi

# Generate unique suffix for resource names
RANDOM_SUFFIX=$(openssl rand -hex 3 2>/dev/null || echo "$(date +%s)" | tail -c 7)
ARR_ACCOUNT_NAME="arr-training-${RANDOM_SUFFIX}"
STORAGE_ACCOUNT_NAME="sttraining${RANDOM_SUFFIX}"
SPATIAL_ANCHORS_ACCOUNT="sa-training-${RANDOM_SUFFIX}"
APP_NAME="industrial-training-platform-${RANDOM_SUFFIX}"

log "🚀 Starting Industrial Training Platform Deployment"
log "================================================="
log "Resource Group: ${RESOURCE_GROUP}"
log "Location: ${LOCATION}"
log "Deployment Name: ${DEPLOYMENT_NAME}"
log "Random Suffix: ${RANDOM_SUFFIX}"

# Prerequisites check
if [[ "$SKIP_PREREQUISITES" == false ]]; then
    log "🔍 Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        error "Azure CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if logged in to Azure
    if ! az account show &> /dev/null; then
        error "Not logged in to Azure. Please run 'az login' first."
        exit 1
    fi
    
    # Check if jq is installed for JSON parsing
    if ! command -v jq &> /dev/null; then
        error "jq is not installed. Please install it for JSON parsing."
        exit 1
    fi
    
    # Check if openssl is available for random generation
    if ! command -v openssl &> /dev/null; then
        warning "openssl not found. Using timestamp for random suffix."
    fi
    
    success "Prerequisites check completed"
fi

# Get subscription info
SUBSCRIPTION_ID=$(az account show --query id --output tsv)
TENANT_ID=$(az account show --query tenantId --output tsv)

log "Subscription ID: ${SUBSCRIPTION_ID}"
log "Tenant ID: ${TENANT_ID}"

# Dry run validation
if [[ "$DRY_RUN" == true ]]; then
    log "🧪 Performing dry run validation..."
    
    # Check if resource group exists
    if az group show --name "${RESOURCE_GROUP}" &>/dev/null; then
        success "Resource group '${RESOURCE_GROUP}' exists"
    else
        warning "Resource group '${RESOURCE_GROUP}' will be created"
    fi
    
    # Check location availability
    if az account list-locations --query "[?name=='${LOCATION}']" --output tsv | grep -q "${LOCATION}"; then
        success "Location '${LOCATION}' is available"
    else
        error "Location '${LOCATION}' is not available"
        exit 1
    fi
    
    # Check resource name availability
    if az storage account check-name --name "${STORAGE_ACCOUNT_NAME}" --query nameAvailable --output tsv | grep -q "true"; then
        success "Storage account name '${STORAGE_ACCOUNT_NAME}' is available"
    else
        error "Storage account name '${STORAGE_ACCOUNT_NAME}' is not available"
        exit 1
    fi
    
    success "Dry run validation completed successfully"
    exit 0
fi

# Create or verify resource group
log "📦 Creating resource group..."
if az group show --name "${RESOURCE_GROUP}" &>/dev/null; then
    log "Resource group '${RESOURCE_GROUP}' already exists"
else
    az group create \
        --name "${RESOURCE_GROUP}" \
        --location "${LOCATION}" \
        --tags purpose=industrial-training environment=demo project=mixed-reality-training
    
    success "Resource group '${RESOURCE_GROUP}' created"
fi

# Register required Azure resource providers
log "🔧 Registering Azure resource providers..."
providers=("Microsoft.MixedReality" "Microsoft.Storage" "Microsoft.Compute")

for provider in "${providers[@]}"; do
    log "Registering ${provider}..."
    az provider register --namespace "${provider}" --wait
done

success "Azure providers registered for Mixed Reality services"

# Create Azure Storage Account
log "💾 Creating Azure Storage Account..."
az storage account create \
    --name "${STORAGE_ACCOUNT_NAME}" \
    --resource-group "${RESOURCE_GROUP}" \
    --location "${LOCATION}" \
    --sku Standard_LRS \
    --kind StorageV2 \
    --access-tier Hot \
    --https-only true \
    --allow-blob-public-access false \
    --tags purpose=industrial-training environment=demo

# Get storage account key
STORAGE_KEY=$(az storage account keys list \
    --account-name "${STORAGE_ACCOUNT_NAME}" \
    --resource-group "${RESOURCE_GROUP}" \
    --query '[0].value' --output tsv)

# Create storage containers
log "📁 Creating storage containers..."
containers=("3d-models" "training-content" "user-data" "session-recordings")

for container in "${containers[@]}"; do
    az storage container create \
        --name "${container}" \
        --account-name "${STORAGE_ACCOUNT_NAME}" \
        --account-key "${STORAGE_KEY}" \
        --public-access off
    
    success "Container '${container}' created"
done

# Create Azure Remote Rendering Account
log "🎨 Creating Azure Remote Rendering Account..."
warning "Note: Azure Remote Rendering will be retired on September 30, 2025"

az mixed-reality remote-rendering-account create \
    --name "${ARR_ACCOUNT_NAME}" \
    --resource-group "${RESOURCE_GROUP}" \
    --location "${LOCATION}" \
    --tags purpose=industrial-training environment=demo

# Get Remote Rendering account details
ARR_ACCOUNT_ID=$(az mixed-reality remote-rendering-account show \
    --name "${ARR_ACCOUNT_NAME}" \
    --resource-group "${RESOURCE_GROUP}" \
    --query accountId --output tsv)

ARR_ACCOUNT_DOMAIN=$(az mixed-reality remote-rendering-account show \
    --name "${ARR_ACCOUNT_NAME}" \
    --resource-group "${RESOURCE_GROUP}" \
    --query accountDomain --output tsv)

ARR_ACCESS_KEY=$(az mixed-reality remote-rendering-account key show \
    --name "${ARR_ACCOUNT_NAME}" \
    --resource-group "${RESOURCE_GROUP}" \
    --query primaryKey --output tsv)

success "Remote Rendering account '${ARR_ACCOUNT_NAME}' created"

# Create Azure Spatial Anchors Account
log "🧭 Creating Azure Spatial Anchors Account..."
az mixed-reality spatial-anchors-account create \
    --name "${SPATIAL_ANCHORS_ACCOUNT}" \
    --resource-group "${RESOURCE_GROUP}" \
    --location "${LOCATION}" \
    --tags purpose=spatial-anchoring environment=industrial-training

# Get Spatial Anchors account details
SPATIAL_ANCHORS_ID=$(az mixed-reality spatial-anchors-account show \
    --name "${SPATIAL_ANCHORS_ACCOUNT}" \
    --resource-group "${RESOURCE_GROUP}" \
    --query accountId --output tsv)

SPATIAL_ANCHORS_DOMAIN=$(az mixed-reality spatial-anchors-account show \
    --name "${SPATIAL_ANCHORS_ACCOUNT}" \
    --resource-group "${RESOURCE_GROUP}" \
    --query accountDomain --output tsv)

SPATIAL_ANCHORS_KEY=$(az mixed-reality spatial-anchors-account key show \
    --name "${SPATIAL_ANCHORS_ACCOUNT}" \
    --resource-group "${RESOURCE_GROUP}" \
    --query primaryKey --output tsv)

success "Spatial Anchors account '${SPATIAL_ANCHORS_ACCOUNT}' created"

# Create Azure AD Application Registration
log "🔐 Creating Azure AD Application Registration..."
APP_ID=$(az ad app create \
    --display-name "${APP_NAME}" \
    --sign-in-audience AzureADMyOrg \
    --query appId --output tsv)

# Create service principal
az ad sp create --id "${APP_ID}" &>/dev/null

# Configure application permissions for Mixed Reality services
az ad app permission add \
    --id "${APP_ID}" \
    --api 00000003-0000-0000-c000-000000000000 \
    --api-permissions 14dad69e-099b-42c9-810b-d002981feec1=Role

# Grant admin consent (if user has permissions)
if az ad app permission grant --id "${APP_ID}" --api 00000003-0000-0000-c000-000000000000 &>/dev/null; then
    success "Admin consent granted for application permissions"
else
    warning "Unable to grant admin consent automatically. Please grant manually in Azure portal."
fi

success "Azure AD application '${APP_NAME}' created"

# Create sample training content
log "📚 Creating sample training content..."
mkdir -p ./temp-content/{industrial-models,training-scenarios,unity-config}

# Create sample 3D model metadata
cat > ./temp-content/industrial-models/pump-assembly.json << EOF
{
  "name": "Industrial Pump Assembly",
  "description": "High-pressure centrifugal pump for industrial applications",
  "modelType": "machinery",
  "trainingScenarios": ["maintenance", "assembly", "troubleshooting"],
  "complexity": "high",
  "polygonCount": 2500000,
  "version": "1.0",
  "created": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "tags": ["pump", "industrial", "machinery", "maintenance"]
}
EOF

cat > ./temp-content/industrial-models/control-panel.json << EOF
{
  "name": "Industrial Control Panel",
  "description": "Programmable logic controller interface panel",
  "modelType": "controls",
  "trainingScenarios": ["operation", "programming", "diagnostics"],
  "complexity": "medium",
  "polygonCount": 850000,
  "version": "1.0",
  "created": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "tags": ["control", "panel", "plc", "interface"]
}
EOF

# Create training scenarios
cat > ./temp-content/training-scenarios/pump-maintenance.json << EOF
{
  "scenarioId": "pump-maintenance-001",
  "title": "Centrifugal Pump Maintenance Procedure",
  "description": "Step-by-step maintenance procedure for industrial centrifugal pumps",
  "duration": "45 minutes",
  "difficulty": "intermediate",
  "prerequisites": ["basic-pump-knowledge", "safety-training"],
  "objectives": [
    "Identify pump components and their functions",
    "Perform routine maintenance checks",
    "Troubleshoot common pump issues",
    "Document maintenance activities"
  ],
  "assessmentCriteria": {
    "safety": "mandatory",
    "accuracy": "85%",
    "timeLimit": "60 minutes"
  },
  "created": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF

# Create Unity configuration
cat > ./temp-content/unity-config/azure-services-config.json << EOF
{
  "azureServices": {
    "remoteRendering": {
      "accountId": "${ARR_ACCOUNT_ID}",
      "accountDomain": "${ARR_ACCOUNT_DOMAIN}",
      "serviceEndpoint": "https://remoterendering.${LOCATION}.mixedreality.azure.com"
    },
    "spatialAnchors": {
      "accountId": "${SPATIAL_ANCHORS_ID}",
      "accountDomain": "${SPATIAL_ANCHORS_DOMAIN}",
      "serviceEndpoint": "https://sts.${LOCATION}.mixedreality.azure.com"
    },
    "storage": {
      "accountName": "${STORAGE_ACCOUNT_NAME}",
      "modelsContainer": "3d-models",
      "trainingContainer": "training-content"
    },
    "azureAD": {
      "tenantId": "${TENANT_ID}",
      "clientId": "${APP_ID}",
      "redirectUri": "ms-appx-web://microsoft.aad.brokerplugin/${APP_ID}"
    }
  },
  "trainingPlatform": {
    "sessionSettings": {
      "maxConcurrentUsers": 10,
      "sessionTimeout": 3600,
      "renderingQuality": "high",
      "enableCollaboration": true
    },
    "spatialSettings": {
      "anchorPersistence": true,
      "roomScale": true,
      "trackingAccuracy": "high",
      "enableWorldMapping": true
    }
  }
}
EOF

# Upload content to storage
log "📤 Uploading training content to storage..."
az storage blob upload \
    --file ./temp-content/industrial-models/pump-assembly.json \
    --container-name "3d-models" \
    --name "pump-assembly/metadata.json" \
    --account-name "${STORAGE_ACCOUNT_NAME}" \
    --account-key "${STORAGE_KEY}" \
    --overwrite

az storage blob upload \
    --file ./temp-content/industrial-models/control-panel.json \
    --container-name "3d-models" \
    --name "control-panel/metadata.json" \
    --account-name "${STORAGE_ACCOUNT_NAME}" \
    --account-key "${STORAGE_KEY}" \
    --overwrite

az storage blob upload \
    --file ./temp-content/training-scenarios/pump-maintenance.json \
    --container-name "training-content" \
    --name "scenarios/pump-maintenance.json" \
    --account-name "${STORAGE_ACCOUNT_NAME}" \
    --account-key "${STORAGE_KEY}" \
    --overwrite

az storage blob upload \
    --file ./temp-content/unity-config/azure-services-config.json \
    --container-name "training-content" \
    --name "unity-config/azure-services-config.json" \
    --account-name "${STORAGE_ACCOUNT_NAME}" \
    --account-key "${STORAGE_KEY}" \
    --overwrite

success "Training content uploaded to storage"

# Cleanup temporary files
rm -rf ./temp-content

# Validate deployment
log "🔍 Validating deployment..."

# Check Remote Rendering account
if az mixed-reality remote-rendering-account show --name "${ARR_ACCOUNT_NAME}" --resource-group "${RESOURCE_GROUP}" &>/dev/null; then
    success "Remote Rendering account is accessible"
else
    error "Remote Rendering account validation failed"
    exit 1
fi

# Check Spatial Anchors account
if az mixed-reality spatial-anchors-account show --name "${SPATIAL_ANCHORS_ACCOUNT}" --resource-group "${RESOURCE_GROUP}" &>/dev/null; then
    success "Spatial Anchors account is accessible"
else
    error "Spatial Anchors account validation failed"
    exit 1
fi

# Check storage account
if az storage account show --name "${STORAGE_ACCOUNT_NAME}" --resource-group "${RESOURCE_GROUP}" &>/dev/null; then
    success "Storage account is accessible"
else
    error "Storage account validation failed"
    exit 1
fi

# Test storage connectivity
BLOB_COUNT=$(az storage blob list \
    --container-name "3d-models" \
    --account-name "${STORAGE_ACCOUNT_NAME}" \
    --account-key "${STORAGE_KEY}" \
    --query "length(@)" --output tsv)

success "Storage validation completed (${BLOB_COUNT} blobs in 3d-models container)"

# Create deployment summary
log "📋 Creating deployment summary..."
cat > deployment-summary.json << EOF
{
  "deploymentName": "${DEPLOYMENT_NAME}",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "resourceGroup": "${RESOURCE_GROUP}",
  "location": "${LOCATION}",
  "subscriptionId": "${SUBSCRIPTION_ID}",
  "resources": {
    "remoteRendering": {
      "accountName": "${ARR_ACCOUNT_NAME}",
      "accountId": "${ARR_ACCOUNT_ID}",
      "domain": "${ARR_ACCOUNT_DOMAIN}"
    },
    "spatialAnchors": {
      "accountName": "${SPATIAL_ANCHORS_ACCOUNT}",
      "accountId": "${SPATIAL_ANCHORS_ID}",
      "domain": "${SPATIAL_ANCHORS_DOMAIN}"
    },
    "storage": {
      "accountName": "${STORAGE_ACCOUNT_NAME}"
    },
    "azureAD": {
      "applicationName": "${APP_NAME}",
      "clientId": "${APP_ID}"
    }
  },
  "nextSteps": [
    "Configure Unity project with provided settings",
    "Install Mixed Reality Toolkit (MRTK) 3.0",
    "Import Azure Remote Rendering SDK",
    "Configure HoloLens 2 development environment",
    "Test spatial anchoring with physical equipment"
  ]
}
EOF

# Display deployment results
log "🎉 Deployment completed successfully!"
log "=================================="
log "Resource Group: ${RESOURCE_GROUP}"
log "Remote Rendering Account: ${ARR_ACCOUNT_NAME}"
log "Spatial Anchors Account: ${SPATIAL_ANCHORS_ACCOUNT}"
log "Storage Account: ${STORAGE_ACCOUNT_NAME}"
log "Azure AD Application: ${APP_NAME}"
log ""
log "📄 Deployment summary saved to: deployment-summary.json"
log ""
log "🔑 Important Configuration Details:"
log "- Remote Rendering Account ID: ${ARR_ACCOUNT_ID}"
log "- Spatial Anchors Account ID: ${SPATIAL_ANCHORS_ID}"
log "- Application Client ID: ${APP_ID}"
log ""
log "⚠️  IMPORTANT SECURITY NOTES:"
log "- Store access keys securely (not in source code)"
log "- Use Azure Key Vault for production deployments"
log "- Grant minimal required permissions to service principals"
log "- Azure Remote Rendering retires September 30, 2025"
log ""
log "🚀 Next Steps:"
log "1. Download Unity configuration from storage"
log "2. Set up Unity project with MRTK 3.0"
log "3. Configure HoloLens 2 development environment"
log "4. Test with actual 3D industrial models"
log "5. Implement spatial anchoring with physical equipment"
log ""
log "💡 To destroy this deployment, run: ./destroy.sh -g ${RESOURCE_GROUP}"

success "Industrial Training Platform deployment completed successfully!"