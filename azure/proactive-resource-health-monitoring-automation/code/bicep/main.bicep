@description('Main Bicep template for Proactive Resource Health Monitoring with Service Bus')

// Parameters
@description('The Azure region where resources will be deployed')
param location string = resourceGroup().location

@description('Environment name (dev, test, prod)')
@allowed(['dev', 'test', 'prod'])
param environment string = 'dev'

@description('Unique suffix for resource names (3-8 characters)')
@minLength(3)
@maxLength(8)
param uniqueSuffix string = uniqueString(resourceGroup().id)

@description('Tags to apply to all resources')
param tags object = {
  purpose: 'health-monitoring'
  environment: environment
  recipe: 'orchestrating-proactive-application-health-monitoring'
}

@description('Service Bus SKU tier')
@allowed(['Basic', 'Standard', 'Premium'])
param serviceBusSku string = 'Standard'

@description('Enable duplicate detection for Service Bus queues and topics')
param enableDuplicateDetection bool = true

@description('Maximum message size in MB for Service Bus')
@allowed([1, 2, 3, 4, 5])
param maxMessageSizeInMegabytes int = 1

@description('Deploy sample VM for health monitoring demonstration')
param deploySampleVm bool = true

@description('VM admin username')
param vmAdminUsername string = 'azureuser'

@description('VM admin password or SSH key')
@secure()
param vmAdminPassword string

@description('VM size for the demo VM')
param vmSize string = 'Standard_B1s'

// Variables
var serviceBusNamespace = 'sb-health-monitoring-${uniqueSuffix}'
var healthQueueName = 'health-events'
var remediationTopicName = 'remediation-actions'
var logicAppName = 'la-health-orchestrator-${uniqueSuffix}'
var logAnalyticsWorkspace = 'log-health-monitoring-${uniqueSuffix}'
var actionGroupName = 'ag-health-alerts-${uniqueSuffix}'
var restartHandlerLogicApp = 'la-restart-handler-${uniqueSuffix}'
var scaleHandlerLogicApp = 'la-scale-handler-${uniqueSuffix}'
var demoVmName = 'vm-health-demo-${uniqueSuffix}'

// Modules
module serviceBus 'modules/serviceBus.bicep' = {
  name: 'serviceBusDeployment'
  params: {
    namespaceName: serviceBusNamespace
    location: location
    tags: tags
    skuTier: serviceBusSku
    healthQueueName: healthQueueName
    remediationTopicName: remediationTopicName
    enableDuplicateDetection: enableDuplicateDetection
    maxMessageSizeInMegabytes: maxMessageSizeInMegabytes
  }
}

module logAnalytics 'modules/logAnalytics.bicep' = {
  name: 'logAnalyticsDeployment'
  params: {
    workspaceName: logAnalyticsWorkspace
    location: location
    tags: tags
  }
}

module logicApps 'modules/logicApps.bicep' = {
  name: 'logicAppsDeployment'
  params: {
    orchestratorName: logicAppName
    restartHandlerName: restartHandlerLogicApp
    scaleHandlerName: scaleHandlerLogicApp
    location: location
    tags: tags
    serviceBusConnectionString: serviceBus.outputs.connectionString
    healthQueueName: healthQueueName
    remediationTopicName: remediationTopicName
  }
  dependsOn: [
    serviceBus
  ]
}

module monitoring 'modules/monitoring.bicep' = {
  name: 'monitoringDeployment'
  params: {
    actionGroupName: actionGroupName
    location: location
    tags: tags
    logicAppTriggerUrl: logicApps.outputs.orchestratorTriggerUrl
    workspaceId: logAnalytics.outputs.workspaceId
  }
  dependsOn: [
    logicApps
    logAnalytics
  ]
}

module demoVm 'modules/virtualMachine.bicep' = if (deploySampleVm) {
  name: 'demoVmDeployment'
  params: {
    vmName: demoVmName
    location: location
    tags: tags
    adminUsername: vmAdminUsername
    adminPassword: vmAdminPassword
    vmSize: vmSize
    actionGroupId: monitoring.outputs.actionGroupId
  }
  dependsOn: [
    monitoring
  ]
}

// Outputs
@description('Service Bus namespace name')
output serviceBusNamespaceName string = serviceBus.outputs.namespaceName

@description('Service Bus connection string (sensitive)')
@secure()
output serviceBusConnectionString string = serviceBus.outputs.connectionString

@description('Logic Apps orchestrator trigger URL (sensitive)')
@secure()
output logicAppTriggerUrl string = logicApps.outputs.orchestratorTriggerUrl

@description('Log Analytics workspace ID')
output logAnalyticsWorkspaceId string = logAnalytics.outputs.workspaceId

@description('Action Group resource ID')
output actionGroupId string = monitoring.outputs.actionGroupId

@description('Demo VM resource ID (if deployed)')
output demoVmId string = deploySampleVm ? demoVm.outputs.vmId : ''

@description('Health monitoring endpoint for testing')
output healthMonitoringEndpoint string = logicApps.outputs.orchestratorTriggerUrl

@description('Resource group location')
output deploymentLocation string = location

@description('Deployment environment')
output deploymentEnvironment string = environment