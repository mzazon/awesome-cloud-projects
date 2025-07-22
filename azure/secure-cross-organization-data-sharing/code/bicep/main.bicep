@description('Main Bicep template for Secure Cross-Organization Data Sharing with Data Share and Service Fabric')

// Parameters
@description('The Azure region where resources will be deployed')
param location string = resourceGroup().location

@description('Unique suffix for resource names to ensure global uniqueness')
param uniqueSuffix string = substring(uniqueString(resourceGroup().id), 0, 6)

@description('Environment designation (dev, test, prod)')
@allowed(['dev', 'test', 'prod'])
param environment string = 'dev'

@description('Organization role in data sharing (provider or consumer)')
@allowed(['provider', 'consumer'])
param organizationRole string = 'provider'

@description('Service Fabric cluster VM size')
@allowed(['Standard_D2s_v3', 'Standard_D4s_v3', 'Standard_D8s_v3'])
param serviceFabricVmSize string = 'Standard_D2s_v3'

@description('Number of Service Fabric cluster nodes')
@minValue(3)
@maxValue(99)
param serviceFabricNodeCount int = 5

@description('Service Fabric cluster OS type')
@allowed(['WindowsServer2019Datacenter', 'WindowsServer2022Datacenter'])
param serviceFabricOsType string = 'WindowsServer2019Datacenter'

@description('Storage account SKU')
@allowed(['Standard_LRS', 'Standard_GRS', 'Standard_RAGRS'])
param storageAccountSku string = 'Standard_LRS'

@description('Key Vault SKU')
@allowed(['standard', 'premium'])
param keyVaultSku string = 'standard'

@description('Log Analytics workspace pricing tier')
@allowed(['PerGB2018', 'Free', 'Standalone', 'PerNode'])
param logAnalyticsSku string = 'PerGB2018'

@description('Tags to apply to all resources')
param resourceTags object = {
  purpose: 'cross-org-data-collaboration'
  environment: environment
  recipe: 'azure-data-share-service-fabric'
  'managed-by': 'bicep'
}

// Variables
var storageAccountName = 'st${organizationRole}${uniqueSuffix}'
var keyVaultName = 'kv-${organizationRole}-${uniqueSuffix}'
var serviceFabricClusterName = 'sf-governance-${uniqueSuffix}'
var dataShareAccountName = 'datashare${uniqueSuffix}'
var logAnalyticsWorkspaceName = 'law-datashare-${uniqueSuffix}'
var applicationInsightsName = 'ai-datashare-${uniqueSuffix}'
var serviceFabricCertificateName = '${serviceFabricClusterName}-cert'

// Get current user/service principal for Key Vault access policies
var currentUser = {
  objectId: ''
  tenantId: tenant().tenantId
}

// Storage Account for data repositories
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: storageAccountName
  location: location
  tags: resourceTags
  sku: {
    name: storageAccountSku
  }
  kind: 'StorageV2'
  properties: {
    accessTier: 'Hot'
    supportsHttpsTrafficOnly: true
    allowBlobPublicAccess: false
    minimumTlsVersion: 'TLS1_2'
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

  // Blob service configuration
  resource blobService 'blobServices@2023-01-01' = {
    name: 'default'
    properties: {
      deleteRetentionPolicy: {
        enabled: true
        days: 7
      }
      containerDeleteRetentionPolicy: {
        enabled: true
        days: 7
      }
    }

    // Container for shared datasets
    resource sharedDatasetsContainer 'containers@2023-01-01' = {
      name: 'shared-datasets'
      properties: {
        publicAccess: 'None'
        metadata: {
          purpose: 'cross-organization-data-sharing'
          dataClassification: 'confidential'
        }
      }
    }
  }
}

