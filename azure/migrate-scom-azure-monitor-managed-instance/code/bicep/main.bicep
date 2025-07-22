// Azure Monitor SCOM Managed Instance Infrastructure
// This template deploys the complete infrastructure for migrating on-premises SCOM to Azure Monitor SCOM Managed Instance

@description('The Azure region where all resources will be deployed')
param location string = resourceGroup().location

@description('Environment name (e.g., dev, test, prod)')
@allowed(['dev', 'test', 'prod'])
param environmentName string = 'prod'

@description('Unique suffix for resource names to ensure global uniqueness')
param resourceSuffix string = uniqueString(resourceGroup().id)

@description('Virtual network address space')
param vnetAddressPrefix string = '10.0.0.0/16'

@description('SCOM Managed Instance subnet address prefix')
param scomSubnetAddressPrefix string = '10.0.1.0/24'

@description('SQL Managed Instance subnet address prefix (minimum /27)')
param sqlSubnetAddressPrefix string = '10.0.2.0/27'

@description('SQL Managed Instance administrator username')
param sqlAdminUsername string = 'scomadmin'

@description('SQL Managed Instance administrator password')
@secure()
param sqlAdminPassword string

@description('SQL Managed Instance compute tier')
@allowed(['GeneralPurpose', 'BusinessCritical'])
param sqlTier string = 'GeneralPurpose'

@description('SQL Managed Instance compute generation')
@allowed(['Gen4', 'Gen5'])
param sqlComputeGeneration string = 'Gen5'

@description('SQL Managed Instance vCore capacity')
@allowed([4, 8, 16, 24, 32, 40, 64, 80])
param sqlVCores int = 8

@description('SQL Managed Instance storage size in GB')
@minValue(32)
@maxValue(16384)
param sqlStorageSize int = 256

@description('SQL Managed Instance license type')
@allowed(['LicenseIncluded', 'BasePrice'])
param sqlLicenseType string = 'BasePrice'

@description('Enable public endpoint for SQL Managed Instance')
param sqlPublicEndpointEnabled bool = true

@description('SCOM Managed Instance capacity settings')
@allowed(['Small', 'Medium', 'Large'])
param scomCapacity string = 'Medium'

@description('Log Analytics workspace retention in days')
@minValue(7)
@maxValue(730)
param logAnalyticsRetentionDays int = 30

@description('Tags to apply to all resources')
param tags object = {
  Environment: environmentName
  Purpose: 'SCOM Migration'
  ManagedBy: 'Bicep'
}

// Variables for resource names
var resourceNames = {
  vnet: 'vnet-scom-${resourceSuffix}'
  scomSubnet: 'scom-mi-subnet'
  sqlSubnet: 'sql-mi-subnet'
  scomNsg: 'nsg-scom-mi-${resourceSuffix}'
  sqlNsg: 'nsg-sql-mi-${resourceSuffix}'
  routeTable: 'rt-scom-${resourceSuffix}'
  sqlManagedInstance: 'sql-mi-${resourceSuffix}'
  scomManagedInstance: 'scom-mi-${resourceSuffix}'
  keyVault: 'kv-scom-${resourceSuffix}'
  storageAccount: 'stscom${replace(resourceSuffix, '-', '')}'
  logAnalyticsWorkspace: 'law-scom-${resourceSuffix}'
  managedIdentity: 'id-scom-mi-${resourceSuffix}'
  actionGroup: 'ag-scom-alerts-${resourceSuffix}'
}

// Managed Identity for SCOM Managed Instance
resource managedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: resourceNames.managedIdentity
  location: location
  tags: tags
}

// Key Vault for secrets management
resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: resourceNames.keyVault
  location: location
  tags: tags
  properties: {
    sku: {
      family: 'A'
      name: 'standard'
    }
    tenantId: subscription().tenantId
    enabledForDeployment: true
    enabledForTemplateDeployment: true
    enabledForDiskEncryption: true
    enableRbacAuthorization: true
    enableSoftDelete: true
    softDeleteRetentionInDays: 90
    enablePurgeProtection: true
    networkAcls: {
      defaultAction: 'Allow'
      bypass: 'AzureServices'
    }
  }
}

// Storage Account for management pack migration
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: resourceNames.storageAccount
  location: location
  tags: tags
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    accessTier: 'Hot'
    allowBlobPublicAccess: false
    allowSharedKeyAccess: true
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
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
  }
}

// Blob container for management packs
resource managementPacksContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = {
  name: '${storageAccount.name}/default/management-packs'
  properties: {
    publicAccess: 'None'
  }
}

// Route Table for SQL Managed Instance
resource routeTable 'Microsoft.Network/routeTables@2023-11-01' = {
  name: resourceNames.routeTable
  location: location
  tags: tags
  properties: {
    routes: [
      {
        name: 'subnet-to-vnetlocal'
        properties: {
          addressPrefix: vnetAddressPrefix
          nextHopType: 'VnetLocal'
        }
      }
    ]
    disableBgpRoutePropagation: false
  }
}

// Network Security Group for SCOM Managed Instance
resource scomNsg 'Microsoft.Network/networkSecurityGroups@2023-11-01' = {
  name: resourceNames.scomNsg
  location: location
  tags: tags
  properties: {
    securityRules: [
      {
        name: 'Allow-SCOM-Agents'
        properties: {
          protocol: 'Tcp'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: 'VirtualNetwork'
          destinationPortRange: '5723'
          access: 'Allow'
          priority: 1000
          direction: 'Inbound'
        }
      }
      {
        name: 'Allow-SCOM-Console'
        properties: {
          protocol: 'Tcp'
          sourceAddressPrefix: 'VirtualNetwork'
          sourcePortRange: '*'
          destinationAddressPrefix: 'VirtualNetwork'
          destinationPortRange: '5724'
          access: 'Allow'
          priority: 1100
          direction: 'Inbound'
        }
      }
      {
        name: 'Allow-SCOM-WebConsole'
        properties: {
          protocol: 'Tcp'
          sourceAddressPrefix: 'VirtualNetwork'
          sourcePortRange: '*'
          destinationAddressPrefix: 'VirtualNetwork'
          destinationPortRange: '80'
          access: 'Allow'
          priority: 1200
          direction: 'Inbound'
        }
      }
      {
        name: 'Allow-SCOM-WebConsole-SSL'
        properties: {
          protocol: 'Tcp'
          sourceAddressPrefix: 'VirtualNetwork'
          sourcePortRange: '*'
          destinationAddressPrefix: 'VirtualNetwork'
          destinationPortRange: '443'
          access: 'Allow'
          priority: 1300
          direction: 'Inbound'
        }
      }
      {
        name: 'Allow-SQL-MI-Access'
        properties: {
          protocol: 'Tcp'
          sourceAddressPrefix: 'VirtualNetwork'
          sourcePortRange: '*'
          destinationAddressPrefix: 'VirtualNetwork'
          destinationPortRanges: ['1433', '3342']
          access: 'Allow'
          priority: 1100
          direction: 'Outbound'
        }
      }
      {
        name: 'Allow-Internet-Outbound'
        properties: {
          protocol: '*'
          sourceAddressPrefix: 'VirtualNetwork'
          sourcePortRange: '*'
          destinationAddressPrefix: 'Internet'
          destinationPortRange: '*'
          access: 'Allow'
          priority: 1200
          direction: 'Outbound'
        }
      }
    ]
  }
}

// Network Security Group for SQL Managed Instance
resource sqlNsg 'Microsoft.Network/networkSecurityGroups@2023-11-01' = {
  name: resourceNames.sqlNsg
  location: location
  tags: tags
  properties: {
    securityRules: [
      {
        name: 'allow_tds_inbound'
        properties: {
          protocol: 'Tcp'
          sourceAddressPrefix: 'VirtualNetwork'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '1433'
          access: 'Allow'
          priority: 1000
          direction: 'Inbound'
        }
      }
      {
        name: 'allow_redirect_inbound'
        properties: {
          protocol: 'Tcp'
          sourceAddressPrefix: 'VirtualNetwork'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '11000-11999'
          access: 'Allow'
          priority: 1100
          direction: 'Inbound'
        }
      }
      {
        name: 'allow_geodr_inbound'
        properties: {
          protocol: 'Tcp'
          sourceAddressPrefix: 'VirtualNetwork'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '5022'
          access: 'Allow'
          priority: 1200
          direction: 'Inbound'
        }
      }
      {
        name: 'allow_publicEndpoint_inbound'
        properties: {
          protocol: 'Tcp'
          sourceAddressPrefix: 'Internet'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '3342'
          access: sqlPublicEndpointEnabled ? 'Allow' : 'Deny'
          priority: 1300
          direction: 'Inbound'
        }
      }
    ]
  }
}

// Virtual Network
resource vnet 'Microsoft.Network/virtualNetworks@2023-11-01' = {
  name: resourceNames.vnet
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [vnetAddressPrefix]
    }
    subnets: [
      {
        name: resourceNames.scomSubnet
        properties: {
          addressPrefix: scomSubnetAddressPrefix
          networkSecurityGroup: {
            id: scomNsg.id
          }
        }
      }
      {
        name: resourceNames.sqlSubnet
        properties: {
          addressPrefix: sqlSubnetAddressPrefix
          networkSecurityGroup: {
            id: sqlNsg.id
          }
          routeTable: {
            id: routeTable.id
          }
          delegations: [
            {
              name: 'Microsoft.Sql.managedInstances'
              properties: {
                serviceName: 'Microsoft.Sql/managedInstances'
              }
            }
          ]
        }
      }
    ]
  }
}

// SQL Managed Instance
resource sqlManagedInstance 'Microsoft.Sql/managedInstances@2023-08-01-preview' = {
  name: resourceNames.sqlManagedInstance
  location: location
  tags: tags
  sku: {
    name: sqlTier
    tier: sqlTier
    capacity: sqlVCores
    family: sqlComputeGeneration
  }
  properties: {
    administratorLogin: sqlAdminUsername
    administratorLoginPassword: sqlAdminPassword
    subnetId: '${vnet.id}/subnets/${resourceNames.sqlSubnet}'
    licenseType: sqlLicenseType
    vCores: sqlVCores
    storageSizeInGB: sqlStorageSize
    publicDataEndpointEnabled: sqlPublicEndpointEnabled
    collation: 'SQL_Latin1_General_CP1_CI_AS'
    timezoneId: 'UTC'
    proxyOverride: 'Proxy'
    minimalTlsVersion: '1.2'
    storageAccountType: 'GRS'
    zoneRedundant: false
    requestedBackupStorageRedundancy: 'Geo'
  }
}

// Log Analytics Workspace for monitoring integration
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: resourceNames.logAnalyticsWorkspace
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: logAnalyticsRetentionDays
    features: {
      enableLogAccessUsingOnlyResourcePermissions: true
      disableLocalAuth: false
    }
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

// Action Group for alerting
resource actionGroup 'Microsoft.Insights/actionGroups@2023-01-01' = {
  name: resourceNames.actionGroup
  location: 'Global'
  tags: tags
  properties: {
    groupShortName: 'SCOMAlerts'
    enabled: true
    emailReceivers: [
      {
        name: 'admin'
        emailAddress: 'admin@company.com'
        useCommonAlertSchema: true
      }
    ]
    smsReceivers: []
    webhookReceivers: []
    itsmReceivers: []
    azureAppPushReceivers: []
    automationRunbookReceivers: []
    voiceReceivers: []
    logicAppReceivers: []
    azureFunctionReceivers: []
    armRoleReceivers: []
    eventHubReceivers: []
  }
}

// Role assignment for Managed Identity to access Key Vault
resource keyVaultSecretsUserRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(keyVault.id, managedIdentity.id, 'Key Vault Secrets User')
  scope: keyVault
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '4633458b-17de-408a-b874-0445c86b69e6') // Key Vault Secrets User
    principalId: managedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

// Role assignment for Managed Identity to access Storage Account
resource storageDataContributorRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccount.id, managedIdentity.id, 'Storage Blob Data Contributor')
  scope: storageAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'ba92f5b4-2d11-453d-a403-e96b0029c9fe') // Storage Blob Data Contributor
    principalId: managedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

// Store SQL connection string in Key Vault
resource sqlConnectionStringSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  name: 'sql-connection-string'
  parent: keyVault
  properties: {
    value: 'Server=${sqlManagedInstance.properties.fullyQualifiedDomainName},3342;Database=master;User ID=${sqlAdminUsername};Password=${sqlAdminPassword};Encrypt=true;TrustServerCertificate=false;'
    contentType: 'text/plain'
  }
}

// Note: SCOM Managed Instance resource is commented out as it's in preview
// Uncomment when the resource provider is generally available
/*
resource scomManagedInstance 'Microsoft.Monitor/accounts@2023-04-03' = {
  name: resourceNames.scomManagedInstance
  location: location
  tags: tags
  properties: {
    sqlManagedInstanceResourceId: sqlManagedInstance.id
    subnetResourceId: '${vnet.id}/subnets/${resourceNames.scomSubnet}'
    managedIdentityResourceId: managedIdentity.id
    keyVaultUri: keyVault.properties.vaultUri
    logAnalyticsWorkspaceResourceId: logAnalyticsWorkspace.id
    capacity: scomCapacity
  }
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${managedIdentity.id}': {}
    }
  }
}
*/

// Outputs
output resourceGroupName string = resourceGroup().name
output vnetId string = vnet.id
output vnetName string = vnet.name
output scomSubnetId string = '${vnet.id}/subnets/${resourceNames.scomSubnet}'
output sqlSubnetId string = '${vnet.id}/subnets/${resourceNames.sqlSubnet}'
output sqlManagedInstanceId string = sqlManagedInstance.id
output sqlManagedInstanceFqdn string = sqlManagedInstance.properties.fullyQualifiedDomainName
output keyVaultId string = keyVault.id
output keyVaultUri string = keyVault.properties.vaultUri
output storageAccountId string = storageAccount.id
output storageAccountName string = storageAccount.name
output logAnalyticsWorkspaceId string = logAnalyticsWorkspace.id
output logAnalyticsWorkspaceName string = logAnalyticsWorkspace.name
output managedIdentityId string = managedIdentity.id
output managedIdentityPrincipalId string = managedIdentity.properties.principalId
output actionGroupId string = actionGroup.id
output deploymentInstructions string = 'SQL Managed Instance deployment may take 4-6 hours. Monitor deployment status in Azure Portal.'