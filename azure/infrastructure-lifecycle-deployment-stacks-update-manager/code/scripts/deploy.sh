#!/bin/bash

# Azure Infrastructure Lifecycle Management with Deployment Stacks and Update Manager
# Deployment Script
# This script deploys the complete infrastructure lifecycle management solution

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/deploy.log"
TEMPLATE_FILE="${SCRIPT_DIR}/../bicep/main.bicep"
PARAMETERS_FILE="${SCRIPT_DIR}/../bicep/parameters.json"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}" | tee -a "$LOG_FILE"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}" | tee -a "$LOG_FILE"
}

warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}" | tee -a "$LOG_FILE"
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1${NC}" | tee -a "$LOG_FILE"
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        error "Azure CLI is not installed. Please install Azure CLI first."
        exit 1
    fi
    
    # Check Azure CLI version
    local az_version=$(az version --query '"azure-cli"' -o tsv 2>/dev/null || echo "unknown")
    info "Azure CLI version: $az_version"
    
    # Check if logged in to Azure
    if ! az account show &> /dev/null; then
        error "Not logged in to Azure. Please run 'az login' first."
        exit 1
    fi
    
    # Check if Bicep is available
    if ! az bicep version &> /dev/null; then
        warning "Bicep not found. Installing Bicep..."
        az bicep install
    fi
    
    # Check if template files exist
    if [[ ! -f "$TEMPLATE_FILE" ]]; then
        error "Bicep template file not found: $TEMPLATE_FILE"
        exit 1
    fi
    
    log "Prerequisites check completed successfully"
}

# Function to set environment variables
set_environment_variables() {
    log "Setting environment variables..."
    
    # Generate unique suffix for resources
    if [[ -z "${RANDOM_SUFFIX:-}" ]]; then
        export RANDOM_SUFFIX=$(openssl rand -hex 3 2>/dev/null || echo $(date +%s | tail -c 6))
    fi
    
    # Set core variables
    export RESOURCE_GROUP="${RESOURCE_GROUP:-rg-infra-lifecycle-${RANDOM_SUFFIX}}"
    export LOCATION="${LOCATION:-eastus}"
    export SUBSCRIPTION_ID="${SUBSCRIPTION_ID:-$(az account show --query id --output tsv)}"
    
    # Set deployment and update management variables
    export DEPLOYMENT_STACK_NAME="${DEPLOYMENT_STACK_NAME:-stack-web-tier-${RANDOM_SUFFIX}}"
    export MAINTENANCE_CONFIG_NAME="${MAINTENANCE_CONFIG_NAME:-mc-weekly-updates-${RANDOM_SUFFIX}}"
    export LOG_ANALYTICS_WORKSPACE="${LOG_ANALYTICS_WORKSPACE:-law-monitoring-${RANDOM_SUFFIX}}"
    
    # Set VM credentials (use secure defaults)
    export VM_ADMIN_USERNAME="${VM_ADMIN_USERNAME:-azureuser}"
    export VM_ADMIN_PASSWORD="${VM_ADMIN_PASSWORD:-ComplexP@ssw0rd123!}"
    
    # Display configuration
    info "Configuration:"
    info "  Resource Group: $RESOURCE_GROUP"
    info "  Location: $LOCATION"
    info "  Subscription: $SUBSCRIPTION_ID"
    info "  Deployment Stack: $DEPLOYMENT_STACK_NAME"
    info "  Maintenance Config: $MAINTENANCE_CONFIG_NAME"
    info "  Log Analytics Workspace: $LOG_ANALYTICS_WORKSPACE"
    info "  Random Suffix: $RANDOM_SUFFIX"
}

# Function to create resource group
create_resource_group() {
    log "Creating resource group..."
    
    if az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        warning "Resource group $RESOURCE_GROUP already exists. Skipping creation."
    else
        az group create \
            --name "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --tags purpose=recipe environment=demo created-by=deployment-script
        
        log "Resource group created successfully: $RESOURCE_GROUP"
    fi
}

# Function to create Log Analytics workspace
create_log_analytics_workspace() {
    log "Creating Log Analytics workspace..."
    
    if az monitor log-analytics workspace show --resource-group "$RESOURCE_GROUP" --workspace-name "$LOG_ANALYTICS_WORKSPACE" &> /dev/null; then
        warning "Log Analytics workspace $LOG_ANALYTICS_WORKSPACE already exists. Skipping creation."
    else
        az monitor log-analytics workspace create \
            --resource-group "$RESOURCE_GROUP" \
            --workspace-name "$LOG_ANALYTICS_WORKSPACE" \
            --location "$LOCATION" \
            --sku pergb2018 \
            --retention-time 30
        
        log "Log Analytics workspace created successfully: $LOG_ANALYTICS_WORKSPACE"
    fi
}

