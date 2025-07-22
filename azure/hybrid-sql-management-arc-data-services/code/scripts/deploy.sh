#!/bin/bash

# Azure Arc-enabled Data Services Deployment Script
# This script deploys Azure Arc Data Controller and SQL Managed Instance
# with Azure Monitor integration for hybrid database management

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

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command_exists az; then
        error "Azure CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if kubectl is installed
    if ! command_exists kubectl; then
        error "kubectl is not installed. Please install it first."
        exit 1
    fi
    
    # Check if openssl is installed (for random suffix generation)
    if ! command_exists openssl; then
        error "openssl is not installed. Please install it first."
        exit 1
    fi
    
    # Check Azure CLI version
    local cli_version=$(az version --query '."azure-cli"' -o tsv 2>/dev/null || echo "unknown")
    if [[ "$cli_version" != "unknown" ]]; then
        info "Azure CLI version: $cli_version"
    else
        warn "Could not determine Azure CLI version"
    fi
    
    # Check if logged into Azure
    if ! az account show >/dev/null 2>&1; then
        error "Not logged into Azure. Please run 'az login' first."
        exit 1
    fi
    
    # Check if kubectl can connect to cluster
    if ! kubectl cluster-info >/dev/null 2>&1; then
        error "Cannot connect to Kubernetes cluster. Please ensure kubectl is configured."
        exit 1
    fi
    
    log "Prerequisites check completed successfully"
}

# Function to set environment variables
set_environment_variables() {
    log "Setting up environment variables..."
    
    # Set default values if not provided
    export RESOURCE_GROUP="${RESOURCE_GROUP:-rg-arc-data-services}"
    export LOCATION="${LOCATION:-eastus}"
    export ARC_DATA_CONTROLLER_NAME="${ARC_DATA_CONTROLLER_NAME:-arc-dc-controller}"
    export SQL_MI_NAME="${SQL_MI_NAME:-sql-mi-arc}"
    export LOG_ANALYTICS_WORKSPACE="${LOG_ANALYTICS_WORKSPACE:-law-arc-monitoring}"
    export SQL_ADMIN_USERNAME="${SQL_ADMIN_USERNAME:-arcadmin}"
    export SQL_ADMIN_PASSWORD="${SQL_ADMIN_PASSWORD:-MySecurePassword123!}"
    export ALERT_EMAIL="${ALERT_EMAIL:-admin@company.com}"
    
    # Get subscription ID
    export SUBSCRIPTION_ID=$(az account show --query id --output tsv)
    if [[ -z "$SUBSCRIPTION_ID" ]]; then
        error "Could not retrieve subscription ID"
        exit 1
    fi
    
    # Generate unique suffix for resource names
    local random_suffix=$(openssl rand -hex 3)
    export RESOURCE_GROUP="${RESOURCE_GROUP}-${random_suffix}"
    export LOG_ANALYTICS_WORKSPACE="${LOG_ANALYTICS_WORKSPACE}-${random_suffix}"
    
    info "Resource Group: $RESOURCE_GROUP"
    info "Location: $LOCATION"
    info "Subscription ID: $SUBSCRIPTION_ID"
    info "Arc Data Controller: $ARC_DATA_CONTROLLER_NAME"
    info "SQL MI Name: $SQL_MI_NAME"
    info "Log Analytics Workspace: $LOG_ANALYTICS_WORKSPACE"
    
    log "Environment variables configured successfully"
}

# Function to install required Azure CLI extensions
install_extensions() {
    log "Installing Azure CLI extensions..."
    
    # Install arcdata extension
    if ! az extension list --query "[?name=='arcdata']" -o tsv | grep -q arcdata; then
        az extension add --name arcdata --yes
        log "Azure Arc data services extension installed"
    else
        info "Azure Arc data services extension already installed"
    fi
    
    # Update extensions to latest version
    az extension update --name arcdata 2>/dev/null || true
    
    log "Extensions installation completed"
}

