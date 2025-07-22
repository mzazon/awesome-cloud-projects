#!/bin/bash

# Azure Multi-Database ETL Orchestration Deployment Script
# This script deploys Azure Data Factory, Azure Database for MySQL, Key Vault, and monitoring components
# for enterprise-grade ETL orchestration across multiple database sources

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARN: $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
    exit 1
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1${NC}"
}

# Script usage information
usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -g, --resource-group    Resource group name (default: rg-etl-orchestration)"
    echo "  -l, --location          Azure region (default: eastus)"
    echo "  -s, --skip-prereqs      Skip prerequisites check"
    echo "  -d, --dry-run           Show what would be deployed without actually deploying"
    echo "  -v, --verbose           Enable verbose output"
    echo "  -h, --help              Show this help message"
    echo ""
    echo "Environment Variables:"
    echo "  MYSQL_ADMIN_PASSWORD    MySQL admin password (required)"
    echo "  SOURCE_MYSQL_CONNECTION Source MySQL connection string (required)"
    echo ""
    echo "Example:"
    echo "  export MYSQL_ADMIN_PASSWORD='ComplexPassword123!'"
    echo "  export SOURCE_MYSQL_CONNECTION='server=onprem-mysql.domain.com;port=3306;database=source_db;uid=etl_user;pwd=SecurePassword123!'"
    echo "  $0 -g my-resource-group -l westus2"
}

# Default values
RESOURCE_GROUP="rg-etl-orchestration"
LOCATION="eastus"
SKIP_PREREQS=false
DRY_RUN=false
VERBOSE=false

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
        -s|--skip-prereqs)
            SKIP_PREREQS=true
            shift
            ;;
        -d|--dry-run)
            DRY_RUN=true
            shift
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            error "Unknown option: $1"
            ;;
    esac
done

# Enable verbose output if requested
if [ "$VERBOSE" = true ]; then
    set -x
fi

