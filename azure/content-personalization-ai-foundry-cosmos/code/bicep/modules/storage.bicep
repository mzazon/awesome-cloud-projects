@description('Storage Account module for Azure Functions')

// Parameters
@description('Name of the storage account')
param storageAccountName string

@description('Azure region for resource deployment')
param location string

@description('Tags to apply to the resource')
param tags object = {}

// Variables
var storageAccountSku = 'Standard_LRS'
var storageAccountKind = 'StorageV2'
var accessTier = 'Hot'

// Resources
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: storageAccountName
  location: location
  tags: tags
  sku: {
    name: storageAccountSku
  }
  kind: storageAccountKind
  properties: {
    accessTier: accessTier
    supportsHttpsTrafficOnly: true
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
    allowSharedKeyAccess: true
    networkAcls: {
      defaultAction: 'Allow'
      bypass: 'AzureServices'
    }
    encryption: {
      services: {
        blob: {
          enabled: true
        }
        file: {
          enabled: true
        }
      }
      keySource: 'Microsoft.Storage'
    }
  }
}

// Outputs
@description('Storage Account Resource ID')
output storageAccountId string = storageAccount.id

@description('Storage Account Name')
output storageAccountName string = storageAccount.name

@description('Storage Account Connection String')
@secure()
output connectionString string = 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};AccountKey=${storageAccount.listKeys().keys[0].value};EndpointSuffix=${environment().suffixes.storage}'

@description('Storage Account Primary Endpoints')
output primaryEndpoints object = storageAccount.properties.primaryEndpoints