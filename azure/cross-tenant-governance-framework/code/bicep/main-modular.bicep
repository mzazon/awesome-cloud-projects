// ==============================================================================
// Azure Lighthouse and Azure Automanage Cross-Tenant Governance (Modular)
// ==============================================================================
// This Bicep template deploys the infrastructure needed for cross-tenant
// resource governance using Azure Lighthouse and Azure Automanage with
// a modular approach.
// ==============================================================================

targetScope = 'resourceGroup'

@description('The tenant ID of the MSP (Managed Service Provider)')
param mspTenantId string

@description('The name of the MSP offer for Lighthouse delegation')
param mspOfferName string = 'Cross-Tenant Resource Governance'

@description('Description of the MSP offer')
param mspOfferDescription string = 'Managed services for automated VM configuration, patching, and compliance monitoring'

@description('Array of authorization objects for Lighthouse delegation')
param authorizations array

@description('Location for all resources')
param location string = resourceGroup().location

@description('Name of the Log Analytics workspace')
param logAnalyticsWorkspaceName string

@description('SKU for the Log Analytics workspace')
@allowed([
  'CapacityReservation'
  'Free'
  'LACluster'
  'PerGB2018'
  'PerNode'
  'Premium'
  'Standalone'
  'Standard'
])
param logAnalyticsWorkspaceSku string = 'PerGB2018'

@description('Name of the Automanage configuration profile')
param automanageProfileName string

@description('Name of the action group for alerting')
param actionGroupName string

@description('Email address for alert notifications')
param alertEmailAddress string

@description('Tags to apply to all resources')
param tags object = {
  purpose: 'lighthouse-governance'
  environment: 'production'
  managedBy: 'msp'
}

@description('Enable antimalware protection in Automanage')
param enableAntimalware bool = true

@description('Enable Azure Security Center integration in Automanage')
param enableSecurityCenter bool = true

@description('Enable backup services in Automanage')
param enableBackup bool = true

@description('Enable boot diagnostics in Automanage')
param enableBootDiagnostics bool = true

@description('Enable change tracking and inventory in Automanage')
param enableChangeTracking bool = true

@description('Enable guest configuration in Automanage')
param enableGuestConfiguration bool = true

@description('Enable update management in Automanage')
param enableUpdateManagement bool = true

@description('Enable VM insights in Automanage')
param enableVMInsights bool = true

// ==============================================================================
// Monitoring Module
// ==============================================================================

module monitoring 'modules/monitoring.bicep' = {
  name: 'monitoring-deployment'
  params: {
    location: location
    logAnalyticsWorkspaceName: logAnalyticsWorkspaceName
    logAnalyticsWorkspaceSku: logAnalyticsWorkspaceSku
    actionGroupName: actionGroupName
    alertEmailAddress: alertEmailAddress
    tags: tags
  }
}

// ==============================================================================
// Automanage Module
// ==============================================================================

module automanage 'modules/automanage.bicep' = {
  name: 'automanage-deployment'
  params: {
    location: location
    automanageProfileName: automanageProfileName
    logAnalyticsWorkspaceId: monitoring.outputs.logAnalyticsWorkspaceId
    tags: tags
    enableAntimalware: enableAntimalware
    enableSecurityCenter: enableSecurityCenter
    enableBackup: enableBackup
    enableBootDiagnostics: enableBootDiagnostics
    enableChangeTracking: enableChangeTracking
    enableGuestConfiguration: enableGuestConfiguration
    enableUpdateManagement: enableUpdateManagement
    enableVMInsights: enableVMInsights
  }
}

// ==============================================================================
// Lighthouse Module
// ==============================================================================

module lighthouse 'modules/lighthouse.bicep' = {
  name: 'lighthouse-deployment'
  params: {
    mspTenantId: mspTenantId
    mspOfferName: mspOfferName
    mspOfferDescription: mspOfferDescription
    authorizations: authorizations
    tags: tags
  }
}

// ==============================================================================
// Azure Workbook for Cross-Tenant Monitoring
// ==============================================================================

resource monitoringWorkbook 'Microsoft.Insights/workbooks@2023-06-01' = {
  name: guid('lighthouse-cross-tenant-monitoring')
  location: location
  tags: tags
  kind: 'shared'
  properties: {
    displayName: 'Lighthouse Cross-Tenant Monitoring'
    serializedData: loadTextContent('workbook-template.json')
    category: 'workbook'
    sourceId: monitoring.outputs.logAnalyticsWorkspaceId
  }
}

// ==============================================================================
// Outputs
// ==============================================================================

@description('The resource ID of the Log Analytics workspace')
output logAnalyticsWorkspaceId string = monitoring.outputs.logAnalyticsWorkspaceId

@description('The Log Analytics workspace name')
output logAnalyticsWorkspaceName string = monitoring.outputs.logAnalyticsWorkspaceName

@description('The Log Analytics workspace customer ID')
output logAnalyticsWorkspaceCustomerId string = monitoring.outputs.logAnalyticsWorkspaceCustomerId

@description('The resource ID of the Automanage configuration profile')
output automanageProfileId string = automanage.outputs.automanageProfileId

@description('The resource ID of the Automanage best practices profile')
output automanageBestPracticesProfileId string = automanage.outputs.automanageBestPracticesProfileId

@description('The Automanage profile name')
output automanageProfileName string = automanage.outputs.automanageProfileName

@description('The resource ID of the Lighthouse registration definition')
output lighthouseRegistrationDefinitionId string = lighthouse.outputs.registrationDefinitionId

@description('The resource ID of the Lighthouse registration assignment')
output lighthouseRegistrationAssignmentId string = lighthouse.outputs.registrationAssignmentId

@description('The MSP registration name for reference')
output mspRegistrationName string = lighthouse.outputs.mspRegistrationName

@description('The MSP assignment name for reference')
output mspAssignmentName string = lighthouse.outputs.mspAssignmentName

@description('The resource ID of the action group')
output actionGroupId string = monitoring.outputs.actionGroupId

@description('The resource ID of the data collection rule')
output dataCollectionRuleId string = monitoring.outputs.dataCollectionRuleId

@description('The resource ID of the monitoring workbook')
output monitoringWorkbookId string = monitoringWorkbook.id

@description('Deployment summary')
output deploymentSummary object = {
  lighthouseRegistrationName: lighthouse.outputs.mspRegistrationName
  automanageProfileName: automanage.outputs.automanageProfileName
  logAnalyticsWorkspaceName: monitoring.outputs.logAnalyticsWorkspaceName
  actionGroupName: actionGroupName
  monitoringWorkbookName: monitoringWorkbook.properties.displayName
  status: 'Deployed Successfully'
}