# Function to create Bicep template
create_bicep_template() {
    log "Creating Bicep template..."
    
    # Create the bicep directory if it doesn't exist
    mkdir -p "$(dirname "$TEMPLATE_FILE")"
    
    cat > "$TEMPLATE_FILE" << 'EOF'
@description('Location for all resources')
param location string = resourceGroup().location

@description('Admin username for VMs')
param adminUsername string = 'azureuser'

@description('Admin password for VMs')
@secure()
param adminPassword string

@description('Size of VMs')
param vmSize string = 'Standard_B2s'

@description('Number of VM instances')
param instanceCount int = 2

@description('Unique suffix for resource names')
param uniqueSuffix string = uniqueString(resourceGroup().id)

// Virtual Network
resource vnet 'Microsoft.Network/virtualNetworks@2023-09-01' = {
  name: 'vnet-webtier-${uniqueSuffix}'
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.0.0.0/16'
      ]
    }
    subnets: [
      {
        name: 'subnet-web'
        properties: {
          addressPrefix: '10.0.1.0/24'
        }
      }
    ]
  }
}

// Network Security Group
resource nsg 'Microsoft.Network/networkSecurityGroups@2023-09-01' = {
  name: 'nsg-webtier-${uniqueSuffix}'
  location: location
  properties: {
    securityRules: [
      {
        name: 'AllowHTTP'
        properties: {
          priority: 1000
          protocol: 'Tcp'
          access: 'Allow'
          direction: 'Inbound'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '80'
        }
      }
      {
        name: 'AllowSSH'
        properties: {
          priority: 1001
          protocol: 'Tcp'
          access: 'Allow'
          direction: 'Inbound'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '22'
        }
      }
    ]
  }
}

// Public IP for Load Balancer
resource publicIp 'Microsoft.Network/publicIPAddresses@2023-09-01' = {
  name: 'pip-webtier-lb-${uniqueSuffix}'
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
  }
}

// Load Balancer
resource loadBalancer 'Microsoft.Network/loadBalancers@2023-09-01' = {
  name: 'lb-webtier-${uniqueSuffix}'
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    frontendIPConfigurations: [
      {
        name: 'LoadBalancerFrontEnd'
        properties: {
          publicIPAddress: {
            id: publicIp.id
          }
        }
      }
    ]
    backendAddressPools: [
      {
        name: 'BackendPool'
      }
    ]
    loadBalancingRules: [
      {
        name: 'HTTPRule'
        properties: {
          frontendIPConfiguration: {
            id: resourceId('Microsoft.Network/loadBalancers/frontendIPConfigurations', 'lb-webtier-${uniqueSuffix}', 'LoadBalancerFrontEnd')
          }
          backendAddressPool: {
            id: resourceId('Microsoft.Network/loadBalancers/backendAddressPools', 'lb-webtier-${uniqueSuffix}', 'BackendPool')
          }
          protocol: 'Tcp'
          frontendPort: 80
          backendPort: 80
          enableFloatingIP: false
          idleTimeoutInMinutes: 5
          probe: {
            id: resourceId('Microsoft.Network/loadBalancers/probes', 'lb-webtier-${uniqueSuffix}', 'tcpProbe')
          }
        }
      }
    ]
    probes: [
      {
        name: 'tcpProbe'
        properties: {
          protocol: 'Tcp'
          port: 80
          intervalInSeconds: 5
          numberOfProbes: 2
        }
      }
    ]
  }
}

