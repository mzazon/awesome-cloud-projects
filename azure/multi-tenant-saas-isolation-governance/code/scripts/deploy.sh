#!/bin/bash

# Multi-Tenant SaaS Resource Isolation Deployment Script
# This script deploys Azure Deployment Stacks and Azure Workload Identity for multi-tenant SaaS resource isolation

set -e  # Exit on any error
set -u  # Exit on undefined variables

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

success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✅ $1${NC}"
}

warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️  $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ❌ $1${NC}"
}

# Check if running in dry-run mode
DRY_RUN=false
if [[ "${1:-}" == "--dry-run" ]]; then
    DRY_RUN=true
    warning "Running in dry-run mode - no resources will be created"
fi

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
        error "Please log in to Azure using 'az login'"
        exit 1
    fi
    
    # Check if jq is installed for JSON parsing
    if ! command -v jq &> /dev/null; then
        error "jq is not installed. Please install it for JSON parsing"
        exit 1
    fi
    
    # Check if openssl is available for random string generation
    if ! command -v openssl &> /dev/null; then
        error "openssl is not installed. Please install it for random string generation"
        exit 1
    fi
    
    success "All prerequisites met"
}

# Function to set environment variables
set_environment_variables() {
    log "Setting environment variables..."
    
    # Default values
    export RESOURCE_GROUP=${RESOURCE_GROUP:-"rg-saas-control-plane"}
    export LOCATION=${LOCATION:-"eastus"}
    export SUBSCRIPTION_ID=$(az account show --query id --output tsv)
    export TENANT_ID=$(az account show --query tenantId --output tsv)
    
    # Generate unique suffix for resource names
    RANDOM_SUFFIX=$(openssl rand -hex 3)
    export SAAS_PREFIX="saas${RANDOM_SUFFIX}"
    
    log "Resource Group: ${RESOURCE_GROUP}"
    log "Location: ${LOCATION}"
    log "Subscription ID: ${SUBSCRIPTION_ID}"
    log "SaaS Prefix: ${SAAS_PREFIX}"
    
    success "Environment variables set"
}

