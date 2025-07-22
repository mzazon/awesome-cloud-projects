@description('The name of the Service Fabric cluster')
param clusterName string = 'sf-cluster-${uniqueString(resourceGroup().id)}'

@description('The location where resources will be deployed')
param location string = resourceGroup().location

@description('The name of the Application Insights resource')
param applicationInsightsName string = 'ai-monitoring-${uniqueString(resourceGroup().id)}'

@description('The name of the Log Analytics workspace')
param logAnalyticsWorkspaceName string = 'la-workspace-${uniqueString(resourceGroup().id)}'

@description('The name of the Function App')
param functionAppName string = 'fn-eventprocessor-${uniqueString(resourceGroup().id)}'

@description('The name of the storage account for the Function App')
param storageAccountName string = 'st${uniqueString(resourceGroup().id)}'

@description('The name of the Event Hub namespace')
param eventHubNamespaceName string = 'eh-namespace-${uniqueString(resourceGroup().id)}'

@description('The name of the Event Hub')
param eventHubName string = 'service-events'

@description('Admin username for the Service Fabric cluster')
param adminUsername string = 'azureuser'

@description('Admin password for the Service Fabric cluster')
@secure()
param adminPassword string

@description('The SKU for the Service Fabric cluster')
@allowed([
  'Basic'
  'Standard'
])
param clusterSku string = 'Standard'

@description('The number of Event Hub partitions')
@minValue(1)
@maxValue(32)
param eventHubPartitionCount int = 4

@description('The retention period for Event Hub messages in days')
@minValue(1)
@maxValue(7)
param eventHubRetentionDays int = 1

@description('The pricing tier for the Log Analytics workspace')
@allowed([
  'Free'
  'Standalone'
  'PerNode'
  'PerGB2018'
])
param logAnalyticsWorkspaceSku string = 'PerGB2018'

@description('The retention period for Log Analytics data in days')
@minValue(30)
@maxValue(730)
param logAnalyticsRetentionDays int = 30

@description('Tags to apply to all resources')
param tags object = {
  purpose: 'microservices-monitoring'
  environment: 'demo'
}

// Log Analytics Workspace
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: logAnalyticsWorkspaceName
  location: location
  tags: tags
  properties: {
    sku: {
      name: logAnalyticsWorkspaceSku
    }
    retentionInDays: logAnalyticsRetentionDays
    features: {
      enableLogAccessUsingOnlyResourcePermissions: true
    }
    workspaceCapping: {
      dailyQuotaGb: 1
    }
  }
}

// Application Insights
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

// Event Hub Namespace
resource eventHubNamespace 'Microsoft.EventHub/namespaces@2024-01-01' = {
  name: eventHubNamespaceName
  location: location
  tags: tags
  sku: {
    name: 'Standard'
    tier: 'Standard'
    capacity: 1
  }
  properties: {
    minimumTlsVersion: '1.2'
    publicNetworkAccess: 'Enabled'
    disableLocalAuth: false
    zoneRedundant: false
    isAutoInflateEnabled: true
    maximumThroughputUnits: 10
    kafkaEnabled: false
  }
}

// Event Hub
resource eventHub 'Microsoft.EventHub/namespaces/eventhubs@2024-01-01' = {
  parent: eventHubNamespace
  name: eventHubName
  properties: {
    messageRetentionInDays: eventHubRetentionDays
    partitionCount: eventHubPartitionCount
    status: 'Active'
  }
}

// Event Hub Authorization Rule
resource eventHubAuthorizationRule 'Microsoft.EventHub/namespaces/eventhubs/authorizationRules@2024-01-01' = {
  parent: eventHub
  name: 'FunctionAppAccessKey'
  properties: {
    rights: [
      'Send'
      'Listen'
    ]
  }
}

// Storage Account for Function App
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: storageAccountName
  location: location
  tags: tags
  sku: {
    name: 'Standard_LRS'
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
    accessTier: 'Hot'
  }
}