// Virtual Machine Scale Set
resource vmss 'Microsoft.Compute/virtualMachineScaleSets@2023-09-01' = {
  name: 'vmss-webtier-${uniqueSuffix}'
  location: location
  sku: {
    name: vmSize
    tier: 'Standard'
    capacity: instanceCount
  }
  properties: {
    upgradePolicy: {
      mode: 'Manual'
    }
    virtualMachineProfile: {
      osProfile: {
        computerNamePrefix: 'web'
        adminUsername: adminUsername
        adminPassword: adminPassword
      }
      storageProfile: {
        osDisk: {
          createOption: 'FromImage'
          caching: 'ReadWrite'
          managedDisk: {
            storageAccountType: 'Premium_LRS'
          }
        }
        imageReference: {
          publisher: 'Canonical'
          offer: '0001-com-ubuntu-server-jammy'
          sku: '22_04-lts-gen2'
          version: 'latest'
        }
      }
      networkProfile: {
        networkInterfaceConfigurations: [
          {
            name: 'nic-webtier'
            properties: {
              primary: true
              ipConfigurations: [
                {
                  name: 'ipconfig1'
                  properties: {
                    subnet: {
                      id: '${vnet.id}/subnets/subnet-web'
                    }
                    loadBalancerBackendAddressPools: [
                      {
                        id: '${loadBalancer.id}/backendAddressPools/BackendPool'
                      }
                    ]
                  }
                }
              ]
              networkSecurityGroup: {
                id: nsg.id
              }
            }
          }
        ]
      }
      extensionProfile: {
        extensions: [
          {
            name: 'customScript'
            properties: {
              publisher: 'Microsoft.Azure.Extensions'
              type: 'CustomScript'
              typeHandlerVersion: '2.1'
              autoUpgradeMinorVersion: true
              settings: {
                commandToExecute: 'apt-get update && apt-get install -y nginx && systemctl enable nginx && systemctl start nginx'
              }
            }
          }
        ]
      }
    }
  }
}

output loadBalancerIP string = publicIp.properties.ipAddress
output vmssName string = vmss.name
output vnetId string = vnet.id
output publicIpId string = publicIp.id
output loadBalancerId string = loadBalancer.id
output nsgId string = nsg.id
EOF

    log "Bicep template created successfully"
}

# Function to create deployment stack
create_deployment_stack() {
    log "Creating Azure Deployment Stack..."
    
    # Check if deployment stack already exists
    if az stack group show --name "$DEPLOYMENT_STACK_NAME" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        warning "Deployment stack $DEPLOYMENT_STACK_NAME already exists. Updating..."
        
        az stack group create \
            --name "$DEPLOYMENT_STACK_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --template-file "$TEMPLATE_FILE" \
            --parameters adminPassword="$VM_ADMIN_PASSWORD" adminUsername="$VM_ADMIN_USERNAME" uniqueSuffix="$RANDOM_SUFFIX" \
            --action-on-unmanage deleteAll \
            --deny-settings-mode denyWriteAndDelete \
            --deny-settings-apply-to-child-scopes \
            --yes
    else
        az stack group create \
            --name "$DEPLOYMENT_STACK_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --template-file "$TEMPLATE_FILE" \
            --parameters adminPassword="$VM_ADMIN_PASSWORD" adminUsername="$VM_ADMIN_USERNAME" uniqueSuffix="$RANDOM_SUFFIX" \
            --action-on-unmanage deleteAll \
            --deny-settings-mode denyWriteAndDelete \
            --deny-settings-apply-to-child-scopes
    fi
    
    log "Deployment stack created successfully: $DEPLOYMENT_STACK_NAME"
}

# Function to create maintenance configuration
create_maintenance_configuration() {
    log "Creating maintenance configuration..."
    
    if az maintenance configuration show --resource-group "$RESOURCE_GROUP" --resource-name "$MAINTENANCE_CONFIG_NAME" &> /dev/null; then
        warning "Maintenance configuration $MAINTENANCE_CONFIG_NAME already exists. Skipping creation."
    else
        az maintenance configuration create \
            --resource-group "$RESOURCE_GROUP" \
            --resource-name "$MAINTENANCE_CONFIG_NAME" \
            --location "$LOCATION" \
            --maintenance-scope InGuestPatch \
            --recurring-schedules '[{
                "frequency": "Week",
                "interval": 1,
                "startTime": "2024-01-01 02:00",
                "timeZone": "UTC",
                "duration": "03:00",
                "daysOfWeek": ["Sunday"]
            }]' \
            --reboot-setting IfRequired \
            --windows-classifications-to-include Critical Security \
            --linux-classifications-to-include Critical Security \
            --install-patches-linux-parameters packageNameMasksToInclude='*' \
            --install-patches-windows-parameters classificationsToInclude='Critical,Security'
        
        log "Maintenance configuration created successfully: $MAINTENANCE_CONFIG_NAME"
    fi
}

