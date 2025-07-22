// Azure Stack HCI and Azure Arc Edge Computing Infrastructure
// This template deploys a comprehensive edge computing solution with Azure Stack HCI and Azure Arc

@description('Primary deployment region for cloud resources')
param location string = resourceGroup().location

@description('Environment tag for resource classification')
@allowed(['dev', 'staging', 'production'])
param environment string = 'production'

@description('Base name for all resources (will be combined with random suffix)')
param baseName string = 'edge-infra'

@description('Random suffix for unique resource naming')
param randomSuffix string = uniqueString(resourceGroup().id)

@description('Azure Stack HCI cluster configuration')
param hciClusterConfig object = {
  nodeCount: 2
  vmSize: 'Standard_D8s_v3'
  osType: 'Windows'
}

@description('Azure Kubernetes Service configuration for edge workloads')
param aksConfig object = {
  kubernetesVersion: '1.28.5'
  nodeCount: 2
  nodeVmSize: 'Standard_A4_v2'
  enableAutoScaling: true
  minNodeCount: 1
  maxNodeCount: 5
}

@description('Monitoring and observability configuration')
param monitoringConfig object = {
  retentionInDays: 30
  enableInsights: true
  enableMetrics: true
}

@description('Storage configuration for edge synchronization')
param storageConfig object = {
  skuName: 'Standard_LRS'
  enableHierarchicalNamespace: true
  fileShareQuota: 1024
}

@description('Tags to apply to all resources')
param resourceTags object = {
  purpose: 'edge-computing'
  environment: environment
  solution: 'azure-stack-hci-arc'
  managedBy: 'bicep'
}

// Variables for resource naming
var clusterName = '${baseName}-hci-${randomSuffix}'
var arcResourceName = '${baseName}-arc-${randomSuffix}'
var storageAccountName = 'edgestorage${randomSuffix}'
var logAnalyticsWorkspaceName = '${baseName}-la-${randomSuffix}'
var customLocationName = '${baseName}-cl-${randomSuffix}'
var aksClusterName = '${baseName}-aks-${randomSuffix}'
var syncServiceName = '${baseName}-sync-${randomSuffix}'

// Log Analytics Workspace for centralized monitoring
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: logAnalyticsWorkspaceName
  location: location
  tags: resourceTags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: monitoringConfig.retentionInDays
    features: {
      enableLogAccessUsingOnlyResourcePermissions: true
      disableLocalAuth: false
    }
    workspaceCapping: {
      dailyQuotaGb: 10
    }
  }
}

// Application Insights for application monitoring
resource applicationInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: '${baseName}-appinsights-${randomSuffix}'
  location: location
  tags: resourceTags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logAnalyticsWorkspace.id
    IngestionMode: 'LogAnalytics'
    DisableIpMasking: false
    DisableLocalAuth: false
  }
}

// Storage Account for edge data synchronization
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: storageAccountName
  location: location
  tags: resourceTags
  sku: {
    name: storageConfig.skuName
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
    isHnsEnabled: storageConfig.enableHierarchicalNamespace
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

// File Services for edge synchronization
resource fileServices 'Microsoft.Storage/storageAccounts/fileServices@2023-01-01' = {
  parent: storageAccount
  name: 'default'
  properties: {
    protocolSettings: {
      smb: {
        versions: 'SMB2.1;SMB3.0;SMB3.1.1'
        authenticationMethods: 'NTLMv2;Kerberos'
        kerberosTicketEncryption: 'RC4-HMAC;AES-256'
        channelEncryption: 'AES-128-CCM;AES-128-GCM;AES-256-GCM'
      }
    }
    shareDeleteRetentionPolicy: {
      enabled: true
      days: 7
    }
  }
}

// File Share for edge synchronization
resource fileShare 'Microsoft.Storage/storageAccounts/fileServices/shares@2023-01-01' = {
  parent: fileServices
  name: 'edge-sync'
  properties: {
    shareQuota: storageConfig.fileShareQuota
    enabledProtocols: 'SMB'
    accessTier: 'TransactionOptimized'
  }
}

// Storage Sync Service for file synchronization
resource storageSyncService 'Microsoft.StorageSync/storageSyncServices@2022-09-01' = {
  name: syncServiceName
  location: location
  tags: resourceTags
  properties: {
    incomingTrafficPolicy: 'AllowAllTraffic'
  }
}

// Sync Group for distributed file synchronization
resource syncGroup 'Microsoft.StorageSync/storageSyncServices/syncGroups@2022-09-01' = {
  parent: storageSyncService
  name: 'edge-sync-group'
  properties: {}
}

// Azure Stack HCI Cluster resource
resource hciCluster 'Microsoft.AzureStackHCI/clusters@2023-08-01' = {
  name: clusterName
  location: location
  tags: resourceTags
  properties: {
    cloudManagementEndpoint: 'https://management.azure.com'
    aadClientId: managedIdentity.properties.clientId
    aadTenantId: subscription().tenantId
    desiredProperties: {
      windowsServerSubscription: 'Enabled'
      diagnosticLevel: 'Basic'
    }
  }
  identity: {
    type: 'SystemAssigned'
  }
}

// Managed Identity for Azure Arc and HCI operations
resource managedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: '${baseName}-identity-${randomSuffix}'
  location: location
  tags: resourceTags
}

