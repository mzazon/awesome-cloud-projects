@description('The name of the resource group where resources will be deployed')
param resourceGroupName string = 'rg-mlops-pipeline'

@description('The Azure region where resources will be deployed')
param location string = resourceGroup().location

@description('The name of the Azure Machine Learning workspace')
param mlWorkspaceName string = 'mlw-mlops-demo'

@description('The name of the Azure Kubernetes Service cluster')
param aksClusterName string = 'aks-mlops-cluster'

@description('The name of the Azure Container Registry')
param acrName string = 'acrmlops${uniqueString(resourceGroup().id)}'

@description('The name of the Azure Key Vault')
param keyVaultName string = 'kv-mlops-${uniqueString(resourceGroup().id)}'

@description('The name of the storage account for ML workspace')
param storageAccountName string = 'stmlops${uniqueString(resourceGroup().id)}'

@description('The name of the diagnostic storage account')
param diagStorageAccountName string = 'diagstmlops${uniqueString(resourceGroup().id)}'

@description('The name of the Log Analytics workspace')
param logAnalyticsWorkspaceName string = 'mlops-logs'

@description('The name of the Application Insights component')
param appInsightsName string = 'mlops-insights'

@description('The minimum number of nodes for the system node pool')
@minValue(1)
@maxValue(10)
param systemNodePoolMinCount int = 2

@description('The maximum number of nodes for the system node pool')
@minValue(1)
@maxValue(50)
param systemNodePoolMaxCount int = 5

@description('The minimum number of nodes for the ML node pool')
@minValue(1)
@maxValue(10)
param mlNodePoolMinCount int = 1

@description('The maximum number of nodes for the ML node pool')
@minValue(1)
@maxValue(50)
param mlNodePoolMaxCount int = 4

@description('The VM size for the system node pool')
param systemNodePoolVmSize string = 'Standard_DS3_v2'

@description('The VM size for the ML node pool')
param mlNodePoolVmSize string = 'Standard_DS3_v2'

@description('Tags to be applied to all resources')
param tags object = {
  purpose: 'mlops'
  environment: 'demo'
  project: 'mlops-pipeline'
}

// Storage Account for ML Workspace
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: storageAccountName
  location: location
  tags: tags
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
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
      keySource: 'Microsoft.Storage'
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
    }
    accessTier: 'Hot'
  }
}

// Diagnostic Storage Account
resource diagStorageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: diagStorageAccountName
  location: location
  tags: tags
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
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
      keySource: 'Microsoft.Storage'
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
    }
    accessTier: 'Hot'
  }
}

