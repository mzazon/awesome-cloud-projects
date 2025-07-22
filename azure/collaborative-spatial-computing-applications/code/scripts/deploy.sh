#!/bin/bash

# Deploy script for Azure Spatial Computing Application
# This script creates Azure Remote Rendering and Spatial Anchors resources
# for developing spatial computing applications

set -e  # Exit on any error
set -o pipefail  # Exit on pipe failures

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING:${NC} $1"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1"
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO:${NC} $1"
}

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CONFIG_FILE="$SCRIPT_DIR/deployment-config.env"

# Default values
DEFAULT_LOCATION="eastus"
DEFAULT_RESOURCE_GROUP_PREFIX="rg-spatialcomputing"
DEFAULT_STORAGE_SKU="Standard_LRS"

# Check if deployment config exists
if [[ -f "$CONFIG_FILE" ]]; then
    log "Loading configuration from $CONFIG_FILE"
    source "$CONFIG_FILE"
fi

# Function to display usage
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Deploy Azure Spatial Computing Application infrastructure

OPTIONS:
    -g, --resource-group    Resource group name (default: auto-generated)
    -l, --location          Azure region (default: $DEFAULT_LOCATION)
    -s, --suffix            Unique suffix for resources (default: auto-generated)
    -c, --config            Path to configuration file
    -h, --help             Show this help message
    -v, --verbose          Enable verbose logging
    -d, --dry-run          Show what would be deployed without making changes
    --skip-validation      Skip prerequisite validation
    --force                Force deployment even if resources exist

Examples:
    $0                                          # Deploy with defaults
    $0 -g myresourcegroup -l westus2           # Deploy to specific RG and location
    $0 -c ./custom-config.env                  # Use custom configuration
    $0 --dry-run                               # Preview deployment
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
        -s|--suffix)
            SUFFIX="$2"
            shift 2
            ;;
        -c|--config)
            CONFIG_FILE="$2"
            if [[ -f "$CONFIG_FILE" ]]; then
                source "$CONFIG_FILE"
            else
                error "Configuration file not found: $CONFIG_FILE"
                exit 1
            fi
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        -d|--dry-run)
            DRY_RUN=true
            shift
            ;;
        --skip-validation)
            SKIP_VALIDATION=true
            shift
            ;;
        --force)
            FORCE=true
            shift
            ;;
        *)
            error "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# Set default values if not provided
LOCATION=${LOCATION:-$DEFAULT_LOCATION}
SUFFIX=${SUFFIX:-$(openssl rand -hex 3 2>/dev/null || echo "$(date +%s | tail -c 6)")}
RESOURCE_GROUP=${RESOURCE_GROUP:-"${DEFAULT_RESOURCE_GROUP_PREFIX}-${SUFFIX}"}

# Set resource names
ARR_ACCOUNT_NAME="arr${SUFFIX}"
ASA_ACCOUNT_NAME="asa${SUFFIX}"
STORAGE_ACCOUNT="st3dstorage${SUFFIX}"
BLOB_CONTAINER="3dmodels"
SP_NAME="sp-spatialapp-${SUFFIX}"

