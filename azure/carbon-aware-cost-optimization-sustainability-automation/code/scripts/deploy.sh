#!/bin/bash

# deploy.sh - Automated Carbon-Aware Cost Optimization with Azure Carbon Optimization and Azure Automation
# This script deploys the complete carbon optimization infrastructure on Azure

set -e  # Exit on any error
set -o pipefail  # Exit if any command in a pipeline fails

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

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check if Azure CLI is installed and logged in
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        log_error "Azure CLI is not installed. Please install it first."
        log_error "Visit: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
        exit 1
    fi
    
    # Check if logged in to Azure
    if ! az account show &> /dev/null; then
        log_error "Not logged in to Azure. Please run 'az login' first."
        exit 1
    fi
    
    # Check for required resource providers
    log "Checking required resource providers..."
    local providers=("Microsoft.Automation" "Microsoft.Logic" "Microsoft.KeyVault" "Microsoft.OperationalInsights" "Microsoft.Storage")
    
    for provider in "${providers[@]}"; do
        local status=$(az provider show --namespace "$provider" --query "registrationState" --output tsv 2>/dev/null)
        if [ "$status" != "Registered" ]; then
            log "Registering provider: $provider"
            az provider register --namespace "$provider" --wait
        fi
    done
    
    log_success "Prerequisites check completed"
}

# Function to set environment variables
set_environment_variables() {
    log "Setting up environment variables..."
    
    # Generate unique suffix for resource names
    export RANDOM_SUFFIX=$(openssl rand -hex 3)
    
    # Set environment variables for the solution
    export RESOURCE_GROUP="rg-carbon-optimization-${RANDOM_SUFFIX}"
    export LOCATION="${AZURE_LOCATION:-eastus}"
    export SUBSCRIPTION_ID=$(az account show --query id --output tsv)
    
    # Set resource names with proper Azure naming conventions
    export AUTOMATION_ACCOUNT="aa-carbon-opt-${RANDOM_SUFFIX}"
    export KEY_VAULT_NAME="kv-carbon-${RANDOM_SUFFIX}"
    export LOGIC_APP_NAME="la-carbon-optimization-${RANDOM_SUFFIX}"
    export LOG_ANALYTICS_NAME="law-carbon-opt-${RANDOM_SUFFIX}"
    export STORAGE_ACCOUNT="stcarbonopt${RANDOM_SUFFIX}"
    
    log "Resource Group: $RESOURCE_GROUP"
    log "Location: $LOCATION"
    log "Subscription ID: $SUBSCRIPTION_ID"
    log_success "Environment variables configured"
}

# Function to create resource group
create_resource_group() {
    log "Creating resource group: $RESOURCE_GROUP"
    
    az group create \
        --name "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --tags purpose=sustainability environment=production project=carbon-optimization \
        --output none
    
    log_success "Resource group created: $RESOURCE_GROUP"
}

# Function to create Log Analytics workspace
create_log_analytics() {
    log "Creating Log Analytics workspace: $LOG_ANALYTICS_NAME"
    
    az monitor log-analytics workspace create \
        --resource-group "$RESOURCE_GROUP" \
        --workspace-name "$LOG_ANALYTICS_NAME" \
        --location "$LOCATION" \
        --sku Standard \
        --output none
    
    log_success "Log Analytics workspace created for carbon optimization monitoring"
}

# Function to create Key Vault
create_key_vault() {
    log "Creating Key Vault: $KEY_VAULT_NAME"
    
    az keyvault create \
        --name "$KEY_VAULT_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --sku standard \
        --enable-rbac-authorization true \
        --output none
    
    # Get current user's object ID for access assignment
    local user_object_id=$(az ad signed-in-user show --query id --output tsv)
    
    # Assign Key Vault Secrets Officer role
    az role assignment create \
        --role "Key Vault Secrets Officer" \
        --assignee "$user_object_id" \
        --scope "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.KeyVault/vaults/$KEY_VAULT_NAME" \
        --output none
    
    log_success "Key Vault created with secure access policies"
}

