#!/bin/bash

# Resilient Stateful Microservices with Azure Service Fabric and Durable Functions
# Deployment Script
# 
# This script automates the deployment of a complete microservices orchestration solution
# using Azure Service Fabric for stateful services and Azure Durable Functions for workflow coordination.

set -euo pipefail

# Configuration and Logging
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_FILE="${SCRIPT_DIR}/deployment.log"
readonly CONFIG_FILE="${SCRIPT_DIR}/.deployment_config"

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Global variables
DEPLOYMENT_MODE="full"
SKIP_PREREQUISITES="false"
DRY_RUN="false"
VERBOSE="false"

# Logging functions
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "[$timestamp] [$level] $message" | tee -a "$LOG_FILE"
}

log_info() {
    log "INFO" "${BLUE}$*${NC}"
}

log_success() {
    log "SUCCESS" "${GREEN}$*${NC}"
}

log_warning() {
    log "WARNING" "${YELLOW}$*${NC}"
}

log_error() {
    log "ERROR" "${RED}$*${NC}"
}

# Help function
show_help() {
    cat << EOF
Usage: $0 [OPTIONS]

Deploy Azure Service Fabric and Durable Functions microservices orchestration solution.

OPTIONS:
    -h, --help              Show this help message
    -m, --mode MODE         Deployment mode: full, minimal, dev (default: full)
    -s, --skip-prereqs      Skip prerequisites check
    -d, --dry-run          Show what would be deployed without actually deploying
    -v, --verbose          Enable verbose logging
    --force                Force deployment even if resources exist

DEPLOYMENT MODES:
    full      - Complete production-ready deployment with all features
    minimal   - Basic deployment with essential components only
    dev       - Development environment with reduced costs and relaxed security

EXAMPLES:
    $0                                    # Full deployment
    $0 --mode dev --verbose              # Development deployment with verbose output
    $0 --dry-run                         # Preview deployment without executing
    $0 --skip-prereqs --force            # Skip checks and force deployment

EOF
}

# Parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
                ;;
            -m|--mode)
                DEPLOYMENT_MODE="$2"
                shift 2
                ;;
            -s|--skip-prereqs)
                SKIP_PREREQUISITES="true"
                shift
                ;;
            -d|--dry-run)
                DRY_RUN="true"
                shift
                ;;
            -v|--verbose)
                VERBOSE="true"
                shift
                ;;
            --force)
                FORCE_DEPLOYMENT="true"
                shift
                ;;
            *)
                log_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

# Prerequisites check
check_prerequisites() {
    if [[ "$SKIP_PREREQUISITES" == "true" ]]; then
        log_warning "Skipping prerequisites check as requested"
        return 0
    fi

    log_info "Checking prerequisites..."

    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        log_error "Azure CLI is not installed. Please install it from https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
        exit 1
    fi

    # Check Azure CLI version
    local az_version=$(az version --query '"azure-cli"' -o tsv)
    log_info "Azure CLI version: $az_version"

    # Check if logged in to Azure
    if ! az account show &> /dev/null; then
        log_error "Not logged in to Azure. Run 'az login' first."
        exit 1
    fi

    # Get subscription info
    local subscription_id=$(az account show --query id -o tsv)
    local subscription_name=$(az account show --query name -o tsv)
    log_info "Using subscription: $subscription_name ($subscription_id)"

    # Check required resource providers
    local providers=("Microsoft.ServiceFabric" "Microsoft.Web" "Microsoft.Storage" "Microsoft.Sql" "Microsoft.Insights")
    for provider in "${providers[@]}"; do
        local state=$(az provider show --namespace "$provider" --query registrationState -o tsv 2>/dev/null || echo "NotRegistered")
        if [[ "$state" != "Registered" ]]; then
            log_warning "Resource provider $provider is not registered. Registering..."
            if [[ "$DRY_RUN" == "false" ]]; then
                az provider register --namespace "$provider" --wait
            fi
        fi
    done

    # Check available VM cores quota for Service Fabric
    local location=$(az configure --list-defaults --query "[?name=='location'].value" -o tsv)
    if [[ -z "$location" ]]; then
        location="eastus"
        log_warning "No default location set, using eastus"
    fi

    log_info "Checking compute quota in region: $location"
    local vm_quota=$(az vm list-usage --location "$location" --query "[?name.value=='standardDSv3Family'].currentValue" -o tsv 2>/dev/null || echo "0")
    local vm_limit=$(az vm list-usage --location "$location" --query "[?name.value=='standardDSv3Family'].limit" -o tsv 2>/dev/null || echo "0")
    
    if [[ $(($vm_limit - $vm_quota)) -lt 6 ]]; then
        log_warning "Low VM quota available ($((vm_limit - vm_quota)) cores remaining). Service Fabric requires at least 6 cores."
    fi

    # Check .NET SDK for local development (optional)
    if command -v dotnet &> /dev/null; then
        local dotnet_version=$(dotnet --version)
        log_info ".NET SDK version: $dotnet_version"
    else
        log_warning ".NET SDK not found. Required for local Service Fabric development."
    fi

    log_success "Prerequisites check completed successfully"
}

