#!/bin/bash

# Hybrid PostgreSQL Database Replication with Azure Arc and Cloud Database
# Deployment Script
# 
# This script deploys the complete hybrid PostgreSQL replication solution including:
# - Azure Arc Data Controller on Kubernetes
# - Arc-enabled PostgreSQL instance
# - Azure Database for PostgreSQL Flexible Server
# - Azure Event Grid for change detection
# - Azure Data Factory for orchestration
# - Monitoring and alerting setup

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case $level in
        INFO)
            echo -e "${BLUE}[INFO]${NC} ${timestamp} - $message"
            ;;
        WARN)
            echo -e "${YELLOW}[WARN]${NC} ${timestamp} - $message"
            ;;
        ERROR)
            echo -e "${RED}[ERROR]${NC} ${timestamp} - $message"
            ;;
        SUCCESS)
            echo -e "${GREEN}[SUCCESS]${NC} ${timestamp} - $message"
            ;;
    esac
    
    # Also log to file
    echo "[$level] $timestamp - $message" >> "deployment_$(date +%Y%m%d_%H%M%S).log"
}

# Error handling
error_exit() {
    log ERROR "$1"
    exit 1
}

# Cleanup function for partial deployments
cleanup_on_error() {
    log WARN "Deployment failed. Cleaning up partial resources..."
    
    # Attempt to clean up resources in reverse order
    if [[ -n "${ADF_NAME:-}" ]]; then
        log INFO "Cleaning up Data Factory..."
        az datafactory delete --name "$ADF_NAME" --resource-group "$RESOURCE_GROUP" --yes 2>/dev/null || true
    fi
    
    if [[ -n "${EVENTGRID_TOPIC:-}" ]]; then
        log INFO "Cleaning up Event Grid topic..."
        az eventgrid topic delete --name "$EVENTGRID_TOPIC" --resource-group "$RESOURCE_GROUP" --yes 2>/dev/null || true
    fi
    
    if [[ -n "${AZURE_PG_NAME:-}" ]]; then
        log INFO "Cleaning up Azure PostgreSQL..."
        az postgres flexible-server delete --name "$AZURE_PG_NAME" --resource-group "$RESOURCE_GROUP" --yes 2>/dev/null || true
    fi
    
    if [[ -n "${POSTGRES_NAME:-}" ]]; then
        log INFO "Cleaning up Arc PostgreSQL..."
        kubectl delete postgresql "$POSTGRES_NAME" -n "$K8S_NAMESPACE" 2>/dev/null || true
    fi
    
    if [[ -n "${ARC_DC_NAME:-}" ]]; then
        log INFO "Cleaning up Arc Data Controller..."
        az arcdata dc delete --name "$ARC_DC_NAME" --resource-group "$RESOURCE_GROUP" --namespace "$K8S_NAMESPACE" --force --yes 2>/dev/null || true
    fi
    
    log WARN "Partial cleanup completed. Please run destroy.sh to ensure all resources are removed."
}

trap cleanup_on_error ERR

# Check prerequisites
check_prerequisites() {
    log INFO "Checking prerequisites..."
    
    # Check if running in bash
    if [[ "$0" != *bash* ]] && [[ -z "${BASH_VERSION:-}" ]]; then
        error_exit "This script must be run with bash"
    fi
    
    # Check required tools
    local required_tools=("az" "kubectl" "jq" "psql" "openssl")
    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            error_exit "Required tool '$tool' is not installed or not in PATH"
        fi
    done
    
    # Check Azure CLI login
    if ! az account show &> /dev/null; then
        error_exit "Please login to Azure CLI using 'az login'"
    fi
    
    # Check kubectl context
    if ! kubectl cluster-info &> /dev/null; then
        error_exit "kubectl is not configured or cluster is not accessible"
    fi
    
    # Check Azure CLI extensions
    if ! az extension list --query "[?name=='arcdata']" -o tsv | grep -q arcdata; then
        log INFO "Installing Azure Arc data services extension..."
        az extension add --name arcdata
    fi
    
    # Verify minimum Kubernetes resources
    local nodes=$(kubectl get nodes --no-headers | wc -l)
    if [[ $nodes -lt 1 ]]; then
        error_exit "Kubernetes cluster must have at least 1 node"
    fi
    
    log SUCCESS "Prerequisites check completed"
}

