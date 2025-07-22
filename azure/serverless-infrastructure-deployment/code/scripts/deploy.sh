#!/bin/bash

# Azure Container Apps Jobs Infrastructure Deployment Script
# This script deploys automated infrastructure deployment workflows using Azure Container Apps Jobs and ARM Templates
# Author: Azure Recipe Generator
# Version: 1.0

set -e
set -o pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Global variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/deploy.log"
DEPLOYMENT_START_TIME=$(date +%s)

# Default configuration
DEFAULT_RESOURCE_GROUP="rg-deployment-automation"
DEFAULT_LOCATION="eastus"
DEFAULT_CONTAINER_APPS_ENV="cae-deployment-env"
DEFAULT_JOB_NAME="deployment-job"

# Configuration variables (can be overridden by environment variables)
RESOURCE_GROUP="${RESOURCE_GROUP:-$DEFAULT_RESOURCE_GROUP}"
LOCATION="${LOCATION:-$DEFAULT_LOCATION}"
CONTAINER_APPS_ENV="${CONTAINER_APPS_ENV:-$DEFAULT_CONTAINER_APPS_ENV}"
JOB_NAME="${JOB_NAME:-$DEFAULT_JOB_NAME}"
KEY_VAULT_NAME="${KEY_VAULT_NAME:-kv-deploy-$(openssl rand -hex 4)}"
STORAGE_ACCOUNT="${STORAGE_ACCOUNT:-stdeployartifacts$(openssl rand -hex 4)}"
SUBSCRIPTION_ID="${SUBSCRIPTION_ID:-}"
DRY_RUN="${DRY_RUN:-false}"
SKIP_CONFIRMATIONS="${SKIP_CONFIRMATIONS:-false}"

# Logging function
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${timestamp} [${level}] ${message}" | tee -a "$LOG_FILE"
}

# Info logging
info() {
    log "INFO" "${BLUE}$*${NC}"
}

# Success logging
success() {
    log "SUCCESS" "${GREEN}$*${NC}"
}

# Warning logging
warn() {
    log "WARNING" "${YELLOW}$*${NC}"
}

# Error logging
error() {
    log "ERROR" "${RED}$*${NC}"
}

# Fatal error (exit)
fatal() {
    error "$*"
    exit 1
}

# Progress indicator
show_progress() {
    local message="$1"
    echo -e "${BLUE}⏳ ${message}...${NC}"
}

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Validate prerequisites
validate_prerequisites() {
    info "Validating prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command_exists az; then
        fatal "Azure CLI is not installed. Please install Azure CLI v2.50.0 or later."
    fi
    
    # Check Azure CLI version
    local az_version=$(az version --query '."azure-cli"' -o tsv 2>/dev/null)
    if [[ -z "$az_version" ]]; then
        fatal "Unable to determine Azure CLI version. Please ensure Azure CLI is properly installed."
    fi
    
    info "Azure CLI version: $az_version"
    
    # Check if user is logged in
    if ! az account show >/dev/null 2>&1; then
        fatal "Not logged in to Azure. Please run 'az login' first."
    fi
    
    # Get subscription ID if not provided
    if [[ -z "$SUBSCRIPTION_ID" ]]; then
        SUBSCRIPTION_ID=$(az account show --query id --output tsv)
    fi
    
    # Validate subscription
    if ! az account show --subscription "$SUBSCRIPTION_ID" >/dev/null 2>&1; then
        fatal "Invalid subscription ID: $SUBSCRIPTION_ID"
    fi
    
    # Check required tools
    if ! command_exists openssl; then
        fatal "openssl is required for generating random values. Please install openssl."
    fi
    
    # Check if Container Apps extension is installed
    if ! az extension show --name containerapp >/dev/null 2>&1; then
        warn "Container Apps extension not installed. Installing..."
        az extension add --name containerapp --upgrade
    fi
    
    success "Prerequisites validation completed"
}

# Get current user information
get_current_user() {
    info "Getting current user information..."
    
    local current_user
    current_user=$(az ad signed-in-user show --query id --output tsv 2>/dev/null)
    
    if [[ -z "$current_user" ]]; then
        fatal "Unable to get current user information. Please ensure you're logged in with appropriate permissions."
    fi
    
    echo "$current_user"
}