// Custom Location for Azure Arc enabled Kubernetes
resource customLocation 'Microsoft.ExtendedLocation/customLocations@2021-08-31-preview' = {
  name: customLocationName
  location: location
  tags: resourceTags
  properties: {
    clusterExtensionIds: []
    displayName: customLocationName
    hostResourceId: hciCluster.id
    hostType: 'AzureStackHCI'
    namespace: 'arc-system'
  }
}

// Data Collection Rule for Azure Monitor
resource dataCollectionRule 'Microsoft.Insights/dataCollectionRules@2022-06-01' = {
  name: '${baseName}-dcr-${randomSuffix}'
  location: location
  tags: resourceTags
  properties: {
    description: 'Data collection rule for Azure Stack HCI monitoring'
    dataSources: {
      performanceCounters: [
        {
          name: 'cloudTeamCoreCounters'
          streams: ['Microsoft-Perf']
          scheduledTransferPeriod: 'PT1M'
          samplingFrequencyInSeconds: 15
          counterSpecifiers: [
            '\\Processor(_Total)\\% Processor Time'
            '\\Memory\\Available Bytes'
            '\\LogicalDisk(_Total)\\Disk Reads/sec'
            '\\LogicalDisk(_Total)\\Disk Writes/sec'
            '\\LogicalDisk(_Total)\\% Free Space'
          ]
        }
      ]
      windowsEventLogs: [
        {
          name: 'cloudSecuritySystemEvents'
          streams: ['Microsoft-WindowsEvent']
          xPathQueries: [
            'Security!*[System[(Level=1 or Level=2 or Level=3)]]'
            'System!*[System[(Level=1 or Level=2 or Level=3)]]'
          ]
        }
      ]
    }
    destinations: {
      logAnalytics: [
        {
          workspaceResourceId: logAnalyticsWorkspace.id
          name: logAnalyticsWorkspaceName
        }
      ]
    }
    dataFlows: [
      {
        streams: ['Microsoft-Perf']
        destinations: [logAnalyticsWorkspaceName]
      }
      {
        streams: ['Microsoft-WindowsEvent']
        destinations: [logAnalyticsWorkspaceName]
      }
    ]
  }
}

// Azure Policy Assignment for HCI Security Baseline
resource policyDefinition 'Microsoft.Authorization/policyDefinitions@2021-06-01' = {
  name: guid(resourceGroup().id, 'hci-security-baseline')
  properties: {
    displayName: 'Azure Stack HCI Security Baseline'
    description: 'Ensures Azure Stack HCI clusters meet security requirements'
    policyType: 'Custom'
    mode: 'All'
    parameters: {
      effect: {
        type: 'String'
        defaultValue: 'Audit'
        allowedValues: ['Audit', 'Disabled']
        metadata: {
          displayName: 'Effect'
          description: 'The effect determines what happens when the policy rule is evaluated to match'
        }
      }
    }
    policyRule: {
      if: {
        allOf: [
          {
            field: 'type'
            equals: 'Microsoft.AzureStackHCI/clusters'
          }
        ]
      }
      then: {
        effect: '[parameters(\'effect\')]'
      }
    }
  }
}

