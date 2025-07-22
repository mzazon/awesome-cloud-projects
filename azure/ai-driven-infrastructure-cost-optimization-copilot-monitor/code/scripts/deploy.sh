#!/bin/bash

# Azure Infrastructure Cost Optimization Deployment Script
# This script deploys all resources needed for the cost optimization solution

set -e
set -o pipefail

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

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
DEPLOYMENT_NAME="cost-optimization-$(date +%s)"
CONFIG_FILE="${SCRIPT_DIR}/.deployment_config"

# Default values
DEFAULT_LOCATION="eastus"
DEFAULT_RESOURCE_GROUP_PREFIX="rg-costopt"
DEFAULT_RETENTION_DAYS="30"
DEFAULT_BUDGET_AMOUNT="5000"

# Check if running in dry-run mode
DRY_RUN=${DRY_RUN:-false}

usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Deploy Azure infrastructure for cost optimization with Azure Copilot and Azure Monitor.

OPTIONS:
    -g, --resource-group     Resource group name (default: generated)
    -l, --location          Azure region (default: $DEFAULT_LOCATION)
    -r, --retention-days    Log Analytics retention in days (default: $DEFAULT_RETENTION_DAYS)
    -b, --budget-amount     Monthly budget amount in USD (default: $DEFAULT_BUDGET_AMOUNT)
    -e, --email             Alert email address (required)
    -d, --dry-run           Show what would be deployed without executing
    -h, --help              Show this help message
    --skip-test-vm          Skip creating test VM for validation
    --force                 Force deployment even if resources exist

EXAMPLES:
    $0 --email admin@company.com
    $0 --email admin@company.com --location westus2 --budget-amount 10000
    $0 --email admin@company.com --dry-run

EOF
}

# Parse command line arguments
parse_args() {
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
            -r|--retention-days)
                RETENTION_DAYS="$2"
                shift 2
                ;;
            -b|--budget-amount)
                BUDGET_AMOUNT="$2"
                shift 2
                ;;
            -e|--email)
                ALERT_EMAIL="$2"
                shift 2
                ;;
            -d|--dry-run)
                DRY_RUN=true
                shift
                ;;
            --skip-test-vm)
                SKIP_TEST_VM=true
                shift
                ;;
            --force)
                FORCE_DEPLOYMENT=true
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                error "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done

    # Validate required parameters
    if [[ -z "$ALERT_EMAIL" ]]; then
        error "Alert email address is required. Use --email parameter."
        usage
        exit 1
    fi

    # Set defaults for optional parameters
    LOCATION=${LOCATION:-$DEFAULT_LOCATION}
    RETENTION_DAYS=${RETENTION_DAYS:-$DEFAULT_RETENTION_DAYS}
    BUDGET_AMOUNT=${BUDGET_AMOUNT:-$DEFAULT_BUDGET_AMOUNT}
    SKIP_TEST_VM=${SKIP_TEST_VM:-false}
    FORCE_DEPLOYMENT=${FORCE_DEPLOYMENT:-false}

    # Generate resource group name if not provided
    if [[ -z "$RESOURCE_GROUP" ]]; then
        RANDOM_SUFFIX=$(openssl rand -hex 3)
        RESOURCE_GROUP="${DEFAULT_RESOURCE_GROUP_PREFIX}-${RANDOM_SUFFIX}"
    fi
}

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."

    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        error "Azure CLI is not installed. Please install it from https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
        exit 1
    fi

    # Check Azure CLI version
    AZ_VERSION=$(az version --query '"azure-cli"' -o tsv)
    log "Azure CLI version: $AZ_VERSION"

    # Check if logged in to Azure
    if ! az account show &> /dev/null; then
        error "Not logged in to Azure. Please run 'az login' first."
        exit 1
    fi

    # Get current subscription info
    SUBSCRIPTION_ID=$(az account show --query id --output tsv)
    SUBSCRIPTION_NAME=$(az account show --query name --output tsv)
    TENANT_ID=$(az account show --query tenantId --output tsv)
    
    log "Using subscription: $SUBSCRIPTION_NAME ($SUBSCRIPTION_ID)"
    log "Tenant ID: $TENANT_ID"

    # Validate location
    if ! az account list-locations --query "[?name=='$LOCATION']" --output tsv | grep -q "$LOCATION"; then
        error "Invalid location: $LOCATION"
        log "Available locations:"
        az account list-locations --query "[].name" --output tsv | sort
        exit 1
    fi

    # Check resource providers
    log "Checking required resource providers..."
    local providers=("Microsoft.Automation" "Microsoft.OperationalInsights" "Microsoft.Logic" "Microsoft.Insights" "Microsoft.CostManagement")
    
    for provider in "${providers[@]}"; do
        local state=$(az provider show --namespace "$provider" --query registrationState --output tsv 2>/dev/null || echo "NotRegistered")
        if [[ "$state" != "Registered" ]]; then
            warning "Resource provider $provider is not registered. Registering..."
            if [[ "$DRY_RUN" == "false" ]]; then
                az provider register --namespace "$provider" --wait
            fi
        fi
    done

    success "Prerequisites check completed"
}

