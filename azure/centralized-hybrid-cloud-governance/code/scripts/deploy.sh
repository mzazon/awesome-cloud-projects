#!/bin/bash

# Azure Arc and Azure Policy Deployment Script
# This script automates the deployment of Azure Arc governance infrastructure
# and configures policy enforcement across hybrid environments

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
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} ✅ $1"
}

log_warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} ⚠️ $1"
}

log_error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} ❌ $1"
}

# Default values
RESOURCE_GROUP=""
LOCATION="eastus"
SUBSCRIPTION_ID=""
WORKSPACE_NAME=""
CLUSTER_NAME=""
DRY_RUN=false
SKIP_CLUSTER_CONNECT=false
FORCE_DEPLOYMENT=false

# Help function
show_help() {
    cat << EOF
Azure Arc and Azure Policy Deployment Script

Usage: $0 [OPTIONS]

Options:
    -g, --resource-group NAME    Resource group name (required)
    -l, --location LOCATION      Azure region (default: eastus)
    -s, --subscription ID        Azure subscription ID (optional - uses current)
    -w, --workspace NAME         Log Analytics workspace name (optional - auto-generated)
    -c, --cluster NAME          Kubernetes cluster name (optional - auto-generated)
    -d, --dry-run               Show what would be deployed without making changes
    -k, --skip-cluster          Skip Kubernetes cluster connection to Arc
    -f, --force                 Force deployment even if resources exist
    -h, --help                  Show this help message

Prerequisites:
    - Azure CLI installed and logged in
    - kubectl CLI installed (if connecting Kubernetes clusters)
    - Appropriate Azure permissions (Owner or Contributor)
    - Network connectivity to Azure endpoints

Example:
    $0 -g rg-arc-governance -l eastus -d
    $0 --resource-group rg-arc-governance --location westus2 --force

EOF
}

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
        -s|--subscription)
            SUBSCRIPTION_ID="$2"
            shift 2
            ;;
        -w|--workspace)
            WORKSPACE_NAME="$2"
            shift 2
            ;;
        -c|--cluster)
            CLUSTER_NAME="$2"
            shift 2
            ;;
        -d|--dry-run)
            DRY_RUN=true
            shift
            ;;
        -k|--skip-cluster)
            SKIP_CLUSTER_CONNECT=true
            shift
            ;;
        -f|--force)
            FORCE_DEPLOYMENT=true
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Validate required parameters
if [[ -z "$RESOURCE_GROUP" ]]; then
    log_error "Resource group name is required. Use -g or --resource-group."
    show_help
    exit 1
fi

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        log_error "Azure CLI is not installed. Please install it from https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
        exit 1
    fi
    
    # Check if kubectl is installed (only if not skipping cluster connection)
    if [[ "$SKIP_CLUSTER_CONNECT" == false ]] && ! command -v kubectl &> /dev/null; then
        log_warning "kubectl is not installed. Kubernetes cluster connection will be skipped."
        SKIP_CLUSTER_CONNECT=true
    fi
    
    # Check if logged in to Azure
    if ! az account show &> /dev/null; then
        log_error "Not logged in to Azure. Please run 'az login' first."
        exit 1
    fi
    
    # Get subscription ID if not provided
    if [[ -z "$SUBSCRIPTION_ID" ]]; then
        SUBSCRIPTION_ID=$(az account show --query id --output tsv)
        log "Using current subscription: $SUBSCRIPTION_ID"
    else
        # Set the subscription
        az account set --subscription "$SUBSCRIPTION_ID"
        log "Set subscription to: $SUBSCRIPTION_ID"
    fi
    
    # Check if resource group exists
    if az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        if [[ "$FORCE_DEPLOYMENT" == false ]]; then
            log_warning "Resource group '$RESOURCE_GROUP' already exists."
            read -p "Continue with existing resource group? (y/N): " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                log "Deployment cancelled by user."
                exit 0
            fi
        fi
    fi
    
    log_success "Prerequisites check completed"
}

# Generate unique suffix for resource names
generate_unique_suffix() {
    if command -v openssl &> /dev/null; then
        echo $(openssl rand -hex 3)
    else
        echo $(date +%s | tail -c 7)
    fi
}

# Setup environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    # Generate unique suffix if not in dry run mode
    if [[ "$DRY_RUN" == false ]]; then
        RANDOM_SUFFIX=$(generate_unique_suffix)
    else
        RANDOM_SUFFIX="dryrun"
    fi
    
    # Set workspace name if not provided
    if [[ -z "$WORKSPACE_NAME" ]]; then
        WORKSPACE_NAME="law-arc-${RANDOM_SUFFIX}"
    fi
    
    # Set cluster name if not provided
    if [[ -z "$CLUSTER_NAME" ]]; then
        CLUSTER_NAME="arc-k8s-onprem-${RANDOM_SUFFIX}"
    fi
    
    log "Resource Group: $RESOURCE_GROUP"
    log "Location: $LOCATION"
    log "Subscription: $SUBSCRIPTION_ID"
    log "Workspace: $WORKSPACE_NAME"
    log "Cluster: $CLUSTER_NAME"
    log "Random Suffix: $RANDOM_SUFFIX"
    
    export RESOURCE_GROUP
    export LOCATION
    export SUBSCRIPTION_ID
    export WORKSPACE_NAME
    export CLUSTER_NAME
    export RANDOM_SUFFIX
    
    log_success "Environment variables configured"
}

# Create resource group and Log Analytics workspace
create_foundation() {
    log "Creating foundation resources..."
    
    if [[ "$DRY_RUN" == true ]]; then
        log "[DRY RUN] Would create resource group: $RESOURCE_GROUP"
        log "[DRY RUN] Would create Log Analytics workspace: $WORKSPACE_NAME"
        return 0
    fi
    
    # Create resource group
    if ! az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        log "Creating resource group: $RESOURCE_GROUP"
        az group create \
            --name "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --tags purpose=hybrid-governance environment=demo \
            --output none
        log_success "Resource group created: $RESOURCE_GROUP"
    else
        log_warning "Resource group already exists: $RESOURCE_GROUP"
    fi
    
    # Create Log Analytics workspace
    if ! az monitor log-analytics workspace show --resource-group "$RESOURCE_GROUP" --workspace-name "$WORKSPACE_NAME" &> /dev/null; then
        log "Creating Log Analytics workspace: $WORKSPACE_NAME"
        az monitor log-analytics workspace create \
            --resource-group "$RESOURCE_GROUP" \
            --workspace-name "$WORKSPACE_NAME" \
            --location "$LOCATION" \
            --output none
        log_success "Log Analytics workspace created: $WORKSPACE_NAME"
    else
        log_warning "Log Analytics workspace already exists: $WORKSPACE_NAME"
    fi
    
    # Get workspace ID and key
    WORKSPACE_ID=$(az monitor log-analytics workspace show \
        --resource-group "$RESOURCE_GROUP" \
        --workspace-name "$WORKSPACE_NAME" \
        --query customerId --output tsv)
    
    WORKSPACE_KEY=$(az monitor log-analytics workspace get-shared-keys \
        --resource-group "$RESOURCE_GROUP" \
        --workspace-name "$WORKSPACE_NAME" \
        --query primarySharedKey --output tsv)
    
    export WORKSPACE_ID
    export WORKSPACE_KEY
    
    log_success "Foundation resources created successfully"
}

# Connect Kubernetes cluster to Azure Arc
connect_kubernetes_cluster() {
    if [[ "$SKIP_CLUSTER_CONNECT" == true ]]; then
        log_warning "Skipping Kubernetes cluster connection to Azure Arc"
        return 0
    fi
    
    log "Connecting Kubernetes cluster to Azure Arc..."
    
    if [[ "$DRY_RUN" == true ]]; then
        log "[DRY RUN] Would connect cluster $CLUSTER_NAME to Azure Arc"
        log "[DRY RUN] Would enable Azure Policy extension"
        log "[DRY RUN] Would enable Azure Monitor extension"
        return 0
    fi
    
    # Check if kubectl can connect to cluster
    if ! kubectl cluster-info &> /dev/null; then
        log_error "Cannot connect to Kubernetes cluster. Please ensure kubectl is configured."
        log_warning "Skipping Kubernetes cluster connection"
        return 0
    fi
    
    # Connect cluster to Azure Arc
    if ! az connectedk8s show --name "$CLUSTER_NAME" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        log "Connecting cluster to Azure Arc: $CLUSTER_NAME"
        az connectedk8s connect \
            --name "$CLUSTER_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --tags environment=onpremises type=kubernetes \
            --output none
        log_success "Kubernetes cluster connected to Azure Arc"
    else
        log_warning "Cluster already connected to Azure Arc: $CLUSTER_NAME"
    fi
    
    # Enable Azure Policy extension
    log "Enabling Azure Policy extension..."
    az k8s-extension create \
        --name azurepolicy \
        --cluster-name "$CLUSTER_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --cluster-type connectedClusters \
        --extension-type Microsoft.PolicyInsights \
        --output none || log_warning "Azure Policy extension may already be installed"
    
    # Enable Azure Monitor extension
    log "Enabling Azure Monitor extension..."
    az k8s-extension create \
        --name azuremonitor-containers \
        --cluster-name "$CLUSTER_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --cluster-type connectedClusters \
        --extension-type Microsoft.AzureMonitor.Containers \
        --configuration-settings logAnalyticsWorkspaceResourceID="/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.OperationalInsights/workspaces/${WORKSPACE_NAME}" \
        --output none || log_warning "Azure Monitor extension may already be installed"
    
    log_success "Kubernetes cluster extensions configured"
}

# Create service principal for server onboarding
create_service_principal() {
    log "Creating service principal for server onboarding..."
    
    if [[ "$DRY_RUN" == true ]]; then
        log "[DRY RUN] Would create service principal for server onboarding"
        return 0
    fi
    
    SP_NAME="sp-arc-onboarding-${RANDOM_SUFFIX}"
    
    # Check if service principal already exists
    if az ad sp list --display-name "$SP_NAME" --query "[0].appId" --output tsv | grep -q .; then
        log_warning "Service principal already exists: $SP_NAME"
        SP_ID=$(az ad sp list --display-name "$SP_NAME" --query "[0].appId" --output tsv)
    else
        log "Creating service principal: $SP_NAME"
        SP_CREDENTIALS=$(az ad sp create-for-rbac \
            --name "$SP_NAME" \
            --role "Azure Connected Machine Onboarding" \
            --scopes "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}" \
            --output json)
        
        SP_ID=$(echo "$SP_CREDENTIALS" | jq -r '.appId')
        SP_SECRET=$(echo "$SP_CREDENTIALS" | jq -r '.password')
        TENANT_ID=$(echo "$SP_CREDENTIALS" | jq -r '.tenant')
        
        log_success "Service principal created: $SP_NAME"
        log_warning "Store the following credentials securely:"
        log "Service Principal ID: $SP_ID"
        log "Service Principal Secret: $SP_SECRET"
        log "Tenant ID: $TENANT_ID"
    fi
    
    export SP_NAME
    export SP_ID
}

# Configure governance policies
configure_policies() {
    log "Configuring governance policies..."
    
    if [[ "$DRY_RUN" == true ]]; then
        log "[DRY RUN] Would assign security baseline policy for Arc-enabled servers"
        log "[DRY RUN] Would assign container security policy for Kubernetes"
        return 0
    fi
    
    # Assign built-in policy initiative for Arc-enabled servers
    log "Assigning security baseline policy for Arc-enabled servers..."
    az policy assignment create \
        --name "arc-servers-baseline" \
        --display-name "Security baseline for Arc-enabled servers" \
        --scope "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}" \
        --policy-set-definition "/providers/Microsoft.Authorization/policySetDefinitions/c96b2f5d-8c94-4588-bb6e-0e1295d5a6d4" \
        --location "$LOCATION" \
        --identity-scope "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}" \
        --role Contributor \
        --assign-identity SystemAssigned \
        --output none || log_warning "Policy assignment may already exist"
    
    # Assign Kubernetes policy for container security
    log "Assigning container security policy for Kubernetes..."
    az policy assignment create \
        --name "k8s-container-security" \
        --display-name "Kubernetes container security baseline" \
        --scope "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}" \
        --policy "/providers/Microsoft.Authorization/policyDefinitions/95edb821-ddaf-4404-9732-666045e056b4" \
        --params '{"effect":{"value":"audit"}}' \
        --output none || log_warning "Policy assignment may already exist"
    
    log_success "Governance policies configured"
}

# Create data collection rule for monitoring
create_monitoring_rule() {
    log "Creating monitoring data collection rule..."
    
    if [[ "$DRY_RUN" == true ]]; then
        log "[DRY RUN] Would create data collection rule for Arc-enabled servers"
        return 0
    fi
    
    DCR_NAME="dcr-arc-servers-${RANDOM_SUFFIX}"
    
    # Check if data collection rule already exists
    if az monitor data-collection rule show --name "$DCR_NAME" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        log_warning "Data collection rule already exists: $DCR_NAME"
        return 0
    fi
    
    # Create temporary file for DCR configuration
    DCR_CONFIG=$(mktemp)
    cat > "$DCR_CONFIG" << EOF
{
  "location": "${LOCATION}",
  "properties": {
    "destinations": {
      "logAnalytics": [{
        "workspaceResourceId": "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.OperationalInsights/workspaces/${WORKSPACE_NAME}",
        "name": "centralWorkspace"
      }]
    },
    "dataSources": {
      "performanceCounters": [{
        "streams": ["Microsoft-Perf"],
        "samplingFrequencyInSeconds": 60,
        "counterSpecifiers": [
          "\\\\Processor(_Total)\\\\% Processor Time",
          "\\\\Memory\\\\Available Bytes",
          "\\\\LogicalDisk(_Total)\\\\% Free Space"
        ],
        "name": "perfCounterDataSource"
      }]
    },
    "dataFlows": [{
      "streams": ["Microsoft-Perf"],
      "destinations": ["centralWorkspace"]
    }]
  }
}
EOF
    
    log "Creating data collection rule: $DCR_NAME"
    az monitor data-collection rule create \
        --name "$DCR_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --rule-file "$DCR_CONFIG" \
        --output none
    
    # Clean up temporary file
    rm -f "$DCR_CONFIG"
    
    log_success "Data collection rule created: $DCR_NAME"
}

# Create Resource Graph saved query
create_resource_graph_query() {
    log "Creating Resource Graph saved query..."
    
    if [[ "$DRY_RUN" == true ]]; then
        log "[DRY RUN] Would create Resource Graph saved query for compliance monitoring"
        return 0
    fi
    
    # Create saved query for compliance monitoring
    az graph shared-query create \
        --name "arc-compliance-status" \
        --resource-group "$RESOURCE_GROUP" \
        --description "Monitor compliance status of Arc-enabled resources" \
        --query "PolicyResources | where type =~ 'microsoft.policyinsights/policystates' | where properties.resourceType contains 'microsoft.hybridcompute' or properties.resourceType contains 'microsoft.kubernetes' | project resourceId=properties.resourceId, complianceState=properties.complianceState, policyDefinitionName=properties.policyDefinitionName, timestamp=properties.timestamp | order by timestamp desc" \
        --output none || log_warning "Saved query may already exist"
    
    log_success "Resource Graph saved query created"
}

# Display server onboarding instructions
display_onboarding_instructions() {
    log "Generating server onboarding instructions..."
    
    if [[ -z "$SP_ID" ]]; then
        log_warning "Service principal not available. Skipping onboarding instructions."
        return 0
    fi
    
    echo ""
    echo "=========================================="
    echo "SERVER ONBOARDING INSTRUCTIONS"
    echo "=========================================="
    echo ""
    echo "To connect servers to Azure Arc, run the following commands on each server:"
    echo ""
    echo "For Linux servers:"
    echo "wget https://aka.ms/azcmagent -O ~/install_linux_azcmagent.sh"
    echo "bash ~/install_linux_azcmagent.sh"
    echo "azcmagent connect \\"
    echo "    --service-principal-id '${SP_ID}' \\"
    echo "    --service-principal-secret '<SP_SECRET>' \\"
    echo "    --tenant-id '$(az account show --query tenantId --output tsv)' \\"
    echo "    --subscription-id '${SUBSCRIPTION_ID}' \\"
    echo "    --resource-group '${RESOURCE_GROUP}' \\"
    echo "    --location '${LOCATION}'"
    echo ""
    echo "For Windows servers:"
    echo "Invoke-WebRequest -Uri https://aka.ms/azcmagent -OutFile AzureConnectedMachineAgent.msi"
    echo "msiexec /i AzureConnectedMachineAgent.msi /l*v installationlog.txt /qn"
    echo "& \"C:\\Program Files\\AzureConnectedMachineAgent\\azcmagent.exe\" connect \\"
    echo "    --service-principal-id '${SP_ID}' \\"
    echo "    --service-principal-secret '<SP_SECRET>' \\"
    echo "    --tenant-id '$(az account show --query tenantId --output tsv)' \\"
    echo "    --subscription-id '${SUBSCRIPTION_ID}' \\"
    echo "    --resource-group '${RESOURCE_GROUP}' \\"
    echo "    --location '${LOCATION}'"
    echo ""
    echo "Replace <SP_SECRET> with the actual service principal secret."
    echo "=========================================="
}

# Main deployment function
main() {
    log "Starting Azure Arc and Azure Policy deployment..."
    
    check_prerequisites
    setup_environment
    create_foundation
    connect_kubernetes_cluster
    create_service_principal
    configure_policies
    create_monitoring_rule
    create_resource_graph_query
    display_onboarding_instructions
    
    if [[ "$DRY_RUN" == true ]]; then
        log_success "Dry run completed successfully. No resources were created."
    else
        log_success "Deployment completed successfully!"
        log "Resource Group: $RESOURCE_GROUP"
        log "Log Analytics Workspace: $WORKSPACE_NAME"
        if [[ "$SKIP_CLUSTER_CONNECT" == false ]]; then
            log "Arc-enabled Kubernetes Cluster: $CLUSTER_NAME"
        fi
        log "Service Principal: $SP_NAME"
        log ""
        log "Next steps:"
        log "1. Connect servers to Azure Arc using the instructions above"
        log "2. Monitor compliance in the Azure Portal"
        log "3. Configure additional policies as needed"
        log "4. Set up alerts and notifications"
    fi
}

# Run main function
main "$@"