@description('Log Analytics Workspace module for monitoring and logging')

// Parameters
@description('Name of the Log Analytics workspace')
param workspaceName string

@description('Azure region for resource deployment')
param location string

@description('Tags to apply to the resource')
param tags object = {}

@description('SKU for the Log Analytics workspace')
@allowed(['Free', 'Standalone', 'PerNode', 'PerGB2018'])
param sku string = 'PerGB2018'

@description('Data retention period in days')
@minValue(30)
@maxValue(730)
param retentionInDays int = 30

// Resources
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: workspaceName
  location: location
  tags: tags
  properties: {
    sku: {
      name: sku
    }
    retentionInDays: retentionInDays
    features: {
      enableLogAccessUsingOnlyResourcePermissions: true
    }
    workspaceCapping: {
      dailyQuotaGb: -1
    }
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

// Outputs
@description('Log Analytics Workspace Resource ID')
output workspaceId string = logAnalyticsWorkspace.id

@description('Log Analytics Workspace Name')
output workspaceName string = logAnalyticsWorkspace.name

@description('Log Analytics Workspace Customer ID')
output customerId string = logAnalyticsWorkspace.properties.customerId

@description('Log Analytics Workspace Primary Shared Key')
@secure()
output primarySharedKey string = logAnalyticsWorkspace.listKeys().primarySharedKey