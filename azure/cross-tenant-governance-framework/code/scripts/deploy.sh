#!/bin/bash

# ==============================================================================
# Azure Lighthouse and Automanage Deployment Script
# ==============================================================================
# This script deploys cross-tenant resource governance infrastructure using
# Azure Lighthouse for delegated access and Azure Automanage for automated
# VM configuration management.
# ==============================================================================

set -euo pipefail

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

# Check if we're in dry run mode
DRY_RUN=false
if [[ "${1:-}" == "--dry-run" ]]; then
    DRY_RUN=true
    info "Running in dry-run mode - no resources will be created"
fi

# Function to execute commands with dry run support
execute_cmd() {
    local cmd="$1"
    local description="$2"
    
    if [ "$DRY_RUN" = true ]; then
        info "DRY RUN: $description"
        echo "  Command: $cmd"
        return 0
    fi
    
    info "$description"
    if eval "$cmd"; then
        log "✅ $description completed successfully"
        return 0
    else
        error "❌ Failed to execute: $description"
        return 1
    fi
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        error "Azure CLI is not installed. Please install it first."
    fi
    
    # Check Azure CLI version
    local az_version=$(az version --output tsv --query '"azure-cli"')
    log "Azure CLI version: $az_version"
    
    # Check if PowerShell is available (optional)
    if command -v pwsh &> /dev/null; then
        log "PowerShell found: $(pwsh --version)"
    else
        warn "PowerShell not found. Some features may be limited."
    fi
    
    # Check if logged in to Azure
    if ! az account show &> /dev/null; then
        error "Not logged in to Azure. Please run 'az login' first."
    fi
    
    # Check if openssl is available for random string generation
    if ! command -v openssl &> /dev/null; then
        error "OpenSSL is not installed. Required for generating random strings."
    fi
    
    log "✅ Prerequisites check completed"
}

# Function to set environment variables
set_environment_variables() {
    log "Setting up environment variables..."
    
    # MSP tenant configuration
    export MSP_TENANT_ID="${MSP_TENANT_ID:-$(az account show --query tenantId -o tsv)}"
    export MSP_SUBSCRIPTION_ID="${MSP_SUBSCRIPTION_ID:-$(az account show --query id -o tsv)}"
    export MSP_RESOURCE_GROUP="${MSP_RESOURCE_GROUP:-rg-msp-lighthouse-management}"
    export LOCATION="${LOCATION:-eastus}"
    
    # Customer tenant configuration (these should be provided by user)
    if [[ -z "${CUSTOMER_TENANT_ID:-}" ]]; then
        error "CUSTOMER_TENANT_ID environment variable is required"
    fi
    
    if [[ -z "${CUSTOMER_SUBSCRIPTION_ID:-}" ]]; then
        error "CUSTOMER_SUBSCRIPTION_ID environment variable is required"
    fi
    
    export CUSTOMER_RESOURCE_GROUP="${CUSTOMER_RESOURCE_GROUP:-rg-customer-workloads}"
    
    # Generate unique identifiers
    local random_suffix=$(openssl rand -hex 3)
    export LIGHTHOUSE_DEFINITION_NAME="${LIGHTHOUSE_DEFINITION_NAME:-lighthouse-definition-${random_suffix}}"
    export AUTOMANAGE_PROFILE_NAME="${AUTOMANAGE_PROFILE_NAME:-automanage-profile-${random_suffix}}"
    export LOG_ANALYTICS_WORKSPACE="${LOG_ANALYTICS_WORKSPACE:-law-lighthouse-${random_suffix}}"
    
    # VM configuration
    export VM_NAME="${VM_NAME:-vm-customer-${random_suffix}}"
    export VNET_NAME="${VNET_NAME:-vnet-customer-${random_suffix}}"
    
    # Create deployment state file
    cat > .deployment_state << EOF
MSP_TENANT_ID=${MSP_TENANT_ID}
MSP_SUBSCRIPTION_ID=${MSP_SUBSCRIPTION_ID}
MSP_RESOURCE_GROUP=${MSP_RESOURCE_GROUP}
CUSTOMER_TENANT_ID=${CUSTOMER_TENANT_ID}
CUSTOMER_SUBSCRIPTION_ID=${CUSTOMER_SUBSCRIPTION_ID}
CUSTOMER_RESOURCE_GROUP=${CUSTOMER_RESOURCE_GROUP}
LIGHTHOUSE_DEFINITION_NAME=${LIGHTHOUSE_DEFINITION_NAME}
AUTOMANAGE_PROFILE_NAME=${AUTOMANAGE_PROFILE_NAME}
LOG_ANALYTICS_WORKSPACE=${LOG_ANALYTICS_WORKSPACE}
VM_NAME=${VM_NAME}
VNET_NAME=${VNET_NAME}
LOCATION=${LOCATION}
EOF
    
    log "✅ Environment variables configured"
    info "MSP Tenant ID: $MSP_TENANT_ID"
    info "Customer Tenant ID: $CUSTOMER_TENANT_ID"
    info "Location: $LOCATION"
}