# Prerequisites check
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        error "Azure CLI is not installed. Please install it from https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
    fi
    
    # Check Azure CLI version
    AZ_VERSION=$(az version --query '"azure-cli"' -o tsv)
    log "Azure CLI version: $AZ_VERSION"
    
    # Check if logged in to Azure
    if ! az account show &> /dev/null; then
        error "Not logged in to Azure. Please run 'az login' first."
    fi
    
    # Check if required tools are available
    if ! command -v openssl &> /dev/null; then
        error "OpenSSL is not installed. Please install it for generating random values."
    fi
    
    # Check for required environment variables
    if [ -z "${MYSQL_ADMIN_PASSWORD:-}" ]; then
        error "MYSQL_ADMIN_PASSWORD environment variable is required"
    fi
    
    if [ -z "${SOURCE_MYSQL_CONNECTION:-}" ]; then
        error "SOURCE_MYSQL_CONNECTION environment variable is required"
    fi
    
    # Validate password complexity
    if [[ ${#MYSQL_ADMIN_PASSWORD} -lt 8 ]]; then
        error "MYSQL_ADMIN_PASSWORD must be at least 8 characters long"
    fi
    
    # Check if subscription is set
    SUBSCRIPTION_ID=$(az account show --query id --output tsv)
    if [ -z "$SUBSCRIPTION_ID" ]; then
        error "No active Azure subscription found"
    fi
    
    log "Using subscription: $SUBSCRIPTION_ID"
    log "Prerequisites check completed successfully"
}

# Validate Azure region
validate_region() {
    log "Validating Azure region: $LOCATION"
    
    if ! az account list-locations --query "[?name=='$LOCATION']" --output tsv | grep -q "$LOCATION"; then
        error "Invalid Azure region: $LOCATION"
    fi
    
    log "Region validation completed"
}

# Generate unique resource names
generate_resource_names() {
    log "Generating unique resource names..."
    
    # Generate random suffix
    RANDOM_SUFFIX=$(openssl rand -hex 3)
    
    # Export resource names
    export ADF_NAME="adf-etl-${RANDOM_SUFFIX}"
    export MYSQL_SERVER_NAME="mysql-target-${RANDOM_SUFFIX}"
    export KEY_VAULT_NAME="kv-etl-${RANDOM_SUFFIX}"
    export LOG_ANALYTICS_NAME="la-etl-${RANDOM_SUFFIX}"
    export SUBSCRIPTION_ID=$(az account show --query id --output tsv)
    
    log "Resource names generated:"
    log "  Data Factory: $ADF_NAME"
    log "  MySQL Server: $MYSQL_SERVER_NAME"
    log "  Key Vault: $KEY_VAULT_NAME"
    log "  Log Analytics: $LOG_ANALYTICS_NAME"
}

# Create resource group
create_resource_group() {
    log "Creating resource group: $RESOURCE_GROUP"
    
    if [ "$DRY_RUN" = true ]; then
        info "DRY RUN: Would create resource group $RESOURCE_GROUP in $LOCATION"
        return
    fi
    
    if az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        warn "Resource group $RESOURCE_GROUP already exists"
    else
        az group create \
            --name "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --tags purpose=etl-orchestration environment=demo \
            --output none
        
        log "Resource group created successfully"
    fi
}

# Create Log Analytics workspace
create_log_analytics() {
    log "Creating Log Analytics workspace: $LOG_ANALYTICS_NAME"
    
    if [ "$DRY_RUN" = true ]; then
        info "DRY RUN: Would create Log Analytics workspace $LOG_ANALYTICS_NAME"
        return
    fi
    
    az monitor log-analytics workspace create \
        --resource-group "$RESOURCE_GROUP" \
        --workspace-name "$LOG_ANALYTICS_NAME" \
        --location "$LOCATION" \
        --sku PerGB2018 \
        --output none
    
    log "Log Analytics workspace created successfully"
}

# Create Azure Key Vault
create_key_vault() {
    log "Creating Azure Key Vault: $KEY_VAULT_NAME"
    
    if [ "$DRY_RUN" = true ]; then
        info "DRY RUN: Would create Key Vault $KEY_VAULT_NAME"
        return
    fi
    
    # Create Key Vault
    az keyvault create \
        --name "$KEY_VAULT_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --sku standard \
        --enable-soft-delete true \
        --enable-purge-protection true \
        --output none
    
    # Store secrets
    az keyvault secret set \
        --vault-name "$KEY_VAULT_NAME" \
        --name "mysql-source-connection-string" \
        --value "$SOURCE_MYSQL_CONNECTION" \
        --output none
    
    az keyvault secret set \
        --vault-name "$KEY_VAULT_NAME" \
        --name "mysql-admin-username" \
        --value "mysqladmin" \
        --output none
    
    az keyvault secret set \
        --vault-name "$KEY_VAULT_NAME" \
        --name "mysql-admin-password" \
        --value "$MYSQL_ADMIN_PASSWORD" \
        --output none
    
    log "Key Vault created and secrets stored successfully"
}

# Create Azure Database for MySQL
create_mysql_server() {
    log "Creating Azure Database for MySQL: $MYSQL_SERVER_NAME"
    
    if [ "$DRY_RUN" = true ]; then
        info "DRY RUN: Would create MySQL server $MYSQL_SERVER_NAME"
        return
    fi
    
    # Create MySQL Flexible Server
    az mysql flexible-server create \
        --resource-group "$RESOURCE_GROUP" \
        --name "$MYSQL_SERVER_NAME" \
        --location "$LOCATION" \
        --admin-user "mysqladmin" \
        --admin-password "$MYSQL_ADMIN_PASSWORD" \
        --sku-name Standard_D2ds_v4 \
        --tier GeneralPurpose \
        --storage-size 128 \
        --version 8.0 \
        --high-availability Enabled \
        --zone 1 \
        --standby-zone 2 \
        --output none
    
    # Configure firewall for Azure services
    az mysql flexible-server firewall-rule create \
        --resource-group "$RESOURCE_GROUP" \
        --name "$MYSQL_SERVER_NAME" \
        --rule-name "AllowAzureServices" \
        --start-ip-address 0.0.0.0 \
        --end-ip-address 0.0.0.0 \
        --output none
    
    # Create target database
    az mysql flexible-server db create \
        --resource-group "$RESOURCE_GROUP" \
        --server-name "$MYSQL_SERVER_NAME" \
        --database-name "consolidated_data" \
        --output none
    
    log "MySQL server created successfully with high availability"
}

# Create Azure Data Factory
create_data_factory() {
    log "Creating Azure Data Factory: $ADF_NAME"
    
    if [ "$DRY_RUN" = true ]; then
        info "DRY RUN: Would create Data Factory $ADF_NAME"
        return
    fi
    
    # Create Data Factory
    az datafactory create \
        --resource-group "$RESOURCE_GROUP" \
        --name "$ADF_NAME" \
        --location "$LOCATION" \
        --output none
    
    # Configure managed identity
    az datafactory update \
        --resource-group "$RESOURCE_GROUP" \
        --name "$ADF_NAME" \
        --set identity.type=SystemAssigned \
        --output none
    
    # Get managed identity principal ID
    ADF_IDENTITY_ID=$(az datafactory show \
        --resource-group "$RESOURCE_GROUP" \
        --name "$ADF_NAME" \
        --query identity.principalId -o tsv)
    
    log "Data Factory created with managed identity: $ADF_IDENTITY_ID"
    
    # Grant Key Vault access to Data Factory
    az keyvault set-policy \
        --name "$KEY_VAULT_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --object-id "$ADF_IDENTITY_ID" \
        --secret-permissions get list \
        --output none
    
    log "Key Vault access configured for Data Factory"
}

# Create Self-Hosted Integration Runtime
create_integration_runtime() {
    log "Creating Self-Hosted Integration Runtime"
    
    if [ "$DRY_RUN" = true ]; then
        info "DRY RUN: Would create Self-Hosted Integration Runtime"
        return
    fi
    
    # Create integration runtime
    az datafactory integration-runtime create \
        --resource-group "$RESOURCE_GROUP" \
        --factory-name "$ADF_NAME" \
        --name "SelfHostedIR" \
        --type SelfHosted \
        --description "Integration Runtime for on-premises MySQL connectivity" \
        --output none
    
    # Get authentication key
    IR_AUTH_KEY=$(az datafactory integration-runtime get-connection-info \
        --resource-group "$RESOURCE_GROUP" \
        --factory-name "$ADF_NAME" \
        --name "SelfHostedIR" \
        --query authKey1 -o tsv)
    
    log "Self-Hosted Integration Runtime created"
    info "Authentication Key: $IR_AUTH_KEY"
    info "Install the Integration Runtime on your on-premises server using this key"
}

# Configure monitoring and alerting
configure_monitoring() {
    log "Configuring monitoring and alerting"
    
    if [ "$DRY_RUN" = true ]; then
        info "DRY RUN: Would configure monitoring and alerting"
        return
    fi
    
    # Create diagnostic settings
    az monitor diagnostic-settings create \
        --resource "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.DataFactory/factories/$ADF_NAME" \
        --name "DataFactoryDiagnostics" \
        --workspace "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.OperationalInsights/workspaces/$LOG_ANALYTICS_NAME" \
        --logs '[
            {
                "category": "PipelineRuns",
                "enabled": true,
                "retentionPolicy": {
                    "enabled": true,
                    "days": 90
                }
            },
            {
                "category": "ActivityRuns",
                "enabled": true,
                "retentionPolicy": {
                    "enabled": true,
                    "days": 90
                }
            },
            {
                "category": "TriggerRuns",
                "enabled": true,
                "retentionPolicy": {
                    "enabled": true,
                    "days": 90
                }
            }
        ]' \
        --metrics '[
            {
                "category": "AllMetrics",
                "enabled": true,
                "retentionPolicy": {
                    "enabled": true,
                    "days": 90
                }
            }
        ]' \
        --output none
    
    # Create alert rule for pipeline failures
    az monitor metrics alert create \
        --name "ETL-Pipeline-Failure-Alert" \
        --resource-group "$RESOURCE_GROUP" \
        --scopes "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.DataFactory/factories/$ADF_NAME" \
        --condition "count 'Pipeline failed runs' > 0" \
        --description "Alert when ETL pipeline fails" \
        --evaluation-frequency 5m \
        --window-size 5m \
        --severity 2 \
        --output none
    
    log "Monitoring and alerting configured successfully"
}

# Validate deployment
validate_deployment() {
    log "Validating deployment..."
    
    if [ "$DRY_RUN" = true ]; then
        info "DRY RUN: Would validate deployment"
        return
    fi
    
    # Check Data Factory status
    ADF_STATUS=$(az datafactory show \
        --resource-group "$RESOURCE_GROUP" \
        --name "$ADF_NAME" \
        --query provisioningState -o tsv)
    
    if [ "$ADF_STATUS" != "Succeeded" ]; then
        error "Data Factory deployment failed with status: $ADF_STATUS"
    fi
    
    # Check MySQL server status
    MYSQL_STATUS=$(az mysql flexible-server show \
        --resource-group "$RESOURCE_GROUP" \
        --name "$MYSQL_SERVER_NAME" \
        --query state -o tsv)
    
    if [ "$MYSQL_STATUS" != "Ready" ]; then
        error "MySQL server deployment failed with status: $MYSQL_STATUS"
    fi
    
    # Check Key Vault status
    KV_STATUS=$(az keyvault show \
        --name "$KEY_VAULT_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --query properties.provisioningState -o tsv)
    
    if [ "$KV_STATUS" != "Succeeded" ]; then
        error "Key Vault deployment failed with status: $KV_STATUS"
    fi
    
    log "Deployment validation completed successfully"
}

# Output deployment summary
output_summary() {
    log "Deployment Summary:"
    log "==================="
    log "Resource Group: $RESOURCE_GROUP"
    log "Location: $LOCATION"
    log "Data Factory: $ADF_NAME"
    log "MySQL Server: $MYSQL_SERVER_NAME"
    log "Key Vault: $KEY_VAULT_NAME"
    log "Log Analytics: $LOG_ANALYTICS_NAME"
    log ""
    log "Next Steps:"
    log "1. Install and configure the Self-Hosted Integration Runtime on your on-premises server"
    log "2. Configure Data Factory linked services and pipelines through the Azure portal"
    log "3. Set up triggers for automated ETL execution"
    log "4. Monitor pipeline performance through Azure Monitor"
    log ""
    log "Resources can be accessed through the Azure portal or using Azure CLI"
}

# Main deployment function
main() {
    log "Starting Azure Multi-Database ETL Orchestration deployment..."
    
    # Check prerequisites unless skipped
    if [ "$SKIP_PREREQS" = false ]; then
        check_prerequisites
    fi
    
    # Validate region
    validate_region
    
    # Generate resource names
    generate_resource_names
    
    # Create resources
    create_resource_group
    create_log_analytics
    create_key_vault
    create_mysql_server
    create_data_factory
    create_integration_runtime
    configure_monitoring
    
    # Validate deployment
    validate_deployment
    
    # Output summary
    output_summary
    
    log "Deployment completed successfully!"
}

# Handle script interruption
cleanup_on_error() {
    error "Script interrupted. Some resources may have been created."
    error "Run the destroy.sh script to clean up any created resources."
    exit 1
}

# Set up signal handling
trap cleanup_on_error INT TERM

# Run main function
main "$@"