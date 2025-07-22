#!/bin/bash

# Azure Blob Storage Lifecycle Management - Deployment Script
# This script deploys the complete infrastructure for automated blob storage lifecycle management
# with Azure Storage Accounts and Azure Monitor

set -e
set -u
set -o pipefail

# Global variables
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_FILE="/tmp/azure-lifecycle-deploy-$(date +%Y%m%d-%H%M%S).log"
readonly BLUE='\033[0;34m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly RED='\033[0;31m'
readonly NC='\033[0m' # No Color

# Configuration with defaults
RESOURCE_GROUP="${RESOURCE_GROUP:-rg-lifecycle-demo}"
LOCATION="${LOCATION:-eastus}"
STORAGE_ACCOUNT="${STORAGE_ACCOUNT:-stlifecycle$(openssl rand -hex 3)}"
LOGIC_APP_NAME="${LOGIC_APP_NAME:-logic-storage-alerts}"
WORKSPACE_NAME="${WORKSPACE_NAME:-law-storage-monitoring}"
DRY_RUN="${DRY_RUN:-false}"
SKIP_SAMPLES="${SKIP_SAMPLES:-false}"

# Functions
log() {
    echo -e "${1}" | tee -a "$LOG_FILE"
}

log_info() {
    log "${BLUE}[INFO]${NC} $1"
}

log_success() {
    log "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    log "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    log "${RED}[ERROR]${NC} $1"
}

show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Deploy Azure Blob Storage Lifecycle Management infrastructure.

Options:
    -g, --resource-group NAME    Resource group name (default: rg-lifecycle-demo)
    -l, --location LOCATION      Azure region (default: eastus)
    -s, --storage-account NAME   Storage account name (default: auto-generated)
    -w, --workspace NAME         Log Analytics workspace name (default: law-storage-monitoring)
    -a, --logic-app NAME         Logic App name (default: logic-storage-alerts)
    --dry-run                    Show what would be deployed without creating resources
    --skip-samples              Skip uploading sample data
    -h, --help                   Show this help message

Environment Variables:
    RESOURCE_GROUP              Resource group name
    LOCATION                    Azure region
    STORAGE_ACCOUNT             Storage account name
    LOGIC_APP_NAME              Logic App name
    WORKSPACE_NAME              Log Analytics workspace name
    DRY_RUN                     Enable dry run mode (true/false)
    SKIP_SAMPLES                Skip sample data upload (true/false)

Examples:
    $0                                              # Deploy with defaults
    $0 -g my-rg -l westus2                        # Deploy to specific RG and region
    $0 --dry-run                                   # Show what would be deployed
    $0 --skip-samples                              # Deploy without sample data

EOF
}

check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        log_error "Azure CLI is not installed. Please install it from https://aka.ms/installazurecli"
        exit 1
    fi
    
    # Check if user is logged in to Azure
    if ! az account show &> /dev/null; then
        log_error "You are not logged in to Azure. Please run 'az login' first."
        exit 1
    fi
    
    # Check if openssl is available for random generation
    if ! command -v openssl &> /dev/null; then
        log_error "OpenSSL is not installed. Please install it for unique resource name generation."
        exit 1
    fi
    
    # Validate Azure CLI version
    local az_version
    az_version=$(az version --query '"azure-cli"' -o tsv)
    log_info "Azure CLI version: $az_version"
    
    # Get current subscription info
    local subscription_name
    local subscription_id
    subscription_name=$(az account show --query name -o tsv)
    subscription_id=$(az account show --query id -o tsv)
    log_info "Current subscription: $subscription_name ($subscription_id)"
    
    # Check if location is valid
    if ! az account list-locations --query "[?name=='$LOCATION']" -o tsv | grep -q "$LOCATION"; then
        log_error "Invalid location: $LOCATION"
        log_info "Use 'az account list-locations -o table' to see available locations"
        exit 1
    fi
    
    log_success "Prerequisites check completed successfully"
}

validate_parameters() {
    log_info "Validating parameters..."
    
    # Validate resource group name
    if [[ ! "$RESOURCE_GROUP" =~ ^[a-zA-Z0-9._-]+$ ]]; then
        log_error "Invalid resource group name. Must contain only alphanumeric characters, periods, underscores, and hyphens."
        exit 1
    fi
    
    # Validate storage account name
    if [[ ! "$STORAGE_ACCOUNT" =~ ^[a-z0-9]+$ ]] || [[ ${#STORAGE_ACCOUNT} -lt 3 ]] || [[ ${#STORAGE_ACCOUNT} -gt 24 ]]; then
        log_error "Invalid storage account name. Must be 3-24 characters, lowercase letters and numbers only."
        exit 1
    fi
    
    # Validate workspace name
    if [[ ${#WORKSPACE_NAME} -lt 4 ]] || [[ ${#WORKSPACE_NAME} -gt 63 ]]; then
        log_error "Invalid workspace name. Must be 4-63 characters."
        exit 1
    fi
    
    log_success "Parameter validation completed successfully"
}

check_resource_availability() {
    log_info "Checking resource availability..."
    
    # Check if resource group exists
    if az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        log_warning "Resource group '$RESOURCE_GROUP' already exists"
    fi
    
    # Check if storage account name is available
    local storage_available
    storage_available=$(az storage account check-name --name "$STORAGE_ACCOUNT" --query nameAvailable -o tsv)
    if [[ "$storage_available" != "true" ]]; then
        log_error "Storage account name '$STORAGE_ACCOUNT' is not available"
        exit 1
    fi
    
    log_success "Resource availability check completed"
}

create_resource_group() {
    log_info "Creating resource group: $RESOURCE_GROUP"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would create resource group: $RESOURCE_GROUP in $LOCATION"
        return 0
    fi
    
    if ! az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        az group create \
            --name "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --tags purpose=lifecycle-demo environment=development \
            --output none
        
        log_success "Resource group '$RESOURCE_GROUP' created successfully"
    else
        log_warning "Resource group '$RESOURCE_GROUP' already exists"
    fi
}

create_storage_account() {
    log_info "Creating storage account: $STORAGE_ACCOUNT"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would create storage account: $STORAGE_ACCOUNT"
        return 0
    fi
    
    # Create storage account with lifecycle management support
    az storage account create \
        --name "$STORAGE_ACCOUNT" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --sku Standard_LRS \
        --kind StorageV2 \
        --access-tier Hot \
        --enable-hierarchical-namespace false \
        --tags purpose=lifecycle-demo environment=development \
        --output none
    
    # Wait for storage account to be fully provisioned
    log_info "Waiting for storage account to be fully provisioned..."
    sleep 30
    
    # Enable blob versioning and soft delete
    az storage account blob-service-properties update \
        --account-name "$STORAGE_ACCOUNT" \
        --resource-group "$RESOURCE_GROUP" \
        --enable-versioning true \
        --enable-delete-retention true \
        --delete-retention-days 30 \
        --output none
    
    log_success "Storage account '$STORAGE_ACCOUNT' created with lifecycle management capabilities"
}

create_containers_and_samples() {
    if [[ "$SKIP_SAMPLES" == "true" ]]; then
        log_info "Skipping sample data creation"
        return 0
    fi
    
    log_info "Creating containers and uploading sample data"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would create containers and upload sample data"
        return 0
    fi
    
    # Get storage account key
    local storage_key
    storage_key=$(az storage account keys list \
        --account-name "$STORAGE_ACCOUNT" \
        --resource-group "$RESOURCE_GROUP" \
        --query '[0].value' --output tsv)
    
    # Create containers
    az storage container create \
        --name documents \
        --account-name "$STORAGE_ACCOUNT" \
        --account-key "$storage_key" \
        --public-access off \
        --output none
    
    az storage container create \
        --name logs \
        --account-name "$STORAGE_ACCOUNT" \
        --account-key "$storage_key" \
        --public-access off \
        --output none
    
    # Create sample files
    local temp_dir
    temp_dir=$(mktemp -d)
    
    echo "Sample document content - frequently accessed" > "$temp_dir/document1.txt"
    echo "Application log entry - infrequently accessed" > "$temp_dir/app.log"
    echo "Archive document content - rarely accessed" > "$temp_dir/archive.txt"
    
    # Upload sample files
    az storage blob upload \
        --container-name documents \
        --file "$temp_dir/document1.txt" \
        --name document1.txt \
        --account-name "$STORAGE_ACCOUNT" \
        --account-key "$storage_key" \
        --output none
    
    az storage blob upload \
        --container-name logs \
        --file "$temp_dir/app.log" \
        --name app.log \
        --account-name "$STORAGE_ACCOUNT" \
        --account-key "$storage_key" \
        --output none
    
    # Clean up temporary files
    rm -rf "$temp_dir"
    
    log_success "Containers and sample data created successfully"
}

configure_lifecycle_policy() {
    log_info "Configuring lifecycle management policy"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would configure lifecycle management policy"
        return 0
    fi
    
    # Create lifecycle policy JSON
    local policy_file
    policy_file=$(mktemp)
    
    cat > "$policy_file" << 'EOF'
{
  "rules": [
    {
      "enabled": true,
      "name": "DocumentLifecycle",
      "type": "Lifecycle",
      "definition": {
        "filters": {
          "blobTypes": ["blockBlob"],
          "prefixMatch": ["documents/"]
        },
        "actions": {
          "baseBlob": {
            "tierToCool": {
              "daysAfterModificationGreaterThan": 30
            },
            "tierToArchive": {
              "daysAfterModificationGreaterThan": 90
            },
            "delete": {
              "daysAfterModificationGreaterThan": 365
            }
          }
        }
      }
    },
    {
      "enabled": true,
      "name": "LogLifecycle",
      "type": "Lifecycle",
      "definition": {
        "filters": {
          "blobTypes": ["blockBlob"],
          "prefixMatch": ["logs/"]
        },
        "actions": {
          "baseBlob": {
            "tierToCool": {
              "daysAfterModificationGreaterThan": 7
            },
            "tierToArchive": {
              "daysAfterModificationGreaterThan": 30
            },
            "delete": {
              "daysAfterModificationGreaterThan": 180
            }
          }
        }
      }
    }
  ]
}
EOF
    
    # Apply lifecycle management policy
    az storage account management-policy create \
        --account-name "$STORAGE_ACCOUNT" \
        --resource-group "$RESOURCE_GROUP" \
        --policy "@$policy_file" \
        --output none
    
    # Clean up policy file
    rm -f "$policy_file"
    
    log_success "Lifecycle management policy configured successfully"
}

create_log_analytics_workspace() {
    log_info "Creating Log Analytics workspace: $WORKSPACE_NAME"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would create Log Analytics workspace: $WORKSPACE_NAME"
        return 0
    fi
    
    az monitor log-analytics workspace create \
        --resource-group "$RESOURCE_GROUP" \
        --workspace-name "$WORKSPACE_NAME" \
        --location "$LOCATION" \
        --sku pergb2018 \
        --retention-time 30 \
        --tags purpose=storage-monitoring environment=development \
        --output none
    
    log_success "Log Analytics workspace '$WORKSPACE_NAME' created successfully"
}

configure_diagnostics() {
    log_info "Configuring storage account diagnostics"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would configure storage account diagnostics"
        return 0
    fi
    
    # Get workspace ID
    local workspace_id
    workspace_id=$(az monitor log-analytics workspace show \
        --resource-group "$RESOURCE_GROUP" \
        --workspace-name "$WORKSPACE_NAME" \
        --query id --output tsv)
    
    # Get storage account resource ID
    local storage_account_id
    storage_account_id=$(az storage account show \
        --name "$STORAGE_ACCOUNT" \
        --resource-group "$RESOURCE_GROUP" \
        --query id --output tsv)
    
    # Configure diagnostic settings for blob storage
    az monitor diagnostic-settings create \
        --resource "${storage_account_id}/blobServices/default" \
        --name "BlobStorageMonitoring" \
        --workspace "$workspace_id" \
        --metrics '[
          {
            "category": "Transaction",
            "enabled": true,
            "retentionPolicy": {
              "enabled": true,
              "days": 30
            }
          },
          {
            "category": "Capacity",
            "enabled": true,
            "retentionPolicy": {
              "enabled": true,
              "days": 30
            }
          }
        ]' \
        --logs '[
          {
            "category": "StorageRead",
            "enabled": true,
            "retentionPolicy": {
              "enabled": true,
              "days": 30
            }
          },
          {
            "category": "StorageWrite",
            "enabled": true,
            "retentionPolicy": {
              "enabled": true,
              "days": 30
            }
          }
        ]' \
        --output none
    
    log_success "Storage account diagnostics configured successfully"
}

create_logic_app() {
    log_info "Creating Logic App: $LOGIC_APP_NAME"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would create Logic App: $LOGIC_APP_NAME"
        return 0
    fi
    
    az logic workflow create \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --name "$LOGIC_APP_NAME" \
        --tags purpose=storage-alerts environment=development \
        --output none
    
    log_success "Logic App '$LOGIC_APP_NAME' created successfully"
}

configure_alerts() {
    log_info "Configuring storage cost and capacity alerts"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would configure storage alerts"
        return 0
    fi
    
    # Get storage account resource ID
    local storage_account_id
    storage_account_id=$(az storage account show \
        --name "$STORAGE_ACCOUNT" \
        --resource-group "$RESOURCE_GROUP" \
        --query id --output tsv)
    
    # Create action group for alert notifications
    az monitor action-group create \
        --resource-group "$RESOURCE_GROUP" \
        --name "StorageAlertsGroup" \
        --short-name "StorageAlerts" \
        --tags purpose=storage-alerts environment=development \
        --output none
    
    # Create metric alert for storage capacity
    az monitor metrics alert create \
        --name "HighStorageCapacity" \
        --resource-group "$RESOURCE_GROUP" \
        --scopes "$storage_account_id" \
        --condition "avg UsedCapacity > 1000000000" \
        --description "Alert when storage capacity exceeds 1GB" \
        --evaluation-frequency 5m \
        --window-size 15m \
        --severity 2 \
        --action-groups "StorageAlertsGroup" \
        --output none
    
    # Create metric alert for transaction costs
    az monitor metrics alert create \
        --name "HighTransactionCount" \
        --resource-group "$RESOURCE_GROUP" \
        --scopes "$storage_account_id" \
        --condition "avg Transactions > 1000" \
        --description "Alert when transaction count is high" \
        --evaluation-frequency 5m \
        --window-size 15m \
        --severity 3 \
        --action-groups "StorageAlertsGroup" \
        --output none
    
    log_success "Storage cost and capacity alerts configured successfully"
}

validate_deployment() {
    log_info "Validating deployment..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would validate deployment"
        return 0
    fi
    
    # Check resource group exists
    if ! az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        log_error "Resource group validation failed"
        return 1
    fi
    
    # Check storage account exists
    if ! az storage account show --name "$STORAGE_ACCOUNT" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        log_error "Storage account validation failed"
        return 1
    fi
    
    # Check lifecycle policy exists
    if ! az storage account management-policy show --account-name "$STORAGE_ACCOUNT" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        log_error "Lifecycle policy validation failed"
        return 1
    fi
    
    # Check Log Analytics workspace exists
    if ! az monitor log-analytics workspace show --resource-group "$RESOURCE_GROUP" --workspace-name "$WORKSPACE_NAME" &> /dev/null; then
        log_error "Log Analytics workspace validation failed"
        return 1
    fi
    
    # Check Logic App exists
    if ! az logic workflow show --resource-group "$RESOURCE_GROUP" --name "$LOGIC_APP_NAME" &> /dev/null; then
        log_error "Logic App validation failed"
        return 1
    fi
    
    log_success "Deployment validation completed successfully"
}

show_deployment_summary() {
    log_info "Deployment Summary"
    echo "===================="
    echo "Resource Group: $RESOURCE_GROUP"
    echo "Location: $LOCATION"
    echo "Storage Account: $STORAGE_ACCOUNT"
    echo "Log Analytics Workspace: $WORKSPACE_NAME"
    echo "Logic App: $LOGIC_APP_NAME"
    echo "Lifecycle Policy: Configured"
    echo "Monitoring: Enabled"
    echo "Alerts: Configured"
    echo "Log File: $LOG_FILE"
    echo "===================="
    
    if [[ "$DRY_RUN" != "true" ]]; then
        log_info "Access your resources at: https://portal.azure.com"
        log_info "To clean up resources, run: ./destroy.sh -g $RESOURCE_GROUP"
    fi
}

main() {
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
            -s|--storage-account)
                STORAGE_ACCOUNT="$2"
                shift 2
                ;;
            -w|--workspace)
                WORKSPACE_NAME="$2"
                shift 2
                ;;
            -a|--logic-app)
                LOGIC_APP_NAME="$2"
                shift 2
                ;;
            --dry-run)
                DRY_RUN="true"
                shift
                ;;
            --skip-samples)
                SKIP_SAMPLES="true"
                shift
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
    
    # Initialize logging
    log_info "Starting Azure Blob Storage Lifecycle Management deployment"
    log_info "Log file: $LOG_FILE"
    
    # Execute deployment steps
    check_prerequisites
    validate_parameters
    
    if [[ "$DRY_RUN" != "true" ]]; then
        check_resource_availability
    fi
    
    create_resource_group
    create_storage_account
    create_containers_and_samples
    configure_lifecycle_policy
    create_log_analytics_workspace
    configure_diagnostics
    create_logic_app
    configure_alerts
    
    if [[ "$DRY_RUN" != "true" ]]; then
        validate_deployment
    fi
    
    show_deployment_summary
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "Dry run completed successfully. No resources were created."
    else
        log_success "Deployment completed successfully!"
    fi
}

# Error handling
trap 'log_error "Deployment failed at line $LINENO. Check $LOG_FILE for details."' ERR

# Run main function
main "$@"