# Function to create Azure resource group
create_resource_group() {
    log "Creating resource group..."
    
    if az group show --name "$RESOURCE_GROUP" >/dev/null 2>&1; then
        warn "Resource group $RESOURCE_GROUP already exists"
    else
        az group create \
            --name "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --tags purpose=arc-data-services environment=demo
        log "Resource group $RESOURCE_GROUP created successfully"
    fi
}

# Function to create Log Analytics workspace
create_log_analytics_workspace() {
    log "Creating Log Analytics workspace..."
    
    if az monitor log-analytics workspace show --resource-group "$RESOURCE_GROUP" --workspace-name "$LOG_ANALYTICS_WORKSPACE" >/dev/null 2>&1; then
        warn "Log Analytics workspace $LOG_ANALYTICS_WORKSPACE already exists"
    else
        az monitor log-analytics workspace create \
            --resource-group "$RESOURCE_GROUP" \
            --workspace-name "$LOG_ANALYTICS_WORKSPACE" \
            --location "$LOCATION" \
            --sku PerGB2018
        log "Log Analytics workspace $LOG_ANALYTICS_WORKSPACE created successfully"
    fi
    
    # Get workspace ID and key
    export WORKSPACE_ID=$(az monitor log-analytics workspace show \
        --resource-group "$RESOURCE_GROUP" \
        --workspace-name "$LOG_ANALYTICS_WORKSPACE" \
        --query customerId --output tsv)
    
    export WORKSPACE_KEY=$(az monitor log-analytics workspace get-shared-keys \
        --resource-group "$RESOURCE_GROUP" \
        --workspace-name "$LOG_ANALYTICS_WORKSPACE" \
        --query primarySharedKey --output tsv)
    
    if [[ -z "$WORKSPACE_ID" || -z "$WORKSPACE_KEY" ]]; then
        error "Could not retrieve workspace credentials"
        exit 1
    fi
    
    info "Workspace ID: $WORKSPACE_ID"
    log "Log Analytics workspace configured successfully"
}

# Function to create Azure Arc Data Controller
create_arc_data_controller() {
    log "Creating Azure Arc Data Controller..."
    
    # Check if data controller already exists
    if az arcdata dc show --resource-group "$RESOURCE_GROUP" --name "$ARC_DATA_CONTROLLER_NAME" >/dev/null 2>&1; then
        warn "Azure Arc Data Controller $ARC_DATA_CONTROLLER_NAME already exists"
    else
        # Create namespace if it doesn't exist
        kubectl create namespace arc --dry-run=client -o yaml | kubectl apply -f -
        
        # Create Arc Data Controller
        az arcdata dc create \
            --resource-group "$RESOURCE_GROUP" \
            --name "$ARC_DATA_CONTROLLER_NAME" \
            --namespace arc \
            --subscription "$SUBSCRIPTION_ID" \
            --location "$LOCATION" \
            --connectivity-mode direct \
            --use-k8s
        
        log "Azure Arc Data Controller created successfully"
    fi
    
    # Wait for data controller to be ready
    log "Waiting for Azure Arc Data Controller to be ready..."
    local timeout=300
    local count=0
    
    while [[ $count -lt $timeout ]]; do
        if kubectl wait --for=condition=Ready pod \
            --selector=app.kubernetes.io/name=controller \
            --namespace arc \
            --timeout=10s >/dev/null 2>&1; then
            log "Azure Arc Data Controller is ready"
            break
        fi
        
        count=$((count + 10))
        info "Waiting for controller to be ready... ($count/$timeout seconds)"
        sleep 10
    done
    
    if [[ $count -ge $timeout ]]; then
        error "Timeout waiting for Azure Arc Data Controller to be ready"
        exit 1
    fi
}

# Function to create SQL Managed Instance
create_sql_managed_instance() {
    log "Creating SQL Managed Instance..."
    
    # Check if SQL MI already exists
    if az sql mi-arc show --resource-group "$RESOURCE_GROUP" --name "$SQL_MI_NAME" >/dev/null 2>&1; then
        warn "SQL Managed Instance $SQL_MI_NAME already exists"
    else
        # Create SQL login secret
        kubectl create secret generic sql-login-secret \
            --from-literal=username="$SQL_ADMIN_USERNAME" \
            --from-literal=password="$SQL_ADMIN_PASSWORD" \
            --namespace arc \
            --dry-run=client -o yaml | kubectl apply -f -
        
        # Create SQL Managed Instance
        az sql mi-arc create \
            --resource-group "$RESOURCE_GROUP" \
            --name "$SQL_MI_NAME" \
            --data-controller-name "$ARC_DATA_CONTROLLER_NAME" \
            --cores-request 2 \
            --cores-limit 4 \
            --memory-request 2Gi \
            --memory-limit 4Gi \
            --storage-class-data default \
            --storage-class-logs default \
            --volume-size-data 5Gi \
            --volume-size-logs 5Gi \
            --tier GeneralPurpose \
            --dev
        
        log "SQL Managed Instance created successfully"
    fi
    
    # Wait for SQL MI to be ready
    log "Waiting for SQL Managed Instance to be ready..."
    local timeout=600
    local count=0
    
    while [[ $count -lt $timeout ]]; do
        if kubectl wait --for=condition=Ready pod \
            --selector=app="$SQL_MI_NAME" \
            --namespace arc \
            --timeout=10s >/dev/null 2>&1; then
            log "SQL Managed Instance is ready"
            break
        fi
        
        count=$((count + 10))
        info "Waiting for SQL MI to be ready... ($count/$timeout seconds)"
        sleep 10
    done
    
    if [[ $count -ge $timeout ]]; then
        error "Timeout waiting for SQL Managed Instance to be ready"
        exit 1
    fi
}

# Function to configure Azure Monitor integration
configure_azure_monitor() {
    log "Configuring Azure Monitor integration..."
    
    # Create custom config directory
    mkdir -p ./custom-config
    
    # Initialize configuration
    az arcdata dc config init \
        --source azure-arc-kubeadm \
        --path ./custom-config
    
    # Update config with Log Analytics workspace details
    az arcdata dc config add \
        --path ./custom-config \
        --json-values "spec.monitoring.logAnalyticsWorkspaceConfig.workspaceId=$WORKSPACE_ID"
    
    az arcdata dc config add \
        --path ./custom-config \
        --json-values "spec.monitoring.logAnalyticsWorkspaceConfig.primaryKey=$WORKSPACE_KEY"
    
    # Apply monitoring configuration
    az arcdata dc update \
        --resource-group "$RESOURCE_GROUP" \
        --name "$ARC_DATA_CONTROLLER_NAME" \
        --config-file ./custom-config/control.json
    
    log "Azure Monitor integration configured successfully"
}

# Function to set up monitoring and alerts
setup_monitoring_and_alerts() {
    log "Setting up monitoring and alerts..."
    
    # Create action group for alerts
    if az monitor action-group show --resource-group "$RESOURCE_GROUP" --name "arc-sql-alerts" >/dev/null 2>&1; then
        warn "Action group 'arc-sql-alerts' already exists"
    else
        az monitor action-group create \
            --resource-group "$RESOURCE_GROUP" \
            --name "arc-sql-alerts" \
            --short-name "arcsql" \
            --email-receiver name="admin" email-address="$ALERT_EMAIL"
        log "Action group created successfully"
    fi
    
    # Create CPU utilization alert
    if az monitor metrics alert show --resource-group "$RESOURCE_GROUP" --name "arc-sql-high-cpu" >/dev/null 2>&1; then
        warn "CPU alert 'arc-sql-high-cpu' already exists"
    else
        az monitor metrics alert create \
            --resource-group "$RESOURCE_GROUP" \
            --name "arc-sql-high-cpu" \
            --description "High CPU usage on Arc SQL MI" \
            --severity 2 \
            --window-size 5m \
            --evaluation-frequency 1m \
            --action "arc-sql-alerts" \
            --condition "avg Percentage CPU > 80" \
            --scopes "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.AzureArcData/sqlManagedInstances/$SQL_MI_NAME" \
            2>/dev/null || warn "Could not create CPU alert (resource may not be ready for monitoring)"
    fi
    
    # Create storage alert
    if az monitor metrics alert show --resource-group "$RESOURCE_GROUP" --name "arc-sql-low-storage" >/dev/null 2>&1; then
        warn "Storage alert 'arc-sql-low-storage' already exists"
    else
        az monitor metrics alert create \
            --resource-group "$RESOURCE_GROUP" \
            --name "arc-sql-low-storage" \
            --description "Low storage space on Arc SQL MI" \
            --severity 1 \
            --window-size 5m \
            --evaluation-frequency 1m \
            --action "arc-sql-alerts" \
            --condition "avg Storage percent > 85" \
            --scopes "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.AzureArcData/sqlManagedInstances/$SQL_MI_NAME" \
            2>/dev/null || warn "Could not create storage alert (resource may not be ready for monitoring)"
    fi
    
    log "Monitoring and alerts configured successfully"
}

# Function to configure security and governance
configure_security_governance() {
    log "Configuring security and governance..."
    
    # Enable Azure Policy for Arc-enabled resources
    local policy_assignment_name="arc-sql-security-policy"
    if az policy assignment show --name "$policy_assignment_name" --scope "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP" >/dev/null 2>&1; then
        warn "Policy assignment '$policy_assignment_name' already exists"
    else
        az policy assignment create \
            --name "$policy_assignment_name" \
            --display-name "Arc SQL Security Policy" \
            --policy "/providers/Microsoft.Authorization/policySetDefinitions/89c8a434-18f2-449b-9327-9579c0b9c2f2" \
            --scope "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP" \
            2>/dev/null || warn "Could not create policy assignment (policy may not be available)"
    fi
    
    # Apply security configuration to SQL MI
    az sql mi-arc update \
        --resource-group "$RESOURCE_GROUP" \
        --name "$SQL_MI_NAME" \
        --admin-login-secret sql-login-secret \
        2>/dev/null || warn "Could not update SQL MI security configuration"
    
    log "Security and governance configured successfully"
}

# Function to create monitoring dashboard
create_monitoring_dashboard() {
    log "Creating monitoring dashboard..."
    
    # Create custom monitoring workbook
    cat > arc-sql-workbook.json << 'EOF'
{
  "version": "Notebook/1.0",
  "items": [
    {
      "type": 1,
      "content": {
        "json": "# Azure Arc SQL Managed Instance Monitoring Dashboard\n\nThis dashboard provides real-time insights into your Arc-enabled SQL Managed Instance performance and health."
      }
    },
    {
      "type": 3,
      "content": {
        "version": "KqlItem/1.0",
        "query": "Perf | where CounterName == \"Processor(_Total)\\\\% Processor Time\" | summarize avg(CounterValue) by bin(TimeGenerated, 5m) | order by TimeGenerated desc",
        "size": 0,
        "title": "CPU Utilization (%)",
        "queryType": 0,
        "visualization": "timechart"
      }
    },
    {
      "type": 3,
      "content": {
        "version": "KqlItem/1.0",
        "query": "Perf | where CounterName == \"Memory\\\\Available MBytes\" | summarize avg(CounterValue) by bin(TimeGenerated, 5m) | order by TimeGenerated desc",
        "size": 0,
        "title": "Available Memory (MB)",
        "queryType": 0,
        "visualization": "timechart"
      }
    },
    {
      "type": 3,
      "content": {
        "version": "KqlItem/1.0",
        "query": "AzureActivity | where ResourceProvider == \"Microsoft.AzureArcData\" | summarize count() by bin(TimeGenerated, 1h) | order by TimeGenerated desc",
        "size": 0,
        "title": "Arc Data Services Activity",
        "queryType": 0,
        "visualization": "barchart"
      }
    }
  ]
}
EOF
    
    # Deploy workbook template (if supported)
    if az monitor app-insights workbook create \
        --resource-group "$RESOURCE_GROUP" \
        --name "arc-sql-monitoring" \
        --display-name "Arc SQL Monitoring Dashboard" \
        --serialized-data @arc-sql-workbook.json \
        --location "$LOCATION" >/dev/null 2>&1; then
        log "Monitoring dashboard created successfully"
    else
        warn "Could not create monitoring dashboard (workbook may not be supported in this region)"
        info "Workbook template saved as arc-sql-workbook.json for manual import"
    fi
}

# Function to validate deployment
validate_deployment() {
    log "Validating deployment..."
    
    # Check Arc Data Controller status
    info "Checking Arc Data Controller status..."
    az arcdata dc status show \
        --resource-group "$RESOURCE_GROUP" \
        --name "$ARC_DATA_CONTROLLER_NAME" \
        --output table
    
    # Check Kubernetes resources
    info "Checking Kubernetes resources..."
    kubectl get pods -n arc
    
    # Get SQL MI endpoint
    local sql_endpoint=$(az sql mi-arc show \
        --resource-group "$RESOURCE_GROUP" \
        --name "$SQL_MI_NAME" \
        --query status.endpoints.primary \
        --output tsv 2>/dev/null || echo "Not available yet")
    
    info "SQL MI Endpoint: $sql_endpoint"
    
    # Test database creation
    info "Testing database connectivity..."
    if kubectl exec -n arc deployment/"$SQL_MI_NAME" -- \
        /opt/mssql-tools/bin/sqlcmd -S localhost -U "$SQL_ADMIN_USERNAME" -P "$SQL_ADMIN_PASSWORD" \
        -Q "SELECT @@VERSION" >/dev/null 2>&1; then
        log "Database connectivity test passed"
    else
        warn "Database connectivity test failed (may need time to initialize)"
    fi
    
    log "Deployment validation completed"
}

# Function to display deployment summary
display_summary() {
    log "Deployment Summary"
    echo "============================================"
    echo "Resource Group: $RESOURCE_GROUP"
    echo "Location: $LOCATION"
    echo "Arc Data Controller: $ARC_DATA_CONTROLLER_NAME"
    echo "SQL Managed Instance: $SQL_MI_NAME"
    echo "Log Analytics Workspace: $LOG_ANALYTICS_WORKSPACE"
    echo "SQL Admin Username: $SQL_ADMIN_USERNAME"
    echo "============================================"
    echo ""
    echo "Next Steps:"
    echo "1. Wait for all resources to be fully initialized"
    echo "2. Use Azure Data Studio to connect to your SQL MI"
    echo "3. Monitor your deployment in Azure Monitor"
    echo "4. View monitoring dashboard in Azure portal"
    echo ""
    echo "To connect to SQL MI, use:"
    echo "Server: <SQL_MI_ENDPOINT>"
    echo "Username: $SQL_ADMIN_USERNAME"
    echo "Password: $SQL_ADMIN_PASSWORD"
    echo ""
    echo "To clean up resources, run: ./destroy.sh"
}

# Main execution function
main() {
    log "Starting Azure Arc-enabled Data Services deployment..."
    
    # Run deployment steps
    check_prerequisites
    set_environment_variables
    install_extensions
    create_resource_group
    create_log_analytics_workspace
    create_arc_data_controller
    create_sql_managed_instance
    configure_azure_monitor
    setup_monitoring_and_alerts
    configure_security_governance
    create_monitoring_dashboard
    validate_deployment
    display_summary
    
    log "Deployment completed successfully!"
    log "Please allow additional time for all services to fully initialize."
}

# Handle script interruption
trap 'error "Script interrupted"; exit 1' INT TERM

# Run main function
main "$@"