# Function to check prerequisites
check_prerequisites() {
    if [[ "$SKIP_VALIDATION" == "true" ]]; then
        warn "Skipping prerequisite validation"
        return 0
    fi

    log "Checking prerequisites..."

    # Check Azure CLI
    if ! command -v az &> /dev/null; then
        error "Azure CLI is not installed. Please install it from https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
        exit 1
    fi

    # Check Azure CLI version
    AZ_VERSION=$(az version --query '"azure-cli"' -o tsv 2>/dev/null || echo "unknown")
    info "Azure CLI version: $AZ_VERSION"

    # Check if logged in
    if ! az account show &> /dev/null; then
        error "You are not logged in to Azure. Please run 'az login' first."
        exit 1
    fi

    # Check subscription
    SUBSCRIPTION_ID=$(az account show --query id -o tsv)
    SUBSCRIPTION_NAME=$(az account show --query name -o tsv)
    info "Using subscription: $SUBSCRIPTION_NAME ($SUBSCRIPTION_ID)"

    # Check required Azure providers
    log "Checking Azure resource providers..."
    
    REQUIRED_PROVIDERS=(
        "Microsoft.MixedReality"
        "Microsoft.Storage"
        "Microsoft.Web"
    )

    for provider in "${REQUIRED_PROVIDERS[@]}"; do
        STATUS=$(az provider show --namespace "$provider" --query "registrationState" -o tsv 2>/dev/null || echo "NotRegistered")
        if [[ "$STATUS" != "Registered" ]]; then
            warn "Provider $provider is not registered. Registering..."
            az provider register --namespace "$provider" --no-wait
        else
            info "Provider $provider is registered"
        fi
    done

    # Check if jq is available (helpful for JSON parsing)
    if ! command -v jq &> /dev/null; then
        warn "jq is not installed. JSON parsing will be limited."
    fi

    # Validate location
    if ! az account list-locations --query "[?name=='$LOCATION']" | grep -q "$LOCATION"; then
        error "Location '$LOCATION' is not valid or available"
        exit 1
    fi

    # Check Mixed Reality service availability in region
    MR_LOCATIONS=$(az account list-locations --query "[?metadata.regionType=='Physical' && metadata.pairedRegion[0].name!=null].name" -o tsv)
    if ! echo "$MR_LOCATIONS" | grep -q "$LOCATION"; then
        warn "Mixed Reality services may not be available in '$LOCATION'. Consider using 'eastus' or 'westus2'."
    fi

    log "Prerequisites check completed successfully"
}

# Function to create resource group
create_resource_group() {
    log "Creating resource group: $RESOURCE_GROUP"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY-RUN] Would create resource group: $RESOURCE_GROUP in $LOCATION"
        return 0
    fi

    # Check if resource group already exists
    if az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        if [[ "$FORCE" == "true" ]]; then
            warn "Resource group $RESOURCE_GROUP already exists, continuing due to --force flag"
        else
            error "Resource group $RESOURCE_GROUP already exists. Use --force to continue or choose a different name."
            exit 1
        fi
    else
        az group create \
            --name "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --tags purpose=spatial-computing environment=demo cost-center=innovation deployment-script=true
        
        info "Resource group created successfully"
    fi
}

# Function to create storage account
create_storage_account() {
    log "Creating storage account: $STORAGE_ACCOUNT"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY-RUN] Would create storage account: $STORAGE_ACCOUNT"
        return 0
    fi

    # Check if storage account name is available
    if ! az storage account check-name --name "$STORAGE_ACCOUNT" --query nameAvailable -o tsv | grep -q "true"; then
        error "Storage account name '$STORAGE_ACCOUNT' is not available. Try with a different suffix."
        exit 1
    fi

    az storage account create \
        --name "$STORAGE_ACCOUNT" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --sku "$DEFAULT_STORAGE_SKU" \
        --kind StorageV2 \
        --access-tier Hot \
        --allow-blob-public-access false \
        --min-tls-version TLS1_2

    # Create blob container
    STORAGE_KEY=$(az storage account keys list \
        --resource-group "$RESOURCE_GROUP" \
        --account-name "$STORAGE_ACCOUNT" \
        --query '[0].value' -o tsv)

    az storage container create \
        --account-name "$STORAGE_ACCOUNT" \
        --account-key "$STORAGE_KEY" \
        --name "$BLOB_CONTAINER" \
        --public-access off

    info "Storage account and container created successfully"
}