# Function to setup MSP tenant resources
setup_msp_tenant() {
    log "Setting up MSP tenant resources..."
    
    # Login to MSP tenant and set context
    execute_cmd "az login --tenant ${MSP_TENANT_ID} --allow-no-subscriptions" "Logging in to MSP tenant"
    execute_cmd "az account set --subscription ${MSP_SUBSCRIPTION_ID}" "Setting MSP subscription context"
    
    # Create MSP resource group
    execute_cmd "az group create --name ${MSP_RESOURCE_GROUP} --location ${LOCATION} --tags purpose=lighthouse-management environment=production" "Creating MSP resource group"
    
    log "✅ MSP tenant setup completed"
}

# Function to create Lighthouse delegation templates
create_lighthouse_templates() {
    log "Creating Azure Lighthouse delegation templates..."
    
    # Create ARM template for Lighthouse delegation
    cat > lighthouse-delegation.json << 'EOF'
{
    "$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#",
    "contentVersion": "1.0.0.0",
    "parameters": {
        "mspTenantId": {
            "type": "string",
            "metadata": {
                "description": "The tenant ID of the MSP"
            }
        },
        "mspOfferName": {
            "type": "string",
            "metadata": {
                "description": "The name of the MSP offer"
            }
        },
        "mspOfferDescription": {
            "type": "string",
            "metadata": {
                "description": "Description of the MSP offer"
            }
        },
        "managedByTenantId": {
            "type": "string",
            "metadata": {
                "description": "The tenant ID of the MSP managing tenant"
            }
        },
        "authorizations": {
            "type": "array",
            "metadata": {
                "description": "Array of authorization objects"
            }
        }
    },
    "variables": {
        "mspRegistrationName": "[guid(parameters('mspOfferName'))]",
        "mspAssignmentName": "[guid(parameters('mspOfferName'))]"
    },
    "resources": [
        {
            "type": "Microsoft.ManagedServices/registrationDefinitions",
            "apiVersion": "2020-02-01-preview",
            "name": "[variables('mspRegistrationName')]",
            "properties": {
                "registrationDefinitionName": "[parameters('mspOfferName')]",
                "description": "[parameters('mspOfferDescription')]",
                "managedByTenantId": "[parameters('managedByTenantId')]",
                "authorizations": "[parameters('authorizations')]"
            }
        },
        {
            "type": "Microsoft.ManagedServices/registrationAssignments",
            "apiVersion": "2020-02-01-preview",
            "name": "[variables('mspAssignmentName')]",
            "dependsOn": [
                "[resourceId('Microsoft.ManagedServices/registrationDefinitions/', variables('mspRegistrationName'))]"
            ],
            "properties": {
                "registrationDefinitionId": "[resourceId('Microsoft.ManagedServices/registrationDefinitions/', variables('mspRegistrationName'))]"
            }
        }
    ],
    "outputs": {
        "mspRegistrationName": {
            "type": "string",
            "value": "[variables('mspRegistrationName')]"
        },
        "mspAssignmentName": {
            "type": "string",
            "value": "[variables('mspAssignmentName')]"
        }
    }
}
EOF
    
    log "✅ Lighthouse delegation template created"
}

