#!/bin/bash

# Azure Compliance Reporting Deployment Script
# Deploys Azure Confidential Ledger and Logic Apps for automated compliance reporting

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/deploy.log"
RESOURCE_GROUP_PREFIX="rg-compliance"
LOCATION="eastus"
SUBSCRIPTION_ID=""
DRY_RUN=false

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${1}" | tee -a "${LOG_FILE}"
}

# Error handling
error_exit() {
    log "${RED}ERROR: ${1}${NC}"
    cleanup_on_error
    exit 1
}

# Success message
success() {
    log "${GREEN}✅ ${1}${NC}"
}

# Warning message
warning() {
    log "${YELLOW}⚠️  ${1}${NC}"
}

# Info message
info() {
    log "${BLUE}ℹ️  ${1}${NC}"
}

# Cleanup function for error conditions
cleanup_on_error() {
    warning "Deployment failed. Resources may be partially created."
    warning "Run ./destroy.sh to clean up any created resources."
}

# Display usage information
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

OPTIONS:
    -h, --help              Show this help message
    -d, --dry-run          Show what would be deployed without actually deploying
    -l, --location LOCATION Set Azure region (default: eastus)
    -s, --subscription-id ID Set Azure subscription ID
    -v, --verbose          Enable verbose logging

EXAMPLES:
    $0                                          # Deploy with defaults
    $0 --dry-run                               # Preview deployment
    $0 --location westus2                     # Deploy to West US 2
    $0 --subscription-id 12345678-1234-1234-1234-123456789012

PREREQUISITES:
    - Azure CLI installed and configured
    - Appropriate Azure permissions
    - Subscription access to Azure Confidential Ledger

EOF
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                usage
                exit 0
                ;;
            -d|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -l|--location)
                LOCATION="$2"
                shift 2
                ;;
            -s|--subscription-id)
                SUBSCRIPTION_ID="$2"
                shift 2
                ;;
            -v|--verbose)
                set -x
                shift
                ;;
            *)
                error_exit "Unknown option: $1"
                ;;
        esac
    done
}

# Check prerequisites
check_prerequisites() {
    info "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        error_exit "Azure CLI is not installed. Please install it first."
    fi
    
    # Check if logged in to Azure
    if ! az account show &> /dev/null; then
        error_exit "Not logged in to Azure. Please run 'az login' first."
    fi
    
    # Get subscription ID if not provided
    if [[ -z "${SUBSCRIPTION_ID}" ]]; then
        SUBSCRIPTION_ID=$(az account show --query id --output tsv)
        info "Using subscription: ${SUBSCRIPTION_ID}"
    else
        az account set --subscription "${SUBSCRIPTION_ID}"
    fi
    
    # Check if required providers are registered
    info "Checking Azure resource providers..."
    
    providers=(
        "Microsoft.ConfidentialLedger"
        "Microsoft.Logic"
        "Microsoft.Storage"
        "Microsoft.Monitor"
        "Microsoft.Insights"
        "Microsoft.EventGrid"
    )
    
    for provider in "${providers[@]}"; do
        status=$(az provider show --namespace "${provider}" --query "registrationState" --output tsv)
        if [[ "${status}" != "Registered" ]]; then
            info "Registering provider: ${provider}"
            if [[ "${DRY_RUN}" == "false" ]]; then
                az provider register --namespace "${provider}" --wait
            fi
        fi
    done
    
    # Check for required features
    info "Checking required Azure features..."
    
    # Check if Confidential Ledger is available in the region
    available_regions=$(az provider show --namespace Microsoft.ConfidentialLedger --query "resourceTypes[?resourceType=='ledgers'].locations[]" --output tsv)
    if [[ ! "${available_regions}" =~ "${LOCATION}" ]]; then
        warning "Azure Confidential Ledger may not be available in ${LOCATION}. Available regions: ${available_regions}"
    fi
    
    success "Prerequisites check completed"
}

# Generate unique resource names
generate_resource_names() {
    # Generate unique suffix
    RANDOM_SUFFIX=$(openssl rand -hex 3 2>/dev/null || echo "$(date +%s)" | tail -c 6)
    
    # Set resource names
    RESOURCE_GROUP="${RESOURCE_GROUP_PREFIX}-${RANDOM_SUFFIX}"
    ACL_NAME="acl-${RANDOM_SUFFIX}"
    STORAGE_ACCOUNT="stcompliance${RANDOM_SUFFIX}"
    LOGIC_APP_NAME="la-compliance-${RANDOM_SUFFIX}"
    WORKSPACE_NAME="law-compliance-${RANDOM_SUFFIX}"
    ACTION_GROUP_NAME="ag-compliance-${RANDOM_SUFFIX}"
    
    info "Generated resource names:"
    info "  Resource Group: ${RESOURCE_GROUP}"
    info "  Confidential Ledger: ${ACL_NAME}"
    info "  Storage Account: ${STORAGE_ACCOUNT}"
    info "  Logic App: ${LOGIC_APP_NAME}"
    info "  Log Analytics Workspace: ${WORKSPACE_NAME}"
    info "  Action Group: ${ACTION_GROUP_NAME}"
}