// Key Vault for secrets management
resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: keyVaultName
  location: location
  tags: resourceTags
  properties: {
    sku: {
      family: 'A'
      name: keyVaultSku
    }
    tenantId: tenant().tenantId
    enabledForDeployment: true
    enabledForTemplateDeployment: true
    enabledForDiskEncryption: false
    enableSoftDelete: true
    softDeleteRetentionInDays: 7
    enablePurgeProtection: false
    enableRbacAuthorization: false
    accessPolicies: [
      {
        tenantId: tenant().tenantId
        objectId: currentUser.objectId != '' ? currentUser.objectId : '00000000-0000-0000-0000-000000000000'
        permissions: {
          keys: ['get', 'list', 'create', 'delete', 'update']
          secrets: ['get', 'list', 'set', 'delete']
          certificates: ['get', 'list', 'create', 'delete', 'update', 'import']
        }
      }
    ]
    networkAcls: {
      defaultAction: 'Allow'
      bypass: 'AzureServices'
    }
  }
}

// Log Analytics Workspace for monitoring and audit trails
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: logAnalyticsWorkspaceName
  location: location
  tags: resourceTags
  properties: {
    sku: {
      name: logAnalyticsSku
    }
    retentionInDays: 30
    features: {
      enableLogAccessUsingOnlyResourcePermissions: true
    }
  }
}

// Application Insights for application monitoring
resource applicationInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: applicationInsightsName
  location: location
  tags: resourceTags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logAnalyticsWorkspace.id
    IngestionMode: 'LogAnalytics'
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

// Service Fabric Cluster for microservices orchestration
resource serviceFabricCluster 'Microsoft.ServiceFabric/clusters@2021-06-01' = {
  name: serviceFabricClusterName
  location: location
  tags: resourceTags
  properties: {
    clusterCodeVersion: '9.1.1436.9590'
    upgradeMode: 'Automatic'
    vmImage: serviceFabricOsType
    fabricSettings: [
      {
        name: 'Security'
        parameters: [
          {
            name: 'ClusterCredentialType'
            value: 'X509'
          }
        ]
      }
      {
        name: 'Diagnostics'
        parameters: [
          {
            name: 'ProducerInstances'
            value: 'WinFabEtlFile, WinFabCrashDump'
          }
          {
            name: 'ConsumerInstances'
            value: 'AzureWinFabEtlUploader, AzureWinFabCrashDumpUploader'
          }
        ]
      }
    ]
    managementEndpoint: 'https://${serviceFabricClusterName}.${location}.cloudapp.azure.com:19080'
    nodeTypes: [
      {
        name: 'NodeType0'
        clientConnectionEndpointPort: 19000
        httpGatewayEndpointPort: 19080
        applicationPorts: {
          startPort: 20000
          endPort: 30000
        }
        ephemeralPorts: {
          startPort: 49152
          endPort: 65534
        }
        isPrimary: true
        vmInstanceCount: serviceFabricNodeCount
        durabilityLevel: 'Bronze'
        placementProperties: {
          NodeTypeName: 'NodeType0'
        }
        capacities: {
          memory: '4096'
          cpu: '2'
        }
      }
    ]
    reliabilityLevel: 'Bronze'
    certificate: {
      thumbprint: ''
      x509StoreName: 'My'
    }
    clientCertificateThumbprints: []
    clientCertificateCommonNames: []
    azureActiveDirectory: {
      tenantId: tenant().tenantId
      clusterApplication: ''
      clientApplication: ''
    }
    diagnosticsStorageAccountConfig: {
      storageAccountName: storageAccount.name
      protectedAccountKeyName: 'StorageAccountKey1'
      blobEndpoint: storageAccount.properties.primaryEndpoints.blob
      queueEndpoint: storageAccount.properties.primaryEndpoints.queue
      tableEndpoint: storageAccount.properties.primaryEndpoints.table
    }
  }
}

// Azure Data Share Account (only for provider organization)
resource dataShareAccount 'Microsoft.DataShare/accounts@2021-08-01' = if (organizationRole == 'provider') {
  name: dataShareAccountName
  location: location
  tags: union(resourceTags, {
    role: 'data-provider'
    governance: 'enabled'
  })
  identity: {
    type: 'SystemAssigned'
  }
  properties: {}
}

// Data Share for financial collaboration (only for provider)
resource financialDataShare 'Microsoft.DataShare/accounts/shares@2021-08-01' = if (organizationRole == 'provider') {
  parent: dataShareAccount
  name: 'financial-collaboration-share'
  properties: {
    description: 'Cross-organization financial data sharing for analytics and compliance'
    termsOfUse: 'Data for internal use only. No redistribution allowed. Must comply with data governance policies.'
    shareKind: 'CopyBased'
  }
}

// Role assignment for Data Share to access storage account
resource dataShareStorageRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (organizationRole == 'provider') {
  name: guid(storageAccount.id, dataShareAccount.id, 'Storage Blob Data Reader')
  scope: storageAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '2a2b9908-6ea1-4ae2-8e65-a410df84e7d1') // Storage Blob Data Reader
    principalId: organizationRole == 'provider' ? dataShareAccount.identity.principalId : ''
    principalType: 'ServicePrincipal'
  }
}

// Diagnostic settings for comprehensive monitoring
resource serviceFabricDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'sf-diagnostics'
  scope: serviceFabricCluster
  properties: {
    workspaceId: logAnalyticsWorkspace.id
    logs: [
      {
        categoryGroup: 'allLogs'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: 30
        }
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: 30
        }
      }
    ]
  }
}

resource storageAccountDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'storage-diagnostics'
  scope: storageAccount
  properties: {
    workspaceId: logAnalyticsWorkspace.id
    logs: [
      {
        categoryGroup: 'allLogs'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: 30
        }
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: 30
        }
      }
    ]
  }
}

resource dataShareDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (organizationRole == 'provider') {
  name: 'datashare-diagnostics'
  scope: dataShareAccount
  properties: {
    workspaceId: logAnalyticsWorkspace.id
    logs: [
      {
        categoryGroup: 'allLogs'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: 30
        }
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: 30
        }
      }
    ]
  }
}

// Outputs
@description('Storage account name for data repositories')
output storageAccountName string = storageAccount.name

@description('Storage account primary endpoints')
output storageAccountEndpoints object = storageAccount.properties.primaryEndpoints

@description('Key Vault name for secrets management')
output keyVaultName string = keyVault.name

@description('Key Vault URI')
output keyVaultUri string = keyVault.properties.vaultUri

@description('Service Fabric cluster name')
output serviceFabricClusterName string = serviceFabricCluster.name

@description('Service Fabric cluster endpoint')
output serviceFabricClusterEndpoint string = serviceFabricCluster.properties.clusterEndpoint

@description('Service Fabric management endpoint')
output serviceFabricManagementEndpoint string = serviceFabricCluster.properties.managementEndpoint

@description('Data Share account name (provider only)')
output dataShareAccountName string = organizationRole == 'provider' ? dataShareAccount.name : ''

@description('Data Share account resource ID (provider only)')
output dataShareAccountId string = organizationRole == 'provider' ? dataShareAccount.id : ''

@description('Data Share name (provider only)')
output dataShareName string = organizationRole == 'provider' ? financialDataShare.name : ''

@description('Log Analytics workspace name')
output logAnalyticsWorkspaceName string = logAnalyticsWorkspace.name

@description('Log Analytics workspace ID')
output logAnalyticsWorkspaceId string = logAnalyticsWorkspace.properties.customerId

@description('Application Insights name')
output applicationInsightsName string = applicationInsights.name

@description('Application Insights instrumentation key')
output applicationInsightsInstrumentationKey string = applicationInsights.properties.InstrumentationKey

@description('Application Insights connection string')
output applicationInsightsConnectionString string = applicationInsights.properties.ConnectionString

@description('Resource group location')
output location string = location

@description('Unique suffix used for resource naming')
output uniqueSuffix string = uniqueSuffix

@description('Organization role in data sharing')
output organizationRole string = organizationRole

@description('All resource tags applied')
output resourceTags object = resourceTags