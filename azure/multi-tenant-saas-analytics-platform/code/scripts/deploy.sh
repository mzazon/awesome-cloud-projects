#!/bin/bash

# Azure Multi-Tenant SaaS Performance and Cost Analytics Deployment Script
# Implements Azure Application Insights, Data Explorer, and Cost Management
# for comprehensive multi-tenant monitoring and analytics

set -e  # Exit on any error
set -o pipefail  # Exit on pipe failures

# Configuration and Global Variables
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_FILE="${SCRIPT_DIR}/deploy.log"
readonly CONFIG_FILE="${SCRIPT_DIR}/.deployment_config"

# Default configuration values
DEFAULT_LOCATION="eastus"
DEFAULT_ENVIRONMENT="production"
DEFAULT_RETENTION_DAYS=90
DEFAULT_BUDGET_AMOUNT=200

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Logging functions
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}" | tee -a "${LOG_FILE}"
}

log_warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}" | tee -a "${LOG_FILE}"
}

log_error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}" | tee -a "${LOG_FILE}"
}

log_info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1${NC}" | tee -a "${LOG_FILE}"
}

# Error handling
cleanup_on_error() {
    log_error "Deployment failed. Cleaning up partial resources..."
    if [[ -f "${CONFIG_FILE}" ]]; then
        source "${CONFIG_FILE}"
        if [[ -n "${RESOURCE_GROUP}" ]]; then
            log_warn "Removing partially created resource group: ${RESOURCE_GROUP}"
            az group delete --name "${RESOURCE_GROUP}" --yes --no-wait 2>/dev/null || true
        fi
    fi
    exit 1
}

trap cleanup_on_error ERR

# Prerequisites validation
check_prerequisites() {
    log "Validating prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        log_error "Azure CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check Azure CLI version
    local az_version=$(az version --query '"azure-cli"' -o tsv)
    log_info "Azure CLI version: ${az_version}"
    
    # Check if logged into Azure
    if ! az account show &> /dev/null; then
        log_error "Not logged into Azure. Please run 'az login' first."
        exit 1
    fi
    
    # Get current subscription info
    local subscription_name=$(az account show --query name -o tsv)
    local subscription_id=$(az account show --query id -o tsv)
    log_info "Using subscription: ${subscription_name} (${subscription_id})"
    
    # Check required resource providers
    log "Checking required resource providers..."
    local providers=("Microsoft.OperationalInsights" "Microsoft.Insights" "Microsoft.Kusto" "Microsoft.Consumption")
    
    for provider in "${providers[@]}"; do
        local state=$(az provider show --namespace "${provider}" --query registrationState -o tsv 2>/dev/null || echo "NotRegistered")
        if [[ "${state}" != "Registered" ]]; then
            log_warn "Registering provider: ${provider}"
            az provider register --namespace "${provider}" --wait
        else
            log_info "Provider ${provider} is registered"
        fi
    done
    
    log "Prerequisites validation completed successfully"
}

# Configuration setup
setup_configuration() {
    log "Setting up deployment configuration..."
    
    # Generate unique suffix for resources
    local random_suffix=$(openssl rand -hex 3 2>/dev/null || echo $(date +%s | tail -c 6))
    
    # Set environment variables with user input or defaults
    read -p "Enter Azure region [${DEFAULT_LOCATION}]: " location
    LOCATION="${location:-${DEFAULT_LOCATION}}"
    
    read -p "Enter environment name [${DEFAULT_ENVIRONMENT}]: " environment
    ENVIRONMENT="${environment:-${DEFAULT_ENVIRONMENT}}"
    
    read -p "Enter retention period in days [${DEFAULT_RETENTION_DAYS}]: " retention
    RETENTION_DAYS="${retention:-${DEFAULT_RETENTION_DAYS}}"
    
    read -p "Enter monthly budget amount [${DEFAULT_BUDGET_AMOUNT}]: " budget
    BUDGET_AMOUNT="${budget:-${DEFAULT_BUDGET_AMOUNT}}"
    
    # Generate resource names
    RESOURCE_GROUP="rg-saas-analytics-${random_suffix}"
    APP_INSIGHTS_NAME="ai-saas-analytics-${random_suffix}"
    LOG_ANALYTICS_NAME="la-saas-analytics-${random_suffix}"
    DATA_EXPLORER_CLUSTER="adx-saas-${random_suffix}"
    DATA_EXPLORER_DATABASE="SaaSAnalytics"
    COST_ALERT_NAME="cost-alert-saas-${random_suffix}"
    ACTION_GROUP_NAME="cost-alert-group-${random_suffix}"
    BUDGET_NAME="saas-analytics-budget-${random_suffix}"
    
    # Get subscription ID
    SUBSCRIPTION_ID=$(az account show --query id --output tsv)
    
    # Save configuration
    cat > "${CONFIG_FILE}" << EOF
# Deployment Configuration
LOCATION="${LOCATION}"
ENVIRONMENT="${ENVIRONMENT}"
RETENTION_DAYS="${RETENTION_DAYS}"
BUDGET_AMOUNT="${BUDGET_AMOUNT}"
RESOURCE_GROUP="${RESOURCE_GROUP}"
APP_INSIGHTS_NAME="${APP_INSIGHTS_NAME}"
LOG_ANALYTICS_NAME="${LOG_ANALYTICS_NAME}"
DATA_EXPLORER_CLUSTER="${DATA_EXPLORER_CLUSTER}"
DATA_EXPLORER_DATABASE="${DATA_EXPLORER_DATABASE}"
COST_ALERT_NAME="${COST_ALERT_NAME}"
ACTION_GROUP_NAME="${ACTION_GROUP_NAME}"
BUDGET_NAME="${BUDGET_NAME}"
SUBSCRIPTION_ID="${SUBSCRIPTION_ID}"
DEPLOYMENT_DATE="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
EOF
    
    log "Configuration saved to ${CONFIG_FILE}"
    log_info "Resource Group: ${RESOURCE_GROUP}"
    log_info "Location: ${LOCATION}"
}

