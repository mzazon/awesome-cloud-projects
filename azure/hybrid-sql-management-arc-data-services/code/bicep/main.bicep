@description('Main Bicep template for Azure Arc-enabled SQL Database Management with Azure Monitor')

// Parameters
@description('Location for all resources')
param location string = resourceGroup().location

@description('Base name for all resources')
param baseName string = 'arc-sql-mgmt'

@description('Environment suffix for resource naming')
param environmentSuffix string = uniqueString(resourceGroup().id)

@description('Log Analytics workspace SKU')
@allowed([
  'Free'
  'Standalone'
  'PerNode'
  'PerGB2018'
])
param logAnalyticsWorkspaceSku string = 'PerGB2018'

@description('Log Analytics workspace data retention in days')
@minValue(30)
@maxValue(730)
param logAnalyticsRetentionInDays int = 30

@description('Enable Azure Policy for Arc-enabled resources')
param enableAzurePolicy bool = true

@description('Administrator email for alert notifications')
param adminEmail string

@description('Tags to apply to all resources')
param tags object = {
  Purpose: 'Arc-enabled SQL Database Management'
  Environment: 'Demo'
  Solution: 'Azure Arc Data Services'
}

// Variables
var logAnalyticsWorkspaceName = '${baseName}-law-${environmentSuffix}'
var actionGroupName = '${baseName}-alerts-${environmentSuffix}'
var applicationInsightsName = '${baseName}-ai-${environmentSuffix}'
var managedIdentityName = '${baseName}-mi-${environmentSuffix}'
var keyVaultName = '${baseName}-kv-${environmentSuffix}'
var arcDataControllerName = '${baseName}-dc-${environmentSuffix}'

// User-assigned managed identity for Arc services
resource managedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: managedIdentityName
  location: location
  tags: tags
}

// Key Vault for storing secrets
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
    accessPolicies: [
      {
        tenantId: subscription().tenantId
        objectId: managedIdentity.properties.principalId
        permissions: {
          secrets: [
            'get'
            'list'
            'set'
          ]
        }
      }
    ]
    enabledForDeployment: false
    enabledForDiskEncryption: false
    enabledForTemplateDeployment: true
    enableSoftDelete: true
    softDeleteRetentionInDays: 90
    enableRbacAuthorization: false
    publicNetworkAccess: 'Enabled'
    networkAcls: {
      defaultAction: 'Allow'
      bypass: 'AzureServices'
    }
  }
}

// Store SQL admin password in Key Vault
resource sqlAdminPasswordSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'sql-admin-password'
  properties: {
    value: 'MySecurePassword123!'
    contentType: 'text/plain'
  }
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
    retentionInDays: logAnalyticsRetentionInDays
    features: {
      enableLogAccessUsingOnlyResourcePermissions: true
      disableLocalAuth: false
    }
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

// Application Insights for additional monitoring
resource applicationInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: applicationInsightsName
  location: location
  tags: tags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logAnalyticsWorkspace.id
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