# Generate unique resource names
generate_resource_names() {
    # Use consistent random suffix
    if [[ -f "$CONFIG_FILE" ]]; then
        source "$CONFIG_FILE"
        log_info "Loading existing configuration from $CONFIG_FILE"
    else
        RANDOM_SUFFIX=$(openssl rand -hex 3 2>/dev/null || printf "%06x" $((RANDOM % 16777216)))
        
        cat > "$CONFIG_FILE" << EOF
# Deployment configuration
RANDOM_SUFFIX="$RANDOM_SUFFIX"
DEPLOYMENT_TIMESTAMP="$(date -u +%Y%m%d%H%M%S)"
DEPLOYMENT_MODE="$DEPLOYMENT_MODE"
EOF
        log_info "Generated new configuration in $CONFIG_FILE"
    fi

    # Set resource names based on deployment mode
    case "$DEPLOYMENT_MODE" in
        "dev")
            RESOURCE_GROUP_PREFIX="rg-dev-microservices"
            VM_SIZE="Standard_D2s_v3"
            CLUSTER_SIZE="3"
            SQL_TIER="Basic"
            ;;
        "minimal")
            RESOURCE_GROUP_PREFIX="rg-min-microservices"
            VM_SIZE="Standard_D2s_v3"
            CLUSTER_SIZE="3"
            SQL_TIER="S0"
            ;;
        "full"|*)
            RESOURCE_GROUP_PREFIX="rg-microservices"
            VM_SIZE="Standard_D4s_v3"
            CLUSTER_SIZE="5"
            SQL_TIER="S1"
            ;;
    esac

    # Export all variables for use in functions
    export RESOURCE_GROUP="${RESOURCE_GROUP_PREFIX}-${RANDOM_SUFFIX}"
    export LOCATION="${AZURE_LOCATION:-eastus}"
    export CLUSTER_NAME="sf-cluster-${RANDOM_SUFFIX}"
    export SQL_SERVER_NAME="sql-orchestration-${RANDOM_SUFFIX}"
    export SQL_DATABASE_NAME="MicroservicesState"
    export FUNCTION_APP_NAME="func-orchestrator-${RANDOM_SUFFIX}"
    export STORAGE_ACCOUNT_NAME="st${RANDOM_SUFFIX}"
    export APP_INSIGHTS_NAME="ai-orchestration-${RANDOM_SUFFIX}"
    export KEYVAULT_NAME="kv-orchestration-${RANDOM_SUFFIX}"

    # Append to config file
    cat >> "$CONFIG_FILE" << EOF
RESOURCE_GROUP="$RESOURCE_GROUP"
LOCATION="$LOCATION"
CLUSTER_NAME="$CLUSTER_NAME"
SQL_SERVER_NAME="$SQL_SERVER_NAME"
SQL_DATABASE_NAME="$SQL_DATABASE_NAME"
FUNCTION_APP_NAME="$FUNCTION_APP_NAME"
STORAGE_ACCOUNT_NAME="$STORAGE_ACCOUNT_NAME"
APP_INSIGHTS_NAME="$APP_INSIGHTS_NAME"
KEYVAULT_NAME="$KEYVAULT_NAME"
VM_SIZE="$VM_SIZE"
CLUSTER_SIZE="$CLUSTER_SIZE"
SQL_TIER="$SQL_TIER"
EOF

    log_info "Resource names configured for $DEPLOYMENT_MODE mode:"
    log_info "  Resource Group: $RESOURCE_GROUP"
    log_info "  Location: $LOCATION"
    log_info "  Service Fabric Cluster: $CLUSTER_NAME"
    log_info "  Function App: $FUNCTION_APP_NAME"
}