# Check if resource exists
resource_exists() {
    local resource_type="$1"
    local resource_name="$2"
    local resource_group="$3"
    
    case "$resource_type" in
        "group")
            az group show --name "$resource_name" >/dev/null 2>&1
            ;;
        "keyvault")
            az keyvault show --name "$resource_name" >/dev/null 2>&1
            ;;
        "storage")
            az storage account show --name "$resource_name" --resource-group "$resource_group" >/dev/null 2>&1
            ;;
        "identity")
            az identity show --name "$resource_name" --resource-group "$resource_group" >/dev/null 2>&1
            ;;
        "containerapp-env")
            az containerapp env show --name "$resource_name" --resource-group "$resource_group" >/dev/null 2>&1
            ;;
        "containerapp-job")
            az containerapp job show --name "$resource_name" --resource-group "$resource_group" >/dev/null 2>&1
            ;;
        *)
            false
            ;;
    esac
}

# Create resource group
create_resource_group() {
    info "Creating resource group: $RESOURCE_GROUP"
    
    if resource_exists "group" "$RESOURCE_GROUP"; then
        warn "Resource group $RESOURCE_GROUP already exists"
        return 0
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY RUN] Would create resource group: $RESOURCE_GROUP"
        return 0
    fi
    
    az group create \
        --name "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --tags purpose=deployment-automation environment=demo \
        --output none
    
    success "Resource group created: $RESOURCE_GROUP"
}

# Create Container Apps environment
create_container_apps_environment() {
    info "Creating Container Apps environment: $CONTAINER_APPS_ENV"
    
    if resource_exists "containerapp-env" "$CONTAINER_APPS_ENV" "$RESOURCE_GROUP"; then
        warn "Container Apps environment $CONTAINER_APPS_ENV already exists"
        return 0
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY RUN] Would create Container Apps environment: $CONTAINER_APPS_ENV"
        return 0
    fi
    
    az containerapp env create \
        --name "$CONTAINER_APPS_ENV" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --logs-destination none \
        --output none
    
    success "Container Apps environment created: $CONTAINER_APPS_ENV"
}

# Create Key Vault
create_key_vault() {
    info "Creating Key Vault: $KEY_VAULT_NAME"
    
    if resource_exists "keyvault" "$KEY_VAULT_NAME"; then
        warn "Key Vault $KEY_VAULT_NAME already exists"
        return 0
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY RUN] Would create Key Vault: $KEY_VAULT_NAME"
        return 0
    fi
    
    az keyvault create \
        --name "$KEY_VAULT_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --sku standard \
        --enabled-for-template-deployment true \
        --enable-rbac-authorization true \
        --output none
    
    # Get current user and assign Key Vault Secrets Officer role
    local current_user
    current_user=$(get_current_user)
    
    az role assignment create \
        --assignee "$current_user" \
        --role "Key Vault Secrets Officer" \
        --scope "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.KeyVault/vaults/$KEY_VAULT_NAME" \
        --output none
    
    success "Key Vault created with RBAC enabled: $KEY_VAULT_NAME"
}

# Create Storage Account
create_storage_account() {
    info "Creating Storage Account: $STORAGE_ACCOUNT"
    
    if resource_exists "storage" "$STORAGE_ACCOUNT" "$RESOURCE_GROUP"; then
        warn "Storage Account $STORAGE_ACCOUNT already exists"
        return 0
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY RUN] Would create Storage Account: $STORAGE_ACCOUNT"
        return 0
    fi
    
    az storage account create \
        --name "$STORAGE_ACCOUNT" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --sku Standard_LRS \
        --kind StorageV2 \
        --access-tier Hot \
        --allow-blob-public-access false \
        --output none
    
    # Create containers
    local containers=("arm-templates" "deployment-logs" "deployment-scripts")
    for container in "${containers[@]}"; do
        az storage container create \
            --name "$container" \
            --account-name "$STORAGE_ACCOUNT" \
            --auth-mode login \
            --output none
    done
    
    success "Storage Account created with containers: $STORAGE_ACCOUNT"
}

# Create Managed Identity
create_managed_identity() {
    info "Creating Managed Identity: id-deployment-job"
    
    if resource_exists "identity" "id-deployment-job" "$RESOURCE_GROUP"; then
        warn "Managed Identity id-deployment-job already exists"
        return 0
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY RUN] Would create Managed Identity: id-deployment-job"
        return 0
    fi
    
    az identity create \
        --name "id-deployment-job" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --output none
    
    success "Managed Identity created: id-deployment-job"
}