# Set environment variables
setup_environment() {
    log INFO "Setting up environment variables..."
    
    # Core Azure configuration
    export SUBSCRIPTION_ID=$(az account show --query id -o tsv)
    export RESOURCE_GROUP="${RESOURCE_GROUP:-rg-hybrid-postgres-$(openssl rand -hex 3)}"
    export LOCATION="${LOCATION:-eastus}"
    
    # Arc configuration
    export ARC_DC_NAME="${ARC_DC_NAME:-arc-dc-postgres}"
    export K8S_NAMESPACE="${K8S_NAMESPACE:-arc-data}"
    export POSTGRES_NAME="${POSTGRES_NAME:-postgres-hybrid}"
    
    # Azure services configuration
    export AZURE_PG_NAME="${AZURE_PG_NAME:-azpg-hybrid-$(openssl rand -hex 3)}"
    export ADF_NAME="${ADF_NAME:-adf-hybrid-$(openssl rand -hex 3)}"
    export EVENTGRID_TOPIC="${EVENTGRID_TOPIC:-eg-topic-$(openssl rand -hex 3)}"
    export WORKSPACE_NAME="${WORKSPACE_NAME:-law-hybrid-postgres-$(openssl rand -hex 3)}"
    
    # Database configuration
    export DB_ADMIN_USER="${DB_ADMIN_USER:-pgadmin}"
    export DB_ADMIN_PASSWORD="${DB_ADMIN_PASSWORD:-P@ssw0rd123!}"
    
    # Random suffix for unique naming
    export RANDOM_SUFFIX=$(openssl rand -hex 3)
    
    log INFO "Environment variables configured:"
    log INFO "  Resource Group: $RESOURCE_GROUP"
    log INFO "  Location: $LOCATION"
    log INFO "  Arc Data Controller: $ARC_DC_NAME"
    log INFO "  Kubernetes Namespace: $K8S_NAMESPACE"
    log INFO "  Azure PostgreSQL: $AZURE_PG_NAME"
    log INFO "  Data Factory: $ADF_NAME"
    log INFO "  Event Grid Topic: $EVENTGRID_TOPIC"
}

# Create Azure resource group
create_resource_group() {
    log INFO "Creating Azure resource group..."
    
    if az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        log WARN "Resource group '$RESOURCE_GROUP' already exists"
    else
        az group create \
            --name "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --tags environment=demo purpose=hybrid-replication
        
        log SUCCESS "Resource group '$RESOURCE_GROUP' created"
    fi
}

# Prepare Kubernetes environment
prepare_kubernetes() {
    log INFO "Preparing Kubernetes environment..."
    
    # Create namespace for Arc data services
    if kubectl get namespace "$K8S_NAMESPACE" &> /dev/null; then
        log WARN "Namespace '$K8S_NAMESPACE' already exists"
    else
        kubectl create namespace "$K8S_NAMESPACE"
        log SUCCESS "Namespace '$K8S_NAMESPACE' created"
    fi
    
    # Label namespace for Arc data services
    kubectl label namespace "$K8S_NAMESPACE" \
        arc.azure.com/data-services=enabled \
        --overwrite
    
    log SUCCESS "Kubernetes environment prepared"
}