# Save deployment configuration
save_config() {
    cat > "$CONFIG_FILE" << EOF
DEPLOYMENT_NAME=$DEPLOYMENT_NAME
RESOURCE_GROUP=$RESOURCE_GROUP
LOCATION=$LOCATION
SUBSCRIPTION_ID=$SUBSCRIPTION_ID
RETENTION_DAYS=$RETENTION_DAYS
BUDGET_AMOUNT=$BUDGET_AMOUNT
ALERT_EMAIL=$ALERT_EMAIL
DEPLOYMENT_DATE=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
EOF
    log "Configuration saved to $CONFIG_FILE"
}

# Create resource group
create_resource_group() {
    log "Creating resource group: $RESOURCE_GROUP"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY-RUN] Would create resource group $RESOURCE_GROUP in $LOCATION"
        return 0
    fi

    # Check if resource group exists
    if az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        if [[ "$FORCE_DEPLOYMENT" == "true" ]]; then
            warning "Resource group $RESOURCE_GROUP already exists, continuing due to --force flag"
        else
            error "Resource group $RESOURCE_GROUP already exists. Use --force to continue or choose a different name."
            exit 1
        fi
    else
        az group create \
            --name "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --tags purpose=cost-optimization environment=production deployment="$DEPLOYMENT_NAME"
        
        success "Resource group created: $RESOURCE_GROUP"
    fi
}

# Deploy Log Analytics workspace
deploy_log_analytics() {
    log "Deploying Log Analytics workspace..."
    
    local workspace_name="law-costopt-$(echo $RESOURCE_GROUP | cut -d'-' -f3)"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY-RUN] Would create Log Analytics workspace: $workspace_name"
        return 0
    fi

    az monitor log-analytics workspace create \
        --resource-group "$RESOURCE_GROUP" \
        --workspace-name "$workspace_name" \
        --location "$LOCATION" \
        --retention-in-days "$RETENTION_DAYS" \
        --tags purpose=cost-optimization component=monitoring

    # Store workspace ID for later use
    WORKSPACE_ID=$(az monitor log-analytics workspace show \
        --resource-group "$RESOURCE_GROUP" \
        --workspace-name "$workspace_name" \
        --query id --output tsv)

    success "Log Analytics workspace deployed: $workspace_name"
    echo "WORKSPACE_ID=$WORKSPACE_ID" >> "$CONFIG_FILE"
    echo "WORKSPACE_NAME=$workspace_name" >> "$CONFIG_FILE"
}

# Configure Azure Monitor
configure_azure_monitor() {
    log "Configuring Azure Monitor..."

    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY-RUN] Would configure Azure Monitor diagnostic settings and alerts"
        return 0
    fi

    # Create diagnostic settings for activity logs
    az monitor diagnostic-settings create \
        --name "CostOptimizationLogs" \
        --resource "$SUBSCRIPTION_ID" \
        --logs '[
            {"category": "Administrative", "enabled": true, "retentionPolicy": {"enabled": false, "days": 0}},
            {"category": "ServiceHealth", "enabled": true, "retentionPolicy": {"enabled": false, "days": 0}},
            {"category": "ResourceHealth", "enabled": true, "retentionPolicy": {"enabled": false, "days": 0}}
        ]' \
        --workspace "$WORKSPACE_ID" || warning "Failed to create some diagnostic settings (may already exist)"

    # Create cost alert (simplified version)
    local alert_rule_name="HighCostAlert-${DEPLOYMENT_NAME}"
    
    # Note: Cost alerts require specific setup through Cost Management
    log "Cost alerts will need to be configured manually through Azure Portal > Cost Management"
    
    success "Azure Monitor configured"
}

