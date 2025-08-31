#!/bin/bash

# Azure Resource Monitoring Dashboard Workbooks - Deployment Script
# This script deploys the infrastructure for Azure Monitor Workbooks monitoring solution

set -euo pipefail  # Enhanced error handling

# Color codes for output formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $*"
}

success() {
    echo -e "${GREEN}✅ $*${NC}"
}

warning() {
    echo -e "${YELLOW}⚠️  $*${NC}"
}

error() {
    echo -e "${RED}❌ $*${NC}"
}

# Script metadata
SCRIPT_NAME="Azure Resource Monitoring Dashboard Workbooks Deployment"
SCRIPT_VERSION="1.0.0"
RECIPE_VERSION="1.1"

log "Starting $SCRIPT_NAME (v$SCRIPT_VERSION)"
log "Recipe Version: $RECIPE_VERSION"

# Configuration variables with defaults
DEFAULT_LOCATION="eastus"
DEFAULT_PREFIX="monitoring"

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        error "Azure CLI is not installed. Please install it first."
        error "Visit: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
        exit 1
    fi
    
    # Check Azure CLI version
    local az_version
    az_version=$(az version --query '"azure-cli"' -o tsv 2>/dev/null || echo "unknown")
    log "Azure CLI version: $az_version"
    
    # Check if user is logged in to Azure
    if ! az account show &> /dev/null; then
        error "Not logged in to Azure. Please run 'az login' first."
        exit 1
    fi
    
    # Check if openssl is available for random string generation
    if ! command -v openssl &> /dev/null; then
        error "OpenSSL is required for generating unique resource names."
        exit 1
    fi
    
    success "Prerequisites check completed"
}

# Function to set environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    # Generate unique suffix for resource names
    export RANDOM_SUFFIX=$(openssl rand -hex 3)
    log "Generated unique suffix: $RANDOM_SUFFIX"
    
    # Set default values if not provided
    export LOCATION="${LOCATION:-$DEFAULT_LOCATION}"
    export RESOURCE_GROUP="${RESOURCE_GROUP:-rg-${DEFAULT_PREFIX}-${RANDOM_SUFFIX}}"
    export SUBSCRIPTION_ID=$(az account show --query id --output tsv)
    
    # Azure Monitor specific resources
    export LOG_WORKSPACE="log-workspace-${RANDOM_SUFFIX}"
    export STORAGE_ACCOUNT="stor${RANDOM_SUFFIX}"
    export APP_SERVICE_PLAN="asp-monitoring-${RANDOM_SUFFIX}"
    export WEB_APP="webapp-monitoring-${RANDOM_SUFFIX}"
    export WORKBOOK_NAME="Resource Monitoring Dashboard - ${RANDOM_SUFFIX}"
    export WORKBOOK_DESCRIPTION="Custom dashboard for monitoring resource health, performance, and costs"
    
    log "Environment configuration:"
    log "  Resource Group: $RESOURCE_GROUP"
    log "  Location: $LOCATION"
    log "  Subscription ID: $SUBSCRIPTION_ID"
    log "  Log Analytics Workspace: $LOG_WORKSPACE"
    log "  Storage Account: $STORAGE_ACCOUNT"
    log "  App Service Plan: $APP_SERVICE_PLAN"
    log "  Web App: $WEB_APP"
    
    success "Environment setup completed"
}

# Function to validate Azure subscription and permissions
validate_azure_access() {
    log "Validating Azure subscription and permissions..."
    
    local subscription_name
    subscription_name=$(az account show --query name --output tsv)
    log "Current subscription: $subscription_name"
    
    # Check if the user has Contributor or Owner permissions
    local user_permissions
    user_permissions=$(az role assignment list --assignee "$(az account show --query user.name --output tsv)" \
                      --query "[?roleDefinitionName=='Owner' || roleDefinitionName=='Contributor'].roleDefinitionName" \
                      --output tsv 2>/dev/null || echo "")
    
    if [[ -z "$user_permissions" ]]; then
        warning "Unable to verify permissions. Proceeding with deployment..."
    else
        log "User permissions: $user_permissions"
    fi
    
    success "Azure access validation completed"
}

# Function to create resource group
create_resource_group() {
    log "Creating resource group: $RESOURCE_GROUP"
    
    if az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        warning "Resource group $RESOURCE_GROUP already exists"
        return 0
    fi
    
    az group create \
        --name "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --tags purpose=monitoring environment=demo recipe=azure-workbooks-monitoring \
        --output none
    
    success "Resource group created: $RESOURCE_GROUP"
}

