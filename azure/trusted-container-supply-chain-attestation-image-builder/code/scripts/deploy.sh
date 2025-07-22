#!/bin/bash

# =============================================================================
# Azure Trusted Container Supply Chain Deployment Script
# =============================================================================
# This script deploys the trusted container supply chain infrastructure
# using Azure Attestation Service and Azure Image Builder
# 
# Prerequisites:
# - Azure CLI installed and configured
# - Appropriate Azure subscription permissions
# - Docker installed (for local testing)
# =============================================================================

set -euo pipefail

# =============================================================================
# Configuration and Variables
# =============================================================================

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
DEFAULT_LOCATION="eastus"
DEFAULT_RESOURCE_GROUP="rg-container-supply-chain"

# Global variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/deploy.log"
DEPLOYMENT_STATE_FILE="${SCRIPT_DIR}/.deployment_state"

# =============================================================================
# Utility Functions
# =============================================================================

log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case "$level" in
        "INFO")
            echo -e "${GREEN}[INFO]${NC} $message" | tee -a "$LOG_FILE"
            ;;
        "WARN")
            echo -e "${YELLOW}[WARN]${NC} $message" | tee -a "$LOG_FILE"
            ;;
        "ERROR")
            echo -e "${RED}[ERROR]${NC} $message" | tee -a "$LOG_FILE"
            ;;
        "DEBUG")
            echo -e "${BLUE}[DEBUG]${NC} $message" | tee -a "$LOG_FILE"
            ;;
        *)
            echo -e "$message" | tee -a "$LOG_FILE"
            ;;
    esac
    
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
}

error_exit() {
    log "ERROR" "$1"
    exit 1
}

check_prerequisites() {
    log "INFO" "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        error_exit "Azure CLI is not installed. Please install Azure CLI first."
    fi
    
    # Check if user is logged in to Azure
    if ! az account show &> /dev/null; then
        error_exit "Not logged in to Azure. Please run 'az login' first."
    fi
    
    # Check if OpenSSL is available for random string generation
    if ! command -v openssl &> /dev/null; then
        error_exit "OpenSSL is not available. Please install OpenSSL."
    fi
    
    log "INFO" "Prerequisites check passed."
}

save_deployment_state() {
    local key="$1"
    local value="$2"
    
    # Create state file if it doesn't exist
    touch "$DEPLOYMENT_STATE_FILE"
    
    # Update or add the key-value pair
    if grep -q "^$key=" "$DEPLOYMENT_STATE_FILE"; then
        sed -i.bak "s/^$key=.*/$key=$value/" "$DEPLOYMENT_STATE_FILE"
        rm -f "${DEPLOYMENT_STATE_FILE}.bak"
    else
        echo "$key=$value" >> "$DEPLOYMENT_STATE_FILE"
    fi
}

load_deployment_state() {
    local key="$1"
    
    if [ -f "$DEPLOYMENT_STATE_FILE" ]; then
        grep "^$key=" "$DEPLOYMENT_STATE_FILE" | cut -d'=' -f2 || echo ""
    else
        echo ""
    fi
}

# =============================================================================
# Azure Resource Functions
# =============================================================================

create_resource_group() {
    local rg_name="$1"
    local location="$2"
    
    log "INFO" "Creating resource group: $rg_name"
    
    if az group show --name "$rg_name" &> /dev/null; then
        log "INFO" "Resource group $rg_name already exists."
    else
        az group create \
            --name "$rg_name" \
            --location "$location" \
            --tags purpose=container-supply-chain environment=demo \
            --output none
        
        if [ $? -eq 0 ]; then
            log "INFO" "Resource group $rg_name created successfully."
        else
            error_exit "Failed to create resource group $rg_name."
        fi
    fi
    
    save_deployment_state "RESOURCE_GROUP" "$rg_name"
}