# Function to create control plane infrastructure
create_control_plane() {
    log "Creating control plane infrastructure..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY RUN: Would create resource group ${RESOURCE_GROUP}"
        return 0
    fi
    
    # Create control plane resource group
    log "Creating resource group: ${RESOURCE_GROUP}"
    az group create \
        --name "${RESOURCE_GROUP}" \
        --location "${LOCATION}" \
        --tags purpose=saas-control-plane environment=production
    
    # Create shared Key Vault for secrets management
    log "Creating Key Vault: kv-${SAAS_PREFIX}"
    az keyvault create \
        --name "kv-${SAAS_PREFIX}" \
        --resource-group "${RESOURCE_GROUP}" \
        --location "${LOCATION}" \
        --sku standard \
        --enable-rbac-authorization true
    
    # Create managed identity for deployment operations
    log "Creating managed identity: mi-deployment-${SAAS_PREFIX}"
    az identity create \
        --name "mi-deployment-${SAAS_PREFIX}" \
        --resource-group "${RESOURCE_GROUP}" \
        --location "${LOCATION}"
    
    # Get managed identity details
    export DEPLOYMENT_MI_ID=$(az identity show \
        --name "mi-deployment-${SAAS_PREFIX}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query id --output tsv)
    
    export DEPLOYMENT_MI_CLIENT_ID=$(az identity show \
        --name "mi-deployment-${SAAS_PREFIX}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query clientId --output tsv)
    
    success "Control plane infrastructure created"
}

# Function to create Azure Policy definitions
create_policy_definitions() {
    log "Creating Azure Policy definitions for tenant isolation..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY RUN: Would create Azure Policy definitions"
        return 0
    fi
    
    # Create tenant tagging policy
    cat > /tmp/tenant-tagging-policy.json << 'EOF'
{
  "mode": "All",
  "policyRule": {
    "if": {
      "allOf": [
        {
          "field": "type",
          "notIn": [
            "Microsoft.Resources/resourceGroups",
            "Microsoft.Resources/subscriptions"
          ]
        },
        {
          "anyOf": [
            {
              "field": "tags['TenantId']",
              "exists": "false"
            },
            {
              "field": "tags['Environment']",
              "exists": "false"
            }
          ]
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
        --name "require-tenant-tags" \
        --display-name "Require Tenant Tags" \
        --description "Ensures all resources have required tenant identification tags" \
        --rules /tmp/tenant-tagging-policy.json \
        --mode All
    
    # Create network isolation policy
    cat > /tmp/network-isolation-policy.json << 'EOF'
{
  "mode": "All",
  "policyRule": {
    "if": {
      "allOf": [
        {
          "field": "type",
          "equals": "Microsoft.Network/virtualNetworks"
        },
        {
          "field": "Microsoft.Network/virtualNetworks/subnets[*].networkSecurityGroup.id",
          "exists": "false"
        }
      ]
    },
    "then": {
      "effect": "deny"
    }
  }
}
EOF
    
    az policy definition create \
        --name "require-network-security-groups" \
        --display-name "Require Network Security Groups" \
        --description "Ensures all virtual networks have network security groups" \
        --rules /tmp/network-isolation-policy.json \
        --mode All
    
    # Clean up temporary files
    rm -f /tmp/tenant-tagging-policy.json /tmp/network-isolation-policy.json
    
    success "Azure Policy definitions created for tenant isolation"
}

# Function to configure workload identity
configure_workload_identity() {
    log "Configuring workload identity for tenant-specific authentication..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY RUN: Would configure workload identity"
        return 0
    fi
    
    # Create workload identity application
    az ad app create \
        --display-name "SaaS-Tenant-Workload-${SAAS_PREFIX}" \
        --sign-in-audience AzureADMyOrg
    
    export WORKLOAD_APP_ID=$(az ad app list \
        --display-name "SaaS-Tenant-Workload-${SAAS_PREFIX}" \
        --query '[0].appId' --output tsv)
    
    # Create service principal for the workload identity
    az ad sp create \
        --id "${WORKLOAD_APP_ID}"
    
    export WORKLOAD_SP_ID=$(az ad sp show \
        --id "${WORKLOAD_APP_ID}" \
        --query id --output tsv)
    
    # Configure federated identity credentials
    cat > /tmp/federated-credential.json << EOF
{
  "name": "tenant-workload-federation",
  "issuer": "https://sts.windows.net/${TENANT_ID}/",
  "subject": "system:serviceaccount:tenant-namespace:tenant-workload",
  "description": "Federated identity for tenant workload",
  "audiences": ["api://AzureADTokenExchange"]
}
EOF
    
    az ad app federated-credential create \
        --id "${WORKLOAD_APP_ID}" \
        --parameters /tmp/federated-credential.json
    
    # Grant necessary permissions to the workload identity
    az role assignment create \
        --assignee "${WORKLOAD_SP_ID}" \
        --role "Deployment Stack Contributor" \
        --scope "/subscriptions/${SUBSCRIPTION_ID}"
    
    # Clean up temporary files
    rm -f /tmp/federated-credential.json
    
    success "Workload identity configured for tenant authentication"
}

# Function to create deployment stack templates
create_deployment_stack_templates() {
    log "Creating deployment stack templates for tenant isolation..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY RUN: Would create deployment stack templates"
        return 0
    fi
    
    # Create tenant stack template
    cat > /tmp/tenant-stack-template.json << 'EOF'
{
  "$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {
    "tenantId": {
      "type": "string",
      "metadata": {
        "description": "Unique identifier for the tenant"
      }
    },
    "tenantName": {
      "type": "string",
      "metadata": {
        "description": "Display name for the tenant"
      }
    },
    "environment": {
      "type": "string",
      "defaultValue": "production",
      "allowedValues": ["development", "staging", "production"]
    },
    "location": {
      "type": "string",
      "defaultValue": "[resourceGroup().location]"
    }
  },
  "variables": {
    "resourcePrefix": "[concat('tenant-', parameters('tenantId'))]",
    "tags": {
      "TenantId": "[parameters('tenantId')]",
      "TenantName": "[parameters('tenantName')]",
      "Environment": "[parameters('environment')]",
      "ManagedBy": "DeploymentStack"
    }
  },
  "resources": [
    {
      "type": "Microsoft.Storage/storageAccounts",
      "apiVersion": "2023-01-01",
      "name": "[concat(variables('resourcePrefix'), 'storage')]",
      "location": "[parameters('location')]",
      "tags": "[variables('tags')]",
      "sku": {
        "name": "Standard_LRS"
      },
      "kind": "StorageV2",
      "properties": {
        "supportsHttpsTrafficOnly": true,
        "minimumTlsVersion": "TLS1_2",
        "allowBlobPublicAccess": false,
        "networkAcls": {
          "defaultAction": "Deny"
        }
      }
    },
    {
      "type": "Microsoft.Network/virtualNetworks",
      "apiVersion": "2023-02-01",
      "name": "[concat(variables('resourcePrefix'), '-vnet')]",
      "location": "[parameters('location')]",
      "tags": "[variables('tags')]",
      "properties": {
        "addressSpace": {
          "addressPrefixes": [
            "10.0.0.0/16"
          ]
        },
        "subnets": [
          {
            "name": "tenant-subnet",
            "properties": {
              "addressPrefix": "10.0.1.0/24",
              "networkSecurityGroup": {
                "id": "[resourceId('Microsoft.Network/networkSecurityGroups', concat(variables('resourcePrefix'), '-nsg'))]"
              }
            }
          }
        ]
      },
      "dependsOn": [
        "[resourceId('Microsoft.Network/networkSecurityGroups', concat(variables('resourcePrefix'), '-nsg'))]"
      ]
    },
    {
      "type": "Microsoft.Network/networkSecurityGroups",
      "apiVersion": "2023-02-01",
      "name": "[concat(variables('resourcePrefix'), '-nsg')]",
      "location": "[parameters('location')]",
      "tags": "[variables('tags')]",
      "properties": {
        "securityRules": [
          {
            "name": "DenyAllInbound",
            "properties": {
              "protocol": "*",
              "sourceAddressPrefix": "*",
              "sourcePortRange": "*",
              "destinationAddressPrefix": "*",
              "destinationPortRange": "*",
              "access": "Deny",
              "priority": 1000,
              "direction": "Inbound"
            }
          }
        ]
      }
    }
  ],
  "outputs": {
    "tenantId": {
      "type": "string",
      "value": "[parameters('tenantId')]"
    },
    "storageAccountId": {
      "type": "string",
      "value": "[resourceId('Microsoft.Storage/storageAccounts', concat(variables('resourcePrefix'), 'storage'))]"
    },
    "virtualNetworkId": {
      "type": "string",
      "value": "[resourceId('Microsoft.Network/virtualNetworks', concat(variables('resourcePrefix'), '-vnet'))]"
    }
  }
}
EOF
    
    success "Deployment stack template created for tenant isolation"
}

# Function to provision sample tenants
provision_sample_tenants() {
    log "Provisioning sample tenants..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY RUN: Would provision sample tenants"
        return 0
    fi
    
    # Function to provision a tenant
    provision_tenant() {
        local tenant_id=$1
        local tenant_name=$2
        local environment=${3:-production}
        
        log "Provisioning tenant: ${tenant_id}"
        
        # Create tenant-specific resource group
        az group create \
            --name "rg-tenant-${tenant_id}" \
            --location "${LOCATION}" \
            --tags TenantId="${tenant_id}" TenantName="${tenant_name}" Environment="${environment}"
        
        # Deploy tenant resources using deployment stack template
        az deployment group create \
            --resource-group "rg-tenant-${tenant_id}" \
            --template-file /tmp/tenant-stack-template.json \
            --parameters \
                tenantId="${tenant_id}" \
                tenantName="${tenant_name}" \
                environment="${environment}" \
            --name "tenant-${tenant_id}-deployment"
        
        # Assign workload identity permissions to tenant resources
        az role assignment create \
            --assignee "${WORKLOAD_SP_ID}" \
            --role "Storage Blob Data Contributor" \
            --scope "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/rg-tenant-${tenant_id}"
        
        success "Tenant ${tenant_id} provisioned successfully"
    }
    
    # Provision sample tenants
    provision_tenant "tenant001" "Contoso Corp" "production"
    provision_tenant "tenant002" "Fabrikam Inc" "production"
    
    success "Sample tenants provisioned with deployment stacks"
}

# Function to configure RBAC
configure_rbac() {
    log "Configuring cross-tenant access controls and RBAC..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY RUN: Would configure RBAC"
        return 0
    fi
    
    # Create custom role for tenant administrators
    cat > /tmp/tenant-admin-role.json << EOF
{
  "Name": "Tenant Administrator",
  "Id": null,
  "IsCustom": true,
  "Description": "Full control over tenant-specific resources",
  "Actions": [
    "Microsoft.Resources/subscriptions/resourceGroups/read",
    "Microsoft.Resources/subscriptions/resourceGroups/resources/read",
    "Microsoft.Storage/storageAccounts/*",
    "Microsoft.Network/virtualNetworks/*",
    "Microsoft.Network/networkSecurityGroups/*",
    "Microsoft.Compute/virtualMachines/*"
  ],
  "NotActions": [],
  "DataActions": [
    "Microsoft.Storage/storageAccounts/blobServices/containers/blobs/*"
  ],
  "NotDataActions": [],
  "AssignableScopes": [
    "/subscriptions/${SUBSCRIPTION_ID}"
  ]
}
EOF
    
    # Create the custom role
    az role definition create \
        --role-definition /tmp/tenant-admin-role.json
    
    # Create custom role for tenant users (read-only access)
    cat > /tmp/tenant-user-role.json << EOF
{
  "Name": "Tenant User",
  "Id": null,
  "IsCustom": true,
  "Description": "Read-only access to tenant-specific resources",
  "Actions": [
    "Microsoft.Resources/subscriptions/resourceGroups/read",
    "Microsoft.Resources/subscriptions/resourceGroups/resources/read",
    "Microsoft.Storage/storageAccounts/read",
    "Microsoft.Network/virtualNetworks/read"
  ],
  "NotActions": [],
  "DataActions": [
    "Microsoft.Storage/storageAccounts/blobServices/containers/blobs/read"
  ],
  "NotDataActions": [],
  "AssignableScopes": [
    "/subscriptions/${SUBSCRIPTION_ID}"
  ]
}
EOF
    
    # Create the custom role
    az role definition create \
        --role-definition /tmp/tenant-user-role.json
    
    # Clean up temporary files
    rm -f /tmp/tenant-admin-role.json /tmp/tenant-user-role.json
    
    success "Custom RBAC roles created for tenant access control"
}

# Function to configure monitoring
configure_monitoring() {
    log "Configuring monitoring and governance reporting..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY RUN: Would configure monitoring"
        return 0
    fi
    
    # Create shared monitoring workspace for the SaaS platform
    az monitor log-analytics workspace create \
        --resource-group "${RESOURCE_GROUP}" \
        --workspace-name "law-saas-platform-${SAAS_PREFIX}" \
        --location "${LOCATION}"
    
    export WORKSPACE_ID=$(az monitor log-analytics workspace show \
        --resource-group "${RESOURCE_GROUP}" \
        --workspace-name "law-saas-platform-${SAAS_PREFIX}" \
        --query id --output tsv)
    
    # Create Application Insights for platform monitoring
    az monitor app-insights component create \
        --app "ai-saas-platform-${SAAS_PREFIX}" \
        --location "${LOCATION}" \
        --resource-group "${RESOURCE_GROUP}" \
        --workspace "${WORKSPACE_ID}"
    
    success "Monitoring and governance reporting configured"
}

# Function to validate deployment
validate_deployment() {
    log "Validating deployment..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY RUN: Would validate deployment"
        return 0
    fi
    
    # Verify tenant resource groups exist
    log "Checking tenant resource groups..."
    local tenant_groups=$(az group list --query "[?contains(name, 'rg-tenant-')].name" --output tsv)
    if [[ -z "$tenant_groups" ]]; then
        error "No tenant resource groups found"
        return 1
    fi
    
    # Verify workload identity exists
    log "Checking workload identity..."
    local workload_app=$(az ad app show --id "${WORKLOAD_APP_ID}" --query displayName --output tsv 2>/dev/null)
    if [[ -z "$workload_app" ]]; then
        error "Workload identity not found"
        return 1
    fi
    
    # Verify policies exist
    log "Checking policy definitions..."
    local tenant_tags_policy=$(az policy definition show --name "require-tenant-tags" --query displayName --output tsv 2>/dev/null)
    if [[ -z "$tenant_tags_policy" ]]; then
        error "Tenant tags policy not found"
        return 1
    fi
    
    success "Deployment validation completed successfully"
}

# Function to display deployment summary
display_summary() {
    log "Deployment Summary"
    echo "====================="
    echo "Resource Group: ${RESOURCE_GROUP}"
    echo "Location: ${LOCATION}"
    echo "SaaS Prefix: ${SAAS_PREFIX}"
    echo "Subscription ID: ${SUBSCRIPTION_ID}"
    echo "Workload App ID: ${WORKLOAD_APP_ID:-N/A}"
    echo "====================="
    
    if [[ "$DRY_RUN" == "false" ]]; then
        success "Multi-tenant SaaS resource isolation deployment completed successfully!"
        warning "Remember to run the cleanup script (destroy.sh) when you're done to avoid unnecessary charges."
    else
        success "Dry run completed - no resources were created"
    fi
}

# Main deployment function
main() {
    log "Starting multi-tenant SaaS resource isolation deployment..."
    
    check_prerequisites
    set_environment_variables
    create_control_plane
    create_policy_definitions
    configure_workload_identity
    create_deployment_stack_templates
    provision_sample_tenants
    configure_rbac
    configure_monitoring
    validate_deployment
    display_summary
    
    # Clean up temporary files
    rm -f /tmp/tenant-stack-template.json
}

# Error handling
trap 'error "Deployment failed. Check the logs above for details."' ERR

# Run main function
main "$@"