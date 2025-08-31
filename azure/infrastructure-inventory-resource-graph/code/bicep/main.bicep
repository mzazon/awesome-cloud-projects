@description('Main Bicep template for Infrastructure Inventory Reports with Azure Resource Graph')

// Parameters
@description('The Azure region where resources will be deployed')
param location string = resourceGroup().location

@description('Environment name (e.g., dev, staging, prod)')
@allowed(['dev', 'staging', 'prod'])
param environment string = 'dev'

@description('Organization name for resource naming')
@minLength(2)
@maxLength(10)
param organizationName string

@description('Enable automated inventory reports')
param enableAutomatedReports bool = true

@description('Inventory report frequency in hours (24, 48, 72, 168)')
@allowed([24, 48, 72, 168])
param reportFrequencyHours int = 24

@description('Storage account tier for inventory reports')
@allowed(['Standard_LRS', 'Standard_GRS', 'Standard_ZRS'])
param storageAccountType string = 'Standard_LRS'

@description('Enable compliance monitoring queries')
param enableComplianceMonitoring bool = true

@description('Resource tags to apply to all resources')
param tags object = {
  Environment: environment
  Solution: 'Infrastructure-Inventory-Resource-Graph'
  ManagedBy: 'Bicep'
}

// Variables
var uniqueSuffix = substring(uniqueString(resourceGroup().id), 0, 6)
var storageAccountName = 'inv${organizationName}${uniqueSuffix}'
var functionAppName = 'func-inventory-${organizationName}-${environment}-${uniqueSuffix}'
var appServicePlanName = 'asp-inventory-${organizationName}-${environment}-${uniqueSuffix}'
var keyVaultName = 'kv-inv-${organizationName}-${uniqueSuffix}'
var logAnalyticsWorkspaceName = 'law-inventory-${organizationName}-${environment}-${uniqueSuffix}'
var applicationInsightsName = 'ai-inventory-${organizationName}-${environment}-${uniqueSuffix}'
var managedIdentityName = 'id-inventory-${organizationName}-${environment}-${uniqueSuffix}'

// Managed Identity for Resource Graph access
resource managedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: managedIdentityName
  location: location
  tags: tags
}

// Storage Account for inventory reports
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: storageAccountName
  location: location
  tags: tags
  sku: {
    name: storageAccountType
  }
  kind: 'StorageV2'
  properties: {
    accessTier: 'Hot'
    allowBlobPublicAccess: false
    allowSharedKeyAccess: true
    defaultToOAuthAuthentication: false
    minimumTlsVersion: 'TLS1_2'
    networkAcls: {
      defaultAction: 'Allow'
    }
    supportsHttpsTrafficOnly: true
  }
  
  // Blob service for inventory reports
  resource blobService 'blobServices@2023-01-01' = {
    name: 'default'
    properties: {
      deleteRetentionPolicy: {
        enabled: true
        days: 30
      }
      versioning: {
        enabled: true
      }
    }
    
    // Container for inventory reports
    resource inventoryContainer 'containers@2023-01-01' = {
      name: 'inventory-reports'
      properties: {
        publicAccess: 'None'
        metadata: {
          purpose: 'Infrastructure inventory reports storage'
        }
      }
    }
    
    // Container for compliance reports
    resource complianceContainer 'containers@2023-01-01' = if (enableComplianceMonitoring) {
      name: 'compliance-reports'
      properties: {
        publicAccess: 'None'
        metadata: {
          purpose: 'Compliance monitoring reports storage'
        }
      }
    }
  }
}

// Log Analytics Workspace for monitoring
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2022-10-01' = {
  name: logAnalyticsWorkspaceName
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
    features: {
      enableLogAccessUsingOnlyResourcePermissions: true
    }
  }
}

// Application Insights for function monitoring
resource applicationInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: applicationInsightsName
  location: location
  tags: tags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logAnalyticsWorkspace.id
    IngestionMode: 'LogAnalytics'
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

// Key Vault for storing connection strings and secrets
resource keyVault 'Microsoft.KeyVault/vaults@2023-02-01' = {
  name: keyVaultName
  location: location
  tags: tags
  properties: {
    sku: {
      family: 'A'
      name: 'standard'
    }
    tenantId: subscription().tenantId
    accessPolicies: [
      {
        tenantId: subscription().tenantId
        objectId: managedIdentity.properties.principalId
        permissions: {
          secrets: [
            'get'
            'list'
          ]
        }
      }
    ]
    enabledForDeployment: false
    enabledForDiskEncryption: false
    enabledForTemplateDeployment: false
    enableSoftDelete: true
    softDeleteRetentionInDays: 7
    enableRbacAuthorization: false
    networkAcls: {
      defaultAction: 'Allow'
      bypass: 'AzureServices'
    }
  }
  
  // Storage account connection string secret
  resource storageConnectionStringSecret 'secrets@2023-02-01' = {
    name: 'StorageConnectionString'
    properties: {
      value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};AccountKey=${storageAccount.listKeys().keys[0].value};EndpointSuffix=${environment().suffixes.storage}'
    }
  }
}

// App Service Plan for Function App
resource appServicePlan 'Microsoft.Web/serverfarms@2022-09-01' = if (enableAutomatedReports) {
  name: appServicePlanName
  location: location
  tags: tags
  sku: {
    name: 'Y1'
    tier: 'Dynamic'
    size: 'Y1'
    family: 'Y'
    capacity: 0
  }
  properties: {
    reserved: false
  }
}

// Function App for automated inventory reports
resource functionApp 'Microsoft.Web/sites@2022-09-01' = if (enableAutomatedReports) {
  name: functionAppName
  location: location
  tags: tags
  kind: 'functionapp'
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${managedIdentity.id}': {}
    }
  }
  properties: {
    serverFarmId: enableAutomatedReports ? appServicePlan.id : null
    siteConfig: {
      appSettings: [
        {
          name: 'AzureWebJobsStorage'
          value: '@Microsoft.KeyVault(VaultName=${keyVault.name};SecretName=StorageConnectionString)'
        }
        {
          name: 'WEBSITE_CONTENTAZUREFILECONNECTIONSTRING'
          value: '@Microsoft.KeyVault(VaultName=${keyVault.name};SecretName=StorageConnectionString)'
        }
        {
          name: 'WEBSITE_CONTENTSHARE'
          value: toLower(functionAppName)
        }
        {
          name: 'FUNCTIONS_EXTENSION_VERSION'
          value: '~4'
        }
        {
          name: 'FUNCTIONS_WORKER_RUNTIME'
          value: 'powershell'
        }
        {
          name: 'FUNCTIONS_WORKER_RUNTIME_VERSION'
          value: '7.2'
        }
        {
          name: 'APPINSIGHTS_INSTRUMENTATIONKEY'
          value: applicationInsights.properties.InstrumentationKey
        }
        {
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: applicationInsights.properties.ConnectionString
        }
        {
          name: 'AZURE_CLIENT_ID'
          value: managedIdentity.properties.clientId
        }
        {
          name: 'INVENTORY_STORAGE_ACCOUNT'
          value: storageAccount.name
        }
        {
          name: 'REPORT_FREQUENCY_HOURS'
          value: string(reportFrequencyHours)
        }
        {
          name: 'ENABLE_COMPLIANCE_MONITORING'
          value: string(enableComplianceMonitoring)
        }
        {
          name: 'ORGANIZATION_NAME'
          value: organizationName
        }
        {
          name: 'ENVIRONMENT'
          value: environment
        }
      ]
      powerShellVersion: '7.2'
      use32BitWorkerProcess: false
      ftpsState: 'Disabled'
      minTlsVersion: '1.2'
    }
    httpsOnly: true
    clientAffinityEnabled: false
  }
}

// Role assignment for Reader access to subscription (required for Resource Graph queries)
resource readerRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(subscription().subscriptionId, managedIdentity.id, 'Reader')
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'acdd72a7-3385-48ef-bd42-f606fba81ae7') // Reader role
    principalId: managedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

// Storage Blob Data Contributor role for the managed identity
resource storageBlobDataContributorRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccount.id, managedIdentity.id, 'Storage Blob Data Contributor')
  scope: storageAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'ba92f5b4-2d11-453d-a403-e96b0029c9fe') // Storage Blob Data Contributor
    principalId: managedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

// Workbook for inventory dashboard
resource inventoryWorkbook 'Microsoft.Insights/workbooks@2022-04-01' = {
  name: guid(resourceGroup().id, 'inventory-workbook')
  location: location
  tags: tags
  kind: 'shared'
  properties: {
    displayName: 'Infrastructure Inventory Dashboard'
    serializedData: loadTextContent('workbook-template.json')
    version: '1.0'
    sourceId: logAnalyticsWorkspace.id
    category: 'workbook'
  }
}

// Outputs
@description('Name of the storage account containing inventory reports')
output storageAccountName string = storageAccount.name

@description('Resource ID of the managed identity for Resource Graph access')
output managedIdentityId string = managedIdentity.id

@description('Principal ID of the managed identity')
output managedIdentityPrincipalId string = managedIdentity.properties.principalId

@description('Client ID of the managed identity')
output managedIdentityClientId string = managedIdentity.properties.clientId

@description('Name of the Function App (if automated reports are enabled)')
output functionAppName string = enableAutomatedReports ? functionApp.name : ''

@description('Name of the Key Vault containing secrets')
output keyVaultName string = keyVault.name

@description('Name of the Log Analytics workspace')
output logAnalyticsWorkspaceName string = logAnalyticsWorkspace.name

@description('Application Insights instrumentation key')
output applicationInsightsInstrumentationKey string = applicationInsights.properties.InstrumentationKey

@description('URL to access the inventory dashboard workbook')
output workbookUrl string = 'https://portal.azure.com/#blade/Microsoft_Azure_MonitoringMetrics/AzureMonitoringBrowseBlade/resourceType/microsoft.insights%2Fworkbooks/resourceGroup/${resourceGroup().name}/resource/${inventoryWorkbook.name}'

@description('Sample Resource Graph queries for inventory reporting')
output sampleQueries object = {
  basicInventory: 'Resources | project name, type, location, resourceGroup, subscriptionId | order by type asc, name asc'
  resourceCountByType: 'Resources | summarize count() by type | order by count_ desc'
  locationDistribution: 'Resources | where location != \'\' | summarize ResourceCount=count() by Location=location | order by ResourceCount desc'
  taggingCompliance: 'Resources | extend TagCount = array_length(todynamic(tags)) | extend HasTags = case(TagCount > 0, \'Tagged\', \'Untagged\') | summarize count() by HasTags, type | order by type asc'
  untaggedResources: 'Resources | where tags !has \'Environment\' or tags !has \'Owner\' | project name, type, resourceGroup, location, tags | limit 20'
  comprehensiveInventory: 'Resources | project ResourceName=name, ResourceType=type, Location=location, ResourceGroup=resourceGroup, SubscriptionId=subscriptionId, Tags=tags, ResourceId=id, Kind=kind | order by ResourceType asc, ResourceName asc'
}

@description('Instructions for using the deployed infrastructure')
output usageInstructions object = {
  azureCliSetup: 'az extension add --name resource-graph'
  basicQuery: 'az graph query -q "Resources | limit 5" --output table'
  exportToStorage: 'Use the deployed Function App or manually export query results to the created storage account'
  dashboard: 'Access the inventory dashboard workbook using the provided URL'
  managedIdentity: 'The deployed managed identity has Reader access to the subscription for Resource Graph queries'
}