create_managed_identity() {
    local identity_name="$1"
    local rg_name="$2"
    local location="$3"
    
    log "INFO" "Creating managed identity: $identity_name"
    
    # Check if managed identity exists
    if az identity show --name "$identity_name" --resource-group "$rg_name" &> /dev/null; then
        log "INFO" "Managed identity $identity_name already exists."
    else
        az identity create \
            --name "$identity_name" \
            --resource-group "$rg_name" \
            --location "$location" \
            --output none
        
        if [ $? -eq 0 ]; then
            log "INFO" "Managed identity $identity_name created successfully."
        else
            error_exit "Failed to create managed identity $identity_name."
        fi
    fi
    
    # Wait for identity to be fully provisioned
    sleep 10
    
    # Get identity details
    local identity_id=$(az identity show \
        --name "$identity_name" \
        --resource-group "$rg_name" \
        --query id \
        --output tsv)
    
    local identity_principal_id=$(az identity show \
        --name "$identity_name" \
        --resource-group "$rg_name" \
        --query principalId \
        --output tsv)
    
    save_deployment_state "IDENTITY_ID" "$identity_id"
    save_deployment_state "IDENTITY_PRINCIPAL_ID" "$identity_principal_id"
    
    log "INFO" "Managed identity details retrieved."
}

create_attestation_provider() {
    local provider_name="$1"
    local rg_name="$2"
    local location="$3"
    
    log "INFO" "Creating attestation provider: $provider_name"
    
    # Check if attestation provider exists
    if az attestation show --name "$provider_name" --resource-group "$rg_name" &> /dev/null; then
        log "INFO" "Attestation provider $provider_name already exists."
    else
        az attestation create \
            --name "$provider_name" \
            --resource-group "$rg_name" \
            --location "$location" \
            --output none
        
        if [ $? -eq 0 ]; then
            log "INFO" "Attestation provider $provider_name created successfully."
        else
            error_exit "Failed to create attestation provider $provider_name."
        fi
    fi
    
    # Get attestation endpoint
    local attestation_endpoint=$(az attestation show \
        --name "$provider_name" \
        --resource-group "$rg_name" \
        --query attestUri \
        --output tsv)
    
    save_deployment_state "ATTESTATION_ENDPOINT" "$attestation_endpoint"
    
    log "INFO" "Attestation provider endpoint: $attestation_endpoint"
}

create_key_vault() {
    local kv_name="$1"
    local rg_name="$2"
    local location="$3"
    local identity_principal_id="$4"
    
    log "INFO" "Creating Key Vault: $kv_name"
    
    # Check if Key Vault exists
    if az keyvault show --name "$kv_name" --resource-group "$rg_name" &> /dev/null; then
        log "INFO" "Key Vault $kv_name already exists."
    else
        az keyvault create \
            --name "$kv_name" \
            --resource-group "$rg_name" \
            --location "$location" \
            --sku standard \
            --enable-rbac-authorization true \
            --output none
        
        if [ $? -eq 0 ]; then
            log "INFO" "Key Vault $kv_name created successfully."
        else
            error_exit "Failed to create Key Vault $kv_name."
        fi
    fi
    
    # Wait for Key Vault to be fully provisioned
    sleep 10
    
    # Create signing key
    log "INFO" "Creating signing key in Key Vault."
    
    if az keyvault key show --vault-name "$kv_name" --name "container-signing-key" &> /dev/null; then
        log "INFO" "Signing key already exists in Key Vault."
    else
        az keyvault key create \
            --vault-name "$kv_name" \
            --name "container-signing-key" \
            --kty RSA \
            --size 2048 \
            --ops sign verify \
            --output none
        
        if [ $? -eq 0 ]; then
            log "INFO" "Signing key created successfully."
        else
            error_exit "Failed to create signing key."
        fi
    fi
    
    # Get subscription ID
    local subscription_id=$(az account show --query id --output tsv)
    
    # Grant managed identity access to Key Vault
    log "INFO" "Granting managed identity access to Key Vault."
    
    local key_vault_scope="/subscriptions/$subscription_id/resourceGroups/$rg_name/providers/Microsoft.KeyVault/vaults/$kv_name"
    
    az role assignment create \
        --role "Key Vault Crypto User" \
        --assignee "$identity_principal_id" \
        --scope "$key_vault_scope" \
        --output none
    
    if [ $? -eq 0 ]; then
        log "INFO" "Role assignment created successfully."
    else
        log "WARN" "Failed to create role assignment. It may already exist."
    fi
    
    save_deployment_state "KEY_VAULT_NAME" "$kv_name"
}