// Azure Container Registry
resource containerRegistry 'Microsoft.ContainerRegistry/registries@2023-07-01' = {
  name: acrName
  location: location
  tags: tags
  sku: {
    name: 'Standard'
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
      exportPolicy: {
        status: 'enabled'
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

// Key Vault
resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: keyVaultName
  location: location
  tags: tags
  properties: {
    sku: {
      family: 'A'
      name: 'standard'
    }
    tenantId: subscription().tenantId
    accessPolicies: []
    enabledForDeployment: false
    enabledForDiskEncryption: false
    enabledForTemplateDeployment: false
    enableSoftDelete: true
    softDeleteRetentionInDays: 90
    enableRbacAuthorization: true
    vaultUri: 'https://${keyVaultName}.vault.azure.net/'
    provisioningState: 'Succeeded'
    publicNetworkAccess: 'Enabled'
  }
}

// Log Analytics Workspace
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
      searchVersion: 1
      legacy: 0
      enableLogAccessUsingOnlyResourcePermissions: true
    }
    workspaceCapping: {
      dailyQuotaGb: -1
    }
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

// Application Insights
resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: appInsightsName
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

// Azure Kubernetes Service
resource aksCluster 'Microsoft.ContainerService/managedClusters@2023-11-02-preview' = {
  name: aksClusterName
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    kubernetesVersion: '1.28'
    dnsPrefix: '${aksClusterName}dns'
    fqdn: '${aksClusterName}dns-${uniqueString(resourceGroup().id)}.hcp.${location}.azmk8s.io'
    agentPoolProfiles: [
      {
        name: 'systempool'
        osDiskSizeGB: 128
        count: systemNodePoolMinCount
        enableAutoScaling: true
        minCount: systemNodePoolMinCount
        maxCount: systemNodePoolMaxCount
        vmSize: systemNodePoolVmSize
        osType: 'Linux'
        osSKU: 'Ubuntu'
        type: 'VirtualMachineScaleSets'
        mode: 'System'
        orchestratorVersion: '1.28'
        enableNodePublicIP: false
        maxPods: 110
        availabilityZones: [
          '1'
          '2'
          '3'
        ]
        enableEncryptionAtHost: false
        enableUltraSSD: false
        enableFIPS: false
        kubeletDiskType: 'OS'
        workloadRuntime: 'OCIContainer'
        messageThroughput: 'Standard'
        upgradeSettings: {
          maxSurge: '10%'
          drainTimeoutInMinutes: 30
        }
        powerState: {
          code: 'Running'
        }
      }
      {
        name: 'mlpool'
        osDiskSizeGB: 128
        count: mlNodePoolMinCount
        enableAutoScaling: true
        minCount: mlNodePoolMinCount
        maxCount: mlNodePoolMaxCount
        vmSize: mlNodePoolVmSize
        osType: 'Linux'
        osSKU: 'Ubuntu'
        type: 'VirtualMachineScaleSets'
        mode: 'User'
        orchestratorVersion: '1.28'
        enableNodePublicIP: false
        maxPods: 110
        availabilityZones: [
          '1'
          '2'
          '3'
        ]
        enableEncryptionAtHost: false
        enableUltraSSD: false
        enableFIPS: false
        kubeletDiskType: 'OS'
        workloadRuntime: 'OCIContainer'
        messageThroughput: 'Standard'
        taints: [
          'workload=ml:NoSchedule'
        ]
        upgradeSettings: {
          maxSurge: '10%'
          drainTimeoutInMinutes: 30
        }
        powerState: {
          code: 'Running'
        }
      }
    ]
    linuxProfile: {
      adminUsername: 'azureuser'
      ssh: {
        publicKeys: [
          {
            keyData: 'ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQDCsu/iXpUWJHwJ5YJN8J5lzEJCOvmJcKdLcQGI6gWGpBgKJpXQKjbAIcRkqAoP/wuYuHEqfTj2r6EZEeKNQiZyJcgJlxfJn1EJIGBSKPDHvQNHGJ'
          }
        ]
      }
    }
    servicePrincipalProfile: {
      clientId: 'msi'
    }
    nodeResourceGroup: 'MC_${resourceGroupName}_${aksClusterName}_${location}'
    enableRBAC: true
    enablePodSecurityPolicy: false
    supportPlan: 'KubernetesOfficial'
    networkProfile: {
      networkPlugin: 'azure'
      networkPolicy: 'calico'
      networkMode: 'transparent'
      podCidr: '10.244.0.0/16'
      serviceCidr: '10.0.0.0/16'
      dnsServiceIP: '10.0.0.10'
      dockerBridgeCidr: '172.17.0.1/16'
      outboundType: 'loadBalancer'
      loadBalancerSku: 'Standard'
      loadBalancerProfile: {
        managedOutboundIPs: {
          count: 1
        }
        effectiveOutboundIPs: []
      }
    }
    aadProfile: {
      managed: true
      enableAzureRBAC: true
    }
    autoUpgradeProfile: {
      upgradeChannel: 'patch'
      nodeOSUpgradeChannel: 'NodeImage'
    }
    disableLocalAccounts: false
    securityProfile: {
      workloadIdentity: {
        enabled: true
      }
      imageCleaner: {
        enabled: true
        intervalHours: 24
      }
    }
    storageProfile: {
      diskCSIDriver: {
        enabled: true
        version: 'v1'
      }
      fileCSIDriver: {
        enabled: true
      }
      snapshotController: {
        enabled: true
      }
    }
    oidcIssuerProfile: {
      enabled: true
    }
    podIdentityProfile: {
      enabled: false
    }
    privateLinkResources: []
    apiServerAccessProfile: {
      enablePrivateCluster: false
    }
  }
}

// ACR role assignment for AKS
resource acrPullRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(aksCluster.id, containerRegistry.id, 'AcrPull')
  scope: containerRegistry
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '7f951dda-4ed3-4680-a7ca-43fe172d538d')
    principalId: aksCluster.properties.identityProfile.kubeletidentity.objectId
    principalType: 'ServicePrincipal'
  }
}

// Azure Machine Learning Workspace
resource mlWorkspace 'Microsoft.MachineLearningServices/workspaces@2023-10-01' = {
  name: mlWorkspaceName
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    friendlyName: mlWorkspaceName
    storageAccount: storageAccount.id
    keyVault: keyVault.id
    applicationInsights: appInsights.id
    containerRegistry: containerRegistry.id
    hbiWorkspace: false
    allowPublicAccessWhenBehindVnet: false
    discoveryUrl: 'https://${location}.api.azureml.ms/discovery'
    publicNetworkAccess: 'Enabled'
    imageBuildCompute: null
    primaryUserAssignedIdentity: null
    systemDatastoresAuthMode: 'accessKey'
    workspaceHubConfig: null
    managedNetwork: {
      isolationMode: 'Disabled'
    }
    featureStoreSettings: {
      computeRuntime: null
      offlineStoreConnectionName: null
      onlineStoreConnectionName: null
    }
    encryption: {
      status: 'Disabled'
      keyVaultProperties: {
        keyVaultArmId: ''
        keyIdentifier: ''
      }
    }
    serverlessComputeSettings: null
    v1LegacyMode: false
  }
}

// ML extension for AKS (this requires the cluster to be created first)
resource mlExtension 'Microsoft.KubernetesConfiguration/extensions@2023-05-01' = {
  name: 'ml-extension'
  scope: aksCluster
  properties: {
    extensionType: 'Microsoft.AzureML.Kubernetes'
    autoUpgradeMinorVersion: true
    releaseTrain: 'Stable'
    scope: {
      cluster: {
        releaseNamespace: 'azureml'
      }
    }
    configurationSettings: {
      enableTraining: 'True'
      enableInference: 'True'
      allowInsecureConnections: 'True'
      inferenceRouterServiceType: 'LoadBalancer'
      installNvidiaDevicePlugin: 'False'
      logLevel: 'INFO'
      nginxIngress: 'False'
      rbacEnabled: 'True'
      sslCname: ''
      sslSecret: ''
      storageClass: 'default'
      clusterId: aksCluster.id
    }
    configurationProtectedSettings: {}
  }
}

// Diagnostic settings for AKS
resource aksDiagnosticSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'aks-diagnostics'
  scope: aksCluster
  properties: {
    workspaceId: logAnalyticsWorkspace.id
    logs: [
      {
        category: 'kube-apiserver'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: 30
        }
      }
      {
        category: 'kube-controller-manager'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: 30
        }
      }
      {
        category: 'kube-scheduler'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: 30
        }
      }
      {
        category: 'cluster-autoscaler'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: 30
        }
      }
      {
        category: 'kube-audit'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: 30
        }
      }
      {
        category: 'kube-audit-admin'
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

// Action Group for alerts
resource actionGroup 'Microsoft.Insights/actionGroups@2023-01-01' = {
  name: '${resourceGroupName}-action-group'
  location: 'Global'
  tags: tags
  properties: {
    groupShortName: 'MLOpsAlert'
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
    eventHubReceivers: []
    itsmReceivers: []
    azureAppPushReceivers: []
    automationRunbookReceivers: []
    voiceReceivers: []
    logicAppReceivers: []
    azureFunctionReceivers: []
    armRoleReceivers: []
  }
}

// High latency alert
resource highLatencyAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: 'high-latency-alert'
  location: 'Global'
  tags: tags
  properties: {
    description: 'Alert when average response time is greater than 1000ms'
    severity: 2
    enabled: true
    scopes: [
      aksCluster.id
    ]
    evaluationFrequency: 'PT1M'
    windowSize: 'PT5M'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.MultipleResourceMultipleMetricCriteria'
      allOf: [
        {
          threshold: 1000
          name: 'Metric1'
          metricNamespace: 'Microsoft.ContainerService/managedClusters'
          metricName: 'node_cpu_usage_percentage'
          operator: 'GreaterThan'
          timeAggregation: 'Average'
          criterionType: 'StaticThresholdCriterion'
        }
      ]
    }
    autoMitigate: false
    actions: [
      {
        actionGroupId: actionGroup.id
        webHookProperties: {}
      }
    ]
  }
}

// Outputs
output resourceGroupName string = resourceGroupName
output mlWorkspaceName string = mlWorkspace.name
output mlWorkspaceId string = mlWorkspace.id
output aksClusterName string = aksCluster.name
output aksClusterId string = aksCluster.id
output aksFqdn string = aksCluster.properties.fqdn
output acrName string = containerRegistry.name
output acrLoginServer string = containerRegistry.properties.loginServer
output keyVaultName string = keyVault.name
output keyVaultUri string = keyVault.properties.vaultUri
output storageAccountName string = storageAccount.name
output logAnalyticsWorkspaceName string = logAnalyticsWorkspace.name
output logAnalyticsWorkspaceId string = logAnalyticsWorkspace.id
output appInsightsName string = appInsights.name
output appInsightsId string = appInsights.id
output appInsightsInstrumentationKey string = appInsights.properties.InstrumentationKey
output appInsightsConnectionString string = appInsights.properties.ConnectionString