# Function to create Azure Remote Rendering account
create_remote_rendering_account() {
    log "Creating Azure Remote Rendering account: $ARR_ACCOUNT_NAME"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY-RUN] Would create Remote Rendering account: $ARR_ACCOUNT_NAME"
        return 0
    fi

    # Check if Mixed Reality provider is registered
    PROVIDER_STATUS=$(az provider show --namespace Microsoft.MixedReality --query registrationState -o tsv)
    if [[ "$PROVIDER_STATUS" != "Registered" ]]; then
        warn "Microsoft.MixedReality provider not registered. Registering..."
        az provider register --namespace Microsoft.MixedReality --wait
    fi

    # Create Remote Rendering account
    az mixed-reality remote-rendering-account create \
        --name "$ARR_ACCOUNT_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --sku S1 \
        --tags purpose=spatial-computing environment=demo

    # Get account details
    ARR_ACCOUNT_ID=$(az mixed-reality remote-rendering-account show \
        --name "$ARR_ACCOUNT_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --query accountId -o tsv)

    ARR_ACCOUNT_DOMAIN=$(az mixed-reality remote-rendering-account show \
        --name "$ARR_ACCOUNT_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --query accountDomain -o tsv)

    info "Azure Remote Rendering account created successfully"
    info "Account ID: $ARR_ACCOUNT_ID"
    info "Account Domain: $ARR_ACCOUNT_DOMAIN"
}

# Function to create Azure Spatial Anchors account
create_spatial_anchors_account() {
    log "Creating Azure Spatial Anchors account: $ASA_ACCOUNT_NAME"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY-RUN] Would create Spatial Anchors account: $ASA_ACCOUNT_NAME"
        return 0
    fi

    # Create Spatial Anchors account
    az mixed-reality spatial-anchors-account create \
        --name "$ASA_ACCOUNT_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --sku S1 \
        --tags purpose=spatial-computing environment=demo

    # Get account details
    ASA_ACCOUNT_ID=$(az mixed-reality spatial-anchors-account show \
        --name "$ASA_ACCOUNT_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --query accountId -o tsv)

    ASA_ACCOUNT_DOMAIN=$(az mixed-reality spatial-anchors-account show \
        --name "$ASA_ACCOUNT_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --query accountDomain -o tsv)

    info "Azure Spatial Anchors account created successfully"
    info "Account ID: $ASA_ACCOUNT_ID"
    info "Account Domain: $ASA_ACCOUNT_DOMAIN"
}

# Function to create service principal
create_service_principal() {
    log "Creating service principal: $SP_NAME"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY-RUN] Would create service principal: $SP_NAME"
        return 0
    fi

    # Get subscription ID
    SUBSCRIPTION_ID=$(az account show --query id -o tsv)

    # Create service principal
    SP_DETAILS=$(az ad sp create-for-rbac \
        --name "$SP_NAME" \
        --role "Mixed Reality Administrator" \
        --scopes "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP" \
        --sdk-auth 2>/dev/null)

    if [[ $? -ne 0 ]]; then
        error "Failed to create service principal. You may need additional permissions."
        exit 1
    fi

    # Extract service principal details
    SP_CLIENT_ID=$(echo "$SP_DETAILS" | jq -r .clientId 2>/dev/null || echo "Unable to parse")
    SP_TENANT_ID=$(echo "$SP_DETAILS" | jq -r .tenantId 2>/dev/null || echo "Unable to parse")

    info "Service principal created successfully"
    info "Client ID: $SP_CLIENT_ID"
    info "Tenant ID: $SP_TENANT_ID"
}

# Function to upload sample 3D model
upload_sample_model() {
    log "Uploading sample 3D model"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY-RUN] Would upload sample 3D model"
        return 0
    fi

    # Create temporary directory for sample models
    TEMP_DIR=$(mktemp -d)
    cd "$TEMP_DIR"

    # Download sample 3D model
    if command -v curl &> /dev/null; then
        curl -L -o sample-box.gltf "https://github.com/KhronosGroup/glTF-Sample-Models/raw/master/2.0/Box/glTF/Box.gltf"
        curl -L -o Box0.bin "https://github.com/KhronosGroup/glTF-Sample-Models/raw/master/2.0/Box/glTF/Box0.bin"
    elif command -v wget &> /dev/null; then
        wget -O sample-box.gltf "https://github.com/KhronosGroup/glTF-Sample-Models/raw/master/2.0/Box/glTF/Box.gltf"
        wget -O Box0.bin "https://github.com/KhronosGroup/glTF-Sample-Models/raw/master/2.0/Box/glTF/Box0.bin"
    else
        warn "Neither curl nor wget found. Skipping sample model upload."
        return 0
    fi

    # Get storage account key
    STORAGE_KEY=$(az storage account keys list \
        --resource-group "$RESOURCE_GROUP" \
        --account-name "$STORAGE_ACCOUNT" \
        --query '[0].value' -o tsv)

    # Upload files to blob storage
    az storage blob upload \
        --account-name "$STORAGE_ACCOUNT" \
        --account-key "$STORAGE_KEY" \
        --container-name "$BLOB_CONTAINER" \
        --name "models/sample-box.gltf" \
        --file sample-box.gltf

    az storage blob upload \
        --account-name "$STORAGE_ACCOUNT" \
        --account-key "$STORAGE_KEY" \
        --container-name "$BLOB_CONTAINER" \
        --name "models/Box0.bin" \
        --file Box0.bin

    # Generate SAS token
    CONTAINER_SAS=$(az storage container generate-sas \
        --account-name "$STORAGE_ACCOUNT" \
        --account-key "$STORAGE_KEY" \
        --name "$BLOB_CONTAINER" \
        --permissions dlrw \
        --expiry "$(date -u -d '+1 day' +%Y-%m-%dT%H:%MZ 2>/dev/null || date -u -v+1d +%Y-%m-%dT%H:%MZ)" \
        -o tsv)

    # Clean up temporary directory
    cd "$SCRIPT_DIR"
    rm -rf "$TEMP_DIR"

    info "Sample 3D model uploaded successfully"
}