# Assign RBAC permissions
assign_rbac_permissions() {
    info "Assigning RBAC permissions to Managed Identity"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY RUN] Would assign RBAC permissions"
        return 0
    fi
    
    # Get managed identity client ID
    local identity_client_id
    identity_client_id=$(az identity show \
        --name "id-deployment-job" \
        --resource-group "$RESOURCE_GROUP" \
        --query clientId --output tsv)
    
    if [[ -z "$identity_client_id" ]]; then
        fatal "Unable to get Managed Identity client ID"
    fi
    
    # Wait for identity to be available
    sleep 10
    
    # Assign Contributor role for ARM deployments
    az role assignment create \
        --assignee "$identity_client_id" \
        --role "Contributor" \
        --scope "/subscriptions/$SUBSCRIPTION_ID" \
        --output none
    
    # Assign Storage Blob Data Contributor role
    az role assignment create \
        --assignee "$identity_client_id" \
        --role "Storage Blob Data Contributor" \
        --scope "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Storage/storageAccounts/$STORAGE_ACCOUNT" \
        --output none
    
    # Assign Key Vault Secrets User role
    az role assignment create \
        --assignee "$identity_client_id" \
        --role "Key Vault Secrets User" \
        --scope "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.KeyVault/vaults/$KEY_VAULT_NAME" \
        --output none
    
    success "RBAC permissions assigned to Managed Identity"
}

# Create sample ARM template
create_sample_arm_template() {
    info "Creating sample ARM template"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY RUN] Would create sample ARM template"
        return 0
    fi
    
    local template_file="${SCRIPT_DIR}/sample-template.json"
    
    cat > "$template_file" << 'EOF'
{
    "$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#",
    "contentVersion": "1.0.0.0",
    "parameters": {
        "storageAccountName": {
            "type": "string",
            "metadata": {
                "description": "Name of the storage account to create"
            }
        },
        "location": {
            "type": "string",
            "defaultValue": "[resourceGroup().location]",
            "metadata": {
                "description": "Location for all resources"
            }
        }
    },
    "variables": {
        "storageAccountType": "Standard_LRS"
    },
    "resources": [
        {
            "type": "Microsoft.Storage/storageAccounts",
            "apiVersion": "2023-01-01",
            "name": "[parameters('storageAccountName')]",
            "location": "[parameters('location')]",
            "sku": {
                "name": "[variables('storageAccountType')]"
            },
            "kind": "StorageV2",
            "properties": {
                "accessTier": "Hot",
                "allowBlobPublicAccess": false
            }
        }
    ],
    "outputs": {
        "storageAccountId": {
            "type": "string",
            "value": "[resourceId('Microsoft.Storage/storageAccounts', parameters('storageAccountName'))]"
        }
    }
}
EOF
    
    # Upload ARM template to storage
    az storage blob upload \
        --file "$template_file" \
        --container-name "arm-templates" \
        --name "sample-template.json" \
        --account-name "$STORAGE_ACCOUNT" \
        --auth-mode login \
        --overwrite \
        --output none
    
    # Clean up local file
    rm -f "$template_file"
    
    success "Sample ARM template created and uploaded"
}

# Create deployment script
create_deployment_script() {
    info "Creating deployment script"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY RUN] Would create deployment script"
        return 0
    fi
    
    local script_file="${SCRIPT_DIR}/deploy-script.sh"
    
    cat > "$script_file" << 'EOF'
#!/bin/bash
set -e

# Script parameters
TEMPLATE_NAME=${1:-"sample-template.json"}
DEPLOYMENT_NAME=${2:-"deployment-$(date +%Y%m%d-%H%M%S)"}
TARGET_RESOURCE_GROUP=${3:-"rg-deployment-target"}

echo "Starting deployment: ${DEPLOYMENT_NAME}"
echo "Template: ${TEMPLATE_NAME}"
echo "Target Resource Group: ${TARGET_RESOURCE_GROUP}"

# Authenticate using managed identity
az login --identity

# Download ARM template from storage
az storage blob download \
    --container-name "arm-templates" \
    --name "${TEMPLATE_NAME}" \
    --file "/tmp/${TEMPLATE_NAME}" \
    --account-name "${STORAGE_ACCOUNT_NAME}" \
    --auth-mode login

# Create target resource group if it doesn't exist
az group create \
    --name "${TARGET_RESOURCE_GROUP}" \
    --location "${LOCATION}" \
    --tags deployedBy=automated-deployment

