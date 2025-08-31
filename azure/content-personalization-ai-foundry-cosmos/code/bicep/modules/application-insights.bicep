@description('Application Insights module for application monitoring')

// Parameters
@description('Name of the Application Insights component')
param applicationInsightsName string

@description('Azure region for resource deployment')
param location string

@description('Resource ID of the Log Analytics workspace')
param logAnalyticsWorkspaceId string

@description('Tags to apply to the resource')
param tags object = {}

@description('Application type for Application Insights')
@allowed(['web', 'other'])
param applicationType string = 'web'

@description('Ingestion mode for data collection')
@allowed(['ApplicationInsights', 'ApplicationInsightsWithDiagnosticSettings', 'LogAnalytics'])
param ingestionMode string = 'LogAnalytics'

// Resources
resource applicationInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: applicationInsightsName
  location: location
  tags: tags
  kind: 'web'
  properties: {
    Application_Type: applicationType
    WorkspaceResourceId: logAnalyticsWorkspaceId
    IngestionMode: ingestionMode
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
    DisableIpMasking: false
    DisableLocalAuth: false
  }
}

// Outputs
@description('Application Insights Resource ID')
output applicationInsightsId string = applicationInsights.id

@description('Application Insights Name')
output applicationInsightsName string = applicationInsights.name

@description('Application Insights Instrumentation Key')
@secure()
output instrumentationKey string = applicationInsights.properties.InstrumentationKey

@description('Application Insights Connection String')
@secure()
output connectionString string = applicationInsights.properties.ConnectionString

@description('Application Insights App ID')
output appId string = applicationInsights.properties.AppId