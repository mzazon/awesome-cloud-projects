#!/bin/bash

# Azure Infrastructure Provisioning with Azure Automation and ARM Templates
# Deploy Script
# This script deploys the complete Azure Automation infrastructure for ARM template deployment

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
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1${NC}"
}

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command_exists az; then
        error "Azure CLI is not installed. Please install it from https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
        exit 1
    fi
    
    # Check if user is logged in to Azure
    if ! az account show >/dev/null 2>&1; then
        error "You are not logged in to Azure. Please run 'az login' first."
        exit 1
    fi
    
    # Check if openssl is available for random string generation
    if ! command_exists openssl; then
        error "openssl is not available. Please install it for random string generation."
        exit 1
    fi
    
    log "Prerequisites check passed ✅"
}

# Function to set environment variables
set_environment_variables() {
    log "Setting environment variables..."
    
    # Set default values with validation
    export RESOURCE_GROUP="${RESOURCE_GROUP:-rg-automation-demo}"
    export LOCATION="${LOCATION:-eastus}"
    export AUTOMATION_ACCOUNT="${AUTOMATION_ACCOUNT:-aa-infra-provisioning}"
    export STORAGE_ACCOUNT="${STORAGE_ACCOUNT:-stautoarmtemplates$(openssl rand -hex 3)}"
    export LOG_ANALYTICS_WORKSPACE="${LOG_ANALYTICS_WORKSPACE:-law-automation-monitoring}"
    export SUBSCRIPTION_ID=$(az account show --query id --output tsv)
    
    # Generate unique suffix for resource names
    export RANDOM_SUFFIX=$(openssl rand -hex 3)
    
    # Validate location
    if ! az account list-locations --query "[?name=='${LOCATION}']" --output tsv >/dev/null 2>&1; then
        error "Invalid Azure location: ${LOCATION}"
        exit 1
    fi
    
    # Validate storage account name (must be 3-24 characters, lowercase letters and numbers only)
    if [[ ! "${STORAGE_ACCOUNT}" =~ ^[a-z0-9]{3,24}$ ]]; then
        error "Invalid storage account name. Must be 3-24 characters, lowercase letters and numbers only."
        exit 1
    fi
    
    info "Environment variables set:"
    info "  Resource Group: ${RESOURCE_GROUP}"
    info "  Location: ${LOCATION}"
    info "  Automation Account: ${AUTOMATION_ACCOUNT}"
    info "  Storage Account: ${STORAGE_ACCOUNT}"
    info "  Log Analytics Workspace: ${LOG_ANALYTICS_WORKSPACE}"
    info "  Subscription ID: ${SUBSCRIPTION_ID}"
}

# Function to create resource group
create_resource_group() {
    log "Creating resource group..."
    
    if az group show --name "${RESOURCE_GROUP}" >/dev/null 2>&1; then
        warn "Resource group ${RESOURCE_GROUP} already exists. Skipping creation."
    else
        az group create \
            --name "${RESOURCE_GROUP}" \
            --location "${LOCATION}" \
            --tags purpose=automation environment=demo \
            --output none
        
        log "Resource group ${RESOURCE_GROUP} created successfully ✅"
    fi
}

# Function to create Log Analytics workspace
create_log_analytics_workspace() {
    log "Creating Log Analytics workspace..."
    
    if az monitor log-analytics workspace show \
        --resource-group "${RESOURCE_GROUP}" \
        --workspace-name "${LOG_ANALYTICS_WORKSPACE}" >/dev/null 2>&1; then
        warn "Log Analytics workspace ${LOG_ANALYTICS_WORKSPACE} already exists. Skipping creation."
    else
        az monitor log-analytics workspace create \
            --resource-group "${RESOURCE_GROUP}" \
            --workspace-name "${LOG_ANALYTICS_WORKSPACE}" \
            --location "${LOCATION}" \
            --sku PerGB2018 \
            --output none
        
        log "Log Analytics workspace ${LOG_ANALYTICS_WORKSPACE} created successfully ✅"
    fi
}