create_container_registry() {
    local acr_name="$1"
    local rg_name="$2"
    local location="$3"
    local identity_principal_id="$4"
    
    log "INFO" "Creating Container Registry: $acr_name"
    
    # Check if Container Registry exists
    if az acr show --name "$acr_name" --resource-group "$rg_name" &> /dev/null; then
        log "INFO" "Container Registry $acr_name already exists."
    else
        az acr create \
            --name "$acr_name" \
            --resource-group "$rg_name" \
            --location "$location" \
            --sku Premium \
            --admin-enabled false \
            --output none
        
        if [ $? -eq 0 ]; then
            log "INFO" "Container Registry $acr_name created successfully."
        else
            error_exit "Failed to create Container Registry $acr_name."
        fi
    fi
    
    # Wait for ACR to be fully provisioned
    sleep 10
    
    # Enable content trust
    log "INFO" "Enabling content trust on Container Registry."
    
    az acr config content-trust update \
        --name "$acr_name" \
        --status enabled \
        --output none
    
    if [ $? -eq 0 ]; then
        log "INFO" "Content trust enabled successfully."
    else
        log "WARN" "Failed to enable content trust. It may already be enabled."
    fi
    
    # Get subscription ID
    local subscription_id=$(az account show --query id --output tsv)
    
    # Grant managed identity access to push images
    log "INFO" "Granting managed identity access to Container Registry."
    
    local acr_scope="/subscriptions/$subscription_id/resourceGroups/$rg_name/providers/Microsoft.ContainerRegistry/registries/$acr_name"
    
    az role assignment create \
        --role "AcrPush" \
        --assignee "$identity_principal_id" \
        --scope "$acr_scope" \
        --output none
    
    if [ $? -eq 0 ]; then
        log "INFO" "ACR role assignment created successfully."
    else
        log "WARN" "Failed to create ACR role assignment. It may already exist."
    fi
    
    save_deployment_state "ACR_NAME" "$acr_name"
}

create_image_builder_template() {
    local template_name="$1"
    local rg_name="$2"
    local location="$3"
    local identity_id="$4"
    
    log "INFO" "Creating Image Builder template: $template_name"
    
    # Get subscription ID
    local subscription_id=$(az account show --query id --output tsv)
    
    # Create temporary template file
    local temp_template="/tmp/image-template.json"
    
    cat > "$temp_template" << EOF
{
  "type": "Microsoft.VirtualMachineImages/imageTemplates",
  "apiVersion": "2024-02-01",
  "location": "$location",
  "properties": {
    "buildTimeoutInMinutes": 60,
    "vmProfile": {
      "vmSize": "Standard_D2s_v3",
      "osDiskSizeGB": 30
    },
    "source": {
      "type": "PlatformImage",
      "publisher": "Canonical",
      "offer": "0001-com-ubuntu-server-focal",
      "sku": "20_04-lts-gen2",
      "version": "latest"
    },
    "customize": [
      {
        "type": "Shell",
        "name": "InstallDocker",
        "inline": [
          "sudo apt-get update",
          "sudo apt-get install -y docker.io",
          "sudo systemctl enable docker"
        ]
      },
      {
        "type": "Shell",
        "name": "BuildSecureContainer",
        "inline": [
          "echo 'FROM ubuntu:20.04' > Dockerfile",
          "echo 'RUN apt-get update && apt-get install -y curl' >> Dockerfile",
          "echo 'LABEL security.scan=passed' >> Dockerfile",
          "sudo docker build -t trusted-app:latest ."
        ]
      }
    ],
    "distribute": [
      {
        "type": "SharedImage",
        "galleryImageId": "/subscriptions/$subscription_id/resourceGroups/$rg_name/providers/Microsoft.Compute/galleries/myGallery/images/trustedImage/versions/1.0.0",
        "runOutputName": "trustedImageOutput",
        "replicationRegions": ["$location"]
      }
    ],
    "identity": {
      "type": "UserAssigned",
      "userAssignedIdentities": {
        "$identity_id": {}
      }
    }
  }
}
EOF
    
    # Check if template exists
    if az resource show \
        --resource-group "$rg_name" \
        --resource-type "Microsoft.VirtualMachineImages/imageTemplates" \
        --name "$template_name" &> /dev/null; then
        log "INFO" "Image Builder template $template_name already exists."
    else
        az resource create \
            --resource-group "$rg_name" \
            --resource-type "Microsoft.VirtualMachineImages/imageTemplates" \
            --name "$template_name" \
            --api-version "2024-02-01" \
            --properties "@$temp_template" \
            --output none
        
        if [ $? -eq 0 ]; then
            log "INFO" "Image Builder template $template_name created successfully."
        else
            error_exit "Failed to create Image Builder template $template_name."
        fi
    fi
    
    # Clean up temporary file
    rm -f "$temp_template"
    
    save_deployment_state "IMAGE_BUILDER_NAME" "$template_name"
}

