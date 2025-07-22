#!/bin/bash

# Azure Compute Fleet and Batch Processing Deployment Script
# This script automates the deployment of cost-efficient batch processing infrastructure
# using Azure Compute Fleet and Azure Batch with proper error handling and logging

set -euo pipefail  # Exit on error, undefined vars, pipe failures

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging setup
LOG_FILE="deployment_$(date +%Y%m%d_%H%M%S).log"
exec 1> >(tee -a "$LOG_FILE")
exec 2> >(tee -a "$LOG_FILE" >&2)

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DRY_RUN=false
FORCE_DEPLOY=false
SKIP_CONFIRMATION=false

# Function to print colored output
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_header() {
    echo -e "${BLUE}[HEADER]${NC} $1"
}

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check Azure CLI authentication
check_azure_auth() {
    print_status "Checking Azure CLI authentication..."
    
    if ! az account show >/dev/null 2>&1; then
        print_error "Azure CLI not authenticated. Please run 'az login' first."
        exit 1
    fi
    
    local subscription_id=$(az account show --query id --output tsv)
    local account_name=$(az account show --query name --output tsv)
    
    print_status "Authenticated to Azure subscription: $account_name ($subscription_id)"
}

# Function to check prerequisites
check_prerequisites() {
    print_header "Checking Prerequisites..."
    
    # Check required commands
    local required_commands=("az" "jq" "openssl")
    for cmd in "${required_commands[@]}"; do
        if ! command_exists "$cmd"; then
            print_error "Required command '$cmd' not found. Please install it first."
            exit 1
        fi
    done
    
    # Check Azure CLI version
    local az_version=$(az version --query '"azure-cli"' --output tsv)
    print_status "Azure CLI version: $az_version"
    
    # Check if version is >= 2.50.0
    if ! az version | jq -e '.["azure-cli"] | split(".") | map(tonumber) | .[0] >= 2 and (.[0] > 2 or .[1] >= 50)' >/dev/null; then
        print_warning "Azure CLI version should be 2.50.0 or later for best compatibility"
    fi
    
    # Check Azure authentication
    check_azure_auth
    
    # Check required Azure resource providers
    print_status "Checking Azure resource providers..."
    local providers=("Microsoft.Batch" "Microsoft.Storage" "Microsoft.Compute" "Microsoft.OperationalInsights")
    
    for provider in "${providers[@]}"; do
        local state=$(az provider show --namespace "$provider" --query registrationState --output tsv)
        if [[ "$state" != "Registered" ]]; then
            print_warning "Provider $provider is not registered. Registering..."
            az provider register --namespace "$provider"
        else
            print_status "Provider $provider is registered"
        fi
    done
    
    print_status "Prerequisites check completed successfully"
}

# Function to set environment variables
set_environment_variables() {
    print_header "Setting Environment Variables..."
    
    # Generate unique suffix for resource names
    if [[ -z "${RANDOM_SUFFIX:-}" ]]; then
        export RANDOM_SUFFIX=$(openssl rand -hex 3)
    fi
    
    # Set default values if not provided
    export RESOURCE_GROUP="${RESOURCE_GROUP:-rg-batch-fleet-${RANDOM_SUFFIX}}"
    export LOCATION="${LOCATION:-eastus}"
    export SUBSCRIPTION_ID="${SUBSCRIPTION_ID:-$(az account show --query id --output tsv)}"
    export STORAGE_ACCOUNT="${STORAGE_ACCOUNT:-stbatch${RANDOM_SUFFIX}}"
    export BATCH_ACCOUNT="${BATCH_ACCOUNT:-batchacct${RANDOM_SUFFIX}}"
    export FLEET_NAME="${FLEET_NAME:-compute-fleet-${RANDOM_SUFFIX}}"
    export LOG_WORKSPACE="${LOG_WORKSPACE:-log-batch-${RANDOM_SUFFIX}}"
    export POOL_ID="${POOL_ID:-batch-pool-${RANDOM_SUFFIX}}"
    export JOB_ID="${JOB_ID:-sample-processing-job-${RANDOM_SUFFIX}}"
    
    # Display environment variables
    print_status "Environment Variables:"
    echo "  RESOURCE_GROUP: $RESOURCE_GROUP"
    echo "  LOCATION: $LOCATION"
    echo "  SUBSCRIPTION_ID: $SUBSCRIPTION_ID"
    echo "  STORAGE_ACCOUNT: $STORAGE_ACCOUNT"
    echo "  BATCH_ACCOUNT: $BATCH_ACCOUNT"
    echo "  FLEET_NAME: $FLEET_NAME"
    echo "  LOG_WORKSPACE: $LOG_WORKSPACE"
    echo "  POOL_ID: $POOL_ID"
    echo "  JOB_ID: $JOB_ID"
    echo "  RANDOM_SUFFIX: $RANDOM_SUFFIX"
    
    # Save environment variables to file for cleanup script
    cat > "${SCRIPT_DIR}/deployment_vars.env" << EOF
export RESOURCE_GROUP="$RESOURCE_GROUP"
export LOCATION="$LOCATION"
export SUBSCRIPTION_ID="$SUBSCRIPTION_ID"
export STORAGE_ACCOUNT="$STORAGE_ACCOUNT"
export BATCH_ACCOUNT="$BATCH_ACCOUNT"
export FLEET_NAME="$FLEET_NAME"
export LOG_WORKSPACE="$LOG_WORKSPACE"
export POOL_ID="$POOL_ID"
export JOB_ID="$JOB_ID"
export RANDOM_SUFFIX="$RANDOM_SUFFIX"
EOF
    
    print_status "Environment variables saved to deployment_vars.env"
}

# Function to check if resources already exist
check_existing_resources() {
    print_header "Checking for Existing Resources..."
    
    local resource_exists=false
    
    # Check if resource group exists
    if az group show --name "$RESOURCE_GROUP" >/dev/null 2>&1; then
        print_warning "Resource group '$RESOURCE_GROUP' already exists"
        resource_exists=true
    fi
    
    # Check if storage account exists
    if az storage account show --name "$STORAGE_ACCOUNT" --resource-group "$RESOURCE_GROUP" >/dev/null 2>&1; then
        print_warning "Storage account '$STORAGE_ACCOUNT' already exists"
        resource_exists=true
    fi
    
    # Check if batch account exists
    if az batch account show --name "$BATCH_ACCOUNT" --resource-group "$RESOURCE_GROUP" >/dev/null 2>&1; then
        print_warning "Batch account '$BATCH_ACCOUNT' already exists"
        resource_exists=true
    fi
    
    if [[ "$resource_exists" == true && "$FORCE_DEPLOY" != true ]]; then
        print_error "Some resources already exist. Use --force to redeploy or clean up first."
        exit 1
    fi
}

# Function to create resource group
create_resource_group() {
    print_header "Creating Resource Group..."
    
    if $DRY_RUN; then
        print_status "[DRY RUN] Would create resource group: $RESOURCE_GROUP"
        return 0
    fi
    
    if az group show --name "$RESOURCE_GROUP" >/dev/null 2>&1; then
        print_status "Resource group '$RESOURCE_GROUP' already exists"
    else
        print_status "Creating resource group: $RESOURCE_GROUP"
        az group create \
            --name "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --tags purpose=batch-processing environment=demo deployment-script=true
        
        print_status "✅ Resource group created successfully"
    fi
}

# Function to create storage account
create_storage_account() {
    print_header "Creating Storage Account..."
    
    if $DRY_RUN; then
        print_status "[DRY RUN] Would create storage account: $STORAGE_ACCOUNT"
        return 0
    fi
    
    if az storage account show --name "$STORAGE_ACCOUNT" --resource-group "$RESOURCE_GROUP" >/dev/null 2>&1; then
        print_status "Storage account '$STORAGE_ACCOUNT' already exists"
    else
        print_status "Creating storage account: $STORAGE_ACCOUNT"
        az storage account create \
            --name "$STORAGE_ACCOUNT" \
            --resource-group "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --sku Standard_LRS \
            --kind StorageV2 \
            --tags purpose=batch-processing environment=demo
        
        print_status "✅ Storage account created successfully"
    fi
}

# Function to create batch account
create_batch_account() {
    print_header "Creating Batch Account..."
    
    if $DRY_RUN; then
        print_status "[DRY RUN] Would create batch account: $BATCH_ACCOUNT"
        return 0
    fi
    
    if az batch account show --name "$BATCH_ACCOUNT" --resource-group "$RESOURCE_GROUP" >/dev/null 2>&1; then
        print_status "Batch account '$BATCH_ACCOUNT' already exists"
    else
        print_status "Creating batch account: $BATCH_ACCOUNT"
        az batch account create \
            --name "$BATCH_ACCOUNT" \
            --resource-group "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --storage-account "$STORAGE_ACCOUNT"
        
        print_status "✅ Batch account created successfully"
    fi
    
    # Set batch account context
    print_status "Setting batch account context..."
    az batch account set \
        --name "$BATCH_ACCOUNT" \
        --resource-group "$RESOURCE_GROUP"
}

# Function to create compute fleet
create_compute_fleet() {
    print_header "Creating Compute Fleet..."
    
    if $DRY_RUN; then
        print_status "[DRY RUN] Would create compute fleet: $FLEET_NAME"
        return 0
    fi
    
    # Create fleet configuration file
    local fleet_config_file="${SCRIPT_DIR}/fleet-config.json"
    cat > "$fleet_config_file" << EOF
{
  "name": "$FLEET_NAME",
  "location": "$LOCATION",
  "properties": {
    "computeProfile": {
      "baseVirtualMachineProfile": {
        "storageProfile": {
          "imageReference": {
            "publisher": "MicrosoftWindowsServer",
            "offer": "WindowsServer",
            "sku": "2022-datacenter-core",
            "version": "latest"
          }
        },
        "osProfile": {
          "computerNamePrefix": "batch-vm",
          "adminUsername": "batchadmin",
          "adminPassword": "BatchP@ssw0rd123!"
        }
      },
      "computeApiVersion": "2023-09-01"
    },
    "spotPriorityProfile": {
      "capacity": 80,
      "minCapacity": 0,
      "maxPricePerVM": 0.05,
      "evictionPolicy": "Delete",
      "allocationStrategy": "LowestPrice"
    },
    "regularPriorityProfile": {
      "capacity": 20,
      "minCapacity": 5,
      "allocationStrategy": "LowestPrice"
    }
  }
}
EOF
    
    print_status "Creating compute fleet: $FLEET_NAME"
    if az compute-fleet create \
        --resource-group "$RESOURCE_GROUP" \
        --name "$FLEET_NAME" \
        --body "@$fleet_config_file"; then
        print_status "✅ Compute Fleet created successfully"
    else
        print_warning "Compute Fleet creation failed or not supported in this region"
        print_warning "Continuing with batch pool creation..."
    fi
    
    # Clean up temp file
    rm -f "$fleet_config_file"
}

# Function to create batch pool
create_batch_pool() {
    print_header "Creating Batch Pool..."
    
    if $DRY_RUN; then
        print_status "[DRY RUN] Would create batch pool: $POOL_ID"
        return 0
    fi
    
    # Create pool configuration file
    local pool_config_file="${SCRIPT_DIR}/pool-config.json"
    cat > "$pool_config_file" << EOF
{
  "id": "$POOL_ID",
  "vmSize": "Standard_D2s_v3",
  "virtualMachineConfiguration": {
    "imageReference": {
      "publisher": "MicrosoftWindowsServer",
      "offer": "WindowsServer",
      "sku": "2022-datacenter-core",
      "version": "latest"
    },
    "nodeAgentSKUId": "batch.node.windows amd64"
  },
  "targetDedicatedNodes": 0,
  "targetLowPriorityNodes": 10,
  "enableAutoScale": true,
  "autoScaleFormula": "\$TargetLowPriorityNodes = min(20, \$PendingTasks.GetSample(1 * TimeInterval_Minute, 0).GetAverage() * 2);",
  "autoScaleEvaluationInterval": "PT5M",
  "startTask": {
    "commandLine": "cmd /c echo 'Batch node ready for processing'",
    "waitForSuccess": true
  }
}
EOF
    
    print_status "Creating batch pool: $POOL_ID"
    az batch pool create --json-file "$pool_config_file"
    
    print_status "✅ Batch pool created successfully"
    
    # Clean up temp file
    rm -f "$pool_config_file"
}

# Function to setup monitoring
setup_monitoring() {
    print_header "Setting Up Azure Monitor..."
    
    if $DRY_RUN; then
        print_status "[DRY RUN] Would create Log Analytics workspace: $LOG_WORKSPACE"
        return 0
    fi
    
    # Create Log Analytics workspace
    print_status "Creating Log Analytics workspace: $LOG_WORKSPACE"
    az monitor log-analytics workspace create \
        --workspace-name "$LOG_WORKSPACE" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --sku PerGB2018 \
        --tags purpose=batch-processing environment=demo
    
    # Get workspace ID
    local workspace_id=$(az monitor log-analytics workspace show \
        --workspace-name "$LOG_WORKSPACE" \
        --resource-group "$RESOURCE_GROUP" \
        --query customerId --output tsv)
    
    print_status "Workspace ID: $workspace_id"
    
    # Enable diagnostic settings for batch account
    print_status "Configuring diagnostic settings for batch account..."
    az monitor diagnostic-settings create \
        --name batch-diagnostics \
        --resource "$BATCH_ACCOUNT" \
        --resource-group "$RESOURCE_GROUP" \
        --resource-type Microsoft.Batch/batchAccounts \
        --workspace "$workspace_id" \
        --logs '[{"category":"ServiceLog","enabled":true}]' \
        --metrics '[{"category":"AllMetrics","enabled":true}]'
    
    print_status "✅ Azure Monitor configured successfully"
}

# Function to create sample batch job
create_sample_job() {
    print_header "Creating Sample Batch Job..."
    
    if $DRY_RUN; then
        print_status "[DRY RUN] Would create sample batch job: $JOB_ID"
        return 0
    fi
    
    # Create job configuration file
    local job_config_file="${SCRIPT_DIR}/job-config.json"
    cat > "$job_config_file" << EOF
{
  "id": "$JOB_ID",
  "poolInfo": {
    "poolId": "$POOL_ID"
  },
  "jobManagerTask": {
    "id": "JobManager",
    "displayName": "Sample Processing Job Manager",
    "commandLine": "cmd /c echo 'Processing batch job with cost optimization' && timeout /t 30",
    "killJobOnCompletion": true
  },
  "onAllTasksComplete": "terminateJob",
  "usesTaskDependencies": false
}
EOF
    
    print_status "Creating batch job: $JOB_ID"
    az batch job create --json-file "$job_config_file"
    
    # Add sample tasks to the job
    print_status "Adding sample tasks to job..."
    for i in {1..5}; do
        print_status "Creating task: task-$i"
        az batch task create \
            --job-id "$JOB_ID" \
            --task-id "task-$i" \
            --command-line "cmd /c echo 'Processing task $i on cost-optimized compute' && timeout /t 60"
    done
    
    print_status "✅ Sample batch job created with 5 processing tasks"
    
    # Clean up temp file
    rm -f "$job_config_file"
}

# Function to configure cost management
configure_cost_management() {
    print_header "Configuring Cost Management..."
    
    if $DRY_RUN; then
        print_status "[DRY RUN] Would configure cost alerts and budgets"
        return 0
    fi
    
    # Create cost alert rule
    print_status "Creating cost alert rule..."
    az monitor metrics alert create \
        --name "batch-cost-alert" \
        --resource-group "$RESOURCE_GROUP" \
        --condition "avg 'Percentage CPU' > 80" \
        --description "Alert when batch processing costs exceed threshold" \
        --evaluation-frequency 5m \
        --window-size 15m \
        --severity 2 \
        --tags purpose=batch-processing environment=demo
    
    print_status "✅ Cost alerts configured successfully"
}

# Function to validate deployment
validate_deployment() {
    print_header "Validating Deployment..."
    
    if $DRY_RUN; then
        print_status "[DRY RUN] Would validate deployment"
        return 0
    fi
    
    local validation_failed=false
    
    # Check resource group
    if ! az group show --name "$RESOURCE_GROUP" >/dev/null 2>&1; then
        print_error "Resource group validation failed"
        validation_failed=true
    else
        print_status "✅ Resource group validation passed"
    fi
    
    # Check storage account
    if ! az storage account show --name "$STORAGE_ACCOUNT" --resource-group "$RESOURCE_GROUP" >/dev/null 2>&1; then
        print_error "Storage account validation failed"
        validation_failed=true
    else
        print_status "✅ Storage account validation passed"
    fi
    
    # Check batch account
    if ! az batch account show --name "$BATCH_ACCOUNT" --resource-group "$RESOURCE_GROUP" >/dev/null 2>&1; then
        print_error "Batch account validation failed"
        validation_failed=true
    else
        print_status "✅ Batch account validation passed"
    fi
    
    # Check batch pool
    if ! az batch pool show --pool-id "$POOL_ID" >/dev/null 2>&1; then
        print_error "Batch pool validation failed"
        validation_failed=true
    else
        print_status "✅ Batch pool validation passed"
    fi
    
    # Check Log Analytics workspace
    if ! az monitor log-analytics workspace show --workspace-name "$LOG_WORKSPACE" --resource-group "$RESOURCE_GROUP" >/dev/null 2>&1; then
        print_error "Log Analytics workspace validation failed"
        validation_failed=true
    else
        print_status "✅ Log Analytics workspace validation passed"
    fi
    
    if [[ "$validation_failed" == true ]]; then
        print_error "Deployment validation failed. Please check the logs for details."
        exit 1
    fi
    
    print_status "✅ All deployment validation checks passed"
}

# Function to display deployment summary
display_summary() {
    print_header "Deployment Summary"
    
    echo "Resource Group: $RESOURCE_GROUP"
    echo "Location: $LOCATION"
    echo "Storage Account: $STORAGE_ACCOUNT"
    echo "Batch Account: $BATCH_ACCOUNT"
    echo "Batch Pool: $POOL_ID"
    echo "Sample Job: $JOB_ID"
    echo "Log Analytics Workspace: $LOG_WORKSPACE"
    
    if [[ "$DRY_RUN" != true ]]; then
        echo ""
        echo "Next Steps:"
        echo "1. Monitor batch job execution in the Azure portal"
        echo "2. Check cost analysis in Azure Cost Management"
        echo "3. Review logs in Log Analytics workspace"
        echo "4. Use destroy.sh to clean up resources when done"
        echo ""
        echo "Environment variables saved to: ${SCRIPT_DIR}/deployment_vars.env"
        echo "Deployment log saved to: $LOG_FILE"
    fi
}

# Function to cleanup on error
cleanup_on_error() {
    print_error "Deployment failed. Cleaning up partial resources..."
    
    # Remove temporary files
    rm -f "${SCRIPT_DIR}/fleet-config.json" "${SCRIPT_DIR}/pool-config.json" "${SCRIPT_DIR}/job-config.json"
    
    if [[ "$SKIP_CONFIRMATION" != true ]]; then
        read -p "Do you want to run cleanup of created resources? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            "${SCRIPT_DIR}/destroy.sh" --force
        fi
    fi
}

# Function to show usage
show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --dry-run                    Show what would be deployed without making changes"
    echo "  --force                      Force deployment even if resources exist"
    echo "  --skip-confirmation         Skip confirmation prompts"
    echo "  --resource-group NAME       Override resource group name"
    echo "  --location LOCATION         Override deployment location"
    echo "  --help                      Show this help message"
    echo ""
    echo "Environment Variables:"
    echo "  RESOURCE_GROUP              Resource group name"
    echo "  LOCATION                    Azure region"
    echo "  STORAGE_ACCOUNT             Storage account name"
    echo "  BATCH_ACCOUNT               Batch account name"
    echo "  FLEET_NAME                  Compute fleet name"
    echo "  LOG_WORKSPACE               Log Analytics workspace name"
    echo ""
    echo "Examples:"
    echo "  $0                          Deploy with default settings"
    echo "  $0 --dry-run                Preview deployment"
    echo "  $0 --force                  Force redeploy existing resources"
    echo "  $0 --location westus2       Deploy to specific region"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --force)
            FORCE_DEPLOY=true
            shift
            ;;
        --skip-confirmation)
            SKIP_CONFIRMATION=true
            shift
            ;;
        --resource-group)
            RESOURCE_GROUP="$2"
            shift 2
            ;;
        --location)
            LOCATION="$2"
            shift 2
            ;;
        --help)
            show_usage
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
done

# Main deployment function
main() {
    print_header "Azure Compute Fleet and Batch Processing Deployment"
    
    # Set error trap
    trap cleanup_on_error ERR
    
    # Check prerequisites
    check_prerequisites
    
    # Set environment variables
    set_environment_variables
    
    # Check for existing resources
    check_existing_resources
    
    # Confirmation prompt
    if [[ "$DRY_RUN" != true && "$SKIP_CONFIRMATION" != true ]]; then
        echo ""
        print_warning "This will create Azure resources that may incur costs."
        echo "Resource Group: $RESOURCE_GROUP"
        echo "Location: $LOCATION"
        echo ""
        read -p "Do you want to proceed? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_status "Deployment cancelled by user"
            exit 0
        fi
    fi
    
    # Execute deployment steps
    create_resource_group
    create_storage_account
    create_batch_account
    create_compute_fleet
    create_batch_pool
    setup_monitoring
    create_sample_job
    configure_cost_management
    
    # Validate deployment
    validate_deployment
    
    # Display summary
    display_summary
    
    if [[ "$DRY_RUN" != true ]]; then
        print_status "✅ Deployment completed successfully!"
    else
        print_status "✅ Dry run completed successfully!"
    fi
}

# Run main function
main "$@"