# Function to configure carbon optimization thresholds
configure_carbon_thresholds() {
    log "Configuring carbon optimization thresholds in Key Vault"
    
    # Wait a moment for Key Vault permissions to propagate
    sleep 10
    
    # Set carbon emissions threshold (kg CO2e per month)
    az keyvault secret set \
        --vault-name "$KEY_VAULT_NAME" \
        --name "carbon-threshold-kg" \
        --value "100" \
        --output none
    
    # Set cost threshold for optimization actions (USD per month)
    az keyvault secret set \
        --vault-name "$KEY_VAULT_NAME" \
        --name "cost-threshold-usd" \
        --value "500" \
        --output none
    
    # Set minimum carbon reduction percentage to trigger actions
    az keyvault secret set \
        --vault-name "$KEY_VAULT_NAME" \
        --name "min-carbon-reduction-percent" \
        --value "10" \
        --output none
    
    # Set resource utilization threshold for rightsizing
    az keyvault secret set \
        --vault-name "$KEY_VAULT_NAME" \
        --name "cpu-utilization-threshold" \
        --value "20" \
        --output none
    
    log_success "Carbon optimization thresholds configured in Key Vault"
}

# Function to create Automation Account
create_automation_account() {
    log "Creating Automation Account: $AUTOMATION_ACCOUNT"
    
    az automation account create \
        --name "$AUTOMATION_ACCOUNT" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --assign-identity \
        --sku Basic \
        --output none
    
    # Get the managed identity principal ID
    local identity_principal_id=$(az automation account show \
        --name "$AUTOMATION_ACCOUNT" \
        --resource-group "$RESOURCE_GROUP" \
        --query identity.principalId --output tsv)
    
    # Wait for managed identity to propagate
    sleep 30
    
    # Assign necessary roles for carbon optimization operations
    az role assignment create \
        --role "Cost Management Reader" \
        --assignee "$identity_principal_id" \
        --scope "/subscriptions/$SUBSCRIPTION_ID" \
        --output none
    
    az role assignment create \
        --role "Virtual Machine Contributor" \
        --assignee "$identity_principal_id" \
        --scope "/subscriptions/$SUBSCRIPTION_ID" \
        --output none
    
    az role assignment create \
        --role "Key Vault Secrets User" \
        --assignee "$identity_principal_id" \
        --scope "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.KeyVault/vaults/$KEY_VAULT_NAME" \
        --output none
    
    log_success "Automation Account created with managed identity and carbon optimization permissions"
}