# Function to assign maintenance configuration
assign_maintenance_configuration() {
    log "Assigning maintenance configuration to resources..."
    
    # Get VMSS resource ID from deployment stack
    local vmss_resource_id=$(az stack group show \
        --name "$DEPLOYMENT_STACK_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --query "resources[?type=='Microsoft.Compute/virtualMachineScaleSets'].id" \
        --output tsv)
    
    if [[ -z "$vmss_resource_id" ]]; then
        error "Could not find VMSS resource ID in deployment stack"
        exit 1
    fi
    
    info "VMSS Resource ID: $vmss_resource_id"
    
    # Create maintenance assignment for VMSS
    az maintenance assignment create \
        --resource-group "$RESOURCE_GROUP" \
        --resource-name "maintenance-assignment-vmss-${RANDOM_SUFFIX}" \
        --resource-type Microsoft.Compute/virtualMachineScaleSets \
        --resource-id "$vmss_resource_id" \
        --maintenance-configuration-id "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.Maintenance/maintenanceConfigurations/${MAINTENANCE_CONFIG_NAME}"
    
    log "Maintenance assignment created for VMSS resources"
}

# Function to configure monitoring
configure_monitoring() {
    log "Configuring monitoring and diagnostic settings..."
    
    # Get workspace ID
    local workspace_id=$(az monitor log-analytics workspace show \
        --resource-group "$RESOURCE_GROUP" \
        --workspace-name "$LOG_ANALYTICS_WORKSPACE" \
        --query id --output tsv)
    
    # Get VMSS resource ID
    local vmss_resource_id=$(az stack group show \
        --name "$DEPLOYMENT_STACK_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --query "resources[?type=='Microsoft.Compute/virtualMachineScaleSets'].id" \
        --output tsv)
    
    if [[ -n "$vmss_resource_id" && -n "$workspace_id" ]]; then
        # Enable diagnostic settings for VMSS
        az monitor diagnostic-settings create \
            --name "diag-${DEPLOYMENT_STACK_NAME}" \
            --resource "$vmss_resource_id" \
            --workspace "$workspace_id" \
            --logs '[{
                "category": "Administrative",
                "enabled": true,
                "retentionPolicy": {
                    "enabled": true,
                    "days": 30
                }
            }]' \
            --metrics '[{
                "category": "AllMetrics",
                "enabled": true,
                "retentionPolicy": {
                    "enabled": true,
                    "days": 30
                }
            }]' || warning "Failed to configure diagnostic settings for VMSS"
        
        log "Monitoring configured for deployment stack resources"
    else
        warning "Could not configure monitoring - missing workspace or VMSS resource ID"
    fi
}

# Function to configure Azure Policy
configure_azure_policy() {
    log "Configuring Azure Policy for governance..."
    
    # Create policy definition JSON
    cat > "${SCRIPT_DIR}/policy-definition.json" << 'EOF'
{
  "mode": "All",
  "policyRule": {
    "if": {
      "allOf": [
        {
          "field": "type",
          "equals": "Microsoft.Resources/deploymentStacks"
        },
        {
          "field": "Microsoft.Resources/deploymentStacks/denySettings.mode",
          "notEquals": "denyWriteAndDelete"
        }
      ]
    },
    "then": {
      "effect": "deny"
    }
  },
  "parameters": {}
}
EOF
    
    # Create policy definition
    az policy definition create \
        --name "enforce-deployment-stack-deny-settings" \
        --display-name "Enforce Deployment Stack Deny Settings" \
        --description "Ensures all deployment stacks have appropriate deny settings configured" \
        --rules "${SCRIPT_DIR}/policy-definition.json" \
        --mode All || warning "Policy definition may already exist"
    
    # Assign policy to resource group
    az policy assignment create \
        --name "deployment-stack-governance" \
        --display-name "Deployment Stack Governance" \
        --policy "enforce-deployment-stack-deny-settings" \
        --scope "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}" || warning "Policy assignment may already exist"
    
    log "Azure Policy configured for deployment stack governance"
}