// Action Group for alerts
resource actionGroup 'Microsoft.Insights/actionGroups@2023-01-01' = {
  name: actionGroupName
  location: 'Global'
  tags: tags
  properties: {
    groupShortName: 'arcsql'
    enabled: true
    emailReceivers: [
      {
        name: 'admin'
        emailAddress: adminEmail
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

// Azure Arc Data Controller Custom Location (placeholder for manual creation)
resource arcDataController 'Microsoft.AzureArcData/dataControllers@2023-01-15-preview' = {
  name: arcDataControllerName
  location: location
  tags: tags
  extendedLocation: {
    name: '/subscriptions/${subscription().subscriptionId}/resourceGroups/${resourceGroup().name}/providers/Microsoft.ExtendedLocation/customLocations/${arcDataControllerName}-cl'
    type: 'CustomLocation'
  }
  properties: {
    infrastructure: 'kubernetes'
    basicLoginInformation: {
      username: 'arcadmin'
    }
    logAnalyticsWorkspaceConfig: {
      workspaceId: logAnalyticsWorkspace.properties.customerId
      primaryKey: logAnalyticsWorkspace.listKeys().primarySharedKey
    }
    uploadServicePrincipal: {
      clientId: managedIdentity.properties.clientId
      tenantId: subscription().tenantId
    }
    metricsDashboardCredential: {
      username: 'metricsuser'
    }
    logsRotationPolicy: {
      maxFiles: 20
      maxSizePerFile: 50
    }
    metricsRotationPolicy: {
      maxFiles: 20
      maxSizePerFile: 50
    }
  }
}

// Azure Arc-enabled SQL Managed Instance (placeholder for manual creation)
resource arcSqlManagedInstance 'Microsoft.AzureArcData/sqlManagedInstances@2023-01-15-preview' = {
  name: '${baseName}-sql-mi-${environmentSuffix}'
  location: location
  tags: tags
  extendedLocation: {
    name: '/subscriptions/${subscription().subscriptionId}/resourceGroups/${resourceGroup().name}/providers/Microsoft.ExtendedLocation/customLocations/${arcDataControllerName}-cl'
    type: 'CustomLocation'
  }
  properties: {
    admin: 'arcadmin'
    basicLoginInformation: {
      username: 'arcadmin'
    }
    dataController: {
      id: arcDataController.id
    }
    k8sRaw: {
      spec: {
        dev: true
        tier: 'GeneralPurpose'
        storage: {
          data: {
            volumes: [
              {
                className: 'default'
                size: '5Gi'
              }
            ]
          }
          logs: {
            volumes: [
              {
                className: 'default'
                size: '5Gi'
              }
            ]
          }
        }
        scheduling: {
          default: {
            resources: {
              requests: {
                memory: '2Gi'
                cpu: '2'
              }
              limits: {
                memory: '4Gi'
                cpu: '4'
              }
            }
          }
        }
      }
    }
  }
}

// Azure Policy Assignment for Arc-enabled resources
resource arcSecurityPolicyAssignment 'Microsoft.Authorization/policyAssignments@2024-04-01' = if (enableAzurePolicy) {
  name: 'arc-sql-security-policy'
  properties: {
    displayName: 'Arc SQL Security Policy'
    description: 'Security policy for Arc-enabled SQL resources'
    policyDefinitionId: '/providers/Microsoft.Authorization/policySetDefinitions/89c8a434-18f2-449b-9327-9579c0b9c2f2'
    parameters: {}
    enforcementMode: 'Default'
  }
  location: location
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${managedIdentity.id}': {}
    }
  }
}

// CPU utilization alert for Arc SQL MI
resource cpuUtilizationAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: 'arc-sql-high-cpu'
  location: 'Global'
  tags: tags
  properties: {
    description: 'High CPU usage on Arc SQL MI'
    severity: 2
    enabled: true
    scopes: [
      arcSqlManagedInstance.id
    ]
    evaluationFrequency: 'PT1M'
    windowSize: 'PT5M'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'HighCPU'
          metricName: 'Percentage CPU'
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

// Storage utilization alert for Arc SQL MI
resource storageUtilizationAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: 'arc-sql-low-storage'
  location: 'Global'
  tags: tags
  properties: {
    description: 'Low storage space on Arc SQL MI'
    severity: 1
    enabled: true
    scopes: [
      arcSqlManagedInstance.id
    ]
    evaluationFrequency: 'PT1M'
    windowSize: 'PT5M'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'LowStorage'
          metricName: 'Storage percent'
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

// Azure Monitor Workbook for Arc SQL monitoring
resource monitoringWorkbook 'Microsoft.Insights/workbooks@2023-06-01' = {
  name: guid(resourceGroup().id, 'arc-sql-monitoring-workbook')
  location: location
  tags: tags
  kind: 'shared'
  properties: {
    displayName: 'Arc SQL Monitoring Dashboard'
    description: 'Comprehensive monitoring dashboard for Azure Arc-enabled SQL Managed Instance'
    serializedData: '{"version":"Notebook/1.0","items":[{"type":1,"content":{"json":"# Azure Arc SQL Managed Instance Monitoring Dashboard\\n\\nThis dashboard provides comprehensive monitoring for Azure Arc-enabled SQL Managed Instance deployments."}},{"type":3,"content":{"version":"KqlItem/1.0","query":"Perf\\n| where CounterName == \\"Processor(_Total)\\\\\\\\% Processor Time\\"\\n| summarize avg(CounterValue) by bin(TimeGenerated, 5m)\\n| render timechart","size":0,"title":"CPU Utilization","queryType":0,"resourceType":"microsoft.operationalinsights/workspaces","visualization":"timechart"}},{"type":3,"content":{"version":"KqlItem/1.0","query":"Perf\\n| where CounterName == \\"Memory\\\\\\\\Available MBytes\\"\\n| summarize avg(CounterValue) by bin(TimeGenerated, 5m)\\n| render timechart","size":0,"title":"Memory Usage","queryType":0,"resourceType":"microsoft.operationalinsights/workspaces","visualization":"timechart"}},{"type":3,"content":{"version":"KqlItem/1.0","query":"AzureDiagnostics\\n| where ResourceType == \\"AZUREARC/SQLMANAGEDINSTANCES\\"\\n| summarize count() by bin(TimeGenerated, 1h)\\n| render timechart","size":0,"title":"Database Activity","queryType":0,"resourceType":"microsoft.operationalinsights/workspaces","visualization":"timechart"}}]}'
    sourceId: logAnalyticsWorkspace.id
    category: 'workbook'
  }
}

// Role assignment for managed identity to access Arc resources
resource arcContributorRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, managedIdentity.id, 'AzureArcEnabledSQLContributor')
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b1ff04bb-8a4e-4dc4-8eb5-8693973ce19b') // Azure Arc ScVmm Administrator
    principalId: managedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

// Role assignment for Log Analytics Contributor
resource logAnalyticsContributorRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, managedIdentity.id, 'LogAnalyticsContributor')
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '92aaf0da-9dab-42b6-94a3-d43ce8d16293') // Log Analytics Contributor
    principalId: managedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

// Outputs
@description('Resource Group Name')
output resourceGroupName string = resourceGroup().name

@description('Log Analytics Workspace Name')
output logAnalyticsWorkspaceName string = logAnalyticsWorkspace.name

@description('Log Analytics Workspace ID')
output logAnalyticsWorkspaceId string = logAnalyticsWorkspace.properties.customerId

@description('Log Analytics Workspace Resource ID')
output logAnalyticsWorkspaceResourceId string = logAnalyticsWorkspace.id

@description('Application Insights Name')
output applicationInsightsName string = applicationInsights.name

@description('Application Insights Instrumentation Key')
output applicationInsightsInstrumentationKey string = applicationInsights.properties.InstrumentationKey

@description('Key Vault Name')
output keyVaultName string = keyVault.name

@description('Key Vault URI')
output keyVaultUri string = keyVault.properties.vaultUri

@description('Managed Identity Client ID')
output managedIdentityClientId string = managedIdentity.properties.clientId

@description('Managed Identity Principal ID')
output managedIdentityPrincipalId string = managedIdentity.properties.principalId

@description('Arc Data Controller Name')
output arcDataControllerName string = arcDataController.name

@description('Arc SQL Managed Instance Name')
output arcSqlManagedInstanceName string = arcSqlManagedInstance.name

@description('Action Group Name')
output actionGroupName string = actionGroup.name

@description('Monitoring Workbook Name')
output monitoringWorkbookName string = monitoringWorkbook.name

@description('Deployment Configuration')
output deploymentConfiguration object = {
  location: location
  environmentSuffix: environmentSuffix
  logAnalyticsWorkspaceName: logAnalyticsWorkspaceName
  arcDataControllerName: arcDataControllerName
  sqlManagedInstanceName: arcSqlManagedInstance.name
  keyVaultName: keyVaultName
  managedIdentityName: managedIdentityName
}