# Function to create Log Analytics workspace
create_log_analytics_workspace() {
    log "Creating Log Analytics workspace: $LOG_WORKSPACE"
    
    if az monitor log-analytics workspace show \
       --resource-group "$RESOURCE_GROUP" \
       --workspace-name "$LOG_WORKSPACE" &> /dev/null; then
        warning "Log Analytics workspace $LOG_WORKSPACE already exists"
        return 0
    fi
    
    az monitor log-analytics workspace create \
        --resource-group "$RESOURCE_GROUP" \
        --workspace-name "$LOG_WORKSPACE" \
        --location "$LOCATION" \
        --tags purpose=monitoring recipe=azure-workbooks-monitoring \
        --output none
    
    # Wait for workspace to be fully provisioned
    log "Waiting for Log Analytics workspace to be ready..."
    local max_attempts=30
    local attempt=1
    
    while [[ $attempt -le $max_attempts ]]; do
        local state
        state=$(az monitor log-analytics workspace show \
                --resource-group "$RESOURCE_GROUP" \
                --workspace-name "$LOG_WORKSPACE" \
                --query "provisioningState" --output tsv 2>/dev/null || echo "NotFound")
        
        if [[ "$state" == "Succeeded" ]]; then
            break
        fi
        
        log "Workspace provisioning state: $state (attempt $attempt/$max_attempts)"
        sleep 10
        ((attempt++))
    done
    
    if [[ $attempt -gt $max_attempts ]]; then
        error "Log Analytics workspace creation timed out"
        exit 1
    fi
    
    success "Log Analytics workspace created: $LOG_WORKSPACE"
}

# Function to create sample resources for monitoring
create_sample_resources() {
    log "Creating sample resources for monitoring demonstration..."
    
    # Create storage account
    log "Creating storage account: $STORAGE_ACCOUNT"
    
    if az storage account show \
       --name "$STORAGE_ACCOUNT" \
       --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        warning "Storage account $STORAGE_ACCOUNT already exists"
    else
        az storage account create \
            --name "$STORAGE_ACCOUNT" \
            --resource-group "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --sku Standard_LRS \
            --tags purpose=monitoring environment=demo recipe=azure-workbooks-monitoring \
            --output none
        
        success "Storage account created: $STORAGE_ACCOUNT"
    fi
    
    # Create App Service plan
    log "Creating App Service plan: $APP_SERVICE_PLAN"
    
    if az appservice plan show \
       --name "$APP_SERVICE_PLAN" \
       --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        warning "App Service plan $APP_SERVICE_PLAN already exists"
    else
        az appservice plan create \
            --name "$APP_SERVICE_PLAN" \
            --resource-group "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --sku F1 \
            --tags purpose=monitoring environment=demo recipe=azure-workbooks-monitoring \
            --output none
        
        success "App Service plan created: $APP_SERVICE_PLAN"
    fi
    
    # Create web app
    log "Creating web app: $WEB_APP"
    
    if az webapp show \
       --name "$WEB_APP" \
       --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        warning "Web app $WEB_APP already exists"
    else
        az webapp create \
            --name "$WEB_APP" \
            --resource-group "$RESOURCE_GROUP" \
            --plan "$APP_SERVICE_PLAN" \
            --tags purpose=monitoring environment=demo recipe=azure-workbooks-monitoring \
            --output none
        
        success "Web app created: $WEB_APP"
    fi
    
    success "Sample resources created for monitoring"
}

# Function to create KQL query files
create_kql_query_files() {
    log "Creating KQL query files for workbook configuration..."
    
    # Create resource health query
    cat << 'EOF' > resource_health_query.kql
AzureActivity
| where TimeGenerated >= ago(1h)
| where ActivityStatusValue in ("Success", "Failed", "Warning")
| summarize 
    SuccessfulOperations = countif(ActivityStatusValue == "Success"),
    FailedOperations = countif(ActivityStatusValue == "Failed"),
    WarningOperations = countif(ActivityStatusValue == "Warning"),
    TotalOperations = count()
| extend HealthPercentage = round((SuccessfulOperations * 100.0) / TotalOperations, 1)
| project SuccessfulOperations, FailedOperations, WarningOperations, TotalOperations, HealthPercentage
EOF
    
    # Create performance metrics query
    cat << 'EOF' > performance_metrics_query.kql
Perf
| where TimeGenerated >= ago(4h)
| where CounterName in ("% Processor Time", "Available MBytes", "Disk Read Bytes/sec")
| summarize 
    AvgCPU = avg(CounterValue), 
    AvgMemory = avg(CounterValue),
    MaxDiskIO = max(CounterValue)
by Computer, CounterName, bin(TimeGenerated, 15m)
| render timechart
EOF
    
    # Create alternative metrics query reference
    cat << 'EOF' > azure_metrics_query.txt
Data Source: Azure Monitor Metrics
Metric Namespace: Microsoft.Compute/virtualMachines
Metrics: Percentage CPU, Available Memory Bytes, Disk Read Bytes/sec
Aggregation: Average
Time Range: Last 4 hours
Granularity: 15 minutes
EOF
    
    # Create cost monitoring query (with placeholder replacement)
    cat << EOF > cost_monitoring_query.kql
Resources
| where subscriptionId =~ "${SUBSCRIPTION_ID}"
| where resourceGroup =~ "${RESOURCE_GROUP}"
| extend resourceCost = todynamic('{"cost": 0.0}')
| project name, type, location, resourceGroup, resourceCost
| extend EstimatedMonthlyCost = case(
    type contains "Microsoft.Storage", 5.0,
    type contains "Microsoft.Web/sites", 10.0,
    type contains "Microsoft.Compute", 50.0,
    type contains "Microsoft.OperationalInsights", 15.0,
    1.0)
| order by EstimatedMonthlyCost desc
EOF
    
    success "KQL query files created"
}

