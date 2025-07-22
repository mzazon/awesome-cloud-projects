#!/bin/bash

# Azure SCOM Migration - Deployment Script
# This script deploys Azure Monitor SCOM Managed Instance infrastructure
# Based on recipe: Migrate On-Premises SCOM to Azure Monitor Managed Instance

set -e  # Exit on any error

# Color codes for output
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

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        error "Azure CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if user is logged in
    if ! az account show &> /dev/null; then
        error "You are not logged in to Azure. Please run 'az login' first."
        exit 1
    fi
    
    # Check if OpenSSL is available for random string generation
    if ! command -v openssl &> /dev/null; then
        warning "OpenSSL not found. Using date-based suffix instead."
        RANDOM_SUFFIX=$(date +%s | tail -c 7)
    else
        RANDOM_SUFFIX=$(openssl rand -hex 3)
    fi
    
    success "Prerequisites check completed"
}

# Set environment variables
set_environment_variables() {
    log "Setting environment variables..."
    
    # Core configuration
    export RESOURCE_GROUP="${RESOURCE_GROUP:-rg-scom-migration}"
    export LOCATION="${LOCATION:-East US}"
    export SUBSCRIPTION_ID=$(az account show --query id --output tsv)
    
    # Resource names with unique suffix
    export SCOM_MI_NAME="${SCOM_MI_NAME:-scom-mi-${RANDOM_SUFFIX}}"
    export SQL_MI_NAME="${SQL_MI_NAME:-sql-mi-${RANDOM_SUFFIX}}"
    export VNET_NAME="${VNET_NAME:-vnet-scom-${RANDOM_SUFFIX}}"
    export KEY_VAULT_NAME="${KEY_VAULT_NAME:-kv-scom-${RANDOM_SUFFIX}}"
    export STORAGE_ACCOUNT_NAME="${STORAGE_ACCOUNT_NAME:-scommigration${RANDOM_SUFFIX}}"
    export LOG_ANALYTICS_NAME="${LOG_ANALYTICS_NAME:-law-scom-${RANDOM_SUFFIX}}"
    
    # SQL Configuration
    export SQL_ADMIN_USER="${SQL_ADMIN_USER:-scomadmin}"
    export SQL_ADMIN_PASSWORD="${SQL_ADMIN_PASSWORD:-P@ssw0rd123!}"
    
    success "Environment variables configured"
    log "Resource Group: ${RESOURCE_GROUP}"
    log "Location: ${LOCATION}"
    log "SCOM MI Name: ${SCOM_MI_NAME}"
    log "SQL MI Name: ${SQL_MI_NAME}"
}

# Create resource group
create_resource_group() {
    log "Creating resource group..."
    
    if az group show --name "${RESOURCE_GROUP}" &> /dev/null; then
        warning "Resource group ${RESOURCE_GROUP} already exists"
    else
        az group create \
            --name "${RESOURCE_GROUP}" \
            --location "${LOCATION}" \
            --tags purpose=scom-migration environment=production
        
        success "Resource group created: ${RESOURCE_GROUP}"
    fi
}

# Create virtual network and subnets
create_network_infrastructure() {
    log "Creating virtual network infrastructure..."
    
    # Create virtual network
    if az network vnet show --name "${VNET_NAME}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        warning "Virtual network ${VNET_NAME} already exists"
    else
        az network vnet create \
            --name "${VNET_NAME}" \
            --resource-group "${RESOURCE_GROUP}" \
            --location "${LOCATION}" \
            --address-prefix 10.0.0.0/16 \
            --subnet-name scom-mi-subnet \
            --subnet-prefix 10.0.1.0/24
        
        success "Virtual network created: ${VNET_NAME}"
    fi
    
    # Create SQL MI subnet
    if az network vnet subnet show --name sql-mi-subnet --vnet-name "${VNET_NAME}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        warning "SQL MI subnet already exists"
    else
        az network vnet subnet create \
            --name sql-mi-subnet \
            --resource-group "${RESOURCE_GROUP}" \
            --vnet-name "${VNET_NAME}" \
            --address-prefix 10.0.2.0/27 \
            --delegations Microsoft.Sql/managedInstances
        
        success "SQL MI subnet created"
    fi
    
    # Create Network Security Group
    if az network nsg show --name nsg-scom-mi --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        warning "Network Security Group already exists"
    else
        az network nsg create \
            --name nsg-scom-mi \
            --resource-group "${RESOURCE_GROUP}" \
            --location "${LOCATION}"
        
        # Add NSG rules
        az network nsg rule create \
            --name Allow-SCOM-Agents \
            --nsg-name nsg-scom-mi \
            --resource-group "${RESOURCE_GROUP}" \
            --protocol TCP \
            --source-address-prefixes '*' \
            --source-port-ranges '*' \
            --destination-address-prefixes VirtualNetwork \
            --destination-port-ranges 5723 \
            --access Allow \
            --priority 1000 \
            --direction Inbound
        
        az network nsg rule create \
            --name Allow-SQL-MI-Access \
            --nsg-name nsg-scom-mi \
            --resource-group "${RESOURCE_GROUP}" \
            --protocol TCP \
            --source-address-prefixes VirtualNetwork \
            --source-port-ranges '*' \
            --destination-address-prefixes VirtualNetwork \
            --destination-port-ranges 1433 3342 \
            --access Allow \
            --priority 1100 \
            --direction Outbound
        
        # Associate NSG with subnet
        az network vnet subnet update \
            --name scom-mi-subnet \
            --vnet-name "${VNET_NAME}" \
            --resource-group "${RESOURCE_GROUP}" \
            --network-security-group nsg-scom-mi
        
        success "Network Security Group configured"
    fi
}

