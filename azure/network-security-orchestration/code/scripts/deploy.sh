#!/bin/bash

# =============================================================================
# Azure Network Security Orchestration - Deployment Script
# =============================================================================
# This script deploys the complete Network Security Orchestration solution
# including Logic Apps, Network Security Groups, Key Vault, and monitoring.
# 
# Features:
# - Idempotent deployment (safe to run multiple times)
# - Comprehensive error handling and logging
# - Dry-run mode support
# - Automatic cleanup on failure
# - Prerequisites validation
# - Resource validation
# =============================================================================

set -e  # Exit on any error
set -o pipefail  # Exit on pipe errors

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
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️  $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ❌ $1${NC}"
}

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOYMENT_LOG="${SCRIPT_DIR}/deployment.log"
DRY_RUN="${DRY_RUN:-false}"

# Start logging
exec > >(tee -a "$DEPLOYMENT_LOG") 2>&1

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        error "Azure CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check Azure CLI version
    local az_version=$(az version --query '."azure-cli"' --output tsv)
    log "Azure CLI version: $az_version"
    
    # Check if user is logged in
    if ! az account show &> /dev/null; then
        error "Please log in to Azure CLI first using 'az login'"
        exit 1
    fi
    
    # Check if required tools are available
    for tool in jq curl openssl; do
        if ! command -v $tool &> /dev/null; then
            warning "$tool is not installed. Some features may be limited."
        fi
    done
    
    # Check Azure resource provider registrations
    local required_providers=("Microsoft.Logic" "Microsoft.Network" "Microsoft.KeyVault" "Microsoft.Storage" "Microsoft.OperationalInsights")
    for provider in "${required_providers[@]}"; do
        local state=$(az provider show --namespace "$provider" --query "registrationState" --output tsv 2>/dev/null || echo "NotRegistered")
        if [ "$state" != "Registered" ]; then
            warning "Provider $provider is not registered. Attempting to register..."
            az provider register --namespace "$provider" --wait || true
        fi
    done
    
    success "Prerequisites check passed"
}

# Function to set environment variables
set_environment_variables() {
    log "Setting up environment variables..."
    
    # Set default values or use environment variables
    export RESOURCE_GROUP="${RESOURCE_GROUP:-rg-security-orchestration}"
    export LOCATION="${LOCATION:-eastus}"
    export SUBSCRIPTION_ID=$(az account show --query id --output tsv)
    
    # Generate unique suffix for resource names
    RANDOM_SUFFIX=$(openssl rand -hex 3)
    
    # Set resource names with unique suffix
    export LOGIC_APP_NAME="la-security-orchestrator-${RANDOM_SUFFIX}"
    export KEY_VAULT_NAME="kv-security-${RANDOM_SUFFIX}"
    export STORAGE_ACCOUNT_NAME="stsecurity${RANDOM_SUFFIX}"
    export NSG_NAME="nsg-protected-${RANDOM_SUFFIX}"
    export VNET_NAME="vnet-security-${RANDOM_SUFFIX}"
    export LOG_ANALYTICS_NAME="law-security-${RANDOM_SUFFIX}"
    
    # Save environment variables to file for cleanup script
    cat > "${SCRIPT_DIR}/.env" << EOF
RESOURCE_GROUP=${RESOURCE_GROUP}
LOCATION=${LOCATION}
SUBSCRIPTION_ID=${SUBSCRIPTION_ID}
LOGIC_APP_NAME=${LOGIC_APP_NAME}
KEY_VAULT_NAME=${KEY_VAULT_NAME}
STORAGE_ACCOUNT_NAME=${STORAGE_ACCOUNT_NAME}
NSG_NAME=${NSG_NAME}
VNET_NAME=${VNET_NAME}
LOG_ANALYTICS_NAME=${LOG_ANALYTICS_NAME}
RANDOM_SUFFIX=${RANDOM_SUFFIX}
EOF
    
    success "Environment variables configured"
    log "Resource Group: ${RESOURCE_GROUP}"
    log "Location: ${LOCATION}"
    log "Subscription ID: ${SUBSCRIPTION_ID}"
}

