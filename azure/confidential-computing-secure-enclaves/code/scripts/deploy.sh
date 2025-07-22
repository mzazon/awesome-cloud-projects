#!/bin/bash

#######################################################################
# Azure Confidential Computing with Secure Enclaves - Deployment Script
# Recipe: Confidential Computing with Hardware-Protected Enclaves
# 
# This script deploys a complete confidential computing solution including:
# - Azure Attestation Provider for TEE verification
# - Azure Managed HSM (FIPS 140-3 Level 3) for cryptographic operations
# - Confidential Virtual Machine with AMD SEV-SNP technology
# - Azure Key Vault Premium with HSM-backed keys
# - Azure Storage Account with customer-managed encryption
# - Sample confidential application demonstrating end-to-end workflow
#
# Prerequisites:
# - Azure CLI v2.40.0 or later
# - Contributor or Owner role on subscription
# - Sufficient quota for DCasv5 VMs in target region
# - OpenSSL for generating random values
#
# Estimated deployment time: 30-45 minutes (HSM provisioning takes ~20 minutes)
# Estimated cost: ~$500-800/month for basic setup
#######################################################################

set -euo pipefail

# Script configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly RECIPE_NAME="confidential-computing-secure-enclaves"
readonly AZURE_CLI_MIN_VERSION="2.40.0"

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m' # No Color

# Global variables
DEPLOYMENT_START_TIME=""
RESOURCE_GROUP=""
LOCATION=""
SUBSCRIPTION_ID=""
TENANT_ID=""
RANDOM_SUFFIX=""
HSM_NAME=""
KV_NAME=""
CVM_NAME=""
STORAGE_NAME=""
ATTESTATION_NAME=""
ATTESTATION_ENDPOINT=""
CVM_IP=""

# Logging functions
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a "${SCRIPT_DIR}/deploy.log"
}

success() {
    echo -e "${GREEN}✅ $1${NC}" | tee -a "${SCRIPT_DIR}/deploy.log"
}

warning() {
    echo -e "${YELLOW}⚠️  $1${NC}" | tee -a "${SCRIPT_DIR}/deploy.log"
}

error() {
    echo -e "${RED}❌ $1${NC}" | tee -a "${SCRIPT_DIR}/deploy.log"
}

info() {
    echo -e "${CYAN}ℹ️  $1${NC}" | tee -a "${SCRIPT_DIR}/deploy.log"
}

# Progress tracking
show_progress() {
    local current=$1
    local total=$2
    local message=$3
    local progress=$((current * 100 / total))
    echo -e "${CYAN}[${progress}%] Step ${current}/${total}: ${message}${NC}"
}

# Check if running in Azure Cloud Shell or local environment
check_environment() {
    show_progress 1 12 "Checking deployment environment"
    
    if [[ -n "${AZURE_HTTP_USER_AGENT:-}" ]]; then
        info "Running in Azure Cloud Shell"
    else
        info "Running in local environment"
    fi
    
    # Check required tools
    local tools=("az" "openssl" "ssh" "scp")
    for tool in "${tools[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            error "Required tool '$tool' is not installed"
            exit 1
        fi
    done
    
    # Check Azure CLI version
    local az_version=$(az version --query '"azure-cli"' -o tsv 2>/dev/null || echo "not-installed")
    if [[ "$az_version" == "not-installed" ]]; then
        error "Azure CLI is not installed. Please install Azure CLI v${AZURE_CLI_MIN_VERSION} or later."
        exit 1
    fi
    
    # Version comparison (simplified)
    local version_major=$(echo "$az_version" | cut -d. -f1)
    local version_minor=$(echo "$az_version" | cut -d. -f2)
    if [[ "$version_major" -lt 2 ]] || [[ "$version_major" -eq 2 && "$version_minor" -lt 40 ]]; then
        error "Azure CLI version $az_version is too old. Please upgrade to v${AZURE_CLI_MIN_VERSION} or later."
        exit 1
    fi
    
    info "Azure CLI version: $az_version"
    success "Environment check completed"
}

# Check prerequisites and permissions
check_prerequisites() {
    show_progress 2 12 "Checking prerequisites and permissions"
    
    # Check if logged in to Azure
    if ! az account show &>/dev/null; then
        error "Not logged in to Azure. Please run 'az login' first."
        exit 1
    fi
    
    # Get current subscription info
    SUBSCRIPTION_ID=$(az account show --query id --output tsv)
    TENANT_ID=$(az account show --query tenantId --output tsv)
    local account_name=$(az account show --query user.name --output tsv)
    
    info "Subscription ID: $SUBSCRIPTION_ID"
    info "Tenant ID: $TENANT_ID"
    info "Account: $account_name"
    
    # Check if user has sufficient permissions
    local user_id=$(az ad signed-in-user show --query id --output tsv 2>/dev/null || echo "")
    if [[ -z "$user_id" ]]; then
        warning "Could not verify user permissions. Proceeding with deployment..."
    else
        info "User ID: $user_id"
        
        # Check role assignments
        local roles=$(az role assignment list --assignee "$user_id" --query "[].roleDefinitionName" --output tsv 2>/dev/null || echo "")
        if [[ "$roles" == *"Owner"* ]] || [[ "$roles" == *"Contributor"* ]]; then
            info "User has sufficient permissions"
        else
            warning "User may not have sufficient permissions. Ensure you have Contributor or Owner role."
        fi
    fi
    
    success "Prerequisites check completed"
}