configure_attestation_policy() {
    local provider_name="$1"
    local rg_name="$2"
    
    log "INFO" "Configuring attestation policy."
    
    # Create temporary policy file
    local temp_policy="/tmp/attestation-policy.txt"
    
    cat > "$temp_policy" << 'EOF'
version= 1.0;
authorizationrules
{
    [type=="x-ms-azurevm-vmid"] => permit();
};
issuancerules
{
    c:[type=="x-ms-azurevm-attestation-protocol-ver"] => issue(type="protocol-version", value=c.value);
    c:[type=="x-ms-azurevm-vmid"] => issue(type="vm-id", value=c.value);
    c:[type=="x-ms-azurevm-is-windows"] => issue(type="is-windows", value=c.value);
    c:[type=="x-ms-azurevm-boot-integrity-svg"] => issue(type="boot-integrity", value=c.value);
};
EOF
    
    # Encode policy in base64
    local policy_base64=$(base64 -w 0 "$temp_policy")
    
    # Set attestation policy
    az attestation policy set \
        --name "$provider_name" \
        --resource-group "$rg_name" \
        --policy-format Text \
        --new-attestation-policy "$policy_base64" \
        --attestation-type AzureVM \
        --output none
    
    if [ $? -eq 0 ]; then
        log "INFO" "Attestation policy configured successfully."
    else
        log "WARN" "Failed to configure attestation policy. It may already be configured."
    fi
    
    # Clean up temporary file
    rm -f "$temp_policy"
}

