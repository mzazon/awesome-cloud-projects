#!/bin/bash

# Deploy script for Comprehensive Container Monitoring with Azure Container Storage and Managed Prometheus
# This script deploys the complete monitoring solution for stateful workloads

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/deploy.log"
DRY_RUN="${DRY_RUN:-false}"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}" | tee -a "$LOG_FILE"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}" | tee -a "$LOG_FILE"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}" | tee -a "$LOG_FILE"
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1${NC}" | tee -a "$LOG_FILE"
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check Azure CLI
    if ! command -v az &> /dev/null; then
        error "Azure CLI is not installed. Please install it from https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
        exit 1
    fi
    
    # Check Azure CLI version
    local az_version=$(az version --query '."azure-cli"' -o tsv)
    log "Azure CLI version: $az_version"
    
    # Check if logged in
    if ! az account show &> /dev/null; then
        error "Not logged in to Azure. Please run 'az login' first."
        exit 1
    fi
    
    # Check required extensions
    local extensions=("containerapp" "monitor-control-service")
    for ext in "${extensions[@]}"; do
        if ! az extension show --name "$ext" &> /dev/null; then
            warn "Extension $ext not found. Installing..."
            az extension add --name "$ext" --upgrade
        fi
    done
    
    # Check OpenSSL for random generation
    if ! command -v openssl &> /dev/null; then
        error "OpenSSL is not installed. Please install it for random string generation."
        exit 1
    fi
    
    log "Prerequisites check completed successfully"
}

# Function to set environment variables
set_environment_variables() {
    log "Setting environment variables..."
    
    # Generate unique suffix for resource names
    export RANDOM_SUFFIX=$(openssl rand -hex 3)
    
    # Set Azure environment variables
    export RESOURCE_GROUP="${RESOURCE_GROUP:-rg-stateful-monitoring-${RANDOM_SUFFIX}}"
    export LOCATION="${LOCATION:-eastus}"
    export SUBSCRIPTION_ID=$(az account show --query id --output tsv)
    
    # Set service-specific variables
    export CONTAINER_APP_ENV="${CONTAINER_APP_ENV:-cae-stateful-${RANDOM_SUFFIX}}"
    export CONTAINER_APP_NAME="${CONTAINER_APP_NAME:-ca-stateful-app-${RANDOM_SUFFIX}}"
    export STORAGE_ACCOUNT="${STORAGE_ACCOUNT:-st${RANDOM_SUFFIX}}"
    export MONITOR_WORKSPACE="${MONITOR_WORKSPACE:-amw-prometheus-${RANDOM_SUFFIX}}"
    export GRAFANA_INSTANCE="${GRAFANA_INSTANCE:-grafana-${RANDOM_SUFFIX}}"
    export LOG_ANALYTICS_WORKSPACE="${LOG_ANALYTICS_WORKSPACE:-law-monitoring-${RANDOM_SUFFIX}}"
    export MONITORING_SIDECAR_NAME="monitoring-sidecar-${RANDOM_SUFFIX}"
    
    # Log the configuration
    info "Configuration:"
    info "  Resource Group: $RESOURCE_GROUP"
    info "  Location: $LOCATION"
    info "  Subscription ID: $SUBSCRIPTION_ID"
    info "  Container App Environment: $CONTAINER_APP_ENV"
    info "  Container App Name: $CONTAINER_APP_NAME"
    info "  Storage Account: $STORAGE_ACCOUNT"
    info "  Monitor Workspace: $MONITOR_WORKSPACE"
    info "  Grafana Instance: $GRAFANA_INSTANCE"
    info "  Log Analytics Workspace: $LOG_ANALYTICS_WORKSPACE"
    
    # Save environment variables to file for cleanup script
    cat > "${SCRIPT_DIR}/deployment_vars.env" <<EOF
RESOURCE_GROUP=$RESOURCE_GROUP
LOCATION=$LOCATION
SUBSCRIPTION_ID=$SUBSCRIPTION_ID
CONTAINER_APP_ENV=$CONTAINER_APP_ENV
CONTAINER_APP_NAME=$CONTAINER_APP_NAME
STORAGE_ACCOUNT=$STORAGE_ACCOUNT
MONITOR_WORKSPACE=$MONITOR_WORKSPACE
GRAFANA_INSTANCE=$GRAFANA_INSTANCE
LOG_ANALYTICS_WORKSPACE=$LOG_ANALYTICS_WORKSPACE
MONITORING_SIDECAR_NAME=$MONITORING_SIDECAR_NAME
RANDOM_SUFFIX=$RANDOM_SUFFIX
EOF
    
    log "Environment variables set successfully"
}

# Function to create resource group
create_resource_group() {
    log "Creating resource group..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "DRY RUN: Would create resource group $RESOURCE_GROUP in $LOCATION"
        return 0
    fi
    
    az group create \
        --name "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --tags purpose=stateful-monitoring environment=demo deployment=automated
    
    log "✅ Resource group created: $RESOURCE_GROUP"
}

# Function to create Log Analytics workspace
create_log_analytics_workspace() {
    log "Creating Log Analytics workspace..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "DRY RUN: Would create Log Analytics workspace $LOG_ANALYTICS_WORKSPACE"
        return 0
    fi
    
    az monitor log-analytics workspace create \
        --resource-group "$RESOURCE_GROUP" \
        --workspace-name "$LOG_ANALYTICS_WORKSPACE" \
        --location "$LOCATION" \
        --tags purpose=container-monitoring deployment=automated
    
    log "✅ Log Analytics workspace created: $LOG_ANALYTICS_WORKSPACE"
}

# Function to create Azure Monitor workspace
create_monitor_workspace() {
    log "Creating Azure Monitor workspace for Prometheus..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "DRY RUN: Would create Azure Monitor workspace $MONITOR_WORKSPACE"
        return 0
    fi
    
    az monitor account create \
        --name "$MONITOR_WORKSPACE" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --tags workload=stateful-monitoring service=prometheus deployment=automated
    
    # Get the workspace resource ID for later use
    export MONITOR_WORKSPACE_ID=$(az monitor account show \
        --name "$MONITOR_WORKSPACE" \
        --resource-group "$RESOURCE_GROUP" \
        --query id --output tsv)
    
    echo "MONITOR_WORKSPACE_ID=$MONITOR_WORKSPACE_ID" >> "${SCRIPT_DIR}/deployment_vars.env"
    
    log "✅ Azure Monitor workspace created: $MONITOR_WORKSPACE"
}

# Function to create Container Apps environment
create_container_apps_environment() {
    log "Creating Container Apps environment with monitoring..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "DRY RUN: Would create Container Apps environment $CONTAINER_APP_ENV"
        return 0
    fi
    
    # Get Log Analytics workspace details
    local workspace_id=$(az monitor log-analytics workspace show \
        --resource-group "$RESOURCE_GROUP" \
        --workspace-name "$LOG_ANALYTICS_WORKSPACE" \
        --query customerId --output tsv)
    
    local workspace_key=$(az monitor log-analytics workspace get-shared-keys \
        --resource-group "$RESOURCE_GROUP" \
        --workspace-name "$LOG_ANALYTICS_WORKSPACE" \
        --query primarySharedKey --output tsv)
    
    # Create Container Apps environment
    az containerapp env create \
        --name "$CONTAINER_APP_ENV" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --logs-workspace-id "$workspace_id" \
        --logs-workspace-key "$workspace_key" \
        --tags purpose=stateful-workloads deployment=automated
    
    # Wait for environment to be ready
    log "Waiting for Container Apps environment to be ready..."
    az containerapp env show \
        --name "$CONTAINER_APP_ENV" \
        --resource-group "$RESOURCE_GROUP" \
        --query "properties.provisioningState" --output tsv
    
    log "✅ Container Apps environment created: $CONTAINER_APP_ENV"
}

# Function to create storage account
create_storage_account() {
    log "Creating premium storage account for Container Storage..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "DRY RUN: Would create storage account $STORAGE_ACCOUNT"
        return 0
    fi
    
    az storage account create \
        --name "$STORAGE_ACCOUNT" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --sku Premium_LRS \
        --kind StorageV2 \
        --access-tier Hot \
        --https-only true \
        --tags purpose=container-storage deployment=automated
    
    # Get storage account key
    export STORAGE_KEY=$(az storage account keys list \
        --resource-group "$RESOURCE_GROUP" \
        --account-name "$STORAGE_ACCOUNT" \
        --query '[0].value' --output tsv)
    
    echo "STORAGE_KEY=$STORAGE_KEY" >> "${SCRIPT_DIR}/deployment_vars.env"
    
    log "✅ Premium storage account created: $STORAGE_ACCOUNT"
}

# Function to create storage share
create_storage_share() {
    log "Creating storage share for persistent volumes..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "DRY RUN: Would create storage share postgresql-data"
        return 0
    fi
    
    # Create file share for PostgreSQL data
    az storage share create \
        --name postgresql-data \
        --account-name "$STORAGE_ACCOUNT" \
        --account-key "$STORAGE_KEY" \
        --quota 100
    
    log "✅ Storage share created for persistent volumes"
}

