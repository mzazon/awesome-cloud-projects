// ==============================================================================
// Bicep Template: Simple Container App Deployment with Azure Container Apps
// Description: Deploy a serverless container application with automatic scaling
// ==============================================================================

@description('Location for all resources')
param location string = resourceGroup().location

@description('Base name for all resources (will be suffixed with unique string)')
param baseName string = 'containerapp-demo'

@description('Environment for deployment (dev, test, prod)')
@allowed(['dev', 'test', 'prod'])
param environment string = 'dev'

@description('Container image to deploy')
param containerImage string = 'mcr.microsoft.com/k8se/quickstart:latest'

@description('Container port')
param containerPort int = 80

@description('Enable external ingress')
param enableExternalIngress bool = true

@description('Minimum number of replicas')
@minValue(0)
@maxValue(25)
param minReplicas int = 0

@description('Maximum number of replicas')
@minValue(1)
@maxValue(25)
param maxReplicas int = 5

@description('CPU allocation per container (in cores)')
@allowed(['0.25', '0.5', '0.75', '1.0', '1.25', '1.5', '1.75', '2.0'])
param cpuAllocation string = '0.25'

@description('Memory allocation per container (in Gi)')
@allowed(['0.5Gi', '1.0Gi', '1.5Gi', '2.0Gi', '2.5Gi', '3.0Gi', '3.5Gi', '4.0Gi'])
param memoryAllocation string = '0.5Gi'

@description('Tags to apply to all resources')
param tags object = {
  environment: environment
  purpose: 'recipe-demo'
  'managed-by': 'bicep'
}

// ==============================================================================
// Variables
// ==============================================================================

var uniqueSuffix = substring(uniqueString(resourceGroup().id), 0, 6)
var containerAppsEnvironmentName = '${baseName}-env-${uniqueSuffix}'
var containerAppName = '${baseName}-app-${uniqueSuffix}'
var logAnalyticsWorkspaceName = '${baseName}-logs-${uniqueSuffix}'

// ==============================================================================
// Log Analytics Workspace
// ==============================================================================

resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: logAnalyticsWorkspaceName
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
    features: {
      searchVersion: 1
      legacy: 0
      enableLogAccessUsingOnlyResourcePermissions: true
    }
  }
}

// ==============================================================================
// Container Apps Environment
// ==============================================================================

resource containerAppsEnvironment 'Microsoft.App/managedEnvironments@2024-03-01' = {
  name: containerAppsEnvironmentName
  location: location
  tags: tags
  properties: {
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: logAnalyticsWorkspace.properties.customerId
        sharedKey: logAnalyticsWorkspace.listKeys().primarySharedKey
      }
    }
    zoneRedundant: false
  }
}

// ==============================================================================
// Container App
// ==============================================================================

resource containerApp 'Microsoft.App/containerApps@2024-03-01' = {
  name: containerAppName
  location: location
  tags: tags
  properties: {
    managedEnvironmentId: containerAppsEnvironment.id
    configuration: {
      ingress: enableExternalIngress ? {
        external: true
        targetPort: containerPort
        allowInsecure: false
        traffic: [
          {
            latestRevision: true
            weight: 100
          }
        ]
        corsPolicy: {
          allowedOrigins: ['*']
          allowedMethods: ['GET', 'POST']
          allowedHeaders: ['*']
        }
      } : null
      secrets: []
      activeRevisionsMode: 'Single'
    }
    template: {
      revisionSuffix: 'initial'
      containers: [
        {
          name: 'main-container'
          image: containerImage
          resources: {
            cpu: json(cpuAllocation)
            memory: memoryAllocation
          }
          probes: [
            {
              type: 'Liveness'
              httpGet: {
                path: '/'
                port: containerPort
                scheme: 'HTTP'
              }
              initialDelaySeconds: 30
              periodSeconds: 10
              timeoutSeconds: 5
              failureThreshold: 3
              successThreshold: 1
            }
            {
              type: 'Readiness'
              httpGet: {
                path: '/'
                port: containerPort
                scheme: 'HTTP'
              }
              initialDelaySeconds: 5
              periodSeconds: 5
              timeoutSeconds: 3
              failureThreshold: 3
              successThreshold: 1
            }
          ]
        }
      ]
      scale: {
        minReplicas: minReplicas
        maxReplicas: maxReplicas
        rules: [
          {
            name: 'http-scaling'
            http: {
              metadata: {
                concurrentRequests: '50'
              }
            }
          }
        ]
      }
    }
  }
}

// ==============================================================================
// Outputs
// ==============================================================================

@description('The name of the Container Apps environment')
output containerAppsEnvironmentName string = containerAppsEnvironment.name

@description('The resource ID of the Container Apps environment')
output containerAppsEnvironmentId string = containerAppsEnvironment.id

@description('The name of the Container App')
output containerAppName string = containerApp.name

@description('The resource ID of the Container App')
output containerAppId string = containerApp.id

@description('The application URL (if external ingress is enabled)')
output applicationUrl string = enableExternalIngress ? 'https://${containerApp.properties.configuration.ingress.fqdn}' : 'External ingress not enabled'

@description('The FQDN of the Container App (if external ingress is enabled)')
output fqdn string = enableExternalIngress ? containerApp.properties.configuration.ingress.fqdn : 'External ingress not enabled'

@description('The latest revision name')
output latestRevisionName string = containerApp.properties.latestRevisionName

@description('The provisioning state of the Container App')
output provisioningState string = containerApp.properties.provisioningState

@description('The Log Analytics Workspace name')
output logAnalyticsWorkspaceName string = logAnalyticsWorkspace.name

@description('The Log Analytics Workspace ID')
output logAnalyticsWorkspaceId string = logAnalyticsWorkspace.id

@description('Resource group location')
output location string = location

@description('Resource tags applied')
output appliedTags object = tags