@description('The name of the resource group where resources will be deployed')
param resourceGroupName string = resourceGroup().name

@description('The location where resources will be deployed')
param location string = resourceGroup().location

@description('A unique suffix to ensure resource names are globally unique')
param uniqueSuffix string = uniqueString(resourceGroup().id)

@description('Environment name (dev, staging, prod)')
@allowed(['dev', 'staging', 'prod'])
param environment string = 'dev'

@description('The pricing tier for the App Service Plan')
@allowed(['B1', 'B2', 'B3', 'S1', 'S2', 'S3', 'P1V2', 'P2V2', 'P3V2'])
param appServicePlanSku string = 'P1V2'

@description('The number of workers for the App Service Plan')
@minValue(1)
@maxValue(20)
param appServicePlanWorkerCount int = 1

@description('The container registry SKU')
@allowed(['Basic', 'Standard', 'Premium'])
param containerRegistrySku string = 'Basic'

@description('The storage account SKU')
@allowed(['Standard_LRS', 'Standard_GRS', 'Standard_RAGRS', 'Standard_ZRS'])
param storageAccountSku string = 'Standard_LRS'

@description('The storage account access tier')
@allowed(['Hot', 'Cool'])
param storageAccountAccessTier string = 'Hot'

@description('The data location for Communication Services')
@allowed(['Africa', 'Asia Pacific', 'Australia', 'Brazil', 'Canada', 'Europe', 'France', 'Germany', 'India', 'Japan', 'Korea', 'Norway', 'Switzerland', 'UAE', 'UK', 'United States'])
param communicationServicesDataLocation string = 'United States'

@description('Enable auto-scaling for the App Service Plan')
param enableAutoScaling bool = true

@description('Minimum number of instances for auto-scaling')
@minValue(1)
@maxValue(10)
param autoScaleMinInstances int = 1

@description('Maximum number of instances for auto-scaling')
@minValue(1)
@maxValue(30)
param autoScaleMaxInstances int = 10

@description('CPU threshold for scaling out (percentage)')
@minValue(1)
@maxValue(100)
param scaleOutCpuThreshold int = 70

@description('CPU threshold for scaling in (percentage)')
@minValue(1)
@maxValue(100)
param scaleInCpuThreshold int = 30

@description('The container image name to deploy')
param containerImageName string = 'video-conferencing-app:latest'

@description('Tags to apply to all resources')
param tags object = {
  purpose: 'video-conferencing'
  environment: environment
  project: 'video-conferencing-app'
}

// Resource naming
var storageAccountName = 'stvideoconf${uniqueSuffix}'
var communicationServiceName = 'cs-video-conferencing-${uniqueSuffix}'
var webAppName = 'webapp-video-conferencing-${uniqueSuffix}'
var containerRegistryName = 'acrvideo${uniqueSuffix}'
var appServicePlanName = 'asp-video-conferencing-${uniqueSuffix}'
var applicationInsightsName = 'ai-video-conferencing-${uniqueSuffix}'
var logAnalyticsWorkspaceName = 'law-video-conferencing-${uniqueSuffix}'
var autoScaleSettingsName = 'autoscale-video-conferencing-${uniqueSuffix}'

// Log Analytics Workspace for Application Insights
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

// Application Insights for monitoring
resource applicationInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: applicationInsightsName
  location: location
  tags: tags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    Flow_Type: 'Redfield'
    Request_Source: 'rest'
    WorkspaceResourceId: logAnalyticsWorkspace.id
  }
}

// Azure Container Registry
resource containerRegistry 'Microsoft.ContainerRegistry/registries@2023-07-01' = {
  name: containerRegistryName
  location: location
  tags: tags
  sku: {
    name: containerRegistrySku
  }
  properties: {
    adminUserEnabled: true
    policies: {
      quarantinePolicy: {
        status: 'disabled'
      }
      trustPolicy: {
        type: 'Notary'
        status: 'disabled'
      }
      retentionPolicy: {
        days: 7
        status: 'disabled'
      }
    }
    encryption: {
      status: 'disabled'
    }
    dataEndpointEnabled: false
    publicNetworkAccess: 'Enabled'
    networkRuleBypassOptions: 'AzureServices'
  }
}