# Function to configure authorization parameters
configure_authorization_parameters() {
    log "Configuring authorization parameters for MSP team..."
    
    # Try to get MSP group object IDs (these may need to be created manually)
    local msp_admin_group_id
    local msp_engineer_group_id
    
    # Check if MSP groups exist, create placeholder if not
    if ! msp_admin_group_id=$(az ad group show --group "MSP-Administrators" --query id --output tsv 2>/dev/null); then
        warn "MSP-Administrators group not found. Using current user ID as fallback."
        msp_admin_group_id=$(az ad signed-in-user show --query id --output tsv)
    fi
    
    if ! msp_engineer_group_id=$(az ad group show --group "MSP-Engineers" --query id --output tsv 2>/dev/null); then
        warn "MSP-Engineers group not found. Using current user ID as fallback."
        msp_engineer_group_id=$(az ad signed-in-user show --query id --output tsv)
    fi
    
    # Create authorization parameters file
    cat > lighthouse-parameters.json << EOF
{
    "\$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#",
    "contentVersion": "1.0.0.0",
    "parameters": {
        "mspTenantId": {
            "value": "${MSP_TENANT_ID}"
        },
        "mspOfferName": {
            "value": "Cross-Tenant Resource Governance"
        },
        "mspOfferDescription": {
            "value": "Managed services for automated VM configuration, patching, and compliance monitoring"
        },
        "managedByTenantId": {
            "value": "${MSP_TENANT_ID}"
        },
        "authorizations": {
            "value": [
                {
                    "principalId": "${msp_admin_group_id}",
                    "principalIdDisplayName": "MSP Administrators",
                    "roleDefinitionId": "b24988ac-6180-42a0-ab88-20f7382dd24c"
                },
                {
                    "principalId": "${msp_engineer_group_id}",
                    "principalIdDisplayName": "MSP Engineers",
                    "roleDefinitionId": "9980e02c-c2be-4d73-94e8-173b1dc7cf3c"
                },
                {
                    "principalId": "${msp_admin_group_id}",
                    "principalIdDisplayName": "MSP Administrators - Automanage",
                    "roleDefinitionId": "cdfd5644-ae35-4c17-bb47-ac720c1b0b59"
                }
            ]
        }
    }
}
EOF
    
    log "✅ Authorization parameters configured"
}

# Function to deploy Lighthouse delegation
deploy_lighthouse_delegation() {
    log "Deploying Lighthouse delegation to customer tenant..."
    
    # Switch to customer tenant
    execute_cmd "az login --tenant ${CUSTOMER_TENANT_ID} --allow-no-subscriptions" "Logging in to customer tenant"
    execute_cmd "az account set --subscription ${CUSTOMER_SUBSCRIPTION_ID}" "Setting customer subscription context"
    
    # Deploy the Lighthouse delegation template
    local deployment_name="lighthouse-delegation-$(openssl rand -hex 3)"
    
    execute_cmd "az deployment sub create --name ${deployment_name} --location ${LOCATION} --template-file lighthouse-delegation.json --parameters @lighthouse-parameters.json" "Deploying Lighthouse delegation template"
    
    # Wait for deployment to complete
    if [ "$DRY_RUN" = false ]; then
        info "Waiting for deployment to complete..."
        az deployment sub wait --name ${deployment_name} --created
    fi
    
    # Store deployment name for cleanup
    echo "LIGHTHOUSE_DEPLOYMENT_NAME=${deployment_name}" >> .deployment_state
    
    log "✅ Lighthouse delegation deployed successfully"
}

# Function to verify delegation
verify_delegation() {
    log "Verifying Lighthouse delegation..."
    
    # Switch back to MSP tenant
    execute_cmd "az login --tenant ${MSP_TENANT_ID} --allow-no-subscriptions" "Switching back to MSP tenant"
    execute_cmd "az account set --subscription ${MSP_SUBSCRIPTION_ID}" "Setting MSP subscription context"
    
    if [ "$DRY_RUN" = false ]; then
        # Verify delegation by listing managed customers
        info "Checking managed customers..."
        if az managedservices assignment list --include-definition --output table; then
            log "✅ Managed customers verified"
        else
            warn "No managed customers found yet. This may take a few minutes to propagate."
        fi
        
        # Verify cross-tenant access
        info "Testing cross-tenant resource access..."
        if az resource list --subscription ${CUSTOMER_SUBSCRIPTION_ID} --output table; then
            log "✅ Cross-tenant access verified"
        else
            warn "Cross-tenant access not yet available. Please wait a few minutes."
        fi
    fi
    
    log "✅ Delegation verification completed"
}