# Function to create compliance workbook
create_compliance_workbook() {
    log "Creating compliance reporting workbook..."
    
    # Create workbook JSON
    cat > "${SCRIPT_DIR}/compliance-workbook.json" << 'EOF'
{
  "version": "Notebook/1.0",
  "items": [
    {
      "type": 1,
      "content": {
        "json": "# Infrastructure Lifecycle Management Dashboard\n\nThis dashboard provides insights into deployment stack status and update compliance across your infrastructure."
      }
    },
    {
      "type": 3,
      "content": {
        "version": "KqlItem/1.0",
        "query": "PatchAssessmentResources\n| where TimeGenerated >= ago(7d)\n| summarize UpdatesAvailable = countif(UpdateState == \"Available\"), UpdatesInstalled = countif(UpdateState == \"Installed\") by ComputerName\n| order by UpdatesAvailable desc",
        "size": 0,
        "title": "Update Compliance Summary",
        "timeContext": {
          "durationMs": 604800000
        },
        "queryType": 1,
        "resourceType": "microsoft.resourcegraph/resources"
      }
    }
  ]
}
EOF
    
    # Create Azure Workbook
    az monitor workbook create \
        --resource-group "$RESOURCE_GROUP" \
        --name "infrastructure-lifecycle-dashboard" \
        --display-name "Infrastructure Lifecycle Management Dashboard" \
        --serialized-data "@${SCRIPT_DIR}/compliance-workbook.json" \
        --location "$LOCATION" || warning "Workbook creation may have failed"
    
    log "Compliance reporting workbook created"
}

# Function to validate deployment
validate_deployment() {
    log "Validating deployment..."
    
    # Check deployment stack status
    local stack_status=$(az stack group show \
        --name "$DEPLOYMENT_STACK_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --query "provisioningState" \
        --output tsv 2>/dev/null || echo "NotFound")
    
    if [[ "$stack_status" == "Succeeded" ]]; then
        log "✅ Deployment stack is in successful state"
    else
        error "❌ Deployment stack status: $stack_status"
    fi
    
    # Check maintenance configuration
    local maintenance_status=$(az maintenance configuration show \
        --resource-group "$RESOURCE_GROUP" \
        --resource-name "$MAINTENANCE_CONFIG_NAME" \
        --query "properties.provisioningState" \
        --output tsv 2>/dev/null || echo "NotFound")
    
    if [[ "$maintenance_status" == "Succeeded" ]]; then
        log "✅ Maintenance configuration is active"
    else
        warning "⚠️ Maintenance configuration status: $maintenance_status"
    fi
    
    # Get load balancer IP
    local lb_ip=$(az network public-ip show \
        --resource-group "$RESOURCE_GROUP" \
        --name "pip-webtier-lb-${RANDOM_SUFFIX}" \
        --query ipAddress \
        --output tsv 2>/dev/null || echo "NotFound")
    
    if [[ "$lb_ip" != "NotFound" ]]; then
        log "✅ Load balancer public IP: $lb_ip"
        info "You can test the web server at: http://$lb_ip (may take a few minutes to be available)"
    else
        warning "⚠️ Could not retrieve load balancer IP"
    fi
    
    log "Deployment validation completed"
}

# Function to display deployment summary
display_summary() {
    log "Deployment Summary"
    echo "===================="
    echo "Resource Group: $RESOURCE_GROUP"
    echo "Deployment Stack: $DEPLOYMENT_STACK_NAME"
    echo "Maintenance Configuration: $MAINTENANCE_CONFIG_NAME"
    echo "Log Analytics Workspace: $LOG_ANALYTICS_WORKSPACE"
    echo "Location: $LOCATION"
    echo "Random Suffix: $RANDOM_SUFFIX"
    echo ""
    echo "Next Steps:"
    echo "1. Monitor deployment stack resources in the Azure portal"
    echo "2. Review maintenance schedules and update policies"
    echo "3. Check compliance dashboard for update status"
    echo "4. Test the deployed web application"
    echo ""
    echo "To clean up resources, run: ./destroy.sh"
}

# Main execution function
main() {
    log "Starting Azure Infrastructure Lifecycle Management deployment..."
    
    # Initialize log file
    echo "Azure Infrastructure Lifecycle Management Deployment Log" > "$LOG_FILE"
    echo "Started at: $(date)" >> "$LOG_FILE"
    echo "=========================================" >> "$LOG_FILE"
    
    # Execute deployment steps
    check_prerequisites
    set_environment_variables
    create_resource_group
    create_log_analytics_workspace
    create_bicep_template
    create_deployment_stack
    create_maintenance_configuration
    assign_maintenance_configuration
    configure_monitoring
    configure_azure_policy
    create_compliance_workbook
    validate_deployment
    display_summary
    
    log "Deployment completed successfully!"
    log "Log file available at: $LOG_FILE"
}

# Handle script interruption
trap 'error "Script interrupted. Check the log file for details: $LOG_FILE"; exit 1' INT TERM

# Run main function
main "$@"