# Create resource group
create_resource_group() {
    info "Creating resource group: ${RESOURCE_GROUP}"
    
    if [[ "${DRY_RUN}" == "false" ]]; then
        az group create \
            --name "${RESOURCE_GROUP}" \
            --location "${LOCATION}" \
            --tags purpose=compliance environment=demo \
            --output none
    fi
    
    success "Resource group created successfully"
}

# Create Azure Confidential Ledger
create_confidential_ledger() {
    info "Creating Azure Confidential Ledger: ${ACL_NAME}"
    
    if [[ "${DRY_RUN}" == "false" ]]; then
        # Create Confidential Ledger
        az confidentialledger create \
            --name "${ACL_NAME}" \
            --resource-group "${RESOURCE_GROUP}" \
            --location "${LOCATION}" \
            --ledger-type Private \
            --output none
        
        # Wait for deployment to complete
        info "Waiting for Confidential Ledger deployment to complete..."
        az confidentialledger wait \
            --name "${ACL_NAME}" \
            --resource-group "${RESOURCE_GROUP}" \
            --created
        
        # Get ledger endpoint
        LEDGER_ENDPOINT=$(az confidentialledger show \
            --name "${ACL_NAME}" \
            --resource-group "${RESOURCE_GROUP}" \
            --query "properties.ledgerUri" \
            --output tsv)
        
        info "Ledger endpoint: ${LEDGER_ENDPOINT}"
        echo "LEDGER_ENDPOINT=${LEDGER_ENDPOINT}" >> "${SCRIPT_DIR}/.env"
    fi
    
    success "Confidential Ledger created successfully"
}

# Create Log Analytics workspace
create_log_analytics_workspace() {
    info "Creating Log Analytics workspace: ${WORKSPACE_NAME}"
    
    if [[ "${DRY_RUN}" == "false" ]]; then
        az monitor log-analytics workspace create \
            --name "${WORKSPACE_NAME}" \
            --resource-group "${RESOURCE_GROUP}" \
            --location "${LOCATION}" \
            --output none
        
        # Get workspace ID
        WORKSPACE_ID=$(az monitor log-analytics workspace show \
            --name "${WORKSPACE_NAME}" \
            --resource-group "${RESOURCE_GROUP}" \
            --query id \
            --output tsv)
        
        echo "WORKSPACE_ID=${WORKSPACE_ID}" >> "${SCRIPT_DIR}/.env"
    fi
    
    success "Log Analytics workspace created successfully"
}

# Create storage account
create_storage_account() {
    info "Creating storage account: ${STORAGE_ACCOUNT}"
    
    if [[ "${DRY_RUN}" == "false" ]]; then
        # Create storage account
        az storage account create \
            --name "${STORAGE_ACCOUNT}" \
            --resource-group "${RESOURCE_GROUP}" \
            --location "${LOCATION}" \
            --sku Standard_LRS \
            --encryption-services blob \
            --https-only true \
            --min-tls-version TLS1_2 \
            --allow-blob-public-access false \
            --output none
        
        # Enable blob versioning
        az storage account blob-service-properties update \
            --account-name "${STORAGE_ACCOUNT}" \
            --enable-versioning true \
            --output none
        
        # Create container for compliance reports
        az storage container create \
            --name compliance-reports \
            --account-name "${STORAGE_ACCOUNT}" \
            --auth-mode login \
            --public-access off \
            --output none
    fi
    
    success "Storage account created successfully"
}

# Create action group
create_action_group() {
    info "Creating action group: ${ACTION_GROUP_NAME}"
    
    if [[ "${DRY_RUN}" == "false" ]]; then
        az monitor action-group create \
            --name "${ACTION_GROUP_NAME}" \
            --resource-group "${RESOURCE_GROUP}" \
            --short-name compliance \
            --output none
    fi
    
    success "Action group created successfully"
}

# Create Logic App
create_logic_app() {
    info "Creating Logic App: ${LOGIC_APP_NAME}"
    
    if [[ "${DRY_RUN}" == "false" ]]; then
        # Create Logic App with system-assigned managed identity
        az logic workflow create \
            --name "${LOGIC_APP_NAME}" \
            --resource-group "${RESOURCE_GROUP}" \
            --location "${LOCATION}" \
            --definition '{"definition":{"$schema":"https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#","actions":{},"contentVersion":"1.0.0.0","outputs":{},"triggers":{}}}' \
            --output none
        
        # Enable system-assigned managed identity
        az logic workflow identity assign \
            --name "${LOGIC_APP_NAME}" \
            --resource-group "${RESOURCE_GROUP}" \
            --output none
        
        # Get Logic App identity
        LOGIC_APP_IDENTITY=$(az logic workflow identity show \
            --name "${LOGIC_APP_NAME}" \
            --resource-group "${RESOURCE_GROUP}" \
            --query principalId \
            --output tsv)
        
        echo "LOGIC_APP_IDENTITY=${LOGIC_APP_IDENTITY}" >> "${SCRIPT_DIR}/.env"
    fi
    
    success "Logic App created successfully"
}

# Configure RBAC permissions
configure_rbac() {
    info "Configuring RBAC permissions..."
    
    if [[ "${DRY_RUN}" == "false" ]]; then
        # Grant Logic App access to Confidential Ledger
        info "Granting Logic App access to Confidential Ledger..."
        az role assignment create \
            --assignee "${LOGIC_APP_IDENTITY}" \
            --role "Confidential Ledger Contributor" \
            --scope "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.ConfidentialLedger/ledgers/${ACL_NAME}" \
            --output none
        
        # Grant Logic App access to Storage Account
        info "Granting Logic App access to Storage Account..."
        az role assignment create \
            --assignee "${LOGIC_APP_IDENTITY}" \
            --role "Storage Blob Data Contributor" \
            --scope "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.Storage/storageAccounts/${STORAGE_ACCOUNT}" \
            --output none
        
        # Grant Logic App access to Monitor
        info "Granting Logic App access to Monitor..."
        az role assignment create \
            --assignee "${LOGIC_APP_IDENTITY}" \
            --role "Monitoring Reader" \
            --resource-group "${RESOURCE_GROUP}" \
            --output none
        
        # Allow some time for role assignments to propagate
        sleep 30
    fi
    
    success "RBAC permissions configured successfully"
}

# Create alert rules
create_alert_rules() {
    info "Creating compliance alert rules..."
    
    if [[ "${DRY_RUN}" == "false" ]]; then
        # Create sample compliance alert rule
        az monitor metrics alert create \
            --name "alert-compliance-violation" \
            --resource-group "${RESOURCE_GROUP}" \
            --scopes "${WORKSPACE_ID}" \
            --condition "avg Percentage CPU > 90" \
            --window-size 5m \
            --evaluation-frequency 1m \
            --action "${ACTION_GROUP_NAME}" \
            --description "Compliance threshold violation detected" \
            --output none
        
        # Create log-based alert for security events
        az monitor scheduled-query rule create \
            --name "alert-security-events" \
            --resource-group "${RESOURCE_GROUP}" \
            --location "${LOCATION}" \
            --action "${ACTION_GROUP_NAME}" \
            --condition 'count > 5' \
            --data-source "${WORKSPACE_ID}" \
            --query 'SecurityEvent | where EventID == 4625' \
            --output none || warning "Security event alert may require custom configuration"
    fi
    
    success "Alert rules created successfully"
}

# Update Logic App workflow
update_logic_app_workflow() {
    info "Updating Logic App workflow..."
    
    if [[ "${DRY_RUN}" == "false" ]]; then
        # Create workflow definition
        WORKFLOW_DEFINITION=$(cat << EOF
{
  "definition": {
    "\$schema": "https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#",
    "contentVersion": "1.0.0.0",
    "triggers": {
      "When_Alert_Triggered": {
        "type": "Request",
        "kind": "Http"
      }
    },
    "actions": {
      "Record_to_Ledger": {
        "type": "Http",
        "inputs": {
          "method": "POST",
          "uri": "${LEDGER_ENDPOINT}/app/transactions",
          "headers": {
            "Content-Type": "application/json"
          },
          "body": {
            "contents": "@{triggerBody()}"
          }
        }
      },
      "Generate_Report": {
        "type": "Compose",
        "inputs": {
          "timestamp": "@{utcNow()}",
          "alertData": "@{triggerBody()}",
          "ledgerResponse": "@{body('Record_to_Ledger')}"
        },
        "runAfter": {
          "Record_to_Ledger": ["Succeeded"]
        }
      }
    }
  }
}
EOF
        )
        
        # Update Logic App with workflow
        az logic workflow update \
            --name "${LOGIC_APP_NAME}" \
            --resource-group "${RESOURCE_GROUP}" \
            --definition "${WORKFLOW_DEFINITION}" \
            --output none
        
        # Get Logic App trigger URL
        TRIGGER_URL=$(az logic workflow show \
            --name "${LOGIC_APP_NAME}" \
            --resource-group "${RESOURCE_GROUP}" \
            --query "accessEndpoint" \
            --output tsv)
        
        echo "TRIGGER_URL=${TRIGGER_URL}" >> "${SCRIPT_DIR}/.env"
    fi
    
    success "Logic App workflow updated successfully"
}

# Save deployment information
save_deployment_info() {
    info "Saving deployment information..."
    
    cat > "${SCRIPT_DIR}/deployment-info.json" << EOF
{
  "deploymentDate": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "subscriptionId": "${SUBSCRIPTION_ID}",
  "resourceGroup": "${RESOURCE_GROUP}",
  "location": "${LOCATION}",
  "resources": {
    "confidentialLedger": "${ACL_NAME}",
    "storageAccount": "${STORAGE_ACCOUNT}",
    "logicApp": "${LOGIC_APP_NAME}",
    "logAnalyticsWorkspace": "${WORKSPACE_NAME}",
    "actionGroup": "${ACTION_GROUP_NAME}"
  }
}
EOF
    
    success "Deployment information saved to deployment-info.json"
}

# Validate deployment
validate_deployment() {
    info "Validating deployment..."
    
    if [[ "${DRY_RUN}" == "false" ]]; then
        # Check Confidential Ledger status
        ACL_STATUS=$(az confidentialledger show \
            --name "${ACL_NAME}" \
            --resource-group "${RESOURCE_GROUP}" \
            --query "properties.provisioningState" \
            --output tsv)
        
        if [[ "${ACL_STATUS}" == "Succeeded" ]]; then
            success "Confidential Ledger is operational"
        else
            warning "Confidential Ledger status: ${ACL_STATUS}"
        fi
        
        # Check Storage Account
        STORAGE_STATUS=$(az storage account show \
            --name "${STORAGE_ACCOUNT}" \
            --resource-group "${RESOURCE_GROUP}" \
            --query "provisioningState" \
            --output tsv)
        
        if [[ "${STORAGE_STATUS}" == "Succeeded" ]]; then
            success "Storage Account is operational"
        else
            warning "Storage Account status: ${STORAGE_STATUS}"
        fi
        
        # Check Logic App
        LOGIC_APP_STATUS=$(az logic workflow show \
            --name "${LOGIC_APP_NAME}" \
            --resource-group "${RESOURCE_GROUP}" \
            --query "state" \
            --output tsv)
        
        if [[ "${LOGIC_APP_STATUS}" == "Enabled" ]]; then
            success "Logic App is operational"
        else
            warning "Logic App status: ${LOGIC_APP_STATUS}"
        fi
    fi
    
    success "Deployment validation completed"
}

# Main deployment function
main() {
    # Initialize log file
    echo "=== Azure Compliance Reporting Deployment Log ===" > "${LOG_FILE}"
    echo "Deployment started at: $(date)" >> "${LOG_FILE}"
    
    info "Starting Azure Compliance Reporting deployment..."
    
    # Parse command line arguments
    parse_args "$@"
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        info "DRY RUN MODE - No resources will be created"
    fi
    
    # Execute deployment steps
    check_prerequisites
    generate_resource_names
    create_resource_group
    create_confidential_ledger
    create_log_analytics_workspace
    create_storage_account
    create_action_group
    create_logic_app
    configure_rbac
    create_alert_rules
    update_logic_app_workflow
    save_deployment_info
    validate_deployment
    
    # Final success message
    echo ""
    success "=== DEPLOYMENT COMPLETED SUCCESSFULLY ==="
    info "Resource Group: ${RESOURCE_GROUP}"
    info "Location: ${LOCATION}"
    info "Subscription: ${SUBSCRIPTION_ID}"
    echo ""
    info "Next steps:"
    info "1. Review the deployment-info.json file for resource details"
    info "2. Test the compliance reporting workflow"
    info "3. Configure additional alert rules as needed"
    info "4. Set up monitoring and alerting"
    echo ""
    info "To clean up resources, run: ./destroy.sh"
    info "Log file: ${LOG_FILE}"
}

# Execute main function
main "$@"