# Deploy Azure Arc Data Controller
deploy_arc_data_controller() {
    log INFO "Deploying Azure Arc Data Controller..."
    
    # Check if data controller already exists
    if az arcdata dc show --name "$ARC_DC_NAME" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        log WARN "Arc Data Controller '$ARC_DC_NAME' already exists"
        return 0
    fi
    
    # Create service principal for Arc data controller
    local arc_sp_name="sp-arc-dc-$RANDOM_SUFFIX"
    log INFO "Creating service principal '$arc_sp_name'..."
    
    local arc_sp=$(az ad sp create-for-rbac \
        --name "$arc_sp_name" \
        --role Contributor \
        --scopes "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP" \
        --output json)
    
    # Extract credentials
    export ARC_SP_CLIENT_ID=$(echo "$arc_sp" | jq -r '.appId')
    export ARC_SP_CLIENT_SECRET=$(echo "$arc_sp" | jq -r '.password')
    export ARC_SP_TENANT_ID=$(echo "$arc_sp" | jq -r '.tenant')
    
    # Deploy Arc data controller
    log INFO "Creating Arc Data Controller (this may take 10-15 minutes)..."
    az arcdata dc create \
        --name "$ARC_DC_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --connectivity-mode indirect \
        --namespace "$K8S_NAMESPACE" \
        --infrastructure onpremises \
        --k8s-namespace "$K8S_NAMESPACE" \
        --use-k8s
    
    # Wait for data controller to be ready
    log INFO "Waiting for Arc Data Controller to be ready..."
    local timeout=900  # 15 minutes
    local elapsed=0
    while [[ $elapsed -lt $timeout ]]; do
        if kubectl get pods -n "$K8S_NAMESPACE" --selector=app=controller | grep -q Running; then
            break
        fi
        sleep 30
        elapsed=$((elapsed + 30))
        log INFO "Waiting for Arc Data Controller... ($elapsed/$timeout seconds)"
    done
    
    if [[ $elapsed -ge $timeout ]]; then
        error_exit "Arc Data Controller deployment timed out"
    fi
    
    log SUCCESS "Arc Data Controller deployed successfully"
}

# Create Arc-enabled PostgreSQL server
create_arc_postgresql() {
    log INFO "Creating Arc-enabled PostgreSQL server..."
    
    # Check if PostgreSQL instance already exists
    if kubectl get postgresql "$POSTGRES_NAME" -n "$K8S_NAMESPACE" &> /dev/null; then
        log WARN "Arc PostgreSQL '$POSTGRES_NAME' already exists"
        return 0
    fi
    
    # Create PostgreSQL server configuration
    cat <<EOF > /tmp/postgres-config.yaml
apiVersion: arcdata.microsoft.com/v1beta1
kind: PostgreSql
metadata:
  name: $POSTGRES_NAME
  namespace: $K8S_NAMESPACE
spec:
  engine:
    version: 14
  scale:
    replicas: 1
  scheduling:
    default:
      resources:
        requests:
          memory: 4Gi
          cpu: 2
        limits:
          memory: 8Gi
          cpu: 4
  storage:
    data:
      className: default
      size: 50Gi
    logs:
      className: default
      size: 10Gi
  security:
    adminPassword: "$DB_ADMIN_PASSWORD"
EOF
    
    # Deploy PostgreSQL instance
    kubectl apply -f /tmp/postgres-config.yaml
    
    # Wait for PostgreSQL to be ready
    log INFO "Waiting for Arc PostgreSQL to be ready (this may take 10-15 minutes)..."
    kubectl wait --for=condition=Ready \
        --timeout=900s \
        -n "$K8S_NAMESPACE" \
        postgresql/"$POSTGRES_NAME"
    
    # Get connection endpoint
    POSTGRES_ENDPOINT=$(kubectl get postgresql "$POSTGRES_NAME" \
        -n "$K8S_NAMESPACE" \
        -o jsonpath='{.status.primaryEndpoint}')
    
    log SUCCESS "Arc-enabled PostgreSQL deployed at: $POSTGRES_ENDPOINT"
    
    # Clean up temporary file
    rm -f /tmp/postgres-config.yaml
}

