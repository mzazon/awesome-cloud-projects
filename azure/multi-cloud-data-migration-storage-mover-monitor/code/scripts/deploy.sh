#!/bin/bash

#==============================================================================
# Azure Storage Mover and Azure Monitor Deployment Script
# 
# This script deploys Azure Storage Mover resources with Azure Monitor integration
# for automated multi-cloud data migration from AWS S3 to Azure Blob Storage.
#
# Recipe: Multi-Cloud Data Migration with Azure Storage Mover and Azure Monitor
# Author: Azure Recipe Generator
# Version: 1.0
#==============================================================================

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
    exit 1
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1${NC}"
}

#==============================================================================
# Configuration Variables
#==============================================================================

# Default values (can be overridden by environment variables)
RESOURCE_GROUP="${RESOURCE_GROUP:-rg-migration-demo}"
LOCATION="${LOCATION:-eastus}"
STORAGE_ACCOUNT_NAME="${STORAGE_ACCOUNT_NAME:-stmigration$(openssl rand -hex 4)}"
STORAGE_MOVER_NAME="${STORAGE_MOVER_NAME:-sm-migration-$(openssl rand -hex 3)}"
LOG_WORKSPACE_NAME="${LOG_WORKSPACE_NAME:-log-migration-$(openssl rand -hex 3)}"
LOGIC_APP_NAME="${LOGIC_APP_NAME:-logic-migration-$(openssl rand -hex 3)}"
AWS_S3_BUCKET="${AWS_S3_BUCKET:-}"
AWS_ACCOUNT_ID="${AWS_ACCOUNT_ID:-}"
DEPLOYMENT_NAME="${DEPLOYMENT_NAME:-storage-mover-deployment-$(date +%s)}"
NOTIFICATION_EMAIL="${NOTIFICATION_EMAIL:-admin@yourcompany.com}"

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Deployment state file
STATE_FILE="${PROJECT_ROOT}/deployment_state.json"

#==============================================================================
# Utility Functions
#==============================================================================

# Check if required tools are installed
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check Azure CLI
    if ! command -v az &> /dev/null; then
        error "Azure CLI is not installed. Please install it from https://docs.microsoft.com/en-us/cli/azure/"
    fi
    
    # Check Azure CLI version
    local az_version=$(az version --query '"azure-cli"' -o tsv)
    info "Azure CLI version: $az_version"
    
    # Check if logged in to Azure
    if ! az account show &> /dev/null; then
        error "Not logged in to Azure. Please run 'az login' first."
    fi
    
    # Check subscription
    local subscription_id=$(az account show --query id -o tsv)
    local subscription_name=$(az account show --query name -o tsv)
    info "Using subscription: $subscription_name ($subscription_id)"
    
    # Check if jq is available (optional but recommended)
    if ! command -v jq &> /dev/null; then
        warn "jq is not installed. JSON parsing will be limited."
    fi
    
    # Check if AWS CLI is available for multicloud scenarios
    if ! command -v aws &> /dev/null; then
        warn "AWS CLI is not installed. Required for AWS S3 integration."
    fi
    
    log "Prerequisites check completed successfully"
}

# Validate configuration
validate_configuration() {
    log "Validating configuration..."
    
    # Validate resource group name
    if [[ ! "$RESOURCE_GROUP" =~ ^[a-zA-Z0-9._-]+$ ]]; then
        error "Invalid resource group name: $RESOURCE_GROUP"
    fi
    
    # Validate location
    if ! az account list-locations --query "[?name=='$LOCATION']" -o tsv | grep -q "$LOCATION"; then
        error "Invalid location: $LOCATION"
    fi
    
    # Validate storage account name
    if [[ ! "$STORAGE_ACCOUNT_NAME" =~ ^[a-z0-9]{3,24}$ ]]; then
        error "Invalid storage account name: $STORAGE_ACCOUNT_NAME (must be 3-24 lowercase alphanumeric characters)"
    fi
    
    # Check if AWS configuration is provided for multicloud scenarios
    if [[ -z "$AWS_S3_BUCKET" ]]; then
        warn "AWS_S3_BUCKET is not set. You'll need to configure the source S3 bucket manually."
    fi
    
    if [[ -z "$AWS_ACCOUNT_ID" ]]; then
        warn "AWS_ACCOUNT_ID is not set. You'll need to configure the AWS account ID manually."
    fi
    
    log "Configuration validation completed"
}

# Save deployment state
save_state() {
    local state_data=$(cat <<EOF
{
    "deployment_name": "$DEPLOYMENT_NAME",
    "resource_group": "$RESOURCE_GROUP",
    "location": "$LOCATION",
    "storage_account_name": "$STORAGE_ACCOUNT_NAME",
    "storage_mover_name": "$STORAGE_MOVER_NAME",
    "log_workspace_name": "$LOG_WORKSPACE_NAME",
    "logic_app_name": "$LOGIC_APP_NAME",
    "aws_s3_bucket": "$AWS_S3_BUCKET",
    "aws_account_id": "$AWS_ACCOUNT_ID",
    "deployment_time": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "subscription_id": "$(az account show --query id -o tsv)"
}
EOF
)
    echo "$state_data" > "$STATE_FILE"
    log "Deployment state saved to: $STATE_FILE"
}

# Load deployment state
load_state() {
    if [[ -f "$STATE_FILE" ]]; then
        log "Loading deployment state from: $STATE_FILE"
        return 0
    else
        warn "No deployment state file found at: $STATE_FILE"
        return 1
    fi
}

# Register required resource providers
register_providers() {
    log "Registering required Azure resource providers..."
    
    local providers=(
        "Microsoft.StorageMover"
        "Microsoft.HybridCompute"
        "Microsoft.Insights"
        "Microsoft.Storage"
        "Microsoft.Logic"
        "Microsoft.OperationalInsights"
    )
    
    for provider in "${providers[@]}"; do
        info "Registering provider: $provider"
        az provider register --namespace "$provider" --wait
        
        # Check registration status
        local status=$(az provider show --namespace "$provider" --query registrationState -o tsv)
        if [[ "$status" == "Registered" ]]; then
            info "Provider $provider is registered"
        else
            warn "Provider $provider registration status: $status"
        fi
    done
    
    log "Resource provider registration completed"
}

#==============================================================================
# Deployment Functions
#==============================================================================

# Create resource group
create_resource_group() {
    log "Creating resource group: $RESOURCE_GROUP"
    
    # Check if resource group exists
    if az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        warn "Resource group $RESOURCE_GROUP already exists"
    else
        az group create \
            --name "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --tags purpose=migration environment=demo created-by=azure-recipe
        
        info "Resource group $RESOURCE_GROUP created successfully"
    fi
}