# Execute Azure CLI command with error handling
execute_az_command() {
    local description="$1"
    shift
    local command=("$@")

    log_info "Executing: $description"
    if [[ "$VERBOSE" == "true" ]]; then
        log_info "Command: ${command[*]}"
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would execute: ${command[*]}"
        return 0
    fi

    local output
    local exit_code
    
    if [[ "$VERBOSE" == "true" ]]; then
        output=$("${command[@]}" 2>&1) || exit_code=$?
    else
        output=$("${command[@]}" 2>&1) || exit_code=$?
    fi
    
    if [[ ${exit_code:-0} -eq 0 ]]; then
        log_success "$description completed successfully"
        if [[ "$VERBOSE" == "true" && -n "$output" ]]; then
            log_info "Output: $output"
        fi
        return 0
    else
        log_error "$description failed (exit code: ${exit_code:-0})"
        log_error "Output: $output"
        return ${exit_code:-1}
    fi
}

# Create resource group
create_resource_group() {
    log_info "Creating resource group $RESOURCE_GROUP..."
    
    # Check if resource group already exists
    if az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        log_warning "Resource group $RESOURCE_GROUP already exists"
        return 0
    fi

    execute_az_command "Create resource group" \
        az group create \
        --name "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --tags \
        purpose=microservices-orchestration \
        environment="$DEPLOYMENT_MODE" \
        deployed-by=automation \
        deployment-timestamp="$(date -u +%Y%m%d%H%M%S)"
}

# Create Key Vault for secrets management
create_key_vault() {
    log_info "Creating Key Vault $KEYVAULT_NAME..."
    
    execute_az_command "Create Key Vault" \
        az keyvault create \
        --name "$KEYVAULT_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --sku standard \
        --enable-soft-delete true \
        --enable-purge-protection true \
        --retention-days 7

    # Store SQL admin password in Key Vault
    local sql_password=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25)
    execute_az_command "Store SQL password in Key Vault" \
        az keyvault secret set \
        --vault-name "$KEYVAULT_NAME" \
        --name "sql-admin-password" \
        --value "$sql_password"

    # Store Service Fabric certificate password
    local cert_password=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25)
    execute_az_command "Store certificate password in Key Vault" \
        az keyvault secret set \
        --vault-name "$KEYVAULT_NAME" \
        --name "sf-cert-password" \
        --value "$cert_password"
}