# Resource group creation
create_resource_group() {
    log "Creating resource group: ${RESOURCE_GROUP}"
    
    az group create \
        --name "${RESOURCE_GROUP}" \
        --location "${LOCATION}" \
        --tags purpose=saas-analytics environment="${ENVIRONMENT}" \
               solution=multi-tenant-monitoring deployment-date="${DEPLOYMENT_DATE}" \
        --output none
    
    log "✅ Resource group created successfully"
}

# Log Analytics workspace creation
create_log_analytics_workspace() {
    log "Creating Log Analytics workspace: ${LOG_ANALYTICS_NAME}"
    
    az monitor log-analytics workspace create \
        --resource-group "${RESOURCE_GROUP}" \
        --workspace-name "${LOG_ANALYTICS_NAME}" \
        --location "${LOCATION}" \
        --retention-time "${RETENTION_DAYS}" \
        --sku pergb2018 \
        --tags solution=multi-tenant-monitoring environment="${ENVIRONMENT}" \
        --output none
    
    # Get workspace ID for Application Insights integration
    WORKSPACE_ID=$(az monitor log-analytics workspace show \
        --resource-group "${RESOURCE_GROUP}" \
        --workspace-name "${LOG_ANALYTICS_NAME}" \
        --query customerId --output tsv)
    
    # Update configuration file with workspace ID
    echo "WORKSPACE_ID=\"${WORKSPACE_ID}\"" >> "${CONFIG_FILE}"
    
    log "✅ Log Analytics workspace created with ID: ${WORKSPACE_ID}"
}

# Application Insights creation
create_application_insights() {
    log "Creating Application Insights: ${APP_INSIGHTS_NAME}"
    
    az monitor app-insights component create \
        --resource-group "${RESOURCE_GROUP}" \
        --app "${APP_INSIGHTS_NAME}" \
        --location "${LOCATION}" \
        --kind web \
        --workspace "${WORKSPACE_ID}" \
        --retention-time "${RETENTION_DAYS}" \
        --tags solution=multi-tenant-monitoring tenant-enabled=true environment="${ENVIRONMENT}" \
        --output none
    
    # Get Application Insights details
    INSTRUMENTATION_KEY=$(az monitor app-insights component show \
        --resource-group "${RESOURCE_GROUP}" \
        --app "${APP_INSIGHTS_NAME}" \
        --query instrumentationKey --output tsv)
    
    CONNECTION_STRING=$(az monitor app-insights component show \
        --resource-group "${RESOURCE_GROUP}" \
        --app "${APP_INSIGHTS_NAME}" \
        --query connectionString --output tsv)
    
    # Update configuration file
    cat >> "${CONFIG_FILE}" << EOF
INSTRUMENTATION_KEY="${INSTRUMENTATION_KEY}"
CONNECTION_STRING="${CONNECTION_STRING}"
EOF
    
    log "✅ Application Insights created with instrumentation key: ${INSTRUMENTATION_KEY}"
}

