#!/bin/bash

#####################################################################
# Simple File Backup Automation Deployment Script
# Azure Recipe: simple-file-backup-logic-apps-storage
# 
# This script deploys Logic Apps and Storage resources for automated
# file backup using Azure serverless services.
#####################################################################

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

error() {
    echo -e "${RED}[ERROR] $1${NC}" >&2
}

success() {
    echo -e "${GREEN}[SUCCESS] $1${NC}"
}

warning() {
    echo -e "${YELLOW}[WARNING] $1${NC}"
}

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_NAME="simple-file-backup"
DEFAULT_LOCATION="eastus"

# Help function
show_help() {
    cat << EOF
Usage: $0 [OPTIONS]

Deploy Azure Logic Apps and Storage for automated file backup.

OPTIONS:
    -g, --resource-group    Resource group name (optional, will generate if not provided)
    -l, --location         Azure region (default: ${DEFAULT_LOCATION})
    -s, --suffix           Custom suffix for resource names (optional, will generate if not provided)
    -d, --dry-run          Show what would be deployed without actually deploying
    -h, --help             Show this help message
    --skip-checks          Skip prerequisite checks
    --verbose              Enable verbose logging

EXAMPLES:
    $0                                          # Deploy with generated names
    $0 -g "rg-backup-prod" -l "westus2"        # Deploy to specific resource group and region
    $0 -s "demo01" --dry-run                   # Show deployment plan with custom suffix
    $0 --verbose                               # Deploy with detailed logging

ENVIRONMENT VARIABLES:
    AZURE_RESOURCE_GROUP    Override resource group name
    AZURE_LOCATION          Override deployment region
    AZURE_SUBSCRIPTION_ID   Target subscription ID

EOF
}

# Default values
RESOURCE_GROUP=""
LOCATION="${DEFAULT_LOCATION}"
SUFFIX=""
DRY_RUN=false
SKIP_CHECKS=false
VERBOSE=false

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
        -s|--suffix)
            SUFFIX="$2"
            shift 2
            ;;
        -d|--dry-run)
            DRY_RUN=true
            shift
            ;;
        --skip-checks)
            SKIP_CHECKS=true
            shift
            ;;
        --verbose)
            VERBOSE=true
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Enable verbose logging if requested
if [[ "$VERBOSE" == "true" ]]; then
    set -x
fi

# Use environment variables if set and not overridden
RESOURCE_GROUP="${RESOURCE_GROUP:-${AZURE_RESOURCE_GROUP:-}}"
LOCATION="${LOCATION:-${AZURE_LOCATION:-${DEFAULT_LOCATION}}}"

# Generate suffix if not provided
if [[ -z "$SUFFIX" ]]; then
    SUFFIX=$(openssl rand -hex 3 2>/dev/null || echo "$(date +%s | tail -c 6)")
fi

# Generate resource group name if not provided
if [[ -z "$RESOURCE_GROUP" ]]; then
    RESOURCE_GROUP="rg-backup-${SUFFIX}"
fi

# Set resource names
STORAGE_ACCOUNT="stbackup${SUFFIX}"
LOGIC_APP="la-backup-${SUFFIX}"
CONTAINER_NAME="backup-files"

log "Starting deployment of Simple File Backup Automation"
log "Resource Group: ${RESOURCE_GROUP}"
log "Location: ${LOCATION}"
log "Storage Account: ${STORAGE_ACCOUNT}"
log "Logic App: ${LOGIC_APP}"
log "Container: ${CONTAINER_NAME}"

if [[ "$DRY_RUN" == "true" ]]; then
    warning "DRY RUN MODE - No resources will be created"
fi