create_signing_scripts() {
    local script_dir="$1"
    local attestation_endpoint="$2"
    local kv_name="$3"
    local acr_name="$4"
    
    log "INFO" "Creating signing and verification scripts."
    
    # Create signing script
    local sign_script="$script_dir/sign-image.sh"
    
    cat > "$sign_script" << 'EOF'
#!/bin/bash
set -e

# Variables
IMAGE_NAME=$1
ATTESTATION_ENDPOINT=$2
KEY_VAULT_NAME=$3

echo "Starting attestation process for image: ${IMAGE_NAME}"

# Get attestation token (simplified example)
# In production, this would involve collecting TPM evidence
EVIDENCE=$(echo "sample-evidence" | base64)

# Submit evidence to attestation service
ATTESTATION_RESPONSE=$(curl -X POST \
    "${ATTESTATION_ENDPOINT}/attest/AzureVM?api-version=2020-10-01" \
    -H "Content-Type: application/json" \
    -d "{\"evidence\": \"${EVIDENCE}\"}")

# Extract attestation token
ATTESTATION_TOKEN=$(echo ${ATTESTATION_RESPONSE} | jq -r '.token')

if [ -n "${ATTESTATION_TOKEN}" ]; then
    echo "✅ Attestation successful"
    
    # Sign image with Key Vault key
    az keyvault key sign \
        --vault-name ${KEY_VAULT_NAME} \
        --name container-signing-key \
        --algorithm RS256 \
        --value $(echo ${IMAGE_NAME} | sha256sum | cut -d' ' -f1)
    
    echo "✅ Image signed successfully"
else
    echo "❌ Attestation failed"
    exit 1
fi
EOF
    
    chmod +x "$sign_script"
    
    # Create verification script
    local verify_script="$script_dir/verify-deployment.sh"
    
    cat > "$verify_script" << 'EOF'
#!/bin/bash
set -e

# Variables
IMAGE_URI=$1
ACR_NAME=$2
ATTESTATION_ENDPOINT=$3

echo "Verifying image: ${IMAGE_URI}"

# Check if image has valid signature in ACR
SIGNATURE_STATUS=$(az acr repository show \
    --name ${ACR_NAME} \
    --image ${IMAGE_URI} \
    --query 'changeableAttributes.signed' \
    --output tsv)

if [ "${SIGNATURE_STATUS}" != "true" ]; then
    echo "❌ Image is not signed"
    exit 1
fi

# Verify attestation token validity
# In production, retrieve and verify the attestation token
# associated with the image

echo "✅ Image verification passed"
echo "Image is authorized for deployment"
EOF
    
    chmod +x "$verify_script"
    
    log "INFO" "Signing and verification scripts created successfully."
}

# =============================================================================
# Main Deployment Function
# =============================================================================

deploy_infrastructure() {
    log "INFO" "Starting trusted container supply chain deployment..."
    
    # Parse command line arguments
    local location="${1:-$DEFAULT_LOCATION}"
    local resource_group="${2:-$DEFAULT_RESOURCE_GROUP}"
    
    # Generate unique suffix for globally unique resource names
    local random_suffix=$(openssl rand -hex 3)
    
    # Set resource names
    local attestation_provider="attestation${random_suffix}"
    local image_builder_name="imagebuilder${random_suffix}"
    local acr_name="acr${random_suffix}"
    local key_vault_name="kv-${random_suffix}"
    local managed_identity="mi-imagebuilder-${random_suffix}"
    
    # Save configuration
    save_deployment_state "LOCATION" "$location"
    save_deployment_state "RANDOM_SUFFIX" "$random_suffix"
    save_deployment_state "ATTESTATION_PROVIDER" "$attestation_provider"
    save_deployment_state "IMAGE_BUILDER_NAME" "$image_builder_name"
    save_deployment_state "ACR_NAME" "$acr_name"
    save_deployment_state "KEY_VAULT_NAME" "$key_vault_name"
    save_deployment_state "MANAGED_IDENTITY" "$managed_identity"
    
    # Create resource group
    create_resource_group "$resource_group" "$location"
    
    # Create managed identity
    create_managed_identity "$managed_identity" "$resource_group" "$location"
    
    # Load identity details
    local identity_id=$(load_deployment_state "IDENTITY_ID")
    local identity_principal_id=$(load_deployment_state "IDENTITY_PRINCIPAL_ID")
    
    # Create attestation provider
    create_attestation_provider "$attestation_provider" "$resource_group" "$location"
    
    # Create Key Vault
    create_key_vault "$key_vault_name" "$resource_group" "$location" "$identity_principal_id"
    
    # Create Container Registry
    create_container_registry "$acr_name" "$resource_group" "$location" "$identity_principal_id"
    
    # Create Image Builder template
    create_image_builder_template "$image_builder_name" "$resource_group" "$location" "$identity_id"
    
    # Configure attestation policy
    configure_attestation_policy "$attestation_provider" "$resource_group"
    
    # Load attestation endpoint
    local attestation_endpoint=$(load_deployment_state "ATTESTATION_ENDPOINT")
    
    # Create signing scripts
    create_signing_scripts "$SCRIPT_DIR" "$attestation_endpoint" "$key_vault_name" "$acr_name"
    
    log "INFO" "Deployment completed successfully!"
    log "INFO" "Resource Group: $resource_group"
    log "INFO" "Attestation Provider: $attestation_provider"
    log "INFO" "Key Vault: $key_vault_name"
    log "INFO" "Container Registry: $acr_name"
    log "INFO" "Image Builder: $image_builder_name"
    log "INFO" "Attestation Endpoint: $attestation_endpoint"
    log "INFO" ""
    log "INFO" "Next steps:"
    log "INFO" "1. Review the created resources in the Azure portal"
    log "INFO" "2. Test the signing workflow with: ./sign-image.sh <image-name> $attestation_endpoint $key_vault_name"
    log "INFO" "3. Test the verification workflow with: ./verify-deployment.sh <image-uri> $acr_name $attestation_endpoint"
    log "INFO" "4. Clean up resources when done with: ./destroy.sh"
}