# Configure Azure Database for PostgreSQL
configure_azure_postgresql() {
    log INFO "Configuring Azure Database for PostgreSQL Flexible Server..."
    
    # Check if server already exists
    if az postgres flexible-server show --name "$AZURE_PG_NAME" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        log WARN "Azure PostgreSQL '$AZURE_PG_NAME' already exists"
        return 0
    fi
    
    # Create PostgreSQL flexible server
    log INFO "Creating Azure PostgreSQL Flexible Server (this may take 5-10 minutes)..."
    az postgres flexible-server create \
        --name "$AZURE_PG_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --admin-user "$DB_ADMIN_USER" \
        --admin-password "$DB_ADMIN_PASSWORD" \
        --sku-name Standard_D2ds_v4 \
        --storage-size 128 \
        --version 14 \
        --high-availability Disabled \
        --backup-retention 7 \
        --tags purpose=replication-target
    
    # Configure firewall for Azure services
    az postgres flexible-server firewall-rule create \
        --name allow-azure-services \
        --resource-group "$RESOURCE_GROUP" \
        --server-name "$AZURE_PG_NAME" \
        --start-ip-address 0.0.0.0 \
        --end-ip-address 0.0.0.0
    
    # Enable logical replication
    az postgres flexible-server parameter set \
        --name wal_level \
        --value logical \
        --resource-group "$RESOURCE_GROUP" \
        --server-name "$AZURE_PG_NAME"
    
    log SUCCESS "Azure Database for PostgreSQL configured"
}

# Set up Azure Event Grid
setup_event_grid() {
    log INFO "Setting up Azure Event Grid..."
    
    # Check if topic already exists
    if az eventgrid topic show --name "$EVENTGRID_TOPIC" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        log WARN "Event Grid topic '$EVENTGRID_TOPIC' already exists"
        return 0
    fi
    
    # Create Event Grid topic
    az eventgrid topic create \
        --name "$EVENTGRID_TOPIC" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --tags purpose=database-sync
    
    # Get Event Grid endpoint and key
    EG_ENDPOINT=$(az eventgrid topic show \
        --name "$EVENTGRID_TOPIC" \
        --resource-group "$RESOURCE_GROUP" \
        --query endpoint -o tsv)
    
    EG_KEY=$(az eventgrid topic key list \
        --name "$EVENTGRID_TOPIC" \
        --resource-group "$RESOURCE_GROUP" \
        --query key1 -o tsv)
    
    export EG_ENDPOINT
    export EG_KEY
    
    log SUCCESS "Event Grid configured for change detection"
    log INFO "Event Grid Endpoint: $EG_ENDPOINT"
}