// Policy Assignment for HCI Security Compliance
resource policyAssignment 'Microsoft.Authorization/policyAssignments@2022-06-01' = {
  name: '${baseName}-hci-security-assignment'
  properties: {
    displayName: 'HCI Security Compliance'
    description: 'Ensures HCI clusters comply with security baseline'
    policyDefinitionId: policyDefinition.id
    parameters: {
      effect: {
        value: 'Audit'
      }
    }
    enforcementMode: 'Default'
  }
  scope: resourceGroup().id
}

// Action Group for monitoring alerts
resource actionGroup 'Microsoft.Insights/actionGroups@2023-01-01' = {
  name: '${baseName}-alerts-${randomSuffix}'
  location: 'Global'
  tags: resourceTags
  properties: {
    groupShortName: 'EdgeAlerts'
    enabled: true
    emailReceivers: []
    smsReceivers: []
    webhookReceivers: []
    azureAppPushReceivers: []
    itsmReceivers: []
    azureSignalRReceivers: []
    armRoleReceivers: [
      {
        name: 'Monitoring Contributor'
        roleId: '749f88d5-cbae-40b8-bcfc-e573ddc772fa'
        useCommonAlertSchema: true
      }
    ]
  }
}

// Metric Alert for HCI Cluster Health
resource metricAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: '${baseName}-hci-health-alert'
  location: 'Global'
  tags: resourceTags
  properties: {
    description: 'Alert when HCI cluster health is degraded'
    severity: 2
    enabled: true
    scopes: [
      hciCluster.id
    ]
    evaluationFrequency: 'PT5M'
    windowSize: 'PT15M'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'ClusterHealth'
          criterionType: 'StaticThresholdCriterion'
          metricName: 'ClusterHealthStatus'
          metricNamespace: 'Microsoft.AzureStackHCI/clusters'
          operator: 'LessThan'
          threshold: 1
          timeAggregation: 'Average'
        }
      ]
    }
    actions: [
      {
        actionGroupId: actionGroup.id
      }
    ]
  }
}

// Role Assignment for managed identity
resource roleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, 'azure-stack-hci-registration')
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'cd570a14-e51a-42ad-bac8-bafd67325302') // Azure Stack HCI Registration role
    principalId: managedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
  scope: resourceGroup().id
}

// Outputs for integration and verification
@description('Resource group name containing all resources')
output resourceGroupName string = resourceGroup().name

@description('Azure Stack HCI cluster name')
output hciClusterName string = hciCluster.name

@description('Azure Stack HCI cluster resource ID')
output hciClusterResourceId string = hciCluster.id

@description('Log Analytics workspace name for monitoring')
output logAnalyticsWorkspaceName string = logAnalyticsWorkspace.name

@description('Log Analytics workspace ID for agent configuration')
output logAnalyticsWorkspaceId string = logAnalyticsWorkspace.properties.customerId

@description('Storage account name for edge synchronization')
output storageAccountName string = storageAccount.name

@description('Storage account connection string')
output storageConnectionString string = 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};AccountKey=${storageAccount.listKeys().keys[0].value};EndpointSuffix=${environment().suffixes.storage}'

@description('Custom location name for Arc-enabled services')
output customLocationName string = customLocation.name

@description('Custom location resource ID')
output customLocationResourceId string = customLocation.id

@description('Managed identity client ID for authentication')
output managedIdentityClientId string = managedIdentity.properties.clientId

@description('Managed identity principal ID for role assignments')
output managedIdentityPrincipalId string = managedIdentity.properties.principalId

@description('File share name for edge synchronization')
output fileShareName string = fileShare.name

@description('Storage Sync Service name')
output storageSyncServiceName string = storageSyncService.name

@description('Data Collection Rule resource ID')
output dataCollectionRuleId string = dataCollectionRule.id

@description('Application Insights instrumentation key')
output applicationInsightsInstrumentationKey string = applicationInsights.properties.InstrumentationKey

@description('Application Insights connection string')
output applicationInsightsConnectionString string = applicationInsights.properties.ConnectionString