# Function to create resource group
create_resource_group() {
    log "Creating resource group..."
    
    if az group show --name ${RESOURCE_GROUP} &> /dev/null; then
        warning "Resource group ${RESOURCE_GROUP} already exists"
    else
        az group create \
            --name ${RESOURCE_GROUP} \
            --location ${LOCATION} \
            --tags purpose=security-orchestration environment=demo
        
        success "Resource group created: ${RESOURCE_GROUP}"
    fi
}

# Function to create Log Analytics workspace
create_log_analytics() {
    log "Creating Log Analytics workspace..."
    
    if az monitor log-analytics workspace show \
        --resource-group ${RESOURCE_GROUP} \
        --workspace-name ${LOG_ANALYTICS_NAME} &> /dev/null; then
        warning "Log Analytics workspace ${LOG_ANALYTICS_NAME} already exists"
    else
        az monitor log-analytics workspace create \
            --resource-group ${RESOURCE_GROUP} \
            --workspace-name ${LOG_ANALYTICS_NAME} \
            --location ${LOCATION} \
            --sku PerGB2018
        
        success "Log Analytics workspace created for security monitoring"
    fi
}

# Function to create Key Vault
create_key_vault() {
    log "Creating Azure Key Vault..."
    
    if az keyvault show --name ${KEY_VAULT_NAME} &> /dev/null; then
        warning "Key Vault ${KEY_VAULT_NAME} already exists"
    else
        az keyvault create \
            --name ${KEY_VAULT_NAME} \
            --resource-group ${RESOURCE_GROUP} \
            --location ${LOCATION} \
            --sku standard \
            --enabled-for-template-deployment true \
            --enabled-for-disk-encryption true
        
        # Store sample threat intelligence API key
        az keyvault secret set \
            --vault-name ${KEY_VAULT_NAME} \
            --name "ThreatIntelApiKey" \
            --value "sample-api-key-for-threat-feeds"
        
        success "Key Vault created with security credentials"
    fi
}

# Function to create storage account
create_storage_account() {
    log "Creating storage account..."
    
    if az storage account show \
        --name ${STORAGE_ACCOUNT_NAME} \
        --resource-group ${RESOURCE_GROUP} &> /dev/null; then
        warning "Storage account ${STORAGE_ACCOUNT_NAME} already exists"
    else
        az storage account create \
            --name ${STORAGE_ACCOUNT_NAME} \
            --resource-group ${RESOURCE_GROUP} \
            --location ${LOCATION} \
            --sku Standard_LRS \
            --kind StorageV2 \
            --access-tier Hot \
            --https-only true \
            --min-tls-version TLS1_2 \
            --allow-blob-public-access false
        
        success "Storage account created"
    fi
    
    # Get storage account connection string
    STORAGE_CONNECTION=$(az storage account show-connection-string \
        --name ${STORAGE_ACCOUNT_NAME} \
        --resource-group ${RESOURCE_GROUP} \
        --output tsv)
    
    # Create containers for security data
    az storage container create \
        --name "security-events" \
        --connection-string "${STORAGE_CONNECTION}" \
        --public-access off \
        --fail-on-exist false
    
    az storage container create \
        --name "compliance-reports" \
        --connection-string "${STORAGE_CONNECTION}" \
        --public-access off \
        --fail-on-exist false
    
    success "Storage containers configured for security workflow data"
}

# Function to create network infrastructure
create_network_infrastructure() {
    log "Creating virtual network and network security group..."
    
    # Create virtual network
    if az network vnet show \
        --name ${VNET_NAME} \
        --resource-group ${RESOURCE_GROUP} &> /dev/null; then
        warning "Virtual network ${VNET_NAME} already exists"
    else
        az network vnet create \
            --name ${VNET_NAME} \
            --resource-group ${RESOURCE_GROUP} \
            --location ${LOCATION} \
            --address-prefixes 10.0.0.0/16 \
            --subnet-name protected-subnet \
            --subnet-prefixes 10.0.1.0/24
        
        success "Virtual network created"
    fi
    
    # Create Network Security Group
    if az network nsg show \
        --name ${NSG_NAME} \
        --resource-group ${RESOURCE_GROUP} &> /dev/null; then
        warning "Network Security Group ${NSG_NAME} already exists"
    else
        az network nsg create \
            --name ${NSG_NAME} \
            --resource-group ${RESOURCE_GROUP} \
            --location ${LOCATION}
        
        # Add default security rules
        az network nsg rule create \
            --nsg-name ${NSG_NAME} \
            --resource-group ${RESOURCE_GROUP} \
            --name "Allow-HTTPS-Inbound" \
            --priority 1000 \
            --direction Inbound \
            --access Allow \
            --protocol Tcp \
            --source-address-prefixes "*" \
            --destination-port-ranges 443 \
            --description "Allow HTTPS traffic inbound"
        
        # Add SSH rule for management
        az network nsg rule create \
            --nsg-name ${NSG_NAME} \
            --resource-group ${RESOURCE_GROUP} \
            --name "Allow-SSH-Inbound" \
            --priority 1100 \
            --direction Inbound \
            --access Allow \
            --protocol Tcp \
            --source-address-prefixes "10.0.0.0/8" \
            --destination-port-ranges 22 \
            --description "Allow SSH from private networks"
        
        success "Network Security Group created with baseline rules"
    fi
    
    # Associate NSG with subnet
    az network vnet subnet update \
        --vnet-name ${VNET_NAME} \
        --name protected-subnet \
        --resource-group ${RESOURCE_GROUP} \
        --network-security-group ${NSG_NAME}
    
    success "Network infrastructure configured"
}

