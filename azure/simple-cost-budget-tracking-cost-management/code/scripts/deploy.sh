#!/bin/bash

# Deploy script for Simple Cost Budget Tracking with Cost Management
# This script creates Azure budgets, action groups, and cost alerts for proactive cost monitoring

set -euo pipefail  # Exit on any error, undefined variable, or pipe failure

# Color codes for output formatting
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        log_error "Azure CLI is not installed. Please install it from https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
        exit 1
    fi
    
    # Check Azure CLI version (minimum 2.0.81)
    local az_version
    az_version=$(az version --query '"azure-cli"' -o tsv 2>/dev/null || echo "0.0.0")
    local required_version="2.0.81"
    
    if ! printf '%s\n%s\n' "$required_version" "$az_version" | sort -V -C; then
        log_error "Azure CLI version $az_version is too old. Please upgrade to version $required_version or later."
        exit 1
    fi
    
    # Check if user is logged in to Azure
    if ! az account show &> /dev/null; then
        log_error "Not logged in to Azure. Please run 'az login' first."
        exit 1
    fi
    
    # Check if openssl is available for random string generation
    if ! command -v openssl &> /dev/null; then
        log_error "openssl is not installed. Please install it for random string generation."
        exit 1
    fi
    
    log_success "Prerequisites check completed"
}

# Function to validate email address format
validate_email() {
    local email="$1"
    local email_regex='^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$'
    
    if [[ ! $email =~ $email_regex ]]; then
        log_error "Invalid email address format: $email"
        return 1
    fi
    return 0
}

# Function to prompt for email if not provided
get_email_address() {
    if [[ -z "${EMAIL_ADDRESS:-}" ]]; then
        echo -n "Enter email address for budget alerts: "
        read -r EMAIL_ADDRESS
        
        if [[ -z "$EMAIL_ADDRESS" ]]; then
            log_error "Email address is required for budget alerts"
            exit 1
        fi
    fi
    
    if ! validate_email "$EMAIL_ADDRESS"; then
        log_error "Please provide a valid email address"
        exit 1
    fi
    
    export EMAIL_ADDRESS
}

# Function to set environment variables
setup_environment() {
    log_info "Setting up environment variables..."
    
    # Generate unique suffix for resource names
    readonly RANDOM_SUFFIX=$(openssl rand -hex 3)
    
    # Set default values if not provided
    export LOCATION="${LOCATION:-eastus}"
    export BUDGET_AMOUNT="${BUDGET_AMOUNT:-100}"
    export RESOURCE_GROUP="${RESOURCE_GROUP:-rg-cost-tracking-${RANDOM_SUFFIX}}"
    export BUDGET_NAME="${BUDGET_NAME:-monthly-cost-budget-${RANDOM_SUFFIX}}"
    export ACTION_GROUP_NAME="${ACTION_GROUP_NAME:-cost-alert-group-${RANDOM_SUFFIX}}"
    export FILTERED_BUDGET_NAME="${FILTERED_BUDGET_NAME:-rg-budget-${RANDOM_SUFFIX}}"
    
    # Get subscription ID
    SUBSCRIPTION_ID=$(az account show --query id --output tsv)
    export SUBSCRIPTION_ID
    
    log_info "Environment variables configured:"
    log_info "  - Resource Group: $RESOURCE_GROUP"
    log_info "  - Location: $LOCATION"
    log_info "  - Budget Amount: \$$BUDGET_AMOUNT"
    log_info "  - Email: $EMAIL_ADDRESS"
    log_info "  - Subscription ID: $SUBSCRIPTION_ID"
}

# Function to create resource group
create_resource_group() {
    log_info "Creating resource group: $RESOURCE_GROUP"
    
    if az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        log_warning "Resource group $RESOURCE_GROUP already exists, skipping creation"
        return 0
    fi
    
    az group create \
        --name "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --tags purpose=cost-monitoring environment=demo \
        --output none
    
    log_success "Resource group created: $RESOURCE_GROUP"
}