# Function to create configuration files
create_configuration_files() {
    log "Creating configuration files"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY-RUN] Would create configuration files"
        return 0
    fi

    # Create Unity configuration directory
    mkdir -p "$PROJECT_ROOT/unity-spatial-app/Assets/StreamingAssets"

    # Create Azure configuration file
    cat > "$PROJECT_ROOT/unity-spatial-app/Assets/StreamingAssets/AzureConfig.json" << EOF
{
    "RemoteRenderingSettings": {
        "AccountId": "$ARR_ACCOUNT_ID",
        "AccountDomain": "$ARR_ACCOUNT_DOMAIN",
        "AccountKey": "REPLACE_WITH_ACCOUNT_KEY",
        "AuthenticationToken": "",
        "PreferredSessionSize": "Standard"
    },
    "SpatialAnchorsSettings": {
        "AccountId": "$ASA_ACCOUNT_ID",
        "AccountDomain": "$ASA_ACCOUNT_DOMAIN",
        "AccountKey": "REPLACE_WITH_ACCOUNT_KEY",
        "AccessToken": ""
    },
    "ApplicationSettings": {
        "MaxConcurrentSessions": 1,
        "SessionTimeoutMinutes": 30,
        "AutoStartSession": true,
        "EnableSpatialMapping": true,
        "EnableHandTracking": true
    }
}
EOF

    # Create spatial synchronization configuration
    cat > "$PROJECT_ROOT/spatial-sync-config.json" << EOF
{
    "SpatialSynchronization": {
        "CoordinateSystem": "WorldAnchor",
        "SynchronizationMode": "CloudBased",
        "UpdateFrequencyHz": 30,
        "PredictionBufferMs": 100,
        "InterpolationEnabled": true,
        "NetworkCompensation": {
            "LatencyCompensation": true,
            "JitterReduction": true,
            "PacketLossRecovery": true
        }
    },
    "DeviceCapabilities": {
        "HoloLens": {
            "SpatialMapping": true,
            "HandTracking": true,
            "EyeTracking": true,
            "VoiceCommands": true
        },
        "Mobile": {
            "ARCore": true,
            "ARKit": true,
            "PlaneDetection": true,
            "TouchInput": true
        }
    },
    "CollaborationSettings": {
        "MaxConcurrentUsers": 8,
        "SpatialAnchorSharing": true,
        "GestureSharing": true,
        "VoiceSharing": false
    }
}
EOF

    info "Configuration files created successfully"
}

# Function to save deployment information
save_deployment_info() {
    log "Saving deployment information"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY-RUN] Would save deployment information"
        return 0
    fi

    # Create deployment info file
    cat > "$SCRIPT_DIR/deployment-info.env" << EOF