# Azure Data Explorer cluster creation
create_data_explorer_cluster() {
    log "Creating Azure Data Explorer cluster: ${DATA_EXPLORER_CLUSTER}"
    log_warn "This operation may take 10-15 minutes to complete..."
    
    az kusto cluster create \
        --cluster-name "${DATA_EXPLORER_CLUSTER}" \
        --resource-group "${RESOURCE_GROUP}" \
        --location "${LOCATION}" \
        --sku name=Standard_D11_v2 tier=Standard \
        --capacity 2 \
        --tags solution=multi-tenant-monitoring analytics=enabled environment="${ENVIRONMENT}" \
        --output none
    
    # Wait for cluster provisioning
    log "Waiting for cluster provisioning to complete..."
    az kusto cluster wait \
        --cluster-name "${DATA_EXPLORER_CLUSTER}" \
        --resource-group "${RESOURCE_GROUP}" \
        --created \
        --timeout 1800  # 30 minutes timeout
    
    log "✅ Azure Data Explorer cluster created successfully"
}

# Data Explorer database and connection setup
setup_data_explorer_database() {
    log "Creating Azure Data Explorer database: ${DATA_EXPLORER_DATABASE}"
    
    # Create database
    az kusto database create \
        --cluster-name "${DATA_EXPLORER_CLUSTER}" \
        --database-name "${DATA_EXPLORER_DATABASE}" \
        --resource-group "${RESOURCE_GROUP}" \
        --read-write-database location="${LOCATION}" \
            hot-cache-period=P30D soft-delete-period=P365D \
        --output none
    
    # Create data connection from Log Analytics to Data Explorer
    log "Setting up data connection from Log Analytics to Data Explorer..."
    
    local workspace_resource_id="/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.OperationalInsights/workspaces/${LOG_ANALYTICS_NAME}"
    
    az kusto data-connection create \
        --cluster-name "${DATA_EXPLORER_CLUSTER}" \
        --database-name "${DATA_EXPLORER_DATABASE}" \
        --data-connection-name "AppInsightsConnection" \
        --resource-group "${RESOURCE_GROUP}" \
        --kind LogAnalytics \
        --log-analytics-workspace-resource-id "${workspace_resource_id}" \
        --output none
    
    log "✅ Data Explorer database and connection created successfully"
}

# Cost management setup
setup_cost_management() {
    log "Setting up cost management and budgets..."
    
    # Create action group for cost alerts
    read -p "Enter email address for cost alerts: " alert_email
    if [[ -n "${alert_email}" ]]; then
        az monitor action-group create \
            --name "${ACTION_GROUP_NAME}" \
            --resource-group "${RESOURCE_GROUP}" \
            --short-name "CostAlert" \
            --email-receiver name=admin email="${alert_email}" \
            --tags solution=multi-tenant-monitoring environment="${ENVIRONMENT}" \
            --output none
        
        log "✅ Cost alert action group created with email: ${alert_email}"
    else
        log_warn "No email provided for cost alerts. Skipping action group creation."
    fi
    
    # Create budget
    local start_date=$(date -u +%Y-%m-01T00:00:00Z)
    
    az consumption budget create \
        --resource-group "${RESOURCE_GROUP}" \
        --budget-name "${BUDGET_NAME}" \
        --amount "${BUDGET_AMOUNT}" \
        --time-grain Monthly \
        --time-period start-date="${start_date}" \
        --category Cost \
        --filter "ResourceGroupName eq '${RESOURCE_GROUP}'" \
        --output none
    
    log "✅ Cost management budget configured: \$${BUDGET_AMOUNT}/month"
}

# Custom tables and functions setup
setup_custom_analytics() {
    log "Setting up custom tables and functions in Data Explorer..."
    
    # Create custom table for tenant metrics
    local table_script=".create table TenantMetrics (
        Timestamp: datetime,
        TenantId: string,
        MetricName: string,
        MetricValue: real,
        ResourceId: string,
        Location: string,
        CostCenter: string
    )"
    
    az kusto script create \
        --cluster-name "${DATA_EXPLORER_CLUSTER}" \
        --database-name "${DATA_EXPLORER_DATABASE}" \
        --resource-group "${RESOURCE_GROUP}" \
        --script-name "CreateTenantMetricsTable" \
        --script-content "${table_script}" \
        --output none
    
    # Create function for tenant cost analysis
    local function_script=".create function TenantCostAnalysis() {
        TenantMetrics
        | where Timestamp > ago(30d)
        | summarize TotalCost = sum(MetricValue) by TenantId, bin(Timestamp, 1d)
        | order by Timestamp desc
    }"
    
    az kusto script create \
        --cluster-name "${DATA_EXPLORER_CLUSTER}" \
        --database-name "${DATA_EXPLORER_DATABASE}" \
        --resource-group "${RESOURCE_GROUP}" \
        --script-name "CreateCostAnalysisFunction" \
        --script-content "${function_script}" \
        --output none
    
    log "✅ Custom tables and functions created in Data Explorer"
}