# Function to create Azure Monitor Action Group
create_action_group() {
    log_info "Creating Azure Monitor Action Group: $ACTION_GROUP_NAME"
    
    if az monitor action-group show --name "$ACTION_GROUP_NAME" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        log_warning "Action group $ACTION_GROUP_NAME already exists, skipping creation"
    else
        az monitor action-group create \
            --name "$ACTION_GROUP_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --short-name "CostAlert" \
            --action email "budget-admin" "$EMAIL_ADDRESS" \
            --output none
        
        log_success "Action group created with email notifications enabled"
    fi
    
    # Get action group resource ID
    ACTION_GROUP_ID=$(az monitor action-group show \
        --name "$ACTION_GROUP_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --query id --output tsv)
    
    export ACTION_GROUP_ID
    log_info "Email alerts will be sent to: $EMAIL_ADDRESS"
}

# Function to create budget alerts configuration
create_budget_alerts_config() {
    log_info "Creating budget alerts configuration..."
    
    cat > budget-alerts.json << EOF
[
  {
    "enabled": true,
    "operator": "GreaterThan",
    "threshold": 50,
    "contactEmails": ["$EMAIL_ADDRESS"],
    "contactRoles": [],
    "contactGroups": ["$ACTION_GROUP_ID"],
    "thresholdType": "Actual"
  },
  {
    "enabled": true,
    "operator": "GreaterThan", 
    "threshold": 80,
    "contactEmails": ["$EMAIL_ADDRESS"],
    "contactRoles": [],
    "contactGroups": ["$ACTION_GROUP_ID"],
    "thresholdType": "Actual"
  },
  {
    "enabled": true,
    "operator": "GreaterThan",
    "threshold": 100,
    "contactEmails": ["$EMAIL_ADDRESS"],
    "contactRoles": [],
    "contactGroups": ["$ACTION_GROUP_ID"],
    "thresholdType": "Forecasted"
  }
]
EOF
    
    log_success "Budget alert thresholds configured: 50%, 80%, 100%"
}

# Function to create cost management budget
create_cost_budget() {
    log_info "Creating monthly cost budget: \$$BUDGET_AMOUNT"
    
    # Check if budget already exists
    if az rest \
        --method GET \
        --url "https://management.azure.com/subscriptions/$SUBSCRIPTION_ID/providers/Microsoft.Consumption/budgets/$BUDGET_NAME?api-version=2023-11-01" \
        &> /dev/null; then
        log_warning "Budget $BUDGET_NAME already exists, skipping creation"
        return 0
    fi
    
    local start_date end_date
    start_date=$(date -d 'first day of this month' +%Y-%m-01 2>/dev/null || date -v1d +%Y-%m-01)
    end_date=$(date -d 'first day of next month + 1 year' +%Y-%m-01 2>/dev/null || date -v1d -v+1y +%Y-%m-01)
    
    local budget_json
    budget_json=$(cat << EOF
{
  "properties": {
    "category": "Cost",
    "amount": $BUDGET_AMOUNT,
    "timeGrain": "Monthly",
    "timePeriod": {
      "startDate": "$start_date",
      "endDate": "$end_date"
    },
    "notifications": $(cat budget-alerts.json)
  }
}
EOF
)
    
    # Create budget using Azure REST API
    if az rest \
        --method PUT \
        --url "https://management.azure.com/subscriptions/$SUBSCRIPTION_ID/providers/Microsoft.Consumption/budgets/$BUDGET_NAME?api-version=2023-11-01" \
        --body "$budget_json" \
        --output none; then
        log_success "Monthly budget created: \$$BUDGET_AMOUNT"
        log_info "Budget scope: Subscription $SUBSCRIPTION_ID"
    else
        log_error "Failed to create budget"
        return 1
    fi
}

# Function to create filtered budget for resource group
create_filtered_budget() {
    log_info "Creating filtered budget for resource group: $RESOURCE_GROUP"
    
    # Check if filtered budget already exists
    if az rest \
        --method GET \
        --url "https://management.azure.com/subscriptions/$SUBSCRIPTION_ID/providers/Microsoft.Consumption/budgets/$FILTERED_BUDGET_NAME?api-version=2023-11-01" \
        &> /dev/null; then
        log_warning "Filtered budget $FILTERED_BUDGET_NAME already exists, skipping creation"
        return 0
    fi
    
    local start_date end_date
    start_date=$(date -d 'first day of this month' +%Y-%m-01 2>/dev/null || date -v1d +%Y-%m-01)
    end_date=$(date -d 'first day of next month + 1 year' +%Y-%m-01 2>/dev/null || date -v1d -v+1y +%Y-%m-01)
    
    local filtered_budget_json
    filtered_budget_json=$(cat << EOF
{
  "properties": {
    "category": "Cost",
    "amount": $BUDGET_AMOUNT,
    "timeGrain": "Monthly",
    "timePeriod": {
      "startDate": "$start_date",
      "endDate": "$end_date"
    },
    "filter": {
      "dimensions": {
        "name": "ResourceGroupName",
        "operator": "In",
        "values": ["$RESOURCE_GROUP"]
      }
    },
    "notifications": $(cat budget-alerts.json)
  }
}
EOF
)
    
    # Create filtered budget using Azure REST API
    if az rest \
        --method PUT \
        --url "https://management.azure.com/subscriptions/$SUBSCRIPTION_ID/providers/Microsoft.Consumption/budgets/$FILTERED_BUDGET_NAME?api-version=2023-11-01" \
        --body "$filtered_budget_json" \
        --output none; then
        log_success "Resource group budget created with filters"
        log_info "Monitoring costs for resource group: $RESOURCE_GROUP"
    else
        log_error "Failed to create filtered budget"
        return 1
    fi
}

# Function to test action group notifications
test_action_group() {
    log_info "Testing action group notification delivery..."
    
    # Test action group notification (if supported)
    if az monitor action-group test-notifications create \
        --action-group-name "$ACTION_GROUP_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --alert-type "budget" \
        --output none 2>/dev/null; then
        log_success "Test email sent to verify notification delivery"
    else
        log_warning "Action group test notifications not supported in this Azure CLI version"
        log_info "Budget alerts will still work when thresholds are exceeded"
    fi
}

# Function to verify deployment
verify_deployment() {
    log_info "Verifying deployment..."
    
    # Verify budget creation
    if az rest \
        --method GET \
        --url "https://management.azure.com/subscriptions/$SUBSCRIPTION_ID/providers/Microsoft.Consumption/budgets/$BUDGET_NAME?api-version=2023-11-01" \
        --query "properties.{Amount:amount,TimeGrain:timeGrain,Category:category}" \
        --output table; then
        log_success "Budget configuration verified"
    else
        log_error "Failed to verify budget configuration"
        return 1
    fi
    
    # List all budgets for verification
    log_info "Listing all budgets:"
    az rest \
        --method GET \
        --url "https://management.azure.com/subscriptions/$SUBSCRIPTION_ID/providers/Microsoft.Consumption/budgets?api-version=2023-11-01" \
        --query "value[].{Name:name,Amount:properties.amount}" \
        --output table
    
    log_success "Budget monitoring is now active"
    log_info "View in Azure portal: https://portal.azure.com/#view/Microsoft_Azure_CostManagement/Menu/~/overview"
}

# Function to save deployment state
save_deployment_state() {
    log_info "Saving deployment state..."
    
    cat > deployment-state.json << EOF
{
  "deployment_timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "resource_group": "$RESOURCE_GROUP",
  "location": "$LOCATION",
  "budget_name": "$BUDGET_NAME",
  "filtered_budget_name": "$FILTERED_BUDGET_NAME",
  "action_group_name": "$ACTION_GROUP_NAME",
  "action_group_id": "$ACTION_GROUP_ID",
  "subscription_id": "$SUBSCRIPTION_ID",
  "email_address": "$EMAIL_ADDRESS",
  "budget_amount": "$BUDGET_AMOUNT"
}
EOF
    
    log_success "Deployment state saved to deployment-state.json"
}

# Function to display deployment summary
show_deployment_summary() {
    echo
    log_success "=== DEPLOYMENT COMPLETED SUCCESSFULLY ==="
    echo
    echo "📊 Budget Configuration:"
    echo "   • Monthly Budget: \$$BUDGET_AMOUNT"
    echo "   • Alert Thresholds: 50%, 80%, 100%"
    echo "   • Email Notifications: $EMAIL_ADDRESS"
    echo
    echo "🔗 Resources Created:"
    echo "   • Resource Group: $RESOURCE_GROUP"
    echo "   • Action Group: $ACTION_GROUP_NAME"
    echo "   • Main Budget: $BUDGET_NAME"
    echo "   • Filtered Budget: $FILTERED_BUDGET_NAME"
    echo
    echo "🌐 Azure Portal Links:"
    echo "   • Cost Management: https://portal.azure.com/#view/Microsoft_Azure_CostManagement/Menu/~/overview"
    echo "   • Budgets: https://portal.azure.com/#view/Microsoft_Azure_CostManagement/Menu/~/budgets"
    echo
    echo "📧 Important Notes:"
    echo "   • Budget alerts will be sent to: $EMAIL_ADDRESS"
    echo "   • Add azure-noreply@microsoft.com to your email whitelist"
    echo "   • Cost evaluation occurs every 4-8 hours"
    echo
    echo "🧹 Cleanup:"
    echo "   • Run './destroy.sh' to remove all resources"
    echo
}

# Function to handle cleanup on error
cleanup_on_error() {
    log_error "Deployment failed. Cleaning up partial deployment..."
    
    # Remove configuration files
    rm -f budget-alerts.json deployment-state.json
    
    # Note: We don't automatically delete Azure resources on error
    # as they might be needed for troubleshooting
    log_warning "Azure resources were not automatically cleaned up."
    log_warning "Run './destroy.sh' manually if you want to remove them."
}

# Main deployment function
main() {
    echo "🚀 Starting Azure Cost Budget Tracking Deployment"
    echo "=================================================="
    
    # Set up error handling
    trap cleanup_on_error ERR
    
    # Check prerequisites
    check_prerequisites
    
    # Get email address
    get_email_address
    
    # Setup environment
    setup_environment
    
    # Create resources
    create_resource_group
    create_action_group
    create_budget_alerts_config
    create_cost_budget
    create_filtered_budget
    
    # Test and verify
    test_action_group
    verify_deployment
    
    # Save state and show summary
    save_deployment_state
    show_deployment_summary
    
    log_success "Deployment completed successfully!"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --email)
            EMAIL_ADDRESS="$2"
            shift 2
            ;;
        --budget-amount)
            BUDGET_AMOUNT="$2"
            shift 2
            ;;
        --location)
            LOCATION="$2"
            shift 2
            ;;
        --resource-group)
            RESOURCE_GROUP="$2"
            shift 2
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo
            echo "Options:"
            echo "  --email EMAIL          Email address for budget alerts (required)"
            echo "  --budget-amount AMOUNT Budget amount in USD (default: 100)"
            echo "  --location LOCATION    Azure region (default: eastus)"
            echo "  --resource-group NAME  Resource group name (default: auto-generated)"
            echo "  --help                 Show this help message"
            echo
            echo "Environment Variables:"
            echo "  EMAIL_ADDRESS         Email for alerts (can be set instead of --email)"
            echo "  BUDGET_AMOUNT         Budget amount (can be set instead of --budget-amount)"
            echo "  LOCATION              Azure region (can be set instead of --location)"
            echo "  RESOURCE_GROUP        Resource group name (can be set instead of --resource-group)"
            echo
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Run main function
main "$@"