# Prerequisites check function
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        error "Azure CLI is not installed. Please install it from https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
        exit 1
    fi
    
    # Check Azure CLI version
    AZ_VERSION=$(az version --query '"azure-cli"' -o tsv 2>/dev/null || echo "unknown")
    log "Azure CLI version: ${AZ_VERSION}"
    
    # Check if logged into Azure
    if ! az account show &> /dev/null; then
        error "Not logged into Azure. Please run 'az login' first."
        exit 1
    fi
    
    # Get current subscription
    SUBSCRIPTION_ID=$(az account show --query id --output tsv)
    SUBSCRIPTION_NAME=$(az account show --query name --output tsv)
    log "Current subscription: ${SUBSCRIPTION_NAME} (${SUBSCRIPTION_ID})"
    
    # Check if Logic Apps extension is available
    if ! az extension list --query "[?name=='logic']" | grep -q "logic"; then
        log "Installing Azure Logic Apps CLI extension..."
        if [[ "$DRY_RUN" == "false" ]]; then
            az extension add --name logic --upgrade 2>/dev/null || {
                warning "Failed to install Logic Apps extension. Continuing without it."
            }
        fi
    fi
    
    # Validate location
    if ! az account list-locations --query "[?name=='${LOCATION}']" | grep -q "${LOCATION}"; then
        error "Invalid location: ${LOCATION}"
        log "Available locations: $(az account list-locations --query '[].name' -o tsv | tr '\n' ' ')"
        exit 1
    fi
    
    # Check resource providers
    log "Checking required resource providers..."
    REQUIRED_PROVIDERS=("Microsoft.Storage" "Microsoft.Logic" "Microsoft.Web")
    
    for provider in "${REQUIRED_PROVIDERS[@]}"; do
        STATUS=$(az provider show --namespace "$provider" --query "registrationState" -o tsv 2>/dev/null || echo "NotFound")
        if [[ "$STATUS" != "Registered" ]]; then
            warning "Resource provider ${provider} is not registered (Status: ${STATUS})"
            if [[ "$DRY_RUN" == "false" ]]; then
                log "Registering ${provider}..."
                az provider register --namespace "$provider" --wait
            fi
        fi
    done
    
    success "Prerequisites check completed"
}

# Validate resource names function
validate_names() {
    log "Validating resource names..."
    
    # Validate storage account name (3-24 chars, lowercase letters and numbers only)
    if ! [[ "$STORAGE_ACCOUNT" =~ ^[a-z0-9]{3,24}$ ]]; then
        error "Invalid storage account name: ${STORAGE_ACCOUNT}"
        error "Storage account name must be 3-24 characters, lowercase letters and numbers only"
        exit 1
    fi
    
    # Check if storage account name is available
    if [[ "$DRY_RUN" == "false" ]]; then
        if ! az storage account check-name --name "$STORAGE_ACCOUNT" --query "nameAvailable" -o tsv | grep -q "true"; then
            error "Storage account name '${STORAGE_ACCOUNT}' is not available"
            SUGGESTED_NAME="stbackup$(openssl rand -hex 4)"
            error "Try using a different suffix or use: ${SUGGESTED_NAME}"
            exit 1
        fi
    fi
    
    success "Resource names validation completed"
}

# Create resource group function
create_resource_group() {
    log "Creating resource group: ${RESOURCE_GROUP}"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would create resource group: ${RESOURCE_GROUP} in ${LOCATION}"
        return 0
    fi
    
    # Check if resource group exists
    if az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        warning "Resource group ${RESOURCE_GROUP} already exists"
        return 0
    fi
    
    az group create \
        --name "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --tags purpose=backup environment=demo project=file-automation created_by=script created_date="$(date -u +%Y-%m-%d)" \
        --output table
    
    success "Resource group created: ${RESOURCE_GROUP}"
}

# Create storage account function
create_storage_account() {
    log "Creating storage account: ${STORAGE_ACCOUNT}"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would create storage account: ${STORAGE_ACCOUNT}"
        log "[DRY RUN] Configuration: Standard_LRS, Cool tier, TLS 1.2 minimum"
        return 0
    fi
    
    # Check if storage account already exists
    if az storage account show --name "$STORAGE_ACCOUNT" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        warning "Storage account ${STORAGE_ACCOUNT} already exists"
        return 0
    fi
    
    az storage account create \
        --name "$STORAGE_ACCOUNT" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --sku Standard_LRS \
        --kind StorageV2 \
        --access-tier Cool \
        --allow-blob-public-access false \
        --min-tls-version TLS1_2 \
        --tags purpose=backup environment=demo created_by=script \
        --output table
    
    success "Storage account created with security features enabled"
}