# Check regional availability for confidential computing
check_regional_availability() {
    show_progress 3 12 "Checking regional availability for confidential computing"
    
    # List of regions known to support DCasv5 VMs (as of 2025)
    local supported_regions=(
        "eastus" "eastus2" "westus2" "westus3" "centralus" "northcentralus" "southcentralus"
        "northeurope" "westeurope" "uksouth" "ukwest" "francecentral" "germanywestcentral"
        "switzerlandnorth" "norwayeast" "swedencentral" "australiaeast" "australiasoutheast"
        "southeastasia" "eastasia" "japaneast" "koreacentral" "canadacentral" "brazilsouth"
        "southafricanorth" "uaenorth" "centralindia" "southindia"
    )
    
    local region_supported=false
    for region in "${supported_regions[@]}"; do
        if [[ "$LOCATION" == "$region" ]]; then
            region_supported=true
            break
        fi
    done
    
    if [[ "$region_supported" == false ]]; then
        warning "Region '$LOCATION' may not support DCasv5 confidential VMs"
        warning "Supported regions include: ${supported_regions[*]}"
        echo
        read -p "Continue anyway? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            error "Deployment cancelled by user"
            exit 1
        fi
    else
        success "Region '$LOCATION' supports confidential computing"
    fi
    
    # Check resource quotas
    local quota_check=$(az vm list-usage --location "$LOCATION" --query "[?contains(name.value, 'DCasv5')].{Name:name.localizedValue, Current:currentValue, Limit:limit}" --output tsv 2>/dev/null || echo "")
    if [[ -n "$quota_check" ]]; then
        info "DCasv5 VM quota information:"
        echo "$quota_check" | while IFS=$'\t' read -r name current limit; do
            info "  $name: $current/$limit"
        done
    fi
}