# Deployment Information
# Generated on: $(date)
# Resource Group: $RESOURCE_GROUP
# Location: $LOCATION
# Suffix: $SUFFIX

# Azure Resources
RESOURCE_GROUP="$RESOURCE_GROUP"
LOCATION="$LOCATION"
SUFFIX="$SUFFIX"

# Remote Rendering
ARR_ACCOUNT_NAME="$ARR_ACCOUNT_NAME"
ARR_ACCOUNT_ID="$ARR_ACCOUNT_ID"
ARR_ACCOUNT_DOMAIN="$ARR_ACCOUNT_DOMAIN"

# Spatial Anchors
ASA_ACCOUNT_NAME="$ASA_ACCOUNT_NAME"
ASA_ACCOUNT_ID="$ASA_ACCOUNT_ID"
ASA_ACCOUNT_DOMAIN="$ASA_ACCOUNT_DOMAIN"

# Storage
STORAGE_ACCOUNT="$STORAGE_ACCOUNT"
BLOB_CONTAINER="$BLOB_CONTAINER"

# Service Principal
SP_NAME="$SP_NAME"
SP_CLIENT_ID="$SP_CLIENT_ID"
SP_TENANT_ID="$SP_TENANT_ID"

# Subscription
SUBSCRIPTION_ID="$SUBSCRIPTION_ID"
EOF

    info "Deployment information saved to: $SCRIPT_DIR/deployment-info.env"
}

# Function to display post-deployment information
display_post_deployment_info() {
    log "Deployment completed successfully!"
    
    echo ""
    echo "=== Deployment Summary ==="
    echo "Resource Group: $RESOURCE_GROUP"
    echo "Location: $LOCATION"
    echo "Suffix: $SUFFIX"
    echo ""
    echo "=== Azure Remote Rendering ==="
    echo "Account Name: $ARR_ACCOUNT_NAME"
    echo "Account ID: $ARR_ACCOUNT_ID"
    echo "Account Domain: $ARR_ACCOUNT_DOMAIN"
    echo ""
    echo "=== Azure Spatial Anchors ==="
    echo "Account Name: $ASA_ACCOUNT_NAME"
    echo "Account ID: $ASA_ACCOUNT_ID"
    echo "Account Domain: $ASA_ACCOUNT_DOMAIN"
    echo ""
    echo "=== Storage Account ==="
    echo "Storage Account: $STORAGE_ACCOUNT"
    echo "Blob Container: $BLOB_CONTAINER"
    echo ""
    echo "=== Service Principal ==="
    echo "Name: $SP_NAME"
    echo "Client ID: $SP_CLIENT_ID"
    echo "Tenant ID: $SP_TENANT_ID"
    echo ""
    echo "=== Next Steps ==="
    echo "1. Configure Unity project with the Azure settings"
    echo "2. Replace placeholder account keys in configuration files"
    echo "3. Deploy your spatial computing application"
    echo "4. Test with HoloLens 2 or Mixed Reality simulator"
    echo ""
    echo "=== Important Notes ==="
    echo "⚠️  Azure Remote Rendering will be retired on September 30, 2025"
    echo "⚠️  Azure Spatial Anchors will be retired on November 20, 2024"
    echo "💡 Consider migrating to Azure Object Anchors for future implementations"
    echo ""
    echo "=== Cleanup ==="
    echo "To remove all resources, run: $SCRIPT_DIR/destroy.sh"
    echo ""
}

# Main deployment function
main() {
    log "Starting Azure Spatial Computing Application deployment"
    
    # Check prerequisites
    check_prerequisites
    
    # Create resources
    create_resource_group
    create_storage_account
    create_remote_rendering_account
    create_spatial_anchors_account
    create_service_principal
    upload_sample_model
    create_configuration_files
    
    # Save deployment info
    save_deployment_info
    
    # Display summary
    display_post_deployment_info
}

# Trap to handle script interruption
trap 'error "Deployment interrupted. Some resources may have been created."; exit 1' INT TERM

# Run main function
main "$@"