# Create storage container function
create_storage_container() {
    log "Creating storage container: ${CONTAINER_NAME}"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would create container: ${CONTAINER_NAME} with private access"
        return 0
    fi
    
    # Check if container already exists
    if az storage container show --name "$CONTAINER_NAME" --account-name "$STORAGE_ACCOUNT" &> /dev/null; then
        warning "Container ${CONTAINER_NAME} already exists"
        return 0
    fi
    
    az storage container create \
        --name "$CONTAINER_NAME" \
        --account-name "$STORAGE_ACCOUNT" \
        --resource-group "$RESOURCE_GROUP" \
        --public-access off \
        --metadata purpose=backup created="$(date -u +%Y-%m-%d)" \
        --output table
    
    success "Backup container created: ${CONTAINER_NAME}"
}

# Create Logic Apps workflow function
create_logic_app() {
    log "Creating Logic Apps workflow: ${LOGIC_APP}"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would create Logic Apps workflow: ${LOGIC_APP}"
        log "[DRY RUN] Would configure daily recurrence at 2:00 AM EST"
        return 0
    fi
    
    # Check if Logic App already exists
    if az logic workflow show --resource-group "$RESOURCE_GROUP" --name "$LOGIC_APP" &> /dev/null; then
        warning "Logic App ${LOGIC_APP} already exists"
        return 0
    fi
    
    # Create workflow definition file
    WORKFLOW_FILE="${SCRIPT_DIR}/workflow-definition.json"
    cat > "$WORKFLOW_FILE" << EOF
{
    "definition": {
        "\$schema": "https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#",
        "contentVersion": "1.0.0.0",
        "parameters": {},
        "triggers": {
            "Recurrence": {
                "recurrence": {
                    "frequency": "Day",
                    "interval": 1,
                    "schedule": {
                        "hours": ["2"],
                        "minutes": [0]
                    },
                    "timeZone": "Eastern Standard Time"
                },
                "type": "Recurrence"
            }
        },
        "actions": {
            "Initialize_backup_status": {
                "type": "InitializeVariable",
                "inputs": {
                    "variables": [
                        {
                            "name": "BackupStatus",
                            "type": "String",
                            "value": "Starting backup process"
                        }
                    ]
                },
                "runAfter": {}
            },
            "Create_backup_log": {
                "type": "Http",
                "inputs": {
                    "method": "PUT",
                    "uri": "https://${STORAGE_ACCOUNT}.blob.core.windows.net/${CONTAINER_NAME}/backup-log-@{formatDateTime(utcNow(), 'yyyy-MM-dd-HH-mm')}.txt",
                    "headers": {
                        "x-ms-blob-type": "BlockBlob",
                        "Content-Type": "text/plain"
                    },
                    "body": "Backup process initiated at @{utcNow()}"
                },
                "runAfter": {
                    "Initialize_backup_status": ["Succeeded"]
                }
            }
        },
        "outputs": {}
    }
}
EOF
    
    # Create Logic Apps workflow
    az logic workflow create \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --name "$LOGIC_APP" \
        --definition "@${WORKFLOW_FILE}" \
        --tags purpose=backup environment=demo automation=file-backup created_by=script \
        --output table
    
    # Clean up temporary file
    rm -f "$WORKFLOW_FILE"
    
    success "Logic Apps workflow created: ${LOGIC_APP}"
}

# Enable Logic Apps workflow function
enable_logic_app() {
    log "Enabling Logic Apps workflow"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would enable Logic Apps workflow"
        return 0
    fi
    
    az logic workflow update \
        --resource-group "$RESOURCE_GROUP" \
        --name "$LOGIC_APP" \
        --state Enabled \
        --output table
    
    success "Logic Apps workflow enabled for scheduled execution"
}

# Validate deployment function
validate_deployment() {
    log "Validating deployment..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would validate all resources"
        return 0
    fi
    
    # Check resource group
    if ! az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        error "Resource group validation failed"
        return 1
    fi
    
    # Check storage account
    STORAGE_STATE=$(az storage account show --name "$STORAGE_ACCOUNT" --resource-group "$RESOURCE_GROUP" --query "provisioningState" -o tsv 2>/dev/null || echo "NotFound")
    if [[ "$STORAGE_STATE" != "Succeeded" ]]; then
        error "Storage account validation failed (State: ${STORAGE_STATE})"
        return 1
    fi
    
    # Check container
    if ! az storage container show --name "$CONTAINER_NAME" --account-name "$STORAGE_ACCOUNT" &> /dev/null; then
        error "Storage container validation failed"
        return 1
    fi
    
    # Check Logic App
    LOGIC_STATE=$(az logic workflow show --resource-group "$RESOURCE_GROUP" --name "$LOGIC_APP" --query "state" -o tsv 2>/dev/null || echo "NotFound")
    if [[ "$LOGIC_STATE" != "Enabled" ]]; then
        error "Logic App validation failed (State: ${LOGIC_STATE})"
        return 1
    fi
    
    success "All resources validated successfully"
}

# Create test file function
create_test_file() {
    log "Creating test backup file..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would create test backup file"
        return 0
    fi
    
    # Create test file
    TEST_FILE="${SCRIPT_DIR}/test-backup.txt"
    echo "Test backup file created at $(date)" > "$TEST_FILE"
    
    # Upload test file
    az storage blob upload \
        --file "$TEST_FILE" \
        --container-name "$CONTAINER_NAME" \
        --name "manual-test-backup-$(date +%Y%m%d-%H%M%S).txt" \
        --account-name "$STORAGE_ACCOUNT" \
        --resource-group "$RESOURCE_GROUP" \
        --output table
    
    # Clean up local test file
    rm -f "$TEST_FILE"
    
    success "Test file uploaded successfully to verify storage access"
}

# Display deployment info function
display_deployment_info() {
    log "Deployment Summary"
    echo "===================="
    echo "Resource Group: ${RESOURCE_GROUP}"
    echo "Location: ${LOCATION}"
    echo "Storage Account: ${STORAGE_ACCOUNT}"
    echo "Logic App: ${LOGIC_APP}"
    echo "Container: ${CONTAINER_NAME}"
    echo ""
    
    if [[ "$DRY_RUN" == "false" ]]; then
        echo "Next Steps:"
        echo "1. Configure Logic Apps workflow with specific file sources"
        echo "2. Set up monitoring and alerts for backup failures"
        echo "3. Review and customize the backup schedule as needed"
        echo "4. Test the workflow by manually triggering it from Azure portal"
        echo ""
        echo "Azure Portal Links:"
        echo "- Resource Group: https://portal.azure.com/#@/resource/subscriptions/${AZURE_SUBSCRIPTION_ID:-$(az account show --query id -o tsv)}/resourceGroups/${RESOURCE_GROUP}"
        echo "- Logic App: https://portal.azure.com/#@/resource/subscriptions/${AZURE_SUBSCRIPTION_ID:-$(az account show --query id -o tsv)}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.Logic/workflows/${LOGIC_APP}"
        echo "- Storage Account: https://portal.azure.com/#@/resource/subscriptions/${AZURE_SUBSCRIPTION_ID:-$(az account show --query id -o tsv)}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.Storage/storageAccounts/${STORAGE_ACCOUNT}"
    fi
}

# Cleanup function for script interruption
cleanup() {
    log "Script interrupted. Cleaning up temporary files..."
    rm -f "${SCRIPT_DIR}/workflow-definition.json"
    rm -f "${SCRIPT_DIR}/test-backup.txt"
}

# Set trap for cleanup
trap cleanup EXIT INT TERM

# Main execution
main() {
    log "Simple File Backup Automation Deployment Script"
    log "================================================"
    
    # Run prerequisite checks unless skipped
    if [[ "$SKIP_CHECKS" == "false" ]]; then
        check_prerequisites
    else
        warning "Skipping prerequisite checks"
    fi
    
    # Validate resource names
    validate_names
    
    # Execute deployment steps
    create_resource_group
    create_storage_account
    create_storage_container
    create_logic_app
    enable_logic_app
    
    # Validate deployment
    validate_deployment
    
    # Create test file
    create_test_file
    
    # Display summary
    display_deployment_info
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY RUN COMPLETED - No resources were created"
    else
        success "Deployment completed successfully!"
        success "Your automated file backup system is now ready to use."
    fi
}

# Execute main function
main "$@"