// Azure Communication Services
resource communicationService 'Microsoft.Communication/communicationServices@2023-04-01' = {
  name: communicationServiceName
  location: 'global'
  tags: tags
  properties: {
    dataLocation: communicationServicesDataLocation
  }
}

// Storage Account for call recordings
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: storageAccountName
  location: location
  tags: tags
  sku: {
    name: storageAccountSku
  }
  kind: 'StorageV2'
  properties: {
    dnsEndpointType: 'Standard'
    defaultToOAuthAuthentication: false
    publicNetworkAccess: 'Enabled'
    allowCrossTenantReplication: false
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
    allowSharedKeyAccess: true
    networkAcls: {
      bypass: 'AzureServices'
      virtualNetworkRules: []
      ipRules: []
      defaultAction: 'Allow'
    }
    supportsHttpsTrafficOnly: true
    encryption: {
      requireInfrastructureEncryption: false
      services: {
        file: {
          keyType: 'Account'
          enabled: true
        }
        blob: {
          keyType: 'Account'
          enabled: true
        }
      }
      keySource: 'Microsoft.Storage'
    }
    accessTier: storageAccountAccessTier
  }
}

// Blob container for recordings
resource blobContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = {
  name: '${storageAccount.name}/default/recordings'
  properties: {
    immutableStorageWithVersioning: {
      enabled: false
    }
    defaultEncryptionScope: '$account-encryption-key'
    denyEncryptionScopeOverride: false
    publicAccess: 'None'
  }
}

// App Service Plan
resource appServicePlan 'Microsoft.Web/serverfarms@2023-01-01' = {
  name: appServicePlanName
  location: location
  tags: tags
  sku: {
    name: appServicePlanSku
    capacity: appServicePlanWorkerCount
  }
  kind: 'linux'
  properties: {
    perSiteScaling: false
    elasticScaleEnabled: false
    maximumElasticWorkerCount: 1
    isSpot: false
    reserved: true
    isXenon: false
    hyperV: false
    targetWorkerCount: 0
    targetWorkerSizeId: 0
    zoneRedundant: false
  }
}

// Web App for Containers
resource webApp 'Microsoft.Web/sites@2023-01-01' = {
  name: webAppName
  location: location
  tags: tags
  kind: 'app,linux,container'
  properties: {
    enabled: true
    hostNameSslStates: [
      {
        name: '${webAppName}.azurewebsites.net'
        sslState: 'Disabled'
        hostType: 'Standard'
      }
      {
        name: '${webAppName}.scm.azurewebsites.net'
        sslState: 'Disabled'
        hostType: 'Repository'
      }
    ]
    serverFarmId: appServicePlan.id
    reserved: true
    isXenon: false
    hyperV: false
    vnetRouteAllEnabled: false
    vnetImagePullEnabled: false
    vnetContentShareEnabled: false
    siteConfig: {
      numberOfWorkers: 1
      linuxFxVersion: 'DOCKER|${containerRegistry.properties.loginServer}/${containerImageName}'
      acrUseManagedIdentityCreds: false
      alwaysOn: true
      http20Enabled: false
      functionAppScaleLimit: 0
      minimumElasticInstanceCount: 0
      appSettings: [
        {
          name: 'ACS_CONNECTION_STRING'
          value: communicationService.listKeys().primaryConnectionString
        }
        {
          name: 'STORAGE_CONNECTION_STRING'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};EndpointSuffix=${environment().suffixes.storage};AccountKey=${storageAccount.listKeys().keys[0].value}'
        }
        {
          name: 'APPINSIGHTS_INSTRUMENTATION_KEY'
          value: applicationInsights.properties.InstrumentationKey
        }
        {
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: applicationInsights.properties.ConnectionString
        }
        {
          name: 'NODE_ENV'
          value: 'production'
        }
        {
          name: 'DOCKER_REGISTRY_SERVER_URL'
          value: 'https://${containerRegistry.properties.loginServer}'
        }
        {
          name: 'DOCKER_REGISTRY_SERVER_USERNAME'
          value: containerRegistry.name
        }
        {
          name: 'DOCKER_REGISTRY_SERVER_PASSWORD'
          value: containerRegistry.listCredentials().passwords[0].value
        }
        {
          name: 'WEBSITES_ENABLE_APP_SERVICE_STORAGE'
          value: 'false'
        }
        {
          name: 'WEBSITES_PORT'
          value: '3000'
        }
      ]
    }
    scmSiteAlsoStopped: false
    clientAffinityEnabled: false
    clientCertEnabled: false
    clientCertMode: 'Required'
    hostNamesDisabled: false
    customDomainVerificationId: ''
    containerSize: 0
    dailyMemoryTimeQuota: 0
    httpsOnly: true
    redundancyMode: 'None'
    storageAccountRequired: false
    keyVaultReferenceIdentity: 'SystemAssigned'
  }
}

// Web App logging configuration
resource webAppLogging 'Microsoft.Web/sites/config@2023-01-01' = {
  parent: webApp
  name: 'logs'
  properties: {
    applicationLogs: {
      fileSystem: {
        level: 'Warning'
      }
    }
    httpLogs: {
      fileSystem: {
        retentionInMb: 35
        enabled: true
      }
    }
    failedRequestsTracing: {
      enabled: false
    }
    detailedErrorMessages: {
      enabled: false
    }
  }
}

// Auto-scaling settings
resource autoScaleSettings 'Microsoft.Insights/autoscalesettings@2022-10-01' = if (enableAutoScaling) {
  name: autoScaleSettingsName
  location: location
  tags: tags
  properties: {
    name: autoScaleSettingsName
    targetResourceUri: appServicePlan.id
    enabled: true
    profiles: [
      {
        name: 'Default'
        capacity: {
          minimum: string(autoScaleMinInstances)
          maximum: string(autoScaleMaxInstances)
          default: string(appServicePlanWorkerCount)
        }
        rules: [
          {
            metricTrigger: {
              metricName: 'CpuPercentage'
              metricNamespace: 'Microsoft.Web/serverfarms'
              metricResourceUri: appServicePlan.id
              timeGrain: 'PT1M'
              statistic: 'Average'
              timeWindow: 'PT5M'
              timeAggregation: 'Average'
              operator: 'GreaterThan'
              threshold: scaleOutCpuThreshold
              dimensions: []
              dividePerInstance: false
            }
            scaleAction: {
              direction: 'Increase'
              type: 'ChangeCount'
              value: '1'
              cooldown: 'PT5M'
            }
          }
          {
            metricTrigger: {
              metricName: 'CpuPercentage'
              metricNamespace: 'Microsoft.Web/serverfarms'
              metricResourceUri: appServicePlan.id
              timeGrain: 'PT1M'
              statistic: 'Average'
              timeWindow: 'PT5M'
              timeAggregation: 'Average'
              operator: 'LessThan'
              threshold: scaleInCpuThreshold
              dimensions: []
              dividePerInstance: false
            }
            scaleAction: {
              direction: 'Decrease'
              type: 'ChangeCount'
              value: '1'
              cooldown: 'PT5M'
            }
          }
        ]
      }
    ]
    notifications: []
  }
}

// Outputs
@description('The name of the resource group')
output resourceGroupName string = resourceGroupName

@description('The name of the web app')
output webAppName string = webApp.name

@description('The default hostname of the web app')
output webAppUrl string = 'https://${webApp.properties.defaultHostName}'

@description('The name of the container registry')
output containerRegistryName string = containerRegistry.name

@description('The login server of the container registry')
output containerRegistryLoginServer string = containerRegistry.properties.loginServer

@description('The name of the Communication Services resource')
output communicationServiceName string = communicationService.name

@description('The name of the storage account')
output storageAccountName string = storageAccount.name

@description('The name of the Application Insights resource')
output applicationInsightsName string = applicationInsights.name

@description('The instrumentation key for Application Insights')
output applicationInsightsInstrumentationKey string = applicationInsights.properties.InstrumentationKey

@description('The connection string for Application Insights')
output applicationInsightsConnectionString string = applicationInsights.properties.ConnectionString

@description('The name of the App Service Plan')
output appServicePlanName string = appServicePlan.name

@description('The name of the auto-scale settings')
output autoScaleSettingsName string = enableAutoScaling ? autoScaleSettings.name : 'Not configured'

@description('The primary connection string for Communication Services')
output communicationServiceConnectionString string = communicationService.listKeys().primaryConnectionString

@description('The connection string for the storage account')
output storageAccountConnectionString string = 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};EndpointSuffix=${environment().suffixes.storage};AccountKey=${storageAccount.listKeys().keys[0].value}'