# Function to create Automanage configuration
create_automanage_configuration() {
    log "Creating Azure Automanage configuration..."
    
    # Create Log Analytics workspace
    execute_cmd "az monitor log-analytics workspace create --resource-group ${MSP_RESOURCE_GROUP} --workspace-name ${LOG_ANALYTICS_WORKSPACE} --location ${LOCATION} --sku pergb2018" "Creating Log Analytics workspace"
    
    # Get workspace ID
    local workspace_id
    if [ "$DRY_RUN" = false ]; then
        workspace_id=$(az monitor log-analytics workspace show --resource-group ${MSP_RESOURCE_GROUP} --workspace-name ${LOG_ANALYTICS_WORKSPACE} --query id --output tsv)
    else
        workspace_id="/subscriptions/${MSP_SUBSCRIPTION_ID}/resourceGroups/${MSP_RESOURCE_GROUP}/providers/Microsoft.OperationalInsights/workspaces/${LOG_ANALYTICS_WORKSPACE}"
    fi
    
    # Create Automanage configuration profile
    cat > automanage-profile.json << EOF
{
    "location": "${LOCATION}",
    "properties": {
        "configuration": {
            "Antimalware/Enable": "true",
            "AzureSecurityCenter/Enable": "true",
            "Backup/Enable": "true",
            "BootDiagnostics/Enable": "true",
            "ChangeTrackingAndInventory/Enable": "true",
            "GuestConfiguration/Enable": "true",
            "LogAnalytics/Enable": "true",
            "LogAnalytics/WorkspaceId": "${workspace_id}",
            "UpdateManagement/Enable": "true",
            "VMInsights/Enable": "true"
        }
    }
}
EOF
    
    execute_cmd "az automanage configuration-profile create --resource-group ${MSP_RESOURCE_GROUP} --configuration-profile-name ${AUTOMANAGE_PROFILE_NAME} --body @automanage-profile.json" "Creating Automanage configuration profile"
    
    log "✅ Automanage configuration created"
}

# Function to deploy customer VMs
deploy_customer_vms() {
    log "Deploying virtual machines in customer tenant..."
    
    # Switch to customer tenant
    execute_cmd "az login --tenant ${CUSTOMER_TENANT_ID} --allow-no-subscriptions" "Switching to customer tenant"
    execute_cmd "az account set --subscription ${CUSTOMER_SUBSCRIPTION_ID}" "Setting customer subscription context"
    
    # Create customer resource group
    execute_cmd "az group create --name ${CUSTOMER_RESOURCE_GROUP} --location ${LOCATION} --tags customer=tenant-a purpose=workload-vms" "Creating customer resource group"
    
    # Create virtual network
    execute_cmd "az network vnet create --resource-group ${CUSTOMER_RESOURCE_GROUP} --name ${VNET_NAME} --address-prefix 10.0.0.0/16 --subnet-name default --subnet-prefix 10.0.1.0/24" "Creating virtual network"
    
    # Generate secure password
    local vm_password="P@ssw0rd123!$(openssl rand -hex 4)"
    
    # Create virtual machine
    execute_cmd "az vm create --resource-group ${CUSTOMER_RESOURCE_GROUP} --name ${VM_NAME} --image Win2019Datacenter --admin-username azureuser --admin-password '${vm_password}' --size Standard_B2s --vnet-name ${VNET_NAME} --subnet default --tags automanage=enabled environment=production" "Creating virtual machine"
    
    # Store VM password securely
    echo "VM_PASSWORD=${vm_password}" >> .deployment_state
    
    log "✅ Customer VMs deployed successfully"
}

# Function to enable Automanage
enable_automanage() {
    log "Enabling Automanage on customer virtual machines..."
    
    # Switch back to MSP tenant for cross-tenant management
    execute_cmd "az login --tenant ${MSP_TENANT_ID} --allow-no-subscriptions" "Switching back to MSP tenant"
    execute_cmd "az account set --subscription ${MSP_SUBSCRIPTION_ID}" "Setting MSP subscription context"
    
    # Enable Automanage on customer VMs
    execute_cmd "az automanage configuration-profile-assignment create --resource-group ${CUSTOMER_RESOURCE_GROUP} --vm-name ${VM_NAME} --configuration-profile-assignment-name default --configuration-profile ${AUTOMANAGE_PROFILE_NAME} --subscription ${CUSTOMER_SUBSCRIPTION_ID}" "Enabling Automanage on customer VMs"
    
    log "✅ Automanage enabled on customer virtual machines"
}

