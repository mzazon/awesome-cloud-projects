@description('The Azure region where all resources will be deployed')
param location string = resourceGroup().location

@description('Environment name (e.g., dev, test, prod)')
@allowed([
  'dev'
  'test'
  'prod'
])
param environment string = 'dev'

@description('Unique suffix for resource names to ensure global uniqueness')
param uniqueSuffix string = uniqueString(resourceGroup().id)

@description('Tags to be applied to all resources')
param tags object = {
  purpose: 'monitoring'
  environment: environment
  solution: 'resource-monitoring-dashboard'
}

@description('Log Analytics workspace retention in days')
@minValue(30)
@maxValue(730)
param logAnalyticsRetentionDays int = 30

@description('Log Analytics workspace pricing tier')
@allowed([
  'PerGB2018'
  'Free'
  'Standalone'
])
param logAnalyticsSku string = 'PerGB2018'

@description('Storage account SKU')
@allowed([
  'Standard_LRS'
  'Standard_GRS'
  'Standard_RAGRS'
])
param storageAccountSku string = 'Standard_LRS'

@description('App Service plan SKU')
@allowed([
  'F1'
  'D1'
  'B1'
  'B2'
  'B3'
  'S1'
  'S2'
  'S3'
])
param appServicePlanSku string = 'F1'

// Variables for resource names
var logAnalyticsWorkspaceName = 'log-workspace-${uniqueSuffix}'
var storageAccountName = 'stor${uniqueSuffix}'
var appServicePlanName = 'asp-monitoring-${uniqueSuffix}'
var webAppName = 'webapp-monitoring-${uniqueSuffix}'
var workbookName = 'Resource Monitoring Dashboard - ${uniqueSuffix}'
var applicationInsightsName = 'ai-monitoring-${uniqueSuffix}'

// Log Analytics Workspace
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: logAnalyticsWorkspaceName
  location: location
  tags: tags
  properties: {
    sku: {
      name: logAnalyticsSku
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

// Storage Account for monitoring demonstration
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: storageAccountName
  location: location
  tags: tags
  sku: {
    name: storageAccountSku
  }
  kind: 'StorageV2'
  properties: {
    defaultToOAuthAuthentication: false
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

// Diagnostic settings for Storage Account
resource storageAccountDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  scope: storageAccount
  name: 'storage-diagnostics'
  properties: {
    workspaceId: logAnalyticsWorkspace.id
    metrics: [
      {
        category: 'Transaction'
        enabled: true
        retentionPolicy: {
          enabled: false
          days: 0
        }
      }
    ]
  }
}

// App Service Plan
resource appServicePlan 'Microsoft.Web/serverfarms@2023-01-01' = {
  name: appServicePlanName
  location: location
  tags: tags
  sku: {
    name: appServicePlanSku
    tier: appServicePlanSku == 'F1' ? 'Free' : 'Basic'
    size: appServicePlanSku
    family: appServicePlanSku == 'F1' ? 'F' : 'B'
    capacity: 1
  }
  kind: 'app'
  properties: {
    perSiteScaling: false
    elasticScaleEnabled: false
    maximumElasticWorkerCount: 1
    isSpot: false
    reserved: false
    isXenon: false
    hyperV: false
    targetWorkerCount: 0
    targetWorkerSizeId: 0
    zoneRedundant: false
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

// Web App
resource webApp 'Microsoft.Web/sites@2023-01-01' = {
  name: webAppName
  location: location
  tags: tags
  kind: 'app'
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
    reserved: false
    isXenon: false
    hyperV: false
    vnetRouteAllEnabled: false
    vnetImagePullEnabled: false
    vnetContentShareEnabled: false
    siteConfig: {
      numberOfWorkers: 1
      acrUseManagedIdentityCreds: false
      alwaysOn: false
      http20Enabled: false
      functionAppScaleLimit: 0
      minimumElasticInstanceCount: 0
      appSettings: [
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
          value: '~2'
        }
      ]
      ftpsState: 'FtpsOnly'
      minTlsVersion: '1.2'
    }
    scmSiteAlsoStopped: false
    clientAffinityEnabled: true
    clientCertEnabled: false
    clientCertMode: 'Required'
    hostNamesDisabled: false
    containerSize: 0
    dailyMemoryTimeQuota: 0
    httpsOnly: true
    redundancyMode: 'None'
    storageAccountRequired: false
    keyVaultReferenceIdentity: 'SystemAssigned'
  }
}

// Diagnostic settings for Web App
resource webAppDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  scope: webApp
  name: 'webapp-diagnostics'
  properties: {
    workspaceId: logAnalyticsWorkspace.id
    logs: [
      {
        category: 'AppServiceHTTPLogs'
        enabled: true
        retentionPolicy: {
          enabled: false
          days: 0
        }
      }
      {
        category: 'AppServiceConsoleLogs'
        enabled: true
        retentionPolicy: {
          enabled: false
          days: 0
        }
      }
      {
        category: 'AppServiceAppLogs'
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

// Azure Monitor Workbook
resource monitoringWorkbook 'Microsoft.Insights/workbooks@2023-06-01' = {
  name: guid(resourceGroup().id, 'monitoring-workbook')
  location: location
  tags: tags
  kind: 'shared'
  properties: {
    displayName: workbookName
    description: 'Custom dashboard for monitoring resource health, performance, and costs'
    category: 'workbook'
    sourceId: resourceGroup().id
    serializedData: string({
      version: 'Notebook/1.0'
      items: [
        {
          type: 1
          content: {
            json: '# Resource Monitoring Dashboard\n\nThis workbook provides comprehensive monitoring for Azure resources including health status, performance metrics, and cost analysis.'
          }
          name: 'title-text'
        }
        {
          type: 9
          content: {
            version: 'KqlParameterItem/1.0'
            parameters: [
              {
                id: 'time-range-param'
                version: 'KqlParameterItem/1.0'
                name: 'TimeRange'
                type: 4
                isRequired: true
                value: {
                  durationMs: 86400000
                }
                typeSettings: {
                  selectableValues: [
                    {
                      durationMs: 3600000
                    }
                    {
                      durationMs: 14400000
                    }
                    {
                      durationMs: 43200000
                    }
                    {
                      durationMs: 86400000
                    }
                    {
                      durationMs: 172800000
                    }
                    {
                      durationMs: 259200000
                    }
                    {
                      durationMs: 604800000
                    }
                  ]
                  allowCustom: true
                }
                timeContext: {
                  durationMs: 86400000
                }
              }
              {
                id: 'resource-group-param'
                version: 'KqlParameterItem/1.0'
                name: 'ResourceGroup'
                type: 5
                isRequired: true
                value: resourceGroup().name
                typeSettings: {
                  additionalResourceOptions: [
                    'value::1'
                  ]
                  showDefault: false
                }
                timeContext: {
                  durationMs: 86400000
                }
              }
            ]
            style: 'pills'
            queryType: 0
            resourceType: 'microsoft.operationalinsights/workspaces'
          }
          name: 'parameters'
        }
        {
          type: 1
          content: {
            json: '## Resource Health Overview'
          }
          name: 'health-title'
        }
        {
          type: 3
          content: {
            version: 'KqlItem/1.0'
            query: 'AzureActivity\n| where TimeGenerated >= {TimeRange:start}\n| where ResourceGroup =~ "{ResourceGroup}"\n| where ActivityStatusValue in ("Success", "Failed", "Warning")\n| summarize \n    SuccessfulOperations = countif(ActivityStatusValue == "Success"),\n    FailedOperations = countif(ActivityStatusValue == "Failed"),\n    WarningOperations = countif(ActivityStatusValue == "Warning"),\n    TotalOperations = count()\n| extend HealthPercentage = round((SuccessfulOperations * 100.0) / TotalOperations, 1)\n| project SuccessfulOperations, FailedOperations, WarningOperations, TotalOperations, HealthPercentage'
            size: 3
            title: 'Resource Health Status'
            timeContext: {
              durationMs: 86400000
            }
            timeContextFromParameter: 'TimeRange'
            queryType: 0
            resourceType: 'microsoft.operationalinsights/workspaces'
            visualization: 'tiles'
            tileSettings: {
              titleContent: {
                columnMatch: 'HealthPercentage'
                formatter: 1
                formatOptions: {
                  showIcon: true
                }
              }
              leftContent: {
                columnMatch: 'HealthPercentage'
                formatter: 12
                formatOptions: {
                  palette: 'greenRed'
                  showIcon: true
                }
                numberFormat: {
                  unit: 1
                  options: {
                    style: 'decimal'
                    maximumFractionDigits: 1
                  }
                }
              }
              secondaryContent: {
                columnMatch: 'TotalOperations'
                formatter: 1
              }
              showBorder: false
            }
            graphSettings: {
              type: 0
            }
          }
          name: 'health-overview'
        }
        {
          type: 1
          content: {
            json: '## Performance Metrics'
          }
          name: 'performance-title'
        }
        {
          type: 10
          content: {
            chartId: 'workbook-chart-1'
            version: 'MetricsItem/2.0'
            size: 0
            chartType: 2
            resourceIds: [
              storageAccount.id
              webApp.id
            ]
            timeContext: {
              durationMs: 86400000
            }
            timeContextFromParameter: 'TimeRange'
            metrics: [
              {
                namespace: 'microsoft.storage/storageaccounts'
                metric: 'microsoft.storage/storageaccounts--Transactions'
                aggregation: 1
                splitBy: null
              }
              {
                namespace: 'microsoft.web/sites'
                metric: 'microsoft.web/sites--Requests'
                aggregation: 1
                splitBy: null
              }
            ]
            title: 'Resource Performance Metrics'
            gridSettings: {
              rowLimit: 10000
            }
          }
          name: 'performance-metrics'
        }
        {
          type: 1
          content: {
            json: '## Cost Analysis'
          }
          name: 'cost-title'
        }
        {
          type: 3
          content: {
            version: 'KqlItem/1.0'
            query: 'Resources\n| where subscriptionId =~ "{subscription().subscriptionId}"\n| where resourceGroup =~ "{ResourceGroup}"\n| project name, type, location, resourceGroup\n| extend EstimatedMonthlyCost = case(\n    type contains "Microsoft.Storage/storageAccounts", 5.0,\n    type contains "Microsoft.Web/sites", 10.0,\n    type contains "Microsoft.Web/serverfarms", 15.0,\n    type contains "Microsoft.OperationalInsights/workspaces", 20.0,\n    type contains "Microsoft.Insights/components", 5.0,\n    1.0)\n| order by EstimatedMonthlyCost desc'
            size: 0
            title: 'Resource Cost Estimates (USD/Month)'
            timeContext: {
              durationMs: 86400000
            }
            timeContextFromParameter: 'TimeRange'
            queryType: 1
            resourceType: 'microsoft.resourcegraph/resources'
            visualization: 'table'
            gridSettings: {
              formatters: [
                {
                  columnMatch: 'EstimatedMonthlyCost'
                  formatter: 0
                  numberFormat: {
                    unit: 0
                    options: {
                      style: 'currency'
                      currency: 'USD'
                    }
                  }
                }
              ]
              rowLimit: 1000
              filter: true
              sortBy: [
                {
                  itemKey: 'EstimatedMonthlyCost'
                  sortOrder: 2
                }
              ]
            }
            sortBy: [
              {
                itemKey: 'EstimatedMonthlyCost'
                sortOrder: 2
              }
            ]
          }
          name: 'cost-analysis'
        }
      ]
      styleSettings: {}
      $schema: 'https://github.com/Microsoft/Application-Insights-Workbooks/blob/master/schema/workbook.json'
    })
  }
}

// Outputs
@description('The resource ID of the Log Analytics workspace')
output logAnalyticsWorkspaceId string = logAnalyticsWorkspace.id

@description('The name of the Log Analytics workspace')
output logAnalyticsWorkspaceName string = logAnalyticsWorkspace.name

@description('The resource ID of the storage account')
output storageAccountId string = storageAccount.id

@description('The name of the storage account')
output storageAccountName string = storageAccount.name

@description('The resource ID of the web app')
output webAppId string = webApp.id

@description('The URL of the web app')
output webAppUrl string = 'https://${webApp.properties.defaultHostName}'

@description('The resource ID of the Application Insights component')
output applicationInsightsId string = applicationInsights.id

@description('The instrumentation key for Application Insights')
output applicationInsightsInstrumentationKey string = applicationInsights.properties.InstrumentationKey

@description('The connection string for Application Insights')
output applicationInsightsConnectionString string = applicationInsights.properties.ConnectionString

@description('The resource ID of the monitoring workbook')
output workbookId string = monitoringWorkbook.id

@description('The name of the monitoring workbook')
output workbookName string = monitoringWorkbook.properties.displayName

@description('Resource group location')
output location string = location

@description('Environment name')
output environment string = environment

@description('Unique suffix used for resource names')
output uniqueSuffix string = uniqueSuffix