# Function to create Azure Automation Account
create_automation_account() {
    log "Creating Azure Automation Account..."
    
    if az automation account show \
        --resource-group "${RESOURCE_GROUP}" \
        --name "${AUTOMATION_ACCOUNT}" >/dev/null 2>&1; then
        warn "Automation Account ${AUTOMATION_ACCOUNT} already exists. Skipping creation."
    else
        az automation account create \
            --resource-group "${RESOURCE_GROUP}" \
            --name "${AUTOMATION_ACCOUNT}" \
            --location "${LOCATION}" \
            --sku Basic \
            --assign-identity \
            --output none
        
        log "Automation Account ${AUTOMATION_ACCOUNT} created successfully ✅"
    fi
    
    # Get the managed identity principal ID
    export MANAGED_IDENTITY_ID=$(az automation account show \
        --resource-group "${RESOURCE_GROUP}" \
        --name "${AUTOMATION_ACCOUNT}" \
        --query "identity.principalId" \
        --output tsv)
    
    info "Managed Identity ID: ${MANAGED_IDENTITY_ID}"
}

# Function to create storage account
create_storage_account() {
    log "Creating storage account for ARM templates..."
    
    if az storage account show \
        --resource-group "${RESOURCE_GROUP}" \
        --name "${STORAGE_ACCOUNT}" >/dev/null 2>&1; then
        warn "Storage account ${STORAGE_ACCOUNT} already exists. Skipping creation."
    else
        az storage account create \
            --name "${STORAGE_ACCOUNT}" \
            --resource-group "${RESOURCE_GROUP}" \
            --location "${LOCATION}" \
            --sku Standard_LRS \
            --kind StorageV2 \
            --output none
        
        log "Storage account ${STORAGE_ACCOUNT} created successfully ✅"
    fi
    
    # Get storage account key
    export STORAGE_KEY=$(az storage account keys list \
        --resource-group "${RESOURCE_GROUP}" \
        --account-name "${STORAGE_ACCOUNT}" \
        --query "[0].value" \
        --output tsv)
    
    # Create file share for ARM templates
    if az storage share show \
        --name arm-templates \
        --account-name "${STORAGE_ACCOUNT}" \
        --account-key "${STORAGE_KEY}" >/dev/null 2>&1; then
        warn "File share arm-templates already exists. Skipping creation."
    else
        az storage share create \
            --name arm-templates \
            --account-name "${STORAGE_ACCOUNT}" \
            --account-key "${STORAGE_KEY}" \
            --output none
        
        log "File share arm-templates created successfully ✅"
    fi
}

# Function to configure RBAC permissions
configure_rbac() {
    log "Configuring RBAC permissions..."
    
    # Wait for managed identity to be fully created
    info "Waiting for managed identity to be fully provisioned..."
    sleep 30
    
    # Assign Contributor role to managed identity for deployment operations
    if az role assignment list \
        --assignee "${MANAGED_IDENTITY_ID}" \
        --role "Contributor" \
        --scope "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}" \
        --query "[0].id" \
        --output tsv >/dev/null 2>&1; then
        warn "Contributor role already assigned to managed identity. Skipping."
    else
        az role assignment create \
            --assignee "${MANAGED_IDENTITY_ID}" \
            --role "Contributor" \
            --scope "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}" \
            --output none
        
        log "Contributor role assigned to managed identity ✅"
    fi
    
    # Assign Storage Blob Data Contributor for template access
    if az role assignment list \
        --assignee "${MANAGED_IDENTITY_ID}" \
        --role "Storage Blob Data Contributor" \
        --scope "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.Storage/storageAccounts/${STORAGE_ACCOUNT}" \
        --query "[0].id" \
        --output tsv >/dev/null 2>&1; then
        warn "Storage Blob Data Contributor role already assigned to managed identity. Skipping."
    else
        az role assignment create \
            --assignee "${MANAGED_IDENTITY_ID}" \
            --role "Storage Blob Data Contributor" \
            --scope "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.Storage/storageAccounts/${STORAGE_ACCOUNT}" \
            --output none
        
        log "Storage Blob Data Contributor role assigned to managed identity ✅"
    fi
}

# Function to create and upload ARM template
create_arm_template() {
    log "Creating and uploading ARM template..."
    
    # Create temporary file for ARM template
    local temp_template=$(mktemp)
    
    cat > "${temp_template}" << 'EOF'
{
    "$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#",
    "contentVersion": "1.0.0.0",
    "parameters": {
        "storageAccountType": {
            "type": "string",
            "defaultValue": "Standard_LRS",
            "allowedValues": [
                "Standard_LRS",
                "Standard_GRS",
                "Standard_ZRS"
            ],
            "metadata": {
                "description": "Storage Account type"
            }
        },
        "location": {
            "type": "string",
            "defaultValue": "[resourceGroup().location]",
            "metadata": {
                "description": "Location for all resources"
            }
        },
        "environment": {
            "type": "string",
            "defaultValue": "demo",
            "metadata": {
                "description": "Environment tag"
            }
        }
    },
    "variables": {
        "storageAccountName": "[concat('st', uniqueString(resourceGroup().id))]",
        "virtualNetworkName": "[concat('vnet-', parameters('environment'), '-', uniqueString(resourceGroup().id))]",
        "subnetName": "default"
    },
    "resources": [
        {
            "type": "Microsoft.Storage/storageAccounts",
            "apiVersion": "2021-09-01",
            "name": "[variables('storageAccountName')]",
            "location": "[parameters('location')]",
            "tags": {
                "environment": "[parameters('environment')]",
                "deployment": "automated"
            },
            "sku": {
                "name": "[parameters('storageAccountType')]"
            },
            "kind": "StorageV2",
            "properties": {
                "allowBlobPublicAccess": false,
                "supportsHttpsTrafficOnly": true
            }
        },
        {
            "type": "Microsoft.Network/virtualNetworks",
            "apiVersion": "2021-05-01",
            "name": "[variables('virtualNetworkName')]",
            "location": "[parameters('location')]",
            "tags": {
                "environment": "[parameters('environment')]",
                "deployment": "automated"
            },
            "properties": {
                "addressSpace": {
                    "addressPrefixes": [
                        "10.0.0.0/16"
                    ]
                },
                "subnets": [
                    {
                        "name": "[variables('subnetName')]",
                        "properties": {
                            "addressPrefix": "10.0.1.0/24"
                        }
                    }
                ]
            }
        }
    ],
    "outputs": {
        "storageAccountName": {
            "type": "string",
            "value": "[variables('storageAccountName')]"
        },
        "virtualNetworkName": {
            "type": "string",
            "value": "[variables('virtualNetworkName')]"
        },
        "deploymentTimestamp": {
            "type": "string",
            "value": "[utcNow()]"
        }
    }
}
EOF
    
    # Upload ARM template to storage account
    az storage file upload \
        --share-name arm-templates \
        --source "${temp_template}" \
        --path infrastructure-template.json \
        --account-name "${STORAGE_ACCOUNT}" \
        --account-key "${STORAGE_KEY}" \
        --output none
    
    # Clean up temporary file
    rm "${temp_template}"
    
    log "ARM template created and uploaded successfully ✅"
}

# Function to create and publish PowerShell runbook
create_powershell_runbook() {
    log "Creating PowerShell runbook..."
    
    # Create temporary file for runbook script
    local temp_runbook=$(mktemp)
    
    cat > "${temp_runbook}" << 'EOF'
param(
    [Parameter(Mandatory=$true)]
    [string]$ResourceGroupName,
    
    [Parameter(Mandatory=$true)]
    [string]$StorageAccountName,
    
    [Parameter(Mandatory=$true)]
    [string]$TemplateName,
    
    [Parameter(Mandatory=$false)]
    [string]$Environment = "demo",
    
    [Parameter(Mandatory=$false)]
    [string]$StorageAccountType = "Standard_LRS"
)

# Ensure no context inheritance
Disable-AzContextAutosave -Scope Process

try {
    # Connect using managed identity
    Write-Output "Connecting to Azure using managed identity..."
    $AzureContext = (Connect-AzAccount -Identity).context
    
    # Download ARM template from storage
    Write-Output "Downloading ARM template from storage..."
    $StorageAccount = Get-AzStorageAccount -ResourceGroupName $ResourceGroupName -Name $StorageAccountName
    $StorageKey = (Get-AzStorageAccountKey -ResourceGroupName $ResourceGroupName -Name $StorageAccountName)[0].Value
    $StorageContext = New-AzStorageContext -StorageAccountName $StorageAccountName -StorageAccountKey $StorageKey
    
    # Create temp directory for template
    $TempPath = "C:\Temp"
    if (!(Test-Path $TempPath)) {
        New-Item -ItemType Directory -Path $TempPath
    }
    
    # Download template file
    Get-AzStorageFileContent -ShareName "arm-templates" -Path $TemplateName -Destination $TempPath -Context $StorageContext
    $TemplateFile = Join-Path $TempPath $TemplateName
    
    # Set deployment parameters
    $DeploymentParams = @{
        storageAccountType = $StorageAccountType
        environment = $Environment
    }
    
    # Generate unique deployment name
    $DeploymentName = "deployment-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
    
    Write-Output "Starting deployment: $DeploymentName"
    
    # Deploy ARM template
    $Deployment = New-AzResourceGroupDeployment -ResourceGroupName $ResourceGroupName -Name $DeploymentName -TemplateFile $TemplateFile -TemplateParameterObject $DeploymentParams -Verbose
    
    if ($Deployment.ProvisioningState -eq "Succeeded") {
        Write-Output "✅ Deployment completed successfully"
        Write-Output "Deployment Name: $DeploymentName"
        Write-Output "Provisioning State: $($Deployment.ProvisioningState)"
        
        # Log deployment outputs
        if ($Deployment.Outputs) {
            Write-Output "Deployment Outputs:"
            $Deployment.Outputs.Keys | ForEach-Object {
                Write-Output "  $($_): $($Deployment.Outputs[$_].Value)"
            }
        }
    } else {
        Write-Error "Deployment failed with state: $($Deployment.ProvisioningState)"
        throw "Deployment failed"
    }
    
} catch {
    Write-Error "Error during deployment: $($_.Exception.Message)"
    
    # Attempt rollback if deployment exists
    try {
        Write-Output "Attempting rollback to previous successful deployment..."
        $PreviousDeployment = Get-AzResourceGroupDeployment -ResourceGroupName $ResourceGroupName | Where-Object { $_.ProvisioningState -eq "Succeeded" } | Sort-Object Timestamp -Descending | Select-Object -First 1
        
        if ($PreviousDeployment) {
            Write-Output "Rolling back to deployment: $($PreviousDeployment.DeploymentName)"
            # Rollback implementation would go here
        }
    } catch {
        Write-Error "Rollback failed: $($_.Exception.Message)"
    }
    
    throw $_.Exception
}
EOF
    
    # Check if runbook already exists
    if az automation runbook show \
        --resource-group "${RESOURCE_GROUP}" \
        --automation-account-name "${AUTOMATION_ACCOUNT}" \
        --name "Deploy-Infrastructure" >/dev/null 2>&1; then
        warn "Runbook Deploy-Infrastructure already exists. Updating content..."
        
        # Update existing runbook
        az automation runbook replace-content \
            --resource-group "${RESOURCE_GROUP}" \
            --automation-account-name "${AUTOMATION_ACCOUNT}" \
            --name "Deploy-Infrastructure" \
            --content "@${temp_runbook}" \
            --output none
    else
        # Create new runbook
        az automation runbook create \
            --resource-group "${RESOURCE_GROUP}" \
            --automation-account-name "${AUTOMATION_ACCOUNT}" \
            --name "Deploy-Infrastructure" \
            --type PowerShell \
            --description "Automated infrastructure deployment using ARM templates" \
            --output none
        
        # Upload runbook script
        az automation runbook replace-content \
            --resource-group "${RESOURCE_GROUP}" \
            --automation-account-name "${AUTOMATION_ACCOUNT}" \
            --name "Deploy-Infrastructure" \
            --content "@${temp_runbook}" \
            --output none
    fi
    
    # Publish the runbook
    az automation runbook publish \
        --resource-group "${RESOURCE_GROUP}" \
        --automation-account-name "${AUTOMATION_ACCOUNT}" \
        --name "Deploy-Infrastructure" \
        --output none
    
    # Clean up temporary file
    rm "${temp_runbook}"
    
    log "PowerShell runbook created and published successfully ✅"
}

# Function to install required PowerShell modules
install_powershell_modules() {
    log "Installing required PowerShell modules in Automation Account..."
    
    local modules=("Az.Accounts" "Az.Resources" "Az.Storage")
    
    for module in "${modules[@]}"; do
        info "Installing module: ${module}"
        
        # Install module (this might take some time)
        az automation module install \
            --resource-group "${RESOURCE_GROUP}" \
            --automation-account-name "${AUTOMATION_ACCOUNT}" \
            --name "${module}" \
            --module-version "latest" \
            --output none
        
        log "Module ${module} installation initiated ✅"
    done
    
    info "Waiting for module installation to complete..."
    sleep 60
    
    log "Required PowerShell modules installation initiated ✅"
}

# Function to create target resource group
create_target_resource_group() {
    log "Creating target resource group for deployments..."
    
    export TARGET_RESOURCE_GROUP="rg-deployed-infrastructure"
    
    if az group show --name "${TARGET_RESOURCE_GROUP}" >/dev/null 2>&1; then
        warn "Target resource group ${TARGET_RESOURCE_GROUP} already exists. Skipping creation."
    else
        az group create \
            --name "${TARGET_RESOURCE_GROUP}" \
            --location "${LOCATION}" \
            --tags environment=demo deployment=automated \
            --output none
        
        log "Target resource group ${TARGET_RESOURCE_GROUP} created successfully ✅"
    fi
    
    # Assign permissions to managed identity for target resource group
    if az role assignment list \
        --assignee "${MANAGED_IDENTITY_ID}" \
        --role "Contributor" \
        --scope "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${TARGET_RESOURCE_GROUP}" \
        --query "[0].id" \
        --output tsv >/dev/null 2>&1; then
        warn "Contributor role already assigned to managed identity for target resource group. Skipping."
    else
        az role assignment create \
            --assignee "${MANAGED_IDENTITY_ID}" \
            --role "Contributor" \
            --scope "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${TARGET_RESOURCE_GROUP}" \
            --output none
        
        log "Contributor role assigned to managed identity for target resource group ✅"
    fi
}

# Function to test the deployment
test_deployment() {
    log "Testing infrastructure deployment..."
    
    # Start the runbook job
    local job_id=$(az automation runbook start \
        --resource-group "${RESOURCE_GROUP}" \
        --automation-account-name "${AUTOMATION_ACCOUNT}" \
        --name "Deploy-Infrastructure" \
        --parameters resourceGroupName="${TARGET_RESOURCE_GROUP}" storageAccountName="${STORAGE_ACCOUNT}" templateName=infrastructure-template.json environment=demo \
        --query "jobId" \
        --output tsv)
    
    if [[ -n "${job_id}" ]]; then
        log "Runbook job started successfully ✅"
        info "Job ID: ${job_id}"
        
        # Monitor job status
        info "Monitoring job progress..."
        sleep 30
        
        local job_status=$(az automation job show \
            --resource-group "${RESOURCE_GROUP}" \
            --automation-account-name "${AUTOMATION_ACCOUNT}" \
            --job-id "${job_id}" \
            --query "status" \
            --output tsv)
        
        info "Job Status: ${job_status}"
        
        if [[ "${job_status}" == "Completed" ]]; then
            log "Deployment test completed successfully ✅"
        else
            warn "Deployment test is still running or has a different status: ${job_status}"
        fi
    else
        error "Failed to start runbook job"
        exit 1
    fi
}

# Function to display deployment summary
display_summary() {
    log "Deployment Summary:"
    echo "===================="
    echo "Resource Group: ${RESOURCE_GROUP}"
    echo "Automation Account: ${AUTOMATION_ACCOUNT}"
    echo "Storage Account: ${STORAGE_ACCOUNT}"
    echo "Log Analytics Workspace: ${LOG_ANALYTICS_WORKSPACE}"
    echo "Target Resource Group: ${TARGET_RESOURCE_GROUP}"
    echo "Location: ${LOCATION}"
    echo "Managed Identity ID: ${MANAGED_IDENTITY_ID}"
    echo "===================="
    echo ""
    echo "Next Steps:"
    echo "1. Monitor the Azure Automation runbook jobs in the Azure portal"
    echo "2. Check the Log Analytics workspace for deployment logs"
    echo "3. Verify ARM template deployments in the target resource group"
    echo "4. Review the deployed infrastructure resources"
    echo ""
    echo "To clean up resources, run: ./destroy.sh"
}

# Main execution
main() {
    log "Starting Azure Infrastructure Provisioning deployment..."
    
    # Check for dry run mode
    if [[ "${1:-}" == "--dry-run" ]]; then
        info "Running in dry-run mode - no resources will be created"
        export DRY_RUN=true
    fi
    
    check_prerequisites
    set_environment_variables
    
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        info "Dry run completed - no resources were created"
        exit 0
    fi
    
    create_resource_group
    create_log_analytics_workspace
    create_automation_account
    create_storage_account
    configure_rbac
    create_arm_template
    install_powershell_modules
    create_powershell_runbook
    create_target_resource_group
    test_deployment
    
    log "Deployment completed successfully! 🎉"
    display_summary
}

# Run main function with all arguments
main "$@"