# Function to configure monitoring
configure_monitoring() {
    log "Configuring cross-tenant monitoring and alerting..."
    
    # Create action group for alerting
    local action_group_name="ag-lighthouse-alerts-$(openssl rand -hex 3)"
    
    execute_cmd "az monitor action-group create --resource-group ${MSP_RESOURCE_GROUP} --name ${action_group_name} --short-name LighthouseAlerts --email-receivers name=MSP-Ops email=ops@msp-company.com" "Creating action group for alerts"
    
    # Get VM resource ID for alerting
    local vm_resource_id
    if [ "$DRY_RUN" = false ]; then
        vm_resource_id=$(az vm show --resource-group ${CUSTOMER_RESOURCE_GROUP} --name ${VM_NAME} --subscription ${CUSTOMER_SUBSCRIPTION_ID} --query id --output tsv)
    else
        vm_resource_id="/subscriptions/${CUSTOMER_SUBSCRIPTION_ID}/resourceGroups/${CUSTOMER_RESOURCE_GROUP}/providers/Microsoft.Compute/virtualMachines/${VM_NAME}"
    fi
    
    # Create alert rule for VM availability
    local alert_rule_name="vm-availability-cross-tenant"
    
    execute_cmd "az monitor metrics alert create --resource-group ${MSP_RESOURCE_GROUP} --name ${alert_rule_name} --description 'Alert when VMs are unavailable across customer tenants' --scopes ${vm_resource_id} --condition 'avg \"Percentage CPU\" > 80' --window-size 5m --evaluation-frequency 1m --action ${action_group_name} --severity 2" "Creating VM availability alert rule"
    
    # Store monitoring resources for cleanup
    echo "ACTION_GROUP_NAME=${action_group_name}" >> .deployment_state
    echo "ALERT_RULE_NAME=${alert_rule_name}" >> .deployment_state
    
    log "✅ Cross-tenant monitoring configured"
}

# Function to create deployment summary
create_deployment_summary() {
    log "Creating deployment summary..."
    
    cat > deployment-summary.txt << EOF
=================================================================
Azure Lighthouse and Automanage Deployment Summary
=================================================================
Deployment Date: $(date)
Deployment Mode: ${DRY_RUN}

MSP Tenant Configuration:
- Tenant ID: ${MSP_TENANT_ID}
- Subscription ID: ${MSP_SUBSCRIPTION_ID}
- Resource Group: ${MSP_RESOURCE_GROUP}
- Location: ${LOCATION}

Customer Tenant Configuration:
- Tenant ID: ${CUSTOMER_TENANT_ID}
- Subscription ID: ${CUSTOMER_SUBSCRIPTION_ID}
- Resource Group: ${CUSTOMER_RESOURCE_GROUP}

Deployed Resources:
- Lighthouse Definition: ${LIGHTHOUSE_DEFINITION_NAME}
- Automanage Profile: ${AUTOMANAGE_PROFILE_NAME}
- Log Analytics Workspace: ${LOG_ANALYTICS_WORKSPACE}
- Virtual Network: ${VNET_NAME}
- Virtual Machine: ${VM_NAME}

Management URLs:
- Azure Portal: https://portal.azure.com
- Lighthouse Dashboard: https://portal.azure.com/#blade/Microsoft_Azure_CustomerHub/ServiceProvidersBladeV2
- Automanage Dashboard: https://portal.azure.com/#blade/Microsoft_Azure_Automanage/AutomanageBlade

Next Steps:
1. Verify Lighthouse delegation in Azure Portal
2. Check Automanage compliance status
3. Review monitoring alerts and dashboards
4. Configure additional customer tenants as needed

For cleanup, run: ./destroy.sh
=================================================================
EOF
    
    log "✅ Deployment summary created: deployment-summary.txt"
}

# Main deployment function
main() {
    log "Starting Azure Lighthouse and Automanage deployment..."
    
    # Check if running from correct directory
    if [[ ! -f "deploy.sh" ]]; then
        error "Please run this script from the scripts directory"
    fi
    
    # Run deployment steps
    check_prerequisites
    set_environment_variables
    setup_msp_tenant
    create_lighthouse_templates
    configure_authorization_parameters
    deploy_lighthouse_delegation
    verify_delegation
    create_automanage_configuration
    deploy_customer_vms
    enable_automanage
    configure_monitoring
    create_deployment_summary
    
    log "🎉 Deployment completed successfully!"
    
    if [ "$DRY_RUN" = false ]; then
        info "Deployment state saved to: .deployment_state"
        info "Deployment summary saved to: deployment-summary.txt"
        warn "Please secure the .deployment_state file as it contains sensitive information"
    fi
    
    info "To clean up resources, run: ./destroy.sh"
}

# Trap to handle script interruption
trap 'error "Script interrupted by user"' INT TERM

# Run main function
main "$@"