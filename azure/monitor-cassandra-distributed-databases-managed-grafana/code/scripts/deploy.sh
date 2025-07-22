#!/bin/bash

# Deploy Azure Managed Instance for Apache Cassandra with Azure Managed Grafana Monitoring
# This script deploys the complete monitoring solution for distributed NoSQL databases

set -euo pipefail

# Script configuration
readonly SCRIPT_NAME="$(basename "$0")"
readonly LOG_FILE="/tmp/cassandra-monitoring-deploy.log"
readonly REQUIRED_CLI_VERSION="2.40.0"

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Logging functions
log() {
    echo -e "[$(date +'%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

log_info() {
    log "${BLUE}[INFO]${NC} $*"
}

log_success() {
    log "${GREEN}[SUCCESS]${NC} $*"
}

log_warn() {
    log "${YELLOW}[WARNING]${NC} $*"
}

log_error() {
    log "${RED}[ERROR]${NC} $*"
}

# Error handling
error_exit() {
    log_error "$1"
    log_error "Deployment failed. Check log file: $LOG_FILE"
    exit 1
}

# Cleanup function for partial deployments
cleanup_on_error() {
    log_warn "Cleaning up partially deployed resources..."
    
    # Only cleanup if resource group exists and was created by this script
    if [[ -n "${RESOURCE_GROUP:-}" ]] && az group exists --name "$RESOURCE_GROUP" 2>/dev/null; then
        log_warn "Deleting resource group: $RESOURCE_GROUP"
        az group delete --name "$RESOURCE_GROUP" --yes --no-wait 2>/dev/null || true
    fi
}

# Set trap for cleanup on error
trap cleanup_on_error ERR

# Prerequisites check function
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        error_exit "Azure CLI is not installed. Please install Azure CLI v${REQUIRED_CLI_VERSION} or later."
    fi
    
    # Check Azure CLI version
    local cli_version
    cli_version=$(az version --output tsv --query '"azure-cli"' 2>/dev/null || echo "0.0.0")
    if [[ "$(printf '%s\n' "$REQUIRED_CLI_VERSION" "$cli_version" | sort -V | head -n1)" != "$REQUIRED_CLI_VERSION" ]]; then
        error_exit "Azure CLI version $REQUIRED_CLI_VERSION or later is required. Current version: $cli_version"
    fi
    
    # Check if logged in to Azure
    if ! az account show &>/dev/null; then
        error_exit "Not logged in to Azure. Please run 'az login' first."
    fi
    
    # Check if openssl is available for random suffix generation
    if ! command -v openssl &> /dev/null; then
        error_exit "openssl is required for generating random suffixes."
    fi
    
    log_success "Prerequisites check passed"
}

# Function to wait for resource deployment
wait_for_resource() {
    local resource_type="$1"
    local resource_name="$2"
    local max_attempts="${3:-60}"
    local attempt=1
    
    log_info "Waiting for $resource_type '$resource_name' to be ready..."
    
    while [[ $attempt -le $max_attempts ]]; do
        if [[ "$resource_type" == "cassandra-cluster" ]]; then
            if az managed-cassandra cluster show \
                --cluster-name "$resource_name" \
                --resource-group "$RESOURCE_GROUP" \
                --query "properties.provisioningState" \
                --output tsv 2>/dev/null | grep -q "Succeeded"; then
                log_success "$resource_type '$resource_name' is ready"
                return 0
            fi
        elif [[ "$resource_type" == "cassandra-datacenter" ]]; then
            if az managed-cassandra datacenter show \
                --cluster-name "$CASSANDRA_CLUSTER_NAME" \
                --data-center-name "$resource_name" \
                --resource-group "$RESOURCE_GROUP" \
                --query "properties.provisioningState" \
                --output tsv 2>/dev/null | grep -q "Succeeded"; then
                log_success "$resource_type '$resource_name' is ready"
                return 0
            fi
        elif [[ "$resource_type" == "grafana" ]]; then
            if az grafana show \
                --name "$resource_name" \
                --resource-group "$RESOURCE_GROUP" \
                --query "properties.provisioningState" \
                --output tsv 2>/dev/null | grep -q "Succeeded"; then
                log_success "$resource_type '$resource_name' is ready"
                return 0
            fi
        fi
        
        log_info "Attempt $attempt/$max_attempts: $resource_type not ready yet, waiting 30 seconds..."
        sleep 30
        ((attempt++))
    done
    
    error_exit "$resource_type '$resource_name' did not become ready within expected time"
}

# Function to prompt for user input with default values
prompt_for_input() {
    local prompt="$1"
    local default_value="$2"
    local input
    
    read -p "$prompt [$default_value]: " input
    echo "${input:-$default_value}"
}

# Main deployment function
main() {
    log_info "Starting Azure Cassandra Monitoring deployment"
    log_info "Log file: $LOG_FILE"
    
    # Check prerequisites
    check_prerequisites
    
    # Configuration with defaults
    export RESOURCE_GROUP="${RESOURCE_GROUP:-rg-cassandra-monitoring}"
    export LOCATION="${LOCATION:-eastus}"
    
    # Get subscription ID
    export SUBSCRIPTION_ID
    SUBSCRIPTION_ID=$(az account show --query id --output tsv)
    log_info "Using subscription: $SUBSCRIPTION_ID"
    
    # Interactive configuration (if not set via environment variables)
    if [[ -z "${SKIP_PROMPTS:-}" ]]; then
        RESOURCE_GROUP=$(prompt_for_input "Resource Group name" "$RESOURCE_GROUP")
        LOCATION=$(prompt_for_input "Azure region" "$LOCATION")
        
        # Validate location
        if ! az account list-locations --query "[?name=='$LOCATION']" --output tsv | grep -q "$LOCATION"; then
            error_exit "Invalid Azure region: $LOCATION"
        fi
    fi
    
    # Generate unique suffix for resource names
    local random_suffix
    random_suffix=$(openssl rand -hex 3)
    export CASSANDRA_CLUSTER_NAME="${CASSANDRA_CLUSTER_NAME:-cassandra-${random_suffix}}"
    export GRAFANA_NAME="${GRAFANA_NAME:-grafana-${random_suffix}}"
    export VNET_NAME="${VNET_NAME:-vnet-cassandra-${random_suffix}}"
    export WORKSPACE_NAME="${WORKSPACE_NAME:-law-cassandra-${random_suffix}}"
    
    log_info "Configuration:"
    log_info "  Resource Group: $RESOURCE_GROUP"
    log_info "  Location: $LOCATION"
    log_info "  Cassandra Cluster: $CASSANDRA_CLUSTER_NAME"
    log_info "  Grafana Instance: $GRAFANA_NAME"
    log_info "  Virtual Network: $VNET_NAME"
    
    # Step 1: Create resource group
    log_info "Step 1: Creating resource group..."
    if az group show --name "$RESOURCE_GROUP" &>/dev/null; then
        log_warn "Resource group '$RESOURCE_GROUP' already exists"
    else
        az group create \
            --name "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --tags purpose=monitoring environment=demo \
            --output none
        log_success "Resource group created: $RESOURCE_GROUP"
    fi
    
    # Step 2: Create virtual network
    log_info "Step 2: Creating virtual network..."
    if az network vnet show --name "$VNET_NAME" --resource-group "$RESOURCE_GROUP" &>/dev/null; then
        log_warn "Virtual network '$VNET_NAME' already exists"
    else
        az network vnet create \
            --name "$VNET_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --address-prefixes 10.0.0.0/16 \
            --output none
        
        az network vnet subnet create \
            --name cassandra-subnet \
            --resource-group "$RESOURCE_GROUP" \
            --vnet-name "$VNET_NAME" \
            --address-prefixes 10.0.1.0/24 \
            --output none
        
        log_success "Virtual network configured: $VNET_NAME"
    fi
    
    # Get subnet ID for Cassandra deployment
    local subnet_id
    subnet_id=$(az network vnet subnet show \
        --name cassandra-subnet \
        --resource-group "$RESOURCE_GROUP" \
        --vnet-name "$VNET_NAME" \
        --query id --output tsv)
    
    # Step 3: Deploy Cassandra cluster
    log_info "Step 3: Deploying Cassandra cluster (this may take 15-20 minutes)..."
    if az managed-cassandra cluster show --cluster-name "$CASSANDRA_CLUSTER_NAME" --resource-group "$RESOURCE_GROUP" &>/dev/null; then
        log_warn "Cassandra cluster '$CASSANDRA_CLUSTER_NAME' already exists"
    else
        az managed-cassandra cluster create \
            --cluster-name "$CASSANDRA_CLUSTER_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --delegated-management-subnet-id "$subnet_id" \
            --initial-cassandra-admin-password "P@ssw0rd123!" \
            --client-certificates \
            --cassandra-version "4.0" \
            --output none
        
        log_success "Cassandra cluster deployment initiated: $CASSANDRA_CLUSTER_NAME"
        wait_for_resource "cassandra-cluster" "$CASSANDRA_CLUSTER_NAME" 60
    fi
    
    # Step 4: Create Cassandra data center
    log_info "Step 4: Creating Cassandra data center..."
    if az managed-cassandra datacenter show \
        --cluster-name "$CASSANDRA_CLUSTER_NAME" \
        --data-center-name "dc1" \
        --resource-group "$RESOURCE_GROUP" &>/dev/null; then
        log_warn "Data center 'dc1' already exists"
    else
        az managed-cassandra datacenter create \
            --cluster-name "$CASSANDRA_CLUSTER_NAME" \
            --data-center-name "dc1" \
            --resource-group "$RESOURCE_GROUP" \
            --data-center-location "$LOCATION" \
            --delegated-subnet-id "$subnet_id" \
            --node-count 3 \
            --sku "Standard_DS14_v2" \
            --output none
        
        log_success "Data center creation initiated with 3 nodes"
        wait_for_resource "cassandra-datacenter" "dc1" 60
    fi
    
    # Step 5: Create Log Analytics workspace
    log_info "Step 5: Creating Log Analytics workspace..."
    if az monitor log-analytics workspace show \
        --workspace-name "$WORKSPACE_NAME" \
        --resource-group "$RESOURCE_GROUP" &>/dev/null; then
        log_warn "Log Analytics workspace '$WORKSPACE_NAME' already exists"
    else
        az monitor log-analytics workspace create \
            --workspace-name "$WORKSPACE_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --output none
        log_success "Log Analytics workspace created: $WORKSPACE_NAME"
    fi
    
    # Get workspace ID for diagnostic settings
    local workspace_id
    workspace_id=$(az monitor log-analytics workspace show \
        --workspace-name "$WORKSPACE_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --query id --output tsv)
    
    # Step 6: Configure diagnostic settings
    log_info "Step 6: Configuring diagnostic settings..."
    local cassandra_resource_id="/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.DocumentDB/cassandraClusters/${CASSANDRA_CLUSTER_NAME}"
    
    if az monitor diagnostic-settings show \
        --name "cassandra-diagnostics" \
        --resource "$cassandra_resource_id" &>/dev/null; then
        log_warn "Diagnostic settings already configured"
    else
        az monitor diagnostic-settings create \
            --name "cassandra-diagnostics" \
            --resource "$cassandra_resource_id" \
            --workspace "$workspace_id" \
            --logs '[{"category":"CassandraLogs","enabled":true},{"category":"CassandraAudit","enabled":true}]' \
            --metrics '[{"category":"AllMetrics","enabled":true}]' \
            --output none
        log_success "Diagnostic settings configured"
    fi
    
    # Step 7: Deploy Azure Managed Grafana
    log_info "Step 7: Deploying Azure Managed Grafana..."
    if az grafana show --name "$GRAFANA_NAME" --resource-group "$RESOURCE_GROUP" &>/dev/null; then
        log_warn "Grafana instance '$GRAFANA_NAME' already exists"
    else
        az grafana create \
            --name "$GRAFANA_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --sku "Standard" \
            --output none
        
        log_success "Azure Managed Grafana deployment initiated"
        wait_for_resource "grafana" "$GRAFANA_NAME" 30
    fi
    
    # Get Grafana endpoint
    local grafana_endpoint
    grafana_endpoint=$(az grafana show \
        --name "$GRAFANA_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --query properties.endpoint --output tsv)
    
    # Step 8: Configure Grafana permissions
    log_info "Step 8: Configuring Grafana permissions..."
    local grafana_identity
    grafana_identity=$(az grafana show \
        --name "$GRAFANA_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --query identity.principalId --output tsv)
    
    # Check if role assignment already exists
    if az role assignment list \
        --assignee "$grafana_identity" \
        --role "Monitoring Reader" \
        --scope "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}" \
        --query "[0].id" --output tsv &>/dev/null; then
        log_warn "Monitoring Reader role already assigned to Grafana"
    else
        az role assignment create \
            --assignee "$grafana_identity" \
            --role "Monitoring Reader" \
            --scope "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}" \
            --output none
        log_success "Grafana permissions configured"
    fi
    
    # Step 9: Create action group and alerts
    log_info "Step 9: Creating monitoring alerts..."
    if az monitor action-group show \
        --name "cassandra-alerts" \
        --resource-group "$RESOURCE_GROUP" &>/dev/null; then
        log_warn "Action group 'cassandra-alerts' already exists"
    else
        az monitor action-group create \
            --name "cassandra-alerts" \
            --resource-group "$RESOURCE_GROUP" \
            --short-name "CassAlert" \
            --email-receiver name="ops-team" email-address="ops@example.com" \
            --output none
        log_success "Action group created for alerts"
    fi
    
    # Create metric alert for high CPU usage
    if az monitor metrics alert show \
        --name "cassandra-high-cpu" \
        --resource-group "$RESOURCE_GROUP" &>/dev/null; then
        log_warn "CPU alert 'cassandra-high-cpu' already exists"
    else
        az monitor metrics alert create \
            --name "cassandra-high-cpu" \
            --resource-group "$RESOURCE_GROUP" \
            --scopes "$cassandra_resource_id" \
            --condition "avg CPUUsage > 80" \
            --window-size 5m \
            --evaluation-frequency 1m \
            --action "cassandra-alerts" \
            --description "Alert when Cassandra CPU usage exceeds 80%" \
            --output none
        log_success "CPU monitoring alert configured"
    fi
    
    # Generate dashboard configuration files
    log_info "Step 10: Creating dashboard configuration files..."
    
    # Create data source configuration
    cat > datasource-config.json << EOF
{
  "name": "Azure Monitor - Cassandra",
  "type": "grafana-azure-monitor-datasource",
  "access": "proxy",
  "jsonData": {
    "azureAuthType": "msi",
    "subscriptionId": "${SUBSCRIPTION_ID}"
  }
}
EOF
    
    # Create dashboard JSON configuration
    cat > cassandra-dashboard.json << EOF
{
  "dashboard": {
    "title": "Cassandra Cluster Monitoring",
    "panels": [
      {
        "title": "Node CPU Usage",
        "targets": [
          {
            "azureMonitor": {
              "resourceGroup": "${RESOURCE_GROUP}",
              "metricName": "CPUUsage",
              "aggregation": "Average",
              "timeGrain": "PT1M"
            }
          }
        ],
        "gridPos": {"h": 8, "w": 12, "x": 0, "y": 0}
      },
      {
        "title": "Read/Write Latency",
        "targets": [
          {
            "azureMonitor": {
              "resourceGroup": "${RESOURCE_GROUP}",
              "metricName": "ReadLatency",
              "aggregation": "Average",
              "timeGrain": "PT1M"
            }
          }
        ],
        "gridPos": {"h": 8, "w": 12, "x": 12, "y": 0}
      }
    ],
    "time": {"from": "now-6h", "to": "now"},
    "refresh": "30s"
  }
}
EOF
    
    log_success "Dashboard configuration files created"
    
    # Final summary
    log_success "============================================"
    log_success "Deployment completed successfully!"
    log_success "============================================"
    log_info "Resource Summary:"
    log_info "  Resource Group: $RESOURCE_GROUP"
    log_info "  Cassandra Cluster: $CASSANDRA_CLUSTER_NAME"
    log_info "  Grafana Instance: $GRAFANA_NAME"
    log_info "  Grafana URL: $grafana_endpoint"
    log_info "  Virtual Network: $VNET_NAME"
    log_info "  Log Analytics Workspace: $WORKSPACE_NAME"
    log_info ""
    log_info "Next Steps:"
    log_info "1. Access Grafana at: $grafana_endpoint"
    log_info "2. Use your Azure AD credentials to log in"
    log_info "3. Import the data source configuration from: datasource-config.json"
    log_info "4. Import the dashboard configuration from: cassandra-dashboard.json"
    log_info ""
    log_warn "Remember to run destroy.sh when you're done to avoid charges!"
    log_info "Deployment log saved to: $LOG_FILE"
}

# Script entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi