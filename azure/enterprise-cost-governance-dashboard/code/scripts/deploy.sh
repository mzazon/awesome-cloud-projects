#!/bin/bash

# Azure Cost Governance Deployment Script
# This script deploys the complete cost governance solution with Azure Resource Graph and Power BI

set -e  # Exit on any error

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✅ $1${NC}"
}

warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️  $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ❌ $1${NC}"
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        error "Azure CLI is not installed. Please install it from https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
        exit 1
    fi
    
    # Check if user is logged in
    if ! az account show &> /dev/null; then
        error "You are not logged in to Azure. Please run 'az login' first."
        exit 1
    fi
    
    # Check if openssl is available for random string generation
    if ! command -v openssl &> /dev/null; then
        error "OpenSSL is not installed. Please install it for random string generation."
        exit 1
    fi
    
    success "Prerequisites check passed"
}

# Function to display configuration
display_configuration() {
    log "Deployment Configuration:"
    echo "  Resource Group: ${RESOURCE_GROUP}"
    echo "  Location: ${LOCATION}"
    echo "  Subscription ID: ${SUBSCRIPTION_ID}"
    echo "  Storage Account: ${STORAGE_ACCOUNT}"
    echo "  Logic App: ${LOGIC_APP_NAME}"
    echo "  Key Vault: ${KEY_VAULT_NAME}"
    echo "  Action Group: ${ACTION_GROUP_NAME}"
    echo ""
}

# Function to confirm deployment
confirm_deployment() {
    if [[ "${SKIP_CONFIRMATION}" != "true" ]]; then
        read -p "Do you want to proceed with the deployment? (y/n): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log "Deployment cancelled by user"
            exit 0
        fi
    fi
}

# Function to set environment variables
set_environment_variables() {
    log "Setting up environment variables..."
    
    # Generate unique suffix for resource names
    RANDOM_SUFFIX=$(openssl rand -hex 3)
    
    # Set default values if not provided
    export RESOURCE_GROUP="${RESOURCE_GROUP:-rg-cost-governance-${RANDOM_SUFFIX}}"
    export LOCATION="${LOCATION:-eastus}"
    export SUBSCRIPTION_ID=$(az account show --query id --output tsv)
    export TENANT_ID=$(az account show --query tenantId --output tsv)
    
    # Set resource names with unique identifiers
    export STORAGE_ACCOUNT="${STORAGE_ACCOUNT:-stcostgov${RANDOM_SUFFIX}}"
    export LOGIC_APP_NAME="${LOGIC_APP_NAME:-la-cost-governance-${RANDOM_SUFFIX}}"
    export KEY_VAULT_NAME="${KEY_VAULT_NAME:-kv-cost-gov-${RANDOM_SUFFIX}}"
    export ACTION_GROUP_NAME="${ACTION_GROUP_NAME:-ag-cost-alerts-${RANDOM_SUFFIX}}"
    
    # Validate storage account name length (3-24 characters)
    if [[ ${#STORAGE_ACCOUNT} -gt 24 ]]; then
        export STORAGE_ACCOUNT="stcostgov${RANDOM_SUFFIX}"
    fi
    
    # Validate Key Vault name length (3-24 characters)
    if [[ ${#KEY_VAULT_NAME} -gt 24 ]]; then
        export KEY_VAULT_NAME="kv-cost-${RANDOM_SUFFIX}"
    fi
    
    success "Environment variables configured"
}

# Function to create resource group
create_resource_group() {
    log "Creating resource group..."
    
    if az group show --name "${RESOURCE_GROUP}" &> /dev/null; then
        warning "Resource group ${RESOURCE_GROUP} already exists"
    else
        az group create \
            --name "${RESOURCE_GROUP}" \
            --location "${LOCATION}" \
            --tags purpose=cost-governance environment=production
        success "Resource group created: ${RESOURCE_GROUP}"
    fi
}

# Function to create storage account
create_storage_account() {
    log "Creating storage account..."
    
    if az storage account show --name "${STORAGE_ACCOUNT}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        warning "Storage account ${STORAGE_ACCOUNT} already exists"
    else
        az storage account create \
            --name "${STORAGE_ACCOUNT}" \
            --resource-group "${RESOURCE_GROUP}" \
            --location "${LOCATION}" \
            --sku Standard_LRS \
            --kind StorageV2 \
            --access-tier Hot \
            --allow-blob-public-access false \
            --min-tls-version TLS1_2
        success "Storage account created: ${STORAGE_ACCOUNT}"
    fi
}

# Function to configure Key Vault
configure_key_vault() {
    log "Configuring Azure Key Vault..."
    
    # Create Key Vault
    if az keyvault show --name "${KEY_VAULT_NAME}" &> /dev/null; then
        warning "Key Vault ${KEY_VAULT_NAME} already exists"
    else
        az keyvault create \
            --name "${KEY_VAULT_NAME}" \
            --resource-group "${RESOURCE_GROUP}" \
            --location "${LOCATION}" \
            --sku standard \
            --enable-rbac-authorization true
        success "Key Vault created: ${KEY_VAULT_NAME}"
    fi
    
    # Grant Key Vault Secrets Officer role to current user
    USER_OBJECT_ID=$(az ad signed-in-user show --query id --output tsv)
    az role assignment create \
        --role "Key Vault Secrets Officer" \
        --assignee "${USER_OBJECT_ID}" \
        --scope "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.KeyVault/vaults/${KEY_VAULT_NAME}" \
        --output none || true
    
    # Wait for role assignment to propagate
    sleep 10
    
    # Store cost governance configuration secrets
    az keyvault secret set \
        --vault-name "${KEY_VAULT_NAME}" \
        --name "cost-threshold-monthly" \
        --value "10000" \
        --output none
    
    az keyvault secret set \
        --vault-name "${KEY_VAULT_NAME}" \
        --name "cost-threshold-daily" \
        --value "500" \
        --output none
    
    success "Key Vault configured with cost governance secrets"
}

# Function to setup Resource Graph infrastructure
setup_resource_graph() {
    log "Setting up Azure Resource Graph infrastructure..."
    
    # Install Azure Resource Graph extension
    if ! az extension show --name resource-graph &> /dev/null; then
        az extension add --name resource-graph --only-show-errors
        success "Azure Resource Graph extension installed"
    else
        warning "Azure Resource Graph extension already installed"
    fi
    
    # Get storage account key
    STORAGE_KEY=$(az storage account keys list \
        --account-name "${STORAGE_ACCOUNT}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query '[0].value' --output tsv)
    
    # Create containers for Resource Graph data
    az storage container create \
        --name resource-graph-data \
        --account-name "${STORAGE_ACCOUNT}" \
        --account-key "${STORAGE_KEY}" \
        --public-access off \
        --output none || true
    
    # Test Resource Graph query
    az graph query \
        --query "resources | where type in~ ['microsoft.compute/virtualmachines', 'microsoft.storage/storageaccounts', 'microsoft.sql/servers'] | project name, type, resourceGroup, location, subscriptionId | limit 5" \
        --output table
    
    success "Resource Graph infrastructure configured and tested"
}

# Function to create Logic App
create_logic_app() {
    log "Creating Azure Logic App..."
    
    if az logic workflow show --name "${LOGIC_APP_NAME}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        warning "Logic App ${LOGIC_APP_NAME} already exists"
    else
        # Create Logic App with basic workflow
        az logic workflow create \
            --name "${LOGIC_APP_NAME}" \
            --resource-group "${RESOURCE_GROUP}" \
            --location "${LOCATION}" \
            --definition '{
                "definition": {
                    "$schema": "https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#",
                    "contentVersion": "1.0.0.0",
                    "parameters": {},
                    "triggers": {
                        "Recurrence": {
                            "recurrence": {
                                "frequency": "Hour",
                                "interval": 6
                            },
                            "type": "Recurrence"
                        }
                    },
                    "actions": {
                        "Initialize_variable": {
                            "inputs": {
                                "variables": [
                                    {
                                        "name": "costThreshold",
                                        "type": "integer",
                                        "value": 10000
                                    }
                                ]
                            },
                            "runAfter": {},
                            "type": "InitializeVariable"
                        }
                    },
                    "outputs": {}
                }
            }' \
            --output none
        success "Logic App created: ${LOGIC_APP_NAME}"
    fi
    
    # Enable managed identity for Logic App
    az logic workflow identity assign \
        --name "${LOGIC_APP_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --system-assigned \
        --output none
    
    success "Logic App configured with managed identity"
}

# Function to configure permissions
configure_permissions() {
    log "Configuring permissions for cost management..."
    
    # Get Logic App managed identity principal ID
    LOGIC_APP_PRINCIPAL_ID=$(az logic workflow identity show \
        --name "${LOGIC_APP_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query principalId --output tsv)
    
    # Wait for managed identity to propagate
    sleep 30
    
    # Assign Cost Management Reader role to Logic App
    az role assignment create \
        --role "Cost Management Reader" \
        --assignee "${LOGIC_APP_PRINCIPAL_ID}" \
        --scope "/subscriptions/${SUBSCRIPTION_ID}" \
        --output none || true
    
    # Assign Reader role for Resource Graph access
    az role assignment create \
        --role "Reader" \
        --assignee "${LOGIC_APP_PRINCIPAL_ID}" \
        --scope "/subscriptions/${SUBSCRIPTION_ID}" \
        --output none || true
    
    # Grant Key Vault access to Logic App
    az keyvault set-policy \
        --name "${KEY_VAULT_NAME}" \
        --object-id "${LOGIC_APP_PRINCIPAL_ID}" \
        --secret-permissions get list \
        --output none || true
    
    # Grant storage account access to Logic App
    az role assignment create \
        --role "Storage Blob Data Contributor" \
        --assignee "${LOGIC_APP_PRINCIPAL_ID}" \
        --scope "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.Storage/storageAccounts/${STORAGE_ACCOUNT}" \
        --output none || true
    
    success "Permissions configured for Logic App"
}

# Function to create Action Group
create_action_group() {
    log "Creating Action Group for cost alerts..."
    
    # Get default email for notifications
    DEFAULT_EMAIL="${NOTIFICATION_EMAIL:-$(az account show --query user.name --output tsv)}"
    
    if az monitor action-group show --name "${ACTION_GROUP_NAME}" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        warning "Action Group ${ACTION_GROUP_NAME} already exists"
    else
        az monitor action-group create \
            --name "${ACTION_GROUP_NAME}" \
            --resource-group "${RESOURCE_GROUP}" \
            --short-name CostAlerts \
            --action email cost-admin "${DEFAULT_EMAIL}" \
            --output none
        success "Action Group created: ${ACTION_GROUP_NAME}"
    fi
    
    # Create budget alert for monthly cost threshold
    if az consumption budget show --budget-name "monthly-cost-governance" --resource-group "${RESOURCE_GROUP}" &> /dev/null; then
        warning "Budget alert already exists"
    else
        az consumption budget create \
            --budget-name "monthly-cost-governance" \
            --amount 10000 \
            --time-grain Monthly \
            --time-period-start-date "$(date -d 'first day of this month' +%Y-%m-01)" \
            --time-period-end-date "$(date -d 'last day of december' +%Y-12-31)" \
            --resource-group "${RESOURCE_GROUP}" \
            --notifications '{
                "Actual_GreaterThan_80_Percent": {
                    "enabled": true,
                    "operator": "GreaterThan",
                    "threshold": 80,
                    "contactEmails": ["'${DEFAULT_EMAIL}'"],
                    "contactRoles": ["Owner"],
                    "contactGroups": ["/subscriptions/'${SUBSCRIPTION_ID}'/resourceGroups/'${RESOURCE_GROUP}'/providers/microsoft.insights/actionGroups/'${ACTION_GROUP_NAME}'"]
                },
                "Forecasted_GreaterThan_100_Percent": {
                    "enabled": true,
                    "operator": "GreaterThan",
                    "threshold": 100,
                    "contactEmails": ["'${DEFAULT_EMAIL}'"],
                    "contactRoles": ["Owner"],
                    "contactGroups": ["/subscriptions/'${SUBSCRIPTION_ID}'/resourceGroups/'${RESOURCE_GROUP}'/providers/microsoft.insights/actionGroups/'${ACTION_GROUP_NAME}'"]
                }
            }' \
            --output none
        success "Budget alert configured"
    fi
}

# Function to configure Power BI data sources
configure_powerbi_data() {
    log "Configuring Power BI data sources..."
    
    # Get storage account key
    STORAGE_KEY=$(az storage account keys list \
        --account-name "${STORAGE_ACCOUNT}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query '[0].value' --output tsv)
    
    # Create containers for Power BI data
    az storage container create \
        --name powerbi-datasets \
        --account-name "${STORAGE_ACCOUNT}" \
        --account-key "${STORAGE_KEY}" \
        --public-access off \
        --output none || true
    
    az storage container create \
        --name cost-reports \
        --account-name "${STORAGE_ACCOUNT}" \
        --account-key "${STORAGE_KEY}" \
        --public-access off \
        --output none || true
    
    # Generate sample cost data for Power BI testing
    az graph query \
        --query "resources | where type in~ ['microsoft.compute/virtualmachines', 'microsoft.storage/storageaccounts'] | project name, type, resourceGroup, location, subscriptionId, tags | limit 100" \
        --output json > /tmp/resource-inventory.json
    
    # Upload sample data to storage for Power BI consumption
    az storage blob upload \
        --file /tmp/resource-inventory.json \
        --container-name powerbi-datasets \
        --name "resource-inventory-$(date +%Y%m%d).json" \
        --account-name "${STORAGE_ACCOUNT}" \
        --account-key "${STORAGE_KEY}" \
        --overwrite \
        --output none
    
    # Create SAS token for Power BI access (valid for 1 year)
    STORAGE_SAS=$(az storage container generate-sas \
        --name powerbi-datasets \
        --account-name "${STORAGE_ACCOUNT}" \
        --account-key "${STORAGE_KEY}" \
        --permissions r \
        --expiry "$(date -d '+1 year' +%Y-%m-%d)" \
        --output tsv)
    
    success "Power BI data sources configured"
    log "Storage URL: https://${STORAGE_ACCOUNT}.blob.core.windows.net/powerbi-datasets"
    log "SAS Token: ${STORAGE_SAS}"
    
    # Clean up temporary file
    rm -f /tmp/resource-inventory.json
}

# Function to deploy Resource Graph queries
deploy_resource_graph_queries() {
    log "Deploying Resource Graph queries for cost analysis..."
    
    # Get storage account key
    STORAGE_KEY=$(az storage account keys list \
        --account-name "${STORAGE_ACCOUNT}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query '[0].value' --output tsv)
    
    # Create comprehensive Resource Graph query for cost analysis
    cat > /tmp/cost-analysis-query.kql << 'EOF'
resources
| where type in~ [
    'microsoft.compute/virtualmachines',
    'microsoft.storage/storageaccounts',
    'microsoft.sql/servers',
    'microsoft.web/sites',
    'microsoft.containerinstance/containergroups',
    'microsoft.kubernetes/connectedclusters'
]
| extend costCenter = tostring(tags['CostCenter'])
| extend environment = tostring(tags['Environment'])
| extend owner = tostring(tags['Owner'])
| project 
    name,
    type,
    resourceGroup,
    location,
    subscriptionId,
    costCenter,
    environment,
    owner,
    tags
| where isnotempty(name)
| order by type, name
EOF
    
    # Execute cost analysis query and save results
    az graph query \
        --query "$(cat /tmp/cost-analysis-query.kql)" \
        --output json > /tmp/cost-analysis-results.json
    
    # Upload query results to storage
    az storage blob upload \
        --file /tmp/cost-analysis-results.json \
        --container-name cost-reports \
        --name "cost-analysis-$(date +%Y%m%d-%H%M).json" \
        --account-name "${STORAGE_ACCOUNT}" \
        --account-key "${STORAGE_KEY}" \
        --overwrite \
        --output none
    
    # Create tag compliance query
    cat > /tmp/tag-compliance-query.kql << 'EOF'
resources
| where type in~ [
    'microsoft.compute/virtualmachines',
    'microsoft.storage/storageaccounts',
    'microsoft.sql/servers'
]
| extend hasOwnerTag = isnotempty(tags['Owner'])
| extend hasCostCenterTag = isnotempty(tags['CostCenter'])
| extend hasEnvironmentTag = isnotempty(tags['Environment'])
| summarize 
    TotalResources = count(),
    ResourcesWithOwner = countif(hasOwnerTag),
    ResourcesWithCostCenter = countif(hasCostCenterTag),
    ResourcesWithEnvironment = countif(hasEnvironmentTag)
by type, subscriptionId
| extend 
    OwnerTagCompliance = round(100.0 * ResourcesWithOwner / TotalResources, 2),
    CostCenterTagCompliance = round(100.0 * ResourcesWithCostCenter / TotalResources, 2),
    EnvironmentTagCompliance = round(100.0 * ResourcesWithEnvironment / TotalResources, 2)
EOF
    
    # Execute tag compliance analysis
    az graph query \
        --query "$(cat /tmp/tag-compliance-query.kql)" \
        --output json > /tmp/tag-compliance-results.json
    
    az storage blob upload \
        --file /tmp/tag-compliance-results.json \
        --container-name cost-reports \
        --name "tag-compliance-$(date +%Y%m%d-%H%M).json" \
        --account-name "${STORAGE_ACCOUNT}" \
        --account-key "${STORAGE_KEY}" \
        --overwrite \
        --output none
    
    success "Resource Graph queries deployed and executed"
    
    # Clean up temporary files
    rm -f /tmp/cost-analysis-query.kql /tmp/cost-analysis-results.json /tmp/tag-compliance-query.kql /tmp/tag-compliance-results.json
}

# Function to update Logic App workflow
update_logic_app_workflow() {
    log "Updating Logic App workflow for automated cost governance..."
    
    # Update Logic App with comprehensive cost governance workflow
    az logic workflow update \
        --name "${LOGIC_APP_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --definition '{
            "definition": {
                "$schema": "https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#",
                "contentVersion": "1.0.0.0",
                "parameters": {
                    "storageAccountName": {
                        "type": "string",
                        "defaultValue": "'${STORAGE_ACCOUNT}'"
                    },
                    "keyVaultName": {
                        "type": "string",
                        "defaultValue": "'${KEY_VAULT_NAME}'"
                    }
                },
                "triggers": {
                    "Recurrence": {
                        "recurrence": {
                            "frequency": "Hour",
                            "interval": 6
                        },
                        "type": "Recurrence"
                    }
                },
                "actions": {
                    "Get_Cost_Threshold": {
                        "inputs": {
                            "authentication": {
                                "type": "ManagedServiceIdentity"
                            },
                            "method": "GET",
                            "uri": "https://@{parameters('keyVaultName')}.vault.azure.net/secrets/cost-threshold-daily?api-version=2016-10-01"
                        },
                        "runAfter": {},
                        "type": "Http"
                    },
                    "Execute_Resource_Graph_Query": {
                        "inputs": {
                            "authentication": {
                                "type": "ManagedServiceIdentity"
                            },
                            "body": {
                                "query": "resources | where type in~ ['microsoft.compute/virtualmachines', 'microsoft.storage/storageaccounts'] | summarize count() by type, subscriptionId"
                            },
                            "method": "POST",
                            "uri": "https://management.azure.com/providers/Microsoft.ResourceGraph/resources?api-version=2021-03-01"
                        },
                        "runAfter": {
                            "Get_Cost_Threshold": [
                                "Succeeded"
                            ]
                        },
                        "type": "Http"
                    },
                    "Store_Results": {
                        "inputs": {
                            "authentication": {
                                "type": "ManagedServiceIdentity"
                            },
                            "body": "@body('Execute_Resource_Graph_Query')",
                            "headers": {
                                "x-ms-blob-type": "BlockBlob"
                            },
                            "method": "PUT",
                            "uri": "https://@{parameters('storageAccountName')}.blob.core.windows.net/cost-reports/resource-summary-@{utcnow()}.json"
                        },
                        "runAfter": {
                            "Execute_Resource_Graph_Query": [
                                "Succeeded"
                            ]
                        },
                        "type": "Http"
                    }
                },
                "outputs": {}
            }
        }' \
        --output none
    
    success "Logic App workflow updated for automated cost governance"
}

# Function to test the deployment
test_deployment() {
    log "Testing deployment..."
    
    # Test Resource Graph query
    log "Testing Resource Graph connectivity..."
    az graph query \
        --query "resources | summarize count() by type | order by count_ desc | limit 5" \
        --output table
    
    # Test Cost Management API access
    log "Testing Cost Management API access..."
    az rest \
        --method POST \
        --url "https://management.azure.com/subscriptions/${SUBSCRIPTION_ID}/providers/Microsoft.CostManagement/query?api-version=2021-10-01" \
        --headers "Content-Type=application/json" \
        --body '{
            "type": "Usage",
            "timeframe": "WeekToDate",
            "dataset": {
                "granularity": "Daily",
                "aggregation": {
                    "totalCost": {
                        "name": "PreTaxCost",
                        "function": "Sum"
                    }
                }
            }
        }' \
        --output table || warning "Cost Management API test failed - this is expected if no usage data is available"
    
    # Test Logic App workflow
    log "Testing Logic App workflow..."
    az logic workflow trigger run \
        --name "${LOGIC_APP_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --trigger-name Recurrence \
        --output none || warning "Logic App trigger test failed - this is expected if permissions are still propagating"
    
    success "Deployment testing completed"
}

# Function to display deployment summary
display_deployment_summary() {
    log "Deployment Summary:"
    echo "===================="
    echo "Resource Group: ${RESOURCE_GROUP}"
    echo "Storage Account: ${STORAGE_ACCOUNT}"
    echo "Key Vault: ${KEY_VAULT_NAME}"
    echo "Logic App: ${LOGIC_APP_NAME}"
    echo "Action Group: ${ACTION_GROUP_NAME}"
    echo ""
    echo "Power BI Data Source:"
    echo "  Storage URL: https://${STORAGE_ACCOUNT}.blob.core.windows.net/powerbi-datasets"
    echo ""
    echo "Next Steps:"
    echo "1. Configure Power BI workspace and connect to the storage account"
    echo "2. Set up Power BI datasets using the uploaded sample data"
    echo "3. Create dashboards for cost governance visualization"
    echo "4. Configure additional notification channels in Action Group"
    echo "5. Customize cost thresholds in Key Vault secrets"
    echo ""
    echo "Estimated Monthly Cost: $50-100 (depends on usage and Power BI license)"
    echo ""
    success "Deployment completed successfully!"
}

# Main deployment function
main() {
    log "Starting Azure Cost Governance Solution Deployment"
    
    # Check prerequisites
    check_prerequisites
    
    # Set environment variables
    set_environment_variables
    
    # Display configuration
    display_configuration
    
    # Confirm deployment
    confirm_deployment
    
    # Create infrastructure
    create_resource_group
    create_storage_account
    configure_key_vault
    setup_resource_graph
    create_logic_app
    configure_permissions
    create_action_group
    configure_powerbi_data
    deploy_resource_graph_queries
    update_logic_app_workflow
    
    # Test deployment
    test_deployment
    
    # Display summary
    display_deployment_summary
}

# Handle command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --resource-group)
            RESOURCE_GROUP="$2"
            shift 2
            ;;
        --location)
            LOCATION="$2"
            shift 2
            ;;
        --storage-account)
            STORAGE_ACCOUNT="$2"
            shift 2
            ;;
        --notification-email)
            NOTIFICATION_EMAIL="$2"
            shift 2
            ;;
        --skip-confirmation)
            SKIP_CONFIRMATION="true"
            shift
            ;;
        --help)
            echo "Usage: $0 [options]"
            echo "Options:"
            echo "  --resource-group NAME     Resource group name (default: rg-cost-governance-RANDOM)"
            echo "  --location LOCATION       Azure region (default: eastus)"
            echo "  --storage-account NAME    Storage account name (default: stcostgovRANDOM)"
            echo "  --notification-email EMAIL  Email for notifications (default: current user)"
            echo "  --skip-confirmation       Skip deployment confirmation prompt"
            echo "  --help                    Show this help message"
            exit 0
            ;;
        *)
            error "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Run main function
main "$@"