# Deploy ARM template
DEPLOYMENT_OUTPUT=$(az deployment group create \
    --resource-group "${TARGET_RESOURCE_GROUP}" \
    --template-file "/tmp/${TEMPLATE_NAME}" \
    --name "${DEPLOYMENT_NAME}" \
    --parameters storageAccountName="st${DEPLOYMENT_NAME}test" \
    --output json)

# Log deployment results
echo "Deployment completed successfully"
echo "Deployment output: ${DEPLOYMENT_OUTPUT}"

# Upload deployment log to storage
echo "${DEPLOYMENT_OUTPUT}" > "/tmp/deployment-log-${DEPLOYMENT_NAME}.json"
az storage blob upload \
    --file "/tmp/deployment-log-${DEPLOYMENT_NAME}.json" \
    --container-name "deployment-logs" \
    --name "deployment-log-${DEPLOYMENT_NAME}.json" \
    --account-name "${STORAGE_ACCOUNT_NAME}" \
    --auth-mode login

echo "✅ Deployment workflow completed: ${DEPLOYMENT_NAME}"
EOF
    
    # Upload deployment script to storage
    az storage blob upload \
        --file "$script_file" \
        --container-name "deployment-scripts" \
        --name "deploy-script.sh" \
        --account-name "$STORAGE_ACCOUNT" \
        --auth-mode login \
        --overwrite \
        --output none
    
    # Clean up local file
    rm -f "$script_file"
    
    success "Deployment script created and uploaded"
}

# Create Container Apps Job
create_container_apps_job() {
    info "Creating Container Apps Job: $JOB_NAME"
    
    if resource_exists "containerapp-job" "$JOB_NAME" "$RESOURCE_GROUP"; then
        warn "Container Apps Job $JOB_NAME already exists"
        return 0
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY RUN] Would create Container Apps Job: $JOB_NAME"
        return 0
    fi
    
    # Get managed identity ID
    local identity_id
    identity_id=$(az identity show \
        --name "id-deployment-job" \
        --resource-group "$RESOURCE_GROUP" \
        --query id --output tsv)
    
    if [[ -z "$identity_id" ]]; then
        fatal "Unable to get Managed Identity ID"
    fi
    
    az containerapp job create \
        --name "$JOB_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --environment "$CONTAINER_APPS_ENV" \
        --trigger-type "Manual" \
        --replica-timeout 1800 \
        --replica-retry-limit 3 \
        --parallelism 1 \
        --completion-count 1 \
        --image "mcr.microsoft.com/azure-cli:latest" \
        --cpu "0.5" \
        --memory "1.0Gi" \
        --assign-identity "$identity_id" \
        --env-vars \
            "STORAGE_ACCOUNT_NAME=$STORAGE_ACCOUNT" \
            "LOCATION=$LOCATION" \
        --command "/bin/bash" \
        --args "-c" "az storage blob download --container-name deployment-scripts --name deploy-script.sh --file /tmp/deploy-script.sh --account-name \$STORAGE_ACCOUNT_NAME --auth-mode login && chmod +x /tmp/deploy-script.sh && /tmp/deploy-script.sh" \
        --output none
    
    success "Container Apps Job created: $JOB_NAME"
}

# Create scheduled Container Apps Job
create_scheduled_job() {
    info "Creating scheduled Container Apps Job: ${JOB_NAME}-scheduled"
    
    if resource_exists "containerapp-job" "${JOB_NAME}-scheduled" "$RESOURCE_GROUP"; then
        warn "Scheduled Container Apps Job ${JOB_NAME}-scheduled already exists"
        return 0
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY RUN] Would create scheduled Container Apps Job: ${JOB_NAME}-scheduled"
        return 0
    fi
    
    # Get managed identity ID
    local identity_id
    identity_id=$(az identity show \
        --name "id-deployment-job" \
        --resource-group "$RESOURCE_GROUP" \
        --query id --output tsv)
    
    if [[ -z "$identity_id" ]]; then
        fatal "Unable to get Managed Identity ID"
    fi
    
    az containerapp job create \
        --name "${JOB_NAME}-scheduled" \
        --resource-group "$RESOURCE_GROUP" \
        --environment "$CONTAINER_APPS_ENV" \
        --trigger-type "Schedule" \
        --cron-expression "0 2 * * *" \
        --replica-timeout 1800 \
        --replica-retry-limit 3 \
        --parallelism 1 \
        --completion-count 1 \
        --image "mcr.microsoft.com/azure-cli:latest" \
        --cpu "0.5" \
        --memory "1.0Gi" \
        --assign-identity "$identity_id" \
        --env-vars \
            "STORAGE_ACCOUNT_NAME=$STORAGE_ACCOUNT" \
            "LOCATION=$LOCATION" \
        --command "/bin/bash" \
        --args "-c" "az storage blob download --container-name deployment-scripts --name deploy-script.sh --file /tmp/deploy-script.sh --account-name \$STORAGE_ACCOUNT_NAME --auth-mode login && chmod +x /tmp/deploy-script.sh && /tmp/deploy-script.sh" \
        --output none
    
    success "Scheduled Container Apps Job created: ${JOB_NAME}-scheduled"
}

# Verify deployment
verify_deployment() {
    info "Verifying deployment..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY RUN] Would verify deployment"
        return 0
    fi
    
    # Check Container Apps Job
    if az containerapp job show --name "$JOB_NAME" --resource-group "$RESOURCE_GROUP" --query "properties.provisioningState" --output tsv | grep -q "Succeeded"; then
        success "✅ Container Apps Job is running"
    else
        warn "⚠️  Container Apps Job may not be ready"
    fi
    
    # Check scheduled job
    if az containerapp job show --name "${JOB_NAME}-scheduled" --resource-group "$RESOURCE_GROUP" --query "properties.provisioningState" --output tsv | grep -q "Succeeded"; then
        success "✅ Scheduled Container Apps Job is running"
    else
        warn "⚠️  Scheduled Container Apps Job may not be ready"
    fi
    
    # Check storage containers
    local containers=("arm-templates" "deployment-logs" "deployment-scripts")
    for container in "${containers[@]}"; do
        if az storage container show --name "$container" --account-name "$STORAGE_ACCOUNT" --auth-mode login >/dev/null 2>&1; then
            success "✅ Storage container '$container' is ready"
        else
            warn "⚠️  Storage container '$container' may not be ready"
        fi
    done
    
    success "Deployment verification completed"
}

# Test manual job execution
test_manual_execution() {
    info "Testing manual job execution..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY RUN] Would test manual job execution"
        return 0
    fi
    
    if [[ "$SKIP_CONFIRMATIONS" != "true" ]]; then
        read -p "Do you want to test the manual job execution? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            info "Skipping manual job execution test"
            return 0
        fi
    fi
    
    local job_execution_name
    job_execution_name=$(az containerapp job start \
        --name "$JOB_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --query "name" --output tsv)
    
    if [[ -n "$job_execution_name" ]]; then
        success "✅ Manual job execution started: $job_execution_name"
        info "Monitor execution status with: az containerapp job execution show --name $job_execution_name --job-name $JOB_NAME --resource-group $RESOURCE_GROUP"
    else
        warn "⚠️  Failed to start manual job execution"
    fi
}

# Display deployment summary
display_summary() {
    local deployment_end_time=$(date +%s)
    local deployment_duration=$((deployment_end_time - DEPLOYMENT_START_TIME))
    
    echo
    echo "=================================="
    echo "🎉 DEPLOYMENT COMPLETED SUCCESSFULLY"
    echo "=================================="
    echo
    echo "📋 Deployment Summary:"
    echo "  • Resource Group: $RESOURCE_GROUP"
    echo "  • Location: $LOCATION"
    echo "  • Container Apps Environment: $CONTAINER_APPS_ENV"
    echo "  • Container Apps Job: $JOB_NAME"
    echo "  • Scheduled Job: ${JOB_NAME}-scheduled"
    echo "  • Key Vault: $KEY_VAULT_NAME"
    echo "  • Storage Account: $STORAGE_ACCOUNT"
    echo "  • Managed Identity: id-deployment-job"
    echo "  • Deployment Duration: ${deployment_duration}s"
    echo
    echo "🔧 Next Steps:"
    echo "  • Test manual job execution:"
    echo "    az containerapp job start --name $JOB_NAME --resource-group $RESOURCE_GROUP"
    echo "  • Monitor job executions:"
    echo "    az containerapp job execution list --job-name $JOB_NAME --resource-group $RESOURCE_GROUP"
    echo "  • Upload custom ARM templates to storage container 'arm-templates'"
    echo "  • Review deployment logs in storage container 'deployment-logs'"
    echo
    echo "📖 Documentation: https://docs.microsoft.com/en-us/azure/container-apps/jobs"
    echo
}

# Show usage
show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo
    echo "Deploy automated infrastructure deployment workflows with Azure Container Apps Jobs"
    echo
    echo "Options:"
    echo "  -g, --resource-group NAME     Resource group name (default: $DEFAULT_RESOURCE_GROUP)"
    echo "  -l, --location LOCATION       Azure region (default: $DEFAULT_LOCATION)"
    echo "  -e, --environment NAME        Container Apps environment name (default: $DEFAULT_CONTAINER_APPS_ENV)"
    echo "  -j, --job-name NAME           Container Apps job name (default: $DEFAULT_JOB_NAME)"
    echo "  -k, --key-vault NAME          Key Vault name (default: auto-generated)"
    echo "  -s, --storage-account NAME    Storage account name (default: auto-generated)"
    echo "  -n, --dry-run                 Show what would be deployed without making changes"
    echo "  -y, --yes                     Skip confirmation prompts"
    echo "  -h, --help                    Show this help message"
    echo
    echo "Environment Variables:"
    echo "  RESOURCE_GROUP                Resource group name"
    echo "  LOCATION                      Azure region"
    echo "  CONTAINER_APPS_ENV            Container Apps environment name"
    echo "  JOB_NAME                      Container Apps job name"
    echo "  KEY_VAULT_NAME                Key Vault name"
    echo "  STORAGE_ACCOUNT               Storage account name"
    echo "  SUBSCRIPTION_ID               Azure subscription ID"
    echo "  DRY_RUN                       Enable dry run mode (true/false)"
    echo "  SKIP_CONFIRMATIONS            Skip confirmation prompts (true/false)"
    echo
    echo "Examples:"
    echo "  $0                            Deploy with default settings"
    echo "  $0 -g my-rg -l westus2       Deploy to specific resource group and location"
    echo "  $0 --dry-run                  Show deployment plan without executing"
    echo "  $0 -y                         Deploy without confirmation prompts"
    echo
}