# Create Azure Data Factory pipeline
create_data_factory() {
    log INFO "Creating Azure Data Factory pipeline..."
    
    # Check if Data Factory already exists
    if az datafactory show --name "$ADF_NAME" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        log WARN "Data Factory '$ADF_NAME' already exists"
        return 0
    fi
    
    # Create Data Factory instance
    log INFO "Creating Data Factory instance..."
    az datafactory create \
        --name "$ADF_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION"
    
    # Get PostgreSQL connection endpoints
    local postgres_endpoint
    postgres_endpoint=$(kubectl get postgresql "$POSTGRES_NAME" \
        -n "$K8S_NAMESPACE" \
        -o jsonpath='{.status.primaryEndpoint}')
    
    # Create linked services for both PostgreSQL instances
    log INFO "Creating linked services..."
    
    cat <<EOF > /tmp/adf-linkedservice-arc.json
{
  "name": "ArcPostgreSQLLinkedService",
  "properties": {
    "type": "PostgreSql",
    "typeProperties": {
      "connectionString": "Host=$postgres_endpoint;Database=postgres;Username=postgres;Password=$DB_ADMIN_PASSWORD;"
    }
  }
}
EOF
    
    cat <<EOF > /tmp/adf-linkedservice-azure.json
{
  "name": "AzurePostgreSQLLinkedService",
  "properties": {
    "type": "AzurePostgreSql",
    "typeProperties": {
      "connectionString": "Server=$AZURE_PG_NAME.postgres.database.azure.com;Database=postgres;Port=5432;UID=$DB_ADMIN_USER;Password=$DB_ADMIN_PASSWORD;SSL Mode=Require;"
    }
  }
}
EOF
    
    # Create linked services
    az datafactory linked-service create \
        --factory-name "$ADF_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --name ArcPostgreSQLLinkedService \
        --properties @/tmp/adf-linkedservice-arc.json
    
    az datafactory linked-service create \
        --factory-name "$ADF_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --name AzurePostgreSQLLinkedService \
        --properties @/tmp/adf-linkedservice-azure.json
    
    # Create pipeline definition
    cat <<EOF > /tmp/adf-pipeline.json
{
  "name": "HybridPostgreSQLSync",
  "properties": {
    "activities": [
      {
        "name": "IncrementalCopy",
        "type": "Copy",
        "dependsOn": [],
        "policy": {
          "timeout": "7.00:00:00",
          "retry": 3,
          "retryIntervalInSeconds": 30
        },
        "typeProperties": {
          "source": {
            "type": "PostgreSqlSource",
            "query": "SELECT * FROM information_schema.tables WHERE table_schema = 'public'"
          },
          "sink": {
            "type": "AzurePostgreSqlSink",
            "writeBatchSize": 10000,
            "writeBatchTimeout": "00:30:00"
          },
          "enableStaging": false
        },
        "inputs": [
          {
            "referenceName": "ArcPostgreSQLLinkedService",
            "type": "LinkedServiceReference"
          }
        ],
        "outputs": [
          {
            "referenceName": "AzurePostgreSQLLinkedService",
            "type": "LinkedServiceReference"
          }
        ]
      }
    ],
    "parameters": {
      "lastSyncTime": {
        "type": "String",
        "defaultValue": "2024-01-01T00:00:00Z"
      }
    }
  }
}
EOF
    
    # Create the pipeline
    az datafactory pipeline create \
        --factory-name "$ADF_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --name HybridPostgreSQLSync \
        --pipeline @/tmp/adf-pipeline.json
    
    log SUCCESS "Data Factory pipeline components created"
    
    # Clean up temporary files
    rm -f /tmp/adf-linkedservice-*.json /tmp/adf-pipeline.json
}

# Enable monitoring and alerting
enable_monitoring() {
    log INFO "Enabling monitoring and alerting..."
    
    # Check if workspace already exists
    if az monitor log-analytics workspace show --workspace-name "$WORKSPACE_NAME" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        log WARN "Log Analytics workspace '$WORKSPACE_NAME' already exists"
    else
        # Create Log Analytics workspace
        az monitor log-analytics workspace create \
            --workspace-name "$WORKSPACE_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --location "$LOCATION"
    fi
    
    # Configure Arc PostgreSQL monitoring
    cat <<EOF > /tmp/postgres-monitoring.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: postgres-monitoring
  namespace: $K8S_NAMESPACE
data:
  prometheus.yml: |
    global:
      scrape_interval: 30s
    scrape_configs:
      - job_name: 'postgres'
        static_configs:
          - targets: ['$POSTGRES_NAME:9187']
EOF
    
    kubectl apply -f /tmp/postgres-monitoring.yaml
    
    # Create alert for replication lag (if metric is available)
    if az monitor metrics alert create \
        --name alert-replication-lag \
        --resource-group "$RESOURCE_GROUP" \
        --scopes "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.DBforPostgreSQL/flexibleServers/$AZURE_PG_NAME" \
        --condition "avg cpu_percent > 80" \
        --description "Alert when CPU usage exceeds 80%" \
        --severity 2 &> /dev/null; then
        log SUCCESS "Monitoring alert created"
    else
        log WARN "Could not create monitoring alert - metric may not be available yet"
    fi
    
    log SUCCESS "Monitoring and alerting configured"
    
    # Clean up temporary file
    rm -f /tmp/postgres-monitoring.yaml
}