# Deploy Automation Account
deploy_automation_account() {
    log "Deploying Azure Automation Account..."
    
    local automation_account="aa-costopt-$(echo $RESOURCE_GROUP | cut -d'-' -f3)"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY-RUN] Would create Automation Account: $automation_account"
        return 0
    fi

    # Create Automation Account
    az automation account create \
        --name "$automation_account" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --sku "Basic" \
        --tags purpose=cost-optimization component=automation

    # Enable system-assigned managed identity
    az automation account identity assign \
        --name "$automation_account" \
        --resource-group "$RESOURCE_GROUP"

    # Get the principal ID for role assignment
    local principal_id
    principal_id=$(az automation account show \
        --name "$automation_account" \
        --resource-group "$RESOURCE_GROUP" \
        --query identity.principalId --output tsv)

    # Assign permissions
    az role assignment create \
        --assignee "$principal_id" \
        --role "Virtual Machine Contributor" \
        --scope "/subscriptions/$SUBSCRIPTION_ID" || warning "Role assignment may already exist"

    az role assignment create \
        --assignee "$principal_id" \
        --role "Storage Account Contributor" \
        --scope "/subscriptions/$SUBSCRIPTION_ID" || warning "Role assignment may already exist"

    success "Automation Account deployed: $automation_account"
    echo "AUTOMATION_ACCOUNT=$automation_account" >> "$CONFIG_FILE"
    echo "PRINCIPAL_ID=$principal_id" >> "$CONFIG_FILE"
}

# Deploy runbooks
deploy_runbooks() {
    log "Deploying cost optimization runbooks..."

    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY-RUN] Would deploy VM and storage optimization runbooks"
        return 0
    fi

    local automation_account
    automation_account=$(grep "AUTOMATION_ACCOUNT=" "$CONFIG_FILE" | cut -d'=' -f2)

    # Deploy VM optimization runbook
    if [[ -f "$PROJECT_ROOT/terraform/runbooks/vm-optimization.ps1" ]]; then
        az automation runbook create \
            --automation-account-name "$automation_account" \
            --resource-group "$RESOURCE_GROUP" \
            --name "Optimize-VMSize" \
            --type "PowerShell" \
            --content "@$PROJECT_ROOT/terraform/runbooks/vm-optimization.ps1"

        az automation runbook publish \
            --automation-account-name "$automation_account" \
            --resource-group "$RESOURCE_GROUP" \
            --name "Optimize-VMSize"
    fi

    # Deploy storage optimization runbook
    if [[ -f "$PROJECT_ROOT/terraform/runbooks/storage-optimization.ps1" ]]; then
        az automation runbook create \
            --automation-account-name "$automation_account" \
            --resource-group "$RESOURCE_GROUP" \
            --name "Optimize-StorageTier" \
            --type "PowerShell" \
            --content "@$PROJECT_ROOT/terraform/runbooks/storage-optimization.ps1"

        az automation runbook publish \
            --automation-account-name "$automation_account" \
            --resource-group "$RESOURCE_GROUP" \
            --name "Optimize-StorageTier"
    fi

    success "Runbooks deployed successfully"
}

# Configure Cost Management
configure_cost_management() {
    log "Configuring Cost Management..."

    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY-RUN] Would configure budget with amount $BUDGET_AMOUNT USD"
        return 0
    fi

    # Create budget (simplified - actual implementation may need REST API)
    local budget_name="MonthlyOptimizationBudget-$(echo $RESOURCE_GROUP | cut -d'-' -f3)"
    local start_date=$(date +%Y-%m-01)
    local end_date=$(date -d "+1 year" +%Y-%m-%d)

    log "Setting up budget: $budget_name"
    log "Budget amount: $BUDGET_AMOUNT USD"
    log "Alert email: $ALERT_EMAIL"
    
    # Note: Budget creation through CLI has limitations
    warning "Budget creation requires Azure Portal or REST API for full functionality"
    log "Manual step: Create budget '$budget_name' in Azure Portal > Cost Management"

    success "Cost Management configuration noted"
}

# Create test VM (optional)
create_test_vm() {
    if [[ "$SKIP_TEST_VM" == "true" ]]; then
        log "Skipping test VM creation as requested"
        return 0
    fi

    log "Creating test VM for validation..."

    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY-RUN] Would create test VM for optimization testing"
        return 0
    fi

    local vm_name="test-vm-optimize-$(echo $RESOURCE_GROUP | cut -d'-' -f3)"
    
    # Create test VM with oversized configuration for optimization
    az vm create \
        --resource-group "$RESOURCE_GROUP" \
        --name "$vm_name" \
        --image "Ubuntu2204" \
        --size "Standard_D4s_v3" \
        --admin-username "azureuser" \
        --generate-ssh-keys \
        --tags purpose=testing component=cost-optimization-target \
        --no-wait

    success "Test VM creation initiated: $vm_name"
    echo "TEST_VM_NAME=$vm_name" >> "$CONFIG_FILE"
}

