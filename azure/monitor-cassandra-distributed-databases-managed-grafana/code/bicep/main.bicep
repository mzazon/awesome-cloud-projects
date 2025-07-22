// Bicep template for Monitor Distributed Cassandra Databases with Managed Grafana
// This template deploys a complete monitoring solution including:
// - Azure Virtual Network with dedicated subnet
// - Azure Managed Instance for Apache Cassandra cluster
// - Azure Managed Grafana instance
// - Log Analytics workspace for diagnostics
// - Azure Monitor alert rules and action groups

@description('Primary Azure region for all resources')
param location string = resourceGroup().location

@description('Base name for all resources - will be suffixed with unique identifiers')
param baseName string

@description('Environment name (dev, staging, prod)')
@allowed([
  'dev'
  'staging'
  'prod'
])
param environment string = 'dev'

@description('Cassandra cluster initial admin password')
@secure()
param cassandraAdminPassword string

@description('Number of nodes in the Cassandra data center')
@minValue(1)
@maxValue(10)
param cassandraNodeCount int = 3

@description('VM SKU for Cassandra nodes')
@allowed([
  'Standard_DS13_v2'
  'Standard_DS14_v2'
  'Standard_E16s_v3'
  'Standard_E32s_v3'
])
param cassandraNodeSku string = 'Standard_DS14_v2'

@description('Cassandra version to deploy')
@allowed([
  '3.11'
  '4.0'
])
param cassandraVersion string = '4.0'

@description('Azure Managed Grafana SKU')
@allowed([
  'Standard'
  'Essential'
])
param grafanaSku string = 'Standard'

@description('Email address for alert notifications')
param alertEmailAddress string

@description('Tags to apply to all resources')
param tags object = {
  Environment: environment
  Purpose: 'NoSQL Database Monitoring'
  Recipe: 'monitoring-distributed-nosql-databases'
}

// Variables for resource naming
var uniqueSuffix = substring(uniqueString(resourceGroup().id), 0, 6)
var vnetName = '${baseName}-vnet-${uniqueSuffix}'
var cassandraClusterName = '${baseName}-cassandra-${uniqueSuffix}'
var grafanaName = '${baseName}-grafana-${uniqueSuffix}'
var workspaceName = '${baseName}-law-${uniqueSuffix}'
var actionGroupName = '${baseName}-alerts-${uniqueSuffix}'

// Virtual Network for Cassandra cluster
resource virtualNetwork 'Microsoft.Network/virtualNetworks@2023-05-01' = {
  name: vnetName
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.0.0.0/16'
      ]
    }
    subnets: [
      {
        name: 'cassandra-subnet'
        properties: {
          addressPrefix: '10.0.1.0/24'
          delegations: [
            {
              name: 'Microsoft.DocumentDB/cassandraClusters'
              properties: {
                serviceName: 'Microsoft.DocumentDB/cassandraClusters'
              }
            }
          ]
        }
      }
    ]
  }
}

// Log Analytics workspace for diagnostics and monitoring
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2022-10-01' = {
  name: workspaceName
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

// Azure Managed Instance for Apache Cassandra cluster
resource cassandraCluster 'Microsoft.DocumentDB/cassandraClusters@2023-04-15' = {
  name: cassandraClusterName
  location: location
  tags: tags
  properties: {
    delegatedManagementSubnetId: virtualNetwork.properties.subnets[0].id
    cassandraVersion: cassandraVersion
    clientCertificates: []
    initialCassandraAdminPassword: cassandraAdminPassword
    authenticationMethod: 'Cassandra'
    hoursBetweenBackups: 24
    deallocated: false
    cassandraAuditLoggingEnabled: true
  }
}

// Cassandra data center with specified node configuration
resource cassandraDataCenter 'Microsoft.DocumentDB/cassandraClusters/dataCenters@2023-04-15' = {
  parent: cassandraCluster
  name: 'dc1'
  properties: {
    dataCenterLocation: location
    delegatedSubnetId: virtualNetwork.properties.subnets[0].id
    nodeCount: cassandraNodeCount
    sku: cassandraNodeSku
    diskSku: 'P30'
    diskCapacity: 4
    availabilityZone: false
    authenticationMethodLdapProperties: null
  }
}

// Diagnostic settings for Cassandra cluster
resource cassandraDiagnosticSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'cassandra-diagnostics'
  scope: cassandraCluster
  properties: {
    workspaceId: logAnalyticsWorkspace.id
    logs: [
      {
        categoryGroup: 'allLogs'
        enabled: true
        retentionPolicy: {
          enabled: false
          days: 0
        }
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
        retentionPolicy: {
          enabled: false
          days: 0
        }
      }
    ]
  }
}

// Azure Managed Grafana instance
resource grafanaInstance 'Microsoft.Dashboard/grafana@2023-09-01' = {
  name: grafanaName
  location: location
  tags: tags
  sku: {
    name: grafanaSku
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    zoneRedundancy: 'Disabled'
    apiKey: 'Enabled'
    deterministicOutboundIP: 'Disabled'
    publicNetworkAccess: 'Enabled'
    grafanaIntegrations: {
      azureMonitorWorkspaceIntegrations: [
        {
          azureMonitorWorkspaceResourceId: logAnalyticsWorkspace.id
        }
      ]
    }
  }
}

// Role assignment for Grafana to read monitoring data
resource grafanaMonitoringReaderRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, grafanaInstance.id, 'Monitoring Reader')
  scope: resourceGroup()
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '43d0d8ad-25c7-4714-9337-8ba259a9fe05') // Monitoring Reader
    principalId: grafanaInstance.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Action group for alert notifications
resource actionGroup 'Microsoft.Insights/actionGroups@2023-01-01' = {
  name: actionGroupName
  location: 'Global'
  tags: tags
  properties: {
    groupShortName: 'CassAlert'
    enabled: true
    emailReceivers: [
      {
        name: 'ops-team'
        emailAddress: alertEmailAddress
        useCommonAlertSchema: true
      }
    ]
    smsReceivers: []
    webhookReceivers: []
    armRoleReceivers: []
    azureFunctionReceivers: []
    logicAppReceivers: []
    azureAppPushReceivers: []
    itsmReceivers: []
    automationRunbookReceivers: []
    voiceReceivers: []
    eventHubReceivers: []
  }
}

// Metric alert for high CPU usage
resource cpuAlertRule 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: '${cassandraClusterName}-high-cpu'
  location: 'Global'
  tags: tags
  properties: {
    description: 'Alert when Cassandra cluster CPU usage exceeds 80%'
    severity: 2
    enabled: true
    scopes: [
      cassandraCluster.id
    ]
    evaluationFrequency: 'PT1M'
    windowSize: 'PT5M'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'CPU Usage'
          metricName: 'CpuUsage'
          metricNamespace: 'Microsoft.DocumentDB/cassandraClusters'
          operator: 'GreaterThan'
          threshold: 80
          timeAggregation: 'Average'
          criterionType: 'StaticThresholdCriterion'
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

// Metric alert for high memory usage
resource memoryAlertRule 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: '${cassandraClusterName}-high-memory'
  location: 'Global'
  tags: tags
  properties: {
    description: 'Alert when Cassandra cluster memory usage exceeds 85%'
    severity: 2
    enabled: true
    scopes: [
      cassandraCluster.id
    ]
    evaluationFrequency: 'PT1M'
    windowSize: 'PT5M'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'Memory Usage'
          metricName: 'MemoryUsage'
          metricNamespace: 'Microsoft.DocumentDB/cassandraClusters'
          operator: 'GreaterThan'
          threshold: 85
          timeAggregation: 'Average'
          criterionType: 'StaticThresholdCriterion'
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

// Metric alert for connection failures
resource connectionAlertRule 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: '${cassandraClusterName}-connection-failures'
  location: 'Global'
  tags: tags
  properties: {
    description: 'Alert when Cassandra cluster connection failures exceed threshold'
    severity: 1
    enabled: true
    scopes: [
      cassandraCluster.id
    ]
    evaluationFrequency: 'PT1M'
    windowSize: 'PT5M'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'Connection Failures'
          metricName: 'ConnectionErrors'
          metricNamespace: 'Microsoft.DocumentDB/cassandraClusters'
          operator: 'GreaterThan'
          threshold: 5
          timeAggregation: 'Total'
          criterionType: 'StaticThresholdCriterion'
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

// Outputs for reference and validation
@description('Resource group name')
output resourceGroupName string = resourceGroup().name

@description('Virtual network name')
output virtualNetworkName string = virtualNetwork.name

@description('Cassandra cluster name')
output cassandraClusterName string = cassandraCluster.name

@description('Cassandra cluster resource ID')
output cassandraClusterResourceId string = cassandraCluster.id

@description('Cassandra cluster seed nodes')
output cassandraSeedNodes array = cassandraCluster.properties.seedNodes

@description('Grafana instance name')
output grafanaInstanceName string = grafanaInstance.name

@description('Grafana endpoint URL')
output grafanaEndpoint string = grafanaInstance.properties.endpoint

@description('Log Analytics workspace name')
output logAnalyticsWorkspaceName string = logAnalyticsWorkspace.name

@description('Log Analytics workspace ID')
output logAnalyticsWorkspaceId string = logAnalyticsWorkspace.id

@description('Action group name for alerts')
output actionGroupName string = actionGroup.name

@description('Deployment summary')
output deploymentSummary object = {
  cassandraCluster: cassandraCluster.name
  nodeCount: cassandraNodeCount
  grafanaEndpoint: grafanaInstance.properties.endpoint
  monitoringEnabled: true
  alertsConfigured: true
}