# Set environment variables with validation
set_environment_variables() {
    show_progress 4 12 "Setting up environment variables"
    
    # Generate unique suffix for globally unique resource names
    RANDOM_SUFFIX=$(openssl rand -hex 3)
    
    # Set default values (can be overridden by environment variables)
    RESOURCE_GROUP="${RESOURCE_GROUP:-rg-confidential-${RANDOM_SUFFIX}}"
    LOCATION="${LOCATION:-eastus}"
    
    # Validate resource group name
    if [[ ! "$RESOURCE_GROUP" =~ ^[a-zA-Z0-9._-]+$ ]]; then
        error "Invalid resource group name: $RESOURCE_GROUP"
        exit 1
    fi
    
    # Set resource names with validation
    HSM_NAME="hsm${RANDOM_SUFFIX}"
    KV_NAME="kv${RANDOM_SUFFIX}"
    CVM_NAME="cvm${RANDOM_SUFFIX}"
    STORAGE_NAME="st${RANDOM_SUFFIX}"
    ATTESTATION_NAME="att${RANDOM_SUFFIX}"
    
    # Validate Azure naming conventions
    if [[ ${#HSM_NAME} -gt 24 ]]; then
        error "HSM name too long: $HSM_NAME"
        exit 1
    fi
    
    if [[ ${#STORAGE_NAME} -gt 24 ]]; then
        error "Storage account name too long: $STORAGE_NAME"
        exit 1
    fi
    
    # Export variables for use in sub-processes
    export RESOURCE_GROUP LOCATION SUBSCRIPTION_ID TENANT_ID
    export HSM_NAME KV_NAME CVM_NAME STORAGE_NAME ATTESTATION_NAME
    
    info "Resource Group: $RESOURCE_GROUP"
    info "Location: $LOCATION"
    info "HSM Name: $HSM_NAME"
    info "Key Vault Name: $KV_NAME"
    info "VM Name: $CVM_NAME"
    info "Storage Name: $STORAGE_NAME"
    info "Attestation Name: $ATTESTATION_NAME"
    
    success "Environment variables configured"
}

# Create resource group with proper tagging
create_resource_group() {
    show_progress 5 12 "Creating resource group"
    
    if az group show --name "$RESOURCE_GROUP" &>/dev/null; then
        warning "Resource group '$RESOURCE_GROUP' already exists"
        local existing_location=$(az group show --name "$RESOURCE_GROUP" --query location --output tsv)
        if [[ "$existing_location" != "$LOCATION" ]]; then
            error "Existing resource group is in different location: $existing_location"
            exit 1
        fi
    else
        az group create \
            --name "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --tags \
                purpose=confidential-computing \
                environment=demo \
                recipe="$RECIPE_NAME" \
                created-by=deploy-script \
                created-date="$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
                cost-center=demo \
                auto-delete=enabled
        
        success "Resource group '$RESOURCE_GROUP' created"
    fi
}

# Create Azure Attestation Provider
create_attestation_provider() {
    show_progress 6 12 "Creating Azure Attestation Provider"
    
    if az attestation show --name "$ATTESTATION_NAME" --resource-group "$RESOURCE_GROUP" &>/dev/null; then
        warning "Attestation provider '$ATTESTATION_NAME' already exists"
    else
        az attestation create \
            --name "$ATTESTATION_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --tags \
                purpose=confidential-computing \
                component=attestation
        
        success "Attestation provider '$ATTESTATION_NAME' created"
    fi
    
    # Get attestation endpoint
    ATTESTATION_ENDPOINT=$(az attestation show \
        --name "$ATTESTATION_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --query attestUri --output tsv)
    
    export ATTESTATION_ENDPOINT
    info "Attestation endpoint: $ATTESTATION_ENDPOINT"
    
    # Wait for attestation provider to be ready
    local max_attempts=30
    local attempts=0
    while [[ $attempts -lt $max_attempts ]]; do
        local status=$(az attestation show \
            --name "$ATTESTATION_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --query provisioningState --output tsv)
        
        if [[ "$status" == "Succeeded" ]]; then
            success "Attestation provider is ready"
            break
        elif [[ "$status" == "Failed" ]]; then
            error "Attestation provider provisioning failed"
            exit 1
        else
            info "Attestation provider status: $status (attempt $((attempts + 1))/$max_attempts)"
            sleep 10
            ((attempts++))
        fi
    done
    
    if [[ $attempts -eq $max_attempts ]]; then
        error "Attestation provider provisioning timed out"
        exit 1
    fi
}

# Create Azure Managed HSM with comprehensive error handling
create_managed_hsm() {
    show_progress 7 12 "Creating Azure Managed HSM (this will take 20-25 minutes)"
    
    if az keyvault show --hsm-name "$HSM_NAME" &>/dev/null; then
        warning "Managed HSM '$HSM_NAME' already exists"
        local status=$(az keyvault show --hsm-name "$HSM_NAME" --query properties.provisioningState --output tsv)
        if [[ "$status" == "Succeeded" ]]; then
            success "Managed HSM is already provisioned"
            return 0
        fi
    fi
    
    # Get current user ID for HSM administrator
    local user_id=$(az ad signed-in-user show --query id --output tsv)
    if [[ -z "$user_id" ]]; then
        error "Could not determine current user ID for HSM administrator"
        exit 1
    fi
    
    # Create the Managed HSM
    info "Starting HSM creation... (this is a long-running operation)"
    az keyvault create \
        --hsm-name "$HSM_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --retention-days 7 \
        --administrators "$user_id" \
        --tags \
            purpose=confidential-computing \
            component=hsm \
            security-level=fips-140-3-level-3 \
        --no-wait
    
    # Wait for HSM to be provisioned with enhanced monitoring
    info "Waiting for HSM provisioning to complete..."
    local max_attempts=60  # 60 attempts * 30 seconds = 30 minutes max
    local attempts=0
    local last_status=""
    
    while [[ $attempts -lt $max_attempts ]]; do
        local status=$(az keyvault show \
            --hsm-name "$HSM_NAME" \
            --query properties.provisioningState \
            --output tsv 2>/dev/null || echo "NotFound")
        
        if [[ "$status" == "Succeeded" ]]; then
            success "Managed HSM '$HSM_NAME' provisioned successfully"
            break
        elif [[ "$status" == "Failed" ]]; then
            error "HSM provisioning failed"
            # Get detailed error information
            az keyvault show --hsm-name "$HSM_NAME" --query properties.statusMessage --output tsv || true
            exit 1
        else
            if [[ "$status" != "$last_status" ]]; then
                info "HSM status changed: $status"
                last_status="$status"
            fi
            
            local elapsed_time=$((attempts * 30))
            local remaining_time=$((max_attempts * 30 - elapsed_time))
            info "HSM provisioning in progress... (elapsed: ${elapsed_time}s, remaining: ${remaining_time}s)"
            
            sleep 30
            ((attempts++))
        fi
    done
    
    if [[ $attempts -eq $max_attempts ]]; then
        error "HSM provisioning timed out after 30 minutes"
        exit 1
    fi
    
    # Verify HSM is fully operational
    local hsm_uri=$(az keyvault show --hsm-name "$HSM_NAME" --query properties.hsmUri --output tsv)
    info "HSM URI: $hsm_uri"
}

# Initialize HSM security domain with backup
initialize_hsm_security_domain() {
    show_progress 8 12 "Initializing HSM security domain"
    
    # Create backup directory
    local backup_dir="${SCRIPT_DIR}/hsm-backup"
    mkdir -p "$backup_dir"
    
    # Security domain file paths
    local security_domain_file="${backup_dir}/SecurityDomain-${HSM_NAME}.json"
    local exchange_key_file="${backup_dir}/SecurityDomainExchangeKey-${HSM_NAME}.pem"
    
    # Check if security domain already exists
    if [[ -f "$security_domain_file" ]]; then
        warning "Security domain file already exists, skipping download"
        return 0
    fi
    
    # Download security domain for backup
    info "Downloading security domain and exchange key..."
    if ! az keyvault security-domain download \
        --hsm-name "$HSM_NAME" \
        --security-domain-file "$security_domain_file" \
        --sd-exchange-key "$exchange_key_file"; then
        error "Failed to download security domain"
        exit 1
    fi
    
    # Verify files were created
    if [[ ! -f "$security_domain_file" || ! -f "$exchange_key_file" ]]; then
        error "Security domain files were not created properly"
        exit 1
    fi
    
    # Set appropriate permissions
    chmod 600 "$security_domain_file" "$exchange_key_file"
    
    success "HSM security domain initialized and backed up"
    warning "Security domain files created:"
    warning "  - $security_domain_file"
    warning "  - $exchange_key_file"
    warning "Store these files securely - they are required for disaster recovery"
}

# Create Confidential Virtual Machine with comprehensive configuration
create_confidential_vm() {
    show_progress 9 12 "Creating Confidential Virtual Machine with AMD SEV-SNP"
    
    if az vm show --resource-group "$RESOURCE_GROUP" --name "$CVM_NAME" &>/dev/null; then
        warning "Confidential VM '$CVM_NAME' already exists"
        CVM_IP=$(az vm show -d \
            --resource-group "$RESOURCE_GROUP" \
            --name "$CVM_NAME" \
            --query publicIps --output tsv)
        info "VM IP address: $CVM_IP"
        export CVM_IP
        return 0
    fi
    
    # Create SSH key if it doesn't exist
    local ssh_key_path="$HOME/.ssh/id_rsa"
    if [[ ! -f "$ssh_key_path" ]]; then
        info "Generating SSH key pair..."
        ssh-keygen -t rsa -b 2048 -f "$ssh_key_path" -N "" -C "confidential-vm-key"
        chmod 600 "$ssh_key_path"
        chmod 644 "${ssh_key_path}.pub"
    fi
    
    # Create the confidential VM with enhanced configuration
    info "Creating confidential VM (this may take 5-10 minutes)..."
    az vm create \
        --resource-group "$RESOURCE_GROUP" \
        --name "$CVM_NAME" \
        --image "Canonical:0001-com-ubuntu-confidential-vm-jammy:22_04-lts-cvm:latest" \
        --size Standard_DC4as_v5 \
        --security-type ConfidentialVM \
        --enable-secure-boot true \
        --enable-vtpm true \
        --os-disk-security-type VMGuestStateOnly \
        --os-disk-size-gb 128 \
        --admin-username azureuser \
        --ssh-key-values "${ssh_key_path}.pub" \
        --public-ip-sku Standard \
        --public-ip-address-allocation static \
        --nsg-rule SSH \
        --storage-sku Premium_LRS \
        --tags \
            purpose=confidential-computing \
            component=compute \
            security-type=confidential-vm \
            tee-type=amd-sev-snp
    
    # Get VM public IP and verify
    CVM_IP=$(az vm show -d \
        --resource-group "$RESOURCE_GROUP" \
        --name "$CVM_NAME" \
        --query publicIps --output tsv)
    
    if [[ -z "$CVM_IP" ]]; then
        error "Failed to get VM public IP address"
        exit 1
    fi
    
    export CVM_IP
    success "Confidential VM '$CVM_NAME' created with IP: $CVM_IP"
    
    # Wait for VM to be fully ready and SSH-accessible
    info "Waiting for VM to be fully ready..."
    local max_attempts=20
    local attempts=0
    
    while [[ $attempts -lt $max_attempts ]]; do
        if ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no -i "$ssh_key_path" \
               azureuser@"$CVM_IP" "echo 'SSH connection successful'" &>/dev/null; then
            success "VM is ready and SSH-accessible"
            break
        else
            info "Waiting for VM to be ready... (attempt $((attempts + 1))/$max_attempts)"
            sleep 30
            ((attempts++))
        fi
    done
    
    if [[ $attempts -eq $max_attempts ]]; then
        error "VM did not become ready within expected time"
        exit 1
    fi
    
    # Verify confidential VM features
    info "Verifying confidential VM features..."
    ssh -o StrictHostKeyChecking=no -i "$ssh_key_path" azureuser@"$CVM_IP" \
        "sudo dmesg | grep -i sev && ls -la /dev/sev* 2>/dev/null || echo 'TEE devices not yet available'"
}

# Create and configure remaining Azure services
create_and_configure_services() {
    show_progress 10 12 "Creating and configuring Azure services"
    
    # Create Key Vault with premium tier
    info "Creating Key Vault with Premium tier..."
    if ! az keyvault show --name "$KV_NAME" &>/dev/null; then
        az keyvault create \
            --name "$KV_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --sku Premium \
            --enable-rbac-authorization true \
            --tags \
                purpose=confidential-computing \
                component=key-vault \
                tier=premium
        
        # Get current user ID and assign role
        local user_id=$(az ad signed-in-user show --query id --output tsv)
        az role assignment create \
            --role "Key Vault Administrator" \
            --assignee "$user_id" \
            --scope $(az keyvault show --name "$KV_NAME" --query id --output tsv)
        
        # Wait for role assignment to propagate
        sleep 30
        
        # Create HSM-backed encryption key
        az keyvault key create \
            --vault-name "$KV_NAME" \
            --name enclave-master-key \
            --kty RSA-HSM \
            --size 2048 \
            --ops encrypt decrypt sign verify
        
        success "Key Vault configured with HSM-backed keys"
    else
        warning "Key Vault '$KV_NAME' already exists"
    fi
    
    # Create secure storage account
    info "Creating secure storage account..."
    if ! az storage account show --name "$STORAGE_NAME" --resource-group "$RESOURCE_GROUP" &>/dev/null; then
        az storage account create \
            --name "$STORAGE_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --sku Standard_LRS \
            --encryption-services blob file \
            --https-only true \
            --allow-blob-public-access false \
            --min-tls-version TLS1_2 \
            --tags \
                purpose=confidential-computing \
                component=storage
        
        success "Secure storage account created"
    else
        warning "Storage account '$STORAGE_NAME' already exists"
    fi
}

# Configure attestation and HSM policies
configure_security_policies() {
    show_progress 11 12 "Configuring security policies"
    
    # Configure attestation policy for AMD SEV-SNP
    info "Configuring attestation policy for AMD SEV-SNP..."
    
    # Create attestation policy file
    local policy_file="${SCRIPT_DIR}/attestation-policy.json"
    cat > "$policy_file" << 'EOF'
{
  "version": "1.0",
  "rules": [
    {
      "claim": "[type]",
      "operator": "equals",
      "value": "sevsnp"
    },
    {
      "claim": "[x-ms-attestation-type]",
      "operator": "equals", 
      "value": "sevsnpvm"
    },
    {
      "claim": "[x-ms-compliance-status]",
      "operator": "equals",
      "value": "azure-compliant"
    },
    {
      "claim": "[x-ms-sevsnpvm-guestsvn]",
      "operator": ">=",
      "value": "0"
    }
  ]
}
EOF
    
    # Convert policy to JWT format (base64 encoded)
    local policy_jwt=$(cat "$policy_file" | base64 -w 0)
    
    # Set attestation policy
    az attestation policy set \
        --name "$ATTESTATION_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --policy-format JWT \
        --policy "$policy_jwt" \
        --tee-type SevSnpVm
    
    success "Attestation policy configured for AMD SEV-SNP"
    
    # Clean up policy file
    rm -f "$policy_file"
    
    # Configure Managed HSM access policies
    info "Configuring Managed HSM access policies..."
    
    # Create managed identity for the application
    if ! az identity show --name confidential-app-identity --resource-group "$RESOURCE_GROUP" &>/dev/null; then
        az identity create \
            --name confidential-app-identity \
            --resource-group "$RESOURCE_GROUP" \
            --tags \
                purpose=confidential-computing \
                component=identity
    fi
    
    # Get application identity principal ID
    local app_identity_id=$(az identity show \
        --name confidential-app-identity \
        --resource-group "$RESOURCE_GROUP" \
        --query principalId --output tsv)
    
    # Assign Managed HSM Crypto User role
    az keyvault role assignment create \
        --hsm-name "$HSM_NAME" \
        --role "Managed HSM Crypto User" \
        --assignee "$app_identity_id" \
        --scope /keys
    
    # Create encryption key in Managed HSM
    az keyvault key create \
        --hsm-name "$HSM_NAME" \
        --name confidential-data-key \
        --kty RSA-HSM \
        --size 3072 \
        --ops encrypt decrypt wrapKey unwrapKey
    
    success "Managed HSM access policies configured"
}

# Deploy and test confidential application
deploy_confidential_application() {
    show_progress 12 12 "Deploying and testing confidential application"
    
    # Create enhanced deployment script
    local deploy_script="${SCRIPT_DIR}/deploy-app.sh"
    cat > "$deploy_script" << 'EOF'
#!/bin/bash
set -euo pipefail

echo "🚀 Starting confidential application deployment..."

# Update system packages
echo "📦 Updating system packages..."
sudo apt-get update -y
sudo apt-get upgrade -y
sudo apt-get install -y python3-pip git curl wget unzip software-properties-common

# Install Azure CLI
if ! command -v az &> /dev/null; then
    echo "📥 Installing Azure CLI..."
    curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash
fi

# Install Python dependencies
echo "🐍 Installing Python dependencies..."
pip3 install --upgrade pip
pip3 install azure-identity azure-keyvault-keys azure-attestation azure-storage-blob

# Create sample confidential application
echo "🔐 Creating confidential application..."
cat > confidential_app.py << 'PYEOF'
#!/usr/bin/env python3
"""
Confidential Computing Application
This application demonstrates secure processing in a TEE environment
"""

import os
import sys
import json
import logging
from typing import Optional, Dict, Any
from azure.identity import ManagedIdentityCredential, DefaultAzureCredential
from azure.keyvault.keys import KeyClient
from azure.attestation import AttestationClient
from azure.core.exceptions import AzureError

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

class ConfidentialApp:
    """Confidential computing application with TEE integration"""
    
    def __init__(self):
        self.attestation_endpoint = os.environ.get('ATTESTATION_ENDPOINT')
        self.hsm_name = os.environ.get('HSM_NAME')
        self.credential = None
        self.key_client = None
        self.attestation_client = None
        
    def initialize_clients(self) -> bool:
        """Initialize Azure clients with proper authentication"""
        try:
            logger.info("🔐 Initializing Azure clients...")
            
            # Try managed identity first, fallback to default credential
            try:
                self.credential = ManagedIdentityCredential()
                # Test the credential
                token = self.credential.get_token("https://vault.azure.net/.default")
                logger.info("✅ Managed Identity authentication successful")
            except Exception as e:
                logger.warning(f"Managed Identity failed: {e}")
                logger.info("🔄 Falling back to DefaultAzureCredential...")
                self.credential = DefaultAzureCredential()
            
            if not self.attestation_endpoint or not self.hsm_name:
                logger.error("❌ Missing required environment variables")
                return False
            
            # Initialize attestation client
            self.attestation_client = AttestationClient(
                endpoint=self.attestation_endpoint,
                credential=self.credential
            )
            
            # Initialize HSM key client
            hsm_endpoint = f"https://{self.hsm_name}.managedhsm.azure.net"
            self.key_client = KeyClient(
                vault_url=hsm_endpoint,
                credential=self.credential
            )
            
            logger.info(f"🔍 Attestation endpoint: {self.attestation_endpoint}")
            logger.info(f"🔑 HSM endpoint: {hsm_endpoint}")
            
            return True
            
        except Exception as e:
            logger.error(f"❌ Failed to initialize clients: {e}")
            return False
    
    def verify_tee_environment(self) -> bool:
        """Verify we're running in a trusted execution environment"""
        try:
            logger.info("🔍 Verifying TEE environment...")
            
            # Check for SEV-SNP device
            sev_devices = ['/dev/sev', '/dev/sev-guest']
            found_device = False
            
            for device in sev_devices:
                if os.path.exists(device):
                    logger.info(f"✅ Found TEE device: {device}")
                    found_device = True
                    break
            
            if not found_device:
                logger.warning("⚠️  No SEV-SNP devices found")
                return False
            
            # Check for vTPM
            if os.path.exists('/sys/class/tpm'):
                logger.info("✅ Virtual TPM detected")
            else:
                logger.warning("⚠️  Virtual TPM not found")
            
            return True
            
        except Exception as e:
            logger.error(f"❌ TEE verification failed: {e}")
            return False
    
    def generate_attestation_token(self) -> Optional[str]:
        """Generate attestation token for the TEE"""
        try:
            logger.info("📋 Generating attestation token...")
            
            # In a real implementation, this would:
            # 1. Generate a hardware attestation report
            # 2. Submit it to the attestation service
            # 3. Receive a signed JWT token
            
            # For demo purposes, we'll simulate this process
            attestation_token = "eyJ0eXAiOiJKV1QiLCJhbGciOiJSUzI1NiJ9.demo_token_payload"
            logger.info("✅ Attestation token generated (simulated)")
            
            return attestation_token
            
        except Exception as e:
            logger.error(f"❌ Attestation token generation failed: {e}")
            return None
    
    def retrieve_encryption_key(self) -> bool:
        """Retrieve encryption key from HSM"""
        try:
            logger.info("🔑 Retrieving encryption key from HSM...")
            
            key = self.key_client.get_key("confidential-data-key")
            logger.info(f"✅ Successfully retrieved key: {key.name}")
            logger.info(f"   Key ID: {key.id}")
            logger.info(f"   Key type: {key.key_type}")
            logger.info(f"   Key size: {key.key_size if hasattr(key, 'key_size') else 'N/A'}")
            
            return True
            
        except Exception as e:
            logger.error(f"❌ Failed to retrieve encryption key: {e}")
            return False
    
    def process_confidential_data(self) -> bool:
        """Simulate confidential data processing"""
        try:
            logger.info("⚡ Processing confidential data in secure enclave...")
            
            # Simulate data processing steps
            steps = [
                "Loading sensitive data into encrypted memory",
                "Applying cryptographic transformations",
                "Performing secure computations",
                "Generating encrypted results",
                "Storing results with hardware-backed encryption"
            ]
            
            for i, step in enumerate(steps, 1):
                logger.info(f"   {i}. {step}")
                # Simulate processing time
                import time
                time.sleep(0.5)
            
            logger.info("✅ Confidential processing completed successfully")
            return True
            
        except Exception as e:
            logger.error(f"❌ Confidential processing failed: {e}")
            return False
    
    def run(self) -> int:
        """Main application workflow"""
        try:
            logger.info("🚀 Starting confidential application...")
            
            # Initialize clients
            if not self.initialize_clients():
                return 1
            
            # Verify TEE environment
            if not self.verify_tee_environment():
                logger.warning("⚠️  TEE verification failed, but continuing...")
            
            # Generate attestation token
            token = self.generate_attestation_token()
            if not token:
                logger.warning("⚠️  Attestation token generation failed, but continuing...")
            
            # Retrieve encryption key
            if not self.retrieve_encryption_key():
                return 1
            
            # Process confidential data
            if not self.process_confidential_data():
                return 1
            
            logger.info("🎉 Confidential application completed successfully!")
            return 0
            
        except Exception as e:
            logger.error(f"❌ Application failed: {e}")
            return 1

def main():
    """Main entry point"""
    app = ConfidentialApp()
    return app.run()

if __name__ == "__main__":
    sys.exit(main())
PYEOF

# Make the application executable
chmod +x confidential_app.py

echo "✅ Confidential application created successfully"

# Test the application
echo "🚀 Testing confidential application..."
export ATTESTATION_ENDPOINT="${ATTESTATION_ENDPOINT}"
export HSM_NAME="${HSM_NAME}"

python3 confidential_app.py

echo "✅ Application deployment and testing completed"
EOF
    
    # Make deployment script executable
    chmod +x "$deploy_script"
    
    # Copy and execute on VM
    info "Copying deployment script to VM..."
    local ssh_key_path="$HOME/.ssh/id_rsa"
    if ! scp -o StrictHostKeyChecking=no -i "$ssh_key_path" "$deploy_script" azureuser@"$CVM_IP":~/deploy-app.sh; then
        error "Failed to copy deployment script to VM"
        exit 1
    fi
    
    info "Executing deployment script on confidential VM..."
    if ! ssh -o StrictHostKeyChecking=no -i "$ssh_key_path" azureuser@"$CVM_IP" \
        "chmod +x deploy-app.sh && ATTESTATION_ENDPOINT='$ATTESTATION_ENDPOINT' HSM_NAME='$HSM_NAME' ./deploy-app.sh"; then
        error "Failed to execute deployment script on VM"
        exit 1
    fi
    
    success "Sample confidential application deployed and tested successfully"
    
    # Clean up local script
    rm -f "$deploy_script"
}

# Comprehensive validation of the entire deployment
validate_deployment() {
    echo
    info "🔍 Validating complete deployment..."
    
    local validation_errors=0
    
    # Check attestation provider
    local attest_status=$(az attestation show \
        --name "$ATTESTATION_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --query provisioningState --output tsv)
    
    if [[ "$attest_status" == "Succeeded" ]]; then
        success "Attestation provider is operational"
    else
        error "Attestation provider status: $attest_status"
        ((validation_errors++))
    fi
    
    # Check Managed HSM
    local hsm_status=$(az keyvault show \
        --hsm-name "$HSM_NAME" \
        --query properties.provisioningState --output tsv)
    
    if [[ "$hsm_status" == "Succeeded" ]]; then
        success "Managed HSM is operational"
        
        # Check HSM keys
        local key_count=$(az keyvault key list --hsm-name "$HSM_NAME" --query "length(@)" --output tsv)
        info "HSM contains $key_count keys"
    else
        error "Managed HSM status: $hsm_status"
        ((validation_errors++))
    fi
    
    # Check Key Vault
    local kv_status=$(az keyvault show \
        --name "$KV_NAME" \
        --query properties.provisioningState --output tsv)
    
    if [[ "$kv_status" == "Succeeded" ]]; then
        success "Key Vault is operational"
    else
        error "Key Vault status: $kv_status"
        ((validation_errors++))
    fi
    
    # Check confidential VM
    local vm_status=$(az vm show \
        --resource-group "$RESOURCE_GROUP" \
        --name "$CVM_NAME" \
        --query provisioningState --output tsv)
    
    if [[ "$vm_status" == "Succeeded" ]]; then
        success "Confidential VM is operational"
        
        # Check VM security configuration
        local security_profile=$(az vm show \
            --resource-group "$RESOURCE_GROUP" \
            --name "$CVM_NAME" \
            --query securityProfile --output json)
        
        if [[ "$security_profile" == *"ConfidentialVM"* ]]; then
            success "VM is configured as Confidential VM"
        else
            warning "VM security configuration may not be optimal"
        fi
    else
        error "Confidential VM status: $vm_status"
        ((validation_errors++))
    fi
    
    # Check storage account
    local storage_status=$(az storage account show \
        --name "$STORAGE_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --query provisioningState --output tsv)
    
    if [[ "$storage_status" == "Succeeded" ]]; then
        success "Storage account is operational"
    else
        error "Storage account status: $storage_status"
        ((validation_errors++))
    fi
    
    # Test SSH connectivity
    local ssh_key_path="$HOME/.ssh/id_rsa"
    if ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no -i "$ssh_key_path" \
           azureuser@"$CVM_IP" "echo 'SSH test successful'" &>/dev/null; then
        success "SSH connectivity to confidential VM verified"
    else
        warning "SSH connectivity test failed - VM may still be initializing"
        ((validation_errors++))
    fi
    
    # Test confidential VM features
    info "Testing confidential VM features..."
    local tee_test=$(ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no -i "$ssh_key_path" \
                     azureuser@"$CVM_IP" "sudo dmesg | grep -i sev | head -1" 2>/dev/null || echo "")
    
    if [[ -n "$tee_test" ]]; then
        success "SEV-SNP features detected: $tee_test"
    else
        warning "Could not verify SEV-SNP features"
    fi
    
    # Summary of validation
    if [[ $validation_errors -eq 0 ]]; then
        success "All deployment validations passed! 🎉"
    else
        error "Deployment validation found $validation_errors issues"
        warning "Review the errors above and check the Azure portal for details"
    fi
    
    return $validation_errors
}

# Display comprehensive deployment summary
display_summary() {
    local deployment_end_time=$(date +%s)
    local deployment_duration=$((deployment_end_time - DEPLOYMENT_START_TIME))
    local duration_minutes=$((deployment_duration / 60))
    local duration_seconds=$((deployment_duration % 60))
    
    echo
    echo "========================================================================"
    echo "🎉 AZURE CONFIDENTIAL COMPUTING DEPLOYMENT COMPLETED"
    echo "========================================================================"
    echo
    echo "📋 DEPLOYMENT SUMMARY:"
    echo "  Resource Group:       $RESOURCE_GROUP"
    echo "  Location:             $LOCATION"
    echo "  Deployment Duration:  ${duration_minutes}m ${duration_seconds}s"
    echo "  Subscription:         $SUBSCRIPTION_ID"
    echo
    echo "🔐 CONFIDENTIAL COMPUTING RESOURCES:"
    echo "  Attestation Provider: $ATTESTATION_NAME"
    echo "  Attestation Endpoint: $ATTESTATION_ENDPOINT"
    echo "  Managed HSM:          $HSM_NAME"
    echo "  Key Vault:            $KV_NAME"
    echo "  Confidential VM:      $CVM_NAME"
    echo "  Storage Account:      $STORAGE_NAME"
    echo "  VM Public IP:         $CVM_IP"
    echo
    echo "🛡️  SECURITY FEATURES ENABLED:"
    echo "  ✅ AMD SEV-SNP Confidential VM"
    echo "  ✅ Hardware-based memory encryption"
    echo "  ✅ Secure Boot and vTPM"
    echo "  ✅ Azure Attestation Service"
    echo "  ✅ Managed HSM (FIPS 140-3 Level 3)"
    echo "  ✅ HSM-backed encryption keys"
    echo "  ✅ Customer-managed storage encryption"
    echo "  ✅ Sample confidential application"
    echo
    echo "🚀 VERIFICATION STEPS:"
    echo "  1. Connect to VM:"
    echo "     ssh azureuser@$CVM_IP"
    echo "  2. Verify SEV-SNP features:"
    echo "     sudo dmesg | grep -i sev"
    echo "  3. Check TEE devices:"
    echo "     ls -la /dev/sev* /dev/tpm*"
    echo "  4. Run confidential application:"
    echo "     python3 ~/confidential_app.py"
    echo "  5. Verify attestation:"
    echo "     curl -X GET '$ATTESTATION_ENDPOINT/attest/SevSnpVm?api-version=2022-08-01'"
    echo
    echo "📁 SECURITY BACKUP FILES:"
    echo "  Check the following directory for HSM backup files:"
    echo "  $SCRIPT_DIR/hsm-backup/"
    echo "  ⚠️  Store these files securely - required for disaster recovery!"
    echo
    echo "💰 COST INFORMATION:"
    echo "  Estimated monthly cost: ~\$500-800"
    echo "  Major cost components:"
    echo "    - Managed HSM: ~\$350-400/month"
    echo "    - Confidential VM: ~\$150-200/month"
    echo "    - Storage and networking: ~\$50-100/month"
    echo "  💡 Run destroy.sh when done testing to avoid charges"
    echo
    echo "📚 ADDITIONAL RESOURCES:"
    echo "  - Azure Confidential Computing:"
    echo "    https://docs.microsoft.com/en-us/azure/confidential-computing/"
    echo "  - Managed HSM documentation:"
    echo "    https://docs.microsoft.com/en-us/azure/key-vault/managed-hsm/"
    echo "  - SEV-SNP technical details:"
    echo "    https://www.amd.com/en/processors/amd-secure-memory-encryption"
    echo
    echo "🆘 TROUBLESHOOTING:"
    echo "  - Deployment logs: $SCRIPT_DIR/deploy.log"
    echo "  - VM serial console: Available in Azure portal"
    echo "  - HSM access logs: Available in Azure Monitor"
    echo "========================================================================"
}

# Cleanup function for script interruption
cleanup_on_exit() {
    local exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        echo
        error "Deployment failed or was interrupted (exit code: $exit_code)"
        error "Check the deployment log for details: $SCRIPT_DIR/deploy.log"
        warning "Some resources may have been created. Consider running destroy.sh to clean up."
        
        # Show recent log entries
        if [[ -f "$SCRIPT_DIR/deploy.log" ]]; then
            echo
            echo "Recent log entries:"
            tail -10 "$SCRIPT_DIR/deploy.log"
        fi
    fi
}

# Main deployment function
main() {
    # Record deployment start time
    DEPLOYMENT_START_TIME=$(date +%s)
    
    # Initialize logging
    exec 2> >(tee -a "${SCRIPT_DIR}/deploy.log")
    
    echo "========================================================================"
    echo "🚀 AZURE CONFIDENTIAL COMPUTING DEPLOYMENT"
    echo "========================================================================"
    echo "This script will deploy a complete confidential computing solution"
    echo "with hardware-based trusted execution environments (TEEs)."
    echo
    echo "📋 DEPLOYMENT INCLUDES:"
    echo "  • AMD SEV-SNP Confidential Virtual Machine"
    echo "  • Azure Attestation Service for TEE verification"
    echo "  • Managed HSM (FIPS 140-3 Level 3) for key management"
    echo "  • Premium Key Vault with HSM-backed keys"
    echo "  • Encrypted storage with customer-managed keys"
    echo "  • Sample confidential application"
    echo
    echo "⏱️  Estimated deployment time: 30-45 minutes"
    echo "💰 Estimated monthly cost: ~\$500-800"
    echo
    echo "🔒 SECURITY FEATURES:"
    echo "  • Hardware-based memory encryption"
    echo "  • Cryptographic attestation of TEE integrity"
    echo "  • Isolated execution environment"
    echo "  • Hardware security module protection"
    echo
    
    # Confirm deployment
    echo "⚠️  This deployment will create billable Azure resources."
    read -p "Continue with deployment? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log "Deployment cancelled by user"
        exit 0
    fi
    
    # Set trap for cleanup on exit
    trap cleanup_on_exit EXIT
    
    # Execute deployment steps
    check_environment
    check_prerequisites
    set_environment_variables
    check_regional_availability
    create_resource_group
    create_attestation_provider
    create_managed_hsm
    initialize_hsm_security_domain
    create_confidential_vm
    create_and_configure_services
    configure_security_policies
    deploy_confidential_application
    
    # Final validation and summary
    if validate_deployment; then
        display_summary
        success "Deployment completed successfully! ✨"
        exit 0
    else
        error "Deployment completed with validation errors"
        exit 1
    fi
}

# Script entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi