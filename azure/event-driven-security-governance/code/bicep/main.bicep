@description('The name of the resource group. This will be used as a prefix for all resources.')
param resourceGroupName string = 'rg-security-governance'

@description('The Azure region where resources will be deployed.')
param location string = resourceGroup().location

@description('A unique suffix to ensure resource names are globally unique.')
param uniqueSuffix string = uniqueString(resourceGroup().id)

@description('The name of the Event Grid topic for security events.')
param eventGridTopicName string = 'eg-security-governance-${uniqueSuffix}'

@description('The name of the Function App for security processing.')
param functionAppName string = 'func-security-${uniqueSuffix}'

@description('The name of the storage account for Function App.')
param storageAccountName string = 'stsecurity${uniqueSuffix}'

@description('The name of the Log Analytics workspace.')
param logAnalyticsWorkspaceName string = 'law-security-${uniqueSuffix}'

@description('The name of the Application Insights component.')
param appInsightsName string = 'appi-security-${uniqueSuffix}'

@description('The name of the Action Group for alerts.')
param actionGroupName string = 'ag-security-${uniqueSuffix}'

@description('Email address for security alert notifications.')
param alertEmailAddress string

@description('Tags to apply to all resources.')
param tags object = {
  purpose: 'security-governance'
  environment: 'demo'
  owner: 'admin'
  compliance: 'required'
}

// Variables
var storageAccountNameCleaned = take(replace(storageAccountName, '-', ''), 24)
var functionAppServicePlanName = 'asp-${functionAppName}'

// Log Analytics Workspace
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: logAnalyticsWorkspaceName
  location: location
  tags: union(tags, {
    purpose: 'compliance-monitoring'
  })
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

// Application Insights
resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: appInsightsName
  location: location
  kind: 'web'
  tags: tags
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logAnalyticsWorkspace.id
  }
}

// Storage Account for Function App
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: storageAccountNameCleaned
  location: location
  tags: union(tags, {
    purpose: 'function-storage'
  })
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    accessTier: 'Hot'
    allowBlobPublicAccess: false
    allowSharedKeyAccess: true
    supportsHttpsTrafficOnly: true
    minimumTlsVersion: 'TLS1_2'
  }
}

// Function App Service Plan (Consumption)
resource functionAppServicePlan 'Microsoft.Web/serverfarms@2023-12-01' = {
  name: functionAppServicePlanName
  location: location
  tags: tags
  sku: {
    name: 'Y1'
    tier: 'Dynamic'
  }
  properties: {
    reserved: true // Required for Linux
  }
}

// Function App with System-Assigned Managed Identity
resource functionApp 'Microsoft.Web/sites@2023-12-01' = {
  name: functionAppName
  location: location
  tags: union(tags, {
    purpose: 'security-automation'
  })
  kind: 'functionapp,linux'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: functionAppServicePlan.id
    siteConfig: {
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
          value: 'python'
        }
        {
          name: 'APPINSIGHTS_INSTRUMENTATIONKEY'
          value: appInsights.properties.InstrumentationKey
        }
        {
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: appInsights.properties.ConnectionString
        }
        {
          name: 'EventGridTopicEndpoint'
          value: eventGridTopic.properties.endpoint
        }
        {
          name: 'EventGridTopicKey'
          value: eventGridTopic.listKeys().key1
        }
        {
          name: 'LogAnalyticsWorkspaceId'
          value: logAnalyticsWorkspace.properties.customerId
        }
        {
          name: 'AzureWebJobsFeatureFlags'
          value: 'EnableWorkerIndexing'
        }
      ]
      linuxFxVersion: 'Python|3.9'
      use32BitWorkerProcess: false
      ftpsState: 'Disabled'
      minTlsVersion: '1.2'
    }
    httpsOnly: true
  }
}

// Event Grid Topic
resource eventGridTopic 'Microsoft.EventGrid/topics@2023-12-15-preview' = {
  name: eventGridTopicName
  location: location
  tags: union(tags, {
    purpose: 'security-events'
  })
  properties: {
    inputSchema: 'EventGridSchema'
  }
}

// Event Grid Subscription
resource eventGridSubscription 'Microsoft.EventGrid/eventSubscriptions@2023-12-15-preview' = {
  name: 'security-governance-subscription'
  scope: resourceGroup()
  properties: {
    destination: {
      endpointType: 'AzureFunction'
      properties: {
        resourceId: '${functionApp.id}/functions/SecurityEventProcessor'
        maxEventsPerBatch: 1
        preferredBatchSizeInKilobytes: 64
      }
    }
    filter: {
      includedEventTypes: [
        'Microsoft.Resources.ResourceWriteSuccess'
        'Microsoft.Resources.ResourceDeleteSuccess'
        'Microsoft.Resources.ResourceActionSuccess'
      ]
      advancedFilters: [
        {
          operatorType: 'StringBeginsWith'
          key: 'data.operationName'
          values: [
            'Microsoft.Compute/virtualMachines'
            'Microsoft.Network/networkSecurityGroups'
            'Microsoft.Storage/storageAccounts'
          ]
        }
      ]
    }
    retryPolicy: {
      maxDeliveryAttempts: 3
      eventTimeToLiveInMinutes: 1440
    }
  }
  dependsOn: [
    functionApp
  ]
}

// Action Group for Alerts
resource actionGroup 'Microsoft.Insights/actionGroups@2023-01-01' = {
  name: actionGroupName
  location: 'Global'
  tags: tags
  properties: {
    groupShortName: 'SecAlert'
    enabled: true
    emailReceivers: [
      {
        name: 'SecurityTeam'
        emailAddress: alertEmailAddress
        useCommonAlertSchema: true
      }
    ]
  }
}

// Alert Rule for Security Violations
resource securityViolationAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: 'SecurityViolationAlert'
  location: 'Global'
  tags: tags
  properties: {
    description: 'Alert when security violations exceed threshold'
    severity: 2
    enabled: true
    scopes: [
      functionApp.id
    ]
    evaluationFrequency: 'PT1M'
    windowSize: 'PT5M'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'FunctionExecutionCount'
          metricName: 'FunctionExecutionCount'
          operator: 'GreaterThan'
          threshold: 5
          timeAggregation: 'Count'
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

// Alert Rule for Function Failures
resource functionFailureAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: 'SecurityFunctionFailureAlert'
  location: 'Global'
  tags: tags
  properties: {
    description: 'Alert when security function executions fail'
    severity: 1
    enabled: true
    scopes: [
      functionApp.id
    ]
    evaluationFrequency: 'PT1M'
    windowSize: 'PT5M'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'FunctionExecutionFailures'
          metricName: 'FunctionExecutionFailures'
          operator: 'GreaterThan'
          threshold: 0
          timeAggregation: 'Count'
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

// RBAC Role Assignments for Function App Managed Identity
resource securityReaderRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, functionApp.id, 'SecurityReader')
  scope: resourceGroup()
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '39bc4728-0917-49c7-9d2c-d95423bc2eb4') // Security Reader
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

resource contributorRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, functionApp.id, 'Contributor')
  scope: resourceGroup()
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b24988ac-6180-42a0-ab88-20f7382dd24c') // Contributor
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

resource monitoringContributorRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, functionApp.id, 'MonitoringContributor')
  scope: resourceGroup()
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '749f88d5-cbae-40b8-bcfc-e573ddc772fa') // Monitoring Contributor
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Outputs
@description('The name of the deployed resource group.')
output resourceGroupName string = resourceGroup().name

@description('The endpoint URL of the Event Grid topic.')
output eventGridTopicEndpoint string = eventGridTopic.properties.endpoint

@description('The name of the Function App.')
output functionAppName string = functionApp.name

@description('The URL of the Function App.')
output functionAppUrl string = 'https://${functionApp.properties.defaultHostName}'

@description('The principal ID of the Function App managed identity.')
output functionAppPrincipalId string = functionApp.identity.principalId

@description('The ID of the Log Analytics workspace.')
output logAnalyticsWorkspaceId string = logAnalyticsWorkspace.properties.customerId

@description('The name of the storage account.')
output storageAccountName string = storageAccount.name

@description('The Application Insights connection string.')
output appInsightsConnectionString string = appInsights.properties.ConnectionString

@description('The name of the Action Group for alerts.')
output actionGroupName string = actionGroup.name

@description('The Event Grid subscription name.')
output eventGridSubscriptionName string = eventGridSubscription.name