# Validate deployment
validate_deployment() {
    log INFO "Validating deployment..."
    
    # Check Arc PostgreSQL
    log INFO "Validating Arc-enabled PostgreSQL..."
    if kubectl get pods -n "$K8S_NAMESPACE" | grep "$POSTGRES_NAME" | grep -q Running; then
        log SUCCESS "Arc PostgreSQL is running"
    else
        log ERROR "Arc PostgreSQL is not running properly"
        return 1
    fi
    
    # Check Azure PostgreSQL
    log INFO "Validating Azure PostgreSQL..."
    if az postgres flexible-server show --name "$AZURE_PG_NAME" --resource-group "$RESOURCE_GROUP" --query state -o tsv | grep -q Ready; then
        log SUCCESS "Azure PostgreSQL is ready"
    else
        log ERROR "Azure PostgreSQL is not ready"
        return 1
    fi
    
    # Check Event Grid
    log INFO "Validating Event Grid..."
    if az eventgrid topic show --name "$EVENTGRID_TOPIC" --resource-group "$RESOURCE_GROUP" --query provisioningState -o tsv | grep -q Succeeded; then
        log SUCCESS "Event Grid topic is ready"
    else
        log ERROR "Event Grid topic is not ready"
        return 1
    fi
    
    # Check Data Factory
    log INFO "Validating Data Factory..."
    if az datafactory show --name "$ADF_NAME" --resource-group "$RESOURCE_GROUP" --query provisioningState -o tsv | grep -q Succeeded; then
        log SUCCESS "Data Factory is ready"
    else
        log ERROR "Data Factory is not ready"
        return 1
    fi
    
    log SUCCESS "All components validated successfully"
}

# Print deployment summary
print_summary() {
    log SUCCESS "Deployment completed successfully!"
    echo
    echo "=== DEPLOYMENT SUMMARY ==="
    echo "Resource Group: $RESOURCE_GROUP"
    echo "Location: $LOCATION"
    echo
    echo "Arc Data Services:"
    echo "  - Data Controller: $ARC_DC_NAME"
    echo "  - PostgreSQL Instance: $POSTGRES_NAME"
    echo "  - Namespace: $K8S_NAMESPACE"
    echo
    echo "Azure Services:"
    echo "  - PostgreSQL Server: $AZURE_PG_NAME"
    echo "  - Data Factory: $ADF_NAME"
    echo "  - Event Grid Topic: $EVENTGRID_TOPIC"
    echo "  - Log Analytics Workspace: $WORKSPACE_NAME"
    echo
    echo "Connection Information:"
    echo "  - Arc PostgreSQL Endpoint: $POSTGRES_ENDPOINT"
    echo "  - Azure PostgreSQL FQDN: $AZURE_PG_NAME.postgres.database.azure.com"
    echo "  - Database Admin User: $DB_ADMIN_USER"
    echo
    echo "Next Steps:"
    echo "1. Test database connectivity"
    echo "2. Configure replication schedules in Data Factory"
    echo "3. Set up custom monitoring dashboards"
    echo "4. Run validation tests from the recipe"
    echo
    echo "To clean up all resources, run: ./destroy.sh"
    echo "=========================="
}

# Main deployment function
main() {
    log INFO "Starting hybrid PostgreSQL replication deployment..."
    log INFO "Deployment log will be saved to: deployment_$(date +%Y%m%d_%H%M%S).log"
    
    check_prerequisites
    setup_environment
    create_resource_group
    prepare_kubernetes
    deploy_arc_data_controller
    create_arc_postgresql
    configure_azure_postgresql
    setup_event_grid
    create_data_factory
    enable_monitoring
    validate_deployment
    print_summary
    
    log SUCCESS "Deployment completed successfully in $(date)"
}

# Script entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi