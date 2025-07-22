// main.bicep - Comprehensive Container Monitoring with Azure Container Storage and Managed Prometheus
// This template deploys a comprehensive monitoring solution for stateful containerized workloads

targetScope = 'resourceGroup'

// ============================================================================
// PARAMETERS
// ============================================================================

@description('Location for all resources')
param location string = resourceGroup().location

@description('Unique suffix for resource names')
param uniqueSuffix string = uniqueString(resourceGroup().id)

@description('Environment name (dev, staging, prod)')
@allowed(['dev', 'staging', 'prod'])
param environment string = 'dev'

@description('Project name for resource tagging')
param projectName string = 'stateful-monitoring'

@description('Container Apps Environment name')
param containerAppEnvironmentName string = 'cae-stateful-${uniqueSuffix}'

@description('Container App name for the stateful application')
param containerAppName string = 'ca-stateful-app-${uniqueSuffix}'

@description('Monitoring sidecar container app name')
param monitoringSidecarName string = 'ca-monitoring-sidecar-${uniqueSuffix}'

@description('Storage account name for container storage')
param storageAccountName string = 'st${uniqueSuffix}'

@description('Azure Monitor workspace name')
param monitorWorkspaceName string = 'amw-prometheus-${uniqueSuffix}'

@description('Azure Managed Grafana instance name')
param grafanaInstanceName string = 'grafana-${uniqueSuffix}'

@description('Log Analytics workspace name')
param logAnalyticsWorkspaceName string = 'law-monitoring-${uniqueSuffix}'

@description('PostgreSQL database name')
param postgresDbName string = 'sampledb'

@description('PostgreSQL username')
param postgresUsername string = 'sampleuser'

@description('PostgreSQL password')
@secure()
param postgresPassword string

@description('Container CPU allocation')
param containerCpu string = '1.0'

@description('Container memory allocation')
param containerMemory string = '2.0Gi'

@description('Minimum replica count')
param minReplicas int = 1

@description('Maximum replica count')
param maxReplicas int = 3

@description('Enable monitoring and alerting')
param enableMonitoring bool = true

@description('Storage performance tier')
@allowed(['Standard_LRS', 'Standard_ZRS', 'Premium_LRS'])
param storagePerformanceTier string = 'Premium_LRS'

// ============================================================================
// VARIABLES
// ============================================================================

var commonTags = {
  environment: environment
  project: projectName
  purpose: 'stateful-workload-monitoring'
  'created-by': 'bicep-template'
}

var fileShareName = 'postgresql-data'
var storagePoolName = 'storage-pool-${uniqueSuffix}'

// ============================================================================
// EXISTING RESOURCES
// ============================================================================

// Reference to current resource group for tagging
resource resourceGroup 'Microsoft.Resources/resourceGroups@2023-07-01' existing = {
  scope: subscription()
  name: resourceGroup().name
}

// ============================================================================
// LOG ANALYTICS WORKSPACE
// ============================================================================

resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: logAnalyticsWorkspaceName
  location: location
  tags: commonTags
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

// ============================================================================
// AZURE MONITOR WORKSPACE
// ============================================================================

resource monitorWorkspace 'Microsoft.Monitor/accounts@2023-04-03' = {
  name: monitorWorkspaceName
  location: location
  tags: union(commonTags, {
    service: 'prometheus'
    workload: 'stateful-monitoring'
  })
  properties: {}
}

// ============================================================================
// STORAGE ACCOUNT
// ============================================================================

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: storageAccountName
  location: location
  tags: commonTags
  sku: {
    name: storagePerformanceTier
  }
  kind: 'StorageV2'
  properties: {
    accessTier: 'Hot'
    supportsHttpsTrafficOnly: true
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
    allowSharedKeyAccess: true
    networkAcls: {
      bypass: 'AzureServices'
      defaultAction: 'Allow'
    }
    encryption: {
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
  }
}

// File Services for Azure Container Storage
resource fileServices 'Microsoft.Storage/storageAccounts/fileServices@2023-05-01' = {
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

// File Share for PostgreSQL data
resource fileShare 'Microsoft.Storage/storageAccounts/fileServices/shares@2023-05-01' = {
  parent: fileServices
  name: fileShareName
  properties: {
    shareQuota: 100
    enabledProtocols: 'SMB'
    accessTier: 'Premium'
  }
}

// ============================================================================
// CONTAINER APPS ENVIRONMENT
// ============================================================================

resource containerAppEnvironment 'Microsoft.App/managedEnvironments@2024-03-01' = {
  name: containerAppEnvironmentName
  location: location
  tags: commonTags
  properties: {
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: logAnalyticsWorkspace.properties.customerId
        sharedKey: logAnalyticsWorkspace.listKeys().primarySharedKey
      }
    }
    zoneRedundant: false
    kedaConfiguration: {}
    daprConfiguration: {}
    infrastructureResourceGroup: 'rg-${containerAppEnvironmentName}-infrastructure'
  }
}

// Storage for Container Apps
resource containerAppStorage 'Microsoft.App/managedEnvironments/storages@2024-03-01' = {
  parent: containerAppEnvironment
  name: 'postgresql-storage'
  properties: {
    azureFile: {
      accountName: storageAccount.name
      accountKey: storageAccount.listKeys().keys[0].value
      shareName: fileShare.name
      accessMode: 'ReadWrite'
    }
  }
}

// ============================================================================
// STATEFUL CONTAINER APPLICATION
// ============================================================================

resource statefulContainerApp 'Microsoft.App/containerApps@2024-03-01' = {
  name: containerAppName
  location: location
  tags: union(commonTags, {
    'app-type': 'stateful'
    service: 'postgresql'
  })
  properties: {
    managedEnvironmentId: containerAppEnvironment.id
    configuration: {
      ingress: {
        external: true
        targetPort: 5432
        transport: 'tcp'
        traffic: [
          {
            weight: 100
            latestRevision: true
          }
        ]
      }
      secrets: [
        {
          name: 'postgres-password'
          value: postgresPassword
        }
      ]
      registries: []
    }
    template: {
      containers: [
        {
          name: 'postgresql'
          image: 'postgres:14'
          env: [
            {
              name: 'POSTGRES_DB'
              value: postgresDbName
            }
            {
              name: 'POSTGRES_USER'
              value: postgresUsername
            }
            {
              name: 'POSTGRES_PASSWORD'
              secretRef: 'postgres-password'
            }
            {
              name: 'PGDATA'
              value: '/var/lib/postgresql/data/pgdata'
            }
          ]
          resources: {
            cpu: json(containerCpu)
            memory: containerMemory
          }
          volumeMounts: [
            {
              mountPath: '/var/lib/postgresql/data'
              volumeName: 'data-volume'
            }
          ]
        }
      ]
      scale: {
        minReplicas: minReplicas
        maxReplicas: maxReplicas
        rules: [
          {
            name: 'cpu-scale'
            custom: {
              type: 'cpu'
              metadata: {
                type: 'Utilization'
                value: '80'
              }
            }
          }
        ]
      }
      volumes: [
        {
          name: 'data-volume'
          storageType: 'AzureFile'
          storageName: containerAppStorage.name
        }
      ]
    }
  }
}

// ============================================================================
// MONITORING SIDECAR CONTAINER
// ============================================================================

resource monitoringSidecarApp 'Microsoft.App/containerApps@2024-03-01' = if (enableMonitoring) {
  name: monitoringSidecarName
  location: location
  tags: union(commonTags, {
    'app-type': 'monitoring'
    service: 'node-exporter'
  })
  properties: {
    managedEnvironmentId: containerAppEnvironment.id
    configuration: {
      ingress: {
        external: false
        targetPort: 9100
        transport: 'http'
        traffic: [
          {
            weight: 100
            latestRevision: true
          }
        ]
      }
    }
    template: {
      containers: [
        {
          name: 'node-exporter'
          image: 'prom/node-exporter:latest'
          command: ['/bin/node_exporter']
          args: ['--path.rootfs=/host']
          resources: {
            cpu: 0.25
            memory: '0.5Gi'
          }
          volumeMounts: [
            {
              mountPath: '/host'
              volumeName: 'host-volume'
            }
          ]
        }
      ]
      scale: {
        minReplicas: 1
        maxReplicas: 1
      }
      volumes: [
        {
          name: 'host-volume'
          storageType: 'EmptyDir'
        }
      ]
    }
  }
}