# Function to create Logic Apps workflow
create_logic_apps_workflow() {
    log "Creating Logic Apps workflow..."
    
    if az logic workflow show \
        --name ${LOGIC_APP_NAME} \
        --resource-group ${RESOURCE_GROUP} &> /dev/null; then
        warning "Logic Apps workflow ${LOGIC_APP_NAME} already exists"
    else
        # Create basic Logic Apps workflow
        az logic workflow create \
            --name ${LOGIC_APP_NAME} \
            --resource-group ${RESOURCE_GROUP} \
            --location ${LOCATION} \
            --definition '{
                "$schema": "https://schema.management.azure.com/schemas/2016-06-01/Microsoft.Logic.json",
                "contentVersion": "1.0.0.0",
                "parameters": {},
                "triggers": {
                    "manual": {
                        "type": "Request",
                        "kind": "Http",
                        "inputs": {
                            "schema": {
                                "properties": {
                                    "threatType": {"type": "string"},
                                    "sourceIP": {"type": "string"},
                                    "severity": {"type": "string"},
                                    "action": {"type": "string"}
                                },
                                "type": "object"
                            }
                        }
                    }
                },
                "actions": {
                    "Parse_Security_Event": {
                        "type": "ParseJson",
                        "inputs": {
                            "content": "@triggerBody()",
                            "schema": {
                                "properties": {
                                    "threatType": {"type": "string"},
                                    "sourceIP": {"type": "string"},
                                    "severity": {"type": "string"},
                                    "action": {"type": "string"}
                                },
                                "type": "object"
                            }
                        }
                    },
                    "Log_Security_Event": {
                        "type": "Http",
                        "inputs": {
                            "method": "POST",
                            "uri": "https://httpbin.org/post",
                            "body": {
                                "timestamp": "@utcnow()",
                                "event": "@triggerBody()",
                                "status": "processed"
                            }
                        }
                    }
                },
                "outputs": {}
            }'
        
        success "Logic Apps workflow created for security orchestration"
    fi
}

# Function to configure monitoring
configure_monitoring() {
    log "Configuring monitoring and compliance..."
    
    # Enable diagnostic settings for Logic Apps
    az monitor diagnostic-settings create \
        --name "SecurityOrchestrationLogs" \
        --resource "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.Logic/workflows/${LOGIC_APP_NAME}" \
        --workspace "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.OperationalInsights/workspaces/${LOG_ANALYTICS_NAME}" \
        --logs '[{
            "category": "WorkflowRuntime",
            "enabled": true,
            "retentionPolicy": {
                "enabled": true,
                "days": 90
            }
        }]' \
        --metrics '[{
            "category": "AllMetrics",
            "enabled": true,
            "retentionPolicy": {
                "enabled": true,
                "days": 90
            }
        }]' || warning "Diagnostic settings may already exist"
    
    success "Monitoring and compliance configured"
}