# Create storage account
create_storage_account() {
    log "Creating storage account: $STORAGE_ACCOUNT_NAME"
    
    # Check if storage account exists
    if az storage account show --name "$STORAGE_ACCOUNT_NAME" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        warn "Storage account $STORAGE_ACCOUNT_NAME already exists"
    else
        az storage account create \
            --name "$STORAGE_ACCOUNT_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --sku Standard_LRS \
            --kind StorageV2 \
            --access-tier Hot \
            --enable-hierarchical-namespace false \
            --tags purpose=migration source=aws-s3
        
        info "Storage account $STORAGE_ACCOUNT_NAME created successfully"
    fi
    
    # Get storage account key
    local storage_key=$(az storage account keys list \
        --account-name "$STORAGE_ACCOUNT_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --query "[0].value" --output tsv)
    
    # Create container for migrated data
    az storage container create \
        --name "migrated-data" \
        --account-name "$STORAGE_ACCOUNT_NAME" \
        --account-key "$storage_key" \
        --public-access off
    
    info "Storage container 'migrated-data' created"
}

# Create Log Analytics workspace
create_log_analytics_workspace() {
    log "Creating Log Analytics workspace: $LOG_WORKSPACE_NAME"
    
    # Check if workspace exists
    if az monitor log-analytics workspace show --resource-group "$RESOURCE_GROUP" --workspace-name "$LOG_WORKSPACE_NAME" &> /dev/null; then
        warn "Log Analytics workspace $LOG_WORKSPACE_NAME already exists"
    else
        az monitor log-analytics workspace create \
            --resource-group "$RESOURCE_GROUP" \
            --workspace-name "$LOG_WORKSPACE_NAME" \
            --location "$LOCATION" \
            --sku pergb2018 \
            --retention-time 30 \
            --tags purpose=migration monitoring=azure-monitor
        
        info "Log Analytics workspace $LOG_WORKSPACE_NAME created successfully"
    fi
    
    # Get workspace ID
    local workspace_id=$(az monitor log-analytics workspace show \
        --resource-group "$RESOURCE_GROUP" \
        --workspace-name "$LOG_WORKSPACE_NAME" \
        --query customerId --output tsv)
    
    info "Log Analytics workspace ID: $workspace_id"
}

# Create Storage Mover resource
create_storage_mover() {
    log "Creating Storage Mover resource: $STORAGE_MOVER_NAME"
    
    # Check if Storage Mover exists
    if az storage-mover show --resource-group "$RESOURCE_GROUP" --name "$STORAGE_MOVER_NAME" &> /dev/null; then
        warn "Storage Mover $STORAGE_MOVER_NAME already exists"
    else
        az storage-mover create \
            --resource-group "$RESOURCE_GROUP" \
            --name "$STORAGE_MOVER_NAME" \
            --location "$LOCATION" \
            --description "Multi-cloud migration from AWS S3 to Azure Blob Storage" \
            --tags environment=demo migration-type=s3-to-blob
        
        info "Storage Mover $STORAGE_MOVER_NAME created successfully"
    fi
}

# Create Logic App
create_logic_app() {
    log "Creating Logic App: $LOGIC_APP_NAME"
    
    # Check if Logic App exists
    if az logic app show --resource-group "$RESOURCE_GROUP" --name "$LOGIC_APP_NAME" &> /dev/null; then
        warn "Logic App $LOGIC_APP_NAME already exists"
    else
        # Create a basic Logic App workflow
        local workflow_definition=$(cat <<'EOF'
{
    "$schema": "https://schema.management.azure.com/schemas/2016-06-01/Microsoft.Logic.json",
    "contentVersion": "1.0.0.0",
    "parameters": {},
    "triggers": {
        "manual": {
            "type": "Request",
            "kind": "Http"
        }
    },
    "actions": {
        "Response": {
            "type": "Response",
            "kind": "Http",
            "inputs": {
                "statusCode": 200,
                "body": {
                    "message": "Migration automation workflow triggered successfully"
                }
            }
        }
    }
}
EOF
)
        
        az logic app create \
            --resource-group "$RESOURCE_GROUP" \
            --name "$LOGIC_APP_NAME" \
            --location "$LOCATION" \
            --definition "$workflow_definition" \
            --tags purpose=migration automation=workflow
        
        info "Logic App $LOGIC_APP_NAME created successfully"
    fi
}

# Create Azure Monitor alerts
create_monitor_alerts() {
    log "Creating Azure Monitor alerts..."
    
    # Create action group for notifications
    local action_group_name="migration-alerts"
    
    if az monitor action-group show --resource-group "$RESOURCE_GROUP" --name "$action_group_name" &> /dev/null; then
        warn "Action group $action_group_name already exists"
    else
        az monitor action-group create \
            --resource-group "$RESOURCE_GROUP" \
            --name "$action_group_name" \
            --short-name "migration" \
            --email-receiver name="admin" email="$NOTIFICATION_EMAIL"
        
        info "Action group $action_group_name created successfully"
    fi
    
    # Note: Creating metric alerts for Storage Mover would require the service to be fully available
    # This is a placeholder for when the service metrics are available
    warn "Storage Mover metrics may not be immediately available. Monitor alerts will be created when metrics are available."
}

# Configure monitoring and diagnostics
configure_monitoring() {
    log "Configuring monitoring and diagnostics..."
    
    # Get Log Analytics workspace ID
    local workspace_id=$(az monitor log-analytics workspace show \
        --resource-group "$RESOURCE_GROUP" \
        --workspace-name "$LOG_WORKSPACE_NAME" \
        --query id --output tsv)
    
    # Enable diagnostic settings for Storage Account
    az monitor diagnostic-settings create \
        --resource-group "$RESOURCE_GROUP" \
        --name "storage-diagnostics" \
        --resource "/subscriptions/$(az account show --query id -o tsv)/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Storage/storageAccounts/$STORAGE_ACCOUNT_NAME" \
        --logs '[{"category":"StorageRead","enabled":true},{"category":"StorageWrite","enabled":true},{"category":"StorageDelete","enabled":true}]' \
        --metrics '[{"category":"Transaction","enabled":true},{"category":"Capacity","enabled":true}]' \
        --workspace "$workspace_id"
    
    info "Diagnostic settings configured for storage account"
}

# Verify deployment
verify_deployment() {
    log "Verifying deployment..."
    
    # Check resource group
    if ! az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        error "Resource group $RESOURCE_GROUP was not created"
    fi
    
    # Check storage account
    if ! az storage account show --name "$STORAGE_ACCOUNT_NAME" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        error "Storage account $STORAGE_ACCOUNT_NAME was not created"
    fi
    
    # Check Log Analytics workspace
    if ! az monitor log-analytics workspace show --resource-group "$RESOURCE_GROUP" --workspace-name "$LOG_WORKSPACE_NAME" &> /dev/null; then
        error "Log Analytics workspace $LOG_WORKSPACE_NAME was not created"
    fi
    
    # Check Storage Mover
    if ! az storage-mover show --resource-group "$RESOURCE_GROUP" --name "$STORAGE_MOVER_NAME" &> /dev/null; then
        error "Storage Mover $STORAGE_MOVER_NAME was not created"
    fi
    
    # Check Logic App
    if ! az logic app show --resource-group "$RESOURCE_GROUP" --name "$LOGIC_APP_NAME" &> /dev/null; then
        error "Logic App $LOGIC_APP_NAME was not created"
    fi
    
    log "Deployment verification completed successfully"
}

# Display deployment summary
display_summary() {
    log "Deployment Summary"
    echo "=================================="
    echo "Resource Group: $RESOURCE_GROUP"
    echo "Location: $LOCATION"
    echo "Storage Account: $STORAGE_ACCOUNT_NAME"
    echo "Storage Mover: $STORAGE_MOVER_NAME"
    echo "Log Analytics Workspace: $LOG_WORKSPACE_NAME"
    echo "Logic App: $LOGIC_APP_NAME"
    echo "Deployment State File: $STATE_FILE"
    echo "=================================="
    
    # Get resource URLs
    local subscription_id=$(az account show --query id -o tsv)
    
    echo ""
    echo "Resource URLs:"
    echo "Storage Account: https://portal.azure.com/#@/resource/subscriptions/$subscription_id/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Storage/storageAccounts/$STORAGE_ACCOUNT_NAME"
    echo "Storage Mover: https://portal.azure.com/#@/resource/subscriptions/$subscription_id/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.StorageMover/storageMovers/$STORAGE_MOVER_NAME"
    echo "Log Analytics: https://portal.azure.com/#@/resource/subscriptions/$subscription_id/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.OperationalInsights/workspaces/$LOG_WORKSPACE_NAME"
    echo "Logic App: https://portal.azure.com/#@/resource/subscriptions/$subscription_id/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Logic/workflows/$LOGIC_APP_NAME"
    echo ""
    
    info "Next steps:"
    echo "1. Configure AWS S3 source endpoint in Storage Mover"
    echo "2. Set up migration jobs through Azure portal or API"
    echo "3. Configure Logic App workflow for automation"
    echo "4. Set up monitoring alerts for migration events"
    echo "5. Test the migration process with sample data"
}

#==============================================================================
# Main Execution
#==============================================================================

main() {
    log "Starting Azure Storage Mover and Monitor deployment..."
    
    # Check prerequisites
    check_prerequisites
    
    # Validate configuration
    validate_configuration
    
    # Register required providers
    register_providers
    
    # Create resources
    create_resource_group
    create_storage_account
    create_log_analytics_workspace
    create_storage_mover
    create_logic_app
    create_monitor_alerts
    configure_monitoring
    
    # Verify deployment
    verify_deployment
    
    # Save deployment state
    save_state
    
    # Display summary
    display_summary
    
    log "Deployment completed successfully!"
    log "Run './destroy.sh' to clean up all resources when done."
}

# Handle script interruption
trap 'error "Script interrupted by user"' INT TERM

# Show usage information
show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Deploy Azure Storage Mover and Azure Monitor for multi-cloud data migration"
    echo ""
    echo "Options:"
    echo "  -h, --help                Show this help message"
    echo "  -g, --resource-group      Resource group name (default: $RESOURCE_GROUP)"
    echo "  -l, --location            Azure location (default: $LOCATION)"
    echo "  -s, --storage-account     Storage account name (default: generated)"
    echo "  -m, --storage-mover       Storage Mover name (default: generated)"
    echo "  -w, --log-workspace       Log Analytics workspace name (default: generated)"
    echo "  -a, --logic-app           Logic App name (default: generated)"
    echo "  -b, --aws-s3-bucket       AWS S3 bucket name for source data"
    echo "  -i, --aws-account-id      AWS Account ID"
    echo "  -e, --email               Notification email (default: $NOTIFICATION_EMAIL)"
    echo ""
    echo "Environment variables:"
    echo "  RESOURCE_GROUP, LOCATION, STORAGE_ACCOUNT_NAME, STORAGE_MOVER_NAME"
    echo "  LOG_WORKSPACE_NAME, LOGIC_APP_NAME, AWS_S3_BUCKET, AWS_ACCOUNT_ID"
    echo "  NOTIFICATION_EMAIL"
    echo ""
    echo "Examples:"
    echo "  $0"
    echo "  $0 -g my-migration-rg -l westus2 -b my-source-bucket"
    echo "  $0 --resource-group my-rg --aws-s3-bucket my-bucket --aws-account-id 123456789012"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_usage
            exit 0
            ;;
        -g|--resource-group)
            RESOURCE_GROUP="$2"
            shift 2
            ;;
        -l|--location)
            LOCATION="$2"
            shift 2
            ;;
        -s|--storage-account)
            STORAGE_ACCOUNT_NAME="$2"
            shift 2
            ;;
        -m|--storage-mover)
            STORAGE_MOVER_NAME="$2"
            shift 2
            ;;
        -w|--log-workspace)
            LOG_WORKSPACE_NAME="$2"
            shift 2
            ;;
        -a|--logic-app)
            LOGIC_APP_NAME="$2"
            shift 2
            ;;
        -b|--aws-s3-bucket)
            AWS_S3_BUCKET="$2"
            shift 2
            ;;
        -i|--aws-account-id)
            AWS_ACCOUNT_ID="$2"
            shift 2
            ;;
        -e|--email)
            NOTIFICATION_EMAIL="$2"
            shift 2
            ;;
        *)
            error "Unknown option: $1"
            ;;
    esac
done

# Run main function
main "$@"