# Function to display deployment summary and next steps
display_deployment_summary() {
    log "Deployment completed successfully!"
    
    echo ""
    echo "=== DEPLOYMENT SUMMARY ==="
    echo "Resource Group: $RESOURCE_GROUP"
    echo "Location: $LOCATION"
    echo "Subscription ID: $SUBSCRIPTION_ID"
    echo ""
    echo "Created Resources:"
    echo "- Log Analytics Workspace: $LOG_WORKSPACE"
    echo "- Storage Account: $STORAGE_ACCOUNT"
    echo "- App Service Plan: $APP_SERVICE_PLAN"
    echo "- Web App: $WEB_APP"
    echo ""
    echo "Generated Files:"
    echo "- resource_health_query.kql"
    echo "- performance_metrics_query.kql"
    echo "- azure_metrics_query.txt"
    echo "- cost_monitoring_query.kql"
    echo ""
    echo "=== NEXT STEPS ==="
    echo "1. Navigate to Azure Monitor Workbooks:"
    echo "   https://portal.azure.com/#view/Microsoft_Azure_Monitoring/AzureMonitoringBrowseBlade/~/workbooks"
    echo ""
    echo "2. Create a new custom workbook:"
    echo "   - Select 'Empty' template"
    echo "   - Configure workbook name: $WORKBOOK_NAME"
    echo "   - Set resource group: $RESOURCE_GROUP"
    echo ""
    echo "3. Add workbook sections using the generated KQL queries:"
    echo "   - Resource Health Overview (resource_health_query.kql)"
    echo "   - Performance Metrics (performance_metrics_query.kql)"
    echo "   - Cost Monitoring (cost_monitoring_query.kql)"
    echo ""
    echo "4. Configure interactive parameters:"
    echo "   - Time Range Parameter"
    echo "   - Resource Group Parameter"
    echo "   - Subscription Parameter"
    echo ""
    echo "5. Save and share the workbook with appropriate permissions"
    echo ""
    echo "=== COST ESTIMATION ==="
    echo "Estimated monthly costs (USD):"
    echo "- Log Analytics Workspace: \$0-15 (depending on data ingestion)"
    echo "- Storage Account: \$1-5"
    echo "- App Service (F1): \$0 (free tier)"
    echo "- Azure Monitor Workbooks: \$0 (free)"
    echo "Total estimated cost: \$1-20 per month"
    echo ""
    echo "=== CLEANUP ==="
    echo "To remove all resources, run: ./destroy.sh"
    echo ""
    
    # Get resource group ID for workbook association
    export RG_RESOURCE_ID=$(az group show --name "$RESOURCE_GROUP" --query id --output tsv)
    echo "Resource Group ID (for workbook configuration): $RG_RESOURCE_ID"
    
    success "Deployment completed successfully!"
}

# Function to handle script interruption
cleanup_on_exit() {
    local exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        error "Script interrupted or failed with exit code $exit_code"
        warning "Some resources may have been partially created"
        warning "Run './destroy.sh' to clean up any created resources"
    fi
    exit $exit_code
}

# Set trap for cleanup on script exit
trap cleanup_on_exit EXIT INT TERM

# Main deployment function
main() {
    log "Starting Azure Resource Monitoring Dashboard Workbooks deployment..."
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --resource-group)
                RESOURCE_GROUP="$2"
                shift 2
                ;;
            --location)
                LOCATION="$2"
                shift 2
                ;;
            --help|-h)
                echo "Usage: $0 [OPTIONS]"
                echo ""
                echo "Options:"
                echo "  --resource-group NAME    Specify resource group name"
                echo "  --location LOCATION      Specify Azure region (default: $DEFAULT_LOCATION)"
                echo "  --help, -h               Show this help message"
                echo ""
                echo "Example:"
                echo "  $0 --resource-group my-monitoring-rg --location westus2"
                exit 0
                ;;
            *)
                error "Unknown option: $1"
                echo "Use --help for usage information"
                exit 1
                ;;
        esac
    done
    
    # Execute deployment steps
    check_prerequisites
    setup_environment
    validate_azure_access
    create_resource_group
    create_log_analytics_workspace
    create_sample_resources
    create_kql_query_files
    display_deployment_summary
}

# Execute main function with all arguments
main "$@"