# Function to validate deployment
validate_deployment() {
    log "Validating deployment..."
    
    # Check if all resources exist
    local validation_failed=false
    
    # Validate resource group
    if ! az group show --name ${RESOURCE_GROUP} &> /dev/null; then
        error "Resource group validation failed"
        validation_failed=true
    fi
    
    # Validate Logic Apps
    if ! az logic workflow show --name ${LOGIC_APP_NAME} --resource-group ${RESOURCE_GROUP} &> /dev/null; then
        error "Logic Apps workflow validation failed"
        validation_failed=true
    fi
    
    # Validate Key Vault
    if ! az keyvault show --name ${KEY_VAULT_NAME} &> /dev/null; then
        error "Key Vault validation failed"
        validation_failed=true
    fi
    
    # Validate Storage Account
    if ! az storage account show --name ${STORAGE_ACCOUNT_NAME} --resource-group ${RESOURCE_GROUP} &> /dev/null; then
        error "Storage account validation failed"
        validation_failed=true
    fi
    
    # Validate Network Security Group
    if ! az network nsg show --name ${NSG_NAME} --resource-group ${RESOURCE_GROUP} &> /dev/null; then
        error "Network Security Group validation failed"
        validation_failed=true
    fi
    
    # Validate Virtual Network
    if ! az network vnet show --name ${VNET_NAME} --resource-group ${RESOURCE_GROUP} &> /dev/null; then
        error "Virtual network validation failed"
        validation_failed=true
    fi
    
    if [ "$validation_failed" = true ]; then
        error "Deployment validation failed"
        exit 1
    fi
    
    success "Deployment validation passed"
}

# Function to display deployment summary
display_summary() {
    log "Deployment Summary:"
    echo "=================================="
    echo "Resource Group: ${RESOURCE_GROUP}"
    echo "Location: ${LOCATION}"
    echo "Logic Apps Workflow: ${LOGIC_APP_NAME}"
    echo "Key Vault: ${KEY_VAULT_NAME}"
    echo "Storage Account: ${STORAGE_ACCOUNT_NAME}"
    echo "Network Security Group: ${NSG_NAME}"
    echo "Virtual Network: ${VNET_NAME}"
    echo "Log Analytics Workspace: ${LOG_ANALYTICS_NAME}"
    echo "=================================="
    
    # Get Logic Apps callback URL
    CALLBACK_URL=$(az logic workflow show \
        --name ${LOGIC_APP_NAME} \
        --resource-group ${RESOURCE_GROUP} \
        --query "accessEndpoint" --output tsv) || warning "Unable to retrieve callback URL"
    
    if [ ! -z "$CALLBACK_URL" ]; then
        echo "Logic Apps Callback URL: ${CALLBACK_URL}"
    fi
    
    success "Azure Network Security Orchestration deployment completed successfully!"
    warning "Remember to run the cleanup script when you're done testing to avoid ongoing charges"
}

# Main deployment function
main() {
    log "Azure Network Security Orchestration Deployment Started"
    log "=================================================================="
    
    # Check if running in dry-run mode
    if [ "$1" = "--dry-run" ]; then
        log "Running in dry-run mode - no resources will be created"
        export DRY_RUN=true
    fi
    
    # Execute deployment steps
    check_prerequisites
    set_environment_variables
    
    if [ "$DRY_RUN" != "true" ]; then
        create_resource_group
        create_log_analytics
        create_key_vault
        create_storage_account
        create_network_infrastructure
        create_logic_apps_workflow
        configure_monitoring
        validate_deployment
        display_summary
        
        log "=================================================================="
        log "Deployment completed successfully!"
        log "=================================================================="
        log "Next steps:"
        log "1. Configure threat intelligence feeds in Logic Apps"
        log "2. Set up monitoring alerts for security events"
        log "3. Test the security orchestration workflow"
        log "4. Review and customize Network Security Group rules"
        log ""
        log "To clean up resources, run: ./destroy.sh"
    else
        log "Dry-run completed. No resources were created."
    fi
}

# Cleanup function for errors
cleanup_on_error() {
    error "An error occurred during deployment. Cleaning up resources..."
    
    if [ -f "${SCRIPT_DIR}/.env" ]; then
        source "${SCRIPT_DIR}/.env"
        
        # Delete resource group and all resources
        az group delete --name ${RESOURCE_GROUP} --yes --no-wait || true
        
        # Remove environment file
        rm -f "${SCRIPT_DIR}/.env"
        
        warning "Partial cleanup completed. You may need to manually remove remaining resources."
    fi
    
    exit 1
}

# Set up error handling
trap cleanup_on_error ERR

# Run main function
main "$@"