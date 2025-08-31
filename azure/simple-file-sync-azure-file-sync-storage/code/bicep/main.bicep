// ==============================================================================
// Azure File Sync Infrastructure Template
// ==============================================================================
// This Bicep template creates a complete Azure File Sync infrastructure including:
// - Storage Account with Azure Files
// - Storage Sync Service
// - Sync Group
// - Cloud Endpoint
// Based on the recipe: Simple File Sync with Azure File Sync and Storage
// ==============================================================================

@description('Azure region for all resources')
param location string = resourceGroup().location

@description('Environment name (dev, test, prod)')
@allowed([
  'dev'
  'test'
  'prod'
])
param environment string = 'dev'

@description('Unique suffix for resource naming (3-6 characters)')
@minLength(3)
@maxLength(6)
param uniqueSuffix string = uniqueString(resourceGroup().id)

@description('Storage account SKU')
@allowed([
  'Standard_LRS'
  'Standard_GRS'
  'Standard_ZRS'
  'Premium_LRS'
])
param storageAccountSku string = 'Standard_LRS'

@description('Azure file share quota in GB')
@minValue(100)
@maxValue(102400)
param fileShareQuota int = 1024

@description('Azure file share access tier')
@allowed([
  'Hot'
  'Cool'
  'Premium'
])
param fileShareAccessTier string = 'Hot'

@description('Storage Sync Service incoming traffic policy')
@allowed([
  'AllowAllTraffic'
  'AllowVirtualNetworksOnly'
])
param incomingTrafficPolicy string = 'AllowAllTraffic'

@description('Tags to apply to all resources')
param tags object = {
  Environment: environment
  Purpose: 'Azure File Sync Recipe'
  ManagedBy: 'Bicep Template'
}

// ==============================================================================
// Variables
// ==============================================================================

var storageAccountName = 'filesync${uniqueSuffix}'
var storageSyncServiceName = 'filesync-service-${uniqueSuffix}'
var fileShareName = 'companyfiles'
var syncGroupName = 'main-sync-group'
var cloudEndpointName = 'cloud-endpoint-${uniqueSuffix}'

// ==============================================================================
// Storage Account with Azure Files
// ==============================================================================

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' = {
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
    allowSharedKeyAccess: true
    supportsHttpsTrafficOnly: true
    minimumTlsVersion: 'TLS1_2'
    largeFileSharesState: 'Enabled'
    networkAcls: {
      bypass: 'AzureServices'
      defaultAction: 'Allow'
    }
    encryption: {
      services: {
        file: {
          enabled: true
          keyType: 'Account'
        }
        blob: {
          enabled: true
          keyType: 'Account'
        }
      }
      keySource: 'Microsoft.Storage'
    }
  }
}

// File Services for Azure Files
resource fileServices 'Microsoft.Storage/storageAccounts/fileServices@2023-05-01' = {
  parent: storageAccount
  name: 'default'
  properties: {
    shareDeleteRetentionPolicy: {
      enabled: true
      days: 7
    }
  }
}

// Azure File Share
resource fileShare 'Microsoft.Storage/storageAccounts/fileServices/shares@2023-05-01' = {
  parent: fileServices
  name: fileShareName
  properties: {
    accessTier: fileShareAccessTier
    shareQuota: fileShareQuota
    enabledProtocols: 'SMB'
    metadata: {
      purpose: 'Azure File Sync Recipe'
      environment: environment
    }
  }
}

// ==============================================================================
// Storage Sync Service
// ==============================================================================

resource storageSyncService 'Microsoft.StorageSync/storageSyncServices@2022-09-01' = {
  name: storageSyncServiceName
  location: location
  tags: tags
  properties: {
    incomingTrafficPolicy: incomingTrafficPolicy
    useIdentity: false
  }
}

// ==============================================================================
// Sync Group
// ==============================================================================

resource syncGroup 'Microsoft.StorageSync/storageSyncServices/syncGroups@2022-09-01' = {
  parent: storageSyncService
  name: syncGroupName
  properties: {}
}

// ==============================================================================
// Cloud Endpoint
// ==============================================================================

resource cloudEndpoint 'Microsoft.StorageSync/storageSyncServices/syncGroups/cloudEndpoints@2022-09-01' = {
  parent: syncGroup
  name: cloudEndpointName
  properties: {
    storageAccountResourceId: storageAccount.id
    azureFileShareName: fileShareName
    storageAccountTenantId: tenant().tenantId
    friendlyName: 'Primary Cloud Endpoint for ${fileShareName}'
  }
}

// ==============================================================================
// Outputs
// ==============================================================================

@description('Resource Group name')
output resourceGroupName string = resourceGroup().name

@description('Storage Account name')
output storageAccountName string = storageAccount.name

@description('Storage Account resource ID')
output storageAccountId string = storageAccount.id

@description('Azure File Share name')
output fileShareName string = fileShare.name

@description('Azure File Share UNC path')
output fileShareUncPath string = '\\\\${storageAccount.name}.file.${environment().suffixes.storage}\\${fileShareName}'

@description('Storage Sync Service name')
output storageSyncServiceName string = storageSyncService.name

@description('Storage Sync Service resource ID')
output storageSyncServiceId string = storageSyncService.id

@description('Sync Group name')
output syncGroupName string = syncGroup.name

@description('Cloud Endpoint name')
output cloudEndpointName string = cloudEndpoint.name

@description('Primary storage account key (for configuration purposes)')
@secure()
output storageAccountKey string = storageAccount.listKeys().keys[0].value

@description('Storage Account connection string')
@secure()
output storageConnectionString string = 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};AccountKey=${storageAccount.listKeys().keys[0].value};EndpointSuffix=${environment().suffixes.storage}'

@description('Server registration information for Azure File Sync agent')
output serverRegistrationInfo object = {
  storageSyncServiceId: storageSyncService.id
  resourceGroupName: resourceGroup().name
  subscriptionId: subscription().subscriptionId
  location: location
  syncGroupName: syncGroup.name
  tenantId: tenant().tenantId
}

@description('Azure File Share mounting instructions')
output mountingInstructions object = {
  windowsCmd: 'net use Z: \\\\${storageAccount.name}.file.${environment().suffixes.storage}\\${fileShareName} /persistent:yes'
  powershell: '$connectTestResult = Test-NetConnection -ComputerName ${storageAccount.name}.file.${environment().suffixes.storage} -Port 445; if ($connectTestResult.TcpTestSucceeded) { cmd.exe /C "cmdkey /add:`"${storageAccount.name}.file.${environment().suffixes.storage}`" /user:`"localhost\\${storageAccount.name}`" /pass:`"<storage-account-key>`""; New-PSDrive -Name Z -PSProvider FileSystem -Root "\\\\${storageAccount.name}.file.${environment().suffixes.storage}\\${fileShareName}" -Persist } else { Write-Error -Message "Unable to reach the Azure storage account via port 445. Check to make sure your organization or ISP is not blocking port 445, or use Azure P2S VPN, Azure S2S VPN, or Express Route to tunnel SMB traffic over a different port." }'
  linux: 'sudo mkdir /mnt/${fileShareName}; sudo mount -t cifs //${storageAccount.name}.file.${environment().suffixes.storage}/${fileShareName} /mnt/${fileShareName} -o vers=3.0,username=${storageAccount.name},password=<storage-account-key>,dir_mode=0777,file_mode=0777,serverino'
}

@description('Resource tags applied')
output appliedTags object = tags

@description('Estimated monthly cost breakdown (USD)')
output estimatedMonthlyCosts object = {
  storageAccount: {
    description: 'Storage costs for ${fileShareQuota}GB file share'
    estimatedCost: '${fileShareQuota * 0.06} - ${fileShareQuota * 0.18} USD/month (varies by redundancy and access tier)'
  }
  syncService: {
    description: 'Azure File Sync service costs'
    baseCost: 'First server endpoint free, additional servers ~15 USD/month each'
    transactionCosts: 'Transaction costs based on sync activity (typically < 5 USD/month)'
  }
  totalEstimate: 'Approximately ${fileShareQuota * 0.06 + 5} - ${fileShareQuota * 0.18 + 20} USD/month depending on configuration'
}