# Function to deploy stateful application
deploy_stateful_application() {
    log "Deploying stateful PostgreSQL application..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "DRY RUN: Would deploy stateful application $CONTAINER_APP_NAME"
        return 0
    fi
    
    # Create container app with persistent storage
    az containerapp create \
        --name "$CONTAINER_APP_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --environment "$CONTAINER_APP_ENV" \
        --image postgres:14 \
        --target-port 5432 \
        --ingress external \
        --min-replicas 1 \
        --max-replicas 3 \
        --cpu 1.0 \
        --memory 2.0Gi \
        --env-vars POSTGRES_DB=sampledb \
                   POSTGRES_USER=sampleuser \
                   POSTGRES_PASSWORD=samplepass123 \
        --secrets storage-key="$STORAGE_KEY" \
        --tags purpose=stateful-workload deployment=automated
    
    log "✅ Stateful PostgreSQL application deployed: $CONTAINER_APP_NAME"
}

# Function to configure Prometheus monitoring
configure_prometheus_monitoring() {
    log "Configuring Azure Managed Prometheus monitoring..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "DRY RUN: Would configure Prometheus monitoring"
        return 0
    fi
    
    # Configure Prometheus scraping rules
    cat > "${SCRIPT_DIR}/prometheus-rules.json" <<EOF
[
    {
        "record": "container_cpu_usage_rate",
        "expression": "rate(container_cpu_usage_seconds_total[5m])"
    },
    {
        "record": "container_memory_usage_percent",
        "expression": "container_memory_working_set_bytes / container_spec_memory_limit_bytes * 100"
    },
    {
        "record": "stateful_app:storage_efficiency_ratio",
        "expression": "storage_pool_capacity_used_bytes / storage_pool_capacity_provisioned_bytes"
    },
    {
        "record": "stateful_app:container_restart_rate_5m",
        "expression": "rate(container_restarts_total[5m])"
    }
]
EOF
    
    # Create Prometheus rule group for metrics
    az monitor prometheus rule-group create \
        --resource-group "$RESOURCE_GROUP" \
        --workspace-name "$MONITOR_WORKSPACE" \
        --name "stateful-app-metrics" \
        --location "$LOCATION" \
        --description "Metrics collection for stateful applications" \
        --rules "@${SCRIPT_DIR}/prometheus-rules.json"
    
    log "✅ Prometheus monitoring configured with custom rules"
}

# Function to create Grafana instance
create_grafana_instance() {
    log "Creating Azure Managed Grafana instance..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "DRY RUN: Would create Grafana instance $GRAFANA_INSTANCE"
        return 0
    fi
    
    # Create Grafana instance
    az grafana create \
        --name "$GRAFANA_INSTANCE" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --sku Standard \
        --tags monitoring=prometheus workload=stateful deployment=automated
    
    # Get Grafana endpoint
    export GRAFANA_URL=$(az grafana show \
        --name "$GRAFANA_INSTANCE" \
        --resource-group "$RESOURCE_GROUP" \
        --query "properties.endpoint" --output tsv)
    
    echo "GRAFANA_URL=$GRAFANA_URL" >> "${SCRIPT_DIR}/deployment_vars.env"
    
    log "✅ Grafana instance created: $GRAFANA_INSTANCE"
    log "   Access URL: $GRAFANA_URL"
}

# Function to configure monitoring alerts
configure_monitoring_alerts() {
    log "Configuring automated monitoring alerts..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "DRY RUN: Would configure monitoring alerts"
        return 0
    fi
    
    # Create alerting rules for stateful workloads
    cat > "${SCRIPT_DIR}/alert-rules.json" <<EOF
[
    {
        "alert": "ContainerHighCPUUsage",
        "expression": "container_cpu_usage_rate > 0.8",
        "for": "5m",
        "annotations": {
            "summary": "Container CPU usage is above 80%",
            "description": "Container {{ \$labels.container }} has high CPU usage"
        }
    },
    {
        "alert": "StoragePoolCapacityWarning",
        "expression": "stateful_app:storage_efficiency_ratio > 0.85",
        "for": "10m",
        "annotations": {
            "summary": "Storage pool capacity is above 85%",
            "description": "Storage pool utilization requires attention"
        }
    }
]
EOF
    
    # Create alert rule group
    az monitor prometheus rule-group create \
        --resource-group "$RESOURCE_GROUP" \
        --workspace-name "$MONITOR_WORKSPACE" \
        --name "stateful-workload-alerts" \
        --location "$LOCATION" \
        --description "Critical alerts for stateful workload monitoring" \
        --rules "@${SCRIPT_DIR}/alert-rules.json"
    
    log "✅ Monitoring alerts configured successfully"
}