// Function App Service Plan
resource functionAppServicePlan 'Microsoft.Web/serverfarms@2023-12-01' = {
  name: '${functionAppName}-plan'
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

// Function App
resource functionApp 'Microsoft.Web/sites@2023-12-01' = {
  name: functionAppName
  location: location
  tags: tags
  kind: 'functionapp,linux'
  properties: {
    serverFarmId: functionAppServicePlan.id
    reserved: true
    isXenon: false
    hyperV: false
    vnetRouteAllEnabled: false
    vnetImagePullEnabled: false
    vnetContentShareEnabled: false
    siteConfig: {
      numberOfWorkers: 1
      linuxFxVersion: 'Node|18'
      acrUseManagedIdentityCreds: false
      alwaysOn: false
      http20Enabled: false
      functionAppScaleLimit: 200
      minimumElasticInstanceCount: 0
      appSettings: [
        {
          name: 'AzureWebJobsStorage'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};EndpointSuffix=${environment().suffixes.storage};AccountKey=${storageAccount.listKeys().keys[0].value}'
        }
        {
          name: 'WEBSITE_CONTENTAZUREFILECONNECTIONSTRING'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};EndpointSuffix=${environment().suffixes.storage};AccountKey=${storageAccount.listKeys().keys[0].value}'
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
          value: 'node'
        }
        {
          name: 'WEBSITE_NODE_DEFAULT_VERSION'
          value: '~18'
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
          name: 'ApplicationInsightsAgent_EXTENSION_VERSION'
          value: '~3'
        }
        {
          name: 'EventHubConnectionString'
          value: eventHubAuthorizationRule.listKeys().primaryConnectionString
        }
        {
          name: 'EventHubName'
          value: eventHubName
        }
      ]
      ftpsState: 'FtpsOnly'
      minTlsVersion: '1.2'
    }
    scmSiteAlsoStopped: false
    clientAffinityEnabled: false
    clientCertEnabled: false
    clientCertMode: 'Required'
    hostNamesDisabled: false
    containerSize: 1536
    dailyMemoryTimeQuota: 0
    httpsOnly: true
    redundancyMode: 'None'
    storageAccountRequired: false
    keyVaultReferenceIdentity: 'SystemAssigned'
  }
}

// Service Fabric Managed Cluster
resource serviceFabricCluster 'Microsoft.ServiceFabric/managedclusters@2024-04-01' = {
  name: clusterName
  location: location
  tags: tags
  sku: {
    name: clusterSku
  }
  properties: {
    clusterCodeVersion: '9.1.1436.9590'
    clusterUpgradeMode: 'Automatic'
    adminUserName: adminUsername
    adminPassword: adminPassword
    dnsName: clusterName
    clientConnectionPort: 19000
    httpGatewayConnectionPort: 19080
    loadBalancingRules: [
      {
        frontendPort: 80
        backendPort: 80
        protocol: 'tcp'
        probeProtocol: 'tcp'
      }
      {
        frontendPort: 443
        backendPort: 443
        protocol: 'tcp'
        probeProtocol: 'tcp'
      }
    ]
    allowRdpAccess: false
    networkSecurityRules: [
      {
        name: 'allowSvcFabSMB'
        description: 'allow port 445'
        protocol: '*'
        sourcePortRange: '*'
        destinationPortRange: '445'
        sourceAddressPrefix: 'VirtualNetwork'
        destinationAddressPrefix: '*'
        access: 'Allow'
        priority: 3950
        direction: 'Inbound'
      }
      {
        name: 'allowSvcFabCluser'
        description: 'allow ports 1025-1027'
        protocol: '*'
        sourcePortRange: '*'
        destinationPortRange: '1025-1027'
        sourceAddressPrefix: 'VirtualNetwork'
        destinationAddressPrefix: '*'
        access: 'Allow'
        priority: 3960
        direction: 'Inbound'
      }
      {
        name: 'allowSvcFabEphemeral'
        description: 'allow ports 49152-65534'
        protocol: '*'
        sourcePortRange: '*'
        destinationPortRange: '49152-65534'
        sourceAddressPrefix: 'VirtualNetwork'
        destinationAddressPrefix: '*'
        access: 'Allow'
        priority: 3970
        direction: 'Inbound'
      }
      {
        name: 'allowSvcFabPortal'
        description: 'allow port 19080'
        protocol: '*'
        sourcePortRange: '*'
        destinationPortRange: '19080'
        sourceAddressPrefix: '*'
        destinationAddressPrefix: '*'
        access: 'Allow'
        priority: 3980
        direction: 'Inbound'
      }
      {
        name: 'allowSvcFabClient'
        description: 'allow port 19000'
        protocol: '*'
        sourcePortRange: '*'
        destinationPortRange: '19000'
        sourceAddressPrefix: '*'
        destinationAddressPrefix: '*'
        access: 'Allow'
        priority: 3990
        direction: 'Inbound'
      }
    ]
    fabricSettings: [
      {
        name: 'Security'
        parameters: [
          {
            name: 'ClusterCredentialType'
            value: 'None'
          }
        ]
      }
    ]
  }
}

