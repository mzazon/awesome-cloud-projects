#!/bin/bash

#
# deploy.sh - Deploy Azure Virtual Desktop Cost Optimization Infrastructure
#
# This script deploys the complete Azure Virtual Desktop cost optimization solution
# including AVD workspaces, host pools, VM scale sets, auto-scaling, cost management,
# and automation components.
#
# Usage: ./deploy.sh [--dry-run] [--debug]
#

set -e  # Exit on any error
set -o pipefail  # Exit on pipe failures

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/deploy.log"
DEBUG_MODE=false
DRY_RUN=false

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
        INFO)  echo -e "${GREEN}[INFO]${NC} $message" | tee -a "$LOG_FILE" ;;
        WARN)  echo -e "${YELLOW}[WARN]${NC} $message" | tee -a "$LOG_FILE" ;;
        ERROR) echo -e "${RED}[ERROR]${NC} $message" | tee -a "$LOG_FILE" ;;
        DEBUG) if $DEBUG_MODE; then echo -e "${BLUE}[DEBUG]${NC} $message" | tee -a "$LOG_FILE"; fi ;;
    esac
    
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
}

# Function to check prerequisites
check_prerequisites() {
    log INFO "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        log ERROR "Azure CLI is not installed. Please install it from https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
        exit 1
    fi
    
    # Check Azure CLI version (minimum 2.50)
    local az_version=$(az --version | head -n1 | grep -oE '[0-9]+\.[0-9]+' | head -n1)
    local major_version=$(echo $az_version | cut -d. -f1)
    local minor_version=$(echo $az_version | cut -d. -f2)
    
    if [ "$major_version" -lt 2 ] || ([ "$major_version" -eq 2 ] && [ "$minor_version" -lt 50 ]); then
        log ERROR "Azure CLI version $az_version is too old. Please upgrade to version 2.50 or later."
        exit 1
    fi
    
    log INFO "Azure CLI version $az_version is compatible"
    
    # Check if user is logged in
    if ! az account show &> /dev/null; then
        log ERROR "Not logged in to Azure. Please run 'az login' first."
        exit 1
    fi
    
    # Check if required Azure providers are registered
    local providers=("Microsoft.DesktopVirtualization" "Microsoft.Compute" "Microsoft.Network" "Microsoft.Storage" "Microsoft.Logic" "Microsoft.Consumption" "Microsoft.OperationalInsights" "Microsoft.Web")
    
    for provider in "${providers[@]}"; do
        local status=$(az provider show --namespace "$provider" --query "registrationState" --output tsv 2>/dev/null || echo "NotRegistered")
        if [ "$status" != "Registered" ]; then
            log WARN "Provider $provider is not registered. Registering..."
            if ! $DRY_RUN; then
                az provider register --namespace "$provider" --wait
            fi
        else
            log DEBUG "Provider $provider is registered"
        fi
    done
    
    # Check if openssl is available for random generation
    if ! command -v openssl &> /dev/null; then
        log ERROR "openssl is required for generating random suffixes. Please install openssl."
        exit 1
    fi
    
    log INFO "All prerequisites check passed ✅"
}

