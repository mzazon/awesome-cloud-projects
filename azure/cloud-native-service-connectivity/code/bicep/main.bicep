// ===========================================================================
// Azure Cloud-Native Service Connectivity with Application Gateway for Containers
// This Bicep template implements the infrastructure for cloud-native service
// connectivity using Azure Application Gateway for Containers and Service Connector
// ===========================================================================

targetScope = 'resourceGroup'

// ===========================================================================
// PARAMETERS
// ===========================================================================

@description('Location for all resources')
param location string = resourceGroup().location

@description('Prefix for all resource names')
@minLength(3)
@maxLength(10)
param resourcePrefix string = 'cloudnative'

@description('Environment name (dev, staging, prod)')
@allowed(['dev', 'staging', 'prod'])
param environment string = 'dev'

@description('AKS cluster configuration')
param aksConfig object = {
  nodeCount: 3
  nodeVmSize: 'Standard_D2s_v3'
  kubernetesVersion: '1.29.0'
  enableWorkloadIdentity: true
  networkPlugin: 'azure'
  networkPolicy: 'azure'
}

@description('Application Gateway for Containers configuration')
param applicationGatewayConfig object = {
  sku: 'Standard_v2'
  capacity: 2
  frontendPort: 80
  protocol: 'Http'
}

@description('Storage account configuration')
param storageConfig object = {
  sku: 'Standard_LRS'
  kind: 'StorageV2'
  allowBlobPublicAccess: false
  minTlsVersion: 'TLS1_2'
}

@description('SQL Database configuration')
param sqlConfig object = {
  edition: 'Basic'
  computeModel: 'Serverless'
  autoPauseDelay: 60
  adminUsername: 'cloudadmin'
  adminPassword: 'SecurePassword123!'
}

@description('Key Vault configuration')
param keyVaultConfig object = {
  sku: 'standard'
  enableRbacAuthorization: true
  enableSoftDelete: true
  softDeleteRetentionInDays: 90
}

@description('Tags to be applied to all resources')
param tags object = {
  Environment: environment
  Purpose: 'cloud-native-connectivity'
  ManagedBy: 'bicep'
}

// ===========================================================================
// VARIABLES
// ===========================================================================

var uniqueSuffix = uniqueString(resourceGroup().id)
var aksClusterName = '${resourcePrefix}-aks-${uniqueSuffix}'
var applicationGatewayName = '${resourcePrefix}-agc-${uniqueSuffix}'
var storageAccountName = '${resourcePrefix}stor${uniqueSuffix}'
var sqlServerName = '${resourcePrefix}-sqlserver-${uniqueSuffix}'
var keyVaultName = '${resourcePrefix}-kv-${uniqueSuffix}'
var workloadIdentityName = '${resourcePrefix}-wi-${uniqueSuffix}'
var logAnalyticsWorkspaceName = '${resourcePrefix}-log-${uniqueSuffix}'
var applicationInsightsName = '${resourcePrefix}-ai-${uniqueSuffix}'

// Networking variables
var vnetName = '${resourcePrefix}-vnet-${uniqueSuffix}'
var vnetAddressPrefix = '10.0.0.0/16'
var aksSubnetName = 'aks-subnet'
var aksSubnetAddressPrefix = '10.0.1.0/24'
var applicationGatewaySubnetName = 'agc-subnet'
var applicationGatewaySubnetAddressPrefix = '10.0.2.0/24'
var privateEndpointSubnetName = 'pe-subnet'
var privateEndpointSubnetAddressPrefix = '10.0.3.0/24'

// ===========================================================================
// RESOURCES
// ===========================================================================

// Log Analytics Workspace for monitoring
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
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

// Application Insights for application monitoring
resource applicationInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: applicationInsightsName
  location: location
  tags: tags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logAnalyticsWorkspace.id
  }
}

// Virtual Network for all resources
resource virtualNetwork 'Microsoft.Network/virtualNetworks@2023-11-01' = {
  name: vnetName
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [
        vnetAddressPrefix
      ]
    }
    subnets: [
      {
        name: aksSubnetName
        properties: {
          addressPrefix: aksSubnetAddressPrefix
          serviceEndpoints: [
            {
              service: 'Microsoft.Storage'
            }
            {
              service: 'Microsoft.Sql'
            }
            {
              service: 'Microsoft.KeyVault'
            }
          ]
        }
      }
      {
        name: applicationGatewaySubnetName
        properties: {
          addressPrefix: applicationGatewaySubnetAddressPrefix
          delegations: [
            {
              name: 'Microsoft.ServiceNetworking/trafficControllers'
              properties: {
                serviceName: 'Microsoft.ServiceNetworking/trafficControllers'
              }
            }
          ]
        }
      }
      {
        name: privateEndpointSubnetName
        properties: {
          addressPrefix: privateEndpointSubnetAddressPrefix
          privateEndpointNetworkPolicies: 'Disabled'
        }
      }
    ]
  }
}

// User-assigned managed identity for workload identity
resource workloadIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: workloadIdentityName
  location: location
  tags: tags
}

// Azure Kubernetes Service (AKS) cluster
resource aksCluster 'Microsoft.ContainerService/managedClusters@2024-02-01' = {
  name: aksClusterName
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    kubernetesVersion: aksConfig.kubernetesVersion
    dnsPrefix: aksClusterName
    agentPoolProfiles: [
      {
        name: 'systempool'
        count: aksConfig.nodeCount
        vmSize: aksConfig.nodeVmSize
        osType: 'Linux'
        mode: 'System'
        vnetSubnetID: '${virtualNetwork.id}/subnets/${aksSubnetName}'
        enableNodePublicIP: false
        maxPods: 110
        type: 'VirtualMachineScaleSets'
        availabilityZones: [
          '1'
          '2'
          '3'
        ]
        upgradeSettings: {
          maxSurge: '1'
        }
        nodeTaints: [
          'CriticalAddonsOnly=true:NoSchedule'
        ]
      }
      {
        name: 'workerpool'
        count: aksConfig.nodeCount
        vmSize: aksConfig.nodeVmSize
        osType: 'Linux'
        mode: 'User'
        vnetSubnetID: '${virtualNetwork.id}/subnets/${aksSubnetName}'
        enableNodePublicIP: false
        maxPods: 110
        type: 'VirtualMachineScaleSets'
        availabilityZones: [
          '1'
          '2'
          '3'
        ]
        upgradeSettings: {
          maxSurge: '1'
        }
      }
    ]
    networkProfile: {
      networkPlugin: aksConfig.networkPlugin
      networkPolicy: aksConfig.networkPolicy
      serviceCidr: '10.1.0.0/16'
      dnsServiceIP: '10.1.0.10'
      loadBalancerSku: 'Standard'
    }
    addonProfiles: {
      omsagent: {
        enabled: true
        config: {
          logAnalyticsWorkspaceResourceID: logAnalyticsWorkspace.id
        }
      }
      azurepolicy: {
        enabled: true
      }
    }
    oidcIssuerProfile: {
      enabled: aksConfig.enableWorkloadIdentity
    }
    securityProfile: {
      workloadIdentity: {
        enabled: aksConfig.enableWorkloadIdentity
      }
    }
    apiServerAccessProfile: {
      enablePrivateCluster: false
      enablePrivateClusterPublicFQDN: false
    }
    autoScalerProfile: {
      'scale-down-delay-after-add': '10m'
      'scale-down-unneeded-time': '10m'
      'scale-down-utilization-threshold': '0.5'
    }
  }
}

// Application Gateway for Containers
resource applicationGatewayForContainers 'Microsoft.ServiceNetworking/trafficControllers@2023-11-01' = {
  name: applicationGatewayName
  location: location
  tags: tags
  properties: {
    associations: [
      {
        associationType: 'subnets'
        subnet: {
          id: '${virtualNetwork.id}/subnets/${applicationGatewaySubnetName}'
        }
      }
    ]
  }
}

// Frontend configuration for Application Gateway for Containers
resource applicationGatewayFrontend 'Microsoft.ServiceNetworking/trafficControllers/frontends@2023-11-01' = {
  parent: applicationGatewayForContainers
  name: 'frontend-config'
  location: location
  properties: {
    fqdn: '${applicationGatewayName}.${location}.cloudapp.azure.com'
  }
}