# Create sample analytics queries
create_sample_queries() {
    log "Creating sample analytics queries..."
    
    # Performance analysis query
    cat > "${SCRIPT_DIR}/performance-analysis.kql" << 'EOF'
// Performance Analysis Query for Multi-Tenant SaaS
requests
| where timestamp > ago(24h)
| extend TenantId = tostring(customDimensions.TenantId)
| summarize 
    RequestCount = count(),
    AvgDuration = avg(duration),
    P95Duration = percentile(duration, 95),
    FailureRate = countif(success == false) * 100.0 / count()
by TenantId, bin(timestamp, 1h)
| order by timestamp desc
EOF
    
    # Cost correlation query
    cat > "${SCRIPT_DIR}/cost-correlation.kql" << 'EOF'
// Cost Correlation Query for Multi-Tenant SaaS
union 
(requests | extend MetricType = "Performance"),
(dependencies | extend MetricType = "Dependencies")
| where timestamp > ago(7d)
| extend TenantId = tostring(customDimensions.TenantId)
| summarize 
    TotalOperations = count(),
    AvgCost = avg(itemCount * 0.001) // Estimated cost per operation
by TenantId, MetricType, bin(timestamp, 1d)
| order by TotalOperations desc
EOF
    
    log "✅ Sample analytics queries created"
}

# Deployment validation
validate_deployment() {
    log "Validating deployment..."
    
    # Check resource group
    if az group show --name "${RESOURCE_GROUP}" &>/dev/null; then
        log_info "✅ Resource group validation passed"
    else
        log_error "❌ Resource group validation failed"
        return 1
    fi
    
    # Check Application Insights
    if az monitor app-insights component show --resource-group "${RESOURCE_GROUP}" --app "${APP_INSIGHTS_NAME}" &>/dev/null; then
        log_info "✅ Application Insights validation passed"
    else
        log_error "❌ Application Insights validation failed"
        return 1
    fi
    
    # Check Data Explorer cluster
    if az kusto cluster show --cluster-name "${DATA_EXPLORER_CLUSTER}" --resource-group "${RESOURCE_GROUP}" &>/dev/null; then
        log_info "✅ Data Explorer cluster validation passed"
    else
        log_error "❌ Data Explorer cluster validation failed"
        return 1
    fi
    
    log "✅ Deployment validation completed successfully"
}

# Display deployment summary
display_summary() {
    log "=== DEPLOYMENT SUMMARY ==="
    log_info "Resource Group: ${RESOURCE_GROUP}"
    log_info "Location: ${LOCATION}"
    log_info "Application Insights: ${APP_INSIGHTS_NAME}"
    log_info "Instrumentation Key: ${INSTRUMENTATION_KEY}"
    log_info "Log Analytics Workspace: ${LOG_ANALYTICS_NAME}"
    log_info "Data Explorer Cluster: ${DATA_EXPLORER_CLUSTER}"
    log_info "Data Explorer Database: ${DATA_EXPLORER_DATABASE}"
    log_info "Budget: \$${BUDGET_AMOUNT}/month"
    log ""
    log_info "Configuration saved to: ${CONFIG_FILE}"
    log_info "Deployment log saved to: ${LOG_FILE}"
    log_info "Sample queries created in: ${SCRIPT_DIR}/"
    log ""
    log_info "Next steps:"
    log_info "1. Configure your SaaS application to use the Application Insights connection string"
    log_info "2. Add tenant identification to your telemetry data"
    log_info "3. Use the sample queries to start analyzing performance and cost data"
    log_info "4. Set up dashboards in Azure Monitor Workbooks or Power BI"
    log ""
    log_warn "Remember to clean up resources when no longer needed to avoid ongoing charges"
}

# Main deployment function
main() {
    log "Starting Azure Multi-Tenant SaaS Analytics deployment..."
    log "Deployment started at: $(date)"
    
    # Run deployment steps
    check_prerequisites
    setup_configuration
    create_resource_group
    create_log_analytics_workspace
    create_application_insights
    create_data_explorer_cluster
    setup_data_explorer_database
    setup_cost_management
    setup_custom_analytics
    create_sample_queries
    validate_deployment
    display_summary
    
    log "✅ Deployment completed successfully at: $(date)"
    log "Total deployment time: $SECONDS seconds"
}

# Check if script is being run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi