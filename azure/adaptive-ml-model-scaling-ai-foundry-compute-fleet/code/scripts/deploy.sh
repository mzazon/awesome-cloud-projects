#!/bin/bash

# Adaptive ML Model Scaling with Azure AI Foundry and Compute Fleet
# Deployment Script
# 
# This script deploys the complete Azure AI Foundry and Compute Fleet solution
# for adaptive ML model scaling as described in the recipe.

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

# Error handling
error_exit() {
    log_error "$1"
    exit 1
}

# Cleanup function for failed deployments
cleanup_on_error() {
    local exit_code=$?
    if [ $exit_code -ne 0 ]; then
        log_error "Deployment failed with exit code $exit_code. Starting cleanup..."
        if [ "${CLEANUP_ON_ERROR:-true}" = "true" ]; then
            ./destroy.sh --force --no-confirm || true
        fi
    fi
    exit $exit_code
}

# Set trap for cleanup on error
trap cleanup_on_error EXIT

# Default values
DRY_RUN=false
SKIP_PREREQS=false
CLEANUP_ON_ERROR=true

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --skip-prereqs)
            SKIP_PREREQS=true
            shift
            ;;
        --no-cleanup-on-error)
            CLEANUP_ON_ERROR=false
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --dry-run                Show what would be deployed without making changes"
            echo "  --skip-prereqs          Skip prerequisite checks"
            echo "  --no-cleanup-on-error   Don't cleanup resources if deployment fails"
            echo "  --help, -h              Show this help message"
            echo ""
            echo "Environment Variables:"
            echo "  RESOURCE_GROUP          Azure resource group name (default: rg-ml-adaptive-scaling)"
            echo "  LOCATION                Azure region (default: eastus)"
            echo "  RANDOM_SUFFIX           Custom suffix for resource names"
            exit 0
            ;;
        *)
            error_exit "Unknown option: $1. Use --help for usage information."
            ;;
    esac
done

# Banner
echo "=================================================="
echo "Azure AI Foundry Adaptive ML Scaling Deployment"
echo "=================================================="
echo ""

if [ "$DRY_RUN" = true ]; then
    log_warning "DRY RUN MODE - No resources will be created"
    echo ""
fi

# Set environment variables with defaults
export RESOURCE_GROUP="${RESOURCE_GROUP:-rg-ml-adaptive-scaling}"
export LOCATION="${LOCATION:-eastus}"
export SUBSCRIPTION_ID=$(az account show --query id --output tsv 2>/dev/null || echo "")
export TENANT_ID=$(az account show --query tenantId --output tsv 2>/dev/null || echo "")

# Generate unique suffix if not provided
if [ -z "${RANDOM_SUFFIX:-}" ]; then
    export RANDOM_SUFFIX=$(openssl rand -hex 3)
fi

export AI_FOUNDRY_NAME="aif-adaptive-${RANDOM_SUFFIX}"
export COMPUTE_FLEET_NAME="cf-ml-scaling-${RANDOM_SUFFIX}"
export ML_WORKSPACE_NAME="mlw-scaling-${RANDOM_SUFFIX}"
export STORAGE_ACCOUNT_NAME="stmlscaling${RANDOM_SUFFIX}"
export KEY_VAULT_NAME="kv-ml-${RANDOM_SUFFIX}"
export LOG_ANALYTICS_NAME="law-ml-${RANDOM_SUFFIX}"

log_info "Deployment Configuration:"
log_info "  Resource Group: ${RESOURCE_GROUP}"
log_info "  Location: ${LOCATION}"
log_info "  Random Suffix: ${RANDOM_SUFFIX}"
log_info "  Subscription ID: ${SUBSCRIPTION_ID}"

# Prerequisites check
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        error_exit "Azure CLI is not installed. Please install it from https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
    fi
    
    # Check Azure CLI version
    local az_version=$(az version --query '"azure-cli"' -o tsv)
    log_info "Azure CLI version: ${az_version}"
    
    # Check if logged in to Azure
    if [ -z "$SUBSCRIPTION_ID" ]; then
        error_exit "Not logged in to Azure. Please run 'az login' first."
    fi
    
    # Check if jq is installed for JSON parsing
    if ! command -v jq &> /dev/null; then
        log_warning "jq is not installed. Some advanced features may not work properly."
    fi
    
    # Check if openssl is available for random generation
    if ! command -v openssl &> /dev/null; then
        log_warning "openssl is not available. Using alternative random generation."
        export RANDOM_SUFFIX=$(date +%s | tail -c 6)
    fi
    
    # Validate Azure subscription permissions
    log_info "Validating Azure permissions..."
    if ! az group list --query "[0].id" -o tsv &> /dev/null; then
        error_exit "Insufficient permissions to list resource groups. Please check your Azure permissions."
    fi
    
    # Check quota limits for compute resources
    log_info "Checking compute quotas in region ${LOCATION}..."
    local cores_available=$(az vm list-usage --location "$LOCATION" --query "[?name.value=='cores'].currentValue" -o tsv 2>/dev/null || echo "0")
    if [ "$cores_available" -gt 100 ]; then
        log_warning "High core usage detected (${cores_available}). Monitor quota limits during deployment."
    fi
    
    log_success "Prerequisites check completed"
}

# Register required resource providers
register_providers() {
    log_info "Registering required Azure resource providers..."
    
    local providers=(
        "Microsoft.MachineLearningServices"
        "Microsoft.Compute"
        "Microsoft.CognitiveServices"
        "Microsoft.OperationalInsights"
        "Microsoft.Storage"
        "Microsoft.KeyVault"
        "Microsoft.Insights"
    )
    
    for provider in "${providers[@]}"; do
        log_info "Registering provider: ${provider}"
        if [ "$DRY_RUN" = false ]; then
            az provider register --namespace "$provider" --wait || log_warning "Failed to register provider: ${provider}"
        fi
    done
    
    log_success "Resource providers registration completed"
}

# Create resource group
create_resource_group() {
    log_info "Creating resource group: ${RESOURCE_GROUP}"
    
    if [ "$DRY_RUN" = false ]; then
        az group create \
            --name "${RESOURCE_GROUP}" \
            --location "${LOCATION}" \
            --tags purpose=ml-scaling environment=demo deployment-script=true \
            || error_exit "Failed to create resource group"
    fi
    
    log_success "Resource group created: ${RESOURCE_GROUP}"
}

# Create storage account
create_storage_account() {
    log_info "Creating storage account: ${STORAGE_ACCOUNT_NAME}"
    
    if [ "$DRY_RUN" = false ]; then
        az storage account create \
            --resource-group "${RESOURCE_GROUP}" \
            --name "${STORAGE_ACCOUNT_NAME}" \
            --location "${LOCATION}" \
            --sku Standard_LRS \
            --kind StorageV2 \
            --access-tier Hot \
            --allow-blob-public-access false \
            --min-tls-version TLS1_2 \
            || error_exit "Failed to create storage account"
    fi
    
    log_success "Storage account created: ${STORAGE_ACCOUNT_NAME}"
}

# Create Key Vault
create_key_vault() {
    log_info "Creating Key Vault: ${KEY_VAULT_NAME}"
    
    if [ "$DRY_RUN" = false ]; then
        az keyvault create \
            --resource-group "${RESOURCE_GROUP}" \
            --name "${KEY_VAULT_NAME}" \
            --location "${LOCATION}" \
            --sku standard \
            --enable-soft-delete true \
            --retention-days 7 \
            || error_exit "Failed to create Key Vault"
    fi
    
    log_success "Key Vault created: ${KEY_VAULT_NAME}"
}

# Create Log Analytics workspace
create_log_analytics() {
    log_info "Creating Log Analytics workspace: ${LOG_ANALYTICS_NAME}"
    
    if [ "$DRY_RUN" = false ]; then
        az monitor log-analytics workspace create \
            --resource-group "${RESOURCE_GROUP}" \
            --workspace-name "${LOG_ANALYTICS_NAME}" \
            --location "${LOCATION}" \
            --sku pergb2018 \
            || error_exit "Failed to create Log Analytics workspace"
    fi
    
    log_success "Log Analytics workspace created: ${LOG_ANALYTICS_NAME}"
}

# Create AI Foundry Hub and Project
create_ai_foundry() {
    log_info "Creating AI Foundry Hub: ${AI_FOUNDRY_NAME}"
    
    if [ "$DRY_RUN" = false ]; then
        # Create AI Foundry hub
        az ml workspace create \
            --resource-group "${RESOURCE_GROUP}" \
            --name "${AI_FOUNDRY_NAME}" \
            --location "${LOCATION}" \
            --kind Hub \
            --description "AI Foundry Hub for ML Scaling" \
            --storage-account "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.Storage/storageAccounts/${STORAGE_ACCOUNT_NAME}" \
            --key-vault "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.KeyVault/vaults/${KEY_VAULT_NAME}" \
            || error_exit "Failed to create AI Foundry hub"
        
        # Create project within the hub
        az ml workspace create \
            --resource-group "${RESOURCE_GROUP}" \
            --name "project-${AI_FOUNDRY_NAME}" \
            --location "${LOCATION}" \
            --kind Project \
            --hub-id "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.MachineLearningServices/workspaces/${AI_FOUNDRY_NAME}" \
            || error_exit "Failed to create AI Foundry project"
    fi
    
    log_success "AI Foundry hub and project created"
}

# Create Machine Learning workspace
create_ml_workspace() {
    log_info "Creating ML workspace: ${ML_WORKSPACE_NAME}"
    
    if [ "$DRY_RUN" = false ]; then
        az ml workspace create \
            --resource-group "${RESOURCE_GROUP}" \
            --name "${ML_WORKSPACE_NAME}" \
            --location "${LOCATION}" \
            --storage-account "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.Storage/storageAccounts/${STORAGE_ACCOUNT_NAME}" \
            --key-vault "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.KeyVault/vaults/${KEY_VAULT_NAME}" \
            || error_exit "Failed to create ML workspace"
    fi
    
    log_success "ML workspace created: ${ML_WORKSPACE_NAME}"
}

# Create Compute Fleet
create_compute_fleet() {
    log_info "Creating Compute Fleet: ${COMPUTE_FLEET_NAME}"
    
    if [ "$DRY_RUN" = false ]; then
        # Create VM sizes profile configuration
        cat > vm-sizes-profile.json << 'EOF'
[
  {
    "name": "Standard_D4s_v3",
    "rank": 1
  },
  {
    "name": "Standard_D8s_v3", 
    "rank": 2
  },
  {
    "name": "Standard_E4s_v3",
    "rank": 3
  }
]
EOF
        
        az vm fleet create \
            --resource-group "${RESOURCE_GROUP}" \
            --name "${COMPUTE_FLEET_NAME}" \
            --location "${LOCATION}" \
            --vm-sizes-profile @vm-sizes-profile.json \
            --spot-priority-profile '{
              "capacity": 20,
              "minCapacity": 5,
              "maxPricePerVM": 0.10,
              "evictionPolicy": "Deallocate",
              "allocationStrategy": "PriceCapacityOptimized"
            }' \
            --regular-priority-profile '{
              "capacity": 10,
              "minCapacity": 2,
              "allocationStrategy": "LowestPrice"
            }' \
            || error_exit "Failed to create Compute Fleet"
        
        # Clean up temporary file
        rm -f vm-sizes-profile.json
    fi
    
    log_success "Compute Fleet created: ${COMPUTE_FLEET_NAME}"
}

# Deploy AI agents
deploy_ai_agents() {
    log_info "Deploying AI Foundry agents..."
    
    if [ "$DRY_RUN" = false ]; then
        # Create main scaling agent configuration
        cat > agent-config.json << EOF
{
  "name": "ml-scaling-agent",
  "description": "Intelligent ML compute scaling orchestrator",
  "model": {
    "type": "gpt-4",
    "version": "2024-02-01",
    "parameters": {
      "temperature": 0.3,
      "maxTokens": 2000
    }
  },
  "instructions": "You are an expert ML infrastructure agent responsible for optimizing compute resource allocation. Monitor workload metrics, analyze capacity requirements, and make scaling decisions to maintain performance while minimizing costs. Always consider spot instance availability and pricing trends.",
  "tools": [
    {
      "type": "azure_monitor",
      "name": "workload_monitor",
      "configuration": {
        "workspace_id": "${LOG_ANALYTICS_NAME}",
        "metrics": ["cpu_utilization", "memory_usage", "queue_depth", "inference_latency"]
      }
    },
    {
      "type": "compute_fleet",
      "name": "fleet_manager",
      "configuration": {
        "fleet_id": "${COMPUTE_FLEET_NAME}",
        "scaling_policies": {
          "scale_up_threshold": 0.75,
          "scale_down_threshold": 0.25,
          "cooldown_period": 300
        }
      }
    }
  ]
}
EOF
        
        # Deploy main scaling agent
        az ml agent create \
            --resource-group "${RESOURCE_GROUP}" \
            --workspace-name "${AI_FOUNDRY_NAME}" \
            --name ml-scaling-agent \
            --file agent-config.json \
            || error_exit "Failed to create main scaling agent"
        
        # Create cost optimizer agent
        cat > cost-optimizer-agent.json << EOF
{
  "name": "cost-optimizer",
  "description": "Specialized agent for ML cost optimization",
  "model": {
    "type": "gpt-4",
    "version": "2024-02-01"
  },
  "instructions": "You are a cost optimization specialist for ML infrastructure. Analyze pricing patterns, spot instance availability, and resource utilization to recommend the most cost-effective compute configurations. Always balance cost savings with performance requirements.",
  "tools": [
    {
      "type": "azure_pricing",
      "name": "pricing_analyzer"
    },
    {
      "type": "azure_advisor",
      "name": "cost_recommendations"
    }
  ]
}
EOF
        
        # Deploy cost optimizer agent
        az ml agent create \
            --resource-group "${RESOURCE_GROUP}" \
            --workspace-name "${AI_FOUNDRY_NAME}" \
            --name cost-optimizer \
            --file cost-optimizer-agent.json \
            || log_warning "Failed to create cost optimizer agent"
        
        # Create performance monitor agent
        cat > performance-monitor-agent.json << EOF
{
  "name": "performance-monitor",
  "description": "Specialized agent for ML performance monitoring",
  "model": {
    "type": "gpt-4",
    "version": "2024-02-01"
  },
  "instructions": "You are a performance monitoring specialist for ML workloads. Track model training times, inference latency, and resource utilization to ensure SLA compliance. Identify performance bottlenecks and recommend optimization strategies.",
  "tools": [
    {
      "type": "azure_monitor",
      "name": "performance_metrics"
    },
    {
      "type": "application_insights",
      "name": "ml_telemetry"
    }
  ]
}
EOF
        
        # Deploy performance monitor agent
        az ml agent create \
            --resource-group "${RESOURCE_GROUP}" \
            --workspace-name "${AI_FOUNDRY_NAME}" \
            --name performance-monitor \
            --file performance-monitor-agent.json \
            || log_warning "Failed to create performance monitor agent"
        
        # Clean up temporary files
        rm -f agent-config.json cost-optimizer-agent.json performance-monitor-agent.json
    fi
    
    log_success "AI agents deployed successfully"
}

# Configure monitoring and alerting
configure_monitoring() {
    log_info "Configuring monitoring and alerting..."
    
    if [ "$DRY_RUN" = false ]; then
        # Create custom workbook for scaling metrics
        cat > scaling-workbook.json << 'EOF'
{
  "version": "Notebook/1.0",
  "items": [
    {
      "type": 9,
      "content": {
        "version": "KqlParameterItem/1.0",
        "parameters": [
          {
            "id": "timeRange",
            "version": "KqlParameterItem/1.0",
            "name": "TimeRange",
            "type": 4,
            "value": {
              "durationMs": 3600000
            }
          }
        ]
      }
    },
    {
      "type": 3,
      "content": {
        "version": "KqlItem/1.0",
        "query": "AzureMetrics\n| where ResourceProvider == \"MICROSOFT.MACHINELEARNINGSERVICES\"\n| where MetricName in (\"CpuUtilization\", \"MemoryUtilization\")\n| summarize avg(Average) by bin(TimeGenerated, 5m), MetricName\n| render timechart",
        "size": 0,
        "title": "ML Compute Utilization",
        "timeContext": {
          "durationMs": 3600000
        }
      }
    }
  ]
}
EOF
        
        # Deploy monitoring workbook
        az monitor workbook create \
            --resource-group "${RESOURCE_GROUP}" \
            --name "ML-Scaling-Dashboard" \
            --display-name "ML Adaptive Scaling Dashboard" \
            --description "Comprehensive monitoring for ML compute scaling" \
            --template-data @scaling-workbook.json \
            || log_warning "Failed to create monitoring workbook"
        
        # Clean up temporary file
        rm -f scaling-workbook.json
    fi
    
    log_success "Monitoring and alerting configured"
}

# Verify deployment
verify_deployment() {
    log_info "Verifying deployment..."
    
    if [ "$DRY_RUN" = false ]; then
        # Check resource group
        if ! az group show --name "${RESOURCE_GROUP}" &> /dev/null; then
            error_exit "Resource group verification failed"
        fi
        
        # Check AI Foundry hub
        if ! az ml workspace show --resource-group "${RESOURCE_GROUP}" --name "${AI_FOUNDRY_NAME}" &> /dev/null; then
            error_exit "AI Foundry hub verification failed"
        fi
        
        # Check ML workspace
        if ! az ml workspace show --resource-group "${RESOURCE_GROUP}" --name "${ML_WORKSPACE_NAME}" &> /dev/null; then
            error_exit "ML workspace verification failed"
        fi
        
        # Check Compute Fleet
        if ! az vm fleet show --resource-group "${RESOURCE_GROUP}" --name "${COMPUTE_FLEET_NAME}" &> /dev/null; then
            error_exit "Compute Fleet verification failed"
        fi
        
        log_success "All core resources verified successfully"
    fi
}

# Main deployment function
main() {
    log_info "Starting Azure AI Foundry Adaptive ML Scaling deployment..."
    
    # Run prerequisite checks
    if [ "$SKIP_PREREQS" = false ]; then
        check_prerequisites
    fi
    
    # Register providers
    register_providers
    
    # Create foundational resources
    create_resource_group
    create_storage_account
    create_key_vault
    create_log_analytics
    
    # Create AI and ML resources
    create_ai_foundry
    create_ml_workspace
    create_compute_fleet
    
    # Deploy agents and configure monitoring
    deploy_ai_agents
    configure_monitoring
    
    # Verify deployment
    verify_deployment
    
    # Deployment summary
    echo ""
    echo "=================================================="
    log_success "Deployment completed successfully!"
    echo "=================================================="
    echo ""
    log_info "Deployment Summary:"
    log_info "  Resource Group: ${RESOURCE_GROUP}"
    log_info "  AI Foundry Hub: ${AI_FOUNDRY_NAME}"
    log_info "  ML Workspace: ${ML_WORKSPACE_NAME}"
    log_info "  Compute Fleet: ${COMPUTE_FLEET_NAME}"
    log_info "  Storage Account: ${STORAGE_ACCOUNT_NAME}"
    log_info "  Key Vault: ${KEY_VAULT_NAME}"
    log_info "  Log Analytics: ${LOG_ANALYTICS_NAME}"
    echo ""
    log_info "Next Steps:"
    log_info "1. Access AI Foundry at: https://ml.azure.com"
    log_info "2. Review the monitoring dashboard in Azure Monitor"
    log_info "3. Test the scaling agents with sample ML workloads"
    log_info "4. Monitor costs and resource utilization"
    echo ""
    log_warning "Remember to run './destroy.sh' when finished to avoid ongoing charges"
    
    # Disable trap since deployment succeeded
    trap - EXIT
}

# Run main function
main "$@"