// Storage Account for application data
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: storageAccountName
  location: location
  tags: tags
  kind: storageConfig.kind
  sku: {
    name: storageConfig.sku
  }
  properties: {
    accessTier: 'Hot'
    allowBlobPublicAccess: storageConfig.allowBlobPublicAccess
    minimumTlsVersion: storageConfig.minTlsVersion
    supportsHttpsTrafficOnly: true
    networkAcls: {
      defaultAction: 'Allow'
      virtualNetworkRules: [
        {
          id: '${virtualNetwork.id}/subnets/${aksSubnetName}'
          action: 'Allow'
        }
      ]
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

// Blob container for application data
resource blobContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = {
  name: '${storageAccount.name}/default/application-data'
  properties: {
    publicAccess: 'None'
  }
}

// SQL Server for application database
resource sqlServer 'Microsoft.Sql/servers@2023-08-01-preview' = {
  name: sqlServerName
  location: location
  tags: tags
  properties: {
    administratorLogin: sqlConfig.adminUsername
    administratorLoginPassword: sqlConfig.adminPassword
    version: '12.0'
    publicNetworkAccess: 'Enabled'
    restrictOutboundNetworkAccess: 'Disabled'
  }
}

// SQL Database
resource sqlDatabase 'Microsoft.Sql/servers/databases@2023-08-01-preview' = {
  parent: sqlServer
  name: 'application-db'
  location: location
  tags: tags
  sku: {
    name: 'GP_S_Gen5'
    tier: 'GeneralPurpose'
    family: 'Gen5'
    capacity: 1
  }
  properties: {
    collation: 'SQL_Latin1_General_CP1_CI_AS'
    maxSizeBytes: 1073741824 // 1 GB
    catalogCollation: 'SQL_Latin1_General_CP1_CI_AS'
    zoneRedundant: false
    requestedServiceObjectiveName: 'GP_S_Gen5_1'
    isLedgerOn: false
    availabilityZone: 'NoPreference'
    autoPauseDelay: sqlConfig.autoPauseDelay
    minCapacity: json('0.5')
  }
}

// SQL Server virtual network rule
resource sqlVnetRule 'Microsoft.Sql/servers/virtualNetworkRules@2023-08-01-preview' = {
  parent: sqlServer
  name: 'aks-subnet-rule'
  properties: {
    virtualNetworkSubnetId: '${virtualNetwork.id}/subnets/${aksSubnetName}'
    ignoreMissingVnetServiceEndpoint: false
  }
}

// Key Vault for secrets management
resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: keyVaultName
  location: location
  tags: tags
  properties: {
    tenantId: subscription().tenantId
    sku: {
      family: 'A'
      name: keyVaultConfig.sku
    }
    accessPolicies: []
    enabledForDeployment: false
    enabledForDiskEncryption: false
    enabledForTemplateDeployment: false
    enableSoftDelete: keyVaultConfig.enableSoftDelete
    softDeleteRetentionInDays: keyVaultConfig.softDeleteRetentionInDays
    enableRbacAuthorization: keyVaultConfig.enableRbacAuthorization
    enablePurgeProtection: true
    networkAcls: {
      defaultAction: 'Allow'
      virtualNetworkRules: [
        {
          id: '${virtualNetwork.id}/subnets/${aksSubnetName}'
          ignoreMissingVnetServiceEndpoint: false
        }
      ]
    }
  }
}

// Key Vault secrets
resource keyVaultSecrets 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = [
  {
    parent: keyVault
    name: 'database-connection-timeout'
    properties: {
      value: '30'
    }
  }
  {
    parent: keyVault
    name: 'api-rate-limit'
    properties: {
      value: '1000'
    }
  }
  {
    parent: keyVault
    name: 'storage-connection-string'
    properties: {
      value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};AccountKey=${storageAccount.listKeys().keys[0].value};EndpointSuffix=${environment().suffixes.storage}'
    }
  }
]

// ===========================================================================
// ROLE ASSIGNMENTS
// ===========================================================================

// Storage Blob Data Contributor role for workload identity
resource storageRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccount.id, workloadIdentity.id, 'ba92f5b4-2d11-453d-a403-e96b0029c9fe')
  scope: storageAccount
  properties: {
    principalId: workloadIdentity.properties.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'ba92f5b4-2d11-453d-a403-e96b0029c9fe') // Storage Blob Data Contributor
  }
}

// Key Vault Secrets User role for workload identity
resource keyVaultRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(keyVault.id, workloadIdentity.id, '4633458b-17de-408a-b874-0445c86b69e6')
  scope: keyVault
  properties: {
    principalId: workloadIdentity.properties.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '4633458b-17de-408a-b874-0445c86b69e6') // Key Vault Secrets User
  }
}

// SQL DB Contributor role for workload identity
resource sqlRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(sqlDatabase.id, workloadIdentity.id, '9b7fa17d-e63e-47b0-bb0a-15c516ac86ec')
  scope: sqlDatabase
  properties: {
    principalId: workloadIdentity.properties.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '9b7fa17d-e63e-47b0-bb0a-15c516ac86ec') // SQL DB Contributor
  }
}

// Contributor role for AKS cluster to manage Application Gateway for Containers
resource aksContributorRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(applicationGatewayForContainers.id, aksCluster.id, 'b24988ac-6180-42a0-ab88-20f7382dd24c')
  scope: applicationGatewayForContainers
  properties: {
    principalId: aksCluster.identity.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b24988ac-6180-42a0-ab88-20f7382dd24c') // Contributor
  }
}

// Network Contributor role for AKS cluster on the virtual network
resource aksNetworkContributorRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(virtualNetwork.id, aksCluster.id, '4d97b98b-1d4f-4787-a291-c67834d212e7')
  scope: virtualNetwork
  properties: {
    principalId: aksCluster.identity.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '4d97b98b-1d4f-4787-a291-c67834d212e7') // Network Contributor
  }
}

// ===========================================================================
// OUTPUTS
// ===========================================================================

@description('AKS cluster name')
output aksClusterName string = aksCluster.name

@description('AKS cluster resource ID')
output aksClusterResourceId string = aksCluster.id

@description('AKS cluster FQDN')
output aksClusterFqdn string = aksCluster.properties.fqdn

@description('AKS cluster OIDC issuer URL')
output aksOidcIssuerUrl string = aksCluster.properties.oidcIssuerProfile.issuerURL

@description('Application Gateway for Containers name')
output applicationGatewayName string = applicationGatewayForContainers.name

@description('Application Gateway for Containers resource ID')
output applicationGatewayResourceId string = applicationGatewayForContainers.id

@description('Application Gateway for Containers FQDN')
output applicationGatewayFqdn string = applicationGatewayFrontend.properties.fqdn

@description('Workload Identity client ID')
output workloadIdentityClientId string = workloadIdentity.properties.clientId

@description('Workload Identity principal ID')
output workloadIdentityPrincipalId string = workloadIdentity.properties.principalId

@description('Storage account name')
output storageAccountName string = storageAccount.name

@description('Storage account resource ID')
output storageAccountResourceId string = storageAccount.id

@description('SQL Server name')
output sqlServerName string = sqlServer.name

@description('SQL Server FQDN')
output sqlServerFqdn string = sqlServer.properties.fullyQualifiedDomainName

@description('SQL Database name')
output sqlDatabaseName string = sqlDatabase.name

@description('Key Vault name')
output keyVaultName string = keyVault.name

@description('Key Vault URI')
output keyVaultUri string = keyVault.properties.vaultUri

@description('Virtual Network name')
output virtualNetworkName string = virtualNetwork.name

@description('Virtual Network resource ID')
output virtualNetworkResourceId string = virtualNetwork.id

@description('AKS subnet name')
output aksSubnetName string = aksSubnetName

@description('Application Gateway subnet name')
output applicationGatewaySubnetName string = applicationGatewaySubnetName

@description('Log Analytics Workspace name')
output logAnalyticsWorkspaceName string = logAnalyticsWorkspace.name

@description('Log Analytics Workspace resource ID')
output logAnalyticsWorkspaceResourceId string = logAnalyticsWorkspace.id

@description('Application Insights name')
output applicationInsightsName string = applicationInsights.name

@description('Application Insights connection string')
output applicationInsightsConnectionString string = applicationInsights.properties.ConnectionString

@description('Tags applied to resources')
output appliedTags object = tags

@description('Resource group location')
output resourceGroupLocation string = location

@description('Deployment summary')
output deploymentSummary object = {
  aksCluster: {
    name: aksCluster.name
    kubernetesVersion: aksCluster.properties.kubernetesVersion
    nodeCount: aksConfig.nodeCount
    nodeVmSize: aksConfig.nodeVmSize
  }
  applicationGateway: {
    name: applicationGatewayForContainers.name
    fqdn: applicationGatewayFrontend.properties.fqdn
  }
  workloadIdentity: {
    name: workloadIdentity.name
    clientId: workloadIdentity.properties.clientId
  }
  services: {
    storage: storageAccount.name
    sqlServer: sqlServer.name
    sqlDatabase: sqlDatabase.name
    keyVault: keyVault.name
  }
  networking: {
    virtualNetwork: virtualNetwork.name
    aksSubnet: aksSubnetName
    applicationGatewaySubnet: applicationGatewaySubnetName
  }
  monitoring: {
    logAnalytics: logAnalyticsWorkspace.name
    applicationInsights: applicationInsights.name
  }
}