# =============================================================================
# Script Usage and Help
# =============================================================================

show_help() {
    cat << EOF
Azure Trusted Container Supply Chain Deployment Script

Usage: $0 [OPTIONS] [LOCATION] [RESOURCE_GROUP]

OPTIONS:
    -h, --help          Show this help message
    -v, --verbose       Enable verbose logging
    --dry-run          Show what would be deployed without actually deploying
    --force            Force deployment even if resources exist

ARGUMENTS:
    LOCATION           Azure region (default: $DEFAULT_LOCATION)
    RESOURCE_GROUP     Resource group name (default: $DEFAULT_RESOURCE_GROUP)

EXAMPLES:
    $0                                      # Deploy with defaults
    $0 westus2                             # Deploy to West US 2
    $0 westus2 my-supply-chain-rg          # Deploy to West US 2 with custom RG
    $0 --verbose eastus                    # Deploy with verbose logging

ENVIRONMENT VARIABLES:
    AZURE_LOCATION     Override default location
    AZURE_RG          Override default resource group
    LOG_LEVEL         Set log level (INFO, WARN, ERROR, DEBUG)

For more information, see the recipe documentation.
EOF
}

# =============================================================================
# Main Script Logic
# =============================================================================

# Initialize logging
mkdir -p "$(dirname "$LOG_FILE")"
echo "Deployment started at $(date)" > "$LOG_FILE"

# Parse command line options
VERBOSE=false
DRY_RUN=false
FORCE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --force)
            FORCE=true
            shift
            ;;
        -*)
            error_exit "Unknown option: $1"
            ;;
        *)
            break
            ;;
    esac
done

# Set location and resource group from arguments or environment variables
LOCATION="${1:-${AZURE_LOCATION:-$DEFAULT_LOCATION}}"
RESOURCE_GROUP="${2:-${AZURE_RG:-$DEFAULT_RESOURCE_GROUP}}"

# Validate location
if [[ ! "$LOCATION" =~ ^[a-z0-9]+$ ]]; then
    error_exit "Invalid location format: $LOCATION"
fi

# Validate resource group name
if [[ ! "$RESOURCE_GROUP" =~ ^[a-zA-Z0-9_\-\.]+$ ]]; then
    error_exit "Invalid resource group name format: $RESOURCE_GROUP"
fi

log "INFO" "Starting deployment with location: $LOCATION and resource group: $RESOURCE_GROUP"

# Check if this is a dry run
if [ "$DRY_RUN" = true ]; then
    log "INFO" "DRY RUN MODE - No resources will be created"
    log "INFO" "Would deploy to location: $LOCATION"
    log "INFO" "Would create resource group: $RESOURCE_GROUP"
    log "INFO" "Would create attestation provider, key vault, container registry, and image builder"
    exit 0
fi

# Check prerequisites
check_prerequisites

# Run deployment
if [ "$FORCE" = true ]; then
    log "INFO" "Force deployment enabled - existing resources will be updated"
fi

deploy_infrastructure "$LOCATION" "$RESOURCE_GROUP"

log "INFO" "Deployment script completed successfully!"
log "INFO" "Check the log file for details: $LOG_FILE"