# Create Application Insights
create_application_insights() {
    log_info "Creating Application Insights $APP_INSIGHTS_NAME..."
    
    execute_az_command "Create Application Insights" \
        az monitor app-insights component create \
        --app "$APP_INSIGHTS_NAME" \
        --location "$LOCATION" \
        --resource-group "$RESOURCE_GROUP" \
        --kind web \
        --application-type web

    # Get instrumentation key for later use
    APP_INSIGHTS_KEY=$(az monitor app-insights component show \
        --app "$APP_INSIGHTS_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --query instrumentationKey --output tsv)
    
    log_info "Application Insights instrumentation key: $APP_INSIGHTS_KEY"
}

# Create Azure SQL Database
create_sql_database() {
    log_info "Creating Azure SQL Database..."
    
    # Get SQL password from Key Vault
    local sql_password=$(az keyvault secret show \
        --vault-name "$KEYVAULT_NAME" \
        --name "sql-admin-password" \
        --query value -o tsv)

    # Create SQL Server
    execute_az_command "Create SQL Server" \
        az sql server create \
        --name "$SQL_SERVER_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --admin-user sqladmin \
        --admin-password "$sql_password" \
        --enable-ad-only-auth false

    # Configure firewall to allow Azure services
    execute_az_command "Configure SQL Server firewall" \
        az sql server firewall-rule create \
        --resource-group "$RESOURCE_GROUP" \
        --server "$SQL_SERVER_NAME" \
        --name AllowAzureServices \
        --start-ip-address 0.0.0.0 \
        --end-ip-address 0.0.0.0

    # Create database
    execute_az_command "Create SQL Database" \
        az sql db create \
        --resource-group "$RESOURCE_GROUP" \
        --server "$SQL_SERVER_NAME" \
        --name "$SQL_DATABASE_NAME" \
        --service-objective "$SQL_TIER" \
        --backup-storage-redundancy Local

    log_success "SQL Database created successfully"
}

# Create Storage Account for Durable Functions
create_storage_account() {
    log_info "Creating Storage Account $STORAGE_ACCOUNT_NAME..."
    
    execute_az_command "Create Storage Account" \
        az storage account create \
        --name "$STORAGE_ACCOUNT_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --sku Standard_LRS \
        --kind StorageV2 \
        --access-tier Hot \
        --https-only true \
        --min-tls-version TLS1_2 \
        --allow-blob-public-access false

    log_success "Storage Account created successfully"
}

# Create Service Fabric Cluster
create_service_fabric_cluster() {
    log_info "Creating Service Fabric Cluster $CLUSTER_NAME..."
    log_warning "Service Fabric cluster creation takes 10-15 minutes..."
    
    # Get certificate password from Key Vault
    local cert_password=$(az keyvault secret show \
        --vault-name "$KEYVAULT_NAME" \
        --name "sf-cert-password" \
        --query value -o tsv)

    # Create certificates directory
    mkdir -p "$SCRIPT_DIR/certificates"

    execute_az_command "Create Service Fabric Cluster" \
        az sf cluster create \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --cluster-name "$CLUSTER_NAME" \
        --cluster-size "$CLUSTER_SIZE" \
        --vm-password "$(az keyvault secret show --vault-name "$KEYVAULT_NAME" --name "sql-admin-password" --query value -o tsv)" \
        --vm-user-name sfuser \
        --vm-sku "$VM_SIZE" \
        --os WindowsServer2019Datacenter \
        --certificate-output-folder "$SCRIPT_DIR/certificates" \
        --certificate-password "$cert_password" \
        --upgrade-mode Automatic

    log_success "Service Fabric Cluster created successfully"
}

# Create Function App
create_function_app() {
    log_info "Creating Function App $FUNCTION_APP_NAME..."
    
    execute_az_command "Create Function App" \
        az functionapp create \
        --resource-group "$RESOURCE_GROUP" \
        --consumption-plan-location "$LOCATION" \
        --runtime dotnet \
        --functions-version 4 \
        --name "$FUNCTION_APP_NAME" \
        --storage-account "$STORAGE_ACCOUNT_NAME" \
        --disable-app-insights false \
        --app-insights "$APP_INSIGHTS_NAME"

    # Get SQL password for connection string
    local sql_password=$(az keyvault secret show \
        --vault-name "$KEYVAULT_NAME" \
        --name "sql-admin-password" \
        --query value -o tsv)

    # Configure Function App settings
    execute_az_command "Configure Function App settings" \
        az functionapp config appsettings set \
        --name "$FUNCTION_APP_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --settings \
        "SqlConnectionString=Server=tcp:${SQL_SERVER_NAME}.database.windows.net,1433;Database=${SQL_DATABASE_NAME};User ID=sqladmin;Password=${sql_password};Encrypt=true;TrustServerCertificate=false;Connection Timeout=30;" \
        "ServiceFabricConnectionString=https://${CLUSTER_NAME}.${LOCATION}.cloudapp.azure.com:19080" \
        "APPINSIGHTS_INSTRUMENTATIONKEY=$APP_INSIGHTS_KEY"

    log_success "Function App created and configured successfully"
}

# Configure monitoring and alerts
configure_monitoring() {
    log_info "Configuring monitoring and alerts..."
    
    # Create custom metrics alert for order processing failures
    execute_az_command "Create order processing failure alert" \
        az monitor metrics alert create \
        --name "OrderProcessingFailures" \
        --resource-group "$RESOURCE_GROUP" \
        --scopes "/subscriptions/$(az account show --query id -o tsv)/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.Insights/components/${APP_INSIGHTS_NAME}" \
        --condition "count 'customEvents' > 5" \
        --window-size 5m \
        --evaluation-frequency 1m \
        --description "Alert when order processing failures exceed threshold"

    log_success "Monitoring and alerts configured successfully"
}

# Validate deployment
validate_deployment() {
    log_info "Validating deployment..."
    
    # Check resource group
    if ! az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        log_error "Resource group validation failed"
        return 1
    fi

    # Check Service Fabric cluster
    local cluster_state=$(az sf cluster show \
        --resource-group "$RESOURCE_GROUP" \
        --name "$CLUSTER_NAME" \
        --query clusterState -o tsv 2>/dev/null || echo "NotFound")
    
    if [[ "$cluster_state" != "Ready" ]]; then
        log_warning "Service Fabric cluster is not in Ready state: $cluster_state"
    fi

    # Check Function App
    local function_state=$(az functionapp show \
        --name "$FUNCTION_APP_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --query state -o tsv 2>/dev/null || echo "NotFound")
    
    if [[ "$function_state" != "Running" ]]; then
        log_warning "Function App is not in Running state: $function_state"
    fi

    # Check SQL Database
    local db_status=$(az sql db show \
        --resource-group "$RESOURCE_GROUP" \
        --server "$SQL_SERVER_NAME" \
        --name "$SQL_DATABASE_NAME" \
        --query status -o tsv 2>/dev/null || echo "NotFound")
    
    if [[ "$db_status" != "Online" ]]; then
        log_warning "SQL Database is not Online: $db_status"
    fi

    log_success "Deployment validation completed"
}

# Print deployment summary
print_deployment_summary() {
    log_info "Deployment Summary"
    log_info "=================="
    log_info "Resource Group: $RESOURCE_GROUP"
    log_info "Location: $LOCATION"
    log_info "Deployment Mode: $DEPLOYMENT_MODE"
    log_info ""
    log_info "Service Fabric Cluster: $CLUSTER_NAME"
    log_info "  - Management Endpoint: https://${CLUSTER_NAME}.${LOCATION}.cloudapp.azure.com:19080"
    log_info "  - VM Size: $VM_SIZE"
    log_info "  - Cluster Size: $CLUSTER_SIZE"
    log_info ""
    log_info "Function App: $FUNCTION_APP_NAME"
    log_info "  - URL: https://${FUNCTION_APP_NAME}.azurewebsites.net"
    log_info ""
    log_info "SQL Database: $SQL_DATABASE_NAME"
    log_info "  - Server: ${SQL_SERVER_NAME}.database.windows.net"
    log_info ""
    log_info "Storage Account: $STORAGE_ACCOUNT_NAME"
    log_info "Application Insights: $APP_INSIGHTS_NAME"
    log_info "Key Vault: $KEYVAULT_NAME"
    log_info ""
    log_info "Configuration saved to: $CONFIG_FILE"
    log_info "Certificates saved to: $SCRIPT_DIR/certificates/"
    log_info ""
    log_success "Deployment completed successfully!"
    log_info "Next steps:"
    log_info "1. Deploy your Service Fabric applications"
    log_info "2. Deploy your Durable Functions orchestrator"
    log_info "3. Test the end-to-end workflow"
    log_info "4. Configure production monitoring and alerts"
}

# Cleanup on error
cleanup_on_error() {
    log_error "Deployment failed. Cleaning up resources..."
    
    # This will be handled by the destroy.sh script
    log_info "Run './destroy.sh' to clean up all resources"
}

# Main deployment function
main() {
    log_info "Starting Azure Microservices Orchestration deployment"
    log_info "Deployment mode: $DEPLOYMENT_MODE"
    log_info "Dry run: $DRY_RUN"
    
    # Set trap for cleanup on error
    trap cleanup_on_error ERR

    # Execute deployment steps
    check_prerequisites
    generate_resource_names
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "Dry run completed. No resources were created."
        exit 0
    fi

    create_resource_group
    create_key_vault
    create_application_insights
    create_storage_account
    create_sql_database
    create_service_fabric_cluster
    create_function_app
    configure_monitoring
    validate_deployment
    print_deployment_summary
}

# Script entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Initialize logging
    echo "Deployment started at $(date)" > "$LOG_FILE"
    
    # Parse arguments and run main function
    parse_arguments "$@"
    main
fi