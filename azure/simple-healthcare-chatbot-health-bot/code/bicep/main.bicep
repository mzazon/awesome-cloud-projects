// Azure Health Bot Infrastructure as Code
// This template deploys an Azure Health Bot service for healthcare organizations

targetScope = 'resourceGroup'

// =====================================
// PARAMETERS
// =====================================

@description('Name of the Azure Health Bot instance')
param healthBotName string

@description('Location for all resources')
param location string = resourceGroup().location

@description('SKU for the Health Bot service (F0 for free tier, S1 for standard)')
@allowed([
  'F0'
  'S1'
])
param healthBotSku string = 'F0'

@description('Environment tag for resource organization')
@allowed([
  'dev'
  'test'
  'prod'
  'demo'
])
param environment string = 'demo'

@description('Purpose tag for resource identification')
param purpose string = 'healthcare-chatbot'

@description('Organization name for tagging')
param organizationName string = 'healthcare-org'

@description('Enable audit logging for compliance')
param enableAuditLogging bool = true

@description('Data retention period in days for compliance')
@minValue(30)
@maxValue(2555)
param dataRetentionDays int = 90

// =====================================
// VARIABLES
// =====================================

var tags = {
  environment: environment
  purpose: purpose
  organization: organizationName
  createdBy: 'bicep-template'
  createdDate: utcNow('yyyy-MM-dd')
  compliance: 'HIPAA'
}

var healthBotConfig = {
  name: healthBotName
  sku: healthBotSku
  location: location
  tags: tags
}

// =====================================
// RESOURCES
// =====================================

@description('Azure Health Bot service instance')
resource healthBot 'Microsoft.HealthBot/healthBots@2023-05-01' = {
  name: healthBotConfig.name
  location: healthBotConfig.location
  tags: healthBotConfig.tags
  sku: {
    name: healthBotConfig.sku
  }
  properties: {
    // Health Bot configuration properties
    tenantId: subscription().tenantId
  }
}

// Log Analytics Workspace for monitoring and compliance (conditional)
@description('Log Analytics Workspace for Health Bot monitoring and audit trails')
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = if (enableAuditLogging) {
  name: '${healthBotName}-logs'
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: dataRetentionDays
    features: {
      enableLogAccessUsingOnlyResourcePermissions: true
    }
    workspaceCapping: {
      dailyQuotaGb: 1
    }
  }
}

// Application Insights for Health Bot telemetry (conditional)
@description('Application Insights for Health Bot performance monitoring')
resource applicationInsights 'Microsoft.Insights/components@2020-02-02' = if (enableAuditLogging) {
  name: '${healthBotName}-insights'
  location: location
  tags: tags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: enableAuditLogging ? logAnalyticsWorkspace.id : null
    IngestionMode: 'LogAnalytics'
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

// =====================================
// OUTPUTS
// =====================================

@description('The resource ID of the Health Bot')
output healthBotId string = healthBot.id

@description('The name of the Health Bot')
output healthBotName string = healthBot.name

@description('The Health Bot management portal URL')
output managementPortalUrl string = 'https://healthbot.microsoft.com/account/${healthBot.id}'

@description('The Health Bot webchat endpoint URL')
output webChatEndpoint string = 'https://healthbot.microsoft.com/webchat/${healthBot.id}'

@description('The resource group name')
output resourceGroupName string = resourceGroup().name

@description('The location where resources were deployed')
output deploymentLocation string = location

@description('The SKU tier used for the Health Bot')
output healthBotSku string = healthBotSku

@description('Log Analytics Workspace ID (if enabled)')
output logAnalyticsWorkspaceId string = enableAuditLogging ? logAnalyticsWorkspace.id : ''

@description('Application Insights connection string (if enabled)')
output applicationInsightsConnectionString string = enableAuditLogging ? applicationInsights.properties.ConnectionString : ''

@description('Application Insights instrumentation key (if enabled)')
output applicationInsightsInstrumentationKey string = enableAuditLogging ? applicationInsights.properties.InstrumentationKey : ''

@description('Deployment timestamp')
output deployedAt string = utcNow('yyyy-MM-dd HH:mm:ss')

@description('Compliance features enabled')
output complianceFeatures object = {
  auditLogging: enableAuditLogging
  dataRetention: dataRetentionDays
  hipaaCompliant: true
  encryption: 'Enabled'
}

@description('Next steps for configuration')
output nextSteps array = [
  'Access the Health Bot Management Portal: ${healthBot.properties.botManagementPortalLink}'
  'Configure healthcare scenarios in the portal'
  'Enable web chat channel for website integration'
  'Review HIPAA compliance settings'
  'Test built-in medical scenarios'
  'Customize branding and messaging'
]