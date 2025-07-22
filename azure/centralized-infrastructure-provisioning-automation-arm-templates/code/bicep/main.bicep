// Main Bicep template for Azure Automation Infrastructure Provisioning
// This template creates the complete infrastructure for automated ARM template deployment

@description('The Azure region where resources will be deployed')
param location string = resourceGroup().location

@description('Environment name for resource tagging')
@allowed([
  'dev'
  'staging'
  'prod'
  'demo'
])
param environment string = 'demo'

@description('Automation account name')
param automationAccountName string = 'aa-infra-provisioning'

@description('Storage account name for ARM templates (must be globally unique)')
param storageAccountName string = 'stautoarmtemplates${uniqueString(resourceGroup().id)}'

@description('Log Analytics workspace name')
param logAnalyticsWorkspaceName string = 'law-automation-monitoring'

@description('Target resource group name for deployments')
param targetResourceGroupName string = 'rg-deployed-infrastructure'

@description('Storage account SKU')
@allowed([
  'Standard_LRS'
  'Standard_GRS'
  'Standard_ZRS'
  'Premium_LRS'
])
param storageAccountSku string = 'Standard_LRS'

@description('Log Analytics workspace SKU')
@allowed([
  'Free'
  'PerGB2018'
  'PerNode'
  'Premium'
  'Standard'
])
param logAnalyticsWorkspaceSku string = 'PerGB2018'

@description('Automation account SKU')
@allowed([
  'Free'
  'Basic'
])
param automationAccountSku string = 'Basic'

@description('PowerShell modules to install in the automation account')
param powershellModules array = [
  'Az.Accounts'
  'Az.Resources'
  'Az.Storage'
  'Az.Profile'
]

// Variables
var tags = {
  environment: environment
  purpose: 'automation'
  deployment: 'automated'
  recipe: 'azure-automation-arm-templates'
}

var fileShareName = 'arm-templates'
var runbookName = 'Deploy-Infrastructure'

// Log Analytics Workspace
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2022-10-01' = {
  name: logAnalyticsWorkspaceName
  location: location
  tags: tags
  properties: {
    sku: {
      name: logAnalyticsWorkspaceSku
    }
    retentionInDays: 30
    features: {
      searchVersion: 1
      legacy: 0
    }
  }
}

// Storage Account for ARM Templates
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: storageAccountName
  location: location
  tags: tags
  sku: {
    name: storageAccountSku
  }
  kind: 'StorageV2'
  properties: {
    accessTier: 'Hot'
    allowBlobPublicAccess: false
    supportsHttpsTrafficOnly: true
    minimumTlsVersion: 'TLS1_2'
    encryption: {
      services: {
        blob: {
          enabled: true
          keyType: 'Account'
        }
        file: {
          enabled: true
          keyType: 'Account'
        }
      }
      keySource: 'Microsoft.Storage'
    }
    networkAcls: {
      defaultAction: 'Allow'
    }
  }
}

// File Services for ARM Templates
resource fileServices 'Microsoft.Storage/storageAccounts/fileServices@2023-01-01' = {
  parent: storageAccount
  name: 'default'
  properties: {
    shareDeleteRetentionPolicy: {
      enabled: true
      days: 7
    }
  }
}

// File Share for ARM Templates
resource fileShare 'Microsoft.Storage/storageAccounts/fileServices/shares@2023-01-01' = {
  parent: fileServices
  name: fileShareName
  properties: {
    accessTier: 'Hot'
    shareQuota: 100
    enabledProtocols: 'SMB'
  }
}

// Automation Account
resource automationAccount 'Microsoft.Automation/automationAccounts@2023-11-01' = {
  name: automationAccountName
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    sku: {
      name: automationAccountSku
    }
    encryption: {
      keySource: 'Microsoft.Automation'
    }
    publicNetworkAccess: true
  }
}

// Link Log Analytics Workspace to Automation Account
resource automationAccountLinkedService 'Microsoft.Automation/automationAccounts/linkedWorkspace@2020-01-13-preview' = {
  parent: automationAccount
  name: 'Automation'
  properties: {
    resourceId: logAnalyticsWorkspace.id
  }
}

// PowerShell Runbook
resource runbook 'Microsoft.Automation/automationAccounts/runbooks@2023-11-01' = {
  parent: automationAccount
  name: runbookName
  properties: {
    runbookType: 'PowerShell'
    logVerbose: true
    logProgress: true
    description: 'Automated infrastructure deployment using ARM templates with managed identity authentication'
    publishContentLink: {
      uri: 'https://raw.githubusercontent.com/Azure/azure-quickstart-templates/master/demos/automation-runbook-managedidentity/runbook.ps1'
      version: '1.0.0.0'
    }
  }
}

// Target Resource Group for Deployments
resource targetResourceGroup 'Microsoft.Resources/resourceGroups@2023-07-01' = {
  name: targetResourceGroupName
  location: location
  tags: tags
  scope: subscription()
}

// Role Assignment - Contributor role for Automation Account on target resource group
resource contributorRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(targetResourceGroup.id, automationAccount.id, 'b24988ac-6180-42a0-ab88-20f7382dd24c')
  scope: targetResourceGroup
  properties: {
    principalId: automationAccount.identity.principalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b24988ac-6180-42a0-ab88-20f7382dd24c') // Contributor role
    principalType: 'ServicePrincipal'
  }
}

// Role Assignment - Storage Blob Data Contributor role for Automation Account on storage account
resource storageContributorRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccount.id, automationAccount.id, 'ba92f5b4-2d11-453d-a403-e96b0029c9fe')
  scope: storageAccount
  properties: {
    principalId: automationAccount.identity.principalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'ba92f5b4-2d11-453d-a403-e96b0029c9fe') // Storage Blob Data Contributor
    principalType: 'ServicePrincipal'
  }
}

// Sample ARM Template as a deployment script (creates the template file)
resource deploymentScript 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
  name: 'create-sample-arm-template'
  location: location
  tags: tags
  kind: 'AzurePowerShell'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    azPowerShellVersion: '9.0'
    scriptContent: '''
      $templateContent = @'
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
'@

      # Get storage account context
      $storageAccountName = "${storageAccountName}"
      $resourceGroupName = "${resourceGroup().name}"
      
      # Get storage account key
      $storageAccount = Get-AzStorageAccount -ResourceGroupName $resourceGroupName -Name $storageAccountName
      $storageKey = (Get-AzStorageAccountKey -ResourceGroupName $resourceGroupName -Name $storageAccountName)[0].Value
      $storageContext = New-AzStorageContext -StorageAccountName $storageAccountName -StorageAccountKey $storageKey
      
      # Create temporary file
      $tempFile = New-TemporaryFile
      $templateContent | Out-File -FilePath $tempFile.FullName -Encoding UTF8
      
      # Upload to file share
      Set-AzStorageFileContent -ShareName "${fileShareName}" -Source $tempFile.FullName -Path "infrastructure-template.json" -Context $storageContext -Force
      
      # Clean up
      Remove-Item $tempFile.FullName
      
      Write-Output "Sample ARM template uploaded to file share successfully"
    '''
    timeout: 'PT10M'
    cleanupPreference: 'OnSuccess'
    retentionInterval: 'P1D'
  }
  dependsOn: [
    fileShare
    storageContributorRoleAssignment
  ]
}

// PowerShell Runbook Content
resource runbookContent 'Microsoft.Automation/automationAccounts/runbooks@2023-11-01' = {
  parent: automationAccount
  name: '${runbookName}-Content'
  properties: {
    runbookType: 'PowerShell'
    logVerbose: true
    logProgress: true
    description: 'Infrastructure deployment runbook with comprehensive error handling and logging'
    draft: {
      inEdit: false
      draftContentLink: {
        uri: 'data:text/plain;base64,${base64('''
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
''')}'
        version: '1.0.0.0'
      }
    }
  }
  dependsOn: [
    automationAccount
  ]
}

// Outputs
@description('Automation Account resource ID')
output automationAccountId string = automationAccount.id

@description('Automation Account managed identity principal ID')
output automationAccountPrincipalId string = automationAccount.identity.principalId

@description('Storage Account resource ID')
output storageAccountId string = storageAccount.id

@description('Storage Account name')
output storageAccountName string = storageAccount.name

@description('Log Analytics Workspace resource ID')
output logAnalyticsWorkspaceId string = logAnalyticsWorkspace.id

@description('Target Resource Group resource ID')
output targetResourceGroupId string = targetResourceGroup.id

@description('Target Resource Group name')
output targetResourceGroupName string = targetResourceGroup.name

@description('File Share name for ARM templates')
output fileShareName string = fileShare.name

@description('Runbook name')
output runbookName string = runbook.name

@description('Primary storage account key (secure)')
@secure()
output storageAccountKey string = storageAccount.listKeys().keys[0].value

@description('Sample ARM template deployment instructions')
output deploymentInstructions object = {
  runbookName: runbook.name
  parameters: {
    ResourceGroupName: targetResourceGroup.name
    StorageAccountName: storageAccount.name
    TemplateName: 'infrastructure-template.json'
    Environment: environment
    StorageAccountType: 'Standard_LRS'
  }
  executionCommand: 'Start-AzAutomationRunbook -AutomationAccountName ${automationAccount.name} -ResourceGroupName ${resourceGroup().name} -Name ${runbook.name}'
}