# Function to create carbon optimization runbook
create_carbon_runbook() {
    log "Creating carbon optimization runbook"
    
    # Create the carbon optimization runbook
    az automation runbook create \
        --automation-account-name "$AUTOMATION_ACCOUNT" \
        --resource-group "$RESOURCE_GROUP" \
        --name "CarbonOptimizationRunbook" \
        --type PowerShell \
        --description "Automated carbon-aware cost optimization based on emissions data" \
        --output none
    
    # Create the runbook content
    cat > carbon-optimization-runbook.ps1 << 'EOF'
param(
    [string]$SubscriptionId,
    [string]$ResourceGroupName,
    [string]$KeyVaultName
)

# Connect using managed identity
Connect-AzAccount -Identity
Set-AzContext -SubscriptionId $SubscriptionId

# Get configuration from Key Vault
$carbonThreshold = Get-AzKeyVaultSecret -VaultName $KeyVaultName -Name "carbon-threshold-kg" -AsPlainText
$costThreshold = Get-AzKeyVaultSecret -VaultName $KeyVaultName -Name "cost-threshold-usd" -AsPlainText
$minCarbonReduction = Get-AzKeyVaultSecret -VaultName $KeyVaultName -Name "min-carbon-reduction-percent" -AsPlainText
$cpuThreshold = Get-AzKeyVaultSecret -VaultName $KeyVaultName -Name "cpu-utilization-threshold" -AsPlainText

Write-Output "Starting carbon optimization analysis..."
Write-Output "Carbon threshold: $carbonThreshold kg CO2e/month"
Write-Output "Cost threshold: $costThreshold USD/month"

# Get carbon optimization recommendations using REST API
$headers = @{
    'Authorization' = "Bearer $((Get-AzAccessToken).Token)"
    'Content-Type' = 'application/json'
}

$recommendationsUri = "https://management.azure.com/subscriptions/$SubscriptionId/providers/Microsoft.CarbonOptimization/carbonOptimizationRecommendations"

try {
    $recommendations = Invoke-RestMethod -Uri $recommendationsUri -Headers $headers -Method GET
    
    foreach ($rec in $recommendations.value) {
        $carbonSavings = $rec.properties.extendedProperties.PotentialMonthlyCarbonSavings
        $costSavings = $rec.properties.extendedProperties.savingsAmount
        $resourceId = $rec.properties.resourceMetadata.resourceId
        
        Write-Output "Analyzing recommendation for resource: $resourceId"
        Write-Output "Potential carbon savings: $carbonSavings kg CO2e/month"
        Write-Output "Potential cost savings: $costSavings USD/month"
        
        # Check if recommendation meets thresholds
        if ([double]$carbonSavings -ge [double]$carbonThreshold -and [double]$costSavings -ge [double]$costThreshold) {
            Write-Output "Recommendation meets thresholds - executing optimization action"
            
            # Execute optimization based on recommendation type
            $recommendationType = $rec.properties.extendedProperties.recommendationType
            
            switch ($recommendationType) {
                "Shutdown" {
                    Write-Output "Executing shutdown recommendation for $resourceId"
                    # Stop the virtual machine
                    $vmName = $resourceId.Split('/')[-1]
                    $vmResourceGroup = $resourceId.Split('/')[4]
                    Stop-AzVM -ResourceGroupName $vmResourceGroup -Name $vmName -Force
                    Write-Output "Virtual machine $vmName stopped successfully"
                }
                "Resize" {
                    Write-Output "Executing resize recommendation for $resourceId"
                    # Resize virtual machine to more efficient SKU
                    $vmName = $resourceId.Split('/')[-1]
                    $vmResourceGroup = $resourceId.Split('/')[4]
                    $newSize = $rec.properties.extendedProperties.targetSku
                    $vm = Get-AzVM -ResourceGroupName $vmResourceGroup -Name $vmName
                    $vm.HardwareProfile.VmSize = $newSize
                    Update-AzVM -ResourceGroupName $vmResourceGroup -VM $vm
                    Write-Output "Virtual machine $vmName resized to $newSize"
                }
            }
            
            # Log optimization action
            Write-Output "Optimization completed - Carbon saved: $carbonSavings kg CO2e, Cost saved: $costSavings USD"
        }
        else {
            Write-Output "Recommendation does not meet thresholds - skipping action"
        }
    }
}
catch {
    Write-Error "Error retrieving carbon optimization recommendations: $($_.Exception.Message)"
}

Write-Output "Carbon optimization analysis completed"
EOF
    
    # Import the runbook content
    az automation runbook replace-content \
        --automation-account-name "$AUTOMATION_ACCOUNT" \
        --resource-group "$RESOURCE_GROUP" \
        --name "CarbonOptimizationRunbook" \
        --content @carbon-optimization-runbook.ps1 \
        --output none
    
    # Publish the runbook
    az automation runbook publish \
        --automation-account-name "$AUTOMATION_ACCOUNT" \
        --resource-group "$RESOURCE_GROUP" \
        --name "CarbonOptimizationRunbook" \
        --output none
    
    # Clean up temporary file
    rm -f carbon-optimization-runbook.ps1
    
    log_success "Carbon optimization runbook created and published"
}

# Function to create storage account
create_storage_account() {
    log "Creating storage account: $STORAGE_ACCOUNT"
    
    az storage account create \
        --name "$STORAGE_ACCOUNT" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --sku Standard_LRS \
        --kind StorageV2 \
        --access-tier Hot \
        --output none
    
    log_success "Storage account created for Logic Apps workflow management"
}

# Function to create Logic Apps workflow
create_logic_app() {
    log "Creating Logic Apps workflow: $LOGIC_APP_NAME"
    
    # Create Logic Apps workflow definition
    cat > logic-app-definition.json << EOF
{
    "\$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#",
    "contentVersion": "1.0.0.0",
    "parameters": {
        "logicAppName": {
            "type": "string",
            "defaultValue": "$LOGIC_APP_NAME"
        },
        "automationAccountName": {
            "type": "string",
            "defaultValue": "$AUTOMATION_ACCOUNT"
        },
        "keyVaultName": {
            "type": "string",
            "defaultValue": "$KEY_VAULT_NAME"
        },
        "storageAccountName": {
            "type": "string",
            "defaultValue": "$STORAGE_ACCOUNT"
        },
        "logAnalyticsWorkspaceName": {
            "type": "string",
            "defaultValue": "$LOG_ANALYTICS_NAME"
        }
    },
    "resources": [
        {
            "type": "Microsoft.Logic/workflows",
            "apiVersion": "2019-05-01",
            "name": "[parameters('logicAppName')]",
            "location": "[resourceGroup().location]",
            "identity": {
                "type": "SystemAssigned"
            },
            "properties": {
                "definition": {
                    "\$schema": "https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#",
                    "contentVersion": "1.0.0.0",
                    "parameters": {},
                    "triggers": {
                        "Recurrence": {
                            "recurrence": {
                                "frequency": "Day",
                                "interval": 1,
                                "timeZone": "UTC",
                                "startTime": "2025-01-01T02:00:00Z"
                            },
                            "type": "Recurrence"
                        }
                    },
                    "actions": {
                        "Get_Carbon_Intensity_Data": {
                            "type": "Http",
                            "inputs": {
                                "method": "GET",
                                "uri": "https://api.carbonintensity.org.uk/intensity"
                            }
                        },
                        "Parse_Carbon_Intensity": {
                            "type": "ParseJson",
                            "inputs": {
                                "content": "@body('Get_Carbon_Intensity_Data')",
                                "schema": {
                                    "type": "object",
                                    "properties": {
                                        "data": {
                                            "type": "array",
                                            "items": {
                                                "type": "object",
                                                "properties": {
                                                    "intensity": {
                                                        "type": "object",
                                                        "properties": {
                                                            "actual": {
                                                                "type": "integer"
                                                            }
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            },
                            "runAfter": {
                                "Get_Carbon_Intensity_Data": ["Succeeded"]
                            }
                        },
                        "Check_Carbon_Intensity_Threshold": {
                            "type": "If",
                            "expression": {
                                "and": [
                                    {
                                        "less": [
                                            "@body('Parse_Carbon_Intensity')?['data']?[0]?['intensity']?['actual']",
                                            200
                                        ]
                                    }
                                ]
                            },
                            "actions": {
                                "Start_Carbon_Optimization_Runbook": {
                                    "type": "Http",
                                    "inputs": {
                                        "method": "POST",
                                        "uri": "[concat('https://management.azure.com/subscriptions/', subscription().subscriptionId, '/resourceGroups/', resourceGroup().name, '/providers/Microsoft.Automation/automationAccounts/', parameters('automationAccountName'), '/runbooks/CarbonOptimizationRunbook/start')]",
                                        "queries": {
                                            "api-version": "2020-01-13-preview"
                                        },
                                        "headers": {
                                            "Content-Type": "application/json"
                                        },
                                        "body": {
                                            "properties": {
                                                "parameters": {
                                                    "SubscriptionId": "[subscription().subscriptionId]",
                                                    "ResourceGroupName": "[resourceGroup().name]",
                                                    "KeyVaultName": "[parameters('keyVaultName')]"
                                                }
                                            }
                                        },
                                        "authentication": {
                                            "type": "ManagedServiceIdentity"
                                        }
                                    }
                                },
                                "Log_Optimization_Trigger": {
                                    "type": "Http",
                                    "inputs": {
                                        "method": "POST",
                                        "uri": "[concat('https://', parameters('logAnalyticsWorkspaceName'), '.ods.opinsights.azure.com/api/logs')]",
                                        "headers": {
                                            "Content-Type": "application/json",
                                            "Log-Type": "CarbonOptimization"
                                        },
                                        "body": {
                                            "timestamp": "@utcnow()",
                                            "carbonIntensity": "@body('Parse_Carbon_Intensity')?['data']?[0]?['intensity']?['actual']",
                                            "action": "optimization_triggered",
                                            "reason": "low_carbon_intensity"
                                        },
                                        "authentication": {
                                            "type": "ManagedServiceIdentity"
                                        }
                                    },
                                    "runAfter": {
                                        "Start_Carbon_Optimization_Runbook": ["Succeeded"]
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    ]
}
EOF
    
    # Deploy the Logic Apps workflow
    az deployment group create \
        --resource-group "$RESOURCE_GROUP" \
        --template-file logic-app-definition.json \
        --output none
    
    # Clean up temporary file
    rm -f logic-app-definition.json
    
    log_success "Logic Apps workflow created for carbon optimization orchestration"
}

# Function to configure Logic Apps permissions
configure_logic_app_permissions() {
    log "Configuring Logic Apps managed identity permissions"
    
    # Get Logic Apps managed identity principal ID
    local logic_app_principal_id=$(az logic workflow show \
        --resource-group "$RESOURCE_GROUP" \
        --name "$LOGIC_APP_NAME" \
        --query identity.principalId --output tsv)
    
    # Wait for managed identity to propagate
    sleep 30
    
    # Assign permissions for carbon optimization operations
    az role assignment create \
        --role "Automation Contributor" \
        --assignee "$logic_app_principal_id" \
        --scope "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Automation/automationAccounts/$AUTOMATION_ACCOUNT" \
        --output none
    
    az role assignment create \
        --role "Log Analytics Contributor" \
        --assignee "$logic_app_principal_id" \
        --scope "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.OperationalInsights/workspaces/$LOG_ANALYTICS_NAME" \
        --output none
    
    az role assignment create \
        --role "Reader" \
        --assignee "$logic_app_principal_id" \
        --scope "/subscriptions/$SUBSCRIPTION_ID" \
        --output none
    
    log_success "Logic Apps managed identity configured with carbon optimization permissions"
}

# Function to create automation schedules
create_automation_schedules() {
    log "Creating carbon optimization schedules"
    
    # Create daily carbon optimization schedule
    az automation schedule create \
        --automation-account-name "$AUTOMATION_ACCOUNT" \
        --resource-group "$RESOURCE_GROUP" \
        --name "DailyCarbonOptimization" \
        --description "Daily carbon optimization analysis and actions" \
        --frequency Day \
        --interval 1 \
        --start-time "2025-01-01T02:00:00Z" \
        --time-zone "UTC" \
        --output none
    
    # Link schedule to runbook
    az automation job-schedule create \
        --automation-account-name "$AUTOMATION_ACCOUNT" \
        --resource-group "$RESOURCE_GROUP" \
        --runbook-name "CarbonOptimizationRunbook" \
        --schedule-name "DailyCarbonOptimization" \
        --parameters SubscriptionId="$SUBSCRIPTION_ID" ResourceGroupName="$RESOURCE_GROUP" KeyVaultName="$KEY_VAULT_NAME" \
        --output none
    
    # Create peak carbon intensity schedule
    az automation schedule create \
        --automation-account-name "$AUTOMATION_ACCOUNT" \
        --resource-group "$RESOURCE_GROUP" \
        --name "PeakCarbonOptimization" \
        --description "Optimization during peak carbon intensity periods" \
        --frequency Day \
        --interval 1 \
        --start-time "2025-01-01T18:00:00Z" \
        --time-zone "UTC" \
        --output none
    
    # Link peak schedule to runbook
    az automation job-schedule create \
        --automation-account-name "$AUTOMATION_ACCOUNT" \
        --resource-group "$RESOURCE_GROUP" \
        --runbook-name "CarbonOptimizationRunbook" \
        --schedule-name "PeakCarbonOptimization" \
        --parameters SubscriptionId="$SUBSCRIPTION_ID" ResourceGroupName="$RESOURCE_GROUP" KeyVaultName="$KEY_VAULT_NAME" \
        --output none
    
    log_success "Carbon optimization schedules created for optimal timing"
}

# Function to validate deployment
validate_deployment() {
    log "Validating deployment..."
    
    # Check if all resources exist
    local resources=("$RESOURCE_GROUP" "$AUTOMATION_ACCOUNT" "$KEY_VAULT_NAME" "$LOGIC_APP_NAME" "$LOG_ANALYTICS_NAME" "$STORAGE_ACCOUNT")
    local resource_types=("group" "automation account" "key vault" "logic app" "log analytics workspace" "storage account")
    
    for i in "${!resources[@]}"; do
        case "${resource_types[$i]}" in
            "group")
                if az group show --name "${resources[$i]}" &> /dev/null; then
                    log_success "Resource group ${resources[$i]} exists"
                else
                    log_error "Resource group ${resources[$i]} not found"
                fi
                ;;
            "automation account")
                if az automation account show --name "${resources[$i]}" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
                    log_success "Automation account ${resources[$i]} exists"
                else
                    log_error "Automation account ${resources[$i]} not found"
                fi
                ;;
            "key vault")
                if az keyvault show --name "${resources[$i]}" &> /dev/null; then
                    log_success "Key vault ${resources[$i]} exists"
                else
                    log_error "Key vault ${resources[$i]} not found"
                fi
                ;;
            "logic app")
                if az logic workflow show --name "${resources[$i]}" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
                    log_success "Logic app ${resources[$i]} exists"
                else
                    log_error "Logic app ${resources[$i]} not found"
                fi
                ;;
            "log analytics workspace")
                if az monitor log-analytics workspace show --workspace-name "${resources[$i]}" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
                    log_success "Log Analytics workspace ${resources[$i]} exists"
                else
                    log_error "Log Analytics workspace ${resources[$i]} not found"
                fi
                ;;
            "storage account")
                if az storage account show --name "${resources[$i]}" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
                    log_success "Storage account ${resources[$i]} exists"
                else
                    log_error "Storage account ${resources[$i]} not found"
                fi
                ;;
        esac
    done
}

# Function to display deployment summary
display_summary() {
    log "=========================================="
    log "DEPLOYMENT SUMMARY"
    log "=========================================="
    log "Resource Group: $RESOURCE_GROUP"
    log "Location: $LOCATION"
    log "Automation Account: $AUTOMATION_ACCOUNT"
    log "Key Vault: $KEY_VAULT_NAME"
    log "Logic App: $LOGIC_APP_NAME"
    log "Log Analytics: $LOG_ANALYTICS_NAME"
    log "Storage Account: $STORAGE_ACCOUNT"
    log "=========================================="
    log_success "Carbon optimization infrastructure deployed successfully!"
    log "The system will automatically optimize resources based on carbon intensity data."
    log "Monitor the Logic Apps and Automation Account for optimization activities."
    log "=========================================="
}

# Main deployment function
main() {
    log "Starting deployment of Carbon-Aware Cost Optimization solution..."
    
    check_prerequisites
    set_environment_variables
    create_resource_group
    create_log_analytics
    create_key_vault
    configure_carbon_thresholds
    create_automation_account
    create_carbon_runbook
    create_storage_account
    create_logic_app
    configure_logic_app_permissions
    create_automation_schedules
    validate_deployment
    display_summary
    
    log_success "Deployment completed successfully!"
}

# Error handling
trap 'log_error "Deployment failed at line $LINENO. Exit code: $?"' ERR

# Run main function
main "$@"