# Function to set environment variables
setup_environment() {
    log INFO "Setting up environment variables..."
    
    # Set default values if not already set
    export RESOURCE_GROUP="${RESOURCE_GROUP:-rg-avd-cost-optimization}"
    export LOCATION="${LOCATION:-eastus}"
    export SUBSCRIPTION_ID="${SUBSCRIPTION_ID:-$(az account show --query id --output tsv)}"
    
    # Generate unique suffix for resource names
    if [ -z "$RANDOM_SUFFIX" ]; then
        export RANDOM_SUFFIX=$(openssl rand -hex 3)
        log INFO "Generated random suffix: $RANDOM_SUFFIX"
    fi
    
    # Set resource names with unique identifiers
    export AVD_WORKSPACE="${AVD_WORKSPACE:-avd-workspace-${RANDOM_SUFFIX}}"
    export HOST_POOL_NAME="${HOST_POOL_NAME:-hp-cost-optimized-${RANDOM_SUFFIX}}"
    export APP_GROUP_NAME="${APP_GROUP_NAME:-ag-desktop-${RANDOM_SUFFIX}}"
    export STORAGE_ACCOUNT="${STORAGE_ACCOUNT:-stcostopt${RANDOM_SUFFIX}}"
    export LOGIC_APP_NAME="${LOGIC_APP_NAME:-la-cost-optimizer-${RANDOM_SUFFIX}}"
    export BUDGET_NAME="${BUDGET_NAME:-budget-avd-${RANDOM_SUFFIX}}"
    export VMSS_NAME="${VMSS_NAME:-vmss-avd-${RANDOM_SUFFIX}}"
    export VNET_NAME="${VNET_NAME:-vnet-avd-${RANDOM_SUFFIX}}"
    export AUTOSCALE_NAME="${AUTOSCALE_NAME:-autoscale-avd-${RANDOM_SUFFIX}}"
    export LAW_NAME="${LAW_NAME:-law-avd-${RANDOM_SUFFIX}}"
    export FUNCTION_APP_NAME="${FUNCTION_APP_NAME:-func-ri-analyzer-${RANDOM_SUFFIX}}"
    
    # Validate storage account name (must be 3-24 chars, alphanumeric only)
    if [ ${#STORAGE_ACCOUNT} -gt 24 ]; then
        export STORAGE_ACCOUNT="stopt${RANDOM_SUFFIX}"
        log WARN "Storage account name truncated to: $STORAGE_ACCOUNT"
    fi
    
    log INFO "Environment variables configured:"
    log INFO "  Resource Group: $RESOURCE_GROUP"
    log INFO "  Location: $LOCATION"
    log INFO "  Subscription ID: $SUBSCRIPTION_ID"
    log INFO "  Random Suffix: $RANDOM_SUFFIX"
}

# Function to create resource group and storage account
create_foundation() {
    log INFO "Creating foundational resources..."
    
    # Create resource group with proper tagging
    log INFO "Creating resource group: $RESOURCE_GROUP"
    if ! $DRY_RUN; then
        az group create \
            --name "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --tags purpose=cost-optimization environment=demo project=avd-optimization
    fi
    log INFO "✅ Resource group created: $RESOURCE_GROUP"
    
    # Create storage account for cost reports and data
    log INFO "Creating storage account: $STORAGE_ACCOUNT"
    if ! $DRY_RUN; then
        az storage account create \
            --name "$STORAGE_ACCOUNT" \
            --resource-group "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --sku Standard_LRS \
            --kind StorageV2 \
            --tags department=shared purpose=cost-reporting \
            --output none
        
        # Wait for storage account to be fully provisioned
        az storage account show \
            --name "$STORAGE_ACCOUNT" \
            --resource-group "$RESOURCE_GROUP" \
            --query "provisioningState" \
            --output tsv | grep -q "Succeeded"
    fi
    log INFO "✅ Storage account created: $STORAGE_ACCOUNT"
}

# Function to create AVD infrastructure
create_avd_infrastructure() {
    log INFO "Creating Azure Virtual Desktop infrastructure..."
    
    # Create AVD workspace
    log INFO "Creating AVD workspace: $AVD_WORKSPACE"
    if ! $DRY_RUN; then
        az desktopvirtualization workspace create \
            --name "$AVD_WORKSPACE" \
            --resource-group "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --tags department=shared purpose=virtual-desktop \
            --description "Cost-optimized virtual desktop workspace" \
            --output none
    fi
    log INFO "✅ AVD workspace created: $AVD_WORKSPACE"
    
    # Create host pool for pooled desktops
    log INFO "Creating host pool: $HOST_POOL_NAME"
    if ! $DRY_RUN; then
        az desktopvirtualization hostpool create \
            --name "$HOST_POOL_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --host-pool-type Pooled \
            --load-balancer-type BreadthFirst \
            --max-session-limit 10 \
            --personal-desktop-assignment-type Automatic \
            --tags department=shared workload-type=pooled cost-center=100 \
            --output none
    fi
    log INFO "✅ Host pool created: $HOST_POOL_NAME"
}

# Function to create cost management budget
create_cost_management() {
    log INFO "Creating cost management budget and alerts..."
    
    # Create budget for AVD resources with automated alerts
    log INFO "Creating budget: $BUDGET_NAME"
    if ! $DRY_RUN; then
        local start_date=$(date -d "first day of this month" +%Y-%m-%d)
        az consumption budget create \
            --budget-name "$BUDGET_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --amount 1000 \
            --category Cost \
            --time-grain Monthly \
            --time-period start-date="$start_date" \
            --notifications actual=80 forecasted=100 \
            --output none
    fi
    log INFO "✅ Cost Management budget created: $BUDGET_NAME"
    
    # Set up cost attribution tags
    export DEPT_A_TAG="department=finance"
    export DEPT_B_TAG="department=engineering"
    export DEPT_C_TAG="department=marketing"
    
    log INFO "Cost attribution tags configured"
}

# Function to create automation components
create_automation() {
    log INFO "Creating automation components..."
    
    # Create Logic App for cost optimization automation
    log INFO "Creating Logic App: $LOGIC_APP_NAME"
    if ! $DRY_RUN; then
        az logic workflow create \
            --name "$LOGIC_APP_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --tags purpose=cost-automation department=shared \
            --output none
        
        # Get Logic App resource ID for permissions
        export LOGIC_APP_ID=$(az logic workflow show \
            --name "$LOGIC_APP_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --query id --output tsv)
        
        log DEBUG "Logic App ID: $LOGIC_APP_ID"
    fi
    log INFO "✅ Logic App created: $LOGIC_APP_NAME"
}

# Function to create compute infrastructure
create_compute_infrastructure() {
    log INFO "Creating compute infrastructure..."
    
    # Create virtual network for AVD resources
    log INFO "Creating virtual network: $VNET_NAME"
    if ! $DRY_RUN; then
        az network vnet create \
            --name "$VNET_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --address-prefix 10.0.0.0/16 \
            --subnet-name subnet-avd \
            --subnet-prefix 10.0.1.0/24 \
            --output none
    fi
    log INFO "✅ Virtual network created: $VNET_NAME"
    
    # Create VM scale set optimized for AVD workloads
    log INFO "Creating VM scale set: $VMSS_NAME"
    if ! $DRY_RUN; then
        az vmss create \
            --name "$VMSS_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --image Win2022Datacenter \
            --vm-sku Standard_D2s_v3 \
            --instance-count 2 \
            --vnet-name "$VNET_NAME" \
            --subnet subnet-avd \
            --admin-username avdadmin \
            --admin-password 'SecureP@ssw0rd123!' \
            --tags workload=avd department=shared cost-optimization=enabled \
            --output none
    fi
    log INFO "✅ VM Scale Set created: $VMSS_NAME"
}

# Function to configure auto-scaling
configure_autoscaling() {
    log INFO "Configuring auto-scaling rules..."
    
    # Create auto-scaling profile for business hours
    log INFO "Creating auto-scaling profile: $AUTOSCALE_NAME"
    if ! $DRY_RUN; then
        az monitor autoscale create \
            --name "$AUTOSCALE_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --resource "$VMSS_NAME" \
            --resource-type Microsoft.Compute/virtualMachineScaleSets \
            --min-count 1 \
            --max-count 10 \
            --count 2 \
            --output none
        
        # Add scale-out rule for high CPU usage
        az monitor autoscale rule create \
            --autoscale-name "$AUTOSCALE_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --condition "Percentage CPU > 75 avg 5m" \
            --scale out 1 \
            --output none
        
        # Add scale-in rule for low CPU usage
        az monitor autoscale rule create \
            --autoscale-name "$AUTOSCALE_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --condition "Percentage CPU < 25 avg 5m" \
            --scale in 1 \
            --output none
    fi
    log INFO "✅ Auto-scaling rules configured: $AUTOSCALE_NAME"
}

# Function to create monitoring infrastructure
create_monitoring() {
    log INFO "Creating monitoring infrastructure..."
    
    # Apply comprehensive tagging for cost attribution
    log INFO "Applying cost attribution tags to VM scale set"
    if ! $DRY_RUN; then
        az resource tag \
            --resource-group "$RESOURCE_GROUP" \
            --name "$VMSS_NAME" \
            --resource-type Microsoft.Compute/virtualMachineScaleSets \
            --tags cost-center=100 department=shared \
                   workload=virtual-desktop optimization=auto-scaling \
                   billing-code=AVD-PROD environment=production \
            --output none
    fi
    
    # Create Log Analytics workspace for monitoring
    log INFO "Creating Log Analytics workspace: $LAW_NAME"
    if ! $DRY_RUN; then
        az monitor log-analytics workspace create \
            --workspace-name "$LAW_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --tags purpose=monitoring department=shared \
            --output none
        
        export LAW_ID=$(az monitor log-analytics workspace show \
            --workspace-name "$LAW_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --query id --output tsv)
        
        log DEBUG "Log Analytics Workspace ID: $LAW_ID"
    fi
    log INFO "✅ Monitoring infrastructure configured"
}

# Function to configure Reserved Instance analysis
configure_reserved_instance_analysis() {
    log INFO "Configuring Reserved Instance analysis automation..."
    
    # Create storage container for cost analysis data
    log INFO "Creating storage container for cost analysis"
    if ! $DRY_RUN; then
        az storage container create \
            --name cost-analysis \
            --account-name "$STORAGE_ACCOUNT" \
            --public-access off \
            --output none
    fi
    
    # Create function app for Reserved Instance analysis
    log INFO "Creating Function App: $FUNCTION_APP_NAME"
    if ! $DRY_RUN; then
        az functionapp create \
            --name "$FUNCTION_APP_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --storage-account "$STORAGE_ACCOUNT" \
            --consumption-plan-location "$LOCATION" \
            --runtime node \
            --functions-version 4 \
            --tags purpose=cost-analysis department=shared \
            --output none
        
        # Configure function app settings for Cost Management API access
        az functionapp config appsettings set \
            --name "$FUNCTION_APP_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --settings "SUBSCRIPTION_ID=$SUBSCRIPTION_ID" \
                       "RESOURCE_GROUP=$RESOURCE_GROUP" \
                       "STORAGE_CONNECTION=DefaultEndpointsProtocol=https;AccountName=$STORAGE_ACCOUNT" \
            --output none
    fi
    log INFO "✅ Reserved Instance analysis automation configured"
}

# Function to validate deployment
validate_deployment() {
    log INFO "Validating deployment..."
    
    local validation_errors=0
    
    # Check resource group
    if ! az group show --name "$RESOURCE_GROUP" &>/dev/null; then
        log ERROR "Resource group $RESOURCE_GROUP not found"
        ((validation_errors++))
    fi
    
    # Check AVD workspace
    if ! az desktopvirtualization workspace show --name "$AVD_WORKSPACE" --resource-group "$RESOURCE_GROUP" &>/dev/null; then
        log ERROR "AVD workspace $AVD_WORKSPACE not found"
        ((validation_errors++))
    fi
    
    # Check VM scale set
    if ! az vmss show --name "$VMSS_NAME" --resource-group "$RESOURCE_GROUP" &>/dev/null; then
        log ERROR "VM scale set $VMSS_NAME not found"
        ((validation_errors++))
    fi
    
    # Check auto-scaling configuration
    if ! az monitor autoscale show --name "$AUTOSCALE_NAME" --resource-group "$RESOURCE_GROUP" &>/dev/null; then
        log ERROR "Auto-scaling configuration $AUTOSCALE_NAME not found"
        ((validation_errors++))
    fi
    
    if [ $validation_errors -eq 0 ]; then
        log INFO "✅ Deployment validation successful"
        return 0
    else
        log ERROR "❌ Deployment validation failed with $validation_errors errors"
        return 1
    fi
}

# Function to display deployment summary
display_summary() {
    log INFO "Deployment Summary"
    log INFO "=================="
    log INFO "Resource Group: $RESOURCE_GROUP"
    log INFO "Location: $LOCATION"
    log INFO "AVD Workspace: $AVD_WORKSPACE"
    log INFO "Host Pool: $HOST_POOL_NAME"
    log INFO "VM Scale Set: $VMSS_NAME"
    log INFO "Virtual Network: $VNET_NAME"
    log INFO "Storage Account: $STORAGE_ACCOUNT"
    log INFO "Logic App: $LOGIC_APP_NAME"
    log INFO "Function App: $FUNCTION_APP_NAME"
    log INFO "Budget: $BUDGET_NAME"
    log INFO "Auto-scaling: $AUTOSCALE_NAME"
    log INFO "Log Analytics: $LAW_NAME"
    log INFO ""
    log INFO "Next Steps:"
    log INFO "1. Configure AVD session hosts in the Azure portal"
    log INFO "2. Set up user assignments for the AVD workspace"
    log INFO "3. Monitor cost trends in Azure Cost Management"
    log INFO "4. Review Reserved Instance recommendations after 30 days of usage"
    log INFO ""
    log INFO "To clean up resources, run: ./destroy.sh"
}

# Main deployment function
main() {
    log INFO "Starting Azure Virtual Desktop Cost Optimization deployment"
    log INFO "Log file: $LOG_FILE"
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --dry-run)
                DRY_RUN=true
                log INFO "Running in dry-run mode"
                shift
                ;;
            --debug)
                DEBUG_MODE=true
                log INFO "Debug mode enabled"
                shift
                ;;
            -h|--help)
                echo "Usage: $0 [--dry-run] [--debug]"
                echo "  --dry-run  Show what would be deployed without making changes"
                echo "  --debug    Enable debug logging"
                exit 0
                ;;
            *)
                log ERROR "Unknown parameter: $1"
                exit 1
                ;;
        esac
    done
    
    # Execute deployment steps
    check_prerequisites
    setup_environment
    
    if $DRY_RUN; then
        log INFO "DRY RUN MODE - No resources will be created"
        log INFO "Would create the following resources:"
        log INFO "  Resource Group: $RESOURCE_GROUP"
        log INFO "  AVD Workspace: $AVD_WORKSPACE"
        log INFO "  Host Pool: $HOST_POOL_NAME"
        log INFO "  VM Scale Set: $VMSS_NAME"
        log INFO "  Storage Account: $STORAGE_ACCOUNT"
        log INFO "  Logic App: $LOGIC_APP_NAME"
        log INFO "  Function App: $FUNCTION_APP_NAME"
        exit 0
    fi
    
    # Create resources
    create_foundation
    create_avd_infrastructure
    create_cost_management
    create_automation
    create_compute_infrastructure
    configure_autoscaling
    create_monitoring
    configure_reserved_instance_analysis
    
    # Validate and summarize
    if validate_deployment; then
        display_summary
        log INFO "🎉 Azure Virtual Desktop Cost Optimization deployment completed successfully!"
        exit 0
    else
        log ERROR "💥 Deployment failed validation. Check the logs for details."
        exit 1
    fi
}

# Trap errors and cleanup
trap 'log ERROR "Script failed on line $LINENO"' ERR

# Initialize log file
echo "Azure Virtual Desktop Cost Optimization Deployment Log" > "$LOG_FILE"
echo "Started: $(date)" >> "$LOG_FILE"
echo "=========================================" >> "$LOG_FILE"

# Run main function
main "$@"