// Service Fabric Node Type
resource serviceFabricNodeType 'Microsoft.ServiceFabric/managedclusters/nodetypes@2024-04-01' = {
  parent: serviceFabricCluster
  name: 'nt1'
  properties: {
    isPrimary: true
    vmImageSku: '2022-Datacenter'
    vmSize: 'Standard_D2s_v3'
    vmInstanceCount: 3
    dataDiskSizeGB: 128
    dataDiskType: 'StandardSSD_LRS'
    placementProperties: {}
    capacities: {}
    applicationPorts: {
      startPort: 20000
      endPort: 30000
    }
    ephemeralPorts: {
      startPort: 49152
      endPort: 65534
    }
    vmManagedIdentity: {
      type: 'SystemAssigned'
    }
    isStateless: false
    multiplePlacementGroups: false
    frontendConfigurations: [
      {
        ipAddressType: 'IPv4'
        loadBalancerBackendAddressPoolId: '${serviceFabricCluster.id}/providers/Microsoft.Network/loadBalancers/${clusterName}-LB/backendAddressPools/LoadBalancerBEAddressPool'
        loadBalancerInboundNatPoolId: '${serviceFabricCluster.id}/providers/Microsoft.Network/loadBalancers/${clusterName}-LB/inboundNatPools/LoadBalancerBEAddressNatPool'
      }
    ]
    vmExtensions: [
      {
        name: 'ServiceFabricNode'
        properties: {
          type: 'ServiceFabricNode'
          publisher: 'Microsoft.Azure.ServiceFabric'
          typeHandlerVersion: '1.1'
          autoUpgradeMinorVersion: true
          settings: {}
        }
      }
    ]
  }
}

// Diagnostic Settings for Service Fabric Cluster
resource serviceFabricDiagnosticSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'sf-diagnostics'
  scope: serviceFabricCluster
  properties: {
    workspaceId: logAnalyticsWorkspace.id
    logs: [
      {
        category: 'OperationalChannel'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: logAnalyticsRetentionDays
        }
      }
      {
        category: 'ReliableServiceActorChannel'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: logAnalyticsRetentionDays
        }
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: logAnalyticsRetentionDays
        }
      }
    ]
  }
}

// Alert Rules for Service Fabric Cluster Health
resource clusterHealthAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: 'Service Fabric Cluster Health'
  location: 'global'
  tags: tags
  properties: {
    description: 'Alert when cluster health degrades'
    severity: 2
    enabled: true
    scopes: [
      serviceFabricCluster.id
    ]
    evaluationFrequency: 'PT1M'
    windowSize: 'PT5M'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'ClusterHealthState'
          metricName: 'ClusterHealthState'
          operator: 'LessThan'
          threshold: 3
          timeAggregation: 'Average'
          metricNamespace: 'Microsoft.ServiceFabric/managedclusters'
        }
      ]
    }
    autoMitigate: true
  }
}

// Scheduled Query Rule for Application Errors
resource errorRateAlert 'Microsoft.Insights/scheduledQueryRules@2023-03-15-preview' = {
  name: 'High Error Rate Alert'
  location: location
  tags: tags
  properties: {
    description: 'Alert when error rate exceeds threshold'
    severity: 2
    enabled: true
    evaluationFrequency: 'PT1M'
    windowSize: 'PT5M'
    scopes: [
      logAnalyticsWorkspace.id
    ]
    criteria: {
      allOf: [
        {
          query: 'exceptions | where timestamp > ago(5m) | summarize count()'
          timeAggregation: 'Count'
          operator: 'GreaterThan'
          threshold: 10
          failingPeriods: {
            numberOfEvaluationPeriods: 1
            minFailingPeriodsToAlert: 1
          }
        }
      ]
    }
    autoMitigate: true
  }
}

// Outputs
@description('The name of the Service Fabric cluster')
output clusterName string = serviceFabricCluster.name

@description('The endpoint of the Service Fabric cluster')
output clusterEndpoint string = 'https://${serviceFabricCluster.properties.fqdn}:19080'

@description('The client connection endpoint of the Service Fabric cluster')
output clientConnectionEndpoint string = '${serviceFabricCluster.properties.fqdn}:19000'

@description('The Application Insights instrumentation key')
output applicationInsightsInstrumentationKey string = applicationInsights.properties.InstrumentationKey

@description('The Application Insights connection string')
output applicationInsightsConnectionString string = applicationInsights.properties.ConnectionString

@description('The Event Hub connection string')
output eventHubConnectionString string = eventHubAuthorizationRule.listKeys().primaryConnectionString

@description('The Function App name')
output functionAppName string = functionApp.name

@description('The Function App URL')
output functionAppUrl string = 'https://${functionApp.properties.defaultHostName}'

@description('The Log Analytics workspace ID')
output logAnalyticsWorkspaceId string = logAnalyticsWorkspace.id

@description('The resource group name')
output resourceGroupName string = resourceGroup().name

@description('The Service Fabric cluster resource ID')
output serviceFabricClusterId string = serviceFabricCluster.id

@description('The storage account name')
output storageAccountName string = storageAccount.name