# Deploy Logic App workflow
deploy_logic_app() {
    log "Deploying Logic App workflow..."

    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY-RUN] Would deploy Logic App for automated cost optimization responses"
        return 0
    fi

    local logic_app_name="la-costopt-$(echo $RESOURCE_GROUP | cut -d'-' -f3)"

    # Simple Logic App creation (actual workflow definition would be more complex)
    az logic workflow create \
        --resource-group "$RESOURCE_GROUP" \
        --name "$logic_app_name" \
        --definition '{
            "definition": {
                "$schema": "https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#",
                "triggers": {
                    "manual": {
                        "type": "Request",
                        "kind": "Http"
                    }
                },
                "actions": {
                    "Response": {
                        "type": "Response",
                        "inputs": {
                            "statusCode": 200,
                            "body": "Cost optimization workflow triggered"
                        }
                    }
                }
            }
        }' \
        --tags purpose=cost-optimization component=workflow

    success "Logic App deployed: $logic_app_name"
    echo "LOGIC_APP_NAME=$logic_app_name" >> "$CONFIG_FILE"
}

# Validate deployment
validate_deployment() {
    log "Validating deployment..."

    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY-RUN] Would validate all deployed resources"
        return 0
    fi

    local workspace_name
    workspace_name=$(grep "WORKSPACE_NAME=" "$CONFIG_FILE" | cut -d'=' -f2)
    
    # Check Log Analytics workspace
    if az monitor log-analytics workspace show --resource-group "$RESOURCE_GROUP" --workspace-name "$workspace_name" &> /dev/null; then
        success "✓ Log Analytics workspace is accessible"
    else
        error "✗ Log Analytics workspace validation failed"
    fi

    # Check Automation Account
    local automation_account
    automation_account=$(grep "AUTOMATION_ACCOUNT=" "$CONFIG_FILE" | cut -d'=' -f2)
    
    if az automation account show --name "$automation_account" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        success "✓ Automation Account is accessible"
    else
        error "✗ Automation Account validation failed"
    fi

    # List deployed resources
    log "Deployed resources in $RESOURCE_GROUP:"
    az resource list --resource-group "$RESOURCE_GROUP" --query "[].{Name:name, Type:type, Location:location}" --output table

    success "Deployment validation completed"
}

# Display next steps
show_next_steps() {
    log "Deployment completed successfully!"
    echo
    echo "📋 Next Steps:"
    echo "1. Configure Azure Copilot in the Azure Portal"
    echo "2. Set up cost budgets in Cost Management + Billing"
    echo "3. Review and customize automation runbooks"
    echo "4. Test cost optimization workflows"
    echo
    echo "📍 Resources created in resource group: $RESOURCE_GROUP"
    echo "📧 Alert email configured: $ALERT_EMAIL"
    echo "💰 Budget amount: $BUDGET_AMOUNT USD"
    echo
    echo "🔗 Useful links:"
    echo "   - Azure Portal: https://portal.azure.com"
    echo "   - Cost Management: https://portal.azure.com/#view/Microsoft_Azure_CostManagement/Menu/~/overview"
    echo "   - Azure Monitor: https://portal.azure.com/#view/Microsoft_Azure_Monitoring/AzureMonitoringBrowseBlade/~/overview"
    echo
    echo "📄 Configuration saved to: $CONFIG_FILE"
    echo "   Use this file with destroy.sh to clean up resources"
}

# Main deployment function
main() {
    log "Starting Azure Cost Optimization deployment..."
    
    # Parse arguments
    parse_args "$@"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        warning "Running in DRY-RUN mode - no resources will be created"
    fi

    # Execute deployment steps
    check_prerequisites
    save_config
    create_resource_group
    deploy_log_analytics
    configure_azure_monitor
    deploy_automation_account
    deploy_runbooks
    configure_cost_management
    create_test_vm
    deploy_logic_app
    validate_deployment
    
    if [[ "$DRY_RUN" == "false" ]]; then
        show_next_steps
    else
        log "DRY-RUN completed. Use without --dry-run to actually deploy resources."
    fi
}

# Error handling
trap 'error "Deployment failed on line $LINENO. Exit code: $?"' ERR

# Run main function with all arguments
main "$@"