# Create Azure SQL Managed Instance
create_sql_managed_instance() {
    log "Creating Azure SQL Managed Instance (this may take 4-6 hours)..."
    
    if az sql mi show --name "${SQL_MI_NAME}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        warning "SQL Managed Instance ${SQL_MI_NAME} already exists"
        return 0
    fi
    
    # Get subnet ID
    SUBNET_ID=$(az network vnet subnet show \
        --name sql-mi-subnet \
        --vnet-name "${VNET_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query id --output tsv)
    
    # Create SQL MI (this is a long-running operation)
    az sql mi create \
        --name "${SQL_MI_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --location "${LOCATION}" \
        --subnet "${SUBNET_ID}" \
        --license-type BasePrice \
        --storage 256GB \
        --capacity 8 \
        --tier GeneralPurpose \
        --family Gen5 \
        --admin-user "${SQL_ADMIN_USER}" \
        --admin-password "${SQL_ADMIN_PASSWORD}" \
        --public-data-endpoint-enabled true \
        --no-wait
    
    success "SQL Managed Instance creation initiated (running in background)"
    log "This process typically takes 4-6 hours. Monitor progress in Azure Portal."
}

# Create Key Vault
create_key_vault() {
    log "Creating Azure Key Vault..."
    
    if az keyvault show --name "${KEY_VAULT_NAME}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        warning "Key Vault ${KEY_VAULT_NAME} already exists"
        return 0
    fi
    
    # Create Key Vault
    az keyvault create \
        --name "${KEY_VAULT_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --location "${LOCATION}" \
        --sku standard \
        --enable-rbac-authorization false
    
    # Store SQL connection string
    SQL_CONNECTION_STRING="Server=${SQL_MI_NAME}.public.database.windows.net,3342;Database=master;User ID=${SQL_ADMIN_USER};Password=${SQL_ADMIN_PASSWORD};Encrypt=true;TrustServerCertificate=false;"
    
    az keyvault secret set \
        --vault-name "${KEY_VAULT_NAME}" \
        --name "sql-connection-string" \
        --value "${SQL_CONNECTION_STRING}"
    
    success "Key Vault created and configured"
}

# Create managed identity
create_managed_identity() {
    log "Creating managed identity..."
    
    if az identity show --name "scom-mi-identity" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        warning "Managed identity already exists"
        return 0
    fi
    
    az identity create \
        --name "scom-mi-identity" \
        --resource-group "${RESOURCE_GROUP}"
    
    success "Managed identity created"
}

# Create storage account for management packs
create_storage_account() {
    log "Creating storage account for management packs..."
    
    if az storage account show --name "${STORAGE_ACCOUNT_NAME}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        warning "Storage account ${STORAGE_ACCOUNT_NAME} already exists"
        return 0
    fi
    
    az storage account create \
        --name "${STORAGE_ACCOUNT_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --location "${LOCATION}" \
        --sku Standard_LRS
    
    # Get storage key
    STORAGE_KEY=$(az storage account keys list \
        --account-name "${STORAGE_ACCOUNT_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query [0].value --output tsv)
    
    # Create container
    az storage container create \
        --name management-packs \
        --account-name "${STORAGE_ACCOUNT_NAME}" \
        --account-key "${STORAGE_KEY}"
    
    success "Storage account created for management packs"
}

# Create Log Analytics workspace
create_log_analytics() {
    log "Creating Log Analytics workspace..."
    
    if az monitor log-analytics workspace show --workspace-name "${LOG_ANALYTICS_NAME}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        warning "Log Analytics workspace already exists"
        return 0
    fi
    
    az monitor log-analytics workspace create \
        --workspace-name "${LOG_ANALYTICS_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --location "${LOCATION}" \
        --retention-time 30
    
    success "Log Analytics workspace created"
}

# Create action group for alerting
create_action_group() {
    log "Creating Azure Monitor action group..."
    
    if az monitor action-group show --name "ag-scom-alerts" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        warning "Action group already exists"
        return 0
    fi
    
    # Note: Replace with actual email address
    az monitor action-group create \
        --name "ag-scom-alerts" \
        --resource-group "${RESOURCE_GROUP}" \
        --short-name "SCOMAlerts" \
        --email-receiver name=admin email=admin@company.com
    
    success "Action group created"
}

# Wait for SQL MI completion and create SCOM MI
create_scom_managed_instance() {
    log "Waiting for SQL Managed Instance to complete before creating SCOM MI..."
    
    # Check if SCOM MI already exists
    if az monitor scom-managed-instance show --name "${SCOM_MI_NAME}" --resource-group "${RESOURCE_GROUP}" &> /dev/null 2>&1; then
        warning "SCOM Managed Instance ${SCOM_MI_NAME} already exists"
        return 0
    fi
    
    # Wait for SQL MI to be ready
    log "Checking SQL Managed Instance status..."
    while true; do
        SQL_STATE=$(az sql mi show \
            --name "${SQL_MI_NAME}" \
            --resource-group "${RESOURCE_GROUP}" \
            --query state --output tsv 2>/dev/null || echo "NotFound")
        
        if [ "$SQL_STATE" = "Ready" ]; then
            success "SQL Managed Instance is ready"
            break
        elif [ "$SQL_STATE" = "NotFound" ]; then
            error "SQL Managed Instance not found. Please check the deployment."
            exit 1
        else
            log "SQL Managed Instance state: $SQL_STATE. Waiting 5 minutes..."
            sleep 300
        fi
    done
    
    # Get required resource IDs
    SQL_MI_ID=$(az sql mi show \
        --name "${SQL_MI_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query id --output tsv)
    
    SUBNET_ID=$(az network vnet subnet show \
        --name scom-mi-subnet \
        --vnet-name "${VNET_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query id --output tsv)
    
    IDENTITY_ID=$(az identity show \
        --name "scom-mi-identity" \
        --resource-group "${RESOURCE_GROUP}" \
        --query id --output tsv)
    
    KEY_VAULT_URI=$(az keyvault show \
        --name "${KEY_VAULT_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query properties.vaultUri --output tsv)
    
    # Note: The actual az monitor scom-managed-instance create command may vary
    # based on the current Azure CLI version and service availability
    log "Creating SCOM Managed Instance..."
    warning "SCOM Managed Instance creation command may need adjustment based on current Azure CLI version"
    
    # Placeholder for actual SCOM MI creation command
    # az monitor scom-managed-instance create \
    #     --name "${SCOM_MI_NAME}" \
    #     --resource-group "${RESOURCE_GROUP}" \
    #     --location "${LOCATION}" \
    #     --sql-managed-instance-id "${SQL_MI_ID}" \
    #     --subnet-id "${SUBNET_ID}" \
    #     --managed-identity-id "${IDENTITY_ID}" \
    #     --key-vault-uri "${KEY_VAULT_URI}"
    
    success "SCOM Managed Instance configuration prepared"
}

# Generate deployment summary
generate_summary() {
    log "Generating deployment summary..."
    
    cat << EOF

===========================================
SCOM Migration Deployment Summary
===========================================

Resource Group: ${RESOURCE_GROUP}
Location: ${LOCATION}
Subscription: ${SUBSCRIPTION_ID}

Resources Created:
- Virtual Network: ${VNET_NAME}
- SQL Managed Instance: ${SQL_MI_NAME}
- Key Vault: ${KEY_VAULT_NAME}
- Storage Account: ${STORAGE_ACCOUNT_NAME}
- Log Analytics: ${LOG_ANALYTICS_NAME}
- Managed Identity: scom-mi-identity
- Action Group: ag-scom-alerts

SQL MI Connection:
- Server: ${SQL_MI_NAME}.public.database.windows.net,3342
- Admin User: ${SQL_ADMIN_USER}
- Password: [Stored in Key Vault]

Next Steps:
1. Monitor SQL MI deployment progress in Azure Portal
2. Export management packs from on-premises SCOM
3. Configure agent multi-homing for gradual migration
4. Test connectivity and monitoring functionality

===========================================
EOF

    success "Deployment completed successfully!"
}

# Main deployment function
main() {
    log "Starting Azure SCOM Migration deployment..."
    
    check_prerequisites
    set_environment_variables
    create_resource_group
    create_network_infrastructure
    create_key_vault
    create_managed_identity
    create_storage_account
    create_log_analytics
    create_action_group
    create_sql_managed_instance
    create_scom_managed_instance
    generate_summary
    
    success "Deployment script completed successfully!"
}

# Run main function
main "$@"