# Parse command line arguments
parse_arguments() {
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
            -e|--environment)
                CONTAINER_APPS_ENV="$2"
                shift 2
                ;;
            -j|--job-name)
                JOB_NAME="$2"
                shift 2
                ;;
            -k|--key-vault)
                KEY_VAULT_NAME="$2"
                shift 2
                ;;
            -s|--storage-account)
                STORAGE_ACCOUNT="$2"
                shift 2
                ;;
            -n|--dry-run)
                DRY_RUN="true"
                shift
                ;;
            -y|--yes)
                SKIP_CONFIRMATIONS="true"
                shift
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            *)
                error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
}

# Main deployment function
main() {
    # Initialize log file
    echo "Deployment started at $(date)" > "$LOG_FILE"
    
    # Parse command line arguments
    parse_arguments "$@"
    
    # Show banner
    echo "=================================="
    echo "Azure Container Apps Jobs Deployment"
    echo "=================================="
    echo
    
    # Show configuration
    info "Configuration:"
    info "  Resource Group: $RESOURCE_GROUP"
    info "  Location: $LOCATION"
    info "  Container Apps Environment: $CONTAINER_APPS_ENV"
    info "  Job Name: $JOB_NAME"
    info "  Key Vault: $KEY_VAULT_NAME"
    info "  Storage Account: $STORAGE_ACCOUNT"
    info "  Dry Run: $DRY_RUN"
    echo
    
    # Confirmation prompt
    if [[ "$DRY_RUN" != "true" && "$SKIP_CONFIRMATIONS" != "true" ]]; then
        read -p "Continue with deployment? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            info "Deployment cancelled by user"
            exit 0
        fi
    fi
    
    # Execute deployment steps
    validate_prerequisites
    create_resource_group
    create_container_apps_environment
    create_key_vault
    create_storage_account
    create_managed_identity
    assign_rbac_permissions
    create_sample_arm_template
    create_deployment_script
    create_container_apps_job
    create_scheduled_job
    verify_deployment
    test_manual_execution
    display_summary
    
    success "🎉 Deployment completed successfully!"
}

# Handle script interruption
cleanup_on_exit() {
    if [[ $? -ne 0 ]]; then
        error "Deployment failed. Check $LOG_FILE for details."
        echo "To clean up partial deployment, run: ./destroy.sh"
    fi
}

# Set up signal handlers
trap cleanup_on_exit EXIT

# Run main function
main "$@"