// ============================================================================
// AZURE MANAGED GRAFANA
// ============================================================================

resource grafanaInstance 'Microsoft.Dashboard/grafana@2023-09-01' = if (enableMonitoring) {
  name: grafanaInstanceName
  location: location
  tags: union(commonTags, {
    service: 'grafana'
    monitoring: 'prometheus'
  })
  sku: {
    name: 'Standard'
  }
  properties: {
    zoneRedundancy: 'Disabled'
    apiKey: 'Enabled'
    deterministicOutboundIP: 'Disabled'
    publicNetworkAccess: 'Enabled'
    grafanaIntegrations: {
      azureMonitorWorkspaceIntegrations: [
        {
          azureMonitorWorkspaceResourceId: monitorWorkspace.id
        }
      ]
    }
  }
  identity: {
    type: 'SystemAssigned'
  }
}

// ============================================================================
// ROLE ASSIGNMENTS
// ============================================================================

// Monitoring Reader role for Grafana to access Azure Monitor workspace
resource grafanaMonitoringReaderRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (enableMonitoring) {
  scope: monitorWorkspace
  name: guid(monitorWorkspace.id, grafanaInstance.id, 'MonitoringReader')
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '43d0d8ad-25c7-4714-9337-8ba259a9fe05') // Monitoring Reader
    principalId: enableMonitoring ? grafanaInstance.identity.principalId : ''
    principalType: 'ServicePrincipal'
  }
}

// Storage Account Contributor role for Container Apps to access storage
resource storageContributorRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: storageAccount
  name: guid(storageAccount.id, containerAppEnvironment.id, 'StorageAccountContributor')
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '17d1049b-9a84-46fb-8f53-869881c3d3ab') // Storage Account Contributor
    principalId: containerAppEnvironment.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// ============================================================================
// PROMETHEUS DATA COLLECTION RULES
// ============================================================================

resource prometheusDataCollectionEndpoint 'Microsoft.Insights/dataCollectionEndpoints@2023-03-11' = if (enableMonitoring) {
  name: 'dce-prometheus-${uniqueSuffix}'
  location: location
  tags: commonTags
  properties: {
    networkAcls: {
      publicNetworkAccess: 'Enabled'
    }
  }
}

resource prometheusDataCollectionRule 'Microsoft.Insights/dataCollectionRules@2023-03-11' = if (enableMonitoring) {
  name: 'dcr-prometheus-${uniqueSuffix}'
  location: location
  tags: commonTags
  properties: {
    dataCollectionEndpointId: enableMonitoring ? prometheusDataCollectionEndpoint.id : null
    streamDeclarations: {
      'Microsoft-PrometheusMetrics': {
        columns: [
          {
            name: 'TimeGenerated'
            type: 'datetime'
          }
          {
            name: 'Computer'
            type: 'string'
          }
          {
            name: 'Origin'
            type: 'string'
          }
          {
            name: 'Namespace'
            type: 'string'
          }
          {
            name: 'Pod'
            type: 'string'
          }
          {
            name: 'Container'
            type: 'string'
          }
          {
            name: 'Scrape_url'
            type: 'string'
          }
          {
            name: 'Metric'
            type: 'string'
          }
          {
            name: 'Labels'
            type: 'string'
          }
          {
            name: 'Value'
            type: 'real'
          }
        ]
      }
    }
    dataSources: {
      prometheusForwarder: [
        {
          name: 'PrometheusDataSource'
          streams: ['Microsoft-PrometheusMetrics']
          labelIncludeFilter: {}
        }
      ]
    }
    destinations: {
      monitoringAccounts: [
        {
          accountResourceId: monitorWorkspace.id
          name: 'MonitoringAccount1'
        }
      ]
    }
    dataFlows: [
      {
        streams: ['Microsoft-PrometheusMetrics']
        destinations: ['MonitoringAccount1']
      }
    ]
  }
}

// ============================================================================
// METRIC ALERTS
// ============================================================================

resource storageUtilizationAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = if (enableMonitoring) {
  name: 'storage-pool-utilization-high'
  location: 'global'
  tags: commonTags
  properties: {
    description: 'Storage pool utilization exceeds 80%'
    severity: 2
    enabled: true
    scopes: [
      monitorWorkspace.id
    ]
    evaluationFrequency: 'PT5M'
    windowSize: 'PT15M'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.MultipleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'StorageUtilization'
          metricName: 'storage_pool_capacity_used_bytes'
          metricNamespace: 'prometheus'
          operator: 'GreaterThan'
          threshold: 80
          timeAggregation: 'Average'
        }
      ]
    }
    actions: []
  }
}

resource diskLatencyAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = if (enableMonitoring) {
  name: 'disk-read-latency-high'
  location: 'global'
  tags: commonTags
  properties: {
    description: 'Disk read latency exceeds 100ms'
    severity: 1
    enabled: true
    scopes: [
      monitorWorkspace.id
    ]
    evaluationFrequency: 'PT1M'
    windowSize: 'PT5M'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.MultipleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'DiskLatency'
          metricName: 'disk_read_operations_time_seconds_total'
          metricNamespace: 'prometheus'
          operator: 'GreaterThan'
          threshold: 0.1
          timeAggregation: 'Average'
        }
      ]
    }
    actions: []
  }
}

// ============================================================================
// OUTPUTS
// ============================================================================

@description('Resource Group name')
output resourceGroupName string = resourceGroup().name

@description('Log Analytics Workspace ID')
output logAnalyticsWorkspaceId string = logAnalyticsWorkspace.id

@description('Log Analytics Workspace Customer ID')
output logAnalyticsCustomerId string = logAnalyticsWorkspace.properties.customerId

@description('Azure Monitor Workspace ID')
output monitorWorkspaceId string = monitorWorkspace.id

@description('Azure Monitor Workspace Query Endpoint')
output monitorWorkspaceQueryEndpoint string = monitorWorkspace.properties.defaultIngestionSettings.dataCollectionEndpointResourceId

@description('Container Apps Environment ID')
output containerAppEnvironmentId string = containerAppEnvironment.id

@description('Container Apps Environment FQDN')
output containerAppEnvironmentFqdn string = containerAppEnvironment.properties.defaultDomain

@description('Stateful Container App ID')
output statefulContainerAppId string = statefulContainerApp.id

@description('Stateful Container App FQDN')
output statefulContainerAppFqdn string = statefulContainerApp.properties.configuration.ingress.fqdn

@description('Monitoring Sidecar App ID')
output monitoringSidecarAppId string = enableMonitoring ? monitoringSidecarApp.id : ''

@description('Monitoring Sidecar App FQDN')
output monitoringSidecarAppFqdn string = enableMonitoring ? monitoringSidecarApp.properties.configuration.ingress.fqdn : ''

@description('Storage Account ID')
output storageAccountId string = storageAccount.id

@description('Storage Account Name')
output storageAccountName string = storageAccount.name

@description('File Share Name')
output fileShareName string = fileShare.name

@description('Azure Managed Grafana ID')
output grafanaInstanceId string = enableMonitoring ? grafanaInstance.id : ''

@description('Azure Managed Grafana Endpoint')
output grafanaEndpoint string = enableMonitoring ? grafanaInstance.properties.endpoint : ''

@description('Prometheus Data Collection Rule ID')
output prometheusDataCollectionRuleId string = enableMonitoring ? prometheusDataCollectionRule.id : ''

@description('Storage Utilization Alert ID')
output storageUtilizationAlertId string = enableMonitoring ? storageUtilizationAlert.id : ''

@description('Disk Latency Alert ID')
output diskLatencyAlertId string = enableMonitoring ? diskLatencyAlert.id : ''

@description('Deployment Summary')
output deploymentSummary object = {
  resourceGroup: resourceGroup().name
  location: location
  environment: environment
  containerAppEnvironment: containerAppEnvironmentName
  statefulApp: containerAppName
  monitoringEnabled: enableMonitoring
  storageAccount: storageAccountName
  monitorWorkspace: monitorWorkspaceName
  grafanaInstance: enableMonitoring ? grafanaInstanceName : 'disabled'
  alertsConfigured: enableMonitoring
}