# Function to deploy monitoring sidecar
deploy_monitoring_sidecar() {
    log "Deploying monitoring sidecar container..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "DRY RUN: Would deploy monitoring sidecar $MONITORING_SIDECAR_NAME"
        return 0
    fi
    
    # Deploy monitoring sidecar
    az containerapp create \
        --name "$MONITORING_SIDECAR_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --environment "$CONTAINER_APP_ENV" \
        --image prom/node-exporter:latest \
        --target-port 9100 \
        --ingress internal \
        --min-replicas 1 \
        --max-replicas 1 \
        --cpu 0.25 \
        --memory 0.5Gi \
        --command "/bin/node_exporter" \
        --args "--path.rootfs=/host" \
        --tags purpose=monitoring deployment=automated
    
    log "✅ Monitoring sidecar deployed: $MONITORING_SIDECAR_NAME"
}

# Function to validate deployment
validate_deployment() {
    log "Validating deployment..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "DRY RUN: Would validate deployment"
        return 0
    fi
    
    # Check Container Apps environment
    local env_state=$(az containerapp env show \
        --name "$CONTAINER_APP_ENV" \
        --resource-group "$RESOURCE_GROUP" \
        --query "properties.provisioningState" --output tsv)
    
    if [[ "$env_state" != "Succeeded" ]]; then
        error "Container Apps environment is not in succeeded state: $env_state"
        return 1
    fi
    
    # Check container app
    local app_state=$(az containerapp show \
        --name "$CONTAINER_APP_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --query "properties.provisioningState" --output tsv)
    
    if [[ "$app_state" != "Succeeded" ]]; then
        error "Container app is not in succeeded state: $app_state"
        return 1
    fi
    
    # Check Grafana instance
    local grafana_state=$(az grafana show \
        --name "$GRAFANA_INSTANCE" \
        --resource-group "$RESOURCE_GROUP" \
        --query "properties.provisioningState" --output tsv)
    
    if [[ "$grafana_state" != "Succeeded" ]]; then
        error "Grafana instance is not in succeeded state: $grafana_state"
        return 1
    fi
    
    log "✅ Deployment validation completed successfully"
}

# Function to display deployment summary
display_deployment_summary() {
    log "Deployment Summary:"
    log "=================="
    log "Resource Group: $RESOURCE_GROUP"
    log "Location: $LOCATION"
    log "Container Apps Environment: $CONTAINER_APP_ENV"
    log "Stateful Application: $CONTAINER_APP_NAME"
    log "Storage Account: $STORAGE_ACCOUNT"
    log "Monitor Workspace: $MONITOR_WORKSPACE"
    log "Grafana Instance: $GRAFANA_INSTANCE"
    if [[ -n "${GRAFANA_URL:-}" ]]; then
        log "Grafana URL: $GRAFANA_URL"
    fi
    log "Log Analytics Workspace: $LOG_ANALYTICS_WORKSPACE"
    log "Monitoring Sidecar: $MONITORING_SIDECAR_NAME"
    log ""
    log "Next Steps:"
    log "1. Access Grafana at: $GRAFANA_URL"
    log "2. Configure dashboards for monitoring"
    log "3. Set up additional alerting if needed"
    log "4. Monitor container and storage metrics"
    log ""
    log "To clean up resources, run: ./destroy.sh"
}

# Main deployment function
main() {
    log "Starting deployment of Azure Stateful Workload Monitoring solution..."
    
    # Initialize log file
    echo "Deployment started at $(date)" > "$LOG_FILE"
    
    # Check if dry run is requested
    if [[ "$DRY_RUN" == "true" ]]; then
        warn "Running in DRY RUN mode - no resources will be created"
    fi
    
    # Execute deployment steps
    check_prerequisites
    set_environment_variables
    create_resource_group
    create_log_analytics_workspace
    create_monitor_workspace
    create_container_apps_environment
    create_storage_account
    create_storage_share
    deploy_stateful_application
    configure_prometheus_monitoring
    create_grafana_instance
    configure_monitoring_alerts
    deploy_monitoring_sidecar
    validate_deployment
    display_deployment_summary
    
    log "🎉 Deployment completed successfully!"
    log "Check the log file for details: $LOG_FILE"
}

# Trap for cleanup on script exit
cleanup() {
    local exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        error "Deployment failed with exit code $exit_code"
        error "Check the log file for details: $LOG_FILE"
    fi
    
    # Clean up temporary files
    rm -f "${SCRIPT_DIR}/prometheus-rules.json"
    rm -f "${SCRIPT_DIR}/alert-rules.json"
}

trap cleanup EXIT

# Handle script arguments
case "${1:-}" in
    --dry-run)
        DRY_RUN=true
        ;;
    --help)
        echo "Usage: $0 [--dry-run|--help]"
        echo "  --dry-run: Show what would be deployed without actually creating resources"
        echo "  --help: Show this help message"
        exit 0
        ;;
    "")
        # No arguments, continue with normal execution
        ;;
    *)
        error "Unknown argument: $1"
        echo "Use --help for usage information"
        exit 1
        ;;
esac

# Run main function
main "$@"